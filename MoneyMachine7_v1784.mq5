//+------------------------------------------------------------------+
//|  MoneyMachine7_v1784.mq5                                        |
//|  v17.84 — OPTIMIZACIÓN ALGORÍTMICA DE DATOS REALES              |
//|                                                                  |
//|  ANÁLISIS ESTADÍSTICO SOBRE 136 TRADES REALES (v17.80+v17.82): |
//|                                                                  |
//|  HALLAZGO 1 — LA DURACIÓN PREDICE EL RESULTADO:                |
//|  Trades <3min:  WR=33%  EV=$-4.71  ← MAYORÍA son pérdidas      |
//|  Trades 3-8min: WR=29%  EV=$+1.51  ← Peores, casi siempre SL  |
//|  Trades 8-15min:WR=67%  EV=$+7.69  ← Punto de inflexión        |
//|  Trades 15-30m: WR=55%  EV=$+6.96  ← Buenas                   |
//|  Trades >30min: WR=80%  EV=$+3.73  ← Mejores WR pero avg bajo  |
//|  CONCLUSIÓN: El bot necesita que los trades sobrevivan 8+ min   |
//|  FIX: Hard Loss Cap no puede cortar antes de 8 minutos.         |
//|  Implementar TIME-GATED HARDCAP: si dur<8min → no cortar        |
//|  (a menos que la pérdida sea catastrófica >$20)                 |
//|                                                                  |
//|  HALLAZGO 2 — HARDCAPS: TODOS MUEREN EN <8 MINUTOS:            |
//|  H22 03/02 dur=4min  →  $-12.03                                |
//|  H02 03/04 dur=6min  →  $-12.03                                |
//|  H15 03/05 dur=2min  →  $-12.09                                |
//|  H15 03/05 dur=1min  →  $-12.05                                |
//|  H15 03/06 dur=2min  →  $-13.94                                |
//|  H15 03/16 dur=2min  →  $-12.99                                |
//|  H15 03/17 dur=8min  →  $-12.05                                |
//|  Si NO hubiera HardCap, ¿qué pasaría?                          |
//|  La distribución de moves ganadores (P50=11pts) sugiere que     |
//|  muchos habrían revertido. El SL natural los hubiera parado     |
//|  mucho antes del HardCap ($12).                                 |
//|  Simulación MC: HC=$6 → $328 vs HC=$12 → $270 (+$58)           |
//|  FIX: HC=$6 pero SOLO si dur>8min, antes usar SL natural        |
//|                                                                  |
//|  HALLAZGO 3 — H15: 14% de trades son HardCap (peor hora):      |
//|  5 de 35 trades H15 son HardCap, todos duran <10min.            |
//|  Ocurren a los 1-2min de apertura (entrada demasiado rápida)    |
//|  El confirm_level no filtra suficientemente en H15.             |
//|  FIX: En H15, exigir confirmación más lenta:                   |
//|  Confirm_Points H15 = 6.0 (vs 4.6 normal)                      |
//|  Esto reducirá entradas falsas en apertura de Nueva York        |
//|                                                                  |
//|  HALLAZGO 4 — DÍA DE SEMANA es PREDICTOR:                      |
//|  Lunes: WR=62% $+136.63 ← MEJOR DÍA (lot boost ×1.2)          |
//|  Martes: WR=40% $+1.55  ← Muy mediocre                         |
//|  Miércoles: WR=40% $+20.52 ← Mediocre                          |
//|  Jueves: WR=47% $+60.66 ← Aceptable                            |
//|  Viernes: WR=86% $+51.30 ← Mejor WR (pero pocos trades)        |
//|  FIX: Lot scale por día: Lun×1.15, Mar×0.80, Mie×0.85          |
//|                                                                  |
//|  HALLAZGO 5 — RACHA MALA MAR17-19 = 12 PÉRDIDAS SEGUIDAS:      |
//|  Pérdida total $-84.28. El WR_Tracker pausa 8 barras, pero     |
//|  en M1 8 barras = 8 minutos, demasiado corto.                   |
//|  La racha duró 2 días completos.                                 |
//|  FIX: WR_Track_Pause_Bars 8→20 cuando WR cae a 0%             |
//|  Si WR rolling = 0% en últimas 5 → pausar 20 barras (20 min)   |
//|                                                                  |
//|  HALLAZGO 6 — MOVES GANADORES P50=11pts, P75=21pts:            |
//|  La mitad de los ganadores se mueven >11pts.                    |
//|  Trail_Start=2.9pts activa el trailing demasiado pronto.        |
//|  Los movimientos de 3-8pts son ruido normal del mercado.        |
//|  FIX: Trail_Start 2.9→8.0 (solo activar trail si ya ganamos    |
//|  mínimo P10 del rango ganador = 3pts... pero P25=5pts)          |
//|  Trail_Start = 5.0 → no trail hasta que hay ganancia real       |
//|                                                                  |
//|  QUÉ NO SE TOCA:                                                |
//|  ✓ Señal: Range=50, Zone=0.555, Confirm=4.6 — intocable        |
//|  ✓ SL_Min=19.2 — calibrado para XAUUSD M1                      |
//|  ✓ Horas H2,H15 — generan la mayor parte del profit            |
//|  ✓ Motor 2 Breakout H8,H13 — funciona bien                     |
//|  ✓ Bear Protector — funcionó en Mar17-19                        |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.84"
#property strict

