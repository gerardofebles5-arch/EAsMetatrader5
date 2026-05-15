//+------------------------------------------------------------------+
//|                                      PeakRangeHedging_v1.1.mq5  |
//|                    Range Hedging EA - v1.1 Optimized             |
//|                                                                  |
//|  MEJORAS v1.1 vs v1.0:                                           |
//|  1. CONFIRMACION DOBLE: Ichimoku AND Stochastic (antes OR)       |
//|     → Elimina señales falsas que causaban SL en segundos         |
//|  2. MIN BARS COOLDOWN: bloqueo de N barras entre trades          |
//|     → Evita re-entradas inmediatas tras SL                       |
//|  3. VOLATILITY FILTER: ATR mínimo/máximo para filtrar mercados   |
//|     muy volátiles o sin movimiento (XAUUSD M1 sensible)          |
//|  4. SPREAD FILTER: no operar con spread > umbral configurable    |
//|  5. CANDLE CONFIRMATION: vela de confirmación antes de entrar    |
//|     → Entry solo si la vela anterior cierra a favor de la señal  |
//|  6. SESSION QUALITY: filtro de hora pico de liquidez             |
//|  7. MAX CONSECUTIVE LOSSES: pausa tras N pérdidas seguidas       |
//|  8. PARTIAL CLOSE: cierre parcial en 50% del recorrido al TP     |
//|  9. SIGNAL MODE: configurable AND/OR entre Ichimoku y Stochastic |
//| 10. Dashboard mejorado con streak, ATR, spread en tiempo real    |
//+------------------------------------------------------------------+
#property copyright "Peak Range Hedging EA v1.1"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// ── Step 1: Range Hedging Setup ──────────────────────────────────
input group "=== STEP 1: PRIMARY ORDER SETTINGS ==="
input int      MaxOrders           = 20;       // Max total orders (primary + hedge)
input double   RiskPerOrder        = 0.5;      // Risk per primary order (%)
input double   ATR_SL_Coef         = 1.5;      // ATR multiplier for Stop Loss
input double   RR_Ratio            = 1.5;      // Risk/Reward ratio (TP = SL x Coef)
input double   TrailingStopPct     = 50.0;     // Trailing stop activation (% of TP distance)

input group "=== STEP 1: HEDGE ORDER SETTINGS ==="
input double   HedgeRiskPerOrder   = 0.125;    // Risk per hedge order (%)
input double   HedgeATR_SL_Coef    = 1.5;      // ATR multiplier for Hedge SL
input double   HedgeRR_Ratio       = 1.5;      // Hedge TP = SL x Coef
input double   HedgeBreakevenPct   = 50.0;     // Breakeven activation (% of TP distance)

// ── Step 2: Trade Management ─────────────────────────────────────
input group "=== STEP 2: TRADE MANAGEMENT ==="
input bool     UseMaxProfitClose   = false;    // Close all at max profit?
input bool     UseMaxLossClose     = false;    // Close all at max loss?
input bool     UseDailyProfitLimit = true;     // Use daily profit limit?
input double   DailyProfitPct      = 10.0;     // Daily profit limit (% of balance)
input bool     UseDailyLossLimit   = true;     // Use daily loss limit?
input double   DailyLossPct        = 2.0;      // Daily loss limit (% of balance)
input int      MaxRangeCyclesDay   = 20;       // Max range cycles per day

// ── NEW v1.1: Signal Mode ─────────────────────────────────────────
input group "=== v1.1: SIGNAL CONFIRMATION MODE ==="
input bool     UseAndLogic         = true;     // TRUE=Ichimoku AND Stoch | FALSE=OR (v1.0)
input bool     RequireCandleConfirm= true;     // Require candle body confirms direction
input int      CooldownBars        = 3;        // Min bars to wait after any trade close

// ── NEW v1.1: Filters ─────────────────────────────────────────────
input group "=== v1.1: QUALITY FILTERS ==="
input double   MaxSpreadPoints     = 80.0;     // Max allowed spread in points (0=disabled)
input double   ATR_MinFilter       = 0.0;      // Minimum ATR to trade (0=disabled)
input double   ATR_MaxFilter       = 0.0;      // Maximum ATR to trade (0=disabled)
input int      MaxConsecLosses     = 3;        // Pause after N consecutive losses (0=disabled)
input int      ConsecLossPauseBars = 10;       // Bars to pause after max consec losses

// ── NEW v1.1: Partial Close ───────────────────────────────────────
input group "=== v1.1: PARTIAL CLOSE ==="
input bool     UsePartialClose     = true;     // Enable partial close at 50% to TP
input double   PartialClosePct     = 50.0;     // % of position to close partially
input double   PartialTriggerPct   = 50.0;     // Trigger when price reaches X% of TP dist

