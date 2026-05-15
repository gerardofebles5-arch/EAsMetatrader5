//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.0 — PREDICTIVE ENGINE: QUALITY FILTER (NOT DIRECTION)    |
//|                                                                  |
//|  FIX v17: PROBLEMA CRITICO EN v15 Y v16                       |
//|  El motor predictivo competía BUY vs SELL y SIEMPRE ganaba     |
//|  el mismo lado (el que el mercado favorecía ese día).          |
//|  v15: solo SELL. v16: solo BUY. Mismo bug, dirección opuesta. |
//|                                                                  |
//|  CAUSA RAIZ:                                                   |
//|  GetPredictiveSignal() calculaba score_buy y score_sell, y     |
//|  el ganador era siempre el mismo porque MTF/MomentumBias son  |
//|  persistentes (se quedan en la misma dirección horas/días).   |
//|  → El Stochastic (que sí alterna BUY/SELL cada minuto) quedaba|
//|    bloqueado por el sesgo de las otras capas.                 |
//|                                                                  |
//|  SOLUCIÓN v17: CalcQualityScore(dir)                          |
//|  El motor ya NO decide la dirección.                          |
//|  La dirección viene SIEMPRE del Stochastic (como en backtest) |
//|  El motor solo responde: "¿esta señal Stoch tiene calidad?"   |
//|  Si score >= Min_Prediction_Score → ejecutar.                 |
//|  Si no → ignorar esa señal particular.                        |
//|                                                                  |
//|  RESULTADO:                                                    |
//|  BUY cuando Stoch dice BUY Y tiene calidad confirmada.        |
//|  SELL cuando Stoch dice SELL Y tiene calidad confirmada.      |
//|  Nunca bloquea una dirección entera por sesgo de tendencia.   |
//|                                                                  |
//|  Trailing inteligente por lotaje (v16) mantenido.             |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.00"
#property strict

// +++ Main Parameters +++
input bool   Control_orders_user         = true;
input int    Max_Buy                     = 100;
input int    Max_Sell                    = 100;
input string CommentOrder                = "MoneyMachine7";
input double Lot_                        = 0.1;
input bool   Use_dynamic_lot_            = true;
input double Free_margin_for_each_Lots_  = 1000.0;
input double Kmartin_                    = 1.0;
input double Max_Lot_                    = 5.0;
// +++ Breakout Strategy (v2.1) +++
input bool   Enable_Breakout_Strategy    = true;
input int    Breakout_Period             = 50;
input int    Breakout_Buffer             = 120;
input int    Min_Breakout_Range          = 300;
input bool   Use_RSI_Confirmation        = true;
input int    RSI_Period                  = 14;
input double RSI_Buy_Threshold           = 66.0;
input double RSI_Sell_Threshold          = 44.0;
input bool   Use_Volume_Confirmation     = true;
input int    Volume_Ma_Period            = 10;
input bool   Use_Gold_Session_Filter     = false;
// +++ Auto Grid System (ADR) +++
input bool   Use_Auto_Grid               = true;
input int    Auto_Grid_Intensity         = 3;
input double Custom_ADR_Divider          = 1000.0;
input int    ADR_Period_Days             = 1;
// +++ Auto Take Profit (v7.5.5) +++
input bool   Use_Auto_TP                 = true;
input double Auto_TP_Ratio               = 5.0;
// +++ Auto Stop Loss (v2.3) +++
input bool   Use_Auto_SL                 = true;
input double Auto_SL_Ratio               = 1.5;
// +++ Manual Grid Settings (Fallback) +++
input double Grid_Distance_              = 0.0;
input int    Take_Profit_                = 0;
input int    Stop_Loss_                  = 0;
input double Stop_Loss_Percent           = 0.0;
// +++ Smart Grid Defense (v7.5.4) +++
input bool   Use_Grid_Stoch_Filter       = true;
input int    Stoch_K_Period              = 14;
input int    Stoch_D_Period              = 3;
input int    Stoch_Slowing               = 3;
input double Stoch_Buy_Level             = 30.0;
input double Stoch_Sell_Level            = 70.0;
input double Grid_Distance_Multiplier    = 1.0;
input double Max_Drawdown_Percent        = 90.0;
// +++ News Filter +++
input bool   Use_News_Filter             = true;
input int    News_Suspend_Mins_Before    = 30;
input int    News_Suspend_Mins_After     = 30;
// +++ Monday +++
input bool   Trade_Monday                = true;
input int    Monday_Start_Hour           = 5;
input int    Monday_End_Hour             = 21;
// +++ Tuesday +++
input bool   Trade_Tuesday               = true;
input int    Tuesday_Start_Hour          = 5;
input int    Tuesday_End_Hour            = 21;
// +++ Wednesday +++
input bool   Trade_Wednesday             = true;
input int    Wednesday_Start_Hour        = 5;
input int    Wednesday_End_Hour          = 21;
// +++ Thursday +++
input bool   Trade_Thursday              = true;
input int    Thursday_Start_Hour         = 5;
input int    Thursday_End_Hour           = 21;
// +++ Friday +++
input bool   Trade_Friday                = true;
input int    Friday_Start_Hour           = 5;
input int    Friday_End_Hour             = 18;
// +++ Saturday +++
input bool   Trade_Saturday              = false;
input int    Saturday_Start_Hour         = 0;
input int    Saturday_End_Hour           = 0;
// +++ Sunday +++
input bool   Trade_Sunday                = false;
input int    Sunday_Start_Hour           = 0;
input int    Sunday_End_Hour             = 0;
// +++ Institutional Stealth & Recovery (v2.2) +++
input bool   Use_Stealth_Mode            = true;
input bool   Recovery_Mode_Enabled       = true;
input double Recovery_Target_USD         = 2.0;
input int    Overlap_AFTER_X_trades_     = 4;
// +++ Distance Expansion +++
input int    Order_dynamic_distance      = 4;
input double Distance_multiplier         = 1.0;
// Core Strategy (Signals)
input int    InpStrategy                 = 1;
input bool   Enable_Stop_Hunt_Strategy   = true;
input bool   Enable_FVG_Strategy         = true;
input int    InpMagicNumber              = 700000;
input int    ATR_Period                  = 7;
input int    FVG_Lookback_Bars           = 1200;
// Trade Filters
input int    InpMaxSpreadPoints          = 10000;
input int    InpSlippagePoints           = 10;
input bool   Enable_Trend_Filter         = true;
input int    Trend_MA_Period             = 200;
// Dashboard Settings
input bool   Enable_Dashboard            = true;
input int    Dashboard_Corner            = 0;
input int    Dashboard_X_Offset          = 10;
input int    Dashboard_Y_Offset          = 30;
input int    Refresh_Interval_Seconds    = 1;
input bool   Draw_FVG_Zones              = true;
input int    Font_size_Result            = 11;
// +++ Money Management +++
input double Basket_Profit_USD           = 0.0;
input double Basket_Loss_USD             = 0.0;
input double Daily_Profit_Target_USD     = 1000000.0;
input double Daily_Loss_Limit_USD        = 500000.0;
input double InpMaxDailyLossPct          = 50.0;
input double InpMaxEquityDrawdown        = 50.0;
input int    Stop_After_Losses           = 0;
// +++ Trailing & Breakeven +++
input bool   Enable_Breakeven            = false;
input double BE_Trigger_ATR_Multiplier   = 1.0;
input int    BE_Profit_Points            = 10;
input bool   Enable_TrailingStop         = true;
input double TS_Start_ATR_Multiplier     = 5.0;
input double TS_Distance_ATR_Multiplier  = 5.0;
// +++ History Visualization +++
input bool   Enable_History_Labels       = true;
input int    History_Labels_Limit        = 50;
// +++ Trailing Profit System (v14) +++
// MODO 1: TP por USD mínimo (cierre inmediato al alcanzar el umbral)
input bool   Enable_MinUSD_TP            = false;  // activar cierre por USD mínimo
input double TP_Min_USD                  = 1.0;    // profit mínimo en USD para cerrar (ej: $1 = ~1pt con lot 0.01)
// MODO 2: Trailing Profit (sigue el máximo, cierra al retroceder)
input bool   Enable_Trailing_Profit      = true;   // activar trailing profit (RECOMENDADO)
input double TP_Trail_Activate_USD       = 0.50;   // USD de profit para activar el trailing (ej: $0.50)
input double TP_Trail_Retrace_USD        = 0.30;   // USD de retroceso desde el máximo para cerrar (ej: $0.30)
// NOTA: los dos modos pueden coexistir. MinUSD_TP cierra primero si se alcanza antes.
// +++ PREDICTIVE INTELLIGENCE ENGINE (v15) +++
// CAPA 1: Confluencia Multi-Timeframe
input bool   Enable_MTF_Confluence       = true;   // exige alineación en múltiples timeframes
input int    MTF_Min_Confluence          = 2;      // mínimo de timeframes alineados (2 de 3: M1+M5+M15)
// CAPA 2: Order Flow Bias
input bool   Enable_OrderFlow_Bias       = true;   // detecta presión compradora/vendedora via delta volumen
input int    OrderFlow_Bars              = 8;      // barras de ventana para calcular delta de volumen
input double OrderFlow_Min_Delta         = 0.20;   // mínimo desequilibrio (0.20 = 20% más compra que venta)
// CAPA 3: Momentum Predictivo (EMA Cross Temprano)
input bool   Enable_EMA_Momentum         = true;   // EMA rápida vs lenta como predictor de dirección
input int    EMA_Fast_Period             = 3;      // EMA rápida (detecta giro en formación)
input int    EMA_Slow_Period             = 8;      // EMA lenta (confirma tendencia corta)
// CAPA 4: Estructura de Precio (HH/HL detection)
input bool   Enable_Price_Structure      = true;   // detecta estructura alcista/bajista en últimas N barras
input int    Structure_Lookback          = 6;      // barras hacia atrás para detectar swing structure
input double Structure_Min_ATR           = 0.3;    // mínimo tamaño de swing válido en ATR (filtra ruido)
// CAPA 5: Score mínimo para entrada
input int    Min_Prediction_Score        = 3;      // score mínimo de 5 capas para abrir (3=balanceado, 4=conservador, 5=muy selectivo)
// +++ Forensic Core +++
input double MM7_TP_FIXED                = 2.50;
input double MM7_SL_FIXED                = 0.77;
input double MM7_G2_SL_FIXED             = 0.50;
// +++ v8.17 Signal Quality +++
input bool   Enable_Zone_Exit_Filter     = false; // ZoneFreshEntry (OFF=stoch puro como original)
input bool   Enable_Candle_Filter        = false; // ✗ DEMOSTRADO: reduce WR (OFF=como original)
input bool   Enable_BOS_Filter           = false; // Break of Structure (OFF=como original)
input int    BOS_Lookback                = 5;
input double ATR_HighVol_Multiplier      = 1.8;   // ATR alta volatilidad → modo Sweep únicamente
input int    G2_Min_Seconds              = 30;    // segundos mínimos legacy abierto antes de G2 (median original: 31s)
// +++ v10.0 Entry Quality Control +++
input int    Entry_Cooldown_Secs         = 30;    // cooldown entre señales Stoch (evita re-entradas del mismo ciclo)
input int    PostClose_Lockout_Secs      = 15;    // lockout tras cierre de posición (SL→no re-entrar inmediato)
input double Stoch_Depth_Buy             = 25.0;  // K máximo para BUY alta convicción (≤25 = deep oversold)
input double Stoch_Depth_Sell            = 75.0;  // K mínimo para SELL alta convicción (≥75 = deep overbought)
input bool   Enable_Stoch_Depth_Filter   = true;  // exige K en zona profunda para entrar (ON = más selectivo)
// +++ v8.18 Intraday Intelligence +++
input bool   Enable_EMA20_Gate           = false;  // EMA50 gate (OFF: demostrado que reduce trades sin mejorar WR)
input int    EMA20_Period                = 50;     // periodo EMA intraday (50 barras M1 = ~50 min)
input bool   Enable_Stoch_D_Confirm     = false;  // K>D/K<D confirm (OFF: bloquea señales válidas sin mejora WR)
input double Min_K_Velocity             = 0.0;    // K velocity (0.0=OFF como original)
input int    G2_Legacy_Threshold        = 4;      // G2 cada N legacies (4=Overlap_AFTER_X_trades_ del original)
input bool   Enable_AntiImpulse          = false;  // bloquea entrada si vela actual es impulso fuerte contrario (OFF por defecto)
input double AntiImpulse_ATR_Ratio       = 0.5;    // vela actual > ATR*ratio → impulso (bloquear)
input bool   Enable_CoolingOff           = false;  // pausa dirección tras N pérdidas (OFF=sin delay como original)
input int    CoolingOff_Losses           = 3;      // pérdidas consecutivas antes de pausa
input int    CoolingOff_Bars             = 5;      // barras de pausa por dirección (era 3)
// +++ v8.20 Smart Entry +++
input bool   Enable_LocalPA              = false;  // ✗ DEMOSTRADO: reduce WR (OFF=como original)
input int    LocalPA_Lookback            = 5;      // barras hacia atrás para detectar extremo local
input double LocalPA_ATR_Tolerance       = 0.4;    // precio dentro de ATR*ratio del extremo
input bool   DConfirm_P3Only             = false;  // D-confirm en P3 (OFF=como original)
input double EMA_Against_KVel_Factor     = 5.0;    // factor K_velocity si señal va contra EMA
// +++ v8.23 Market Regime & Adaptive +++
input bool   Enable_RegimeFilter         = false;  // detector régimen (OFF=como original)
input int    Regime_Lookback             = 20;
input double Regime_ADX_Threshold        = 25.0;
input bool   Enable_AdaptivePrevCandle   = false;  // ✗ DEMOSTRADO: reduce WR (OFF=como original)
input double AdaptPC_ATR_Ratio_Calm      = 0.10;   // body ratio cuando ATR < ATR_avg*0.8 (mercado tranquilo)
input double AdaptPC_ATR_Ratio_Normal    = 0.20;   // body ratio en condiciones normales
input double AdaptPC_ATR_Ratio_Active    = 0.30;   // body ratio cuando ATR > ATR_avg*1.3 (mercado activo)
input bool   Enable_DynamicTP            = false;  // TP dinámico basado en ATR (OFF=usa TP fijo 2.50)
input double DynamicTP_ATR_Mult          = 2.5;    // TP = ATR * multiplicador
input double DynamicTP_Min_Pts           = 1.5;    // TP mínimo en puntos (safety floor)
input double DynamicTP_Max_Pts           = 5.0;    // TP máximo en puntos (cap)
// +++ v8.22 Loss Reduction +++
input bool   Enable_PrevCandle_Confirm   = false;  // vela anterior confirma dir (OFF=como original)
input double PrevCandle_Min_Body_Ratio   = 0.15;   // cuerpo vela anterior >= rango*ratio (0.15=permisivo, adaptativo)
input bool   Enable_FastLoss_Cooldown    = false;  // fast-loss pause (OFF=como original)
input int    FastLoss_Window_Bars        = 10;     // ventana de barras para contar pérdidas rápidas
input int    FastLoss_Count_Trigger      = 2;      // número de pérdidas rápidas que activa pausa
input int    FastLoss_Pause_Bars         = 10;     // barras de pausa tras trigger (10 M1 = 10 min)
input bool   Enable_RSI_Trend_Gate       = false;  // RSI gate tendencia (OFF=como original)
input double RSI_Trend_Min               = 45.0;   // RSI mínimo para BUY (45=más permisivo, recupera tarde)
input double RSI_Trend_Max               = 55.0;   // RSI máximo para SELL (55=más permisivo)