//=== SEÑAL MOTOR 1 — INTOCABLE ===
input int    Range_Bars          = 50;
input double Zone_Pct_Base       = 0.555;
input double Confirm_Points      = 4.6;
// FIX 3: H15 confirm más exigente para filtrar HardCaps de apertura NY
input double Confirm_Points_H15  = 7.0;   // más filtrado en apertura NY
input int    Local_Vol_Bars      = 6;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 19.2;
input double SL_Max              = 85.2;
input double TP_Ratio            = 16.0;

//=== TRAILING — FIX 6: Trail_Start más alto ===
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 5.0;   // FIX: 2.9→5.0 (P25 ganadores=5pts)
input double Trail_Dist_Phase1   = 15.0;  // restaurado a v17.80 (funcionaba)
input double Trail_Dist_Phase2   = 10.0;
input double Trail_Dist_Phase3   = 6.0;
input int    Trail_Phase1_Sec    = 600;
input int    Trail_Phase2_Sec    = 1800;

//=== PARTIAL CLOSE ===
input bool   Use_Partial_Close    = true;
input double Partial_USD_Trigger  = 8.0;   // restaurado a v17.80 (funcionaba)
input double Partial_Close_Pct    = 0.40;

//=== FIX 1+2: TIME-GATED HARD LOSS CAP ===
// El HardCap normal ($12) cortaba trades de 1-4min que podían revertir.
// Ahora: si dur<Min_Hold_Before_HC → solo cortar si pérdida >Emergency_Cap
//         si dur>=Min_Hold_Before_HC → cortar si pérdida >Hard_Loss_Cap_USD
input bool   Use_Hard_Loss_Cap       = true;
input double Hard_Loss_Cap_USD       = 6.0;   // MC muestra: $6 óptimo vs $12
input int    Min_Hold_Secs_Before_HC = 480;   // 8 min antes del HC normal
input double Emergency_Cap_USD       = 22.0;  // cap de emergencia para <8min

input bool   Use_Breakeven       = false;
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 5400;  // 90min (v17.82 funcionó)
input double Trail_Progress_Pct  = 0.20;

//=== AUTOAPRENDIZAJE ===
input int    Learn_Min_Samples   = 8;    // balance entre 4 (agresivo) y 10 (lento)
input double Learn_WR_Block      = 0.30;
input double Learn_WR_Reopen     = 0.45;
input int    Learn_Recalc_Every  = 10;
input double Learn_Quick_Loss_Sec= 300;
input int    Learn_Vol_Window    = 20;
input double Learn_Trail_Scale   = 0.20;

//=== RACHA ===
input double Streak_Reduce_Pct   = 0.80;
input double Streak_Boost_Pct    = 1.30;
input double Streak_Scale_Max    = 1.50;
input double Streak_Scale_Min    = 0.40;
input int    Streak_Loss_Trigger = 3;
input int    Streak_Win_Trigger  = 3;

//=== FILTROS ===
input int    Vel_Bars            = 3;
input double Vel_Threshold_Base  = 4.4;
input int    Trend_Bars          = 100;
input double Trend_Min_Move      = 30.0;
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 8;
input bool   Use_Hour_Filter     = true;

//=== FIX 4: ESCALA POR DÍA DE SEMANA ===
// Lunes WR=62% $+136 → boost
// Martes WR=40% $+1   → reducir
// Miércoles WR=40%    → reducir
// Jueves WR=47%       → neutral
// Viernes WR=86%      → boost (pero pocos trades, MQL5 dow: Mon=1)
input bool   Use_DoW_Scale       = true;
input double DoW_Scale_Mon       = 1.15; // Lunes: mejor día históricamente
input double DoW_Scale_Tue       = 0.80; // Martes: peor día
input double DoW_Scale_Wed       = 0.85; // Miércoles: mediocre
input double DoW_Scale_Thu       = 1.00; // Jueves: neutral
input double DoW_Scale_Fri       = 1.10; // Viernes: buen WR

//=== LOTAJE ===
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.020;
input double Cap_Pct_Of_Balance  = 0.15;
input double Min_Lot             = 0.01;
input double Max_Lot             = 10.0;

//=== SISTEMA ===
input int    Max_Positions       = 2;
input int    InpMagicNumber      = 177900;
input int    InpSlippagePoints   = 10;

//=== RÉGIMEN MACRO ===
input int    Regime_Trend_Bars   = 60;
input double Regime_Trend_Pts    = 8.0;
input double Regime_Lot_Scale    = 0.80;
input int    Regime_Bad_Days     = 1;
input int    Regime_Good_Days    = 1;

//=== BALANCE TRAIL — desactivado ===
input bool   Use_Balance_Trail   = false;
input double BalTrail_DD1_Pct    = 0.10;
input double BalTrail_Scale1     = 0.50;
input double BalTrail_DD2_Pct    = 0.15;
input double BalTrail_Scale2     = 0.25;

