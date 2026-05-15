//+------------------------------------------------------------------+
//|                                      PeakRangeHedging_v2.0.mq5  |
//|                    Range Hedging EA — v2.0 Scientific Edition    |
//|                                                                  |
//|  CORRECCIONES v2.0 vs v1.1 (basadas en análisis científico):    |
//|                                                                  |
//|  BUGS CRÍTICOS CORREGIDOS (P0):                                  |
//|  [B1] ORDER_FILLING auto-detectado por símbolo (no IOC fijo)    |
//|  [B2] Handles RSI separados: h_RSI_Filter(14) h_RSI_Exit(21)   |
//|       → períodos distintos = handles distintos = buffers reales  |
//|  [B3] DailyCycles++ solo si PositionOpen() retorna true         |
//|  [B8] Eliminado #include <Indicators\Trend.mqh> (no usado)      |
//|                                                                  |
//|  BUGS GRAVES CORREGIDOS (P1):                                    |
//|  [B4] Trailing stop fórmula correcta: distancia fija del precio  |
//|       proporcional al ATR, no inversión de porcentaje            |
//|  [B5] Daily limits: balance vs balance (no equity vs balance)   |
//|  [B6] Máquina de estados explícita 4 estados — elimina segunda  |
//|       primaria incontrolada con hedge abierto                    |
//|                                                                  |
//|  BUGS MODERADOS CORREGIDOS (P2):                                 |
//|  [B7] Hedge signal: BB cruce real + BB width filter (no midline  |
//|       puro que siempre es activo)                                |
//|  [B9] CopyBuffer con count=2 en un solo array (eficiente)       |
//|  [B10] ManageTrailing verifica TP > 0 antes de calcular         |
//|                                                                  |
//|  MEJORAS ARQUITECTÓNICAS (basadas en análisis estadístico):      |
//|  [M1] Stack de señal nuevo: MACD(12,26,9) + EMA(9,21) en M1    |
//|  [M2] Ancla estructural H1: EMA(200) define régimen alcista/     |
//|       bajista — aislado del loop M1, evaluado 1x/hora           |
//|  [M3] Filtro de régimen: Volatility Ratio ATR(14)/ATR_SMA(20)  |
//|       evita trades en mercado choppy (causa del -$1272 drawdown) |
//|  [M4] CalcDynamicVolume usa EQUITY (no balance) para sizing     |
//|       correcto en drawdown flotante (Carver, Systematic Trading) |
//|  [M5] Cierre forzado de sesión a las 21:45 — elimina riesgo de  |
//|       gaps overnight en XAUUSD                                   |
//|  [M6] Verificación de retorno de PositionOpen()                 |
//|  [M7] RSI Exit con período distinto (21) para evitar handle      |
//|       compartido y dar señal de salida más amplia                |
//+------------------------------------------------------------------+
#property copyright "Peak Range Hedging EA v2.0"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum SIGNAL_TYPE  { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = -1 };