// ── Step 3: Primary Order - Indicator Parameters ──────────────────
input group "=== STEP 3: ICHIMOKU PARAMETERS ==="
input int      Ichimoku_Tenkan     = 9;        // Tenkan Sen period
input int      Ichimoku_Kijun      = 26;       // Kijun Sen period
input int      Ichimoku_SenkouB    = 52;       // Senkou Span B period
input int      Ichimoku_Shift      = 1;        // Candle shift

input group "=== STEP 3: STOCHASTIC PARAMETERS ==="
input int      Stoch_K             = 5;        // %K period
input int      Stoch_D             = 3;        // %D period
input int      Stoch_Slowing       = 3;        // Slowing
input double   Stoch_SellLevel     = 80.0;     // Stochastic sell level
input double   Stoch_BuyLevel      = 20.0;     // Stochastic buy level
input int      Stoch_Shift         = 1;        // Candle shift

input group "=== STEP 3: TREND FILTER - RSI ==="
input int      RSI_Period          = 14;       // RSI period (trend filter)
input double   RSI_TrendLevel      = 50.0;     // RSI trend level
input int      RSI_Shift           = 1;        // Candle shift

input group "=== STEP 3: TREND FILTER - PARABOLIC SAR ==="
input double   SAR_Step            = 0.02;     // SAR step
input double   SAR_Maximum         = 0.2;      // SAR maximum
input int      SAR_Shift           = 1;        // Candle shift

input group "=== STEP 3: EXIT SIGNAL - RSI ==="
input int      RSI_Exit_Period     = 14;       // RSI exit period
input double   RSI_ExitSellLevel   = 70.0;     // RSI exit sell level (close buy)
input double   RSI_ExitBuyLevel    = 30.0;     // RSI exit buy level (close sell)
input int      RSI_Exit_Shift      = 1;        // Candle shift

// ── Step 4: Hedge Order - Bollinger Bands ─────────────────────────
input group "=== STEP 4: BOLLINGER BANDS (HEDGE ENTRY) ==="
input int      BB_Period           = 20;       // Bollinger Bands period
input double   BB_Deviations       = 2.0;      // Standard deviations
input int      BB_Shift            = 0;        // Bands shift
input int      BB_CandleShift      = 1;        // Candle shift

// ── Step 5: Trading Hours ─────────────────────────────────────────
input group "=== STEP 5: TRADING HOURS & DAYS ==="
input int      TradingStartHour    = 12;       // Trading start hour (server time)
input int      TradingStartMin     = 0;        // Trading start minute
input int      TradingEndHour      = 22;       // Trading end hour (server time)
input int      TradingEndMin       = 0;        // Trading end minute
input bool     TradeMonday         = true;     // Trade on Monday
input bool     TradeTuesday        = true;     // Trade on Tuesday
input bool     TradeWednesday      = true;     // Trade on Wednesday
input bool     TradeThursday       = true;     // Trade on Thursday
input bool     TradeFriday         = true;     // Trade on Friday

// ── ATR ──────────────────────────────────────────────────────────
input group "=== ATR SETTINGS ==="
input int      ATR_Period          = 14;       // ATR period
input ENUM_TIMEFRAMES ATR_TF       = PERIOD_CURRENT; // ATR timeframe

// ── Dashboard ─────────────────────────────────────────────────────
input group "=== DASHBOARD ==="
input bool     ShowDashboard       = true;     // Show dashboard
input color    DashBGColor         = C'15,15,25';   // Dashboard background color
input color    DashTextColor       = clrWhite;      // Dashboard text color
input color    DashBuyColor        = clrLime;       // Buy signal color
input color    DashSellColor       = clrOrangeRed;  // Sell signal color
input int      DashX               = 10;       // Dashboard X position
input int      DashY               = 30;       // Dashboard Y position

// ── General ───────────────────────────────────────────────────────
input group "=== GENERAL ==="
input long     MagicNumber         = 20250604; // EA Magic Number
input string   TradeComment        = "PeakRH"; // Trade comment

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         Trade;
CPositionInfo  PosInfo;

int h_Ichimoku, h_Stoch, h_RSI_Filter, h_SAR, h_RSI_Exit, h_BB, h_ATR;

datetime       LastBarTime         = 0;
int            DailyCycles         = 0;
double         DailyStartBalance   = 0;
datetime       LastDayReset        = 0;
bool           DailyLimitReached   = false;

// v1.1 state
int            CooldownBarsLeft    = 0;        // bars remaining in cooldown
int            ConsecLossCount     = 0;        // current consecutive losses
int            ConsecLossPauseLeft = 0;        // bars left in consec-loss pause
datetime       LastTradeCloseBar   = 0;        // bar time of last trade close

// Partial close tracking (ticket → already partially closed)
ulong          PartialClosedTickets[]; 

string         ObjPrefix           = "PRH11_";