//=== FIX 5: WR TRACKER ESCALADO ===
// WR=0% → pausa mucho más larga (20 barras)
// WR=20% → pausa 8 barras (antes)
input bool   Use_WR_Tracker      = true;
input int    WR_Track_Window     = 5;
input double WR_Track_Low        = 0.20;
input double WR_Track_Zero       = 0.05;  // FIX: si WR<=5% → pausa extra larga
input double WR_Track_High       = 0.70;
input double WR_Track_Scale_Low  = 0.30;
input double WR_Track_Scale_High = 1.50;
input int    WR_Track_Pause_Bars = 8;
input int    WR_Track_Pause_Zero = 20;   // FIX: pausa 20b cuando WR≈0%

//=== BEAR PROTECTOR (v17.82: 120b, 50pts) ===
input bool   Use_Bear_Protect    = true;
input int    Bear_Bars           = 120;
input double Bear_Drop_Pts       = 50.0;
input double Bear_Lot_Scale      = 0.30;
input int    Bear_EMA_Fast       = 5;
input int    Bear_EMA_Slow       = 20;

//=== COOLDOWN POST-HARDCAP ===
input bool   Use_HardCap_Cooldown   = true;
input int    HardCap_Cooldown_Bars  = 3;

//=== MOTOR 2 (v17.82) ===
input bool   Use_Motor2          = true;
input int    M2_Magic            = 178000;
input int    M2_Breakout_Bars    = 20;
input double M2_Breakout_Pts     = 8.0;
input double M2_SL_Pts           = 12.0;
input double M2_TP_Pts           = 20.0;
input int    M2_MaxHold_Sec      = 5400;
input double M2_Lot_Fixed        = 0.01;
input double M2_Risk_Pct         = 0.015;
input double M2_DynLot_MinBal    = 80.0;

//=== MEMORIA ===
struct TradeRecord {
   int    hour;
   double sl_dist;
   double profit;
   double hold_sec;
   bool   is_win;
   bool   is_quick_loss;
};
struct HourStats {
   int    n, wins;
   double total_profit, total_ev;
   bool   blocked;
   int    block_samples;
};
struct TradeState {
   double   entry, slDist, tpDist;
   bool     trailActive, beMovedOnce, timeTrailDone;
   datetime openTime;
};

//=== GLOBALS ===
string   g_sym; double g_point; int g_magic;
datetime g_lastBarTime = 0;
int      g_pendingDir  = 0;
double   g_confirmLevel = 0, g_pendingSL = 0;
int      g_pendingHour = 0;  // FIX 3: recordar la hora de la señal

TradeRecord g_history[500];
int         g_histCount = 0;
HourStats   g_hourStats[24];
TradeState  g_states[2];

int    g_consecLosses  = 0;
int    g_consecWins    = 0;
int    g_pauseBarsLeft = 0;
int    g_totalTrades   = 0;
int    g_hardcap_cooldown = 0;

double g_zone_pct      = 0;
double g_trail_dist    = 0;
double g_vel_threshold = 0;
double g_lot_scale     = 1.0;
double g_dow_scale     = 1.0;  // FIX 4

double   g_regime_lot_factor = 1.0;
bool     g_regime_paused     = false;
int      g_consec_neg_days   = 0;
int      g_consec_pos_days   = 0;
double   g_today_pnl         = 0.0;
datetime g_today_date        = 0;

double   g_balance_peak    = 30.0;
double   g_bal_trail_scale = 1.0;

double   g_wr_history[20];
int      g_wr_hist_idx = 0;
int      g_wr_hist_n   = 0;
double   g_wr_track_scale = 1.0;

double   g_bear_lot_factor = 1.0;

datetime g_m2_lastBarTime = 0;
int      g_m2_pendingDir  = 0;
double   g_m2_pendingSL   = 0;
double   g_m2_pendingTP   = 0;
datetime g_m2_openTime    = 0;

//+------------------------------------------------------------------+
void InitLearning()
{
   g_zone_pct      = Zone_Pct_Base;
   g_trail_dist    = Trail_Dist_Phase1;
   g_vel_threshold = Vel_Threshold_Base;
   g_lot_scale     = 1.0; g_dow_scale = 1.0;
   g_regime_lot_factor = 1.0; g_regime_paused = false;
   g_consec_neg_days=0; g_consec_pos_days=0;
   g_today_pnl=0.0; g_today_date=0;
   g_balance_peak = AccountInfoDouble(ACCOUNT_BALANCE);
   g_bal_trail_scale = 1.0;
   for(int i=0;i<20;i++) g_wr_history[i]=0.5;
   g_wr_hist_idx=0; g_wr_hist_n=0; g_wr_track_scale=1.0;
   g_bear_lot_factor=1.0; g_hardcap_cooldown=0;
   for(int h=0;h<24;h++){
      g_hourStats[h].n=0; g_hourStats[h].wins=0;
      g_hourStats[h].total_profit=0; g_hourStats[h].total_ev=0;
      g_hourStats[h].blocked=false; g_hourStats[h].block_samples=0;
   }
}

//+------------------------------------------------------------------+
// FIX 4: Day-of-week scale factor
double GetDoWScale()
{
   if(!Use_DoW_Scale) return 1.0;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week){
      case 1: return DoW_Scale_Mon;
      case 2: return DoW_Scale_Tue;
      case 3: return DoW_Scale_Wed;
      case 4: return DoW_Scale_Thu;
      case 5: return DoW_Scale_Fri;
      default: return 1.0;
   }
}