// Máquina de estados explícita [FIX B6]
enum EA_STATE
{
   STATE_IDLE         = 0,   // Sin posiciones — buscando entrada primaria
   STATE_PRIMARY_OPEN = 1,   // 1 primaria abierta — buscando señal de hedge
   STATE_HEDGED       = 2,   // Primaria + hedge abiertos — esperar cierre
   STATE_HEDGE_ONLY   = 3    // Solo hedge abierto — esperar cierre
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// ── Step 1: Primary Order Settings ───────────────────────────────
input group "=== STEP 1: PRIMARY ORDER SETTINGS ==="
input int      MaxOrders           = 20;       // Max total orders (primary + hedge)
input double   RiskPerOrder        = 0.5;      // Risk per primary order (% of equity)
input double   ATR_SL_Coef         = 1.5;      // ATR multiplier for Stop Loss
input double   RR_Ratio            = 1.5;      // Risk/Reward ratio (TP = SL x Coef)
input double   TrailingDistCoef    = 0.75;     // Trailing SL = TrailingDistCoef x ATR from price
input double   TrailingActivatePct = 50.0;     // Activate trailing when % of TP distance reached

input group "=== STEP 1: HEDGE ORDER SETTINGS ==="
input double   HedgeRiskPerOrder   = 0.125;    // Risk per hedge order (% of equity)
input double   HedgeATR_SL_Coef    = 1.5;      // ATR multiplier for Hedge SL
input double   HedgeRR_Ratio       = 1.5;      // Hedge TP = SL x Coef
input double   HedgeBreakevenPct   = 50.0;     // Breakeven activation (% of TP distance)

// ── Step 2: Trade Management ─────────────────────────────────────
input group "=== STEP 2: TRADE MANAGEMENT ==="
input bool     UseMaxProfitClose   = false;    // Close all at max profit?
input bool     UseMaxLossClose     = false;    // Close all at max loss?
input bool     UseDailyProfitLimit = true;     // Use daily profit limit?
input double   DailyProfitPct      = 10.0;     // Daily profit limit (% of balance) [FIX B5]
input bool     UseDailyLossLimit   = true;     // Use daily loss limit?
input double   DailyLossPct        = 2.0;      // Daily loss limit (% of balance) [FIX B5]
input int      MaxRangeCyclesDay   = 20;       // Max primary order cycles per day
input bool     ForceCloseEOD       = true;     // Force close all positions at EOD [M5]
input int      ForceCloseHour      = 21;       // EOD close hour (server time)
input int      ForceCloseMin       = 45;       // EOD close minute

// ── Signal Confirmation ───────────────────────────────────────────
input group "=== v2.0: SIGNAL CONFIRMATION ==="
input bool     RequireCandleConfirm = true;    // Candle body must confirm direction
input int      CooldownBars         = 3;       // Min bars cooldown after any close
input int      MaxConsecLosses      = 3;       // Pause after N consecutive losses (0=off)
input int      ConsecLossPauseBars  = 10;      // Bars to pause after max consec losses

// ── Quality Filters ───────────────────────────────────────────────
input group "=== v2.0: QUALITY FILTERS ==="
input double   MaxSpreadPoints      = 80.0;    // Max spread in points (0=disabled)
input double   VolatilityRatioMin   = 0.7;     // Min ATR/ATR_SMA ratio (0=disabled) [M3]
input double   VolatilityRatioMax   = 2.0;     // Max ATR/ATR_SMA ratio (0=disabled) [M3]
input int      VolatilityRatioLook  = 20;      // Lookback bars for ATR_SMA in ratio filter

// ── Partial Close ─────────────────────────────────────────────────
input group "=== v2.0: PARTIAL CLOSE ==="
input bool     UsePartialClose      = true;    // Enable partial close
input double   PartialClosePct      = 50.0;    // % of volume to close
input double   PartialTriggerPct    = 50.0;    // Trigger at % of TP distance

// ── v2.0 Signal Stack: MACD + EMA ────────────────────────────────
input group "=== STEP 3: MACD ENTRY SIGNAL (M1) ==="
input int      MACD_Fast            = 12;      // MACD fast EMA period
input int      MACD_Slow            = 26;      // MACD slow EMA period
input int      MACD_Signal          = 9;       // MACD signal period
input int      MACD_Shift           = 1;       // Candle shift (1 = closed bar)

input group "=== STEP 3: EMA CONFIRMATION (M1) ==="
input int      EMA9_Period          = 9;       // EMA short period (momentum)
input int      EMA21_Period         = 21;      // EMA medium period (entry/exit)
input int      EMA_Shift            = 1;       // Candle shift

input group "=== STEP 3: TREND FILTER H1 — EMA200 ==="
input int      EMA200_Period        = 200;     // EMA long period (regime filter H1) [M2]
input bool     UseH1RegimeFilter    = true;    // Enable H1 EMA200 regime filter
input int      H1EMA_CandleShift    = 1;       // H1 candle shift

input group "=== STEP 3: TREND FILTER M1 — RSI + SAR ==="
input int      RSI_Period           = 14;      // RSI period (trend filter M1)
input double   RSI_TrendLevel       = 50.0;    // RSI trend level
input int      RSI_Shift            = 1;       // Candle shift
input double   SAR_Step             = 0.02;    // Parabolic SAR step
input double   SAR_Maximum          = 0.2;     // Parabolic SAR maximum
input int      SAR_Shift            = 1;       // Candle shift

input group "=== STEP 3: EXIT SIGNAL — RSI ==="
input int      RSI_Exit_Period      = 21;      // RSI exit period (DIFFERENT from filter) [FIX B2]
input double   RSI_ExitSellLevel    = 70.0;    // RSI exit: close BUY above this
input double   RSI_ExitBuyLevel     = 30.0;    // RSI exit: close SELL below this
input int      RSI_Exit_Shift       = 1;       // Candle shift

// ── Step 4: Hedge Entry — Bollinger Bands ────────────────────────
input group "=== STEP 4: BOLLINGER BANDS (HEDGE ENTRY) ==="
input int      BB_Period            = 20;      // Bollinger Bands period
input double   BB_Deviations        = 2.0;     // Standard deviations
input int      BB_BandShift         = 0;       // Bands parameter shift
input int      BB_CandleShift       = 1;       // Candle shift for signal reading
input double   BB_WidthMinCoef      = 0.5;     // Min BB width as ratio of ATR (squeeze filter) [FIX B7]

// ── Step 5: Trading Hours ─────────────────────────────────────────
input group "=== STEP 5: TRADING HOURS & DAYS ==="
input int      TradingStartHour     = 12;      // Trading start hour (server time)
input int      TradingStartMin      = 0;       // Trading start minute
input int      TradingEndHour       = 22;      // Trading end hour (server time)
input int      TradingEndMin        = 0;       // Trading end minute
input bool     TradeMonday          = true;    // Trade on Monday
input bool     TradeTuesday         = true;    // Trade on Tuesday
input bool     TradeWednesday       = true;    // Trade on Wednesday
input bool     TradeThursday        = true;    // Trade on Thursday
input bool     TradeFriday          = true;    // Trade on Friday

// ── ATR ──────────────────────────────────────────────────────────
input group "=== ATR SETTINGS ==="
input int      ATR_Period           = 14;      // ATR period
input ENUM_TIMEFRAMES ATR_TF        = PERIOD_CURRENT; // ATR timeframe

// ── Dashboard ─────────────────────────────────────────────────────
input group "=== DASHBOARD ==="
input bool     ShowDashboard        = true;    // Show dashboard
input color    DashBGColor          = C'12,14,24';   // Dashboard background
input color    DashTextColor        = clrWhite;      // Text color
input color    DashBuyColor         = C'50,220,120'; // Buy color
input color    DashSellColor        = C'220,70,70';  // Sell color
input int      DashX                = 10;      // Dashboard X position
input int      DashY                = 30;      // Dashboard Y position

// ── General ───────────────────────────────────────────────────────
input group "=== GENERAL ==="
input long     MagicNumber          = 20250604; // EA Magic Number
input string   TradeComment         = "PeakRH"; // Trade comment

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         Trade;
CPositionInfo  PosInfo;

// Indicator handles
int h_MACD, h_EMA9, h_EMA21, h_EMA200_H1;
int h_RSI_Filter, h_SAR, h_RSI_Exit, h_BB, h_ATR;

// Time tracking
datetime LastBarTime       = 0;
datetime LastH1BarTime     = 0;   // For H1 regime filter [M2]
datetime LastDayReset      = 0;

// Daily management [FIX B5 — balance vs balance]
double   DailyStartBalance = 0;
int      DailyCycles       = 0;
bool     DailyLimitReached = false;
bool     EODClosed         = false;

// State machine [FIX B6]
EA_STATE CurrentState      = STATE_IDLE;

// Cooldown & streak
int      CooldownBarsLeft    = 0;
int      ConsecLossCount     = 0;
int      ConsecLossPauseLeft = 0;

// H1 regime cache — evaluated once per H1 bar [M2]
SIGNAL_TYPE H1Regime        = SIG_NONE;

// Partial close tracking
ulong    PartialClosedTickets[];

// Last known positions for closed-position detection
ulong    LastKnownTickets[];

// Dashboard object prefix
string   ObjPrefix          = "PRH20_";

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(30);