//============================================================
#define MM7_G2_MIN_GAP_S  2
#define MM7_ATR_FALLBACK  0.50

struct StealthPos {
   ulong  ticket;
   double vTP, vSL;
   int    dir;
   bool   active;
   // v14: Trailing Profit
   double trailMaxProfit;   // máximo profit USD alcanzado desde apertura
   bool   trailActivated;   // true cuando profit >= TP_Trail_Activate_USD
};
struct FVGZone    { double top,bot; int dir; bool active; };

int      g_magic; double g_point; string g_sym;
int      g_hStoch=INVALID_HANDLE, g_hMA=INVALID_HANDLE, g_hEMA20=INVALID_HANDLE;
int      g_hATR=INVALID_HANDLE,   g_hRSI=INVALID_HANDLE;
// v15: Predictive Intelligence Engine handles
int      g_hEMA_Fast=INVALID_HANDLE;   // EMA rápida para momentum predictor
int      g_hEMA_Slow=INVALID_HANDLE;   // EMA lenta para momentum predictor
int      g_hEMA_M5=INVALID_HANDLE;     // EMA trend en M5 para MTF
int      g_hEMA_M15=INVALID_HANDLE;    // EMA trend en M15 para MTF
int      g_hStoch_M5=INVALID_HANDLE;   // Stoch M5 para MTF
int      g_hStoch_M15=INVALID_HANDLE;  // Stoch M15 para MTF
// v15: score y estado del motor predictivo
int      g_lastPredScore   = 0;    // último score calculado (para dashboard)
int      g_lastPredDir     = 0;    // última dirección predicha

StealthPos g_sp[];   int g_spCnt=0;
FVGZone    g_fvg[];  int g_fvgCnt=0;
datetime   g_fvgLastScan=0;

int      g_legacyClosedAtLastG2=0;
datetime g_lastG2OpenTime=0;
bool     g_g2OpenedThisLegacy=false;
ulong    g_g2ForLegacyTicket=0;
datetime g_lastSignalBar=0;   // BAR-LOCK: datetime de bar[1] cuando última señal legacy abrió
ulong    g_lastLegacyTicket=0;
// v10.0 Entry Quality Control
datetime g_lastEntryTime    = 0;  // timestamp de la última entrada (cooldown entre entradas)
datetime g_postCloseLockout = 0;  // lockout tras cierre de posición
int      g_lastCycleDir     = 0;  // dirección del último ciclo Stoch para evitar re-entrada en mismo ciclo
// Cooling-off state
int      g_consec_loss_buy  = 0;
int      g_consec_loss_sell = 0;
datetime g_pause_buy_until  = 0;
datetime g_pause_sell_until = 0;
int      g_fastLossCount    = 0;
datetime g_fastLossWinStart = 0;
datetime g_pause_fast_until = 0;
int      g_lastSigType      = 0;
int      g_marketRegime     = 0;   // 0=unknown, 1=TRENDING, -1=RANGING
datetime g_regimeScanBar    = 0;
datetime g_dayStart=0;
double   g_dayStartBal=0;
bool     g_haltedToday=false;
datetime g_lastDashTime=0, g_lastLabelTime=0;

double   g_swingHi=0, g_swingLo=0;
datetime g_swingScanBar=0;
double   g_atrAvg=MM7_ATR_FALLBACK;
datetime g_atrAvgBar=0;

//--------------------------------------------------------------------
double GetATR()
{
   if(g_hATR==INVALID_HANDLE) return MM7_ATR_FALLBACK;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(g_hATR,0,1,2,b)<2) return MM7_ATR_FALLBACK;
   return (b[0]>0)?b[0]:MM7_ATR_FALLBACK;
}

double GetATRAvg()
{
   datetime bt=iTime(g_sym,_Period,1);
   if(bt==g_atrAvgBar) return g_atrAvg;
   g_atrAvgBar=bt;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(g_hATR,0,1,20,b)<20) return g_atrAvg;
   double s=0; for(int i=0;i<20;i++) s+=b[i];
   g_atrAvg=s/20.0; return g_atrAvg;
}

bool IsHighVolatility() { return GetATR()>GetATRAvg()*ATR_HighVol_Multiplier; }

// EMA20 Intraday Trend Gate
// Filtra entradas CONTRA el momentum intraday de 20 barras
// Problema detectado en v8.17: 17:30-18:30 SELL con precio SUBIENDO → 2W/26L
// EMA20 lo hubiera bloqueado al detectar precio > EMA20 → no vender
int GetEMA20Gate()
{
   if(!Enable_EMA20_Gate||g_hEMA20==INVALID_HANDLE) return 0; // 0 = no restriction
   double eb[]; ArraySetAsSeries(eb,true);
   if(CopyBuffer(g_hEMA20,0,1,1,eb)<1) return 0;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ema=eb[0];
   // +1 = price above EMA20 → only BUY allowed
   // -1 = price below EMA20 → only SELL allowed
   return (bid>ema)?1:-1;
}

// Stoch D-line confirmation
// K>D at bottom zone = momentum confirms reversal (BUY)
// K<D at top zone = momentum confirms reversal (SELL)
bool StochDConfirm(int dir)
{
   if(!Enable_Stoch_D_Confirm) return true;
   double kb[],db[]; ArraySetAsSeries(kb,true); ArraySetAsSeries(db,true);
   if(CopyBuffer(g_hStoch,0,1,1,kb)<1) return true;
   if(CopyBuffer(g_hStoch,1,1,1,db)<1) return true; // buffer 1 = D line
   double k=kb[0], d=db[0];
   if(dir==1)  return k>d;  // BUY: K must be above D (momentum up)
   if(dir==-1) return k<d;  // SELL: K must be below D (momentum down)
   return true;
}

// K velocity: K must move minimum amount between bars (prevents stale signals)
bool KVelocityOK(double k_now, double k_prev, int dir)
{
   if(Min_K_Velocity<=0) return true;
   double velocity = (dir==1) ? (k_now-k_prev) : (k_prev-k_now);
   return (velocity >= Min_K_Velocity);
}

double GetRSI()
{
   if(g_hRSI==INVALID_HANDLE) return 50.0;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(g_hRSI,0,1,2,b)<2) return 50.0;
   return b[0];
}