enum SIGNAL_TYPE { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = -1 };

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(30);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);

   h_Ichimoku   = iIchimoku(_Symbol, PERIOD_CURRENT, Ichimoku_Tenkan, Ichimoku_Kijun, Ichimoku_SenkouB);
   h_Stoch      = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   h_RSI_Filter = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   h_SAR        = iSAR(_Symbol, PERIOD_CURRENT, SAR_Step, SAR_Maximum);
   h_RSI_Exit   = iRSI(_Symbol, PERIOD_CURRENT, RSI_Exit_Period, PRICE_CLOSE);
   h_BB         = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_Shift, BB_Deviations, PRICE_CLOSE);
   h_ATR        = iATR(_Symbol, ATR_TF, ATR_Period);

   if(h_Ichimoku==INVALID_HANDLE || h_Stoch==INVALID_HANDLE || h_RSI_Filter==INVALID_HANDLE ||
      h_SAR==INVALID_HANDLE || h_RSI_Exit==INVALID_HANDLE || h_BB==INVALID_HANDLE || h_ATR==INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles.");
      return INIT_FAILED;
   }

   ArrayResize(PartialClosedTickets, 0);
   if(ShowDashboard) CreateDashboard();
   Print("PeakRangeHedging v1.1 initialized. Magic: ", MagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_Ichimoku); IndicatorRelease(h_Stoch);
   IndicatorRelease(h_RSI_Filter); IndicatorRelease(h_SAR);
   IndicatorRelease(h_RSI_Exit); IndicatorRelease(h_BB); IndicatorRelease(h_ATR);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = (currentBar != LastBarTime);

   if(isNewBar)
   {
      LastBarTime = currentBar;
      CheckDailyReset();

      // Decrement cooldown counters on new bar
      if(CooldownBarsLeft > 0)     CooldownBarsLeft--;
      if(ConsecLossPauseLeft > 0)  ConsecLossPauseLeft--;

      // Check if any positions closed (to update streak & cooldown)
      CheckPositionsClosed();
   }

   // Always manage trailing stops and partial closes on every tick
   ManageTrailingStops();
   if(UsePartialClose) ManagePartialClose();

   // Only trade logic on new bar
   if(!isNewBar)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   if(DailyLimitReached || !IsTradeAllowed() || CheckDailyLimits())
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Cooldown check
   if(CooldownBarsLeft > 0 || ConsecLossPauseLeft > 0)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Quality filters
   if(!PassesQualityFilters())
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Exit signals first (RSI)
   CheckExitSignals();

   int primaryCount = CountPrimaryOrders();
   int hedgeCount   = CountHedgeOrders();
   int totalCount   = primaryCount + hedgeCount;

   if(totalCount >= MaxOrders || DailyCycles >= MaxRangeCyclesDay)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   SIGNAL_TYPE primarySignal = GetPrimaryEntrySignal();
   SIGNAL_TYPE trendFilter   = GetTrendFilter();
   SIGNAL_TYPE hedgeSignal   = GetHedgeEntrySignal();

   // ── Primary Order Logic ──────────────────────────────────────
   if(primaryCount == 0 && hedgeCount == 0)
   {
      if(primarySignal == SIG_BUY && trendFilter == SIG_BUY)
      {
         OpenPrimaryOrder(ORDER_TYPE_BUY);
         DailyCycles++;
      }
      else if(primarySignal == SIG_SELL && trendFilter == SIG_SELL)
      {
         OpenPrimaryOrder(ORDER_TYPE_SELL);
         DailyCycles++;
      }
   }
   else if(primaryCount > 0 && hedgeCount == 0)
   {
      ENUM_ORDER_TYPE lastPrimaryDir = GetLastPrimaryDirection();
      if(hedgeSignal == SIG_SELL && lastPrimaryDir == ORDER_TYPE_BUY)
         OpenHedgeOrder(ORDER_TYPE_SELL);
      else if(hedgeSignal == SIG_BUY && lastPrimaryDir == ORDER_TYPE_SELL)
         OpenHedgeOrder(ORDER_TYPE_BUY);
   }
   else if(primaryCount > 0 && hedgeCount > 0)
   {
      ENUM_ORDER_TYPE lastHedgeDir = GetLastHedgeDirection();
      if(primarySignal == SIG_SELL && trendFilter == SIG_SELL && lastHedgeDir == ORDER_TYPE_BUY)
         OpenPrimaryOrder(ORDER_TYPE_SELL);
      else if(primarySignal == SIG_BUY && trendFilter == SIG_BUY && lastHedgeDir == ORDER_TYPE_SELL)
         OpenPrimaryOrder(ORDER_TYPE_BUY);
   }

   if(ShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| QUALITY FILTERS (v1.1)                                          |
//+------------------------------------------------------------------+
bool PassesQualityFilters()
{
   // Spread filter
   if(MaxSpreadPoints > 0)
   {
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point / _Point; // in points
      long   spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spreadPts > (long)MaxSpreadPoints) return false;
   }

   // ATR filters
   double atr = GetATR();
   if(ATR_MinFilter > 0 && atr < ATR_MinFilter) return false;
   if(ATR_MaxFilter > 0 && atr > ATR_MaxFilter) return false;

   return true;
}

