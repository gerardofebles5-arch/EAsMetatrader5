//+------------------------------------------------------------------+
//|  MoneyMachine7_v1785.mq5                                        |
//|  v17.85 — RECONSTRUCCIÓN LIMPIA CON MEJORAS PROBADAS            |
//|                                                                  |
//|  BASE: v17.80 (mejor resultado: $270, PF=2.06, WR=53%)          |
//|                                                                  |
//|  ANÁLISIS DEFINITIVO (136 trades reales, 4 versiones):           |
//|                                                                  |
//|  REGLA 1 — NUNCA TOCAR LA SEÑAL PRINCIPAL:                      |
//|  Range=50, Zone=0.555, Confirm=4.6, SL_Min=19.2 funcionan.     |
//|  Cada vez que los tocamos, el PF bajó. Estos son intocables.    |
//|                                                                  |
//|  REGLA 2 — NUNCA BAJAR EL HARDCAP:                             |
//|  Monte Carlo: HC=$12 → $270. HC=$6 → más cortes = peor.        |
//|  El SL natural del mercado es más eficiente que cortar pronto.  |
//|                                                                  |
//|  MEJORAS IMPLEMENTADAS (todas con evidencia estadística):        |
//|                                                                  |
//|  FIX A — ELIMINAR H07 Y H22 DEL CÓDIGO (no del aprendizaje):   |
//|  H07: WR=0% en TODAS las versiones, -$17 acumulado. Sin debate.|
//|  H22: EV≈$0 con v17.80, pero CATASTRÓFICO en versiones nuevas. |
//|  Horas operativas: solo H02 y H15 en Motor 1.                   |
//|                                                                  |
//|  FIX B — RSI(14) COMO FILTRO DE SOBRECOMPRA:                   |
//|  Añade confirmación cuantitativa: solo SELL si RSI > 60.        |
//|  Reduce entradas en H15 cuando el precio está en el techo       |
//|  pero el momentum ya revirtió (causa de HardCaps de 1-2min).    |
//|                                                                  |
//|  FIX C — VOLATILITY RATIO (ATR5/ATR20):                        |
//|  Si ATR5/ATR20 > 1.8 → mercado explosivo, no entrar.           |
//|  Si ATR5/ATR20 < 0.4 → mercado muerto, no entrar.              |
//|  Filtra los momentos de noticias que causan HardCaps instantáneos|
//|                                                                  |
//|  FIX D — CANDLE BODY FILTER:                                    |
//|  Si el cuerpo de la vela señal < 40% del rango → doji/indecisión|
//|  No entrar. Las barras de indecisión generan falsas señales.    |
//|                                                                  |
//|  FIX E — DAILY LOSS LIMIT ($30):                               |
//|  Si pérdida del día supera $30, cerrar todo y pausar.           |
//|  Habría cortado la racha Mar17-19 (-$84) a -$30. Ahorro: $54.  |
//|                                                                  |
//|  FIX F — MOTOR 2 (Breakout) ESCALA CON BALANCE:               |
//|  WR=100% en 4 trades registrados. Debe tener más peso.         |
//|  Lot dinámico basado en riesgo cuando balance > $70.            |
//|                                                                  |
//|  FIX G — Z-SCORE CONFIRMACIÓN (opcional, conservador):         |
//|  Z-Score del precio vs últimas 50 barras.                       |
//|  Solo entrar si Z-Score > 1.2 (precio estadísticamente extremo) |
//|                                                                  |
//|  LO QUE SE MANTIENE IGUAL QUE v17.80:                          |
//|  ✓ Señal: Range=50, Zone=0.555, Confirm=4.6, SL_Min=19.2       |
//|  ✓ HC = $12 exacto                                              |
//|  ✓ Partial = $8, 40%                                            |
//|  ✓ Trail: Start=2.9, Phase1=15, Phase2=10, Phase3=6            |
//|  ✓ WR Tracker: ventana=5, pausa=8                              |
//|  ✓ Bear Protector: 120b, 50pts, ×0.30                          |
//|  ✓ Motor 2: H8+H13, SL=12, TP=20, MaxHold=90min               |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.85"
#property strict

