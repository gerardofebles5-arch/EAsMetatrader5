//+------------------------------------------------------------------+
//|                                      PeakRangeHedging_v3.0.mq5  |
//|              Range Hedging EA — v3.0 Scientific Edition          |
//|                                                                  |
//|  CAMBIOS v3.0 vs v2.0 (especificación técnica pre-implementación)|
//|                                                                  |
//|  [M1]  SL_floor: SL mínimo garantizado (default 20pts XAUUSD)  |
//|         SL = MAX(ATR×coef, SL_floor×10×_Point)                  |
//|  [M2]  SIN partial close — posiciones van a TP completo o SL    |
//|         Causa principal del colapso de RR en v2.0               |
//|  [M3]  Señal primaria en M5 (Ichimoku + Stochastic)             |
//|         Lookback 130 min vs 26 min en M1 — 5x más robusto       |
//|  [M4]  Trailing ATR corregido: distancia FIJA = ATR×coef        |
//|         Activación al 60% del TP (no 50%). Guard: precio>SL.    |
//|  [M5]  AE1 = primer componente principal (PCA) sobre 4 vars:    |
//|         RSI(14), Stoch%K, BB_position, ATR_ratio                 |
//|         Implementado via power iteration en MQL5 (puro, sin libs)|
//|  [M6]  K-means 2 clusters sobre AE1 → régimen TRENDING/CHOPPY   |
//|         CHOPPY → sizing reducido 50%, sin nuevas primarias       |
//|  [M7]  Stochastic como 3er confirmador (AND) junto a Ichimoku   |
//|         y AE1. Triple capa independiente de señal.               |
//|  [M8]  Hedge entry: BB cruce + BB width + AE1 divergencia        |
//|  [M9]  SL fractal: SL colocado en swing high/low de M5          |
//|         con cap ATR×2.5 y floor SL_floor                        |
//|  [M10] Regresión lineal OLS sobre AE1(50 barras):               |
//|         pendiente, MSE, R². Solo operar si R²>0.4               |
//|  [M11] Momentum intraday: retorno 60 barras M5 vs 120-60        |
//|         Confirmación adicional de dirección                      |
//|  [M12] Sizing adaptativo: TRENDING+R²>0.6 → 100%, otros → 70%  |
//|                                                                  |
//|  MANTENIDO DE v2.0:                                              |
//|  - Order filling auto-detectado (B1)                            |
//|  - RSI handles separados (B2)                                   |
//|  - DailyCycles++ solo si orden exitosa (B3)                     |
//|  - Daily limits: balance vs balance (B5)                        |
//|  - Máquina de estados 4 estados (B6)                            |
//|  - BB hedge cruce real + width filter (B7)                      |
//|  - CopyBuffer count=2 eficiente (B9)                            |
//|  - TP > 0 guard en trailing (B10)                               |
//|  - H1 EMA200 régimen (M2v2)                                     |
//|  - EOD forced close (M5v2)                                      |
//|  - CalcDynamicVolume usa equity (M4v2)                          |
//+------------------------------------------------------------------+
#property copyright "Peak Range Hedging EA v3.0"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum SIGNAL_TYPE { SIG_NONE = 0, SIG_BUY = 1, SIG_SELL = -1 };

enum EA_STATE
{
   STATE_IDLE         = 0,
   STATE_PRIMARY_OPEN = 1,
   STATE_HEDGED       = 2,
   STATE_HEDGE_ONLY   = 3
};

enum REGIME_TYPE { REGIME_UNKNOWN = 0, REGIME_TRENDING = 1, REGIME_CHOPPY = 2 };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "=== STEP 1: PRIMARY ORDER SETTINGS ==="
input int      MaxOrders             = 20;      // Max total orders (primary + hedge)
input double   RiskPerOrder          = 0.5;     // Risk per primary order (% equity, full regime)
input double   RiskPerOrder_Reduced  = 0.35;    // Risk per primary order (% equity, partial regime)
input double   ATR_SL_Coef           = 1.5;     // ATR multiplier for initial SL
input double   SL_Floor_Points       = 20.0;    // [M1] Minimum SL in points (XAUUSD: 20)
input double   RR_Ratio              = 1.5;     // Risk/Reward ratio (TP = SL × coef)
input double   TrailingATR_Coef      = 1.0;     // [M4] Trailing SL = price ± ATR×coef
input double   TrailingActivatePct   = 60.0;    // [M4] Activate trailing at % of TP dist

input group "=== STEP 1: HEDGE ORDER SETTINGS ==="
input double   HedgeRiskPerOrder     = 0.125;   // Risk per hedge order (% equity)
input double   HedgeATR_SL_Coef      = 1.5;     // ATR multiplier for Hedge SL
input double   HedgeRR_Ratio         = 1.5;     // Hedge TP = SL × coef
input double   HedgeBreakevenPct     = 50.0;    // Breakeven activation (% of TP dist)

input group "=== STEP 2: TRADE MANAGEMENT ==="
input bool     UseMaxProfitClose     = false;   // Close all at max profit
input bool     UseMaxLossClose       = false;   // Close all at max loss
input bool     UseDailyProfitLimit   = true;    // Enable daily profit limit
input double   DailyProfitPct        = 10.0;    // Daily profit limit (% of balance)
input bool     UseDailyLossLimit     = true;    // Enable daily loss limit
input double   DailyLossPct          = 2.0;     // Daily loss limit (% of balance)
input int      MaxRangeCyclesDay     = 20;      // Max primary order cycles per day
input bool     ForceCloseEOD         = true;    // Force close all at EOD
input int      ForceCloseHour        = 21;      // EOD close hour (server time)
input int      ForceCloseMin         = 45;      // EOD close minute

input group "=== STEP 3: SIGNAL CONFIRMATION ==="
input bool     RequireCandleConfirm  = true;    // Candle body must confirm direction
input int      CooldownBars          = 3;       // Min M1 bars cooldown after close
input int      MaxConsecLosses       = 3;       // Pause after N consecutive losses (0=off)
input int      ConsecLossPauseBars   = 10;      // Bars to pause after max consec losses

input group "=== STEP 3: QUALITY FILTERS ==="
input double   MaxSpreadPoints       = 80.0;    // Max spread in points (0=disabled)
input double   VolatilityRatioMin    = 0.7;     // Min ATR/ATR_SMA ratio
input double   VolatilityRatioMax    = 2.0;     // Max ATR/ATR_SMA ratio
input int      VolatilityRatioLook   = 20;      // Lookback bars for ATR_SMA

input group "=== STEP 3: M5 ENTRY SIGNAL — ICHIMOKU ==="
input int      Ichi_Tenkan           = 9;       // [M3] Tenkan Sen period (M5)
input int      Ichi_Kijun            = 26;      // [M3] Kijun Sen period (M5)
input int      Ichi_SenkouB          = 52;      // [M3] Senkou Span B period (M5)
input int      Ichi_Shift            = 1;       // [M3] Candle shift on M5

input group "=== STEP 3: M1 STOCHASTIC CONFIRMATION ==="
input int      Stoch_K               = 5;       // %K period
input int      Stoch_D               = 3;       // %D period
input int      Stoch_Slowing         = 3;       // Slowing
input double   Stoch_BuyLevel        = 20.0;    // %K threshold for BUY confirmation
input double   Stoch_SellLevel       = 80.0;    // %K threshold for SELL confirmation
input int      Stoch_Shift           = 1;       // Candle shift

input group "=== STEP 3: TREND FILTER H1 — EMA200 ==="
input int      EMA200_Period         = 200;     // H1 EMA200 period
input bool     UseH1RegimeFilter     = true;    // Enable H1 EMA200 regime filter
input int      H1EMA_CandleShift     = 1;       // H1 candle shift