   // [FIX B1] Auto-detect filling mode supported by this symbol/broker
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      Trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      Trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // [M1] New signal stack: MACD + EMA
   h_MACD       = iMACD(_Symbol, PERIOD_CURRENT, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   h_EMA9       = iMA(_Symbol, PERIOD_CURRENT, EMA9_Period,  0, MODE_EMA, PRICE_CLOSE);
   h_EMA21      = iMA(_Symbol, PERIOD_CURRENT, EMA21_Period, 0, MODE_EMA, PRICE_CLOSE);

   // [M2] H1 regime filter
   h_EMA200_H1  = iMA(_Symbol, PERIOD_H1, EMA200_Period, 0, MODE_EMA, PRICE_CLOSE);

   // Trend filters (kept from original strategy)
   h_RSI_Filter = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period,      PRICE_CLOSE);  // period 14
   h_RSI_Exit   = iRSI(_Symbol, PERIOD_CURRENT, RSI_Exit_Period, PRICE_CLOSE);  // period 21 [FIX B2]
   h_SAR        = iSAR(_Symbol, PERIOD_CURRENT, SAR_Step, SAR_Maximum);
   h_BB         = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_BandShift, BB_Deviations, PRICE_CLOSE);
   h_ATR        = iATR(_Symbol, ATR_TF, ATR_Period);

   if(h_MACD==INVALID_HANDLE || h_EMA9==INVALID_HANDLE || h_EMA21==INVALID_HANDLE ||
      h_EMA200_H1==INVALID_HANDLE || h_RSI_Filter==INVALID_HANDLE || h_SAR==INVALID_HANDLE ||
      h_RSI_Exit==INVALID_HANDLE || h_BB==INVALID_HANDLE || h_ATR==INVALID_HANDLE)
   {
      Print("ERROR v2.0: Failed to create one or more indicator handles.");
      return INIT_FAILED;
   }

   ArrayResize(PartialClosedTickets, 0);
   ArrayResize(LastKnownTickets, 0);

   DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(ShowDashboard) CreateDashboard();
   Print("PeakRangeHedging v2.0 initialized. Symbol:", _Symbol, " Magic:", MagicNumber);
   Print("Filling mode set to: ", EnumToString((ENUM_ORDER_TYPE_FILLING)Trade.RequestTypeFilling()));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_MACD);    IndicatorRelease(h_EMA9);
   IndicatorRelease(h_EMA21);   IndicatorRelease(h_EMA200_H1);
   IndicatorRelease(h_RSI_Filter); IndicatorRelease(h_SAR);
   IndicatorRelease(h_RSI_Exit); IndicatorRelease(h_BB);  IndicatorRelease(h_ATR);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar   = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
   bool     isNewBar     = (currentBar   != LastBarTime);
   bool     isNewH1Bar   = (currentH1Bar != LastH1BarTime);

   // ── Per-tick: trailing + partial close ──────────────────────
   ManageTrailingStops();
   if(UsePartialClose) ManagePartialClose();

   // ── H1 bar: update regime cache ─────────────────────────────
   if(isNewH1Bar)
   {
      LastH1BarTime = currentH1Bar;
      if(UseH1RegimeFilter) UpdateH1Regime();
   }

   // ── M1 bar: all trading logic ────────────────────────────────
   if(!isNewBar)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }
   LastBarTime = currentBar;

   // Daily reset [FIX B5]
   CheckDailyReset();

   // Decrement cooldown counters
   if(CooldownBarsLeft    > 0) CooldownBarsLeft--;
   if(ConsecLossPauseLeft > 0) ConsecLossPauseLeft--;

   // Detect closed positions and update state machine
   CheckPositionsClosed();

   // Sync state machine with actual open positions
   SyncStateMachine();

   // EOD forced close [M5]
   if(ForceCloseEOD && ShouldForceCloseEOD())
   {
      if(!EODClosed)
      {
         CloseAllPositions();
         EODClosed = true;
         Print("v2.0: EOD forced close executed at ", TimeToString(TimeCurrent()));
      }
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   if(DailyLimitReached || !IsTradeAllowed() || CheckDailyLimits())
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   if(CooldownBarsLeft > 0 || ConsecLossPauseLeft > 0)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   if(!PassesQualityFilters())
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // Exit signals (RSI) — before entry logic
   CheckExitSignals();

   int totalOrders = CountAllOrders();
   if(totalOrders >= MaxOrders || DailyCycles >= MaxRangeCyclesDay)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // ── STATE MACHINE LOGIC [FIX B6] ────────────────────────────
   SIGNAL_TYPE entrySignal = GetPrimaryEntrySignal();
   SIGNAL_TYPE trendM1     = GetTrendFilterM1();
   SIGNAL_TYPE finalSignal = CombineSignals(entrySignal, trendM1);
   SIGNAL_TYPE hedgeSignal = GetHedgeEntrySignal();

   switch(CurrentState)
   {
      case STATE_IDLE:
         // Open primary order if signal + trend + H1 regime all agree
         if(finalSignal == SIG_BUY)
         {
            if(OpenPrimaryOrder(ORDER_TYPE_BUY))  // [FIX B3] check return
            {
               DailyCycles++;
               CurrentState = STATE_PRIMARY_OPEN;
            }
         }
         else if(finalSignal == SIG_SELL)
         {
            if(OpenPrimaryOrder(ORDER_TYPE_SELL)) // [FIX B3]
            {
               DailyCycles++;
               CurrentState = STATE_PRIMARY_OPEN;
            }
         }
         break;

      case STATE_PRIMARY_OPEN:
         // Wait for hedge signal in opposite direction
         if(hedgeSignal != SIG_NONE)
         {
            ENUM_ORDER_TYPE primDir = GetLastPrimaryDirection();
            if(primDir == ORDER_TYPE_BUY  && hedgeSignal == SIG_SELL)
            {
               if(OpenHedgeOrder(ORDER_TYPE_SELL)) CurrentState = STATE_HEDGED;
            }
            else if(primDir == ORDER_TYPE_SELL && hedgeSignal == SIG_BUY)
            {
               if(OpenHedgeOrder(ORDER_TYPE_BUY))  CurrentState = STATE_HEDGED;
            }
         }
         break;

      case STATE_HEDGED:
         // Wait for positions to close — no new entries
         // Transitions handled in SyncStateMachine()
         break;

      case STATE_HEDGE_ONLY:
         // Wait for hedge to close — no new entries
         // Transitions handled in SyncStateMachine()
         break;
   }

   if(ShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| SYNC STATE MACHINE WITH ACTUAL POSITIONS                        |
//+------------------------------------------------------------------+
void SyncStateMachine()
{
   int pri = CountPrimaryOrders();
   int hdg = CountHedgeOrders();

   if(pri == 0 && hdg == 0)      CurrentState = STATE_IDLE;
   else if(pri > 0 && hdg == 0)  CurrentState = STATE_PRIMARY_OPEN;
   else if(pri > 0 && hdg > 0)   CurrentState = STATE_HEDGED;
   else if(pri == 0 && hdg > 0)  CurrentState = STATE_HEDGE_ONLY;
}

//+------------------------------------------------------------------+
//| H1 REGIME UPDATE [M2]                                           |
//| Called once per H1 bar — cheap, isolates H1 from M1 loop       |
//+------------------------------------------------------------------+
void UpdateH1Regime()
{
   double ema200[1];
   ArraySetAsSeries(ema200, true);
   if(CopyBuffer(h_EMA200_H1, 0, H1EMA_CandleShift, 1, ema200) < 1)
   {
      H1Regime = SIG_NONE;
      return;
   }
   double h1Close = iClose(_Symbol, PERIOD_H1, H1EMA_CandleShift);
   if(h1Close > ema200[0])      H1Regime = SIG_BUY;   // Above 200 EMA = bullish regime
   else if(h1Close < ema200[0]) H1Regime = SIG_SELL;  // Below 200 EMA = bearish regime
   else                         H1Regime = SIG_NONE;
}

//+------------------------------------------------------------------+
//| PRIMARY ENTRY SIGNAL [M1] — MACD + EMA9/21 [M1]                |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetPrimaryEntrySignal()
{
   // ── MACD signal line crossover [FIX B9 — single CopyBuffer call]
   double macdMain[2], macdSig[2];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSig,  true);
   if(CopyBuffer(h_MACD, 0, MACD_Shift, 2, macdMain) < 2) return SIG_NONE;
   if(CopyBuffer(h_MACD, 1, MACD_Shift, 2, macdSig)  < 2) return SIG_NONE;

   // macdMain[0]=current, macdMain[1]=previous
   SIGNAL_TYPE macdSigType = SIG_NONE;
   if(macdMain[1] <= macdSig[1] && macdMain[0] > macdSig[0]) macdSigType = SIG_BUY;
   else if(macdMain[1] >= macdSig[1] && macdMain[0] < macdSig[0]) macdSigType = SIG_SELL;

   if(macdSigType == SIG_NONE) return SIG_NONE;

   // ── EMA9 vs EMA21 confirmation [FIX B9]
   double ema9[1], ema21[1];
   ArraySetAsSeries(ema9,  true);
   ArraySetAsSeries(ema21, true);
   if(CopyBuffer(h_EMA9,  0, EMA_Shift, 1, ema9)  < 1) return SIG_NONE;
   if(CopyBuffer(h_EMA21, 0, EMA_Shift, 1, ema21) < 1) return SIG_NONE;

   // EMA9 must be above EMA21 for BUY, below for SELL
   if(macdSigType == SIG_BUY  && ema9[0] <= ema21[0]) return SIG_NONE;
   if(macdSigType == SIG_SELL && ema9[0] >= ema21[0]) return SIG_NONE;

   // ── Candle body confirmation ─────────────────────────────────
   if(RequireCandleConfirm)
   {
      double candleOpen  = iOpen(_Symbol,  PERIOD_CURRENT, MACD_Shift);
      double candleClose = iClose(_Symbol, PERIOD_CURRENT, MACD_Shift);
      if(macdSigType == SIG_BUY  && candleClose <= candleOpen) return SIG_NONE;
      if(macdSigType == SIG_SELL && candleClose >= candleOpen) return SIG_NONE;
   }

   return macdSigType;
}

//+------------------------------------------------------------------+
//| TREND FILTER M1 — RSI + Parabolic SAR                          |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetTrendFilterM1()
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

   double closeM1 = iClose(_Symbol, PERIOD_CURRENT, SAR_Shift);
   SIGNAL_TYPE sarTrend = (sar[0] < closeM1) ? SIG_BUY : SIG_SELL;

   if(rsiTrend == SIG_BUY  && sarTrend == SIG_BUY)  return SIG_BUY;
   if(rsiTrend == SIG_SELL && sarTrend == SIG_SELL) return SIG_SELL;
   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| COMBINE SIGNALS: Entry + M1 Trend + H1 Regime [M2]             |
//+------------------------------------------------------------------+
SIGNAL_TYPE CombineSignals(SIGNAL_TYPE entry, SIGNAL_TYPE trendM1)
{
   if(entry == SIG_NONE) return SIG_NONE;

   // M1 trend filter
   if(trendM1 != SIG_NONE && trendM1 != entry) return SIG_NONE;

   // H1 regime filter [M2] — only skip if UseH1RegimeFilter=true AND regime conflicts
   if(UseH1RegimeFilter && H1Regime != SIG_NONE && H1Regime != entry) return SIG_NONE;

   return entry;
}

//+------------------------------------------------------------------+
//| HEDGE ENTRY SIGNAL — BB Crossover + Width Filter [FIX B7]      |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetHedgeEntrySignal()
{
   // Read BB mid, upper, lower
   double bbMid[2], bbUpper[1], bbLower[1];
   ArraySetAsSeries(bbMid,   true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   if(CopyBuffer(h_BB, 0, BB_CandleShift, 2, bbMid)   < 2) return SIG_NONE;
   if(CopyBuffer(h_BB, 1, BB_CandleShift, 1, bbUpper) < 1) return SIG_NONE;
   if(CopyBuffer(h_BB, 2, BB_CandleShift, 1, bbLower) < 1) return SIG_NONE;

   // [FIX B7] BB width filter — avoid signal during squeeze
   double bbWidth = bbUpper[0] - bbLower[0];
   double atr     = GetATR();
   if(atr > 0 && BB_WidthMinCoef > 0 && bbWidth < atr * BB_WidthMinCoef) return SIG_NONE;

   // Real crossover: price crosses midline (not just position above/below)
   double closeNow  = iClose(_Symbol, PERIOD_CURRENT, BB_CandleShift);
   double closePrev = iClose(_Symbol, PERIOD_CURRENT, BB_CandleShift + 1);

   // BUY hedge: price crosses above midline
   if(closePrev <= bbMid[1] && closeNow > bbMid[0]) return SIG_BUY;
   // SELL hedge: price crosses below midline
   if(closePrev >= bbMid[1] && closeNow < bbMid[0]) return SIG_SELL;

   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| EXIT SIGNALS — RSI(21) crossing levels [FIX B2]                |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   double rsiExit[2];
   ArraySetAsSeries(rsiExit, true);
   // [FIX B9] Single CopyBuffer call for 2 bars
   if(CopyBuffer(h_RSI_Exit, 0, RSI_Exit_Shift, 2, rsiExit) < 2) return;

   bool rsiCrossAboveSell = (rsiExit[1] <= RSI_ExitSellLevel && rsiExit[0] > RSI_ExitSellLevel);
   bool rsiCrossBelowBuy  = (rsiExit[1] >= RSI_ExitBuyLevel  && rsiExit[0] < RSI_ExitBuyLevel);

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
//| OPEN PRIMARY ORDER [FIX B3 — returns bool]                      |
//+------------------------------------------------------------------+
bool OpenPrimaryOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR();
   if(atr <= 0) return false;

   double sl_dist = atr * ATR_SL_Coef;
   double tp_dist = sl_dist * RR_Ratio;
   double price   = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist, _Digits);

   // [M4] Use equity for dynamic volume sizing
   double volume = CalcDynamicVolume(sl_dist, RiskPerOrder);
   if(volume <= 0) return false;

   bool result = Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, TradeComment + "_PRI");
   if(!result)
      Print("v2.0: OpenPrimaryOrder FAILED. Retcode:", Trade.ResultRetcode(), " ", Trade.ResultRetcodeDescription());
   return result;
}