bool IsVolumeOK()
{
   if(!Use_Volume_Confirmation) return true;
   long vb[]; ArraySetAsSeries(vb,true);
   if(CopyTickVolume(g_sym,_Period,0,Volume_Ma_Period+1,vb)<Volume_Ma_Period+1) return true;
   double s=0; for(int i=1;i<=Volume_Ma_Period;i++) s+=(double)vb[i];
   return ((double)vb[0]>=s/Volume_Ma_Period);
}

int GetTrend()
{
   if(!Enable_Trend_Filter||g_hMA==INVALID_HANDLE) return 0;
   double mb[]; ArraySetAsSeries(mb,true);
   if(CopyBuffer(g_hMA,0,1,1,mb)<1) return 0;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   return (bid>mb[0])?1:(bid<mb[0])?-1:0;
}

int GetCandleDir()
{
   double o=iOpen(g_sym,_Period,1),c=iClose(g_sym,_Period,1);
   double body=MathAbs(c-o); if(body<GetATR()*0.15) return 0;
   return (c>o)?1:-1;
}

void UpdateSwings()
{
   datetime bt=iTime(g_sym,_Period,1);
   if(bt==g_swingScanBar) return; g_swingScanBar=bt;
   double hi=0,lo=DBL_MAX;
   for(int i=1;i<=20;i++){double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);if(h>hi)hi=h;if(l<lo)lo=l;}
   g_swingHi=hi; g_swingLo=lo;
}

bool HasBOS(int dir)
{
   if(!Enable_BOS_Filter) return true;
   double rHi=0,rLo=DBL_MAX;
   for(int i=1;i<=BOS_Lookback;i++){double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);if(h>rHi)rHi=h;if(l<rLo)rLo=l;}
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK),bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   if(dir==1)  return ask>rHi;
   if(dir==-1) return bid<rLo;
   return true;
}

void ScanFVGs()
{
   datetime bt=iTime(g_sym,_Period,0); if(bt==g_fvgLastScan) return; g_fvgLastScan=bt;
   if(!Enable_FVG_Strategy){g_fvgCnt=0;return;}
   int lb=MathMin(FVG_Lookback_Bars,500); g_fvgCnt=0; ArrayResize(g_fvg,100);
   for(int i=2;i<lb&&g_fvgCnt<100;i++)
   {
      double h0=iHigh(g_sym,_Period,i),l0=iLow(g_sym,_Period,i);
      double h2=iHigh(g_sym,_Period,i+2),l2=iLow(g_sym,_Period,i+2);
      if(l0>h2){g_fvg[g_fvgCnt].top=l0;g_fvg[g_fvgCnt].bot=h2;g_fvg[g_fvgCnt].dir=1; g_fvg[g_fvgCnt].active=true;g_fvgCnt++;}
      else if(h0<l2){g_fvg[g_fvgCnt].top=l2;g_fvg[g_fvgCnt].bot=h0;g_fvg[g_fvgCnt].dir=-1;g_fvg[g_fvgCnt].active=true;g_fvgCnt++;}
   }
}

bool InFVG(int dir)
{
   if(!Enable_FVG_Strategy||g_fvgCnt==0) return false;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   for(int i=0;i<g_fvgCnt;i++)
      if(g_fvg[i].active&&g_fvg[i].dir==dir&&bid>=g_fvg[i].bot&&bid<=g_fvg[i].top) return true;
   return false;
}

int GetBreakout()
{
   if(!Enable_Breakout_Strategy) return 0;
   double hi=0,lo=DBL_MAX;
   for(int i=1;i<=Breakout_Period;i++){double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);if(h>hi)hi=h;if(l<lo)lo=l;}
   if((hi-lo)/g_point<Min_Breakout_Range) return 0;
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK),bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double buf=Breakout_Buffer*g_point;
   if(ask>hi+buf){if(Use_RSI_Confirmation&&GetRSI()<RSI_Buy_Threshold)return 0;if(!IsVolumeOK())return 0;return 1;}
   if(bid<lo-buf){if(Use_RSI_Confirmation&&GetRSI()>RSI_Sell_Threshold)return 0;if(!IsVolumeOK())return 0;return -1;}
   return 0;
}

int GetSweep()
{
   if(!Enable_Stop_Hunt_Strategy) return 0;
   UpdateSwings();
   double atr=GetATR(),sw=atr*0.5;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID),ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double kb[]; ArraySetAsSeries(kb,true);
   if(CopyBuffer(g_hStoch,0,1,1,kb)<1) return 0;
   if(bid>g_swingLo&&ask<g_swingLo+sw&&kb[0]<=Stoch_Buy_Level) return 1;
   if(bid<g_swingHi&&bid>g_swingHi-sw&&kb[0]>=Stoch_Sell_Level) return -1;
   return 0;
}

//============================================================
// PREDICTIVE INTELLIGENCE ENGINE v15
// Motor de predicción de dirección de mercado — 5 capas
//============================================================

//--------------------------------------------------------------------
// CAPA 1: Confluencia Multi-Timeframe — CONFIRMACIÓN RELATIVA v17
// FIX v17: En v16 comparaba precio vs EMA50 en M5/M15.
// Si el precio está horas por encima de EMA50 (tendencia alcista),
// SELL NUNCA pasa este filtro → 0 operaciones SELL ese día.
// Si el precio está por debajo de EMA50, BUY NUNCA pasa → 0 BUY.
//
// SOLUCIÓN: en lugar de posición absoluta precio vs EMA,
// medir la INCLINACIÓN/PENDIENTE de la EMA en cada timeframe.
// Pendiente positiva (EMA subiendo) → favorece BUY.
// Pendiente negativa (EMA bajando)  → favorece SELL.
// Pendiente plana (consolidación)   → neutral → no bloquea.
// Esto es relativo al momentum ACTUAL, no a la posición histórica.
//--------------------------------------------------------------------
int GetMTFConfluence(int dir)
{
   if(!Enable_MTF_Confluence) return 1; // bypass garantizado

   int score = 0;
   int checks = 0;

   // M1: pendiente EMA_Fast (últimas 3 barras cerradas)
   if(g_hEMA_Fast != INVALID_HANDLE)
   {
      double ef[]; ArraySetAsSeries(ef, true);
      if(CopyBuffer(g_hEMA_Fast, 0, 1, 3, ef) >= 3)
      {
         checks++;
         double slope = ef[0] - ef[2]; // pendiente 2 barras
         double atr   = GetATR();
         // Solo cuenta si la pendiente es significativa (> 10% ATR)
         // para no sesgarse en mercados laterales
         if(MathAbs(slope) > atr * 0.10)
         {
            int d = (slope > 0) ? 1 : -1;
            if(d == dir) score++;
         }
         else
            score++; // pendiente plana = neutral → no penalizar
      }
   }

   // M5: pendiente EMA_M5 (usando barras M5 cerradas)
   if(g_hEMA_M5 != INVALID_HANDLE)
   {
      double em5[]; ArraySetAsSeries(em5, true);
      if(CopyBuffer(g_hEMA_M5, 0, 1, 3, em5) >= 3)
      {
         checks++;
         double slope5 = em5[0] - em5[2];
         double atr    = GetATR();
         if(MathAbs(slope5) > atr * 0.15)
         {
            int d5 = (slope5 > 0) ? 1 : -1;
            if(d5 == dir) score++;
         }
         else
            score++; // neutral → no bloquear
      }
   }

   // M15: pendiente EMA_M15
   if(g_hEMA_M15 != INVALID_HANDLE)
   {
      double em15[]; ArraySetAsSeries(em15, true);
      if(CopyBuffer(g_hEMA_M15, 0, 1, 3, em15) >= 3)
      {
         checks++;
         double slope15 = em15[0] - em15[2];
         double atr     = GetATR();
         if(MathAbs(slope15) > atr * 0.20)
         {
            int d15 = (slope15 > 0) ? 1 : -1;
            if(d15 == dir) score++;
         }
         else
            score++; // neutral → no bloquear
      }
   }

   if(checks == 0) return 1; // sin datos → bypass
   return (score >= MTF_Min_Confluence) ? 1 : 0;
}

//--------------------------------------------------------------------
// CAPA 2: Order Flow Bias via Delta de Volumen
// Compara volumen de velas alcistas vs bajistas en ventana reciente
// Si delta > umbral → hay presión dominante en una dirección
//--------------------------------------------------------------------
int GetOrderFlowBias(int dir)
{
   if(!Enable_OrderFlow_Bias) return 1; // bypass

   int N = OrderFlow_Bars;
   double buyVol = 0, sellVol = 0;

   for(int i = 1; i <= N; i++)
   {
      double o = iOpen(g_sym, _Period, i);
      double c = iClose(g_sym, _Period, i);
      long   v = iVolume(g_sym, _Period, i);
      if(c >= o) buyVol  += (double)v;
      else       sellVol += (double)v;
   }

   double total = buyVol + sellVol;
   if(total <= 0) return 1; // sin datos → bypass

   double buyRatio  = buyVol  / total;
   double sellRatio = sellVol / total;

   // Delta = diferencia de presión
   if(dir == 1  && buyRatio  >= (0.5 + OrderFlow_Min_Delta/2.0)) return 1;
   if(dir == -1 && sellRatio >= (0.5 + OrderFlow_Min_Delta/2.0)) return 1;

   return 0;
}

//--------------------------------------------------------------------
// CAPA 3 FIX v16: Momentum Bias — funciona en tendencia Y reversión
// PROBLEMA v15: GetEMAMomentum exigía cruce EMA3/EMA8 EN FORMACIÓN.
// En Gold alcista (EMA3 lleva horas > EMA8), nunca hay cruce BUY
// → score_buy = 0 siempre → solo SELL.
//
// SOLUCIÓN: medir la POSICIÓN RELATIVA del gap + ACELERACIÓN del gap.
// BUY: gap (EMA_fast - EMA_slow) es positivo (tendencia arriba)
//      O el gap negativo está REDUCIÉNDOSE (reversión alcista)
// SELL: gap es negativo (tendencia abajo)
//       O el gap positivo está REDUCIÉNDOSE (reversión bajista)
// Esto captura tanto tendencia como reversión sin depender de cruce.
//--------------------------------------------------------------------
int GetMomentumBias(int dir)
{
   if(!Enable_EMA_Momentum) return 1; // bypass

   if(g_hEMA_Fast == INVALID_HANDLE || g_hEMA_Slow == INVALID_HANDLE) return 1;

   double ef_now[]; ArraySetAsSeries(ef_now, true);
   double es_now[]; ArraySetAsSeries(es_now, true);

   // Leer 3 barras para calcular gap y su aceleración
   if(CopyBuffer(g_hEMA_Fast,0,0,3,ef_now)<3) return 1;
   if(CopyBuffer(g_hEMA_Slow,0,0,3,es_now)<3) return 1;

   double gap0 = ef_now[0] - es_now[0]; // gap actual (barra en formación)
   double gap1 = ef_now[1] - es_now[1]; // gap barra anterior cerrada
   double gap2 = ef_now[2] - es_now[2]; // gap 2 barras atrás

   // Aceleración del gap (segunda derivada)
   double accel = (gap0 - gap1) - (gap1 - gap2);

   // BUY score:
   //   +1 si gap positivo (EMA_fast > EMA_slow = momentum alcista)
   //   +1 si gap negativo pero reduciéndose (reversión hacia arriba)
   //   El accel positivo es bonus pero no obligatorio
   if(dir == 1)
   {
      if(gap0 > 0) return 1;                      // tendencia alcista activa
      if(gap0 < 0 && gap0 > gap1) return 1;       // gap negativo pero mejorando (reversión)
      return 0;
   }

   // SELL score:
   //   +1 si gap negativo (EMA_fast < EMA_slow = momentum bajista)
   //   +1 si gap positivo pero reduciéndose (reversión hacia abajo)
   if(dir == -1)
   {
      if(gap0 < 0) return 1;                      // tendencia bajista activa
      if(gap0 > 0 && gap0 < gap1) return 1;       // gap positivo pero empeorando (reversión)
      return 0;
   }

   return 1;
}

