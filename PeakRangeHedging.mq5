//+------------------------------------------------------------------+
//|                                           PeakRangeHedging.mq5  |
//|                         Range Hedging EA - Full Implementation   |
//|                    Reverse Engineered & Built from Strategy Spec |
//+------------------------------------------------------------------+
#property copyright "Peak Range Hedging EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Trend.mqh>

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
input double   HedgeATR_SL_Coef   = 1.5;      // ATR multiplier for Hedge SL
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

// ── ATR for dynamic SL/TP ─────────────────────────────────────────
input group "=== ATR SETTINGS ==="
input int      ATR_Period          = 14;       // ATR period
input ENUM_TIMEFRAMES ATR_TF       = PERIOD_CURRENT; // ATR timeframe

// ── Dashboard ─────────────────────────────────────────────────────
input group "=== DASHBOARD ==="
input bool     ShowDashboard       = true;     // Show dashboard
input color    DashBGColor         = C'20,20,30';   // Dashboard background color
input color    DashTextColor       = clrWhite;      // Dashboard text color
input color    DashBuyColor        = clrLime;       // Buy signal color
input color    DashSellColor       = clrOrangeRed;  // Sell signal color
input int      DashX              = 10;        // Dashboard X position
input int      DashY              = 30;        // Dashboard Y position

// ── Magic Number ─────────────────────────────────────────────────
input group "=== GENERAL ==="
input long     MagicNumber         = 20250604; // EA Magic Number
input string   TradeComment        = "PeakRH"; // Trade comment

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         Trade;
CPositionInfo  PosInfo;

// Indicator handles
int h_Ichimoku, h_Stoch, h_RSI_Filter, h_SAR, h_RSI_Exit, h_BB, h_ATR;

// State tracking
datetime       LastBarTime         = 0;
int            DailyCycles         = 0;
double         DailyStartBalance   = 0;
datetime       LastDayReset        = 0;
bool           DailyLimitReached   = false;

