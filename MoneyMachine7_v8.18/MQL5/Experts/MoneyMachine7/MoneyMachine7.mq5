//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  FORENSIC REPLICA v8.18                                         |
//|  MEJORAS vs v8.17:                                               |
//|  1. EMA20 M1 intraday trend gate (filtra mov. sostenidos contra) |
//|  cae dentro de zona. Ahora requiere K cruzar DE VUELTA hacia     |
//|  zona neutra (señal de reversión real, no zona activa)           |
//|  4. Momentum gate: stoch K aceleración mínima                   |
//|  CAMBIOS vs v8.15:                                               |
//|  1. STOCH ZONE-EXIT: requiere K volviendo HACIA zona neutra     |
//|     (k_prev más extremo que k_now). Entra justo cuando K         |
//|     empieza a recuperarse, no mientras sigue cayendo.            |
//|  2. G2 FIX: seconds-based (no barras) - trades duran <1 barra   |
//|  3. LOT: MathRound() corregido (v8.15 ya lo tenía)             |
//|  4. Todo lo demás idéntico a v8.15 (SMC: Sweep/FVG/Hybrid)      |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "8.18"
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
// +++ Forensic Core +++
input double MM7_TP_FIXED                = 2.50;
input double MM7_SL_FIXED                = 0.77;
input double MM7_G2_SL_FIXED             = 0.50;
// +++ v8.17 Signal Quality +++
input bool   Enable_Zone_Exit_Filter     = true;  // K debe retornar hacia zona neutra (no solo estar en zona)
input bool   Enable_Candle_Filter        = true;  // cuerpo de vela confirma dirección (soft: bypass en sweep/FVG)
input bool   Enable_BOS_Filter           = true;  // Break of Structure para señales puras de stoch
input int    BOS_Lookback                = 5;
input double ATR_HighVol_Multiplier      = 1.8;   // ATR alta volatilidad → modo Sweep únicamente
input int    G2_Min_Seconds              = 20;    // segundos mínimos legacy abierto antes de G2
// +++ v8.18 Intraday Intelligence +++
input bool   Enable_EMA20_Gate           = true;   // EMA20 M1: no BUY si precio bajo EMA20, no SELL si arriba
input int    EMA20_Period                = 20;     // periodo EMA intraday (20 barras M1 = ~20 min)
input bool   Enable_Stoch_D_Confirm     = true;   // K>D para BUY confirmado, K<D para SELL
input double Min_K_Velocity             = 0.5;    // K debe moverse mínimo X pts entre barras (momentum)
input int    G2_Legacy_Threshold        = 13;     // G2 cada N legacies (forense: 13, param: 4)

//============================================================
#define MM7_G2_MIN_GAP_S  2
#define MM7_ATR_FALLBACK  0.50

struct StealthPos { ulong ticket; double vTP,vSL; int dir; bool active; };
struct FVGZone    { double top,bot; int dir; bool active; };

int      g_magic; double g_point; string g_sym;
int      g_hStoch=INVALID_HANDLE, g_hMA=INVALID_HANDLE, g_hEMA20=INVALID_HANDLE;
int      g_hATR=INVALID_HANDLE,   g_hRSI=INVALID_HANDLE;

StealthPos g_sp[];   int g_spCnt=0;
FVGZone    g_fvg[];  int g_fvgCnt=0;
datetime   g_fvgLastScan=0;

int      g_legacyClosedAtLastG2=0;
datetime g_lastG2OpenTime=0;
bool     g_g2OpenedThisLegacy=false;
ulong    g_g2ForLegacyTicket=0;
datetime g_lastSignalBarTime=0;
ulong    g_lastLegacyTicket=0;
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
   double velocity = k_now - k_prev;
   if(dir==1)  return velocity >= Min_K_Velocity;  // K accelerating UP for BUY
   if(dir==-1) return velocity <= -Min_K_Velocity; // K accelerating DOWN for SELL
   return true;
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

//--------------------------------------------------------------------
// SEÑAL STOCH CON ZONE-EXIT FILTER (la mejora clave de v8.17)
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

// Aplicar todos los filtros intraday sobre una señal candidata
// Retorna false si algún filtro la rechaza
bool IntraFiltersPass(int sig, double k_now, double k_prev)
{
   // 1. EMA20 gate: bloquea dirección contra tendencia intraday
   int ema_gate = GetEMA20Gate();
   if(ema_gate != 0 && sig != ema_gate) return false;

   // 2. Stoch D-line confirmation
   if(!StochDConfirm(sig)) return false;

   // 3. K velocity: señal debe tener momentum suficiente
   if(!KVelocityOK(k_now, k_prev, sig)) return false;

   return true;
}