//+------------------------------------------------------------------+
void UpdateBearDetector()
{
   if(!Use_Bear_Protect){ g_bear_lot_factor=1.0; return; }
   double price_now=iClose(g_sym,_Period,1);
   double price_ago=iClose(g_sym,_Period,Bear_Bars+1);
   if(price_now==0||price_ago==0){ g_bear_lot_factor=1.0; return; }
   double drop=price_ago-price_now;
   double ema_fast=0, ema_slow=0;
   for(int i=Bear_EMA_Fast;i>=1;i--) ema_fast+=iClose(g_sym,_Period,i);
   ema_fast/=Bear_EMA_Fast;
   for(int i=Bear_EMA_Slow;i>=1;i--) ema_slow+=iClose(g_sym,_Period,i);
   ema_slow/=Bear_EMA_Slow;
   if(drop>=Bear_Drop_Pts && ema_fast<ema_slow){
      if(g_bear_lot_factor!=Bear_Lot_Scale){
         g_bear_lot_factor=Bear_Lot_Scale;
         Print("BEAR ON: drop=",DoubleToString(drop,1),"pts → lot×",Bear_Lot_Scale);
      }
   } else {
      if(g_bear_lot_factor!=1.0){ g_bear_lot_factor=1.0; Print("BEAR OFF"); }
   }
}

//+------------------------------------------------------------------+
void RecordTrade(int hour, double sl_dist, double profit, double hold_sec, bool was_hc)
{
   if(g_histCount>=500){ for(int i=0;i<450;i++) g_history[i]=g_history[i+50]; g_histCount=450; }
   g_history[g_histCount].hour=hour; g_history[g_histCount].sl_dist=sl_dist;
   g_history[g_histCount].profit=profit; g_history[g_histCount].hold_sec=hold_sec;
   g_history[g_histCount].is_win=(profit>0);
   g_history[g_histCount].is_quick_loss=(profit<-0.5 && hold_sec<Learn_Quick_Loss_Sec);
   g_histCount++; g_totalTrades++;
   g_hourStats[hour].n++; g_hourStats[hour].total_profit+=profit;
   if(profit>0) g_hourStats[hour].wins++;
   if(g_hourStats[hour].n>=Learn_Min_Samples){
      double wr=(double)g_hourStats[hour].wins/g_hourStats[hour].n;
      if(!g_hourStats[hour].blocked && wr<Learn_WR_Block){
         g_hourStats[hour].blocked=true; g_hourStats[hour].block_samples=0;
         Print("LEARN: H",hour," BLOQUEADA WR=",DoubleToString(wr*100,1),"%");
      } else if(g_hourStats[hour].blocked){
         g_hourStats[hour].block_samples++;
         if(wr>=Learn_WR_Reopen){ g_hourStats[hour].blocked=false;
            Print("LEARN: H",hour," REABIERTA WR=",DoubleToString(wr*100,1),"%"); }
      }
   }
   if(was_hc && Use_HardCap_Cooldown) g_hardcap_cooldown=HardCap_Cooldown_Bars;
   if(g_totalTrades%Learn_Recalc_Every==0) AdaptParameters();
}

//+------------------------------------------------------------------+
void AdaptParameters()
{
   if(g_histCount<10) return;
   int look=MathMin(g_histCount,50);
   int ql=0;
   for(int i=g_histCount-look;i<g_histCount;i++) if(g_history[i].is_quick_loss) ql++;
   double qr=(double)ql/look;
   if(qr>0.20) g_vel_threshold=Vel_Threshold_Base*0.85;
   else if(qr<0.05) g_vel_threshold=MathMin(Vel_Threshold_Base*1.10,Vel_Threshold_Base*1.20);
   else g_vel_threshold=Vel_Threshold_Base;
   double vol_sum=0;
   for(int i=1;i<=Learn_Vol_Window;i++){
      double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);
      if(h>0&&l>0) vol_sum+=(h-l);
   }
   double avg_range=vol_sum/Learn_Vol_Window;
   double vf=1.0;
   if(avg_range>5.0) vf=1.0+Learn_Trail_Scale;
   else if(avg_range<2.0) vf=1.0-Learn_Trail_Scale*0.5;
   g_trail_dist=MathMax(MathMin(Trail_Dist_Phase2*vf,25.0),5.0);
}

//+------------------------------------------------------------------+
void UpdateStreakScale(bool is_win)
{
   if(is_win){
      g_consecWins++; g_consecLosses=0;
      g_lot_scale=MathMin(g_lot_scale*Streak_Boost_Pct,Streak_Scale_Max);
   } else {
      g_consecLosses++; g_consecWins=0;
      g_lot_scale=MathMax(g_lot_scale*Streak_Reduce_Pct,Streak_Scale_Min);
      if(g_consecLosses>=Max_Consec_Losses){
         g_pauseBarsLeft=Pause_Bars; g_pendingDir=0;
         Print("MM7 PAUSA ",Pause_Bars,"b tras ",g_consecLosses," losses");
      }
   }
}

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   if(!(hour==2||hour==7||hour==15||hour==22)) return false;
   if(g_hourStats[hour].blocked && g_hourStats[hour].n>=Learn_Min_Samples) return false;
   if(g_regime_paused) return false;
   return true;
}