//+------------------------------------------------------------------+
//| PRIMARY ENTRY SIGNAL (v1.1: AND or OR mode)                     |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetPrimaryEntrySignal()
{
   // ── Ichimoku Tenkan/Kijun crossover ──────────────────────────
   double tenkan_curr[1], tenkan_prev[1], kijun_curr[1], kijun_prev[1];
   ArraySetAsSeries(tenkan_curr, true); ArraySetAsSeries(tenkan_prev, true);
   ArraySetAsSeries(kijun_curr,  true); ArraySetAsSeries(kijun_prev,  true);

   if(CopyBuffer(h_Ichimoku, 0, Ichimoku_Shift,   1, tenkan_curr) < 1) return SIG_NONE;
   if(CopyBuffer(h_Ichimoku, 0, Ichimoku_Shift+1, 1, tenkan_prev) < 1) return SIG_NONE;
   if(CopyBuffer(h_Ichimoku, 1, Ichimoku_Shift,   1, kijun_curr)  < 1) return SIG_NONE;
   if(CopyBuffer(h_Ichimoku, 1, Ichimoku_Shift+1, 1, kijun_prev)  < 1) return SIG_NONE;

   SIGNAL_TYPE ichimokuSig = SIG_NONE;
   if(tenkan_prev[0] <= kijun_prev[0] && tenkan_curr[0] > kijun_curr[0]) ichimokuSig = SIG_BUY;
   else if(tenkan_prev[0] >= kijun_prev[0] && tenkan_curr[0] < kijun_curr[0]) ichimokuSig = SIG_SELL;

   // ── Stochastic %K crosses level ──────────────────────────────
   double stoch_k_curr[1], stoch_k_prev[1];
   ArraySetAsSeries(stoch_k_curr, true);
   ArraySetAsSeries(stoch_k_prev, true);
   if(CopyBuffer(h_Stoch, 0, Stoch_Shift,   1, stoch_k_curr) < 1) return SIG_NONE;
   if(CopyBuffer(h_Stoch, 0, Stoch_Shift+1, 1, stoch_k_prev) < 1) return SIG_NONE;

   SIGNAL_TYPE stochSig = SIG_NONE;
   if(stoch_k_prev[0] <= Stoch_BuyLevel  && stoch_k_curr[0] > Stoch_BuyLevel)  stochSig = SIG_BUY;
   else if(stoch_k_prev[0] >= Stoch_SellLevel && stoch_k_curr[0] < Stoch_SellLevel) stochSig = SIG_SELL;

   SIGNAL_TYPE combined = SIG_NONE;

   if(UseAndLogic)
   {
      // AND: both must agree on same direction
      if(ichimokuSig == SIG_BUY  && stochSig == SIG_BUY)  combined = SIG_BUY;
      if(ichimokuSig == SIG_SELL && stochSig == SIG_SELL) combined = SIG_SELL;
   }
   else
   {
      // OR: either signal valid (v1.0 behavior)
      if(ichimokuSig != SIG_NONE) combined = ichimokuSig;
      else if(stochSig != SIG_NONE) combined = stochSig;
   }

   if(combined == SIG_NONE) return SIG_NONE;

   // ── v1.1 CANDLE BODY CONFIRMATION ────────────────────────────
   if(RequireCandleConfirm)
   {
      double candleOpen  = iOpen(_Symbol,  PERIOD_CURRENT, Ichimoku_Shift);
      double candleClose = iClose(_Symbol, PERIOD_CURRENT, Ichimoku_Shift);
      if(combined == SIG_BUY  && candleClose <= candleOpen) return SIG_NONE; // Bearish candle - reject BUY
      if(combined == SIG_SELL && candleClose >= candleOpen) return SIG_NONE; // Bullish candle - reject SELL
   }

   return combined;
}