//============================================================
// MASTER SIGNAL v8.17
//============================================================
int GetSignal()
{
   if(!Use_Grid_Stoch_Filter) return 0;
   double kb[]; ArraySetAsSeries(kb,true);
   if(CopyBuffer(g_hStoch,0,0,3,kb)<3) return 0;
   double k_now  = kb[1];  // barra completada actual
   double k_prev = kb[2];  // barra anterior

   int trend=GetTrend();
   int strat=(InpStrategy>=0&&InpStrategy<=2)?InpStrategy:1;
   bool hiVol=IsHighVolatility();
   if(hiVol&&strat==1) strat=0;  // alta volatilidad → solo Sweep

   int sig=0;
   bool fromSweep=false, fromFVG=false;

   if(strat==0) // Sweep only
   {
      sig=GetSweep(); if(sig==0) return 0;
      if(trend!=0&&sig!=trend) return 0;
      // Sweep: EMA20 gate applies (sweeps in wrong intraday direction still fail)
      if(!IntraFiltersPass(sig,k_now,k_prev)) return 0;
      fromSweep=true;
   }
   else if(strat==2) // Breakout
   {
      sig=GetBreakout(); if(sig==0) return 0;
      if(trend!=0&&sig!=trend) return 0;
      // Stoch zone check para breakout
      int sz=GetStochZone(k_now,k_prev);
      if(sz!=0&&sz!=sig) return 0;
   }
   else // Hybrid (modo 1)
   {
      // P1: Sweep (mayor calidad estructural)
      if(Enable_Stop_Hunt_Strategy)
      { int s=GetSweep(); if(s!=0&&(trend==0||s==trend)){sig=s;fromSweep=true;} }

      // P2: FVG fill
      if(sig==0&&Enable_FVG_Strategy)
      {
         int sz=GetStochZone(k_now,k_prev);
         // FVG acepta stoch en zona (con o sin zone-exit) — es señal estructural
         bool stOKbuy  = (k_now<=Stoch_Buy_Level+10);
         bool stOKsell = (k_now>=Stoch_Sell_Level-10);
         if(Enable_Zone_Exit_Filter) { stOKbuy=(sz==1||stOKbuy); stOKsell=(sz==-1||stOKsell); }
         if(InFVG(1) &&stOKbuy &&(trend==0||trend== 1)&&IntraFiltersPass(1,k_now,k_prev)){sig= 1;fromFVG=true;}
         if(InFVG(-1)&&stOKsell&&(trend==0||trend==-1)&&IntraFiltersPass(-1,k_now,k_prev)){sig=-1;fromFVG=true;}
      }

      // P3: Stoch puro + confirmadores + filtros intraday
      if(sig==0)
      {
         int sz=GetStochZone(k_now,k_prev);
         if(sz==0) return 0; // sin señal stoch con zone-exit → no opera

         // Filtros intraday en P3 (más estricto que sweep/FVG)
         if(!IntraFiltersPass(sz,k_now,k_prev)) return 0;

         double rsi=GetRSI(); bool volOK=IsVolumeOK();
         bool qualBuy  = (sz==1)  && (rsi<RSI_Buy_Threshold  || volOK);
         bool qualSell = (sz==-1) && (rsi>RSI_Sell_Threshold || volOK);

         // Boost: Breakout en misma dirección
         if(Enable_Breakout_Strategy)
         { int b=GetBreakout(); if(b==1&&qualBuy&&(trend==0||trend==1)){sig=1;} else if(b==-1&&qualSell&&(trend==0||trend==-1)){sig=-1;} }

         // Stoch puro: necesita BOS para confirmar estructura
         if(sig==0)
         {
            if(qualBuy &&(trend==0||trend== 1)&&HasBOS(1))  sig= 1;
            if(qualSell&&(trend==0||trend==-1)&&HasBOS(-1)) sig=-1;
         }
      }
   }

   if(sig==0) return 0;

   // Candle filter SOFT: solo para señales P3 (no sweep ni FVG)
   if(Enable_Candle_Filter&&!fromSweep&&!fromFVG)
   { int cd=GetCandleDir(); if(cd!=0&&cd!=sig) return 0; }

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
   g_sp[g_spCnt].dir=dir;g_sp[g_spCnt].active=true;g_spCnt++;
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
      if(g_sp[i].dir==1){if(g_sp[i].vTP>0&&bid>=g_sp[i].vTP)cls=true;else if(g_sp[i].vSL>0&&bid<=g_sp[i].vSL)cls=true;}
      else              {if(g_sp[i].vTP>0&&ask<=g_sp[i].vTP)cls=true;else if(g_sp[i].vSL>0&&ask>=g_sp[i].vSL)cls=true;}
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
   g_lastSignalBarTime=0;g_fvgLastScan=0;g_fvgCnt=0;
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
   DashLbl("0","[ MoneyMachine7 v8.17 ]",clrGold,       0*lh,x,y,co,fn);
   DashLbl("1","Mode : "+ms+(hv?" [HiVol→Sweep]":""),clrCyan,1*lh,x,y,co,fn);
   DashLbl("2","Bal  : $"+DoubleToString(bal,2)+" lot="+DoubleToString(lot,2),clrWhite,2*lh,x,y,co,fn);
   DashLbl("3","Eq   : $"+DoubleToString(eq,2)+" K="+DoubleToString(k1,1),clrWhite,3*lh,x,y,co,fn);
   DashLbl("4","DD   : "+DoubleToString(dd,2)+"%",(dd>2)?clrOrangeRed:clrLimeGreen,4*lh,x,y,co,fn);
   DashLbl("5","Open : "+(string)CountByMagic()+" FVG:"+(string)g_fvgCnt,clrWhite,5*lh,x,y,co,fn);
   DashLbl("6","Day  : $"+DoubleToString(dp,2),(dp>=0)?clrLimeGreen:clrOrangeRed,6*lh,x,y,co,fn);
   int ema_g=GetEMA20Gate();
   string ema_str=(ema_g==1)?"↑BUY":(ema_g==-1)?"↓SELL":"OFF";
   DashLbl("7","EMA20: "+ema_str+" ATR:"+DoubleToString(GetATR(),3),clrGray,7*lh,x,y,co,fn);
   DashLbl("8","Halt : "+(g_haltedToday?"YES":"no"),(g_haltedToday)?clrRed:clrGray,8*lh,x,y,co,fn);
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
   g_hStoch=iStochastic(g_sym,_Period,Stoch_K_Period,Stoch_D_Period,Stoch_Slowing,MODE_SMA,STO_LOWHIGH);
   if(g_hStoch==INVALID_HANDLE){Alert("Stoch failed");return INIT_FAILED;}
   if(Enable_Trend_Filter){g_hMA=iMA(g_sym,_Period,Trend_MA_Period,0,MODE_SMA,PRICE_CLOSE);if(g_hMA==INVALID_HANDLE){Alert("MA200 failed");return INIT_FAILED;}}
   if(Enable_EMA20_Gate){g_hEMA20=iMA(g_sym,_Period,EMA20_Period,0,MODE_EMA,PRICE_CLOSE);if(g_hEMA20==INVALID_HANDLE){Alert("EMA20 failed");return INIT_FAILED;}}
   g_hATR=iATR(g_sym,_Period,ATR_Period); if(g_hATR==INVALID_HANDLE){Alert("ATR failed");return INIT_FAILED;}
   if(Use_RSI_Confirmation){g_hRSI=iRSI(g_sym,_Period,RSI_Period,PRICE_CLOSE);if(g_hRSI==INVALID_HANDLE){Alert("RSI failed");return INIT_FAILED;}}
   ArrayResize(g_sp,500);g_spCnt=0;ArrayResize(g_fvg,100);g_fvgCnt=0;
   g_dayStart=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_legacyClosedAtLastG2=CountLegacyClosedToday();
   string ms=(InpStrategy==0)?"Sweep":(InpStrategy==1)?"Hybrid":"Breakout";
   Print("MM7 v8.18 | Mode=",ms," | EMA20Gate=",Enable_EMA20_Gate," | DConf=",Enable_Stoch_D_Confirm,
         " | KVel=",Min_K_Velocity," | G2every=",G2_Legacy_Threshold,
         " | ZoneExit=",Enable_Zone_Exit_Filter,
         " | CandleSoft=",Enable_Candle_Filter," | BOS=",Enable_BOS_Filter,
         " | HiVolATRx=",ATR_HighVol_Multiplier," | G2sec=",G2_Min_Seconds);
   EventSetTimer(5); return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hStoch!=INVALID_HANDLE)IndicatorRelease(g_hStoch);
   if(g_hMA   !=INVALID_HANDLE)IndicatorRelease(g_hMA);
   if(g_hEMA20!=INVALID_HANDLE)IndicatorRelease(g_hEMA20);
   if(g_hATR  !=INVALID_HANDLE)IndicatorRelease(g_hATR);
   if(g_hRSI  !=INVALID_HANDLE)IndicatorRelease(g_hRSI);
   ObjectsDeleteAll(0,"MM7D_"); ObjectsDeleteAll(0,"MM7L_");
}