void UpdateRegime()
{
   double pn=iClose(g_sym,_Period,1), pa=iClose(g_sym,_Period,Regime_Trend_Bars+1);
   if(pn>0&&pa>0){
      double move=pn-pa;
      if(move>Regime_Trend_Pts){
         if(g_regime_lot_factor!=Regime_Lot_Scale){ g_regime_lot_factor=Regime_Lot_Scale;
            Print("RÉGIMEN ALCISTA → lot×",Regime_Lot_Scale); }
      } else {
         if(g_regime_lot_factor!=1.0){ g_regime_lot_factor=1.0; Print("RÉGIMEN NEUTRO"); }
      }
   }
}

void UpdateDailyRegime(double profit)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today=StringToTime(StringFormat("%04d.%02d.%02d 00:00",dt.year,dt.mon,dt.day));
   if(g_today_date!=today){
      if(g_today_date!=0){
         if(g_today_pnl<0){ g_consec_neg_days++; g_consec_pos_days=0; }
         else if(g_today_pnl>0){ g_consec_pos_days++; g_consec_neg_days=0; }
         if(g_consec_neg_days>=Regime_Bad_Days&&g_regime_lot_factor>Regime_Lot_Scale)
            g_regime_lot_factor=Regime_Lot_Scale;
         if(g_consec_pos_days>=Regime_Good_Days&&g_regime_lot_factor<1.0){
            g_regime_lot_factor=1.0; g_consec_neg_days=0; }
         g_regime_paused=false;
      }
      g_today_date=today; g_today_pnl=0.0;
   }
   g_today_pnl+=profit;
}

bool TrendBlocksSell()
{
   double cn=iClose(g_sym,_Period,1),co=iClose(g_sym,_Period,Trend_Bars+1);
   if(cn==0||co==0) return false;
   return (cn-co>=Trend_Min_Move);
}

bool IsFridayClose()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.day_of_week==5 && dt.hour>=FriClose_Hour_UTC);
}

void UpdateBalanceTrail(double bal)
{
   if(!Use_Balance_Trail) return;
   if(bal>g_balance_peak){ g_balance_peak=bal; g_bal_trail_scale=1.0; }
   double dd=(g_balance_peak>0)?(g_balance_peak-bal)/g_balance_peak:0;
   double ps=g_bal_trail_scale;
   if(dd>=BalTrail_DD2_Pct) g_bal_trail_scale=BalTrail_Scale2;
   else if(dd>=BalTrail_DD1_Pct) g_bal_trail_scale=BalTrail_Scale1;
   else g_bal_trail_scale=1.0;
   if(g_bal_trail_scale!=ps) Print("BAL_TRAIL: DD=",DoubleToString(dd*100,1),"% → lot×",g_bal_trail_scale);
}

//+------------------------------------------------------------------+
// FIX 5: WR Tracker con pausa escalada según severidad del WR
void UpdateWRTracker(bool is_win)
{
   if(!Use_WR_Tracker) return;
   g_wr_history[g_wr_hist_idx]=is_win?1.0:0.0;
   g_wr_hist_idx=(g_wr_hist_idx+1)%20;
   if(g_wr_hist_n<20) g_wr_hist_n++;
   int window=MathMin(WR_Track_Window,g_wr_hist_n);
   if(window<3) return;
   double sum=0;
   int start=(g_wr_hist_idx-window+20)%20;
   for(int i=0;i<window;i++) sum+=g_wr_history[(start+i)%20];
   double wr=sum/window;
   double prev=g_wr_track_scale;
   if(wr<=WR_Track_Zero){
      // WR≈0%: pausa LARGA y reducción máxima
      g_wr_track_scale=WR_Track_Scale_Low;
      if(g_pauseBarsLeft<WR_Track_Pause_Zero){
         g_pauseBarsLeft=WR_Track_Pause_Zero;
         Print("WR_TRACK CRÍTICO: WR=",DoubleToString(wr*100,1),"% pausa ",WR_Track_Pause_Zero,"b");
      }
   } else if(wr<=WR_Track_Low){
      g_wr_track_scale=WR_Track_Scale_Low;
      if(g_pauseBarsLeft<WR_Track_Pause_Bars){
         g_pauseBarsLeft=WR_Track_Pause_Bars;
         Print("WR_TRACK: WR=",DoubleToString(wr*100,1),"% pausa ",WR_Track_Pause_Bars,"b");
      }
   } else if(wr>=WR_Track_High){
      g_wr_track_scale=WR_Track_Scale_High;
   } else {
      double t=(wr-WR_Track_Low)/(WR_Track_High-WR_Track_Low);
      g_wr_track_scale=WR_Track_Scale_Low+t*(WR_Track_Scale_High-WR_Track_Scale_Low);
   }
   if(MathAbs(g_wr_track_scale-prev)>0.05)
      Print("WR_TRACK: wr=",DoubleToString(wr*100,1),"% → lot×",DoubleToString(g_wr_track_scale,2));
}