//+------------------------------------------------------------------+
//| TREND FILTER (RSI AND SAR)                                      |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetTrendFilter()
{
   double rsi[1];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(h_RSI_Filter, 0, RSI_Shift, 1, rsi) < 1) return SIG_NONE;

   SIGNAL_TYPE rsiTrend = SIG_NONE;
   if(rsi[0] > RSI_TrendLevel)      rsiTrend = SIG_BUY;
   else if(rsi[0] < RSI_TrendLevel) rsiTrend = SIG_SELL;

   double sar[1];
   ArraySetAsSeries(sar, true);
   if(CopyBuffer(h_SAR, 0, SAR_Shift, 1, sar) < 1) return SIG_NONE;

   double closePrice = iClose(_Symbol, PERIOD_CURRENT, SAR_Shift);
   SIGNAL_TYPE sarTrend = (sar[0] < closePrice) ? SIG_BUY : SIG_SELL;

   if(rsiTrend == SIG_BUY  && sarTrend == SIG_BUY)  return SIG_BUY;
   if(rsiTrend == SIG_SELL && sarTrend == SIG_SELL) return SIG_SELL;
   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| HEDGE ENTRY SIGNAL (Bollinger Bands midline)                    |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetHedgeEntrySignal()
{
   double bbMid[1];
   ArraySetAsSeries(bbMid, true);
   if(CopyBuffer(h_BB, 0, BB_CandleShift, 1, bbMid) < 1) return SIG_NONE;
   double closePrice = iClose(_Symbol, PERIOD_CURRENT, BB_CandleShift);
   if(closePrice > bbMid[0]) return SIG_BUY;
   if(closePrice < bbMid[0]) return SIG_SELL;
   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| EXIT SIGNALS (RSI)                                              |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   double rsi_curr[1], rsi_prev[1];
   ArraySetAsSeries(rsi_curr, true); ArraySetAsSeries(rsi_prev, true);
   if(CopyBuffer(h_RSI_Exit, 0, RSI_Exit_Shift,   1, rsi_curr) < 1) return;
   if(CopyBuffer(h_RSI_Exit, 0, RSI_Exit_Shift+1, 1, rsi_prev) < 1) return;

   bool rsiCrossAboveSell = (rsi_prev[0] <= RSI_ExitSellLevel && rsi_curr[0] > RSI_ExitSellLevel);
   bool rsiCrossBelowBuy  = (rsi_prev[0] >= RSI_ExitBuyLevel  && rsi_curr[0] < RSI_ExitBuyLevel);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      double profit = PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();
      if(PosInfo.PositionType() == POSITION_TYPE_BUY  && rsiCrossAboveSell && profit > 0)
         Trade.PositionClose(PosInfo.Ticket());
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL && rsiCrossBelowBuy && profit > 0)
         Trade.PositionClose(PosInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| v1.1: PARTIAL CLOSE at 50% of TP distance                      |
//+------------------------------------------------------------------+
void ManagePartialClose()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;

      ulong ticket = PosInfo.Ticket();

      // Already partially closed?
      bool alreadyDone = false;
      for(int k = 0; k < ArraySize(PartialClosedTickets); k++)
         if(PartialClosedTickets[k] == ticket) { alreadyDone = true; break; }
      if(alreadyDone) continue;

      double openPrice = PosInfo.PriceOpen();
      double tp        = PosInfo.TakeProfit();
      if(tp == 0) continue;

      double tpDist    = MathAbs(tp - openPrice);
      double trigger   = tpDist * (PartialTriggerPct / 100.0);

      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool triggered = false;
      if(PosInfo.PositionType() == POSITION_TYPE_BUY  && currentBid >= openPrice + trigger) triggered = true;
      if(PosInfo.PositionType() == POSITION_TYPE_SELL && currentAsk <= openPrice - trigger) triggered = true;

      if(triggered)
      {
         double vol     = PosInfo.Volume();
         double closeVol= NormalizeDouble(vol * (PartialClosePct / 100.0), 2);
         double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         closeVol       = MathMax(minLot, MathRound(closeVol / lotStep) * lotStep);

         if(closeVol < vol) // Only if there's remaining volume
         {
            Trade.PositionClosePartial(ticket, closeVol);
            // Mark as done
            int sz = ArraySize(PartialClosedTickets);
            ArrayResize(PartialClosedTickets, sz + 1);
            PartialClosedTickets[sz] = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OPEN PRIMARY ORDER                                               |
//+------------------------------------------------------------------+
void OpenPrimaryOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR();
   if(atr <= 0) return;

   double sl_dist = atr * ATR_SL_Coef;
   double tp_dist = sl_dist * RR_Ratio;
   double price   = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist, _Digits);

   double volume = CalcDynamicVolume(sl_dist, RiskPerOrder);
   if(volume <= 0) return;

   Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, TradeComment + "_PRI");
}

//+------------------------------------------------------------------+
//| OPEN HEDGE ORDER                                                 |
//+------------------------------------------------------------------+
void OpenHedgeOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR();
   if(atr <= 0) return;

   double sl_dist = atr * HedgeATR_SL_Coef;
   double tp_dist = sl_dist * HedgeRR_Ratio;
   double price   = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist, _Digits);

   double volume = CalcDynamicVolume(sl_dist, HedgeRiskPerOrder);
   if(volume <= 0) return;

   Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, TradeComment + "_HDG");
}

//+------------------------------------------------------------------+
//| DYNAMIC VOLUME                                                   |
//+------------------------------------------------------------------+
double CalcDynamicVolume(double sl_price_dist, double riskPct)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt   = balance * riskPct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || sl_price_dist <= 0) return 0;
   double volume    = riskAmt / ((sl_price_dist / tickSize) * tickValue);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, MathRound(volume / lotStep) * lotStep)), 2);
}