//--------------------------------------------------------------------
// CAPA 4: Estructura de Precio (HH/HL o LH/LL)
// Detecta si el mercado está construyendo estructura alcista o bajista
// Alcista: el último swing alto > penúltimo swing alto (HH)
//          Y el último swing bajo > penúltimo swing bajo (HL)
// Bajista: inverso (LH + LL)
//--------------------------------------------------------------------
int GetPriceStructure(int dir)
{
   if(!Enable_Price_Structure) return 1; // bypass

   int N = Structure_Lookback;
   double atr = GetATR();
   double minSwing = atr * Structure_Min_ATR;

   // Encontrar 2 swing highs y 2 swing lows en las últimas N barras
   double sh1=0, sh2=0, sl1=DBL_MAX, sl2=DBL_MAX;
   int    si1=-1, si2=-1, sl_i1=-1, sl_i2=-1;

   for(int i=2; i<N+2; i++)
   {
      double h = iHigh(g_sym,_Period,i);
      double l = iLow(g_sym,_Period,i);
      double hp = iHigh(g_sym,_Period,i-1);
      double hn = iHigh(g_sym,_Period,i+1);
      double lp = iLow(g_sym,_Period,i-1);
      double ln = iLow(g_sym,_Period,i+1);

      // Swing High: mayor que vecinos
      if(h > hp && h > hn && (sh1==0 || h > sh1-minSwing))
      {
         if(si1<0){ sh1=h; si1=i; }
         else if(si2<0){ sh2=h; si2=i; }
      }
      // Swing Low: menor que vecinos
      if(l < lp && l < ln && (sl1==DBL_MAX || l < sl1+minSwing))
      {
         if(sl_i1<0){ sl1=l; sl_i1=i; }
         else if(sl_i2<0){ sl2=l; sl_i2=i; }
      }
   }

   // Necesitamos 2 swings de cada tipo para detectar estructura
   if(si1<0||si2<0||sl_i1<0||sl_i2<0) return 1; // datos insuficientes → bypass

   bool hh = (sh1 > sh2); // último swing high > anterior = Higher High
   bool hl = (sl1 > sl2); // último swing low  > anterior = Higher Low
   bool ll = (sl1 < sl2); // último swing low  < anterior = Lower Low
   bool lh = (sh1 < sh2); // último swing high < anterior = Lower High

   if(dir ==  1 && hh && hl) return 1; // estructura alcista
   if(dir == -1 && lh && ll) return 1; // estructura bajista

   return 0;
}

//--------------------------------------------------------------------
// CAPA 5: Stochastic como Timing (no como señal)
// Confirma que NO estamos entrando en cima/valle del impulso
// BUY: K en zona oversold O acaba de salir de ella (no overbought)
// SELL: K en zona overbought O acaba de salir (no oversold)
//--------------------------------------------------------------------
int GetStochTiming(int dir)
{
   if(!Use_Grid_Stoch_Filter) return 1; // bypass si stoch desactivado

   double kb[]; ArraySetAsSeries(kb,true);
   if(CopyBuffer(g_hStoch,0,0,2,kb)<2) return 1;
   double k_now = kb[0];

   // BUY: no entrar si stoch es overbought (precio en zona de venta)
   if(dir ==  1 && k_now > Stoch_Sell_Level) return 0;
   // SELL: no entrar si stoch es oversold (precio en zona de compra)
   if(dir == -1 && k_now < Stoch_Buy_Level)  return 0;

   // Timing ideal: stoch alineado con dirección
   if(dir ==  1 && k_now <= Stoch_Buy_Level + 20) return 1;
   if(dir == -1 && k_now >= Stoch_Sell_Level - 20) return 1;

   return 1; // zona neutral → permitir (el score ya filtra)
}

//--------------------------------------------------------------------
// MOTOR DE CALIDAD v17: CalcQualityScore(dir)
// FIX ARQUITECTURAL: el motor ya NO decide la dirección.
// La dirección viene del Stochastic (como en el backtest original).
// Este motor solo responde: "¿la señal del Stoch tiene calidad?"
//
// Recibe dir = dirección que el Stochastic quiere operar (+1 o -1)
// Retorna score 0-5 (cuántas capas confirman ESA dirección)
// Si score >= Min_Prediction_Score → señal de calidad → ejecutar
// Si score < umbral → señal débil → ignorar
//
// DIFERENCIA CLAVE vs v15/v16:
// Antes: score_buy vs score_sell → siempre ganaba el lado tendencial
// Ahora: CalcQualityScore(1) cuando Stoch dice BUY → ¿hay calidad?
//        CalcQualityScore(-1) cuando Stoch dice SELL → ¿hay calidad?
// Nunca bloquea una dirección entera durante días por sesgo de EMA
//--------------------------------------------------------------------
int CalcQualityScore(int dir)
{
   int score = 0;

   score += GetMTFConfluence(dir);    // pendiente EMA M1/M5/M15 en la dir solicitada
   score += GetOrderFlowBias(dir);    // volumen alcista/bajista dominante
   score += GetMomentumBias(dir);     // EMA rápida vs lenta en la dir solicitada
   score += GetPriceStructure(dir);   // HH/HL o LH/LL en la dir solicitada
   score += GetStochTiming(dir);      // Stoch no está en zona opuesta extrema

   // Guardar para dashboard
   g_lastPredScore = score;
   g_lastPredDir   = dir;

   return score;
}

// Mantener GetPredictiveSignal como wrapper vacío para compatibilidad
// con cualquier referencia externa (retorna 0 siempre = sin señal propia)
int GetPredictiveSignal() { return 0; }

//--------------------------------------------------------------------

//
// PROBLEMA v8.15: K<=30 era TRUE mientras K seguía bajando → entraba
// en medio del movimiento bajista → perdía el SL antes de revertir.
//
// SOLUCIÓN v8.17: Zone-Exit Filter
// BUY:  K está en zona (<30) Y K_actual > K_anterior (K ya empezó a subir)
//       → precio ya tocó mínimo y está revirtiendo
// SELL: K está en zona (>70) Y K_actual < K_anterior (K ya empezó a bajar)
//       → precio ya tocó máximo y está revirtiendo
//
// Esto es equivalente a esperar confirmación de reversión del momentum
// sin llegar al crossover completo (que era demasiado tardío en v8.16)
//--------------------------------------------------------------------
int GetStochZone(double k_now, double k_prev)
{
   bool inBuyZone  = (k_now <= Stoch_Buy_Level);
   bool inSellZone = (k_now >= Stoch_Sell_Level);

   if(Enable_Zone_Exit_Filter)
   {
      // Zone-exit: K en zona Y K volviendo hacia neutro
      bool kRisingBuy   = (k_now > k_prev);  // K subiendo mientras está bajo 30 → reversión
      bool kFallingSell = (k_now < k_prev);  // K bajando mientras está sobre 70 → reversión
      if(inBuyZone  && kRisingBuy)   return  1;
      if(inSellZone && kFallingSell) return -1;
   }
   else
   {
      // Modo zona puro (comportamiento v8.15)
      if(inBuyZone  && !inSellZone) return  1;
      if(inSellZone && !inBuyZone)  return -1;
   }
   return 0;
}

// Anti-Impulso: bloquea entrada si la vela ACTUAL es un impulso fuerte en dirección CONTRARIA
// Esto evita entrar BUY cuando el precio está cayendo con fuerza en el tick actual
// Los 37 trades que perdieron en ≤10s lo hicieron porque entraron CONTRA un impulso activo
bool AntiImpulseOK(int dir)
{
   if(!Enable_AntiImpulse) return true;
   double atr = GetATR();
   if(atr <= 0) return true;
   // Vela actual: ¿qué tan grande es y en qué dirección?
   double o = iOpen(g_sym, _Period, 0);
   double c_price = iClose(g_sym, _Period, 0);
   double body = c_price - o;  // positivo=alcista, negativo=bajista
   double threshold = atr * AntiImpulse_ATR_Ratio;
   // BUY bloqueado si vela actual es fuertemente bajista
   if(dir ==  1 && body < -threshold) return false;
   // SELL bloqueado si vela actual es fuertemente alcista
   if(dir == -1 && body >  threshold) return false;
   return true;
}