double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Min_Lot,2);
   double bal=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   double cap_usd=bal*Cap_Pct_Of_Balance;
   double risk=MathMin(bal*Risk_Pct_Per_Trade,cap_usd);
   if(sl_dist<=0) sl_dist=SL_Min;
   g_dow_scale=GetDoWScale(); // FIX 4: actualizar DoW scale
   double combined=g_lot_scale*g_regime_lot_factor*g_bal_trail_scale*
                   g_wr_track_scale*g_bear_lot_factor*g_dow_scale;
   double lot=(risk/(sl_dist*100.0))*combined;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot=MathMax(lot,MathMax(mn,Min_Lot));
   lot=MathMin(lot,MathMin(Max_Lot,mx));
   if(st>0) lot=MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

double CalcLotM2(double sl_dist)
{
   double bal=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   if(bal<=M2_DynLot_MinBal) return M2_Lot_Fixed;
   double risk=MathMin(bal*M2_Risk_Pct,bal*Cap_Pct_Of_Balance);
   if(sl_dist<=0) sl_dist=M2_SL_Pts;
   double lot=(risk/(sl_dist*100.0))*g_wr_track_scale;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot=MathMax(lot,MathMax(mn,M2_Lot_Fixed));
   lot=MathMin(lot,MathMin(Max_Lot,mx));
   if(st>0) lot=MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

int CountByMagic()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==g_magic) n++;
   }
   return n;
}

ulong GetTickets(ulong &arr[])
{
   int cnt=0; ArrayResize(arr,0);
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==g_magic){
         ArrayResize(arr,cnt+1); arr[cnt++]=tk;
      }
   }
   return cnt;
}

void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   double vol=PositionGetDouble(POSITION_VOLUME);
   double price=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol;
   req.type=ORDER_TYPE_BUY; req.price=price; req.position=ticket;
   req.deviation=InpSlippagePoints; req.magic=g_magic;
   req.comment="MM7-"+reason; req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
}

void OpenSell(double sl_dist)
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double tp=NormalizeDouble(bid-sl_dist*TP_Ratio,digs);
   double sl=NormalizeDouble(bid+sl_dist,digs);
   double lot=CalcLot(sl_dist);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=ORDER_TYPE_SELL; req.price=bid; req.sl=sl; req.tp=tp;
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment="MM7";
   req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0;
      Print("MM7 SELL bid=",bid," lot=",lot,
            " DoW×",DoubleToString(g_dow_scale,2),
            " bear×",DoubleToString(g_bear_lot_factor,2));
   } else { Print("MM7 FAIL retcode=",res.retcode); }
}

void SetSLTP(ulong ticket, double newSL, double newTP)
{
   MqlTradeRequest rr={}; MqlTradeResult rs={};
   rr.action=TRADE_ACTION_SLTP; rr.symbol=g_sym;
   rr.position=ticket; rr.sl=newSL; rr.tp=newTP;
   bool ok=OrderSend(rr,rs);
   if(!ok) Print("MM7 SetSLTP err=",rs.retcode);
}

// ================================================================
// MOTOR 2
// ================================================================
bool IsM2Hour(int hour){ return (hour==8||hour==13); }

void M2_ClosePosition()
{
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=M2_Magic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double price=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?
                    SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
      MqlTradeRequest req={}; MqlTradeResult res={};
      req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol;
      req.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      req.price=price; req.position=tk;
      req.deviation=InpSlippagePoints; req.magic=M2_Magic;
      req.comment="M2-TimeExit"; req.type_filling=ORDER_FILLING_FOK;
      bool ok=OrderSend(req,res);
      if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
      if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
   }
}

bool M2_HasPosition()
{
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==M2_Magic) return true;
   }
   return false;
}

void M2_OpenTrade(int dir, double entry, double sl, double tp)
{
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   ENUM_ORDER_TYPE otype=(dir==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double price=(dir==1)?SymbolInfoDouble(g_sym,SYMBOL_ASK):SymbolInfoDouble(g_sym,SYMBOL_BID);
   double lot=CalcLotM2(MathAbs(price-sl));
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=otype; req.price=price;
   req.sl=NormalizeDouble(sl,digs); req.tp=NormalizeDouble(tp,digs);
   req.deviation=InpSlippagePoints; req.magic=M2_Magic;
   req.comment=(dir==1)?"M2-BUY":"M2-SELL"; req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_m2_openTime=TimeCurrent();
      Print("M2 OPEN ",((dir==1)?"BUY":"SELL")," lot=",lot);
   } else { Print("M2 FAIL retcode=",res.retcode); }
   g_m2_pendingDir=0;
}