//+------------------------------------------------------------------+
//| ATR                                                              |
//+------------------------------------------------------------------+
double GetATR()
{
   double atr[1];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR, 0, 1, 1, atr) < 1) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| TRAILING STOPS & BREAKEVEN                                      |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;

      ulong  ticket    = PosInfo.Ticket();
      double openPrice = PosInfo.PriceOpen();
      double currentSL = PosInfo.StopLoss();
      double currentTP = PosInfo.TakeProfit();
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool   isHedge   = (StringFind(PosInfo.Comment(), "_HDG") >= 0);

      if(PosInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double tpDist    = currentTP - openPrice;
         double pct       = isHedge ? (HedgeBreakevenPct / 100.0) : (TrailingStopPct / 100.0);
         double activation= openPrice + tpDist * pct;
         if(bid >= activation)
         {
            double newSL;
            if(isHedge)
               newSL = NormalizeDouble(openPrice, _Digits);
            else
               newSL = NormalizeDouble(bid - tpDist * (1.0 - TrailingStopPct / 100.0), _Digits);
            if(newSL > currentSL + _Point)
               Trade.PositionModify(ticket, newSL, currentTP);
         }
      }
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double tpDist    = openPrice - currentTP;
         double pct       = isHedge ? (HedgeBreakevenPct / 100.0) : (TrailingStopPct / 100.0);
         double activation= openPrice - tpDist * pct;
         if(ask <= activation)
         {
            double newSL;
            if(isHedge)
               newSL = NormalizeDouble(openPrice, _Digits);
            else
               newSL = NormalizeDouble(ask + tpDist * (1.0 - TrailingStopPct / 100.0), _Digits);
            if(currentSL == 0 || newSL < currentSL - _Point)
               Trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| v1.1: CHECK FOR CLOSED POSITIONS (track streak & cooldown)      |
//+------------------------------------------------------------------+
void CheckPositionsClosed()
{
   static ulong lastKnownTickets[];
   
   // Build current open ticket list
   ulong currentTickets[];
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      ArrayResize(currentTickets, n + 1);
      currentTickets[n++] = PosInfo.Ticket();
   }

   // Find tickets that were open last bar but closed now
   bool anyClose = false;
   for(int j = 0; j < ArraySize(lastKnownTickets); j++)
   {
      bool stillOpen = false;
      for(int k = 0; k < n; k++)
         if(currentTickets[k] == lastKnownTickets[j]) { stillOpen = true; break; }
      
      if(!stillOpen)
      {
         anyClose = true;
         // Determine if it was a win or loss from history
         if(HistorySelectByPosition(lastKnownTickets[j]))
         {
            double totalProfit = 0;
            for(int d = 0; d < HistoryDealsTotal(); d++)
            {
               ulong dealTicket = HistoryDealGetTicket(d);
               if(dealTicket == 0) continue;
               if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == (long)lastKnownTickets[j])
                  totalProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            }
            if(totalProfit < 0)
            {
               ConsecLossCount++;
               if(MaxConsecLosses > 0 && ConsecLossCount >= MaxConsecLosses)
               {
                  ConsecLossPauseLeft = ConsecLossPauseBars;
                  ConsecLossCount = 0;
                  Print("v1.1: Max consecutive losses reached. Pausing ", ConsecLossPauseBars, " bars.");
               }
            }
            else
            {
               ConsecLossCount = 0; // Reset streak on win
            }
         }
      }
   }

   if(anyClose)
      CooldownBarsLeft = CooldownBars;

   // Update known tickets
   ArrayResize(lastKnownTickets, n);
   for(int i = 0; i < n; i++) lastKnownTickets[i] = currentTickets[i];
}

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
int CountPrimaryOrders()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_PRI") >= 0) count++;
   }
   return count;
}

int CountHedgeOrders()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_HDG") >= 0) count++;
   }
   return count;
}

ENUM_ORDER_TYPE GetLastPrimaryDirection()
{
   datetime latestTime = 0;
   ENUM_ORDER_TYPE dir = ORDER_TYPE_BUY;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_PRI") < 0) continue;
      if(PosInfo.Time() >= latestTime) { latestTime = PosInfo.Time(); dir = (PosInfo.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; }
   }
   return dir;
}

ENUM_ORDER_TYPE GetLastHedgeDirection()
{
   datetime latestTime = 0;
   ENUM_ORDER_TYPE dir = ORDER_TYPE_SELL;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_HDG") < 0) continue;
      if(PosInfo.Time() >= latestTime) { latestTime = PosInfo.Time(); dir = (PosInfo.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; }
   }
   return dir;
}

bool IsTradeAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
   {
      case 1: if(!TradeMonday)    return false; break;
      case 2: if(!TradeTuesday)   return false; break;
      case 3: if(!TradeWednesday) return false; break;
      case 4: if(!TradeThursday)  return false; break;
      case 5: if(!TradeFriday)    return false; break;
      default: return false;
   }
   int cur   = dt.hour * 60 + dt.min;
   int start = TradingStartHour * 60 + TradingStartMin;
   int end_  = TradingEndHour   * 60 + TradingEndMin;
   return (cur >= start && cur < end_);
}