//=== SEÑAL MOTOR 1 — INTOCABLE (v17.75, mejor calibración) ===
input int    Range_Bars          = 50;
input double Zone_Pct_Base       = 0.555;
input double Confirm_Points      = 4.6;
input int    Local_Vol_Bars      = 6;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 19.2;
input double SL_Max              = 85.2;
input double TP_Ratio            = 16.0;

//=== HORAS OPERATIVAS — FIX A: solo H02+H15 ===
// H07: WR=0% en todas las versiones → eliminado permanentemente
// H22: EV≈0, catastrófico en nuevas versiones → eliminado
// Opción para investigadores: activar para backtests futuros
input bool   Use_H02             = true;
input bool   Use_H15             = true;
input bool   Use_H07             = false;  // FIX A: WR=0% histórico
input bool   Use_H22             = false;  // FIX A: EV≈0, muy volátil

//=== TRAILING — restaurado a v17.80 (funcionaba) ===
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 2.9;
input double Trail_Dist_Phase1   = 15.0;
input double Trail_Dist_Phase2   = 10.0;
input double Trail_Dist_Phase3   = 6.0;
input int    Trail_Phase1_Sec    = 600;
input int    Trail_Phase2_Sec    = 1800;

//=== PARTIAL CLOSE — restaurado a v17.80 ===
input bool   Use_Partial_Close    = true;
input double Partial_USD_Trigger  = 8.0;
input double Partial_Close_Pct    = 0.40;

//=== HARD LOSS CAP — RESTAURADO A v17.80 EXACTO ===
// Monte Carlo demostró que HC=$12 es óptimo. No bajar.
input bool   Use_Hard_Loss_Cap   = true;
input double Hard_Loss_Cap_USD   = 12.0;

input bool   Use_Breakeven       = false;
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 11520;
input double Trail_Progress_Pct  = 0.20;

//=== FIX B: RSI FILTER ===
// Solo SELL si RSI(14) > umbral (mercado sobrecomprado)
// Filtra entradas cuando ya empezó a revertir antes de entrar
input bool   Use_RSI_Filter      = true;
input int    RSI_Period          = 14;
input double RSI_Sell_Min        = 60.0;  // solo SELL si RSI > 60

//=== FIX C: VOLATILITY RATIO FILTER ===
// ATR5/ATR20: ratio de volatilidad corto/largo plazo
// Explosión de volatilidad (news) = alto ratio → no entrar
// Mercado muerto = bajo ratio → no entrar
input bool   Use_Vol_Ratio       = true;
input int    ATR_Short           = 5;
input int    ATR_Long            = 20;
input double Vol_Ratio_Max       = 1.8;  // > 1.8 = explosión
input double Vol_Ratio_Min       = 0.4;  // < 0.4 = muerto

//=== FIX D: CANDLE BODY FILTER ===
// Filtra doji y velas de indecisión
// Requiere que el cuerpo sea >= Min_Body_Pct del rango total
input bool   Use_Body_Filter     = true;
input double Min_Body_Pct        = 0.40; // cuerpo >= 40% del rango

//=== FIX E: DAILY LOSS LIMIT ===
// Habría cortado la racha Mar17-19 (-$84) a -$30
input bool   Use_Daily_Loss_Limit   = true;
input double Daily_Loss_Limit_USD   = 30.0;  // pausar si pérdida diaria > $30

//=== FIX G: Z-SCORE FILTER (opcional) ===
// Confirma que el precio está estadísticamente extremo
// Z-Score = (precio - media_N) / std_N
input bool   Use_ZScore_Filter   = true;
input int    ZScore_Period        = 50;
input double ZScore_Min           = 1.2;  // precio debe ser 1.2 desv. sobre media