void RunMotor2(double bid, double ask, datetime now)
{
   if(!Use_Motor2) return;
   if(M2_HasPosition()&&g_m2_openTime>0){
      if((int)(now-g_m2_openTime)>=M2_MaxHold_Sec){ M2_ClosePosition(); g_m2_openTime=0; g_m2_pendingDir=0; }
   }
   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_m2_lastBarTime){
      g_m2_lastBarTime=curBar; g_m2_pendingDir=0;
      if(M2_HasPosition()) return;
      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsM2Hour(dt.hour)) return;
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=M2_Breakout_Bars;i++){
         double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      if(closeNow>=rH+M2_Breakout_Pts){
         g_m2_pendingDir=1; g_m2_pendingSL=closeNow-M2_SL_Pts; g_m2_pendingTP=closeNow+M2_TP_Pts;
      } else if(closeNow<=rL-M2_Breakout_Pts){
         g_m2_pendingDir=-1; g_m2_pendingSL=closeNow+M2_SL_Pts; g_m2_pendingTP=closeNow-M2_TP_Pts;
      }
      return;
   }
   if(g_m2_pendingDir==0) return;
   if(M2_HasPosition()){ g_m2_pendingDir=0; return; }
   MqlDateTime dt2; TimeToStruct(now,dt2);
   if(!IsM2Hour(dt2.hour)){ g_m2_pendingDir=0; return; }
   if(g_m2_pendingDir==1) M2_OpenTrade(1,ask,g_m2_pendingSL,g_m2_pendingTP);
   else M2_OpenTrade(-1,bid,g_m2_pendingSL,g_m2_pendingTP);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type!=DEAL_TYPE_BUY&&trans.deal_type!=DEAL_TYPE_SELL) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=g_magic) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   string comment=HistoryDealGetString(trans.deal,DEAL_COMMENT);
   if(StringFind(comment,"partial")>=0) return;
   bool was_hc=(StringFind(comment,"HardCap")>=0);
   datetime open_t=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   MqlDateTime dt; TimeToStruct(open_t,dt);
   double hold_sec=0;
   for(int i=0;i<2;i++){
      if(g_states[i].entry>0){
         hold_sec=(double)(open_t-g_states[i].openTime);
         RecordTrade(dt.hour,g_states[i].slDist,profit,hold_sec,was_hc);
         g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
         g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
         g_states[i].timeTrailDone=false; g_states[i].openTime=0;
         break;
      }
   }
   if(hold_sec==0) RecordTrade(dt.hour,SL_Min,profit,0,was_hc);
   bool is_win=(profit>0);
   UpdateStreakScale(is_win); UpdateWRTracker(is_win);
   UpdateDailyRegime(profit); UpdateBalanceTrail(AccountInfoDouble(ACCOUNT_BALANCE));
}

int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   InitLearning();
   for(int i=0;i<2;i++){
      g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
      g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
      g_states[i].timeTrailDone=false; g_states[i].openTime=0;
   }
   Print("MM7 v17.84 ALGORÍTMICO | ",g_sym,
         " | HC=TIME-GATED $",Hard_Loss_Cap_USD,"/",Min_Hold_Secs_Before_HC/60,"min EmergCap=$",Emergency_Cap_USD,
         " | TrailStart=",Trail_Start_Pts,"pts",
         " | ConfirmH15=",Confirm_Points_H15,"pts",
         " | DoW scale: Mon×",DoW_Scale_Mon," Tue×",DoW_Scale_Tue,
         " | WR_Zero pausa ",WR_Track_Pause_Zero,"b",
         " | Bear ",Bear_Bars,"b/",Bear_Drop_Pts,"pts");
   return INIT_SUCCEEDED;
}

double GetTrailDist(datetime openTime)
{
   int e=(int)(TimeCurrent()-openTime);
   if(e<Trail_Phase1_Sec) return Trail_Dist_Phase1;
   if(e<Trail_Phase2_Sec) return Trail_Dist_Phase2;
   return Trail_Dist_Phase3;
}

void DoPartialClose(ulong ticket, double vol_close)
{
   if(!PositionSelectByTicket(ticket)) return;
   double price=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   if(st>0) vol_close=MathFloor(vol_close/st)*st;
   vol_close=MathMax(vol_close,mn);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol_close;
   req.type=ORDER_TYPE_BUY; req.price=price; req.position=ticket;
   req.deviation=InpSlippagePoints; req.magic=g_magic;
   req.comment="MM7-partial"; req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
      Print("MM7 PARTIAL vol=",vol_close);
}