// Cooling-Off: actualizar contadores y verificar si dirección está en pausa
// Llamado DESPUÉS de cada cierre de posición (en el siguiente tick tras el cierre)
void UpdateCoolingOff()
{
   if(!Enable_CoolingOff) return;
   // Revisar trades cerrados desde la última barra
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(ds, TimeCurrent());
   static datetime g_lastCoolingCheck = 0;
   if(TimeCurrent() - g_lastCoolingCheck < 1) return;
   g_lastCoolingCheck = TimeCurrent();

   // Buscar el último trade cerrado
   int tot = HistoryDealsTotal();
   if(tot == 0) return;
   ulong last_dk = HistoryDealGetTicket(tot-1);
   if(!HistoryDealSelect(last_dk)) return;
   if((int)HistoryDealGetInteger(last_dk, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(last_dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double pnl = HistoryDealGetDouble(last_dk, DEAL_PROFIT);
   datetime open_t = (datetime)HistoryDealGetInteger(last_dk, DEAL_TIME);
   // Calcular duración de este trade para fast-loss cooldown
   // (aproximación: usamos el tiempo del deal de cierre menos el de apertura)
   // Buscamos el deal de entrada correspondiente
   double dur_secs = 30.0; // fallback
   for(int di=tot-2; di>=MathMax(0,tot-10); di--)
   {
      ulong dk2=HistoryDealGetTicket(di);
      if(!HistoryDealSelect(dk2)) continue;
      if((int)HistoryDealGetInteger(dk2,DEAL_MAGIC)!=g_magic) continue;
      if(HistoryDealGetInteger(dk2,DEAL_ENTRY)==DEAL_ENTRY_IN)
      { dur_secs=(double)(open_t-(datetime)HistoryDealGetInteger(dk2,DEAL_TIME)); break; }
   }
   UpdateFastLossCooldown(pnl, MathAbs(dur_secs));

   int    tp  = (int)HistoryDealGetInteger(last_dk, DEAL_TYPE);  // DEAL_TYPE_SELL=cierre buy, DEAL_TYPE_BUY=cierre sell
   // cierre de BUY = DEAL_TYPE_SELL (tp==1), cierre de SELL = DEAL_TYPE_BUY (tp==0)
   bool was_buy = (tp == DEAL_TYPE_SELL);

   if(pnl < 0)
   {
      if(was_buy)  g_consec_loss_buy++;
      else         g_consec_loss_sell++;
      if(was_buy  && g_consec_loss_buy  >= CoolingOff_Losses)
      {
         g_pause_buy_until  = iTime(g_sym, _Period, 0) + CoolingOff_Bars * PeriodSeconds(_Period);
         g_consec_loss_buy  = 0;
         Print("MM7 COOLING-OFF: BUY pausado ", CoolingOff_Bars, " barras");
      }
      if(!was_buy && g_consec_loss_sell >= CoolingOff_Losses)
      {
         g_pause_sell_until = iTime(g_sym, _Period, 0) + CoolingOff_Bars * PeriodSeconds(_Period);
         g_consec_loss_sell = 0;
         Print("MM7 COOLING-OFF: SELL pausado ", CoolingOff_Bars, " barras");
      }
   }
   else
   {
      // Win resetea contador de la dirección ganada
      if(was_buy)  g_consec_loss_buy  = 0;
      else         g_consec_loss_sell = 0;
   }
}

bool IsCoolingOff(int dir)
{
   if(!Enable_CoolingOff) return false;
   datetime now = TimeCurrent();
   if(dir ==  1 && now < g_pause_buy_until)  return true;
   if(dir == -1 && now < g_pause_sell_until) return true;
   return false;
}

// Local Price Action: detecta si el precio está tocando un extremo local
// BUY: precio cerca del mínimo de las últimas N barras → soporte local (Order Block touch)
// SELL: precio cerca del máximo de las últimas N barras → resistencia local
// Esto replica el comportamiento del original que entra en OBs reales
// Resultado esperado: WR sube de 35% → ~45% al filtrar entradas en "mitad de rango"
bool LocalPAConfirm(int dir)
{
   if(!Enable_LocalPA) return true;
   int N = LocalPA_Lookback;
   double atr = GetATR();
   double tol = atr * LocalPA_ATR_Tolerance;
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);

   if(dir == 1) // BUY: precio debe estar cerca del mínimo local
   {
      double lo[]; ArraySetAsSeries(lo, true);
      if(CopyLow(g_sym, _Period, 1, N, lo) < N) return true; // fallback: permitir
      double local_min = lo[ArrayMinimum(lo, 0, N)];
      return (bid <= local_min + tol); // precio dentro de tolerancia del mínimo
   }
   if(dir == -1) // SELL: precio debe estar cerca del máximo local
   {
      double hi[]; ArraySetAsSeries(hi, true);
      if(CopyHigh(g_sym, _Period, 1, N, hi) < N) return true; // fallback: permitir
      double local_max = hi[ArrayMaximum(hi, 0, N)];
      return (bid >= local_max - tol); // precio dentro de tolerancia del máximo
   }
   return true;
}

// ─── MARKET REGIME DETECTOR ─────────────────────────────────────────────────
// Detecta si el mercado está en modo TRENDING o RANGING usando un proxy de ADX:
// Linear regression slope de los últimos N closes.
// Si la pendiente es significativa → TRENDING → preferir señales en esa dirección
// Si la pendiente es plana → RANGING → señales de reversión válidas en ambas dir.
// Esto resuelve horas como 09h (TRENDING bajista mientras el EA compra)
// y 17-19h (TRENDING alcista mientras el EA vende)
void UpdateMarketRegime()
{
   if(!Enable_RegimeFilter) { g_marketRegime=0; return; }
   datetime bt=iTime(g_sym,_Period,1);
   if(bt==g_regimeScanBar) return; g_regimeScanBar=bt;

   int N=Regime_Lookback;
   double closes[]; ArraySetAsSeries(closes,true);
   if(CopyClose(g_sym,_Period,1,N,closes)<N) { g_marketRegime=0; return; }

   // Calcular pendiente de regresión lineal (simple: último - primero normalizado)
   double first=closes[N-1], last_c=closes[0];
   double slope=(last_c-first); // en puntos

   // Calcular rango promedio como referencia de normalización
   double atr=GetATR();
   if(atr<=0) { g_marketRegime=0; return; }

   double slope_normalized=MathAbs(slope)/(atr*N*0.3);

   if(slope_normalized > 1.0) // pendiente fuerte
   {
      g_marketRegime = (slope > 0) ? 1 : -1; // 1=UPTREND, -1=DOWNTREND
   }
   else
   {
      g_marketRegime = 0; // RANGING / neutral
   }
}

// En modo TRENDING: solo aceptar señales EN LA DIRECCIÓN del trend
// En modo RANGING: aceptar señales de reversión en ambas direcciones
// Retorna false si la señal contradice el régimen activo
bool RegimeFilter(int dir)
{
   if(!Enable_RegimeFilter) return true;
   if(g_marketRegime==0) return true; // ranging → libre
   // Solo bloquear si la señal va FUERTEMENTE contra el trend
   // Permitimos si trend es moderado (evitar sobre-filtrar)
   return (dir == g_marketRegime || g_marketRegime == 0);
}

// ─── PREV CANDLE CONFIRMATION ───────────────────────────────────────────────
// La vela anterior cerrada debe apuntar en la misma dirección que la señal.
// Ataca el problema: 87% de pérdidas ocurren en ≤30s (entrada contra momentum).
bool PrevCandleConfirm(int dir)
{
   if(!Enable_PrevCandle_Confirm) return true;
   double o1=iOpen(g_sym,_Period,1), c1=iClose(g_sym,_Period,1);
   double h1=iHigh(g_sym,_Period,1), l1=iLow(g_sym,_Period,1);
   double range=h1-l1;
   if(range < g_point*2) return true; // doji/micro → no filtrar

   // Body ratio adaptativo según volatilidad del mercado
   double ratio = PrevCandle_Min_Body_Ratio; // default fijo
   if(Enable_AdaptivePrevCandle)
   {
      double atr=GetATR(), atr_avg=GetATRAvg();
      if(atr_avg > 0)
      {
         double atr_rel = atr / atr_avg;
         if(atr_rel < 0.8)       ratio = AdaptPC_ATR_Ratio_Calm;   // mercado tranquilo → permisivo
         else if(atr_rel > 1.3)  ratio = AdaptPC_ATR_Ratio_Active;  // mercado activo → estricto
         else                    ratio = AdaptPC_ATR_Ratio_Normal;   // normal
      }
   }

   double body=MathAbs(c1-o1);
   if(dir== 1) return (c1>o1 && body>=range*ratio);
   if(dir==-1) return (c1<o1 && body>=range*ratio);
   return true;
}

// ─── RSI TREND GATE ──────────────────────────────────────────────────────────
// RSI confirma momentum direccional. Umbrales permisivos (48/52) para evitar
// sobre-filtrar. Soluciona horas 09h, 14h donde la dirección es correcta
// pero el RSI muestra que el precio no tiene momentum en esa dirección.
bool RSITrendGate(int dir)
{
   if(!Enable_RSI_Trend_Gate) return true;
   double rsi=GetRSI();
   if(rsi<=0) return true;
   if(dir== 1) return (rsi >= RSI_Trend_Min);
   if(dir==-1) return (rsi <= RSI_Trend_Max);
   return true;
}

// ─── FAST-LOSS COOLDOWN ──────────────────────────────────────────────────────
// 2+ pérdidas ultrarrápidas (≤5s) en 10 barras → pausa 10 barras.
// Captura momentos de spread amplio, noticias o liquidez extrema.
void UpdateFastLossCooldown(double pnl, double dur_seconds)
{
   if(!Enable_FastLoss_Cooldown) return;
   datetime now=TimeCurrent();
   if(now-g_fastLossWinStart > FastLoss_Window_Bars*PeriodSeconds(_Period))
   { g_fastLossCount=0; g_fastLossWinStart=now; }
   if(pnl<0 && dur_seconds<=5.0)
   {
      g_fastLossCount++;
      if(g_fastLossCount>=FastLoss_Count_Trigger)
      {
         g_pause_fast_until=iTime(g_sym,_Period,0)+FastLoss_Pause_Bars*PeriodSeconds(_Period);
         g_fastLossCount=0; g_fastLossWinStart=now;
         Print("MM7 FAST-LOSS COOLDOWN: pausa ",FastLoss_Pause_Bars," barras");
      }
   }
}
bool IsFastLossPause() { return Enable_FastLoss_Cooldown && TimeCurrent()<g_pause_fast_until; }

// ─── INTRA FILTERS PASS ──────────────────────────────────────────────────────
bool IntraFiltersPass(int sig, double k_now, double k_prev)
{
   // El original NO tiene filtros extra sobre la señal stoch+trend
   // Todos estos filtros son opcionales y OFF por default en v8.24
   // 1. Market Regime (OFF por default)
   if(!RegimeFilter(sig)) return false;
   // 2. K velocity (0.0 = desactivado por default)
   if(Min_K_Velocity > 0) {
      double vel = (sig==1) ? (k_now-k_prev) : (k_prev-k_now);
      if(vel < Min_K_Velocity) return false;
   }
   // 3. PrevCandle (OFF por default)
   if(!PrevCandleConfirm(sig)) return false;
   // 4. RSI Trend Gate (OFF por default)
   if(!RSITrendGate(sig)) return false;
   // 5. Anti-impulso (OFF por default)
   if(!AntiImpulseOK(sig)) return false;
   // 6. CoolingOff (OFF por default)
   if(IsCoolingOff(sig)) return false;
   // 7. FastLoss pause (OFF por default)
   if(IsFastLossPause()) return false;
   return true;
}

// IntraFiltersPass_P3: versión estricta para señales puras de Stoch (P3)
// Incluye D-confirm + LocalPA que son más exigentes
bool IntraFiltersPass_P3(int sig, double k_now, double k_prev)
{
   if(!IntraFiltersPass(sig, k_now, k_prev)) return false;

   // D-line confirmation en P3
   if(!StochDConfirm(sig)) return false;

   // Local Price Action: precio debe estar tocando extremo local (OB touch)
   if(!LocalPAConfirm(sig)) return false;

   return true;
}

//============================================================
// MASTER SIGNAL v15 — PREDICTIVE ENGINE INTEGRATION
// v17: El Stochastic decide la dirección (como en el backtest original).
// CalcQualityScore(dir) valida si esa señal concreta tiene calidad.
// El motor NUNCA bloquea una dirección entera por sesgo de tendencia.
//============================================================
int GetSignal()
{
   if(!Use_Grid_Stoch_Filter) return 0;

   int trend = GetTrend();
   double kb[]; ArraySetAsSeries(kb,true);
   if(CopyBuffer(g_hStoch,0,0,3,kb)<3) return 0;
   double k_now  = kb[0];
   double k_prev = kb[1];
   bool hiVol = IsHighVolatility();
   int strat = (InpStrategy>=0&&InpStrategy<=2)?InpStrategy:1;
   if(hiVol && strat==1) strat=0; // alta volatilidad → solo Sweep

   int sig = 0;

   if(strat == 0) // Sweep only
   {
      sig = GetSweep();
      if(sig==0) return 0;
      if(trend!=0 && sig!=trend) return 0;
      if(!IntraFiltersPass(sig,k_now,k_prev)) return 0;
   }
   else if(strat == 2) // Breakout
   {
      sig = GetBreakout();
      if(sig==0) return 0;
      if(trend!=0 && sig!=trend) return 0;
      int sz = GetStochZone(k_now,k_prev);
      if(sz!=0 && sz!=sig) return 0;
   }
   else // Hybrid (modo 1): Sweep → FVG → Stoch — igual que backtest original
   {
      // P1: Sweep estructural
      if(Enable_Stop_Hunt_Strategy)
      {
         int s=GetSweep();
         if(s!=0&&(trend==0||s==trend)&&IntraFiltersPass(s,k_now,k_prev))
         { sig=s; g_lastSigType=1; }
      }

      // P2: FVG fill
      if(sig==0 && Enable_FVG_Strategy)
      {
         bool stOKbuy  = (k_now<=Stoch_Buy_Level+10);
         bool stOKsell = (k_now>=Stoch_Sell_Level-10);
         if(InFVG(1) &&stOKbuy &&(trend==0||trend== 1)&&IntraFiltersPass(1,k_now,k_prev)){sig= 1;g_lastSigType=2;}
         if(InFVG(-1)&&stOKsell&&(trend==0||trend==-1)&&IntraFiltersPass(-1,k_now,k_prev)){sig=-1;g_lastSigType=2;}
      }

      // P3: Stoch cruce — señal principal (como en backtest original)
      if(sig==0)
      {
         bool crossBuy  = (k_now <= Stoch_Buy_Level  && k_prev > Stoch_Buy_Level);
         bool crossSell = (k_now >= Stoch_Sell_Level && k_prev < Stoch_Sell_Level);

         if(Enable_Stoch_Depth_Filter)
         {
            if(crossBuy  && k_now > Stoch_Depth_Buy)  crossBuy  = false;
            if(crossSell && k_now < Stoch_Depth_Sell) crossSell = false;
         }

         if(crossBuy  && IntraFiltersPass(1, k_now,k_prev) && (trend==0||trend== 1))
            { sig= 1; g_lastSigType=3; }
         if(crossSell && IntraFiltersPass(-1,k_now,k_prev) && (trend==0||trend==-1))
            { sig=-1; g_lastSigType=3; }
      }
   }

   // ── FILTRO DE CALIDAD v17 ──────────────────────────────────────
   // El Stoch generó una señal → ahora el motor evalúa SU calidad.
   // CalcQualityScore(sig): ¿cuántas capas confirman ESTA dirección?
   // Si score < mínimo → señal débil → no ejecutar.
   // Si Min_Prediction_Score=0 → filtro desactivado (bypass total).
   if(sig != 0 && Min_Prediction_Score > 0)
   {
      int quality = CalcQualityScore(sig);
      if(quality < Min_Prediction_Score)
      {
         g_lastPredScore = quality;
         g_lastPredDir   = sig;
         return 0; // señal sin calidad suficiente → ignorar
      }
   }

   return sig;
}


//--------------------------------------------------------------------
bool IsScheduleAllowed()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int dow=dt.day_of_week,h=dt.hour;
   if(dow==1) return Trade_Monday    &&h>=Monday_Start_Hour    &&h<Monday_End_Hour;
   if(dow==2) return Trade_Tuesday   &&h>=Tuesday_Start_Hour   &&h<Tuesday_End_Hour;
   if(dow==3) return Trade_Wednesday &&h>=Wednesday_Start_Hour &&h<Wednesday_End_Hour;
   if(dow==4) return Trade_Thursday  &&h>=Thursday_Start_Hour  &&h<Thursday_End_Hour;
   if(dow==5) return Trade_Friday    &&h>=Friday_Start_Hour    &&h<Friday_End_Hour;
   if(dow==6) return Trade_Saturday  &&h>=Saturday_Start_Hour  &&h<Saturday_End_Hour;
   if(dow==0) return Trade_Sunday    &&h>=Sunday_Start_Hour    &&h<Sunday_End_Hour;
   return false;
}

// LOT: MathRound() evita caída a 0.04 cuando balance baja a $4,995-4,999
double CalcLot()
{
   if(!Use_dynamic_lot_) return NormalizeDouble(Lot_,2);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double lot=MathRound(bal/Free_margin_for_each_Lots_)*0.01;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot=MathMax(lot,mn); lot=MathMin(lot,MathMin(Max_Lot_,mx));
   if(st>0) lot=MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

int CountByMagic()    {int n=0;for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i);if(PositionSelectByTicket(tk)&&PositionGetInteger(POSITION_MAGIC)==g_magic)n++;}return n;}
int CountLegacyOpen() {int n=0;for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;if(PositionGetInteger(POSITION_MAGIC)!=g_magic)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"[Legacy]")>=0)n++;}return n;}
int CountG2Open()     {int n=0;for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;if(PositionGetInteger(POSITION_MAGIC)!=g_magic)continue;if(StringFind(PositionGetString(POSITION_COMMENT)," G2")>=0)n++;}return n;}
int CountBuys()       {int n=0;for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;if(PositionGetInteger(POSITION_MAGIC)!=g_magic)continue;if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)n++;}return n;}
int CountSells()      {int n=0;for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;if(PositionGetInteger(POSITION_MAGIC)!=g_magic)continue;if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)n++;}return n;}