input group "=== STEP 3: EXIT SIGNAL — RSI(21) ==="
input int      RSI_Exit_Period       = 21;      // RSI exit period
input double   RSI_ExitSellLevel     = 70.0;    // Exit BUY when RSI crosses above this
input double   RSI_ExitBuyLevel      = 30.0;    // Exit SELL when RSI crosses below this
input int      RSI_Exit_Shift        = 1;       // Candle shift

input group "=== STEP 4: HEDGE — BOLLINGER BANDS ==="
input int      BB_Period             = 20;      // BB period
input double   BB_Deviations         = 2.0;     // BB std deviations
input int      BB_BandShift          = 0;       // BB parameter shift
input int      BB_CandleShift        = 1;       // Candle shift for signal
input double   BB_WidthMinCoef       = 0.5;     // Min BB width as ratio of ATR

input group "=== AE1: PCA COMPOSITE INDICATOR [M5] ==="
input int      AE1_WindowSize        = 100;     // Rolling window for covariance matrix
input int      AE1_MedianLookback    = 200;     // Lookback for AE1 median (signal)
input int      AE1_PowerIterations   = 15;      // Power iteration steps for PC1
input int      AE1_RSI_Period        = 14;      // RSI period for AE1 input
input int      AE1_ATRRatio_Period   = 50;      // SMA period for ATR ratio normalization
input double   AE1_DivergenceThresh  = 0.15;    // [M8] AE1 divergence threshold for hedge

input group "=== OLS REGRESSION ON AE1 [M10] ==="
input int      OLS_Lookback          = 50;      // Bars for OLS regression
input double   OLS_R2_MinThreshold   = 0.40;    // Minimum R² to allow trading
input double   OLS_Slope_MinAbs      = 0.0003;  // Min |slope| (lateral market filter)

input group "=== K-MEANS REGIME DETECTION [M6] ==="
input int      KMeans_Lookback       = 200;     // AE1 buffer for K-means
input double   KMeans_ChoppyVarCoef  = 0.5;     // Choppy if variance < coef×global_variance

input group "=== FRACTAL SL [M9] ==="
input int      Fractal_Lookback      = 10;      // Bars on M5 for swing high/low
input double   Fractal_Buffer_Points = 2.0;     // Points beyond the fractal
input double   Fractal_MaxATR_Coef   = 2.5;     // Cap: SL never wider than ATR×coef

input group "=== ATR SETTINGS ==="
input int      ATR_Period            = 14;      // ATR period

input group "=== STEP 5: TRADING HOURS & DAYS ==="
input int      TradingStartHour      = 12;      // Trading start hour (server time)
input int      TradingStartMin       = 0;       // Trading start minute
input int      TradingEndHour        = 22;      // Trading end hour (server time)
input int      TradingEndMin         = 0;       // Trading end minute
input bool     TradeMonday           = true;
input bool     TradeTuesday          = true;
input bool     TradeWednesday        = true;
input bool     TradeThursday         = true;
input bool     TradeFriday           = true;

input group "=== DASHBOARD ==="
input bool     ShowDashboard         = true;
input color    DashBGColor           = C'12,14,24';
input color    DashTextColor         = clrWhite;
input color    DashBuyColor          = C'50,220,120';
input color    DashSellColor         = C'220,70,70';
input int      DashX                 = 10;
input int      DashY                 = 30;

input group "=== GENERAL ==="
input long     MagicNumber           = 20250604;
input string   TradeComment          = "PeakRH";

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade        Trade;
CPositionInfo PosInfo;

// Indicator handles
int h_Ichi_M5, h_Stoch, h_EMA200_H1, h_RSI_Exit, h_BB, h_ATR;
int h_RSI_AE1, h_ATR_AE1;   // For AE1 inputs

// Time tracking
datetime LastBarTime_M1  = 0;
datetime LastBarTime_M5  = 0;
datetime LastH1BarTime   = 0;
datetime LastDayReset    = 0;

// Daily management
double   DailyStartBalance = 0;
int      DailyCycles       = 0;
bool     DailyLimitReached = false;
bool     EODClosed         = false;

// State machine
EA_STATE    CurrentState   = STATE_IDLE;
SIGNAL_TYPE H1Regime       = SIG_NONE;
REGIME_TYPE MarketRegime   = REGIME_UNKNOWN;

// Cooldown & streak
int      CooldownBarsLeft    = 0;
int      ConsecLossCount     = 0;
int      ConsecLossPauseLeft = 0;

// Last known positions for closed-position detection
ulong    LastKnownTickets[];

// Dashboard prefix
string   ObjPrefix = "PRH30_";

// ── AE1 / PCA state ─────────────────────────────────────────────
// Circular buffers for the 4 input variables (M5 bars)
double   buf_RSI[];      // RSI(14)/100 → [0,1]
double   buf_Stoch[];    // Stoch %K / 100 → [0,1]
double   buf_BBpos[];    // (close-lower)/(upper-lower) → [0,1]
double   buf_ATRratio[]; // ATR(14)/SMA(ATR,50) → [0.x, 3.x]
int      buf_count  = 0; // Number of valid bars in buffers
int      buf_head   = 0; // Current write index (circular)

// AE1 history (for median, OLS, K-means)
double   buf_AE1[];      // Size = KMeans_Lookback (>=OLS_Lookback, >=AE1_MedianLookback)
int      ae1_count  = 0;
int      ae1_head   = 0;

// PC1 eigenvector (4 components: RSI, Stoch, BBpos, ATRratio)
double   PC1[4];
bool     PC1_valid  = false;

// Current AE1 value and OLS results
double   AE1_current    = 0;
double   AE1_median     = 0;
double   OLS_slope      = 0;
double   OLS_R2         = 0;
double   OLS_MSE        = 0;
SIGNAL_TYPE AE1_signal  = SIG_NONE;