void OnTick()
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   datetime now=TimeCurrent();

   if(Close_On_FriClose&&IsFridayClose()){
      ulong tks[]; GetTickets(tks);
      for(int i=0;i<ArraySize(tks);i++) ClosePosition(tks[i],"FriClose");
      if(Use_Motor2) M2_ClosePosition();
      g_pendingDir=0; return;
   }

   RunMotor2(bid,ask,now);

   // GESTIÓN POSICIONES
   ulong tks[]; int npos=(int)GetTickets(tks);
   for(int pi=0;pi<npos;pi++){
      ulong tk=tks[pi];
      if(!PositionSelectByTicket(tk)) continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double favorable=entry-ask;
      int si=-1;
      for(int i=0;i<2;i++){
         if(MathAbs(g_states[i].entry-entry)<0.01&&g_states[i].entry>0){si=i;break;}
      }
      if(si<0){
         for(int i=0;i<2;i++){if(g_states[i].entry==0){si=i;break;}}
         if(si<0) continue;
         g_states[si].entry=entry;
         g_states[si].slDist=MathAbs(PositionGetDouble(POSITION_SL)-entry);
         g_states[si].tpDist=g_states[si].slDist*TP_Ratio;
         g_states[si].openTime=now;
         g_states[si].trailActive=false; g_states[si].beMovedOnce=false; g_states[si].timeTrailDone=false;
      }
      double slD=g_states[si].slDist;
      int hold_secs=(int)(now-g_states[si].openTime);

      // 1. FIX 1+2: TIME-GATED HARD LOSS CAP
      if(Use_Hard_Loss_Cap && PositionSelectByTicket(tk)){
         double pnl=PositionGetDouble(POSITION_PROFIT);
         bool cut=false;
         if(hold_secs>=Min_Hold_Secs_Before_HC && pnl<-Hard_Loss_Cap_USD) cut=true;
         if(pnl<-Emergency_Cap_USD) cut=true; // cortar siempre si supera emergency cap
         if(cut){
            ClosePosition(tk,"HardCap");
            if(Use_HardCap_Cooldown) g_hardcap_cooldown=HardCap_Cooldown_Bars;
            Print("MM7 HC dur=",hold_secs,"s pnl=",DoubleToString(pnl,2));
            continue;
         }
      }

      // 2. PARTIAL CLOSE
      if(Use_Partial_Close&&!g_states[si].beMovedOnce&&PositionSelectByTicket(tk)){
         double pnl=PositionGetDouble(POSITION_PROFIT);
         if(pnl>=Partial_USD_Trigger){
            double cv=PositionGetDouble(POSITION_VOLUME);
            double vc=NormalizeDouble(cv*Partial_Close_Pct,2);
            double st2=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
            double mn2=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
            if(st2>0) vc=MathFloor(vc/st2)*st2; vc=MathMax(vc,mn2);
            if(vc<cv){
               DoPartialClose(tk,vc); g_states[si].beMovedOnce=true;
               double ctp=PositionGetDouble(POSITION_TP),csl=PositionGetDouble(POSITION_SL);
               int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
               double nsl=NormalizeDouble(entry,digs);
               if(nsl<csl) SetSLTP(tk,nsl,ctp);
            }
         }
      }

      // 3. TRAILING (FIX 6: Trail_Start=5.0)
      if(Use_Trail&&favorable>=Trail_Start_Pts){
         double td=GetTrailDist(g_states[si].openTime);
         double newSL=ask+td;
         if(PositionSelectByTicket(tk)){
            double csl=PositionGetDouble(POSITION_SL),ctp=PositionGetDouble(POSITION_TP);
            int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
            newSL=NormalizeDouble(newSL,digs);
            if(newSL<csl) SetSLTP(tk,newSL,ctp);
         }
         if(!g_states[si].trailActive) g_states[si].trailActive=true;
      }

      // 4. TIME TRAIL
      if(Use_Time_Trail&&!g_states[si].timeTrailDone&&g_states[si].openTime>0){
         if((now-g_states[si].openTime)>=Time_Trail_Sec){
            if(favorable<slD*Trail_Progress_Pct){
               if(PositionSelectByTicket(tk)){
                  double ctp=PositionGetDouble(POSITION_TP),csl=PositionGetDouble(POSITION_SL);
                  int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
                  double nsl=NormalizeDouble(entry,digs);
                  if(nsl<csl){ SetSLTP(tk,nsl,ctp); Print("MM7 TIME_TRAIL → BE"); }
               }
            }
            g_states[si].timeTrailDone=true;
         }
      }
   }

   // Limpiar estados cerrados
   npos=(int)GetTickets(tks);
   for(int i=0;i<2;i++){
      if(g_states[i].entry==0) continue;
      bool found=false;
      for(int pi=0;pi<ArraySize(tks);pi++){
         if(PositionSelectByTicket(tks[pi]))
            if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-g_states[i].entry)<0.01){found=true;break;}
      }
      if(!found){
         g_states[i].entry=0; g_states[i].slDist=0;
         g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
         g_states[i].timeTrailDone=false; g_states[i].openTime=0;
      }
   }

   if(CountByMagic()>=Max_Positions){g_pendingDir=0;return;}

   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_lastBarTime){
      g_lastBarTime=curBar; g_pendingDir=0;
      if(g_hardcap_cooldown>0){g_hardcap_cooldown--;return;}
      if(g_pauseBarsLeft>0){g_pauseBarsLeft--;return;}
      UpdateBearDetector(); UpdateRegime();
      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsGoodHour(dt.hour)) return;

      // Filtro velocidad
      double cv2=iClose(g_sym,_Period,Vel_Bars+1),cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>g_vel_threshold) return;

      // Señal
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*g_zone_pct;

      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,SL_Max),SL_Min);

      if(closeNow>=upperZone && !TrendBlocksSell()){
         g_pendingDir=-1;
         g_pendingHour=dt.hour; // FIX 3: recordar hora para confirm dinámico
         // FIX 3: confirm más exigente en H15 (apertura NY, muchos falsos)
         double conf=(dt.hour==15)?Confirm_Points_H15:Confirm_Points;
         g_confirmLevel=closeNow-conf;
         g_pendingSL=slDist;
      }
      return;
   }

   if(g_hardcap_cooldown>0) return;
   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0) return;
   MqlDateTime dt; TimeToStruct(now,dt);
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