//+------------------------------------------------------------------+
//| OPEN HEDGE ORDER [FIX B3 — returns bool]                        |
//+------------------------------------------------------------------+
bool OpenHedgeOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR();
   if(atr <= 0) return false;

   double sl_dist = atr * HedgeATR_SL_Coef;
   double tp_dist = sl_dist * HedgeRR_Ratio;
   double price   = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist, _Digits);

   double volume = CalcDynamicVolume(sl_dist, HedgeRiskPerOrder);
   if(volume <= 0) return false;

   bool result = Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, TradeComment + "_HDG");
   if(!result)
      Print("v2.0: OpenHedgeOrder FAILED. Retcode:", Trade.ResultRetcode(), " ", Trade.ResultRetcodeDescription());
   return result;
}

//+------------------------------------------------------------------+
//| DYNAMIC VOLUME [M4 — uses EQUITY, not balance]                  |
//+------------------------------------------------------------------+
double CalcDynamicVolume(double sl_price_dist, double riskPct)
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);  // [M4] equity not balance
   double riskAmt   = equity * riskPct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0 || sl_price_dist <= 0) return 0;
   double slInTicks = sl_price_dist / tickSize;
   double volume    = riskAmt / (slInTicks * tickValue);
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
//| QUALITY FILTERS [M3 — Volatility Ratio]                         |
//+------------------------------------------------------------------+
bool PassesQualityFilters()
{
   // Spread filter
   if(MaxSpreadPoints > 0)
   {
      long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spreadPts > (long)MaxSpreadPoints) return false;
   }

   // [M3] Volatility Ratio filter: ATR(14) / SMA(ATR, 20)
   if(VolatilityRatioMin > 0 || VolatilityRatioMax > 0)
   {
      double currentATR = GetATR();
      if(currentATR > 0)
      {
         double atrHistory[];
         ArraySetAsSeries(atrHistory, true);
         if(CopyBuffer(h_ATR, 0, 1, VolatilityRatioLook, atrHistory) >= VolatilityRatioLook)
         {
            double atrSum = 0;
            for(int i = 0; i < VolatilityRatioLook; i++) atrSum += atrHistory[i];
            double atrSMA = atrSum / VolatilityRatioLook;
            if(atrSMA > 0)
            {
               double vRatio = currentATR / atrSMA;
               if(VolatilityRatioMin > 0 && vRatio < VolatilityRatioMin) return false; // Too quiet
               if(VolatilityRatioMax > 0 && vRatio > VolatilityRatioMax) return false; // Too explosive
            }
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| TRAILING STOPS [FIX B4 + FIX B10]                               |
//| Fixed formula: trail at ATR*coef distance from current price    |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   double atr = GetATR();
   if(atr <= 0) return;

   double trailDist = atr * TrailingDistCoef;

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

      // [FIX B10] Guard against TP = 0
      if(currentTP == 0) continue;

      if(PosInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double tpDist    = currentTP - openPrice;
         double activation= openPrice + tpDist * (TrailingActivatePct / 100.0);

         if(bid >= activation)
         {
            double newSL;
            if(isHedge)
               newSL = NormalizeDouble(openPrice, _Digits); // Breakeven for hedge
            else
               newSL = NormalizeDouble(bid - trailDist, _Digits); // [FIX B4] ATR-based trail

            if(newSL > currentSL + _Point && newSL < bid) // must be below current price
               Trade.PositionModify(ticket, newSL, currentTP);
         }
      }
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double tpDist    = openPrice - currentTP;
         double activation= openPrice - tpDist * (TrailingActivatePct / 100.0);

         if(ask <= activation)
         {
            double newSL;
            if(isHedge)
               newSL = NormalizeDouble(openPrice, _Digits); // Breakeven for hedge
            else
               newSL = NormalizeDouble(ask + trailDist, _Digits); // [FIX B4] ATR-based trail

            if((currentSL == 0 || newSL < currentSL - _Point) && newSL > ask) // must be above price
               Trade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PARTIAL CLOSE                                                    |
//+------------------------------------------------------------------+
void ManagePartialClose()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;

      ulong ticket = PosInfo.Ticket();
      bool  done   = false;
      for(int k = 0; k < ArraySize(PartialClosedTickets); k++)
         if(PartialClosedTickets[k] == ticket) { done = true; break; }
      if(done) continue;

      double openPrice = PosInfo.PriceOpen();
      double tp        = PosInfo.TakeProfit();
      if(tp == 0) continue; // [FIX B10]

      double tpDist  = MathAbs(tp - openPrice);
      double trigger = tpDist * (PartialTriggerPct / 100.0);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool triggered = false;
      if(PosInfo.PositionType() == POSITION_TYPE_BUY  && bid >= openPrice + trigger) triggered = true;
      if(PosInfo.PositionType() == POSITION_TYPE_SELL && ask <= openPrice - trigger) triggered = true;

      if(triggered)
      {
         double vol     = PosInfo.Volume();
         double closeVol= NormalizeDouble(vol * (PartialClosePct / 100.0), 2);
         double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         closeVol       = MathMax(minLot, MathRound(closeVol / lotStep) * lotStep);
         if(closeVol < vol)
         {
            Trade.PositionClosePartial(ticket, closeVol);
            int sz = ArraySize(PartialClosedTickets);
            ArrayResize(PartialClosedTickets, sz + 1);
            PartialClosedTickets[sz] = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DETECT CLOSED POSITIONS — update streak & cooldown              |
//+------------------------------------------------------------------+
void CheckPositionsClosed()
{
   // Build current ticket list
   ulong currentTickets[];
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      ArrayResize(currentTickets, n + 1);
      currentTickets[n++] = PosInfo.Ticket();
   }

   bool anyClose = false;
   for(int j = 0; j < ArraySize(LastKnownTickets); j++)
   {
      bool stillOpen = false;
      for(int k = 0; k < n; k++)
         if(currentTickets[k] == LastKnownTickets[j]) { stillOpen = true; break; }

      if(!stillOpen)
      {
         anyClose = true;
         // Check history for profit/loss
         if(HistorySelectByPosition(LastKnownTickets[j]))
         {
            double totalProfit = 0;
            for(int d = 0; d < HistoryDealsTotal(); d++)
            {
               ulong dealTicket = HistoryDealGetTicket(d);
               if(dealTicket == 0) continue;
               if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == (long)LastKnownTickets[j])
                  totalProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            }
            if(totalProfit < 0)
            {
               ConsecLossCount++;
               if(MaxConsecLosses > 0 && ConsecLossCount >= MaxConsecLosses)
               {
                  ConsecLossPauseLeft = ConsecLossPauseBars;
                  ConsecLossCount     = 0;
                  Print("v2.0: Max consec losses reached. Pausing ", ConsecLossPauseBars, " bars.");
               }
            }
            else
               ConsecLossCount = 0;
         }
      }
   }

   if(anyClose) CooldownBarsLeft = CooldownBars;

   // Snapshot current tickets
   ArrayResize(LastKnownTickets, n);
   for(int i = 0; i < n; i++) LastKnownTickets[i] = currentTickets[i];
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

int CountAllOrders()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() == _Symbol && PosInfo.Magic() == MagicNumber) count++;
   }
   return count;
}

ENUM_ORDER_TYPE GetLastPrimaryDirection()
{
   datetime latest = 0;
   ENUM_ORDER_TYPE dir = ORDER_TYPE_BUY;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), "_PRI") < 0) continue;
      if(PosInfo.Time() >= latest)
      {
         latest = PosInfo.Time();
         dir = (PosInfo.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      }
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

bool ShouldForceCloseEOD()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int cur     = dt.hour * 60 + dt.min;
   int eodTime = ForceCloseHour * 60 + ForceCloseMin;
   return (cur >= eodTime && cur < eodTime + 60); // Window of 60 minutes after trigger
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
      DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE); // [FIX B5] use balance
      DailyLimitReached = false;
      EODClosed         = false;
      H1Regime          = SIG_NONE; // Reset H1 cache on new day
      Print("v2.0: Daily reset. Balance: ", DailyStartBalance);
   }
}