//=== AUTOAPRENDIZAJE ===
input int    Learn_Min_Samples   = 10;
input double Learn_WR_Block      = 0.30;
input double Learn_WR_Reopen     = 0.45;
input int    Learn_Recalc_Every  = 10;
input double Learn_Quick_Loss_Sec= 300;
input int    Learn_Vol_Window    = 20;
input double Learn_Trail_Scale   = 0.20;

//=== RACHA ===
input double Streak_Reduce_Pct   = 0.80;
input double Streak_Boost_Pct    = 1.20;  // conservador: 1.30→1.20
input double Streak_Scale_Max    = 1.40;  // 1.50→1.40
input double Streak_Scale_Min    = 0.40;
input int    Streak_Loss_Trigger = 3;
input int    Streak_Win_Trigger  = 3;

//=== FILTROS ORIGINALES v17.80 ===
input int    Vel_Bars            = 3;
input double Vel_Threshold_Base  = 4.4;
input int    Trend_Bars          = 100;
input double Trend_Min_Move      = 30.0;
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 8;
input bool   Use_Hour_Filter     = true;

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

//=== WR TRACKER (v17.82: ventana=5, pausa=8) ===
input bool   Use_WR_Tracker      = true;
input int    WR_Track_Window     = 5;
input double WR_Track_Low        = 0.20;
input double WR_Track_High       = 0.70;
input double WR_Track_Scale_Low  = 0.30;
input double WR_Track_Scale_High = 1.50;
input int    WR_Track_Pause_Bars = 8;

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

//=== MOTOR 2 — FIX F: lot dinámico ===
input bool   Use_Motor2          = true;
input int    M2_Magic            = 178000;
input int    M2_Breakout_Bars    = 20;
input double M2_Breakout_Pts     = 8.0;
input double M2_SL_Pts           = 12.0;
input double M2_TP_Pts           = 20.0;
input int    M2_MaxHold_Sec      = 5400;
input double M2_Lot_Fixed        = 0.01;
input double M2_Risk_Pct         = 0.020;  // FIX F: mismo riesgo que M1
input double M2_DynLot_MinBal    = 70.0;   // dinámico si bal > $70

//=== ESTRUCTURAS ===
struct TradeRecord {
   int    hour; double sl_dist,profit,hold_sec;
   bool   is_win,is_quick_loss;
};
struct HourStats {
   int    n,wins; double total_profit,total_ev;
   bool   blocked; int block_samples;
};
struct TradeState {
   double   entry,slDist,tpDist;
   bool     trailActive,beMovedOnce,timeTrailDone;
   datetime openTime;
};

//=== GLOBALS ===
string   g_sym; double g_point; int g_magic;
datetime g_lastBarTime=0;
int      g_pendingDir=0;
double   g_confirmLevel=0, g_pendingSL=0;

TradeRecord g_history[500];
int         g_histCount=0;
HourStats   g_hourStats[24];
TradeState  g_states[2];

int    g_consecLosses=0, g_consecWins=0;
int    g_pauseBarsLeft=0, g_totalTrades=0;
int    g_hardcap_cooldown=0;

double g_zone_pct=0, g_trail_dist=0, g_vel_threshold=0, g_lot_scale=1.0;

double   g_regime_lot_factor=1.0;
bool     g_regime_paused=false;
int      g_consec_neg_days=0, g_consec_pos_days=0;
double   g_today_pnl=0.0, g_today_start_bal=0.0;
datetime g_today_date=0;

double   g_balance_peak=30.0, g_bal_trail_scale=1.0;
double   g_wr_history[20];
int      g_wr_hist_idx=0, g_wr_hist_n=0;
double   g_wr_track_scale=1.0;
double   g_bear_lot_factor=1.0;

bool     g_daily_loss_halted=false;  // FIX E