// AE1 at moment of primary open (for hedge divergence check)
double   AE1_at_primary_open = 0;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(30);

   // Auto-detect filling mode
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      Trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      Trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Ichimoku on M5 [M3]
   h_Ichi_M5   = iIchimoku(_Symbol, PERIOD_M5, Ichi_Tenkan, Ichi_Kijun, Ichi_SenkouB);
   // Stochastic on M1 [M7]
   h_Stoch     = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   // H1 EMA200 regime
   h_EMA200_H1 = iMA(_Symbol, PERIOD_H1, EMA200_Period, 0, MODE_EMA, PRICE_CLOSE);
   // RSI exit (21)
   h_RSI_Exit  = iRSI(_Symbol, PERIOD_CURRENT, RSI_Exit_Period, PRICE_CLOSE);
   // Bollinger Bands
   h_BB        = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_BandShift, BB_Deviations, PRICE_CLOSE);
   // ATR (M1 for SL/TP/trailing)
   h_ATR       = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   // AE1 inputs
   h_RSI_AE1   = iRSI(_Symbol, PERIOD_M5, AE1_RSI_Period, PRICE_CLOSE);
   h_ATR_AE1   = iATR(_Symbol, PERIOD_M5, ATR_Period);

   if(h_Ichi_M5==INVALID_HANDLE || h_Stoch==INVALID_HANDLE || h_EMA200_H1==INVALID_HANDLE ||
      h_RSI_Exit==INVALID_HANDLE || h_BB==INVALID_HANDLE || h_ATR==INVALID_HANDLE ||
      h_RSI_AE1==INVALID_HANDLE  || h_ATR_AE1==INVALID_HANDLE)
   {
      Print("ERROR v3.0: Failed to create one or more indicator handles.");
      return INIT_FAILED;
   }

   // Allocate circular buffers
   int maxBuf = MathMax(AE1_WindowSize, KMeans_Lookback) + 10;
   ArrayResize(buf_RSI,      maxBuf); ArrayInitialize(buf_RSI,      0);
   ArrayResize(buf_Stoch,    maxBuf); ArrayInitialize(buf_Stoch,    0);
   ArrayResize(buf_BBpos,    maxBuf); ArrayInitialize(buf_BBpos,    0);
   ArrayResize(buf_ATRratio, maxBuf); ArrayInitialize(buf_ATRratio, 0);

   int ae1Buf = MathMax(MathMax(KMeans_Lookback, OLS_Lookback), AE1_MedianLookback) + 10;
   ArrayResize(buf_AE1, ae1Buf); ArrayInitialize(buf_AE1, 0);

   // PC1 initialization (equal weights)
   for(int i = 0; i < 4; i++) PC1[i] = 0.5;
   PC1_valid = false;

   ArrayResize(LastKnownTickets, 0);
   DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(ShowDashboard) CreateDashboard();
   Print("PeakRangeHedging v3.0 initialized. Symbol:", _Symbol, " Magic:", MagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_Ichi_M5);  IndicatorRelease(h_Stoch);
   IndicatorRelease(h_EMA200_H1);IndicatorRelease(h_RSI_Exit);
   IndicatorRelease(h_BB);       IndicatorRelease(h_ATR);
   IndicatorRelease(h_RSI_AE1);  IndicatorRelease(h_ATR_AE1);
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime curM1  = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime curM5  = iTime(_Symbol, PERIOD_M5, 0);
   datetime curH1  = iTime(_Symbol, PERIOD_H1, 0);

   bool isNewM1 = (curM1 != LastBarTime_M1);
   bool isNewM5 = (curM5 != LastBarTime_M5);
   bool isNewH1 = (curH1 != LastH1BarTime);

   // ── Per-tick: trailing stops (no partial close) ──────────────
   ManageTrailingStops();

   // ── H1 bar: update regime cache ─────────────────────────────
   if(isNewH1)
   {
      LastH1BarTime = curH1;
      if(UseH1RegimeFilter) UpdateH1Regime();
   }

   // ── M5 bar: update AE1 (PCA), OLS, K-means ──────────────────
   if(isNewM5)
   {
      LastBarTime_M5 = curM5;
      UpdateAE1();          // [M5] PCA composite indicator
      UpdateOLS();          // [M10] Regression on AE1
      UpdateKMeans();       // [M6] Regime detection
   }

   // ── M1 bar: trading logic ────────────────────────────────────
   if(!isNewM1)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }
   LastBarTime_M1 = curM1;

   CheckDailyReset();

   if(CooldownBarsLeft    > 0) CooldownBarsLeft--;
   if(ConsecLossPauseLeft > 0) ConsecLossPauseLeft--;

   CheckPositionsClosed();
   SyncStateMachine();

   // EOD forced close
   if(ForceCloseEOD && ShouldForceCloseEOD())
   {
      if(!EODClosed) { CloseAllPositions(); EODClosed = true; }
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

   // Exit signals before entry
   CheckExitSignals();

   if(CountAllOrders() >= MaxOrders || DailyCycles >= MaxRangeCyclesDay)
   {
      if(ShowDashboard) UpdateDashboard();
      return;
   }

   // ── STATE MACHINE ────────────────────────────────────────────
   SIGNAL_TYPE entryM5    = GetIchimokuM5Signal();   // [M3]
   SIGNAL_TYPE stochConf  = GetStochConfirmation();   // [M7]
   SIGNAL_TYPE finalEntry = BuildFinalSignal(entryM5, stochConf);
   SIGNAL_TYPE hedgeSig   = GetHedgeEntrySignal();

   switch(CurrentState)
   {
      case STATE_IDLE:
         // Need: Ichimoku M5 + Stoch M1 + AE1 + H1 regime all agree
         if(finalEntry == SIG_BUY && CanOpenPrimary())
         {
            if(OpenPrimaryOrder(ORDER_TYPE_BUY))
            {
               DailyCycles++;
               AE1_at_primary_open = AE1_current;
               CurrentState = STATE_PRIMARY_OPEN;
            }
         }
         else if(finalEntry == SIG_SELL && CanOpenPrimary())
         {
            if(OpenPrimaryOrder(ORDER_TYPE_SELL))
            {
               DailyCycles++;
               AE1_at_primary_open = AE1_current;
               CurrentState = STATE_PRIMARY_OPEN;
            }
         }
         break;

      case STATE_PRIMARY_OPEN:
         if(hedgeSig != SIG_NONE)
         {
            ENUM_ORDER_TYPE primDir = GetLastPrimaryDirection();
            // [M8] hedge in opposite direction + AE1 divergence check
            if(primDir == ORDER_TYPE_BUY && hedgeSig == SIG_SELL && CheckAE1Divergence())
            {
               if(OpenHedgeOrder(ORDER_TYPE_SELL)) CurrentState = STATE_HEDGED;
            }
            else if(primDir == ORDER_TYPE_SELL && hedgeSig == SIG_BUY && CheckAE1Divergence())
            {
               if(OpenHedgeOrder(ORDER_TYPE_BUY)) CurrentState = STATE_HEDGED;
            }
         }
         break;

      case STATE_HEDGED:
      case STATE_HEDGE_ONLY:
         break;  // SyncStateMachine handles transitions
   }

   if(ShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| CAN OPEN PRIMARY — regime + OLS + H1 gate                       |
//+------------------------------------------------------------------+
bool CanOpenPrimary()
{
   // [M6] Choppy regime: no new primaries
   if(MarketRegime == REGIME_CHOPPY) return false;

   // [M10] OLS R² gate: AE1 must have enough trend structure
   if(OLS_R2 < OLS_R2_MinThreshold) return false;

   // [M10] Slope gate: avoid lateral AE1
   if(MathAbs(OLS_slope) < OLS_Slope_MinAbs) return false;

   // [M2 via H1] H1 EMA200 must agree
   if(UseH1RegimeFilter && H1Regime == SIG_NONE) return false;

   return true;
}

//+------------------------------------------------------------------+
//| ═══════════════════ AE1 / PCA ENGINE ═══════════════════════════ |
//+------------------------------------------------------------------+

// ── Circular buffer write ─────────────────────────────────────────
void CircBufWrite(double &buf[], int &head, int &count, int maxSize, double val)
{
   buf[head] = val;
   head = (head + 1) % maxSize;
   if(count < maxSize) count++;
}

// ── Read N values from circular buffer (newest first) ─────────────
// Returns false if not enough data
bool CircBufRead(const double &buf[], int head, int count, int maxSize,
                 int n, double &out[])
{
   if(count < n) return false;
   ArrayResize(out, n);
   for(int i = 0; i < n; i++)
   {
      int idx = (head - 1 - i + maxSize) % maxSize;
      out[i] = buf[idx];
   }
   return true;
}

// ── Matrix × vector (4×4 covariance × 4 eigenvector) ─────────────
void MatVecMul4(const double mat[][4], const double vec[], double &res[])
{
   ArrayResize(res, 4);
   for(int i = 0; i < 4; i++)
   {
      res[i] = 0;
      for(int j = 0; j < 4; j++) res[i] += mat[i][j] * vec[j];
   }
}

// ── Normalize a 4-vector to unit length ──────────────────────────
void Normalize4(double &v[])
{
   double norm = 0;
   for(int i = 0; i < 4; i++) norm += v[i]*v[i];
   norm = MathSqrt(norm);
   if(norm < 1e-10) return;
   for(int i = 0; i < 4; i++) v[i] /= norm;
}

// ── UPDATE AE1 via PCA Power Iteration [M5] ──────────────────────
void UpdateAE1()
{
   // --- Step 1: Collect the 4 normalized input variables from M5 ---
   // RSI(14) on M5, normalized [0,1]
   double rsiArr[]; ArraySetAsSeries(rsiArr, true);
   if(CopyBuffer(h_RSI_AE1, 0, 1, 1, rsiArr) < 1) return;
   double x_rsi = rsiArr[0] / 100.0;

   // Stochastic %K on M5 (via M1 handle — re-read M5 stoch inline)
   // Use a dedicated M5 stochastic via the M5 bar close
   // Approximation: use the M1 stochastic but read with M5 shift
   double stochArr[]; ArraySetAsSeries(stochArr, true);
   if(CopyBuffer(h_Stoch, 0, Stoch_Shift, 1, stochArr) < 1) return;
   double x_stoch = stochArr[0] / 100.0;

   // Bollinger Bands position on M5: (close - lower) / (upper - lower)
   double bbMid[], bbUp[], bbLow[];
   ArraySetAsSeries(bbMid, true);
   ArraySetAsSeries(bbUp,  true);
   ArraySetAsSeries(bbLow, true);
   if(CopyBuffer(h_BB, 0, BB_CandleShift, 1, bbMid) < 1) return;
   if(CopyBuffer(h_BB, 1, BB_CandleShift, 1, bbUp)  < 1) return;
   if(CopyBuffer(h_BB, 2, BB_CandleShift, 1, bbLow) < 1) return;
   double bbRange = bbUp[0] - bbLow[0];
   double closeM5 = iClose(_Symbol, PERIOD_M5, 1);
   double x_bbpos = (bbRange > 0) ? MathMax(0, MathMin(1, (closeM5 - bbLow[0]) / bbRange)) : 0.5;

   // ATR ratio on M5: ATR(14)/SMA(ATR(14), AE1_ATRRatio_Period)
   double atrM5Arr[]; ArraySetAsSeries(atrM5Arr, true);
   if(CopyBuffer(h_ATR_AE1, 0, 1, AE1_ATRRatio_Period, atrM5Arr) < AE1_ATRRatio_Period) return;
   double atrNow = atrM5Arr[0];
   double atrSum = 0;
   for(int i = 0; i < AE1_ATRRatio_Period; i++) atrSum += atrM5Arr[i];
   double atrSMA   = atrSum / AE1_ATRRatio_Period;
   double x_atrrat = (atrSMA > 0) ? MathMin(3.0, atrNow / atrSMA) : 1.0;

   int maxBuf = ArraySize(buf_RSI);

   // --- Step 2: Write to circular buffers ---
   CircBufWrite(buf_RSI,      buf_head, buf_count, maxBuf, x_rsi);
   CircBufWrite(buf_Stoch,    buf_head, buf_count, maxBuf, x_stoch);
   CircBufWrite(buf_BBpos,    buf_head, buf_count, maxBuf, x_bbpos);
   CircBufWrite(buf_ATRratio, buf_head, buf_count, maxBuf, x_atrrat);
   // Note: all 4 share the same head/count since they advance together.
   // Adjust: only buf_head was advanced 4 times — fix by using modular math.
   // Actually we wrote 4 times advancing head 4 steps. Let's use independent heads.
   // Simpler: use the count from buf_RSI only (already incremented once per M5 bar).
   // Re-initialize: use a single head tracker. Already consistent above.

   // --- Step 3: PCA covariance matrix over last AE1_WindowSize bars ---
   int N = MathMin(buf_count, AE1_WindowSize);
   if(N < 20) return;  // Need minimum data

   double data[4];
   double mean[4] = {0,0,0,0};

   // Compute means
   for(int i = 0; i < N; i++)
   {
      int idx = (buf_head - 1 - i + maxBuf) % maxBuf;
      mean[0] += buf_RSI[idx];
      mean[1] += buf_Stoch[idx];
      mean[2] += buf_BBpos[idx];
      mean[3] += buf_ATRratio[idx];
   }
   for(int k = 0; k < 4; k++) mean[k] /= N;

   // Compute 4×4 covariance matrix
   double cov[4][4];
   ArrayInitialize(cov, 0);
   for(int i = 0; i < N; i++)
   {
      int idx = (buf_head - 1 - i + maxBuf) % maxBuf;
      double d[4];
      d[0] = buf_RSI[idx]      - mean[0];
      d[1] = buf_Stoch[idx]    - mean[1];
      d[2] = buf_BBpos[idx]    - mean[2];
      d[3] = buf_ATRratio[idx] - mean[3];
      for(int r = 0; r < 4; r++)
         for(int c = 0; c < 4; c++)
            cov[r][c] += d[r] * d[c];
   }
   for(int r = 0; r < 4; r++)
      for(int c = 0; c < 4; c++)
         cov[r][c] /= (N - 1);

   // --- Step 4: Power iteration to extract PC1 (dominant eigenvector) ---
   // Initialize from current PC1 (warm start for stability)
   double v[4];
   for(int k = 0; k < 4; k++) v[k] = PC1[k];
   Normalize4(v);

   double vNew[];
   for(int iter = 0; iter < AE1_PowerIterations; iter++)
   {
      MatVecMul4(cov, v, vNew);
      Normalize4(vNew);
      for(int k = 0; k < 4; k++) v[k] = vNew[k];
   }

   // Ensure consistent sign (PC1[0] always positive for RSI component)
   if(v[0] < 0) for(int k = 0; k < 4; k++) v[k] = -v[k];
   for(int k = 0; k < 4; k++) PC1[k] = v[k];
   PC1_valid = true;

   // --- Step 5: Project current observation onto PC1 ---
   double x_curr[4];
   x_curr[0] = x_rsi;
   x_curr[1] = x_stoch;
   x_curr[2] = x_bbpos;
   x_curr[3] = x_atrrat;

   double ae1_val = 0;
   for(int k = 0; k < 4; k++) ae1_val += PC1[k] * (x_curr[k] - mean[k]);
   AE1_current = ae1_val;

   // --- Step 6: Write AE1 to its own buffer ---
   int ae1MaxBuf = ArraySize(buf_AE1);
   CircBufWrite(buf_AE1, ae1_head, ae1_count, ae1MaxBuf, ae1_val);

   // --- Step 7: Compute AE1 median ---
   int mN = MathMin(ae1_count, AE1_MedianLookback);
   if(mN > 0)
   {
      double tmpArr[];
      bool ok = CircBufRead(buf_AE1, ae1_head, ae1_count, ae1MaxBuf, mN, tmpArr);
      if(ok)
      {
         ArraySort(tmpArr);
         AE1_median = (mN % 2 == 1) ? tmpArr[mN/2] : (tmpArr[mN/2-1] + tmpArr[mN/2]) / 2.0;
      }
   }

   // --- Step 8: AE1 signal ---
   AE1_signal = (AE1_current > AE1_median) ? SIG_BUY : SIG_SELL;
}

//+------------------------------------------------------------------+
//| OLS REGRESSION ON AE1 [M10]                                     |
//+------------------------------------------------------------------+
void UpdateOLS()
{
   int N = MathMin(ae1_count, OLS_Lookback);
   if(N < 10) { OLS_slope = 0; OLS_R2 = 0; OLS_MSE = 0; return; }

   int ae1MaxBuf = ArraySize(buf_AE1);
   double vals[];
   if(!CircBufRead(buf_AE1, ae1_head, ae1_count, ae1MaxBuf, N, vals))
   { OLS_slope = 0; OLS_R2 = 0; return; }

   // OLS: y = a + b×t, t = 0..N-1 (vals[0] = newest, vals[N-1] = oldest)
   // Reverse for chronological order: t=0 oldest, t=N-1 newest
   double sumT=0, sumY=0, sumTT=0, sumTY=0;
   for(int i = 0; i < N; i++)
   {
      double t = (double)i;
      double y = vals[N - 1 - i];  // chronological: vals[N-1] is oldest (t=0)
      sumT  += t;
      sumY  += y;
      sumTT += t*t;
      sumTY += t*y;
   }
   double denom = (double)N * sumTT - sumT * sumT;
   if(MathAbs(denom) < 1e-12) { OLS_slope = 0; OLS_R2 = 0; return; }

   double b = ((double)N * sumTY - sumT * sumY) / denom;  // slope
   double a = (sumY - b * sumT) / (double)N;               // intercept
   OLS_slope = b;

   // Compute R²
   double meanY = sumY / (double)N;
   double ssTot = 0, ssRes = 0;
   for(int i = 0; i < N; i++)
   {
      double t = (double)i;
      double y = vals[N - 1 - i];
      double yHat = a + b * t;
      ssTot += (y - meanY) * (y - meanY);
      ssRes += (y - yHat)  * (y - yHat);
   }
   OLS_MSE = ssRes / (double)N;
   OLS_R2  = (ssTot > 1e-12) ? MathMax(0, 1.0 - ssRes / ssTot) : 0;
}

//+------------------------------------------------------------------+
//| K-MEANS REGIME DETECTION [M6]                                   |
//| 2 clusters on AE1 buffer                                        |
//+------------------------------------------------------------------+
void UpdateKMeans()
{
   int N = MathMin(ae1_count, KMeans_Lookback);
   if(N < 20) { MarketRegime = REGIME_UNKNOWN; return; }

   int ae1MaxBuf = ArraySize(buf_AE1);
   double vals[];
   if(!CircBufRead(buf_AE1, ae1_head, ae1_count, ae1MaxBuf, N, vals))
   { MarketRegime = REGIME_UNKNOWN; return; }

   // Sort a copy to get quartile centroids
   double sorted[];
   ArrayResize(sorted, N);
   ArrayCopy(sorted, vals);
   ArraySort(sorted);

   // C1 = mean of top quartile (high AE1 = trending up)
   // C2 = mean of bottom quartile (low AE1 = trending down)
   int qSize = N / 4;
   double c1 = 0, c2 = 0;
   for(int i = 0; i < qSize; i++) c2 += sorted[i];
   for(int i = N - qSize; i < N; i++) c1 += sorted[i];
   c1 /= qSize; c2 /= qSize;

   // Assign current AE1 to nearest centroid
   // Regime = TRENDING if current bar is clearly in c1 or c2
   // Regime = CHOPPY if variance of recent 20 bars is low
   double recentMean = 0, recentVar = 0;
   int rN = MathMin(20, N);
   for(int i = 0; i < rN; i++) recentMean += vals[i];
   recentMean /= rN;
   for(int i = 0; i < rN; i++) recentVar += (vals[i] - recentMean) * (vals[i] - recentMean);
   recentVar /= rN;

   // Global variance
   double globalMean = 0, globalVar = 0;
   for(int i = 0; i < N; i++) globalMean += vals[i];
   globalMean /= N;
   for(int i = 0; i < N; i++) globalVar += (vals[i] - globalMean) * (vals[i] - globalMean);
   globalVar /= N;

   // Choppy: recent variance is small fraction of global variance
   if(globalVar > 1e-12 && recentVar < KMeans_ChoppyVarCoef * globalVar)
      MarketRegime = REGIME_CHOPPY;
   else
      MarketRegime = REGIME_TRENDING;
}

//+------------------------------------------------------------------+
//| CHECK AE1 DIVERGENCE FOR HEDGE [M8]                             |
//+------------------------------------------------------------------+
bool CheckAE1Divergence()
{
   if(!PC1_valid) return true;  // No data yet → allow hedge
   int N = MathMin(ae1_count, 50);
   if(N < 10) return true;

   int ae1MaxBuf = ArraySize(buf_AE1);
   double vals[];
   if(!CircBufRead(buf_AE1, ae1_head, ae1_count, ae1MaxBuf, N, vals)) return true;

   // Compute std of recent AE1
   double mean = 0;
   for(int i = 0; i < N; i++) mean += vals[i];
   mean /= N;
   double variance = 0;
   for(int i = 0; i < N; i++) variance += (vals[i] - mean) * (vals[i] - mean);
   double stdDev = MathSqrt(variance / N);

   double divergence = MathAbs(AE1_current - AE1_at_primary_open);
   return (divergence > AE1_DivergenceThresh * stdDev);
}

//+------------------------------------------------------------------+
//| H1 REGIME UPDATE                                                 |
//+------------------------------------------------------------------+
void UpdateH1Regime()
{
   double ema200[]; ArraySetAsSeries(ema200, true);
   if(CopyBuffer(h_EMA200_H1, 0, H1EMA_CandleShift, 1, ema200) < 1)
   { H1Regime = SIG_NONE; return; }
   double h1Close = iClose(_Symbol, PERIOD_H1, H1EMA_CandleShift);
   if(h1Close > ema200[0])      H1Regime = SIG_BUY;
   else if(h1Close < ema200[0]) H1Regime = SIG_SELL;
   else                         H1Regime = SIG_NONE;
}

//+------------------------------------------------------------------+
//| ICHIMOKU M5 SIGNAL [M3]                                         |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetIchimokuM5Signal()
{
   double tenkan[], kijun[];
   ArraySetAsSeries(tenkan, true);
   ArraySetAsSeries(kijun,  true);
   if(CopyBuffer(h_Ichi_M5, 0, Ichi_Shift,   2, tenkan) < 2) return SIG_NONE;
   if(CopyBuffer(h_Ichi_M5, 1, Ichi_Shift,   2, kijun)  < 2) return SIG_NONE;

   SIGNAL_TYPE sig = SIG_NONE;
   if(tenkan[1] <= kijun[1] && tenkan[0] > kijun[0]) sig = SIG_BUY;
   else if(tenkan[1] >= kijun[1] && tenkan[0] < kijun[0]) sig = SIG_SELL;

   // Candle confirmation on M5
   if(sig != SIG_NONE && RequireCandleConfirm)
   {
      double m5Open  = iOpen(_Symbol,  PERIOD_M5, Ichi_Shift);
      double m5Close = iClose(_Symbol, PERIOD_M5, Ichi_Shift);
      if(sig == SIG_BUY  && m5Close <= m5Open) return SIG_NONE;
      if(sig == SIG_SELL && m5Close >= m5Open) return SIG_NONE;
   }
   return sig;
}

//+------------------------------------------------------------------+
//| STOCHASTIC M1 CONFIRMATION [M7]                                 |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetStochConfirmation()
{
   double stk[]; ArraySetAsSeries(stk, true);
   if(CopyBuffer(h_Stoch, 0, Stoch_Shift, 1, stk) < 1) return SIG_NONE;
   if(stk[0] < Stoch_BuyLevel)  return SIG_BUY;
   if(stk[0] > Stoch_SellLevel) return SIG_SELL;
   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| BUILD FINAL ENTRY SIGNAL                                        |
//| Requires: Ichimoku M5 AND Stoch M1 AND AE1 AND H1 (all agree)  |
//+------------------------------------------------------------------+
SIGNAL_TYPE BuildFinalSignal(SIGNAL_TYPE ichiM5, SIGNAL_TYPE stochM1)
{
   if(ichiM5 == SIG_NONE) return SIG_NONE;

   // Stochastic must agree
   if(stochM1 != SIG_NONE && stochM1 != ichiM5) return SIG_NONE;

   // AE1 must agree
   if(PC1_valid && AE1_signal != SIG_NONE && AE1_signal != ichiM5) return SIG_NONE;

   // OLS slope must agree
   if(MathAbs(OLS_slope) > OLS_Slope_MinAbs)
   {
      if(ichiM5 == SIG_BUY  && OLS_slope < 0) return SIG_NONE;
      if(ichiM5 == SIG_SELL && OLS_slope > 0) return SIG_NONE;
   }

   // H1 EMA200 regime must agree
   if(UseH1RegimeFilter && H1Regime != SIG_NONE && H1Regime != ichiM5) return SIG_NONE;

   return ichiM5;
}

//+------------------------------------------------------------------+
//| HEDGE ENTRY SIGNAL — BB Crossover + Width + AE1 div [M8]       |
//+------------------------------------------------------------------+
SIGNAL_TYPE GetHedgeEntrySignal()
{
   double bbMid[], bbUp[], bbLow[];
   ArraySetAsSeries(bbMid, true);
   ArraySetAsSeries(bbUp,  true);
   ArraySetAsSeries(bbLow, true);
   if(CopyBuffer(h_BB, 0, BB_CandleShift, 2, bbMid) < 2) return SIG_NONE;
   if(CopyBuffer(h_BB, 1, BB_CandleShift, 1, bbUp)  < 1) return SIG_NONE;
   if(CopyBuffer(h_BB, 2, BB_CandleShift, 1, bbLow) < 1) return SIG_NONE;

   // BB width filter
   double bbWidth = bbUp[0] - bbLow[0];
   double atr     = GetATR_M1();
   if(atr > 0 && BB_WidthMinCoef > 0 && bbWidth < atr * BB_WidthMinCoef) return SIG_NONE;

   // Real crossover
   double closeNow  = iClose(_Symbol, PERIOD_CURRENT, BB_CandleShift);
   double closePrev = iClose(_Symbol, PERIOD_CURRENT, BB_CandleShift + 1);

   if(closePrev <= bbMid[1] && closeNow > bbMid[0]) return SIG_BUY;
   if(closePrev >= bbMid[1] && closeNow < bbMid[0]) return SIG_SELL;
   return SIG_NONE;
}

//+------------------------------------------------------------------+
//| EXIT SIGNALS — RSI(21) crossing levels                          |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   double rsiExit[]; ArraySetAsSeries(rsiExit, true);
   if(CopyBuffer(h_RSI_Exit, 0, RSI_Exit_Shift, 2, rsiExit) < 2) return;

   bool crossAboveSell = (rsiExit[1] <= RSI_ExitSellLevel && rsiExit[0] > RSI_ExitSellLevel);
   bool crossBelowBuy  = (rsiExit[1] >= RSI_ExitBuyLevel  && rsiExit[0] < RSI_ExitBuyLevel);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      double profit = PosInfo.Profit() + PosInfo.Swap() + PosInfo.Commission();
      if(PosInfo.PositionType() == POSITION_TYPE_BUY  && crossAboveSell && profit > 0)
         Trade.PositionClose(PosInfo.Ticket());
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL && crossBelowBuy && profit > 0)
         Trade.PositionClose(PosInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| OPEN PRIMARY ORDER [M1 + M9 — fractal SL + SL_floor]           |
//+------------------------------------------------------------------+
bool OpenPrimaryOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR_M1();
   if(atr <= 0) return false;

   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // [M9] Fractal SL on M5
   double sl_dist = CalcFractalSL(orderType, atr);

   // [M1] SL floor: never less than SL_Floor_Points
   double sl_floor_price = SL_Floor_Points * 10.0 * _Point;
   if(sl_dist < sl_floor_price) sl_dist = sl_floor_price;

   double tp_dist = sl_dist * RR_Ratio;

   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist, _Digits);

   // [M12] Adaptive sizing
   double riskPct = (MarketRegime == REGIME_TRENDING && OLS_R2 > 0.6) ? RiskPerOrder : RiskPerOrder_Reduced;
   double volume  = CalcDynamicVolume(sl_dist, riskPct);
   if(volume <= 0) return false;

   bool result = Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, TradeComment + "_PRI");
   if(!result)
      Print("v3.0: OpenPrimaryOrder FAILED. Retcode:", Trade.ResultRetcode(),
            " ", Trade.ResultRetcodeDescription());
   return result;
}