void OnTick()
{
   StealthCheckAll();
   DailyReset(); CheckHaltConditions();
   if(g_haltedToday){DrawDashboard();return;}
   if(!IsScheduleAllowed()){DrawDashboard();return;}
   if(InpMaxSpreadPoints>0&&SymbolInfoInteger(g_sym,SYMBOL_SPREAD)>InpMaxSpreadPoints) return;
   ScanFVGs(); UpdateSwings();
   CheckG2();
   if(CountLegacyOpen()==0)
   {
      datetime bOpen=iTime(g_sym,_Period,0);
      if(bOpen<=g_lastSignalBarTime){DrawDashboard();return;}
      int sig=GetSignal();
      if(sig== 1&&CountBuys() >=Max_Buy)  sig=0;
      if(sig==-1&&CountSells()>=Max_Sell) sig=0;
      if(sig==1)  {ulong tk=OpenOrder(ORDER_TYPE_BUY, CommentOrder+" [Legacy]",Auto_SL_Ratio);if(tk>0){g_lastSignalBarTime=bOpen;g_lastLegacyTicket=tk;}}
      if(sig==-1) {ulong tk=OpenOrder(ORDER_TYPE_SELL,CommentOrder+" [Legacy]",Auto_SL_Ratio);if(tk>0){g_lastSignalBarTime=bOpen;g_lastLegacyTicket=tk;}}
   }
   DrawDashboard();
}

void OnTimer() { DrawHistoryLabels(); }