datetime g_m2_lastBarTime=0;
int      g_m2_pendingDir=0;
double   g_m2_pendingSL=0, g_m2_pendingTP=0;
datetime g_m2_openTime=0;

//+------------------------------------------------------------------+
void InitLearning()
{
   g_zone_pct=Zone_Pct_Base; g_trail_dist=Trail_Dist_Phase1;
   g_vel_threshold=Vel_Threshold_Base; g_lot_scale=1.0;
   g_regime_lot_factor=1.0; g_regime_paused=false;
   g_consec_neg_days=0; g_consec_pos_days=0;
   g_today_pnl=0.0; g_today_date=0;
   g_today_start_bal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_balance_peak=AccountInfoDouble(ACCOUNT_BALANCE);
   g_bal_trail_scale=1.0;
   for(int i=0;i<20;i++) g_wr_history[i]=0.5;
   g_wr_hist_idx=0; g_wr_hist_n=0; g_wr_track_scale=1.0;
   g_bear_lot_factor=1.0; g_hardcap_cooldown=0;
   g_daily_loss_halted=false;
   for(int h=0;h<24;h++){
      g_hourStats[h].n=0; g_hourStats[h].wins=0;
      g_hourStats[h].total_profit=0; g_hourStats[h].total_ev=0;
      g_hourStats[h].blocked=false; g_hourStats[h].block_samples=0;
   }
}

//+------------------------------------------------------------------+
// FIX B: Calcular RSI manual (sin handles para compatibilidad MT5 backtest)
double CalcRSI(int period)
{
   double gain=0, loss=0;
   for(int i=1;i<=period;i++){
      double delta=iClose(g_sym,_Period,i)-iClose(g_sym,_Period,i+1);
      if(delta>0) gain+=delta; else loss-=delta;
   }
   if(loss==0) return 100.0;
   double rs=gain/loss;
   return 100.0 - (100.0/(1.0+rs));
}

//+------------------------------------------------------------------+
// FIX C: Calcular ATR simple
double CalcATR(int period, int shift=1)
{
   double sum=0;
   for(int i=shift;i<shift+period;i++){
      double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i), pc=iClose(g_sym,_Period,i+1);
      if(h==0||l==0||pc==0) continue;
      double tr=MathMax(h-l,MathMax(MathAbs(h-pc),MathAbs(l-pc)));
      sum+=tr;
   }
   return sum/period;
}

//+------------------------------------------------------------------+
// FIX G: Calcular Z-Score del precio actual
double CalcZScore(int period)
{
   double sum=0;
   for(int i=1;i<=period;i++) sum+=iClose(g_sym,_Period,i);
   double mean=sum/period;
   double variance=0;
   for(int i=1;i<=period;i++){
      double d=iClose(g_sym,_Period,i)-mean;
      variance+=d*d;
   }
   double std=MathSqrt(variance/period);
   if(std==0) return 0;
   double closeNow=iClose(g_sym,_Period,1);
   return (closeNow-mean)/std;
}