// [FIX B5] Compare balance vs balance (not equity vs balance)
bool CheckDailyLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(UseDailyProfitLimit)
   {
      double balanceGain = currentBalance - DailyStartBalance;
      if(balanceGain >= DailyStartBalance * DailyProfitPct / 100.0)
      {
         if(!DailyLimitReached && UseMaxProfitClose) CloseAllPositions();
         DailyLimitReached = true;
         return true;
      }
   }
   if(UseDailyLossLimit)
   {
      double balanceLoss = DailyStartBalance - currentBalance;
      if(balanceLoss >= DailyStartBalance * DailyLossPct / 100.0)
      {
         if(!DailyLimitReached && UseMaxLossClose) CloseAllPositions();
         DailyLimitReached = true;
         return true;
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

double GetVolatilityRatio()
{
   double currentATR = GetATR();
   if(currentATR <= 0) return 1.0;
   double atrHistory[];
   ArraySetAsSeries(atrHistory, true);
   if(CopyBuffer(h_ATR, 0, 1, VolatilityRatioLook, atrHistory) < VolatilityRatioLook) return 1.0;
   double sum = 0;
   for(int i = 0; i < VolatilityRatioLook; i++) sum += atrHistory[i];
   double sma = sum / VolatilityRatioLook;
   return (sma > 0) ? currentATR / sma : 1.0;
}

string StateToStr(EA_STATE s)
{
   switch(s)
   {
      case STATE_IDLE:         return "IDLE";
      case STATE_PRIMARY_OPEN: return "PRIMARY";
      case STATE_HEDGED:       return "HEDGED";
      case STATE_HEDGE_ONLY:   return "HEDGE_ONLY";
      default:                 return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| ═══════════════════ DASHBOARD v2.0 ══════════════════════════════|
//+------------------------------------------------------------------+
void CreateDashboard()
{
   string bgName = ObjPrefix + "BG";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, DashX);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, DashY);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 260);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 420);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, DashBGColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'30,50,100');
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);

   CreateLabel("TITLE",    "◈ PEAK RANGE HEDGING v2.0",      DashX+8,  DashY+6,   11, C'80,180,255', true);
   CreateLabel("SEP0",     "─────────────────────────────",   DashX+6,  DashY+22,  8,  C'30,50,100');

   CreateLabel("LBL_SYMBOL",  "Symbol:   --",    DashX+8, DashY+32,  9, DashTextColor);
   CreateLabel("LBL_SPREAD",  "Spread:   -- pts", DashX+8, DashY+46,  9, DashTextColor);
   CreateLabel("LBL_ATR",     "ATR M1:   --",    DashX+8, DashY+60,  9, DashTextColor);
   CreateLabel("LBL_VRATIO",  "Vol Ratio: --",   DashX+8, DashY+74,  9, DashTextColor);
   CreateLabel("SEP1",     "─────────────────────────────",   DashX+6,  DashY+88,  8,  C'30,50,100');

   CreateLabel("LBL_STATE",   "State:    IDLE",  DashX+8, DashY+98,  9, clrGold);
   CreateLabel("LBL_PORDERS", "Primary:  0",     DashX+8, DashY+112, 9, DashTextColor);
   CreateLabel("LBL_HORDERS", "Hedge:    0",     DashX+8, DashY+126, 9, DashTextColor);
   CreateLabel("LBL_CYCLES",  "Cycles:   0/20",  DashX+8, DashY+140, 9, DashTextColor);
   CreateLabel("LBL_COOLDOWN","Cooldown: 0 bars",DashX+8, DashY+154, 9, DashTextColor);
   CreateLabel("SEP2",     "─────────────────────────────",   DashX+6,  DashY+168, 8,  C'30,50,100');

   CreateLabel("LBL_BALANCE", "Balance:  --",    DashX+8, DashY+178, 9, DashTextColor);
   CreateLabel("LBL_EQUITY",  "Equity:   --",    DashX+8, DashY+192, 9, DashTextColor);
   CreateLabel("LBL_PL",      "Float:    --",    DashX+8, DashY+206, 9, DashTextColor);
   CreateLabel("LBL_DAILYPL", "Daily PL: --",    DashX+8, DashY+220, 9, DashTextColor);
   CreateLabel("SEP3",     "─────────────────────────────",   DashX+6,  DashY+234, 8,  C'30,50,100');

   CreateLabel("LBL_SIGNAL",  "Signal:   --",    DashX+8, DashY+244, 9, DashTextColor);
   CreateLabel("LBL_TRENDM1", "Trend M1: --",    DashX+8, DashY+258, 9, DashTextColor);
   CreateLabel("LBL_REGIMEH1","Regime H1:--",    DashX+8, DashY+272, 9, DashTextColor);
   CreateLabel("SEP4",     "─────────────────────────────",   DashX+6,  DashY+286, 8,  C'30,50,100');

   CreateLabel("LBL_STATUS",  "Status:   ACTIVE",DashX+8, DashY+296, 9, clrLime);
   CreateLabel("LBL_STREAK",  "Streak:   OK",    DashX+8, DashY+310, 9, DashTextColor);
   CreateLabel("LBL_LIMIT",   "Limits:   OK",    DashX+8, DashY+324, 9, clrLime);
   CreateLabel("SEP5",     "─────────────────────────────",   DashX+6,  DashY+338, 8,  C'30,50,100');

   CreateLabel("LBL_HOURS",   StringFormat("%02d:%02d-%02d:%02d | EOD:%02d:%02d",
               TradingStartHour, TradingStartMin, TradingEndHour, TradingEndMin,
               ForceCloseHour, ForceCloseMin), DashX+8, DashY+348, 8, C'100,120,180');
   CreateLabel("LBL_MAGIC",   StringFormat("Magic: %d", MagicNumber),   DashX+8, DashY+362, 7, C'50,60,100');
   CreateLabel("LBL_VERSION", "v2.0 | MACD+EMA9/21+EMA200H1",           DashX+8, DashY+376, 7, C'50,60,100');

   ChartRedraw(0);
}