void CheckDailyReset()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayMidnight = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(todayMidnight > LastDayReset)
   {
      LastDayReset      = todayMidnight;
      DailyCycles       = 0;
      DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      DailyLimitReached = false;
   }
}

bool CheckDailyLimits()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(UseDailyProfitLimit)
   {
      if(equity - DailyStartBalance >= DailyStartBalance * DailyProfitPct / 100.0)
      {
         if(!DailyLimitReached && UseMaxProfitClose) CloseAllPositions();
         DailyLimitReached = true; return true;
      }
   }
   if(UseDailyLossLimit)
   {
      if(DailyStartBalance - equity >= DailyStartBalance * DailyLossPct / 100.0)
      {
         if(!DailyLimitReached && UseMaxLossClose) CloseAllPositions();
         DailyLimitReached = true; return true;
      }
   }
   return false;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      Trade.PositionClose(PosInfo.Ticket());
   }
}

double GetTotalFloatingPL()
{
   double total = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      total += PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();
   }
   return total;
}

//+------------------------------------------------------------------+
//| ═══════════════════ DASHBOARD v1.1 ══════════════════════════════|
//+------------------------------------------------------------------+
void CreateDashboard()
{
   string bgName = ObjPrefix + "BG";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DashX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DashY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 250);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 390);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, DashBGColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'40,40,80');
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);

   CreateLabel("TITLE",    "⬡ PEAK RANGE HEDGING v1.1",     DashX+8,  DashY+6,   11, C'100,200,255', true);
   CreateLabel("SEP0",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",  DashX+6,  DashY+22,  8,  C'40,40,80');

   CreateLabel("LBL_SYMBOL",  "Symbol:  --",      DashX+8, DashY+32,  9, DashTextColor);
   CreateLabel("LBL_SPREAD",  "Spread:  -- pts",  DashX+8, DashY+46,  9, DashTextColor);
   CreateLabel("LBL_ATR",     "ATR:     --",      DashX+8, DashY+60,  9, DashTextColor);
   CreateLabel("SEP1",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",  DashX+6,  DashY+74,  8,  C'40,40,80');

   CreateLabel("LBL_PORDERS", "Primary: 0",       DashX+8, DashY+84,  9, DashTextColor);
   CreateLabel("LBL_HORDERS", "Hedge:   0",       DashX+8, DashY+98,  9, DashTextColor);
   CreateLabel("LBL_CYCLES",  "Cycles:  0/20",    DashX+8, DashY+112, 9, DashTextColor);
   CreateLabel("LBL_COOLDOWN","Cooldown: 0 bars", DashX+8, DashY+126, 9, DashTextColor);
   CreateLabel("SEP2",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",  DashX+6,  DashY+140, 8,  C'40,40,80');

   CreateLabel("LBL_EQUITY",  "Equity:  --",      DashX+8, DashY+150, 9, DashTextColor);
   CreateLabel("LBL_PL",      "Float:   --",      DashX+8, DashY+164, 9, DashTextColor);
   CreateLabel("LBL_DAILYPL", "Daily:   --",      DashX+8, DashY+178, 9, DashTextColor);
   CreateLabel("SEP3",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",  DashX+6,  DashY+192, 8,  C'40,40,80');

   CreateLabel("LBL_SIGNAL",  "Signal:  --",      DashX+8, DashY+202, 9, DashTextColor);
   CreateLabel("LBL_TREND",   "Trend:   --",      DashX+8, DashY+216, 9, DashTextColor);
   CreateLabel("LBL_MODE",    "Mode:    AND",     DashX+8, DashY+230, 9, C'150,150,255');
   CreateLabel("SEP4",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",  DashX+6,  DashY+244, 8,  C'40,40,80');

   CreateLabel("LBL_STATUS",  "Status:  ACTIVE",  DashX+8, DashY+254, 9, clrLime);
   CreateLabel("LBL_STREAK",  "Streak:  --",      DashX+8, DashY+268, 9, DashTextColor);
   CreateLabel("LBL_LIMIT",   "Daily:   OK",      DashX+8, DashY+282, 9, clrLime);
   CreateLabel("SEP5",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",  DashX+6,  DashY+296, 8,  C'40,40,80');

   CreateLabel("LBL_HOURS",   StringFormat("Hours: %02d:%02d - %02d:%02d", TradingStartHour, TradingStartMin, TradingEndHour, TradingEndMin),
               DashX+8, DashY+306, 8, C'120,120,180');
   CreateLabel("LBL_MAGIC",   StringFormat("Magic: %d | v1.1", MagicNumber), DashX+8, DashY+320, 7, C'60,60,100');
   CreateLabel("LBL_FILTERS", "Filters: Spread+ATR+Candle", DashX+8, DashY+334, 7, C'60,60,100');

   ChartRedraw(0);
}

void CreateLabel(string id, string text, int x, int y, int fontSize, color clr, bool bold=false)
{
   string name = ObjPrefix + id;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void UpdateLabel(string id, string text, color clr=clrNONE)
{
   string name = ObjPrefix + id;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   if(clr != clrNONE) ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void UpdateDashboard()
{
   if(!ShowDashboard) return;

   long   spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double atr       = GetATR();
   string currency  = AccountInfoString(ACCOUNT_CURRENCY);
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double floatPL   = GetTotalFloatingPL();
   double dailyPL   = equity - DailyStartBalance;

   // Spread color: green if OK, red if too high
   color spreadClr = (MaxSpreadPoints > 0 && spreadPts > (long)MaxSpreadPoints) ? clrOrangeRed : clrLime;

   UpdateLabel("LBL_SYMBOL",  StringFormat("Symbol:  %s", _Symbol));
   UpdateLabel("LBL_SPREAD",  StringFormat("Spread:  %d pts", spreadPts), spreadClr);
   UpdateLabel("LBL_ATR",     StringFormat("ATR:     %.2f", atr));

   int pri = CountPrimaryOrders();
   int hdg = CountHedgeOrders();
   UpdateLabel("LBL_PORDERS", StringFormat("Primary: %d", pri));
   UpdateLabel("LBL_HORDERS", StringFormat("Hedge:   %d", hdg));
   UpdateLabel("LBL_CYCLES",  StringFormat("Cycles:  %d/%d", DailyCycles, MaxRangeCyclesDay));

   int coolTotal = CooldownBarsLeft + ConsecLossPauseLeft;
   color coolClr = (coolTotal > 0) ? clrGold : DashTextColor;
   UpdateLabel("LBL_COOLDOWN", StringFormat("Cooldown: %d bars", coolTotal), coolClr);

   color plClr    = (floatPL >= 0)  ? clrLime : clrOrangeRed;
   color dailyClr = (dailyPL >= 0)  ? clrLime : clrOrangeRed;
   UpdateLabel("LBL_EQUITY",  StringFormat("Equity:  %.2f %s", equity, currency));
   UpdateLabel("LBL_PL",      StringFormat("Float:   %+.2f %s", floatPL, currency), plClr);
   UpdateLabel("LBL_DAILYPL", StringFormat("Daily:   %+.2f %s", dailyPL, currency), dailyClr);

   SIGNAL_TYPE sig   = GetPrimaryEntrySignal();
   SIGNAL_TYPE trend = GetTrendFilter();
   string sigStr     = (sig == SIG_BUY) ? "BUY ▲" : (sig == SIG_SELL) ? "SELL ▼" : "NONE";
   color  sigClr     = (sig == SIG_BUY) ? DashBuyColor : (sig == SIG_SELL) ? DashSellColor : DashTextColor;
   string trendStr   = (trend == SIG_BUY) ? "UP ▲" : (trend == SIG_SELL) ? "DOWN ▼" : "MIXED";
   color  trendClr   = (trend == SIG_BUY) ? DashBuyColor : (trend == SIG_SELL) ? DashSellColor : clrGold;
   UpdateLabel("LBL_SIGNAL", StringFormat("Signal:  %s", sigStr),   sigClr);
   UpdateLabel("LBL_TREND",  StringFormat("Trend:   %s", trendStr), trendClr);
   UpdateLabel("LBL_MODE",   StringFormat("Mode:    %s | Confirm:%s", UseAndLogic ? "AND" : "OR", RequireCandleConfirm ? "ON" : "OFF"), C'150,150,255');

   bool  inHours  = IsTradeAllowed();
   string statStr = DailyLimitReached ? "LIMIT HIT" : (coolTotal > 0) ? "COOLDOWN" : inHours ? "ACTIVE" : "OFF-HOURS";
   color  statClr = DailyLimitReached ? clrOrangeRed : (coolTotal > 0) ? clrGold : inHours ? clrLime : clrGold;
   UpdateLabel("LBL_STATUS", StringFormat("Status:  %s", statStr), statClr);

   string streakStr = (ConsecLossCount > 0) ? StringFormat("Losses: %d/%d", ConsecLossCount, MaxConsecLosses > 0 ? MaxConsecLosses : 99) : "Streak: OK";
   color  streakClr = (ConsecLossCount >= 2) ? clrOrangeRed : (ConsecLossCount == 1) ? clrGold : clrLime;
   UpdateLabel("LBL_STREAK", streakStr, streakClr);

   string limitStr = DailyLimitReached ? "Daily:   REACHED" : "Daily:   OK";
   UpdateLabel("LBL_LIMIT", limitStr, DailyLimitReached ? clrOrangeRed : clrLime);

   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, ObjPrefix);
   ChartRedraw(0);
}

string PeriodToStr(ENUM_TIMEFRAMES p)
{
   switch(p)
   {
      case PERIOD_M1: return "M1"; case PERIOD_M5: return "M5";
      case PERIOD_M15: return "M15"; case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";  case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";  default: return "TF";
   }
}
//+------------------------------------------------------------------+
//| END OF EA v1.1                                                   |
//+------------------------------------------------------------------+