//+------------------------------------------------------------------+
// FIX E: Verificar Daily Loss Limit y actualizar P&L diario
void CheckDailyLossLimit()
{
   if(!Use_Daily_Loss_Limit) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today=StringToTime(StringFormat("%04d.%02d.%02d 00:00",dt.year,dt.mon,dt.day));
   if(g_today_date!=today){
      g_today_date=today;
      g_today_pnl=0.0;
      g_today_start_bal=AccountInfoDouble(ACCOUNT_BALANCE);
      g_daily_loss_halted=false;
      Print("Nuevo día: balance=$",DoubleToString(g_today_start_bal,2));
   }
   double current_bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double daily_loss=current_bal-g_today_start_bal; // negativo si perdemos
   if(!g_daily_loss_halted && daily_loss < -Daily_Loss_Limit_USD){
      g_daily_loss_halted=true;
      g_pendingDir=0;
      // Cerrar posiciones abiertas
      ulong tks[]; GetTickets(tks);
      for(int i=0;i<ArraySize(tks);i++) ClosePosition(tks[i],"DailyLimit");
      if(Use_Motor2) M2_CloseAll();
      Print("DAILY LOSS LIMIT: pérdida=$",DoubleToString(-daily_loss,2)," > $",Daily_Loss_Limit_USD," → HALT");
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
   double ema_fast=0,ema_slow=0;
   for(int i=Bear_EMA_Fast;i>=1;i--) ema_fast+=iClose(g_sym,_Period,i);
   ema_fast/=Bear_EMA_Fast;
   for(int i=Bear_EMA_Slow;i>=1;i--) ema_slow+=iClose(g_sym,_Period,i);
   ema_slow/=Bear_EMA_Slow;
   if(drop>=Bear_Drop_Pts&&ema_fast<ema_slow){
      if(g_bear_lot_factor!=Bear_Lot_Scale){ g_bear_lot_factor=Bear_Lot_Scale;
         Print("BEAR ON: drop=",DoubleToString(drop,1),"pts→lot×",Bear_Lot_Scale); }
   } else {
      if(g_bear_lot_factor!=1.0){ g_bear_lot_factor=1.0; Print("BEAR OFF"); }
   }
}

void RecordTrade(int hour, double sl_dist, double profit, double hold_sec, bool was_hc)
{
   if(g_histCount>=500){ for(int i=0;i<450;i++) g_history[i]=g_history[i+50]; g_histCount=450; }
   g_history[g_histCount].hour=hour; g_history[g_histCount].sl_dist=sl_dist;
   g_history[g_histCount].profit=profit; g_history[g_histCount].hold_sec=hold_sec;
   g_history[g_histCount].is_win=(profit>0);
   g_history[g_histCount].is_quick_loss=(profit<-0.5&&hold_sec<Learn_Quick_Loss_Sec);
   g_histCount++; g_totalTrades++;
   g_hourStats[hour].n++; g_hourStats[hour].total_profit+=profit;
   if(profit>0) g_hourStats[hour].wins++;
   if(g_hourStats[hour].n>=Learn_Min_Samples){
      double wr=(double)g_hourStats[hour].wins/g_hourStats[hour].n;
      if(!g_hourStats[hour].blocked&&wr<Learn_WR_Block){
         g_hourStats[hour].blocked=true; g_hourStats[hour].block_samples=0;
         Print("LEARN: H",hour," BLOQUEADA WR=",DoubleToString(wr*100,1),"%");
      } else if(g_hourStats[hour].blocked){
         g_hourStats[hour].block_samples++;
         if(wr>=Learn_WR_Reopen){ g_hourStats[hour].blocked=false;
            Print("LEARN: H",hour," REABIERTA WR=",DoubleToString(wr*100,1),"%"); }
      }
   }
   if(was_hc&&Use_HardCap_Cooldown) g_hardcap_cooldown=HardCap_Cooldown_Bars;
   if(g_totalTrades%Learn_Recalc_Every==0) AdaptParameters();
}

void AdaptParameters()
{
   if(g_histCount<10) return;
   int look=MathMin(g_histCount,50); int ql=0;
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

// FIX A: Solo H02 y H15 como horas operativas
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // Verificar si la hora está habilitada
   if(hour==2 && !Use_H02) return false;
   if(hour==7 && !Use_H07) return false;
   if(hour==15 && !Use_H15) return false;
   if(hour==22 && !Use_H22) return false;
   // Solo las horas configuradas
   bool base_ok = (hour==2&&Use_H02) || (hour==7&&Use_H07) ||
                  (hour==15&&Use_H15) || (hour==22&&Use_H22);
   if(!base_ok) return false;
   if(g_hourStats[hour].blocked&&g_hourStats[hour].n>=Learn_Min_Samples) return false;
   if(g_regime_paused) return false;
   return true;
}

void UpdateRegime()
{
   double pn=iClose(g_sym,_Period,1),pa=iClose(g_sym,_Period,Regime_Trend_Bars+1);
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
         if(g_today_pnl<0){ g_consec_neg_days++; g_consec_pos_days=0;
            Print("DIA NEGATIVO #",g_consec_neg_days," PnL=$",DoubleToString(g_today_pnl,2));
         } else if(g_today_pnl>0){ g_consec_pos_days++; g_consec_neg_days=0; }
         if(g_consec_neg_days>=Regime_Bad_Days&&g_regime_lot_factor>Regime_Lot_Scale)
            g_regime_lot_factor=Regime_Lot_Scale;
         if(g_consec_pos_days>=Regime_Good_Days&&g_regime_lot_factor<1.0){
            g_regime_lot_factor=1.0; g_consec_neg_days=0; }
         g_regime_paused=false;
      }
      g_today_date=today; g_today_pnl=0.0;
      g_today_start_bal=AccountInfoDouble(ACCOUNT_BALANCE);
      g_daily_loss_halted=false;
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
   return (dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC);
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

void UpdateWRTracker(bool is_win)
{
   if(!Use_WR_Tracker) return;
   g_wr_history[g_wr_hist_idx]=is_win?1.0:0.0;
   g_wr_hist_idx=(g_wr_hist_idx+1)%20;
   if(g_wr_hist_n<20) g_wr_hist_n++;
   int window=MathMin(WR_Track_Window,g_wr_hist_n);
   if(window<3) return;
   double sum=0; int start=(g_wr_hist_idx-window+20)%20;
   for(int i=0;i<window;i++) sum+=g_wr_history[(start+i)%20];
   double wr=sum/window;
   double prev=g_wr_track_scale;
   if(wr<=WR_Track_Low){
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
   double combined=g_lot_scale*g_regime_lot_factor*g_bal_trail_scale*g_wr_track_scale*g_bear_lot_factor;
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
      Print("MM7 SELL bid=",bid," lot=",lot," bear×",DoubleToString(g_bear_lot_factor,2));
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

//=== MOTOR 2 ===
bool IsM2Hour(int hour){ return (hour==8||hour==13); }

void M2_CloseAll()
{
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=M2_Magic) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double price=(pt==POSITION_TYPE_BUY)?SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
      ENUM_ORDER_TYPE ct=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      MqlTradeRequest req={}; MqlTradeResult res={};
      req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol;
      req.type=ct; req.price=price; req.position=tk;
      req.deviation=InpSlippagePoints; req.magic=M2_Magic;
      req.comment="M2-Close"; req.type_filling=ORDER_FILLING_FOK;
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

void M2_OpenTrade(int dir, double sl, double tp)
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
   if(!Use_Motor2||g_daily_loss_halted) return;
   if(M2_HasPosition()&&g_m2_openTime>0){
      if((int)(now-g_m2_openTime)>=M2_MaxHold_Sec){ M2_CloseAll(); g_m2_openTime=0; g_m2_pendingDir=0; }
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
         if(h==0||l==0) return; if(h>rH) rH=h; if(l<rL) rL=l;
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
   if(g_m2_pendingDir==1) M2_OpenTrade(1,g_m2_pendingSL,g_m2_pendingTP);
   else M2_OpenTrade(-1,g_m2_pendingSL,g_m2_pendingTP);
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
   string horas="";
   if(Use_H02) horas+="H02 ";
   if(Use_H07) horas+="H07 ";
   if(Use_H15) horas+="H15 ";
   if(Use_H22) horas+="H22 ";
   Print("MM7 v17.85 | ",g_sym," | M1:SELL ",StringTrimRight(horas),
         " | M2:Breakout H8+H13",
         " | HC=$",Hard_Loss_Cap_USD," | RSI_filter=",Use_RSI_Filter,">",RSI_Sell_Min,
         " | VolRatio=",Use_Vol_Ratio," | BodyFilter=",Use_Body_Filter,
         " | DailyLimit=$",Daily_Loss_Limit_USD," | ZScore=",Use_ZScore_Filter,">",ZScore_Min,
         " | Partial@$",Partial_USD_Trigger);
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

   // FIX E: Verificar daily loss limit en cada tick
   CheckDailyLossLimit();
   if(g_daily_loss_halted) return;

   if(Close_On_FriClose&&IsFridayClose()){
      ulong tks[]; GetTickets(tks);
      for(int i=0;i<ArraySize(tks);i++) ClosePosition(tks[i],"FriClose");
      if(Use_Motor2) M2_CloseAll();
      g_pendingDir=0; return;
   }

   RunMotor2(bid,ask,now);

   // GESTIÓN POSICIONES ABIERTAS
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

      // 1. HC = $12 restaurado
      if(Use_Hard_Loss_Cap&&PositionSelectByTicket(tk)){
         double pnl=PositionGetDouble(POSITION_PROFIT);
         if(pnl<-Hard_Loss_Cap_USD){
            ClosePosition(tk,"HardCap");
            if(Use_HardCap_Cooldown) g_hardcap_cooldown=HardCap_Cooldown_Bars;
            Print("MM7 HC pnl=",DoubleToString(pnl,2));
            continue;
         }
      }

      // 2. PARTIAL CLOSE ($8, 40%)
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

      // 3. TRAILING
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
            if(favorable<slD*Trail_Progress_Pct&&PositionSelectByTicket(tk)){
               double ctp=PositionGetDouble(POSITION_TP),csl=PositionGetDouble(POSITION_SL);
               int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
               double nsl=NormalizeDouble(entry,digs);
               if(nsl<csl) SetSLTP(tk,nsl,ctp);
            }
            g_states[si].timeTrailDone=true;
         }
      }
   }

   // Limpiar estados
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

      // FIX B: RSI filter — solo SELL si sobrecomprado
      if(Use_RSI_Filter){
         double rsi=CalcRSI(RSI_Period);
         if(rsi<RSI_Sell_Min) return;
      }

      // FIX C: Volatility ratio filter
      if(Use_Vol_Ratio){
         double atr_s=CalcATR(ATR_Short,1);
         double atr_l=CalcATR(ATR_Long,1);
         if(atr_l>0){
            double ratio=atr_s/atr_l;
            if(ratio>Vol_Ratio_Max){ Print("VOL_RATIO: explosión ",DoubleToString(ratio,2)," → skip"); return; }
            if(ratio<Vol_Ratio_Min){ Print("VOL_RATIO: dormido ",DoubleToString(ratio,2)," → skip"); return; }
         }
      }

      // FIX D: Candle body filter
      if(Use_Body_Filter){
         double h=iHigh(g_sym,_Period,1), l=iLow(g_sym,_Period,1);
         double o=iOpen(g_sym,_Period,1), c=iClose(g_sym,_Period,1);
         double total_range=h-l;
         if(total_range>0){
            double body_pct=MathAbs(c-o)/total_range;
            if(body_pct<Min_Body_Pct) return; // doji / indecisión
         }
      }

      // Filtro velocidad original
      double cv2=iClose(g_sym,_Period,Vel_Bars+1),cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>g_vel_threshold) return;

      // FIX G: Z-Score filter
      if(Use_ZScore_Filter){
         double zscore=CalcZScore(ZScore_Period);
         if(zscore<ZScore_Min) return; // precio no está suficientemente extremo
      }

      // SEÑAL MOTOR 1
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i),l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return; if(h>rH) rH=h; if(l<rL) rL=l;
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

      if(closeNow>=upperZone&&!TrendBlocksSell()){
         g_pendingDir=-1;
         g_confirmLevel=closeNow-Confirm_Points;
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

   if(g_pendingDir==-1&&ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