// Dashboard object prefix
string         ObjPrefix           = "PRH_";

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum SIGNAL_TYPE { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = -1 };

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(30);
   Trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Create indicator handles
   h_Ichimoku  = iIchimoku(_Symbol, PERIOD_CURRENT, Ichimoku_Tenkan, Ichimoku_Kijun, Ichimoku_SenkouB);
   h_Stoch     = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   h_RSI_Filter= iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   h_SAR       = iSAR(_Symbol, PERIOD_CURRENT, SAR_Step, SAR_Maximum);
   h_RSI_Exit  = iRSI(_Symbol, PERIOD_CURRENT, RSI_Exit_Period, PRICE_CLOSE);
   h_BB        = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_Shift, BB_Deviations, PRICE_CLOSE);
   h_ATR       = iATR(_Symbol, ATR_TF, ATR_Period);

   if(h_Ichimoku == INVALID_HANDLE || h_Stoch == INVALID_HANDLE ||
      h_RSI_Filter == INVALID_HANDLE || h_SAR == INVALID_HANDLE ||
      h_RSI_Exit == INVALID_HANDLE || h_BB == INVALID_HANDLE || h_ATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create one or more indicator handles.");
      return INIT_FAILED;
   }

   if(ShowDashboard) CreateDashboard();

   Print("PeakRangeHedging EA initialized successfully. Magic: ", MagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_Ichimoku);
   IndicatorRelease(h_Stoch);
   IndicatorRelease(h_RSI_Filter);
   IndicatorRelease(h_SAR);
   IndicatorRelease(h_RSI_Exit);
   IndicatorRelease(h_BB);
   IndicatorRelease(h_ATR);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| EXPERT TICK                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only act on new bar
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == LastBarTime) 
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }
   LastBarTime = currentBar;

   // Daily reset
   CheckDailyReset();

   // Check daily limits
   if(DailyLimitReached) 
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   if(!IsTradeAllowed()) 
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Check daily P&L limits
   if(CheckDailyLimits()) 
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Manage trailing stops and breakeven
   ManageTrailingStops();

   // Check RSI exit signals - close profitable trades
   CheckExitSignals();

   // Count open positions
   int primaryCount = CountPrimaryOrders();
   int hedgeCount   = CountHedgeOrders();
   int totalCount   = primaryCount + hedgeCount;

   // Max orders check
   if(totalCount >= MaxOrders) 
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Max daily cycles
   if(DailyCycles >= MaxRangeCyclesDay) 
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Get indicator values
   SIGNAL_TYPE primarySignal = GetPrimaryEntrySignal();
   SIGNAL_TYPE trendFilter   = GetTrendFilter();
   SIGNAL_TYPE hedgeSignal   = GetHedgeEntrySignal();

   // ── Primary Order Logic ──────────────────────────────────────
   if(primaryCount == 0 && hedgeCount == 0)
   {
      // No positions - open primary if signal + trend align
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
      // Primary open, no hedge yet - check hedge entry signal (opposite direction)
      ENUM_ORDER_TYPE lastPrimaryDir = GetLastPrimaryDirection();
      if(hedgeSignal != SIG_NONE)
      {
         // Hedge opens in opposite direction to primary
         if(lastPrimaryDir == ORDER_TYPE_BUY && hedgeSignal == SIG_SELL)
            OpenHedgeOrder(ORDER_TYPE_SELL);
         else if(lastPrimaryDir == ORDER_TYPE_SELL && hedgeSignal == SIG_BUY)
            OpenHedgeOrder(ORDER_TYPE_BUY);
      }
   }
   else if(primaryCount > 0 && hedgeCount > 0)
   {
      // Both open - alternating logic: after hedge, watch for new primary in opposite direction
      ENUM_ORDER_TYPE lastHedgeDir = GetLastHedgeDirection();
      if(primarySignal != SIG_NONE && trendFilter != SIG_NONE)
      {
         // New primary in opposite direction to last hedge
         if(lastHedgeDir == ORDER_TYPE_BUY && primarySignal == SIG_SELL && trendFilter == SIG_SELL)
            OpenPrimaryOrder(ORDER_TYPE_SELL);
         else if(lastHedgeDir == ORDER_TYPE_SELL && primarySignal == SIG_BUY && trendFilter == SIG_BUY)
            OpenPrimaryOrder(ORDER_TYPE_BUY);
      }
   }

   if(ShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| GET PRIMARY ENTRY SIGNAL (Ichimoku OR Stochastic)               |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetPrimaryEntrySignal()
{
   // ── Ichimoku: Tenkan crosses Kijun ───────────────────────────
   double tenkan_curr[], tenkan_prev[], kijun_curr[], kijun_prev[];
   ArraySetAsSeries(tenkan_curr, true);
   ArraySetAsSeries(tenkan_prev, true);
   ArraySetAsSeries(kijun_curr,  true);
   ArraySetAsSeries(kijun_prev,  true);

   if(CopyBuffer(h_Ichimoku, 0, Ichimoku_Shift,   1, tenkan_curr) < 1) return SIG_NONE;
   if(CopyBuffer(h_Ichimoku, 0, Ichimoku_Shift+1, 1, tenkan_prev) < 1) return SIG_NONE;
   if(CopyBuffer(h_Ichimoku, 1, Ichimoku_Shift,   1, kijun_curr)  < 1) return SIG_NONE;
   if(CopyBuffer(h_Ichimoku, 1, Ichimoku_Shift+1, 1, kijun_prev)  < 1) return SIG_NONE;

   SIGNAL_TYPE ichimokuSig = SIG_NONE;
   // Tenkan crosses Kijun upward = BUY
   if(tenkan_prev[0] <= kijun_prev[0] && tenkan_curr[0] > kijun_curr[0])
      ichimokuSig = SIG_BUY;
   // Tenkan crosses Kijun downward = SELL
   else if(tenkan_prev[0] >= kijun_prev[0] && tenkan_curr[0] < kijun_curr[0])
      ichimokuSig = SIG_SELL;

   // ── Stochastic: %K crosses Buy/Sell level ────────────────────
   double stoch_k_curr[], stoch_k_prev[];
   ArraySetAsSeries(stoch_k_curr, true);
   ArraySetAsSeries(stoch_k_prev, true);

   if(CopyBuffer(h_Stoch, 0, Stoch_Shift,   1, stoch_k_curr) < 1) return SIG_NONE;
   if(CopyBuffer(h_Stoch, 0, Stoch_Shift+1, 1, stoch_k_prev) < 1) return SIG_NONE;

   SIGNAL_TYPE stochSig = SIG_NONE;
   // %K crosses above BuyLevel = BUY
   if(stoch_k_prev[0] <= Stoch_BuyLevel && stoch_k_curr[0] > Stoch_BuyLevel)
      stochSig = SIG_BUY;
   // %K crosses below SellLevel = SELL
   else if(stoch_k_prev[0] >= Stoch_SellLevel && stoch_k_curr[0] < Stoch_SellLevel)
      stochSig = SIG_SELL;

   // OR logic: either signal is valid
   if(ichimokuSig != SIG_NONE) return ichimokuSig;
   if(stochSig != SIG_NONE)    return stochSig;

   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| GET TREND FILTER (RSI AND Parabolic SAR)                        |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetTrendFilter()
{
   // RSI above/below 50
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(h_RSI_Filter, 0, RSI_Shift, 1, rsi) < 1) return SIG_NONE;

   SIGNAL_TYPE rsiTrend = SIG_NONE;
   if(rsi[0] > RSI_TrendLevel)      rsiTrend = SIG_BUY;
   else if(rsi[0] < RSI_TrendLevel) rsiTrend = SIG_SELL;

   // Parabolic SAR trend
   double sar[];
   ArraySetAsSeries(sar, true);
   if(CopyBuffer(h_SAR, 0, SAR_Shift, 1, sar) < 1) return SIG_NONE;

   double closePrice = iClose(_Symbol, PERIOD_CURRENT, SAR_Shift);
   SIGNAL_TYPE sarTrend = SIG_NONE;
   if(sar[0] < closePrice) sarTrend = SIG_BUY;   // SAR below price = uptrend
   else                    sarTrend = SIG_SELL;   // SAR above price = downtrend

   // AND logic: both must agree
   if(rsiTrend == SIG_BUY  && sarTrend == SIG_BUY)  return SIG_BUY;
   if(rsiTrend == SIG_SELL && sarTrend == SIG_SELL) return SIG_SELL;

   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| GET HEDGE ENTRY SIGNAL (Bollinger Bands midline)                |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetHedgeEntrySignal()
{
   double bbMid[];
   ArraySetAsSeries(bbMid, true);
   if(CopyBuffer(h_BB, 0, BB_CandleShift, 1, bbMid) < 1) return SIG_NONE;

   double closePrice = iClose(_Symbol, PERIOD_CURRENT, BB_CandleShift);

   // Candle closes above midline = BUY signal for hedge
   if(closePrice > bbMid[0]) return SIG_BUY;
   // Candle closes below midline = SELL signal for hedge
   if(closePrice < bbMid[0]) return SIG_SELL;

   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| CHECK EXIT SIGNALS (RSI crossing levels)                        |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   double rsi_curr[], rsi_prev[];
   ArraySetAsSeries(rsi_curr, true);
   ArraySetAsSeries(rsi_prev, true);
   if(CopyBuffer(h_RSI_Exit, 0, RSI_Exit_Shift,   1, rsi_curr) < 1) return;
   if(CopyBuffer(h_RSI_Exit, 0, RSI_Exit_Shift+1, 1, rsi_prev) < 1) return;

   // RSI crosses above sell level = close BUY positions (if profitable)
   bool rsiCrossAboveSell = (rsi_prev[0] <= RSI_ExitSellLevel && rsi_curr[0] > RSI_ExitSellLevel);
   // RSI crosses below buy level = close SELL positions (if profitable)
   bool rsiCrossBelowBuy  = (rsi_prev[0] >= RSI_ExitBuyLevel  && rsi_curr[0] < RSI_ExitBuyLevel);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;

      double profit = PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();

      if(PosInfo.PositionType() == POSITION_TYPE_BUY && rsiCrossAboveSell && profit > 0)
         Trade.PositionClose(PosInfo.Ticket());
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL && rsiCrossBelowBuy && profit > 0)
         Trade.PositionClose(PosInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| OPEN PRIMARY ORDER                                               |
//+------------------------------------------------------------------+
void OpenPrimaryOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR();
   if(atr <= 0) return;

   double sl_distance = atr * ATR_SL_Coef;
   double tp_distance = sl_distance * RR_Ratio;

   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = price - sl_distance;
      tp = price + tp_distance;
   }
   else
   {
      sl = price + sl_distance;
      tp = price - tp_distance;
   }

   // Normalize
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double volume = CalcDynamicVolume(sl_distance, RiskPerOrder);
   if(volume <= 0) return;

   string comment = TradeComment + "_PRI";
   Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, comment);
}