int CountLegacyClosedToday()
{
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   HistorySelect(ds,TimeCurrent()); int cnt=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {ulong dk=HistoryDealGetTicket(i);if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic)continue;if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT)continue;if(StringFind(HistoryDealGetString(dk,DEAL_COMMENT)," G2")>=0)continue;cnt++;}
   return cnt;
}

void StealthRegister(ulong ticket,double vTP,double vSL,int dir)
{
   if(!Use_Stealth_Mode||ticket==0) return;
   for(int i=0;i<g_spCnt;i++) if(g_sp[i].ticket==ticket){g_sp[i].vTP=vTP;g_sp[i].vSL=vSL;g_sp[i].active=true;return;}
   if(g_spCnt>=ArraySize(g_sp)) ArrayResize(g_sp,g_spCnt+200);
   g_sp[g_spCnt].ticket=ticket;g_sp[g_spCnt].vTP=vTP;g_sp[g_spCnt].vSL=vSL;
   g_sp[g_spCnt].dir=dir;g_sp[g_spCnt].active=true;
   // v14: inicializar trailing
   g_sp[g_spCnt].trailMaxProfit=0.0;
   g_sp[g_spCnt].trailActivated=false;
   g_spCnt++;
}

bool StealthClosePos(ulong ticket,int dir)
{
   if(!PositionSelectByTicket(ticket)) return true;
   MqlTradeRequest req={};MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL;req.symbol=g_sym;req.position=ticket;
   req.volume=PositionGetDouble(POSITION_VOLUME);
   req.type=(dir==1)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price=(dir==1)?SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
   req.deviation=InpSlippagePoints;req.magic=g_magic;req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;bool _s=OrderSend(req,res);}}
   return !PositionSelectByTicket(ticket);
}

void StealthCheckAll()
{
   if(!Use_Stealth_Mode) return;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID),ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   for(int i=0;i<g_spCnt;i++)
   {
      if(!g_sp[i].active) continue;
      if(!PositionSelectByTicket(g_sp[i].ticket)){g_sp[i].active=false;continue;}

      bool cls=false;
      double curProfit = PositionGetDouble(POSITION_PROFIT);
      double posLot    = PositionGetDouble(POSITION_VOLUME);

      // ── Trailing Profit Inteligente v16 ─────────────────────────
      // Los umbrales se escalan automáticamente según el lotaje real.
      // Referencia: lot base = 0.10 (los parámetros están calibrados para 0.10 lot)
      // Si el lot real es menor o mayor, ajusta proporcionalmente.
      // Ej: lot=0.05 → umbral×0.5; lot=0.20 → umbral×2.0
      if(Enable_Trailing_Profit || Enable_MinUSD_TP)
      {
         double lotRef   = 0.10; // lot de referencia para los parámetros
         double lotScale = (posLot > 0) ? (posLot / lotRef) : 1.0;
         double activateUSD = TP_Trail_Activate_USD * lotScale;
         double retraceUSD  = TP_Trail_Retrace_USD  * lotScale;
         double minUSD      = TP_Min_USD             * lotScale;

         // MODO 1: TP por USD mínimo — cierre inmediato
         if(Enable_MinUSD_TP && curProfit >= minUSD)
            cls = true;

         // MODO 2: Trailing Profit escalado por lotaje
         if(!cls && Enable_Trailing_Profit)
         {
            // Actualizar máximo profit alcanzado
            if(curProfit > g_sp[i].trailMaxProfit)
               g_sp[i].trailMaxProfit = curProfit;

            // Activar trailing cuando se alcanza el umbral (escalado)
            if(!g_sp[i].trailActivated && curProfit >= activateUSD)
               g_sp[i].trailActivated = true;

            // Cerrar cuando el profit retrocede desde el máximo (escalado)
            if(g_sp[i].trailActivated)
            {
               double retrace = g_sp[i].trailMaxProfit - curProfit;
               if(retrace >= retraceUSD) cls = true;
            }
         }
      }

      // ── Trailing Stop Inteligente v16 ────────────────────────────
      // El Trailing Stop usa ATR×multiplier escalado por lotaje.
      // La distancia de activación y trailing se ajustan al tamaño real.
      // En stealth: movemos el vSL virtual conforme el precio avanza.
      if(!cls && Enable_TrailingStop)
      {
         double posType = PositionGetInteger(POSITION_TYPE); // 0=BUY, 1=SELL
         double entryPx = PositionGetDouble(POSITION_PRICE_OPEN);
         double atr     = GetATR();
         double posLotCl= PositionGetDouble(POSITION_VOLUME);

         // Escalar distancias por lotaje (lot 0.10 = referencia 1.0)
         double lotRef2  = 0.10;
         double lScale2  = MathMax(0.5, MathMin(posLotCl / lotRef2, 3.0));
         // Nota: no escalar demasiado — el mercado se mueve lo mismo
         // independiente del lot. Escalamos suavemente (raíz cuadrada)
         double lScaleSoft = MathSqrt(lScale2);

         double tsStart = atr * TS_Start_ATR_Multiplier;    // cuándo activar
         double tsDist  = atr * TS_Distance_ATR_Multiplier; // distancia del trail

         if(posType == POSITION_TYPE_BUY)
         {
            double currentBid = bid;
            // Activar si precio subió suficiente desde entrada
            if(currentBid >= entryPx + tsStart)
            {
               // Nuevo SL virtual = precio actual - tsDist
               double newVSL = currentBid - tsDist;
               // Solo subir el SL, nunca bajarlo
               if(newVSL > g_sp[i].vSL)
                  g_sp[i].vSL = newVSL;
            }
            // Verificar si el SL virtual fue tocado
            if(g_sp[i].vSL > 0 && bid <= g_sp[i].vSL)
               cls = true;
         }
         else // SELL
         {
            double currentAsk = ask;
            // Activar si precio bajó suficiente desde entrada
            if(currentAsk <= entryPx - tsStart)
            {
               // Nuevo SL virtual = precio actual + tsDist
               double newVSL = currentAsk + tsDist;
               // Solo bajar el SL, nunca subirlo
               if(newVSL < g_sp[i].vSL || g_sp[i].vSL <= 0)
                  g_sp[i].vSL = newVSL;
            }
            // Verificar si el SL virtual fue tocado
            if(g_sp[i].vSL > 0 && ask >= g_sp[i].vSL)
               cls = true;
         }
      }

      // ── TP/SL Virtual original (precio fijo) ────────────────────
      // Solo si no hay trailing activo o como fallback de seguridad
      if(!cls)
      {
         if(g_sp[i].dir==1){if(g_sp[i].vTP>0&&bid>=g_sp[i].vTP)cls=true;else if(g_sp[i].vSL>0&&!Enable_TrailingStop&&bid<=g_sp[i].vSL)cls=true;}
         else              {if(g_sp[i].vTP>0&&ask<=g_sp[i].vTP)cls=true;else if(g_sp[i].vSL>0&&!Enable_TrailingStop&&ask>=g_sp[i].vSL)cls=true;}
         // Cuando TrailingStop activo, el vSL se maneja arriba — solo aplicar TP fijo aquí
         if(Enable_TrailingStop && !cls)
         {
            if(g_sp[i].dir==1){if(g_sp[i].vTP>0&&bid>=g_sp[i].vTP)cls=true;}
            else               {if(g_sp[i].vTP>0&&ask<=g_sp[i].vTP)cls=true;}
         }
      }

      if(cls&&StealthClosePos(g_sp[i].ticket,g_sp[i].dir)) g_sp[i].active=false;
   }
}