void CreateLabel(string id, string text, int x, int y, int sz, color clr, bool bold=false)
{
   string name = ObjPrefix + id;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
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

   string  currency  = AccountInfoString(ACCOUNT_CURRENCY);
   double  balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double  equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double  floatPL   = GetTotalFloatingPL();
   double  dailyPL   = balance - DailyStartBalance; // [FIX B5] balance vs balance
   long    spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double  atr       = GetATR();
   double  vRatio    = GetVolatilityRatio();

   color spreadClr = (MaxSpreadPoints > 0 && spreadPts > (long)MaxSpreadPoints) ? DashSellColor : clrLime;
   color vRatioClr = (vRatio < VolatilityRatioMin || (VolatilityRatioMax > 0 && vRatio > VolatilityRatioMax))
                     ? DashSellColor : clrLime;

   UpdateLabel("LBL_SYMBOL",  StringFormat("Symbol:   %s", _Symbol));
   UpdateLabel("LBL_SPREAD",  StringFormat("Spread:   %d pts", spreadPts), spreadClr);
   UpdateLabel("LBL_ATR",     StringFormat("ATR M1:   %.2f", atr));
   UpdateLabel("LBL_VRATIO",  StringFormat("Vol Ratio: %.2f", vRatio), vRatioClr);

   // State machine
   color stateClr = (CurrentState == STATE_IDLE) ? clrGold :
                    (CurrentState == STATE_HEDGED) ? DashSellColor : C'80,180,255';
   UpdateLabel("LBL_STATE",   StringFormat("State:    %s", StateToStr(CurrentState)), stateClr);
   UpdateLabel("LBL_PORDERS", StringFormat("Primary:  %d", CountPrimaryOrders()));
   UpdateLabel("LBL_HORDERS", StringFormat("Hedge:    %d", CountHedgeOrders()));
   UpdateLabel("LBL_CYCLES",  StringFormat("Cycles:   %d/%d", DailyCycles, MaxRangeCyclesDay));

   int coolTotal = CooldownBarsLeft + ConsecLossPauseLeft;
   UpdateLabel("LBL_COOLDOWN",StringFormat("Cooldown: %d bars", coolTotal),
               coolTotal > 0 ? clrGold : DashTextColor);

   UpdateLabel("LBL_BALANCE", StringFormat("Balance:  %.2f %s", balance, currency));
   UpdateLabel("LBL_EQUITY",  StringFormat("Equity:   %.2f %s", equity, currency));
   UpdateLabel("LBL_PL",      StringFormat("Float:    %+.2f %s", floatPL, currency),
               floatPL >= 0 ? clrLime : DashSellColor);
   UpdateLabel("LBL_DAILYPL", StringFormat("Daily PL: %+.2f %s", dailyPL, currency),
               dailyPL >= 0 ? clrLime : DashSellColor);

   // Signals
   SIGNAL_TYPE sig   = GetPrimaryEntrySignal();
   SIGNAL_TYPE trdM1 = GetTrendFilterM1();
   auto SigStr = [](SIGNAL_TYPE s, string pref) -> string {
      return pref + ((s == SIG_BUY) ? "BUY ▲" : (s == SIG_SELL) ? "SELL ▼" : "NONE");
   };
   auto SigClr = [&](SIGNAL_TYPE s) -> color {
      return (s == SIG_BUY) ? DashBuyColor : (s == SIG_SELL) ? DashSellColor : DashTextColor;
   };
   UpdateLabel("LBL_SIGNAL",  SigStr(sig,  "Signal:   "), SigClr(sig));
   UpdateLabel("LBL_TRENDM1", SigStr(trdM1,"Trend M1: "), SigClr(trdM1));
   UpdateLabel("LBL_REGIMEH1",StringFormat("Regime H1:%s", H1Regime==SIG_BUY?"BULL ▲":H1Regime==SIG_SELL?"BEAR ▼":"--"),
               SigClr(H1Regime));

   // Status
   bool   inHours = IsTradeAllowed();
   string statStr = DailyLimitReached ? "LIMIT HIT" : EODClosed ? "EOD CLOSED" :
                    coolTotal > 0 ? "COOLDOWN" : inHours ? "ACTIVE" : "OFF-HOURS";
   color  statClr = DailyLimitReached ? DashSellColor : EODClosed ? clrGold :
                    coolTotal > 0 ? clrGold : inHours ? clrLime : clrGold;
   UpdateLabel("LBL_STATUS",  StringFormat("Status:   %s", statStr), statClr);

   string streakStr = (ConsecLossCount > 0) ?
      StringFormat("Losses:  %d/%d", ConsecLossCount, MaxConsecLosses > 0 ? MaxConsecLosses : 99) : "Streak:   OK";
   UpdateLabel("LBL_STREAK", streakStr,
               ConsecLossCount >= 2 ? DashSellColor : ConsecLossCount == 1 ? clrGold : clrLime);

   UpdateLabel("LBL_LIMIT", DailyLimitReached ? "Limits:   REACHED" : "Limits:   OK",
               DailyLimitReached ? DashSellColor : clrLime);

   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, ObjPrefix);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
//| END OF EA v2.0                                                   |
//+------------------------------------------------------------------+