//+------------------------------------------------------------------+
//| OPEN HEDGE ORDER                                                 |
//+------------------------------------------------------------------+
void OpenHedgeOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR();
   if(atr <= 0) return;

   double sl_distance = atr * HedgeATR_SL_Coef;
   double tp_distance = sl_distance * HedgeRR_Ratio;

   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = price - sl_distance;
      tp = price + tp_distance;
   }
   else
   {
      sl = price + sl_distance;
      tp = price - tp_distance;
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double volume = CalcDynamicVolume(sl_distance, HedgeRiskPerOrder);
   if(volume <= 0) return;

   string comment = TradeComment + "_HDG";
   Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, comment);
}

//+------------------------------------------------------------------+
//| CALCULATE DYNAMIC VOLUME                                         |
//+------------------------------------------------------------------+
double CalcDynamicVolume(double sl_distance_price, double riskPct)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPct / 100.0;

   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0 || tickValue <= 0 || sl_distance_price <= 0) return 0;

   double slInTicks  = sl_distance_price / tickSize;
   double volume     = riskAmount / (slInTicks * tickValue);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   volume = MathMax(minLot, MathMin(maxLot, MathRound(volume / lotStep) * lotStep));
   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| GET ATR VALUE                                                    |
//+------------------------------------------------------------------+
double GetATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR, 0, 1, 1, atr) < 1) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| MANAGE TRAILING STOPS & BREAKEVEN                               |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;

      ulong  ticket     = PosInfo.Ticket();
      double openPrice  = PosInfo.PriceOpen();
      double currentSL  = PosInfo.StopLoss();
      double currentTP  = PosInfo.TakeProfit();
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool isHedge = (StringFind(PosInfo.Comment(), "_HDG") >= 0);

      if(PosInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double tpDist    = currentTP - openPrice;
         double pctNeeded = isHedge ? (HedgeBreakevenPct / 100.0) : (TrailingStopPct / 100.0);
         double activation= openPrice + tpDist * pctNeeded;

         if(currentBid >= activation)
         {
            if(isHedge)
            {
               // Breakeven: move SL to open price
               double newSL = NormalizeDouble(openPrice, _Digits);
               if(newSL > currentSL + _Point)
                  Trade.PositionModify(ticket, newSL, currentTP);
            }
            else
            {
               // Trailing: move SL proportionally
               double trailSL = NormalizeDouble(currentBid - (currentTP - openPrice) * (1.0 - TrailingStopPct / 100.0), _Digits);
               if(trailSL > currentSL + _Point)
                  Trade.PositionModify(ticket, trailSL, currentTP);
            }
         }
      }
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double tpDist    = openPrice - currentTP;
         double pctNeeded = isHedge ? (HedgeBreakevenPct / 100.0) : (TrailingStopPct / 100.0);
         double activation= openPrice - tpDist * pctNeeded;

         if(currentAsk <= activation)
         {
            if(isHedge)
            {
               double newSL = NormalizeDouble(openPrice, _Digits);
               if(newSL < currentSL - _Point || currentSL == 0)
                  Trade.PositionModify(ticket, newSL, currentTP);
            }
            else
            {
               double trailSL = NormalizeDouble(currentAsk + (openPrice - currentTP) * (1.0 - TrailingStopPct / 100.0), _Digits);
               if(trailSL < currentSL - _Point || currentSL == 0)
                  Trade.PositionModify(ticket, trailSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| COUNT PRIMARY ORDERS                                             |
//+------------------------------------------------------------------+
int CountPrimaryOrders()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_PRI") >= 0) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| COUNT HEDGE ORDERS                                               |
//+------------------------------------------------------------------+
int CountHedgeOrders()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_HDG") >= 0) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| GET LAST PRIMARY DIRECTION                                       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE GetLastPrimaryDirection()
{
   datetime latestTime = 0;
   ENUM_ORDER_TYPE dir = ORDER_TYPE_BUY;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_PRI") < 0) continue;
      if(PosInfo.Time() >= latestTime)
      {
         latestTime = PosInfo.Time();
         dir = (PosInfo.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      }
   }
   return dir;
}

//+------------------------------------------------------------------+
//| GET LAST HEDGE DIRECTION                                         |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE GetLastHedgeDirection()
{
   datetime latestTime = 0;
   ENUM_ORDER_TYPE dir = ORDER_TYPE_SELL;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_HDG") < 0) continue;
      if(PosInfo.Time() >= latestTime)
      {
         latestTime = PosInfo.Time();
         dir = (PosInfo.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      }
   }
   return dir;
}

//+------------------------------------------------------------------+
//| IS WITHIN TRADING HOURS                                         |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Check day of week
   switch(dt.day_of_week)
   {
      case 1: if(!TradeMonday)    return false; break;
      case 2: if(!TradeTuesday)   return false; break;
      case 3: if(!TradeWednesday) return false; break;
      case 4: if(!TradeThursday)  return false; break;
      case 5: if(!TradeFriday)    return false; break;
      default: return false; // Weekend
   }

   // Check hour/minute
   int currentMins = dt.hour * 60 + dt.min;
   int startMins   = TradingStartHour * 60 + TradingStartMin;
   int endMins     = TradingEndHour   * 60 + TradingEndMin;

   return (currentMins >= startMins && currentMins < endMins);
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| CHECK DAILY LIMITS                                               |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(UseDailyProfitLimit)
   {
      double dailyProfit    = equity - DailyStartBalance;
      double profitTarget   = DailyStartBalance * DailyProfitPct / 100.0;
      if(dailyProfit >= profitTarget)
      {
         if(!DailyLimitReached)
         {
            Print("Daily profit target reached: ", DoubleToString(dailyProfit, 2));
            if(UseMaxProfitClose) CloseAllPositions();
         }
         DailyLimitReached = true;
         return true;
      }
   }

   if(UseDailyLossLimit)
   {
      double dailyLoss    = DailyStartBalance - equity;
      double lossLimit    = DailyStartBalance * DailyLossPct / 100.0;
      if(dailyLoss >= lossLimit)
      {
         if(!DailyLimitReached)
         {
            Print("Daily loss limit reached: ", DoubleToString(dailyLoss, 2));
            if(UseMaxLossClose) CloseAllPositions();
         }
         DailyLimitReached = true;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      Trade.PositionClose(PosInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| GET TOTAL FLOATING P&L                                          |
//+------------------------------------------------------------------+
double GetTotalFloatingPL()
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      total += PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();
   }
   return total;
}

//+------------------------------------------------------------------+
//| ═══════════════════ DASHBOARD ══════════════════════════════════ |
//+------------------------------------------------------------------+

void CreateDashboard()
{
   // Background rectangle
   string bgName = ObjPrefix + "BG";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DashX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DashY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 230);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 320);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, DashBGColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'40,40,60');
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);

   CreateLabel("TITLE",    "⬡ PEAK RANGE HEDGING",          DashX+10, DashY+8,   12, C'100,200,255', true);
   CreateLabel("SEP1",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━",    DashX+8,  DashY+26,  8,  C'50,50,80');

   CreateLabel("LBL_SYMBOL",  "Symbol: --",     DashX+10, DashY+38,  9, DashTextColor);
   CreateLabel("LBL_SPREAD",  "Spread: --",     DashX+10, DashY+52,  9, DashTextColor);
   CreateLabel("LBL_TF",      "TimeFrame: --",  DashX+10, DashY+66,  9, DashTextColor);

   CreateLabel("SEP2",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━",    DashX+8,  DashY+80,  8,  C'50,50,80');

   CreateLabel("LBL_PORDERS", "Primary: 0",     DashX+10, DashY+92,  9, DashTextColor);
   CreateLabel("LBL_HORDERS", "Hedge:   0",     DashX+10, DashY+106, 9, DashTextColor);
   CreateLabel("LBL_CYCLES",  "Cycles:  0/20",  DashX+10, DashY+120, 9, DashTextColor);

   CreateLabel("SEP3",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━",    DashX+8,  DashY+134, 8,  C'50,50,80');

   CreateLabel("LBL_EQUITY",  "Equity:  --",    DashX+10, DashY+146, 9, DashTextColor);
   CreateLabel("LBL_MARGIN",  "Margin:  --",    DashX+10, DashY+160, 9, DashTextColor);
   CreateLabel("LBL_PL",      "Float P/L: --",  DashX+10, DashY+174, 9, DashTextColor);

   CreateLabel("SEP4",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━",    DashX+8,  DashY+188, 8,  C'50,50,80');

   CreateLabel("LBL_SIGNAL",  "Signal:  --",    DashX+10, DashY+200, 9, DashTextColor);
   CreateLabel("LBL_TREND",   "Trend:   --",    DashX+10, DashY+214, 9, DashTextColor);
   CreateLabel("LBL_STATUS",  "Status:  ACTIVE", DashX+10, DashY+228, 9, clrLime);

   CreateLabel("SEP5",     "━━━━━━━━━━━━━━━━━━━━━━━━━━━",    DashX+8,  DashY+242, 8,  C'50,50,80');

   CreateLabel("LBL_HOURS",   "Hours: 12:00-22:00", DashX+10, DashY+254, 8, C'150,150,200');
   CreateLabel("LBL_LIMIT",   "Daily Limit: OK",    DashX+10, DashY+268, 8, clrLime);
   CreateLabel("LBL_MAGIC",   StringFormat("Magic: %d", MagicNumber), DashX+10, DashY+284, 7, C'80,80,120');

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

   // Symbol & market info
   UpdateLabel("LBL_SYMBOL",  StringFormat("Symbol:  %s", _Symbol));
   UpdateLabel("LBL_SPREAD",  StringFormat("Spread:  %d pts", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   UpdateLabel("LBL_TF",      StringFormat("TF:      %s", PeriodToString(PERIOD_CURRENT)));

   // Positions
   int pri = CountPrimaryOrders();
   int hdg = CountHedgeOrders();
   UpdateLabel("LBL_PORDERS", StringFormat("Primary: %d", pri));
   UpdateLabel("LBL_HORDERS", StringFormat("Hedge:   %d", hdg));
   UpdateLabel("LBL_CYCLES",  StringFormat("Cycles:  %d/%d", DailyCycles, MaxRangeCyclesDay));

   // Account
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin  = AccountInfoDouble(ACCOUNT_MARGIN);
   double floatPL = GetTotalFloatingPL();
   string currency= AccountInfoString(ACCOUNT_CURRENCY);
   color plColor  = (floatPL >= 0) ? clrLime : clrOrangeRed;
   UpdateLabel("LBL_EQUITY",  StringFormat("Equity:  %.2f %s", equity, currency));
   UpdateLabel("LBL_MARGIN",  StringFormat("Margin:  %.2f %s", margin, currency));
   UpdateLabel("LBL_PL",      StringFormat("Float:   %+.2f %s", floatPL, currency), plColor);

   // Signals
   SIGNAL_TYPE sig   = GetPrimaryEntrySignal();
   SIGNAL_TYPE trend = GetTrendFilter();

   string sigStr   = (sig == SIG_BUY) ? "BUY ▲" : (sig == SIG_SELL) ? "SELL ▼" : "NONE";
   color  sigColor = (sig == SIG_BUY) ? DashBuyColor : (sig == SIG_SELL) ? DashSellColor : DashTextColor;
   string trendStr = (trend == SIG_BUY) ? "UP ▲" : (trend == SIG_SELL) ? "DOWN ▼" : "MIXED";
   color  trendClr = (trend == SIG_BUY) ? DashBuyColor : (trend == SIG_SELL) ? DashSellColor : clrGold;

   UpdateLabel("LBL_SIGNAL", StringFormat("Signal:  %s", sigStr),   sigColor);
   UpdateLabel("LBL_TREND",  StringFormat("Trend:   %s", trendStr), trendClr);

   bool inHours = IsTradeAllowed();
   string statusStr = DailyLimitReached ? "LIMIT HIT" : inHours ? "ACTIVE" : "OUT OF HOURS";
   color  statusClr = DailyLimitReached ? clrOrangeRed : inHours ? clrLime : clrGold;
   UpdateLabel("LBL_STATUS", StringFormat("Status:  %s", statusStr), statusClr);

   // Limit status
   string limitStr = DailyLimitReached ? "Daily Limit: REACHED" : "Daily Limit: OK";
   color  limitClr = DailyLimitReached ? clrOrangeRed : clrLime;
   UpdateLabel("LBL_LIMIT", limitStr, limitClr);

   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, ObjPrefix);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| PERIOD TO STRING HELPER                                          |
//+------------------------------------------------------------------+
string PeriodToString(ENUM_TIMEFRAMES period)
{
   switch(period)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "Current";
   }
}
//+------------------------------------------------------------------+
//| END OF EA                                                        |
//+------------------------------------------------------------------+