ulong OpenOrder(ENUM_ORDER_TYPE type,string comment,double slMul)
{
   double lot=CalcLot();
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK),bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double entry=(type==ORDER_TYPE_BUY)?ask:bid;
   int dir=(type==ORDER_TYPE_BUY)?1:-1;
   double slPts=(slMul<=1.0)?MM7_G2_SL_FIXED:MM7_SL_FIXED;
   double vTP=entry+dir*MM7_TP_FIXED, vSL=entry-dir*slPts;
   MqlTradeRequest req={};MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL;req.symbol=g_sym;req.volume=lot;
   req.type=type;req.price=entry;req.sl=0;req.tp=0;
   req.deviation=InpSlippagePoints;req.magic=g_magic;req.comment=comment;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;bool _o=OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
   {
      ulong posTk=0;
      if(res.deal>0&&HistoryDealSelect(res.deal)){ulong pid=(ulong)HistoryDealGetInteger(res.deal,DEAL_POSITION_ID);if(pid>0)posTk=pid;}
      if(posTk==0&&res.deal>0) posTk=res.deal;
      if(posTk==0||!PositionSelectByTicket(posTk))
      {ulong bk=0;datetime bt=0;for(int p=PositionsTotal()-1;p>=0;p--){ulong tk2=PositionGetTicket(p);if(!PositionSelectByTicket(tk2))continue;if(PositionGetString(POSITION_SYMBOL)!=g_sym||PositionGetInteger(POSITION_MAGIC)!=g_magic)continue;datetime t2=(datetime)PositionGetInteger(POSITION_TIME);if(t2>=bt){bt=t2;bk=tk2;}}if(bk>0)posTk=bk;}
      if(Use_Stealth_Mode&&posTk>0) StealthRegister(posTk,vTP,vSL,dir);
      return posTk;
   }
   return 0;
}

// G2: basado en segundos (no barras) porque los trades duran <1 barra en promedio
void CheckG2()
{
   if(!Recovery_Mode_Enabled||CountG2Open()>0||CountLegacyOpen()==0) return;
   int lc=CountLegacyClosedToday();
   if(lc-g_legacyClosedAtLastG2<G2_Legacy_Threshold) return;
   datetime ot=0;int ld=0;ulong ltk=0;
   for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i);if(!PositionSelectByTicket(tk))continue;if(PositionGetInteger(POSITION_MAGIC)!=g_magic)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"[Legacy]")<0)continue;datetime t=(datetime)PositionGetInteger(POSITION_TIME);if(ot==0||t<ot){ot=t;ltk=tk;ld=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;}}
   if(ot==0||ltk==0||ltk==g_g2ForLegacyTicket) return;
   if((TimeCurrent()-ot)<G2_Min_Seconds) return;
   if(g_lastG2OpenTime==TimeCurrent()) return;
   ENUM_ORDER_TYPE type=(ld==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   ulong tk=OpenOrder(type,CommentOrder+" G2",1.0);
   if(tk>0){g_lastG2OpenTime=TimeCurrent();g_legacyClosedAtLastG2=lc;g_g2OpenedThisLegacy=true;g_g2ForLegacyTicket=ltk;}
}

void DailyReset()
{
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today==g_dayStart) return;
   g_dayStart=today;g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);g_haltedToday=false;
   g_legacyClosedAtLastG2=0;g_g2OpenedThisLegacy=false;g_g2ForLegacyTicket=0;
   g_lastSignalBar=0;g_fvgLastScan=0;g_fvgCnt=0;
   g_consec_loss_buy=0;g_consec_loss_sell=0;
   g_pause_buy_until=0;g_pause_sell_until=0;
   g_fastLossCount=0;g_fastLossWinStart=0;g_pause_fast_until=0;
   g_marketRegime=0;g_regimeScanBar=0;
   // v10: reset entry quality control
   g_lastEntryTime=0;g_postCloseLockout=0;g_lastCycleDir=0;
}

void CheckHaltConditions()
{
   if(g_haltedToday) return;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE),eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxEquityDrawdown>0&&bal>0&&(bal-eq)/bal*100.0>=InpMaxEquityDrawdown){g_haltedToday=true;return;}
   if(InpMaxDailyLossPct>0&&g_dayStartBal>0&&(g_dayStartBal-bal)/g_dayStartBal*100.0>=InpMaxDailyLossPct) g_haltedToday=true;
}

void DashLbl(string nm,string txt,color clr,int oy,int x,int y,ENUM_BASE_CORNER c,int fn)
{
   string f="MM7D_"+nm;
   if(ObjectFind(0,f)<0){ObjectCreate(0,f,OBJ_LABEL,0,0,0);ObjectSetInteger(0,f,OBJPROP_CORNER,c);ObjectSetInteger(0,f,OBJPROP_XDISTANCE,x);ObjectSetString(0,f,OBJPROP_FONT,"Courier New");ObjectSetInteger(0,f,OBJPROP_FONTSIZE,fn);}
   ObjectSetInteger(0,f,OBJPROP_YDISTANCE,y+oy);ObjectSetString(0,f,OBJPROP_TEXT,txt);ObjectSetInteger(0,f,OBJPROP_COLOR,clr);
}

void DrawDashboard()
{
   if(!Enable_Dashboard||TimeCurrent()-g_lastDashTime<Refresh_Interval_Seconds) return;
   g_lastDashTime=TimeCurrent();
   double bal=AccountInfoDouble(ACCOUNT_BALANCE),eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double dd=(bal>0)?(bal-eq)/bal*100.0:0;
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   double dp=0; HistorySelect(ds,TimeCurrent());
   for(int i=0;i<HistoryDealsTotal();i++){ulong dk=HistoryDealGetTicket(i);if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)==g_magic)dp+=HistoryDealGetDouble(dk,DEAL_PROFIT);}
   string ms=(InpStrategy==0)?"Sweep":(InpStrategy==1)?"Hybrid":"Breakout";
   bool hv=IsHighVolatility(); double lot=CalcLot();
   double kb[]; ArraySetAsSeries(kb,true); double k1=50;
   if(CopyBuffer(g_hStoch,0,1,2,kb)>=2) k1=kb[0];
   int x=Dashboard_X_Offset,y=Dashboard_Y_Offset,fn=Font_size_Result,lh=fn+4;
   ENUM_BASE_CORNER co=(ENUM_BASE_CORNER)Dashboard_Corner;
   DashLbl("0","[ MoneyMachine7 v17.0 ]",clrGold,       0*lh,x,y,co,fn);
   DashLbl("1","Mode : "+ms+(hv?" [HiVol→Sweep]":"")+" QScore>="+IntegerToString(Min_Prediction_Score)+" Trail:"+(Enable_Trailing_Profit?"ON":"off"),clrCyan,1*lh,x,y,co,fn);
   DashLbl("2","Bal  : $"+DoubleToString(bal,2)+" lot="+DoubleToString(lot,2),clrWhite,2*lh,x,y,co,fn);
   DashLbl("3","Eq   : $"+DoubleToString(eq,2)+" K="+DoubleToString(k1,1),clrWhite,3*lh,x,y,co,fn);
   DashLbl("4","DD   : "+DoubleToString(dd,2)+"%",(dd>2)?clrOrangeRed:clrLimeGreen,4*lh,x,y,co,fn);
   DashLbl("5","Open : "+(string)CountByMagic()+" FVG:"+(string)g_fvgCnt,clrWhite,5*lh,x,y,co,fn);
   DashLbl("6","Day  : $"+DoubleToString(dp,2),(dp>=0)?clrLimeGreen:clrOrangeRed,6*lh,x,y,co,fn);
   // v16: Predictive Engine Score display
   string pred_dir_str=(g_lastPredDir==1)?"↑BUY":(g_lastPredDir==-1)?"↓SELL":"--";
   string pred_score_str=IntegerToString(g_lastPredScore)+"/5";
   color  pred_col=(g_lastPredScore>=Min_Prediction_Score)?clrLimeGreen:(g_lastPredScore>=2)?clrYellow:clrOrangeRed;
   // Layers per direction (MTF + OFI + MomentumBias + Structure + Stoch)
   int mtf_b=GetMTFConfluence(1); int mtf_s=GetMTFConfluence(-1);
   int ofl_b=GetOrderFlowBias(1); int ofl_s=GetOrderFlowBias(-1);
   int ema_b=GetMomentumBias(1);  int ema_s=GetMomentumBias(-1);
   int str_b=GetPriceStructure(1);int str_s=GetPriceStructure(-1);
   int stk_b=GetStochTiming(1);   int stk_s=GetStochTiming(-1);
   int tot_b=mtf_b+ofl_b+ema_b+str_b+stk_b;
   int tot_s=mtf_s+ofl_s+ema_s+str_s+stk_s;
   string layers_b="B:M"+IntegerToString(mtf_b)+"O"+IntegerToString(ofl_b)+"E"+IntegerToString(ema_b)+"S"+IntegerToString(str_b)+"K"+IntegerToString(stk_b)+"="+IntegerToString(tot_b);
   string layers_s="S:M"+IntegerToString(mtf_s)+"O"+IntegerToString(ofl_s)+"E"+IntegerToString(ema_s)+"S"+IntegerToString(str_s)+"K"+IntegerToString(stk_s)+"="+IntegerToString(tot_s);
   color b_col=(tot_b>=Min_Prediction_Score)?clrLimeGreen:clrOrangeRed;
   color s_col=(tot_s>=Min_Prediction_Score)?clrLimeGreen:clrOrangeRed;
   DashLbl("prd","PRED:"+pred_dir_str+" ["+pred_score_str+"] min="+IntegerToString(Min_Prediction_Score),pred_col,7*lh,x,y,co,fn);
   DashLbl("lyrb",layers_b,b_col,8*lh,x,y,co,fn);
   DashLbl("lyrs",layers_s,s_col,9*lh,x,y,co,fn);
   // Lot-scaled trailing info
   double lotScale=(lot>0)?(lot/0.10):1.0;
   string trail_str="Act:$"+DoubleToString(TP_Trail_Activate_USD*lotScale,2)+" Ret:$"+DoubleToString(TP_Trail_Retrace_USD*lotScale,2);
   DashLbl("trl","Trail(×lot) "+trail_str,clrCyan,10*lh,x,y,co,fn);
   string cool_str="";
   if(IsCoolingOff(1))  cool_str+="B";
   if(IsCoolingOff(-1)) cool_str+="S";
   if(IsFastLossPause()) cool_str+="!";
   datetime now_d=TimeCurrent();
   if(now_d<g_postCloseLockout) cool_str+="L"; // L=post-close Lockout
   int cd_remain=(int)(g_lastEntryTime+Entry_Cooldown_Secs-now_d);
   if(cd_remain>0&&cool_str=="") cool_str="C"+IntegerToString(cd_remain);
   if(cool_str=="") cool_str="OK";
   DashLbl("8","Cool:"+cool_str+" Halt:"+(g_haltedToday?"Y":"n")+" ATR:"+DoubleToString(GetATR(),2),(g_haltedToday||cool_str!="OK")?clrOrangeRed:clrGray,11*lh,x,y,co,fn);
}