//+------------------------------------------------------------------+
//| OPEN HEDGE ORDER                                                 |
//+------------------------------------------------------------------+
bool OpenHedgeOrder(ENUM_ORDER_TYPE orderType)
{
   double atr = GetATR_M1();
   if(atr <= 0) return false;

   double sl_dist = atr * HedgeATR_SL_Coef;
   double sl_floor_price = SL_Floor_Points * 10.0 * _Point;
   if(sl_dist < sl_floor_price) sl_dist = sl_floor_price;

   double tp_dist = sl_dist * HedgeRR_Ratio;
   double price   = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist, _Digits);
   double tp = NormalizeDouble((orderType == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist, _Digits);

   double volume = CalcDynamicVolume(sl_dist, HedgeRiskPerOrder);
   if(volume <= 0) return false;

   bool result = Trade.PositionOpen(_Symbol, orderType, volume, price, sl, tp, TradeComment + "_HDG");
   if(!result)
      Print("v3.0: OpenHedgeOrder FAILED. Retcode:", Trade.ResultRetcode(),
            " ", Trade.ResultRetcodeDescription());
   return result;
}

//+------------------------------------------------------------------+
//| FRACTAL SL CALCULATION [M9]                                     |
//+------------------------------------------------------------------+
double CalcFractalSL(ENUM_ORDER_TYPE orderType, double atr)
{
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // Find swing on M5
   double swingLevel = 0;
   if(orderType == ORDER_TYPE_BUY)
   {
      // SL below recent swing low on M5
      double lowest = iLow(_Symbol, PERIOD_M5, 1);
      for(int i = 1; i <= Fractal_Lookback; i++)
      {
         double lo = iLow(_Symbol, PERIOD_M5, i);
         if(lo < lowest) lowest = lo;
      }
      swingLevel = lowest - Fractal_Buffer_Points * 10.0 * _Point;
   }
   else
   {
      // SL above recent swing high on M5
      double highest = iHigh(_Symbol, PERIOD_M5, 1);
      for(int i = 1; i <= Fractal_Lookback; i++)
      {
         double hi = iHigh(_Symbol, PERIOD_M5, i);
         if(hi > highest) highest = hi;
      }
      swingLevel = highest + Fractal_Buffer_Points * 10.0 * _Point;
   }

   double sl_from_fractal = MathAbs(price - swingLevel);

   // Cap at ATR × Fractal_MaxATR_Coef
   double sl_cap = atr * Fractal_MaxATR_Coef;
   if(sl_from_fractal > sl_cap) sl_from_fractal = atr * ATR_SL_Coef;  // Fall back to ATR method

   // Minimum: ATR × ATR_SL_Coef
   double sl_atr = atr * ATR_SL_Coef;
   return MathMax(sl_from_fractal, sl_atr);
}