void DrawHistoryLabels()
{
   if(!Enable_History_Labels||TimeCurrent()-g_lastLabelTime<10) return;
   g_lastLabelTime=TimeCurrent(); ObjectsDeleteAll(0,"MM7L_");
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   HistorySelect(ds,TimeCurrent()); int tot=HistoryDealsTotal(),st=MathMax(0,tot-History_Labels_Limit);
   for(int i=st;i<tot;i++){ulong dk=HistoryDealGetTicket(i);if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic)continue;if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT)continue;
   double pf=HistoryDealGetDouble(dk,DEAL_PROFIT),px=HistoryDealGetDouble(dk,DEAL_PRICE);datetime t=(datetime)HistoryDealGetInteger(dk,DEAL_TIME);
   string nm="MM7L_"+(string)dk;if(ObjectFind(0,nm)<0)ObjectCreate(0,nm,OBJ_TEXT,0,t,px);
   ObjectSetString(0,nm,OBJPROP_TEXT,(pf>=0?"+":"")+DoubleToString(pf,2));ObjectSetInteger(0,nm,OBJPROP_COLOR,(pf>=0)?clrLimeGreen:clrOrangeRed);ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8);}
}

int OnInit()
{
   g_magic=InpMagicNumber; g_sym=_Symbol;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT); if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   // v12: MODE_EMA en lugar de MODE_SMA
   g_hStoch=iStochastic(g_sym,_Period,Stoch_K_Period,Stoch_D_Period,Stoch_Slowing,MODE_EMA,STO_LOWHIGH);
   if(g_hStoch==INVALID_HANDLE){Alert("Stoch failed");return INIT_FAILED;}
   if(Enable_Trend_Filter){g_hMA=iMA(g_sym,PERIOD_H1,Trend_MA_Period,0,MODE_SMA,PRICE_CLOSE);if(g_hMA==INVALID_HANDLE){Alert("MA200 failed");return INIT_FAILED;}}
   if(Enable_EMA20_Gate){g_hEMA20=iMA(g_sym,_Period,EMA20_Period,0,MODE_EMA,PRICE_CLOSE);if(g_hEMA20==INVALID_HANDLE){Alert("EMA20 failed");return INIT_FAILED;}}
   g_hATR=iATR(g_sym,_Period,ATR_Period); if(g_hATR==INVALID_HANDLE){Alert("ATR failed");return INIT_FAILED;}
   if(Use_RSI_Confirmation){g_hRSI=iRSI(g_sym,_Period,RSI_Period,PRICE_CLOSE);if(g_hRSI==INVALID_HANDLE){Alert("RSI failed");return INIT_FAILED;}}

   // ── v15: Predictive Intelligence Engine — inicializar indicadores ──
   if(Enable_EMA_Momentum || Enable_MTF_Confluence)
   {
      g_hEMA_Fast=iMA(g_sym,_Period,EMA_Fast_Period,0,MODE_EMA,PRICE_CLOSE);
      if(g_hEMA_Fast==INVALID_HANDLE){Alert("EMA_Fast failed");return INIT_FAILED;}
      g_hEMA_Slow=iMA(g_sym,_Period,EMA_Slow_Period,0,MODE_EMA,PRICE_CLOSE);
      if(g_hEMA_Slow==INVALID_HANDLE){Alert("EMA_Slow failed");return INIT_FAILED;}
   }
   if(Enable_MTF_Confluence)
   {
      g_hEMA_M5 =iMA(g_sym,PERIOD_M5, 21,0,MODE_EMA,PRICE_CLOSE); // EMA21 en M5
      g_hEMA_M15=iMA(g_sym,PERIOD_M15,21,0,MODE_EMA,PRICE_CLOSE); // EMA21 en M15
      if(g_hEMA_M5 ==INVALID_HANDLE){Alert("EMA_M5 failed"); return INIT_FAILED;}
      if(g_hEMA_M15==INVALID_HANDLE){Alert("EMA_M15 failed");return INIT_FAILED;}
   }

   ArrayResize(g_sp,500);g_spCnt=0;ArrayResize(g_fvg,100);g_fvgCnt=0;
   g_dayStart=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_legacyClosedAtLastG2=CountLegacyClosedToday();
   string ms=(InpStrategy==0)?"Sweep":(InpStrategy==1)?"Hybrid":"Breakout";
   Print("MM7 v17.0 | QUALITY FILTER ENGINE | Mode=",ms,
         " | QualityScore>=",Min_Prediction_Score,"/5 (0=OFF)",
         " | MTF(slope)=",Enable_MTF_Confluence," OFlow=",Enable_OrderFlow_Bias,
         " | MomBias=",Enable_EMA_Momentum," Structure=",Enable_Price_Structure,
         " | TrailProfit=",Enable_Trailing_Profit," act=$",TP_Trail_Activate_USD,"(×lot) ret=$",TP_Trail_Retrace_USD,"(×lot)",
         " | TrailStop=",Enable_TrailingStop,
         " | FIX v17: Stoch decide direccion, Motor valida calidad solamente");
   EventSetTimer(5); return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hStoch  !=INVALID_HANDLE)IndicatorRelease(g_hStoch);
   if(g_hMA     !=INVALID_HANDLE)IndicatorRelease(g_hMA);
   if(g_hEMA20  !=INVALID_HANDLE)IndicatorRelease(g_hEMA20);
   if(g_hATR    !=INVALID_HANDLE)IndicatorRelease(g_hATR);
   if(g_hRSI    !=INVALID_HANDLE)IndicatorRelease(g_hRSI);
   // v15: Predictive Engine
   if(g_hEMA_Fast !=INVALID_HANDLE)IndicatorRelease(g_hEMA_Fast);
   if(g_hEMA_Slow !=INVALID_HANDLE)IndicatorRelease(g_hEMA_Slow);
   if(g_hEMA_M5   !=INVALID_HANDLE)IndicatorRelease(g_hEMA_M5);
   if(g_hEMA_M15  !=INVALID_HANDLE)IndicatorRelease(g_hEMA_M15);
   ObjectsDeleteAll(0,"MM7D_"); ObjectsDeleteAll(0,"MM7L_");
}

void OnTick()
{
   StealthCheckAll();
   // v10: detectar cierre de posición para activar post-close lockout
   static int g_prevPosCount = -1;
   int curPosCount = CountLegacyOpen();
   if(g_prevPosCount > 0 && curPosCount == 0)
   {
      // Una Legacy acaba de cerrarse → activar lockout
      g_postCloseLockout = TimeCurrent() + PostClose_Lockout_Secs;
   }
   g_prevPosCount = curPosCount;

   DailyReset(); CheckHaltConditions();
   if(g_haltedToday){DrawDashboard();return;}
   if(!IsScheduleAllowed()){DrawDashboard();return;}
   if(InpMaxSpreadPoints>0&&SymbolInfoInteger(g_sym,SYMBOL_SPREAD)>InpMaxSpreadPoints) return;
   ScanFVGs(); UpdateSwings(); UpdateMarketRegime();
   UpdateCoolingOff();
   CheckG2();
   if(CountLegacyOpen()==0)
   {
      datetime now = TimeCurrent();

      // v10 COOLDOWN SYSTEM (reemplaza throttle 3s):
      // 1. Post-close lockout: tras cierre de posición, esperar N segundos
      //    Evita SL→re-entrada inmediata en el mismo movimiento adverso
      if(now < g_postCloseLockout){DrawDashboard();return;}

      // 2. Entry cooldown: tiempo mínimo entre señales consecutivas
      //    Evita múltiples entradas en el mismo ciclo Stoch oscilante
      //    Original promedia ~218s entre entradas, mínimo ~30s
      if(now - g_lastEntryTime < Entry_Cooldown_Secs){DrawDashboard();return;}

      int sig=GetSignal();
      if(sig== 1&&CountBuys() >=Max_Buy)  sig=0;
      if(sig==-1&&CountSells()>=Max_Sell) sig=0;
      if(sig==1)  {ulong tk=OpenOrder(ORDER_TYPE_BUY, CommentOrder+" [Legacy]",Auto_SL_Ratio);if(tk>0){g_lastEntryTime=now;g_lastSignalBar=now;g_lastLegacyTicket=tk;}}
      if(sig==-1) {ulong tk=OpenOrder(ORDER_TYPE_SELL,CommentOrder+" [Legacy]",Auto_SL_Ratio);if(tk>0){g_lastEntryTime=now;g_lastSignalBar=now;g_lastLegacyTicket=tk;}}
   }
   DrawDashboard();
}

void OnTimer() { DrawHistoryLabels(); }