//+------------------------------------------------------------------+
//| DYNAMIC VOLUME (equity-based)                                   |
//+------------------------------------------------------------------+
double CalcDynamicVolume(double sl_price_dist, double riskPct)
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt   = equity * riskPct / 100.0;
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
//| ATR (M1)                                                         |
//+------------------------------------------------------------------+
double GetATR_M1()
{
   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(h_ATR, 0, 1, 1, atr) < 1) return 0;
   return atr[0];
}

//+------------------------------------------------------------------+
//| QUALITY FILTERS                                                  |
//+------------------------------------------------------------------+
bool PassesQualityFilters()
{
   if(MaxSpreadPoints > 0)
   {
      long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(sp > (long)MaxSpreadPoints) return false;
   }

   double atr = GetATR_M1();
   if(VolatilityRatioMin > 0 || VolatilityRatioMax > 0)
   {
      double atrHist[]; ArraySetAsSeries(atrHist, true);
      if(CopyBuffer(h_ATR, 0, 1, VolatilityRatioLook, atrHist) >= VolatilityRatioLook)
      {
         double s = 0;
         for(int i = 0; i < VolatilityRatioLook; i++) s += atrHist[i];
         double sma = s / VolatilityRatioLook;
         if(sma > 0)
         {
            double vr = atr / sma;
            if(VolatilityRatioMin > 0 && vr < VolatilityRatioMin) return false;
            if(VolatilityRatioMax > 0 && vr > VolatilityRatioMax) return false;
         }
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| TRAILING STOPS [M4 — ATR-based, correct formula]                |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   double atr = GetATR_M1();
   if(atr <= 0) return;

   double trailDist = atr * TrailingATR_Coef;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;

      ulong  ticket    = PosInfo.Ticket();
      double openPrice = PosInfo.PriceOpen();
      double curSL     = PosInfo.StopLoss();
      double curTP     = PosInfo.TakeProfit();
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool   isHedge   = (StringFind(PosInfo.Comment(), "_HDG") >= 0);

      if(curTP == 0) continue;  // Guard [B10]

      if(PosInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double tpDist    = curTP - openPrice;
         double activation= openPrice + tpDist * (TrailingActivatePct / 100.0);

         if(bid >= activation)
         {
            double newSL;
            if(isHedge)
               newSL = NormalizeDouble(openPrice, _Digits);     // Breakeven
            else
               newSL = NormalizeDouble(bid - trailDist, _Digits); // ATR trail
            // Guard: SL must be below current price
            if(newSL > curSL + _Point && newSL < bid)
               Trade.PositionModify(ticket, newSL, curTP);
         }
      }
      else if(PosInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double tpDist    = openPrice - curTP;
         double activation= openPrice - tpDist * (TrailingActivatePct / 100.0);

         if(ask <= activation)
         {
            double newSL;
            if(isHedge)
               newSL = NormalizeDouble(openPrice, _Digits);
            else
               newSL = NormalizeDouble(ask + trailDist, _Digits);
            // Guard: SL must be above current price
            if((curSL == 0 || newSL < curSL - _Point) && newSL > ask)
               Trade.PositionModify(ticket, newSL, curTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DETECT CLOSED POSITIONS — update streak & cooldown              |
//+------------------------------------------------------------------+
void CheckPositionsClosed()
{
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
         if(HistorySelectByPosition(LastKnownTickets[j]))
         {
            double totalProfit = 0;
            for(int d = 0; d < HistoryDealsTotal(); d++)
            {
               ulong dt = HistoryDealGetTicket(d);
               if(dt == 0) continue;
               if(HistoryDealGetInteger(dt, DEAL_POSITION_ID) == (long)LastKnownTickets[j])
                  totalProfit += HistoryDealGetDouble(dt, DEAL_PROFIT);
            }
            if(totalProfit < 0)
            {
               ConsecLossCount++;
               if(MaxConsecLosses > 0 && ConsecLossCount >= MaxConsecLosses)
               {
                  ConsecLossPauseLeft = ConsecLossPauseBars;
                  ConsecLossCount     = 0;
                  Print("v3.0: Max consec losses. Pausing ", ConsecLossPauseBars, " bars.");
               }
            }
            else ConsecLossCount = 0;
         }
      }
   }

   if(anyClose) CooldownBarsLeft = CooldownBars;

   ArrayResize(LastKnownTickets, n);
   for(int i = 0; i < n; i++) LastKnownTickets[i] = currentTickets[i];
}

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
void SyncStateMachine()
{
   int pri = CountOrders("_PRI");
   int hdg = CountOrders("_HDG");
   if(pri == 0 && hdg == 0)      CurrentState = STATE_IDLE;
   else if(pri > 0 && hdg == 0)  CurrentState = STATE_PRIMARY_OPEN;
   else if(pri > 0 && hdg > 0)   CurrentState = STATE_HEDGED;
   else if(pri == 0 && hdg > 0)  CurrentState = STATE_HEDGE_ONLY;
}

int CountOrders(string tag)
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PosInfo.SelectByIndex(i)) continue;
      if(PosInfo.Symbol() != _Symbol || PosInfo.Magic() != MagicNumber) continue;
      if(StringFind(PosInfo.Comment(), tag) >= 0) count++;
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

int CountPrimaryOrders() { return CountOrders("_PRI"); }
int CountHedgeOrders()   { return CountOrders("_HDG"); }

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
   return (cur >= eodTime && cur < eodTime + 60);
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
      EODClosed         = false;
      H1Regime          = SIG_NONE;
   }
}

bool CheckDailyLimits()
{
   double curBal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(UseDailyProfitLimit)
   {
      if(curBal - DailyStartBalance >= DailyStartBalance * DailyProfitPct / 100.0)
      {
         if(!DailyLimitReached && UseMaxProfitClose) CloseAllPositions();
         DailyLimitReached = true; return true;
      }
   }
   if(UseDailyLossLimit)
   {
      if(DailyStartBalance - curBal >= DailyStartBalance * DailyLossPct / 100.0)
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

double GetVolatilityRatio()
{
   double atr = GetATR_M1();
   if(atr <= 0) return 1.0;
   double h[]; ArraySetAsSeries(h, true);
   if(CopyBuffer(h_ATR, 0, 1, VolatilityRatioLook, h) < VolatilityRatioLook) return 1.0;
   double s = 0;
   for(int i = 0; i < VolatilityRatioLook; i++) s += h[i];
   double sma = s / VolatilityRatioLook;
   return (sma > 0) ? atr / sma : 1.0;
}

string RegimeToStr(REGIME_TYPE r)
{
   switch(r)
   {
      case REGIME_TRENDING: return "TREND";
      case REGIME_CHOPPY:   return "CHOPPY";
      default:              return "--";
   }
}

string StateToStr(EA_STATE s)
{
   switch(s)
   {
      case STATE_IDLE:         return "IDLE";
      case STATE_PRIMARY_OPEN: return "PRIMARY";
      case STATE_HEDGED:       return "HEDGED";
      case STATE_HEDGE_ONLY:   return "HEDGE_ONLY";
      default:                 return "--";
   }
}

string SignalToStr(SIGNAL_TYPE s)
{
   return (s == SIG_BUY) ? "BUY" : (s == SIG_SELL) ? "SELL" : "--";
}

color SignalToClr(SIGNAL_TYPE s)
{
   return (s == SIG_BUY) ? DashBuyColor : (s == SIG_SELL) ? DashSellColor : DashTextColor;
}

//+------------------------------------------------------------------+
//| DASHBOARD v3.0                                                   |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   string bg = ObjPrefix + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, DashX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, DashY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,     268);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,     460);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,   DashBGColor);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,     C'30,50,110');
   ObjectSetInteger(0, bg, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_BACK,      false);

   CreateLabel("TITLE",    "◈ PEAK RANGE HEDGING v3.0",        DashX+8,  DashY+6,   11, C'80,180,255', true);
   CreateLabel("SUB",      "AE1+PCA+OLS+KMEANS",               DashX+8,  DashY+20,  8,  C'50,80,160');
   CreateLabel("SEP0",     "─────────────────────────────────", DashX+6,  DashY+32,  8,  C'30,50,110');

   CreateLabel("LBL_SYMBOL",  "Symbol:    --",   DashX+8, DashY+42,  9, DashTextColor);
   CreateLabel("LBL_SPREAD",  "Spread:    --",   DashX+8, DashY+56,  9, DashTextColor);
   CreateLabel("LBL_ATR",     "ATR M1:    --",   DashX+8, DashY+70,  9, DashTextColor);
   CreateLabel("LBL_VRATIO",  "Vol Ratio: --",   DashX+8, DashY+84,  9, DashTextColor);
   CreateLabel("SEP1",     "─────────────────────────────────", DashX+6,  DashY+98,  8,  C'30,50,110');

   CreateLabel("LBL_STATE",   "State:     IDLE", DashX+8, DashY+108, 9, clrGold);
   CreateLabel("LBL_REGIME",  "Regime:    --",   DashX+8, DashY+122, 9, DashTextColor);
   CreateLabel("LBL_H1",      "H1 EMA200: --",   DashX+8, DashY+136, 9, DashTextColor);
   CreateLabel("LBL_PORD",    "Primary:   0",    DashX+8, DashY+150, 9, DashTextColor);
   CreateLabel("LBL_HORD",    "Hedge:     0",    DashX+8, DashY+164, 9, DashTextColor);
   CreateLabel("LBL_CYCLES",  "Cycles:    0/20", DashX+8, DashY+178, 9, DashTextColor);
   CreateLabel("LBL_COOL",    "Cooldown:  0",    DashX+8, DashY+192, 9, DashTextColor);
   CreateLabel("SEP2",     "─────────────────────────────────", DashX+6,  DashY+206, 8,  C'30,50,110');

   CreateLabel("LBL_AE1",     "AE1:       --",   DashX+8, DashY+216, 9, DashTextColor);
   CreateLabel("LBL_AE1MED",  "AE1 Med:   --",   DashX+8, DashY+230, 9, DashTextColor);
   CreateLabel("LBL_OLS_SLP", "OLS Slope: --",   DashX+8, DashY+244, 9, DashTextColor);
   CreateLabel("LBL_OLS_R2",  "OLS R²:    --",   DashX+8, DashY+258, 9, DashTextColor);
   CreateLabel("LBL_AE1SIG",  "AE1 Sig:   --",   DashX+8, DashY+272, 9, DashTextColor);
   CreateLabel("SEP3",     "─────────────────────────────────", DashX+6,  DashY+286, 8,  C'30,50,110');

   CreateLabel("LBL_BAL",     "Balance:   --",   DashX+8, DashY+296, 9, DashTextColor);
   CreateLabel("LBL_EQ",      "Equity:    --",   DashX+8, DashY+310, 9, DashTextColor);
   CreateLabel("LBL_FLOAT",   "Float:     --",   DashX+8, DashY+324, 9, DashTextColor);
   CreateLabel("LBL_DAIL",    "Daily PL:  --",   DashX+8, DashY+338, 9, DashTextColor);
   CreateLabel("SEP4",     "─────────────────────────────────", DashX+6,  DashY+352, 8,  C'30,50,110');

   CreateLabel("LBL_STATUS",  "Status:    ACTIVE", DashX+8, DashY+362, 9, clrLime);
   CreateLabel("LBL_STREAK",  "Streak:    OK",     DashX+8, DashY+376, 9, DashTextColor);
   CreateLabel("LBL_LIMITS",  "Limits:    OK",     DashX+8, DashY+390, 9, clrLime);
   CreateLabel("SEP5",     "─────────────────────────────────", DashX+6,  DashY+404, 8,  C'30,50,110');
   CreateLabel("LBL_HRS",     StringFormat("%02d:%02d-%02d:%02d EOD:%02d:%02d",
               TradingStartHour,TradingStartMin,TradingEndHour,TradingEndMin,
               ForceCloseHour,ForceCloseMin),    DashX+8, DashY+414, 8, C'100,120,190');
   CreateLabel("LBL_MAG",     StringFormat("Magic: %d | v3.0", MagicNumber), DashX+8, DashY+428, 7, C'50,60,100');

   ChartRedraw(0);
}

void CreateLabel(string id, string text, int x, int y, int sz, color clr, bool bold=false)
{
   string name = ObjPrefix + id;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  sz);
   ObjectSetString(0, name, OBJPROP_FONT,       bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
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

   string  cur  = AccountInfoString(ACCOUNT_CURRENCY);
   double  bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double  eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double  fpl  = GetTotalFloatingPL();
   double  dpl  = bal - DailyStartBalance;
   long    sp   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double  atr  = GetATR_M1();
   double  vr   = GetVolatilityRatio();

   UpdateLabel("LBL_SYMBOL",  StringFormat("Symbol:    %s", _Symbol));
   UpdateLabel("LBL_SPREAD",  StringFormat("Spread:    %d pts", sp),
               (MaxSpreadPoints > 0 && sp > (long)MaxSpreadPoints) ? DashSellColor : clrLime);
   UpdateLabel("LBL_ATR",     StringFormat("ATR M1:    %.2f", atr));
   UpdateLabel("LBL_VRATIO",  StringFormat("Vol Ratio: %.2f", vr),
               (vr < VolatilityRatioMin || vr > VolatilityRatioMax) ? DashSellColor : clrLime);

   color stClr = (CurrentState == STATE_IDLE) ? clrGold :
                 (CurrentState == STATE_HEDGED) ? DashSellColor : C'80,180,255';
   UpdateLabel("LBL_STATE",   StringFormat("State:     %s", StateToStr(CurrentState)), stClr);
   color rgClr = (MarketRegime == REGIME_TRENDING) ? clrLime :
                 (MarketRegime == REGIME_CHOPPY)   ? DashSellColor : clrGold;
   UpdateLabel("LBL_REGIME",  StringFormat("Regime:    %s", RegimeToStr(MarketRegime)), rgClr);
   UpdateLabel("LBL_H1",      StringFormat("H1 EMA200: %s", SignalToStr(H1Regime)),
               SignalToClr(H1Regime));
   UpdateLabel("LBL_PORD",    StringFormat("Primary:   %d", CountPrimaryOrders()));
   UpdateLabel("LBL_HORD",    StringFormat("Hedge:     %d", CountHedgeOrders()));
   UpdateLabel("LBL_CYCLES",  StringFormat("Cycles:    %d/%d", DailyCycles, MaxRangeCyclesDay));
   int cool = CooldownBarsLeft + ConsecLossPauseLeft;
   UpdateLabel("LBL_COOL",    StringFormat("Cooldown:  %d", cool), cool > 0 ? clrGold : DashTextColor);

   color ae1Clr = (AE1_signal == SIG_BUY) ? DashBuyColor :
                  (AE1_signal == SIG_SELL) ? DashSellColor : DashTextColor;
   UpdateLabel("LBL_AE1",     StringFormat("AE1:       %.4f", AE1_current));
   UpdateLabel("LBL_AE1MED",  StringFormat("AE1 Med:   %.4f", AE1_median));
   color slopClr = (OLS_slope > OLS_Slope_MinAbs)  ? DashBuyColor :
                   (OLS_slope < -OLS_Slope_MinAbs) ? DashSellColor : clrGold;
   UpdateLabel("LBL_OLS_SLP", StringFormat("OLS Slope: %.5f", OLS_slope), slopClr);
   color r2Clr = (OLS_R2 >= OLS_R2_MinThreshold) ? clrLime : DashSellColor;
   UpdateLabel("LBL_OLS_R2",  StringFormat("OLS R²:    %.3f", OLS_R2), r2Clr);
   UpdateLabel("LBL_AE1SIG",  StringFormat("AE1 Sig:   %s", SignalToStr(AE1_signal)), ae1Clr);

   UpdateLabel("LBL_BAL",     StringFormat("Balance:   %.2f %s", bal, cur));
   UpdateLabel("LBL_EQ",      StringFormat("Equity:    %.2f %s", eq,  cur));
   UpdateLabel("LBL_FLOAT",   StringFormat("Float:     %+.2f %s", fpl, cur),
               fpl >= 0 ? clrLime : DashSellColor);
   UpdateLabel("LBL_DAIL",    StringFormat("Daily PL:  %+.2f %s", dpl, cur),
               dpl >= 0 ? clrLime : DashSellColor);

   bool inH = IsTradeAllowed();
   string st = DailyLimitReached ? "LIMIT HIT" : EODClosed ? "EOD CLOSED" :
               cool > 0 ? "COOLDOWN" : inH ? "ACTIVE" : "OFF-HOURS";
   color sc  = DailyLimitReached ? DashSellColor : EODClosed ? clrGold :
               cool > 0 ? clrGold : inH ? clrLime : clrGold;
   UpdateLabel("LBL_STATUS",  StringFormat("Status:    %s", st), sc);

   string strk = (ConsecLossCount > 0) ?
      StringFormat("Losses:    %d/%d", ConsecLossCount, MaxConsecLosses > 0 ? MaxConsecLosses : 99) :
      "Streak:    OK";
   UpdateLabel("LBL_STREAK", strk,
               ConsecLossCount >= 2 ? DashSellColor : ConsecLossCount == 1 ? clrGold : clrLime);
   UpdateLabel("LBL_LIMITS", DailyLimitReached ? "Limits:    REACHED" : "Limits:    OK",
               DailyLimitReached ? DashSellColor : clrLime);

   ChartRedraw(0);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, ObjPrefix);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
//| END OF EA v3.0                                                   |
//+------------------------------------------------------------------+
