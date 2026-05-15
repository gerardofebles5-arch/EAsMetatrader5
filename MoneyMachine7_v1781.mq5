//+------------------------------------------------------------------+
//|  MoneyMachine7_v1781.mq5                                        |
//|  v17.81 — TRIPLE MOTOR: Reversión + Breakout + BUY Tendencia   |
//|                                                                  |
//|  APRENDIZAJE DE v17.80:                                         |
//|  ✓ Factor de Beneficio 2.06 — buena base                        |
//|  ✓ Motor 2 (breakout) complementa al Motor 1                    |
//|  ✗ Solo SELL en Motor 1 — pierde oportunidades alcistas masivas |
//|  ✗ Mar17-19: precio cayó -400pts → ambos motores perdieron      |
//|  ✗ TP_Ratio=16 muy alto → muy pocos trades llegan al TP         |
//|  ✗ SL_Min=19.2 muy amplio → pérdidas grandes cuando falla       |
//|  ✗ Motor 2 Lot fijo 0.01 → no escala con el balance            |
//|  ✗ Max_Consec_Losses=3 pausa 8b → demasiado conservador         |
//|  ✗ Partial close muy tardío ($8) → dejar escapar ganancias      |
//|                                                                  |
//|  MEJORAS v17.81:                                                 |
//|  ✓ MOTOR 3: BUY en tendencia alcista (precio en mínimo rango)   |
//|    Detecta cuando precio está en parte baja del rango → BUY     |
//|    Horas: 2, 7, 15, 22 (mismas que Motor 1) | Magic: 178100     |
//|  ✓ TP_Ratio reducido 16→8 → más trades llegan al TP             |
//|  ✓ SL_Min reducido 19.2→14 → pérdidas más controladas           |
//|  ✓ Motor 2 usa lot dinámico (Risk_Pct_Per_Trade) no fijo        |
//|  ✓ Partial_USD_Trigger 8→5 → asegurar ganancias antes           |
//|  ✓ Pause_Bars 8→6, Max_Consec_Losses 3→4 → menos interferencia  |
//|  ✓ ATR FILTER: filtro de volatilidad más preciso que vel simple  |
//|  ✓ Motor 3 bloqueado automáticamente cuando WR<25% (aprendizaje)|
//|  ✓ Trail más ajustado: Phase1 15→12, Phase2 10→7 → retener más  |
//|  ✓ Hard Loss Cap 12→10 → cortar pérdidas antes                  |
//|  ✓ M2 SL 12→10 / TP 20→18 → mejor ratio y control              |
//|                                                                  |
//|  MOTORES:                                                        |
//|  Motor 1: SELL en top rango 50b | H2,7,15,22 | Magic:177900    |
//|  Motor 2: BUY/SELL Breakout apertura H8,13 | Magic:178000       |
//|  Motor 3: BUY en bottom rango 50b | H2,7,15,22 | Magic:178100   |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.81"
#property strict

//=== SEÑAL MOTOR 1 (v17.75 calibrado — no tocar zona superior) ===
input int    Range_Bars          = 50;
input double Zone_Pct_Base       = 0.555;
input double Confirm_Points      = 4.6;
input int    Local_Vol_Bars      = 6;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 14.0;   // FIX: 19.2→14 pérdidas más controladas
input double SL_Max              = 85.2;
input double TP_Ratio            = 8.0;    // FIX: 16→8 más trades llegan al TP

//=== MOTOR 3: BUY EN TENDENCIA (nuevo — espejo del Motor 1) ===
// Motor 1 vende cuando precio está arriba del rango (reversión bajista)
// Motor 3 compra cuando precio está abajo del rango (reversión alcista)
// Juntos cubren AMBAS direcciones del mercado de rango
input bool   Use_Motor3          = true;
input int    M3_Magic            = 178100;
input double M3_Zone_Pct_Base    = 0.555; // simétrico al Motor 1
input double M3_Confirm_Points   = 4.6;
input double M3_TP_Ratio         = 8.0;
input double M3_Risk_Pct         = 0.015; // más conservador que M1
input double M3_SL_Min           = 14.0;
input double M3_SL_Max           = 85.2;
input double M3_WR_Block         = 0.25;  // bloquear si WR<25%
input int    M3_Min_Samples      = 10;

//=== TRAILING ESCALONADO (ajustado para retener más ganancia) ===
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 2.9;
input double Trail_Dist_Phase1   = 12.0;  // FIX: 15→12 trail más ajustado
input double Trail_Dist_Phase2   = 7.0;   // FIX: 10→7
input double Trail_Dist_Phase3   = 5.0;   // FIX: 6→5
input int    Trail_Phase1_Sec    = 600;
input int    Trail_Phase2_Sec    = 1800;

//=== PARTIAL CLOSE EN $ FLOTANTES ===
input bool   Use_Partial_Close    = true;
input double Partial_USD_Trigger  = 5.0;  // FIX: 8→5 asegurar antes
input double Partial_Close_Pct    = 0.40;

//=== HARD LOSS CAP ===
input bool   Use_Hard_Loss_Cap   = true;
input double Hard_Loss_Cap_USD   = 10.0;  // FIX: 12→10 cortar antes

input bool   Use_Breakeven       = false;
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 11520;
input double Trail_Progress_Pct  = 0.20;

//=== ATR FILTER (nuevo — reemplaza filtro velocidad simple) ===
// Evita entrar en barras con volatilidad extrema (noticias, gaps)
// ATR alto = mercado explosivo → esperar
// ATR bajo = mercado tranquilo → bueno para reversión
input bool   Use_ATR_Filter      = true;
input int    ATR_Period          = 14;
input double ATR_Max_Mult        = 2.5;   // si barra actual > 2.5×ATR14 → no entrar
input double ATR_Min_Mult        = 0.3;   // si barra < 0.3×ATR14 → no entrar (mercado muerto)

//=== AUTOAPRENDIZAJE (conservador) ===
input int    Learn_Min_Samples   = 10;
input double Learn_WR_Block      = 0.30;
input double Learn_WR_Reopen     = 0.45;
input int    Learn_Recalc_Every  = 10;
input double Learn_Quick_Loss_Sec= 300;
input int    Learn_Vol_Window    = 20;
input double Learn_Trail_Scale   = 0.20;

//=== RACHA ===
input double Streak_Reduce_Pct   = 0.80;
input double Streak_Boost_Pct    = 1.25;  // FIX: 1.30→1.25 más conservador
input double Streak_Scale_Max    = 1.40;  // FIX: 1.50→1.40
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
input int    Max_Consec_Losses   = 4;    // FIX: 3→4 menos interferencia
input int    Pause_Bars          = 6;    // FIX: 8→6
input bool   Use_Hour_Filter     = true;

//=== LOTAJE ===
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.020;
input double Cap_Pct_Of_Balance  = 0.15;
input double Min_Lot             = 0.01;
input double Max_Lot             = 10.0;

//=== SISTEMA ===
input int    Max_Positions       = 3;    // FIX: 2→3 para acomodar Motor 3
input int    InpMagicNumber      = 177900;
input int    InpSlippagePoints   = 10;

//=== RÉGIMEN ===
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

//=== WR TRACKER ===
input bool   Use_WR_Tracker      = true;
input int    WR_Track_Window     = 8;
input double WR_Track_Low        = 0.20;
input double WR_Track_High       = 0.70;
input double WR_Track_Scale_Low  = 0.30;
input double WR_Track_Scale_High = 1.50;
input int    WR_Track_Pause_Bars = 5;

//=== MOTOR 2: BREAKOUT ===
input bool   Use_Motor2          = true;
input int    M2_Magic            = 178000;
input int    M2_Breakout_Bars    = 20;
input double M2_Breakout_Pts     = 8.0;
input double M2_SL_Pts           = 10.0;   // FIX: 12→10
input double M2_TP_Pts           = 18.0;   // FIX: 20→18
input int    M2_MaxHold_Sec      = 5400;
input double M2_Risk_Pct         = 0.015;  // FIX: lot dinámico (antes fijo 0.01)

//=== ESTRUCTURA DE MEMORIA ===
struct TradeRecord {
   int    hour;
   double sl_dist;
   double profit;
   double hold_sec;
   bool   is_win;
   bool   is_quick_loss;
};

struct HourStats {
   int    n;
   int    wins;
   double total_profit;
   double total_ev;
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

TradeRecord g_history[500];
int         g_histCount = 0;

HourStats   g_hourStats[24];

TradeState  g_states[3]; // ampliado a 3 para Motor 3

int    g_consecLosses  = 0;
int    g_consecWins    = 0;
int    g_pauseBarsLeft = 0;
int    g_totalTrades   = 0;

// Parámetros adaptativos
double g_zone_pct      = 0;
double g_trail_dist    = 0;
double g_vel_threshold = 0;
double g_lot_scale     = 1.0;

// RÉGIMEN MACRO
double   g_regime_lot_factor = 1.0;
bool     g_regime_paused     = false;
int      g_consec_neg_days   = 0;
int      g_consec_pos_days   = 0;
double   g_today_pnl         = 0.0;
datetime g_today_date        = 0;

// BALANCE TRAILING
double   g_balance_peak      = 30.0;
double   g_bal_trail_scale   = 1.0;

// WR TRACKER
double   g_wr_history[20];
int      g_wr_hist_idx = 0;
int      g_wr_hist_n   = 0;
double   g_wr_track_scale= 1.0;

// MOTOR 2
datetime g_m2_lastBarTime   = 0;
int      g_m2_pendingDir    = 0;
double   g_m2_pendingEntry  = 0;
double   g_m2_pendingSL     = 0;
double   g_m2_pendingTP     = 0;
datetime g_m2_openTime      = 0;
double   g_m2_openEntry     = 0;

// MOTOR 3: BUY en reversión alcista
datetime g_m3_lastBarTime   = 0;
int      g_m3_pendingDir    = 0;
double   g_m3_confirmLevel  = 0;
double   g_m3_pendingSL     = 0;
int      g_m3_pauseBarsLeft = 0;
int      g_m3_consecLosses  = 0;
int      g_m3_consecWins    = 0;
double   g_m3_lot_scale     = 1.0;
// M3 estadísticas por hora
int    g_m3_hour_n[24];
int    g_m3_hour_wins[24];
bool   g_m3_hour_blocked[24];

//+------------------------------------------------------------------+
void InitLearning()
{
   g_zone_pct      = Zone_Pct_Base;
   g_trail_dist    = Trail_Dist_Phase1;
   g_vel_threshold = Vel_Threshold_Base;
   g_lot_scale     = 1.0;
   g_regime_lot_factor = 1.0;
   g_regime_paused     = false;
   g_consec_neg_days   = 0;
   g_consec_pos_days   = 0;
   g_today_pnl         = 0.0;
   g_today_date        = 0;
   g_balance_peak    = AccountInfoDouble(ACCOUNT_BALANCE);
   g_bal_trail_scale = 1.0;
   for(int i=0;i<20;i++) g_wr_history[i]=0.5;
   g_wr_hist_idx    = 0;
   g_wr_hist_n      = 0;
   g_wr_track_scale = 1.0;
   for(int h=0; h<24; h++){
      g_hourStats[h].n=0; g_hourStats[h].wins=0;
      g_hourStats[h].total_profit=0; g_hourStats[h].total_ev=0;
      g_hourStats[h].blocked=false; g_hourStats[h].block_samples=0;
      // Motor 3 init
      g_m3_hour_n[h]=0; g_m3_hour_wins[h]=0; g_m3_hour_blocked[h]=false;
   }
   g_m3_pauseBarsLeft=0; g_m3_consecLosses=0; g_m3_consecWins=0; g_m3_lot_scale=1.0;
}

//+------------------------------------------------------------------+
// ATR Filter — evita entrar en barras de volatilidad extrema
// Retorna true si la barra actual está dentro del rango ATR aceptable
bool ATR_OK()
{
   if(!Use_ATR_Filter) return true;
   // Calcular ATR manual con últimas ATR_Period barras
   double atr_sum = 0;
   for(int i=2; i<=ATR_Period+1; i++){
      double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i), pc=iClose(g_sym,_Period,i+1);
      if(h==0||l==0||pc==0) return true;
      double tr = MathMax(h-l, MathMax(MathAbs(h-pc), MathAbs(l-pc)));
      atr_sum += tr;
   }
   double atr14 = atr_sum / ATR_Period;
   if(atr14 <= 0) return true;
   // Barra más reciente
   double cur_h=iHigh(g_sym,_Period,1), cur_l=iLow(g_sym,_Period,1);
   double cur_range = cur_h - cur_l;
   if(cur_range > atr14 * ATR_Max_Mult){
      Print("ATR_FILTER: barra muy volátil (",DoubleToString(cur_range,2)," > ",DoubleToString(atr14*ATR_Max_Mult,2),") — no entrar");
      return false;
   }
   if(cur_range < atr14 * ATR_Min_Mult){
      // mercado muerto — no hay señal real
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void RecordTrade(int hour, double sl_dist, double profit, double hold_sec)
{
   if(g_histCount >= 500) {
      for(int i=0; i<450; i++) g_history[i] = g_history[i+50];
      g_histCount = 450;
   }
   g_history[g_histCount].hour        = hour;
   g_history[g_histCount].sl_dist     = sl_dist;
   g_history[g_histCount].profit      = profit;
   g_history[g_histCount].hold_sec    = hold_sec;
   g_history[g_histCount].is_win      = (profit > 0);
   g_history[g_histCount].is_quick_loss = (profit < -0.5 && hold_sec < Learn_Quick_Loss_Sec);
   g_histCount++;
   g_totalTrades++;
   
   g_hourStats[hour].n++;
   g_hourStats[hour].total_profit += profit;
   if(profit > 0) g_hourStats[hour].wins++;
   
   if(g_hourStats[hour].n >= Learn_Min_Samples){
      double wr = (double)g_hourStats[hour].wins / g_hourStats[hour].n;
      if(!g_hourStats[hour].blocked && wr < Learn_WR_Block){
         g_hourStats[hour].blocked = true;
         g_hourStats[hour].block_samples = 0;
         Print("LEARN M1: Hora ",hour," BLOQUEADA (WR=",DoubleToString(wr*100,1),"%)");
      } else if(g_hourStats[hour].blocked){
         g_hourStats[hour].block_samples++;
         if(wr >= Learn_WR_Reopen){
            g_hourStats[hour].blocked = false;
            Print("LEARN M1: Hora ",hour," REABIERTA (WR=",DoubleToString(wr*100,1),"%)");
         }
      }
   }
   if(g_totalTrades % Learn_Recalc_Every == 0) AdaptParameters();
}

// Registra trade del Motor 3 con su propio autoaprendizaje por hora
void RecordM3Trade(int hour, double profit)
{
   bool is_win = (profit > 0);
   g_m3_hour_n[hour]++;
   if(is_win) g_m3_hour_wins[hour]++;
   if(g_m3_hour_n[hour] >= M3_Min_Samples){
      double wr = (double)g_m3_hour_wins[hour] / g_m3_hour_n[hour];
      if(!g_m3_hour_blocked[hour] && wr < M3_WR_Block){
         g_m3_hour_blocked[hour] = true;
         Print("LEARN M3: Hora ",hour," BLOQUEADA (WR=",DoubleToString(wr*100,1),"%)");
      } else if(g_m3_hour_blocked[hour] && wr >= Learn_WR_Reopen){
         g_m3_hour_blocked[hour] = false;
         Print("LEARN M3: Hora ",hour," REABIERTA (WR=",DoubleToString(wr*100,1),"%)");
      }
   }
   // Racha Motor 3
   if(is_win){
      g_m3_consecWins++; g_m3_consecLosses=0;
      g_m3_lot_scale = MathMin(g_m3_lot_scale * Streak_Boost_Pct, Streak_Scale_Max);
   } else {
      g_m3_consecLosses++; g_m3_consecWins=0;
      g_m3_lot_scale = MathMax(g_m3_lot_scale * Streak_Reduce_Pct, Streak_Scale_Min);
      if(g_m3_consecLosses >= Max_Consec_Losses){
         g_m3_pauseBarsLeft = Pause_Bars;
         g_m3_pendingDir = 0;
         Print("M3 PAUSA ",Pause_Bars,"b tras ",g_m3_consecLosses," losses");
      }
   }
}

//+------------------------------------------------------------------+
void AdaptParameters()
{
   if(g_histCount < 10) return;
   int look = MathMin(g_histCount, 50);
   int quick_losses = 0;
   for(int i=g_histCount-look; i<g_histCount; i++)
      if(g_history[i].is_quick_loss) quick_losses++;
   double quick_ratio = (double)quick_losses / look;
   if(quick_ratio > 0.20)
      g_vel_threshold = MathMin(Vel_Threshold_Base * 0.85, Vel_Threshold_Base);
   else if(quick_ratio < 0.05)
      g_vel_threshold = MathMin(Vel_Threshold_Base * 1.10, Vel_Threshold_Base * 1.20);
   else
      g_vel_threshold = Vel_Threshold_Base;
   double vol_sum = 0;
   for(int i=1; i<=Learn_Vol_Window; i++){
      double h = iHigh(g_sym,_Period,i), l = iLow(g_sym,_Period,i);
      if(h>0 && l>0) vol_sum += (h-l);
   }
   double avg_bar_range = vol_sum / Learn_Vol_Window;
   double vol_factor = 1.0;
   if(avg_bar_range > 5.0)      vol_factor = 1.0 + Learn_Trail_Scale;
   else if(avg_bar_range < 2.0) vol_factor = 1.0 - Learn_Trail_Scale * 0.5;
   g_trail_dist = Trail_Dist_Phase2 * vol_factor;
   g_trail_dist = MathMax(g_trail_dist, 4.0);
   g_trail_dist = MathMin(g_trail_dist, 20.0);
   Print("LEARN Adapt: vel=",DoubleToString(g_vel_threshold,2),
         " trail=",DoubleToString(g_trail_dist,2),"pts",
         " vol=",DoubleToString(avg_bar_range,2),"pts/barra",
         " quick_loss%=",DoubleToString(quick_ratio*100,1),"%");
}

//+------------------------------------------------------------------+
void UpdateStreakScale(bool is_win)
{
   if(is_win){
      g_consecWins++; g_consecLosses = 0;
      g_lot_scale = MathMin(g_lot_scale * Streak_Boost_Pct, Streak_Scale_Max);
      if(g_consecWins >= Streak_Win_Trigger)
         Print("MOMENTUM WIN×",g_consecWins," lot_scale=",DoubleToString(g_lot_scale,3));
   } else {
      g_consecLosses++; g_consecWins = 0;
      g_lot_scale = MathMax(g_lot_scale * Streak_Reduce_Pct, Streak_Scale_Min);
      if(g_consecLosses >= Streak_Loss_Trigger)
         Print("MOMENTUM LOSS×",g_consecLosses," lot_scale=",DoubleToString(g_lot_scale,3));
      if(g_consecLosses >= Max_Consec_Losses){
         g_pauseBarsLeft = Pause_Bars;
         g_pendingDir    = 0;
         Print("MM7 PAUSA ",Pause_Bars,"b tras ",g_consecLosses," losses");
      }
   }
}

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   bool base_ok = (hour==2||hour==7||hour==15||hour==22);
   if(!base_ok) return false;
   if(g_hourStats[hour].blocked && g_hourStats[hour].n >= Learn_Min_Samples) return false;
   if(g_regime_paused) return false;
   return true;
}

bool IsGoodHourM3(int hour)
{
   if(!Use_Hour_Filter) return true;
   bool base_ok = (hour==2||hour==7||hour==15||hour==22);
   if(!base_ok) return false;
   if(g_m3_hour_blocked[hour] && g_m3_hour_n[hour] >= M3_Min_Samples) return false;
   if(g_regime_paused) return false;
   return true;
}

//+------------------------------------------------------------------+
void UpdateRegime()
{
   double price_now  = iClose(g_sym, _Period, 1);
   double price_ago  = iClose(g_sym, _Period, Regime_Trend_Bars + 1);
   if(price_now > 0 && price_ago > 0){
      double move = price_now - price_ago;
      if(move > Regime_Trend_Pts){
         if(g_regime_lot_factor != Regime_Lot_Scale){
            g_regime_lot_factor = Regime_Lot_Scale;
            Print("RÉGIMEN ALCISTA → Motor1 lot×",Regime_Lot_Scale," | Motor3 aprovechar");
         }
      } else {
         if(g_regime_lot_factor != 1.0){
            g_regime_lot_factor = 1.0;
            Print("RÉGIMEN NEUTRO: lot normal");
         }
      }
   }
}

void UpdateDailyRegime(double profit)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",dt.year,dt.mon,dt.day));
   if(g_today_date != today){
      if(g_today_date != 0){
         if(g_today_pnl < 0){ g_consec_neg_days++; g_consec_pos_days = 0; }
         else if(g_today_pnl > 0){ g_consec_pos_days++; g_consec_neg_days = 0; }
         if(g_consec_neg_days >= Regime_Bad_Days && g_regime_lot_factor > Regime_Lot_Scale)
            g_regime_lot_factor = Regime_Lot_Scale;
         if(g_consec_pos_days >= Regime_Good_Days && g_regime_lot_factor < 1.0){
            g_regime_lot_factor = 1.0; g_consec_neg_days = 0;
         }
         g_regime_paused = false;
      }
      g_today_date = today; g_today_pnl = 0.0;
   }
   g_today_pnl += profit;
}

bool TrendBlocksSell()
{
   double cn=iClose(g_sym,_Period,1), co=iClose(g_sym,_Period,Trend_Bars+1);
   if(cn==0||co==0) return false;
   return (cn-co >= Trend_Min_Move);
}

// Motor 3: no hacer BUY si mercado está bajando fuertemente
bool TrendBlocksBuy()
{
   double cn=iClose(g_sym,_Period,1), co=iClose(g_sym,_Period,Trend_Bars+1);
   if(cn==0||co==0) return false;
   return (co-cn >= Trend_Min_Move); // bajando fuerte → no comprar
}

bool IsFridayClose()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.day_of_week==5 && dt.hour>=FriClose_Hour_UTC);
}

//+------------------------------------------------------------------+
void UpdateBalanceTrail(double current_balance)
{
   if(!Use_Balance_Trail) return;
   if(current_balance > g_balance_peak){ g_balance_peak = current_balance; g_bal_trail_scale = 1.0; }
   double dd = (g_balance_peak > 0) ? (g_balance_peak - current_balance) / g_balance_peak : 0;
   double prev_scale = g_bal_trail_scale;
   if(dd >= BalTrail_DD2_Pct)      g_bal_trail_scale = BalTrail_Scale2;
   else if(dd >= BalTrail_DD1_Pct) g_bal_trail_scale = BalTrail_Scale1;
   else                             g_bal_trail_scale = 1.0;
   if(g_bal_trail_scale != prev_scale)
      Print("BAL_TRAIL: DD=",DoubleToString(dd*100,1),"% → lot×",g_bal_trail_scale);
}

//+------------------------------------------------------------------+
void UpdateWRTracker(bool is_win)
{
   if(!Use_WR_Tracker) return;
   g_wr_history[g_wr_hist_idx] = is_win ? 1.0 : 0.0;
   g_wr_hist_idx = (g_wr_hist_idx + 1) % 20;
   if(g_wr_hist_n < 20) g_wr_hist_n++;
   int window = MathMin(WR_Track_Window, g_wr_hist_n);
   if(window < 3) return;
   double sum = 0;
   int start = (g_wr_hist_idx - window + 20) % 20;
   for(int i=0; i<window; i++) sum += g_wr_history[(start+i)%20];
   double wr_roll = sum / window;
   double prev_scale = g_wr_track_scale;
   if(wr_roll <= WR_Track_Low){
      g_wr_track_scale = WR_Track_Scale_Low;
      if(g_pauseBarsLeft < WR_Track_Pause_Bars){
         g_pauseBarsLeft = WR_Track_Pause_Bars;
         Print("WR_TRACK: WR=",DoubleToString(wr_roll*100,1),"% pausa ",WR_Track_Pause_Bars,"b");
      }
   } else if(wr_roll >= WR_Track_High){
      g_wr_track_scale = WR_Track_Scale_High;
   } else {
      double t = (wr_roll - WR_Track_Low) / (WR_Track_High - WR_Track_Low);
      g_wr_track_scale = WR_Track_Scale_Low + t*(WR_Track_Scale_High - WR_Track_Scale_Low);
   }
   if(MathAbs(g_wr_track_scale - prev_scale) > 0.05)
      Print("WR_TRACK: wr=",DoubleToString(wr_roll*100,1),"% → lot×",DoubleToString(g_wr_track_scale,2));
}

double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Min_Lot,2);
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   double cap_usd = bal * Cap_Pct_Of_Balance;
   double risk    = MathMin(bal * Risk_Pct_Per_Trade, cap_usd);
   if(sl_dist <= 0) sl_dist = SL_Min;
   double combined = g_lot_scale * g_regime_lot_factor * g_bal_trail_scale * g_wr_track_scale;
   double lot = (risk / (sl_dist * 100.0)) * combined;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st>0) lot = MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

double CalcLotCustom(double sl_dist, double risk_pct, double lot_scale_override)
{
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   double cap_usd = bal * Cap_Pct_Of_Balance;
   double risk    = MathMin(bal * risk_pct, cap_usd);
   if(sl_dist <= 0) sl_dist = SL_Min;
   double combined = lot_scale_override * g_regime_lot_factor * g_wr_track_scale;
   double lot = (risk / (sl_dist * 100.0)) * combined;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st>0) lot = MathFloor(lot/st)*st;
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
   bool okc=OrderSend(req,res);
   if(!okc){req.type_filling=ORDER_FILLING_IOC;okc=OrderSend(req,res);}
   if(!okc){req.type_filling=ORDER_FILLING_RETURN;okc=OrderSend(req,res);}
}

void ClosePositionByMagic(ulong ticket, int magic_num, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double vol=PositionGetDouble(POSITION_VOLUME);
   ENUM_ORDER_TYPE close_type = (ptype==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   double price = (close_type==ORDER_TYPE_SELL)?SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol;
   req.type=close_type; req.price=price; req.position=ticket;
   req.deviation=InpSlippagePoints; req.magic=magic_num;
   req.comment="MM7-"+reason; req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
}

void OpenSell(double sl_dist)
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double tp_d=sl_dist*TP_Ratio;
   double tp=NormalizeDouble(bid-tp_d,digs);
   double sl=NormalizeDouble(bid+sl_dist,digs);
   double lot=CalcLot(sl_dist);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=ORDER_TYPE_SELL; req.price=bid; req.sl=sl; req.tp=tp;
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment="MM7-M1";
   req.type_filling=ORDER_FILLING_FOK;
   bool oks=OrderSend(req,res);
   if(!oks){req.type_filling=ORDER_FILLING_IOC;oks=OrderSend(req,res);}
   if(!oks){req.type_filling=ORDER_FILLING_RETURN;oks=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0;
      Print("MM7 M1-SELL bid=",bid," SL=",sl," TP=",tp," lot=",lot);
   } else { Print("MM7 M1 FAIL retcode=",res.retcode); }
}

void SetSLTP(ulong ticket, double newSL, double newTP)
{
   MqlTradeRequest rr={}; MqlTradeResult rs={};
   rr.action=TRADE_ACTION_SLTP; rr.symbol=g_sym;
   rr.position=ticket; rr.sl=newSL; rr.tp=newTP;
   bool ok = OrderSend(rr,rs);
   if(!ok) Print("MM7 SetSLTP error retcode=",rs.retcode);
}

// ================================================================
// MOTOR 3: BUY en reversión alcista (espejo del Motor 1)
// Motor 1: precio en TOP del rango → SELL (espera caída)
// Motor 3: precio en BOTTOM del rango → BUY (espera subida)
// ================================================================
bool M3_HasPosition()
{
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==M3_Magic)
         return true;
   }
   return false;
}

void M3_CloseAll(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tk=PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=M3_Magic) continue;
      ClosePositionByMagic(tk, M3_Magic, reason);
   }
}

void M3_OpenBuy(double sl_dist)
{
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double tp_d=sl_dist*M3_TP_Ratio;
   double tp=NormalizeDouble(ask+tp_d,digs);
   double sl=NormalizeDouble(ask-sl_dist,digs);
   double lot=CalcLotCustom(sl_dist, M3_Risk_Pct, g_m3_lot_scale);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=ORDER_TYPE_BUY; req.price=ask; req.sl=sl; req.tp=tp;
   req.deviation=InpSlippagePoints; req.magic=M3_Magic; req.comment="MM7-M3";
   req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_m3_pendingDir=0;
      Print("MM7 M3-BUY ask=",ask," SL=",sl," TP=",tp," lot=",lot);
   } else { Print("MM7 M3 FAIL retcode=",res.retcode); }
}

// Gestionar trailing y hard cap de posiciones BUY del Motor 3
void M3_ManagePositions(datetime now)
{
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tk=PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=M3_Magic) continue;
      
      double pnl = PositionGetDouble(POSITION_PROFIT);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double bid = SymbolInfoDouble(g_sym,SYMBOL_BID);
      double favorable = bid - entry; // BUY: favorable cuando sube
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
      
      // Hard Loss Cap
      if(Use_Hard_Loss_Cap && pnl < -Hard_Loss_Cap_USD){
         ClosePositionByMagic(tk, M3_Magic, "M3-HardCap");
         Print("M3 HARD CAP pnl=",DoubleToString(pnl,2));
         continue;
      }
      
      // Partial close
      if(Use_Partial_Close && pnl >= Partial_USD_Trigger){
         double cv = PositionGetDouble(POSITION_VOLUME);
         double vc = NormalizeDouble(cv*Partial_Close_Pct,2);
         double st2=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
         double mn2=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
         if(st2>0) vc=MathFloor(vc/st2)*st2; vc=MathMax(vc,mn2);
         if(vc<cv){
            // Partial: cierre parcial BUY → vender parte
            MqlTradeRequest req={}; MqlTradeResult res={};
            req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vc;
            req.type=ORDER_TYPE_SELL; req.price=bid; req.position=tk;
            req.deviation=InpSlippagePoints; req.magic=M3_Magic;
            req.comment="M3-partial"; req.type_filling=ORDER_FILLING_FOK;
            bool ok=OrderSend(req,res);
            if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
            // Mover SL a BE
            double nsl=NormalizeDouble(entry,digs);
            if(nsl>curSL) SetSLTP(tk, nsl, curTP);
            Print("M3 PARTIAL vol=",vc," bid=",bid);
         }
      }
      
      // Trailing (BUY: trail sigue subiendo bid)
      if(Use_Trail && favorable >= Trail_Start_Pts){
         double trail_d = Trail_Dist_Phase2; // usar fase 2 por defecto para M3
         int elapsed=(int)(now - (datetime)PositionGetInteger(POSITION_TIME));
         if(elapsed < Trail_Phase1_Sec) trail_d = Trail_Dist_Phase1;
         else if(elapsed < Trail_Phase2_Sec) trail_d = Trail_Dist_Phase2;
         else trail_d = Trail_Dist_Phase3;
         double newSL = NormalizeDouble(bid - trail_d, digs);
         if(newSL > curSL) SetSLTP(tk, newSL, curTP);
      }
   }
}

void RunMotor3(double bid, double ask, datetime now)
{
   if(!Use_Motor3) return;
   
   // Gestionar posiciones abiertas del M3
   M3_ManagePositions(now);
   
   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_m3_lastBarTime){
      g_m3_lastBarTime=curBar;
      if(g_m3_pauseBarsLeft>0){ g_m3_pauseBarsLeft--; g_m3_pendingDir=0; return; }
      g_m3_pendingDir=0;
      if(M3_HasPosition()) return;
      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsGoodHourM3(dt.hour)) return;
      if(!ATR_OK()) return;
      if(TrendBlocksBuy()) return; // no comprar en caída fuerte
      
      // Calcular rango
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      // Zona inferior simétrica a la zona superior del Motor 1
      double lowerZone=rL+range*M3_Zone_Pct_Base;
      
      // Filtro velocidad
      double cv2=iClose(g_sym,_Period,Vel_Bars+1), cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>g_vel_threshold) return;
      
      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,M3_SL_Max),M3_SL_Min);
      
      if(closeNow<=lowerZone){
         g_m3_pendingDir=1;
         g_m3_confirmLevel=closeNow+M3_Confirm_Points; // confirma subiendo
         g_m3_pendingSL=slDist;
      }
      return;
   }
   
   if(g_m3_pauseBarsLeft>0) return;
   if(g_m3_pendingDir==0) return;
   if(M3_HasPosition()){ g_m3_pendingDir=0; return; }
   MqlDateTime dt; TimeToStruct(now,dt);
   if(!IsGoodHourM3(dt.hour)){ g_m3_pendingDir=0; return; }
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){ g_m3_pendingDir=0; return; }
   
   if(g_m3_pendingDir==1 && ask>=g_m3_confirmLevel)
      M3_OpenBuy(g_m3_pendingSL);
}

// ================================================================
// MOTOR 2 — BREAKOUT (con lot dinámico)
// ================================================================
bool IsM2Hour(int hour){ return (hour==8 || hour==13); }

void M2_ClosePosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--){
      ulong tk=PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=M2_Magic) continue;
      ClosePositionByMagic(tk, M2_Magic, "M2-TimeExit");
   }
}

bool M2_HasPosition()
{
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==M2_Magic)
         return true;
   }
   return false;
}

void M2_OpenTrade(int dir, double entry, double sl, double tp)
{
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   ENUM_ORDER_TYPE otype = (dir==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double price = (dir==1)?SymbolInfoDouble(g_sym,SYMBOL_ASK):SymbolInfoDouble(g_sym,SYMBOL_BID);
   // Lot dinámico basado en riesgo (FIX: antes era fijo M2_Lot=0.01)
   double sl_dist = MathAbs(price - sl);
   double lot = CalcLotCustom(sl_dist, M2_Risk_Pct, 1.0);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=otype; req.price=price;
   req.sl=NormalizeDouble(sl,digs); req.tp=NormalizeDouble(tp,digs);
   req.deviation=InpSlippagePoints; req.magic=M2_Magic;
   req.comment=(dir==1)?"M2-BUY":"M2-SELL";
   req.type_filling=ORDER_FILLING_FOK;
   bool ok=OrderSend(req,res);
   if(!ok){req.type_filling=ORDER_FILLING_IOC;ok=OrderSend(req,res);}
   if(!ok){req.type_filling=ORDER_FILLING_RETURN;ok=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_m2_openTime=TimeCurrent(); g_m2_openEntry=price;
      Print("M2 OPEN ",((dir==1)?"BUY":"SELL")," price=",price,
            " SL=",DoubleToString(sl,digs)," TP=",DoubleToString(tp,digs)," lot=",lot);
   } else { Print("M2 FAIL retcode=",res.retcode); }
   g_m2_pendingDir=0;
}

void RunMotor2(double bid, double ask, datetime now)
{
   if(!Use_Motor2) return;
   if(M2_HasPosition() && g_m2_openTime>0){
      if((int)(now-g_m2_openTime)>=M2_MaxHold_Sec){
         M2_ClosePosition();
         g_m2_openTime=0; g_m2_pendingDir=0;
         Print("M2 TimeExit tras ",M2_MaxHold_Sec/60,"min");
      }
   }
   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_m2_lastBarTime){
      g_m2_lastBarTime=curBar; g_m2_pendingDir=0;
      if(M2_HasPosition()) return;
      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsM2Hour(dt.hour)) return;
      if(!ATR_OK()) return; // FIX: Motor 2 también respeta ATR filter
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=M2_Breakout_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double breakH = rH + M2_Breakout_Pts;
      double breakL = rL - M2_Breakout_Pts;
      if(closeNow >= breakH){
         g_m2_pendingDir = 1;
         g_m2_pendingSL  = closeNow - M2_SL_Pts;
         g_m2_pendingTP  = closeNow + M2_TP_Pts;
      } else if(closeNow <= breakL){
         g_m2_pendingDir = -1;
         g_m2_pendingSL  = closeNow + M2_SL_Pts;
         g_m2_pendingTP  = closeNow - M2_TP_Pts;
      }
      return;
   }
   if(g_m2_pendingDir==0) return;
   if(M2_HasPosition()){ g_m2_pendingDir=0; return; }
   MqlDateTime dt2; TimeToStruct(now,dt2);
   if(!IsM2Hour(dt2.hour)){ g_m2_pendingDir=0; return; }
   if(g_m2_pendingDir==1)
      M2_OpenTrade(1, ask, g_m2_pendingSL, g_m2_pendingTP);
   else if(g_m2_pendingDir==-1)
      M2_OpenTrade(-1, bid, g_m2_pendingSL, g_m2_pendingTP);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type!=DEAL_TYPE_BUY&&trans.deal_type!=DEAL_TYPE_SELL) return;
   if(!HistoryDealSelect(trans.deal)) return;
   int deal_magic = (int)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(deal_magic!=g_magic && deal_magic!=M3_Magic) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   double profit  = HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal,DEAL_COMMENT);
   if(StringFind(comment,"partial")>=0) return;
   
   datetime open_t = (datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   MqlDateTime dt; TimeToStruct(open_t, dt);
   
   if(deal_magic == g_magic){
      // Motor 1
      double hold_sec = 0;
      for(int i=0;i<3;i++){
         if(g_states[i].entry>0){
            hold_sec = (double)(open_t - g_states[i].openTime);
            RecordTrade(dt.hour, g_states[i].slDist, profit, hold_sec);
            g_states[i].entry=0; g_states[i].slDist=0;
            g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
            g_states[i].timeTrailDone=false; g_states[i].openTime=0;
            break;
         }
      }
      if(hold_sec == 0) RecordTrade(dt.hour, SL_Min, profit, 0);
      bool is_win = (profit > 0);
      UpdateStreakScale(is_win);
      UpdateWRTracker(is_win);
      UpdateDailyRegime(profit);
      UpdateBalanceTrail(AccountInfoDouble(ACCOUNT_BALANCE));
   } else if(deal_magic == M3_Magic){
      // Motor 3
      bool is_win = (profit > 0);
      RecordM3Trade(dt.hour, profit);
      UpdateWRTracker(is_win); // M3 también alimenta el WR global
      UpdateDailyRegime(profit);
   }
}

int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   InitLearning();
   for(int i=0;i<3;i++){
      g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
      g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
      g_states[i].timeTrailDone=false; g_states[i].openTime=0;
   }
   Print("MM7 v17.81 TRIPLE MOTOR | ",g_sym,
         " | M1:SELL H2,7,15,22 | M2:Breakout H8,13 | M3:BUY H2,7,15,22",
         " | TP_Ratio=",TP_Ratio," SL_Min=",SL_Min,
         " | ATR_Filter=",Use_ATR_Filter," | Partial@$",Partial_USD_Trigger);
   return INIT_SUCCEEDED;
}

double GetTrailDist(datetime openTime)
{
   int elapsed = (int)(TimeCurrent() - openTime);
   if(elapsed < Trail_Phase1_Sec)  return Trail_Dist_Phase1;
   if(elapsed < Trail_Phase2_Sec)  return Trail_Dist_Phase2;
   return Trail_Dist_Phase3;
}

void DoPartialClose(ulong ticket, double vol_close)
{
   if(!PositionSelectByTicket(ticket)) return;
   double price = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   if(st>0) vol_close = MathFloor(vol_close/st)*st;
   vol_close = MathMax(vol_close, mn);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol_close;
   req.type=ORDER_TYPE_BUY; req.price=price; req.position=ticket;
   req.deviation=InpSlippagePoints; req.magic=g_magic;
   req.comment="MM7-partial"; req.type_filling=ORDER_FILLING_FOK;
   bool okp=OrderSend(req,res);
   if(!okp){req.type_filling=ORDER_FILLING_IOC;okp=OrderSend(req,res);}
   if(!okp){req.type_filling=ORDER_FILLING_RETURN;okp=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
      Print("MM7 M1 PARTIAL vol=",vol_close," price=",price);
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
      if(Use_Motor3) M3_CloseAll("FriClose");
      g_pendingDir=0; return;
   }

   // Correr los 3 motores
   RunMotor2(bid, ask, now);
   RunMotor3(bid, ask, now);

   // GESTIÓN POSICIONES MOTOR 1
   ulong tks[]; int npos=(int)GetTickets(tks);
   for(int pi=0;pi<npos;pi++){
      ulong tk=tks[pi];
      if(!PositionSelectByTicket(tk)) continue;
      double entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double favorable= entry - ask;
      int si=-1;
      for(int i=0;i<3;i++){
         if(MathAbs(g_states[i].entry-entry)<0.01&&g_states[i].entry>0){si=i;break;}
      }
      if(si<0){
         for(int i=0;i<3;i++){
            if(g_states[i].entry==0){si=i;break;}
         }
         if(si<0) continue;
         g_states[si].entry=entry;
         g_states[si].slDist=MathAbs(curSL-entry);
         g_states[si].tpDist=g_states[si].slDist*TP_Ratio;
         g_states[si].openTime=now;
         g_states[si].trailActive=false;
         g_states[si].beMovedOnce=false;
         g_states[si].timeTrailDone=false;
      }
      double slD=g_states[si].slDist;
      double elapsed_s = (double)(now - g_states[si].openTime);

      // Hard Loss Cap
      if(Use_Hard_Loss_Cap && PositionSelectByTicket(tk)){
         double pnl = PositionGetDouble(POSITION_PROFIT);
         if(pnl < -Hard_Loss_Cap_USD){
            ClosePosition(tk,"HardCap");
            Print("MM7 M1 HARD CAP pnl=",DoubleToString(pnl,2));
            continue;
         }
      }

      // Partial Close (más agresivo: $5 en lugar de $8)
      if(Use_Partial_Close && !g_states[si].beMovedOnce && PositionSelectByTicket(tk)){
         double pnl_float = PositionGetDouble(POSITION_PROFIT);
         if(pnl_float >= Partial_USD_Trigger){
            double cv = PositionGetDouble(POSITION_VOLUME);
            double vc = NormalizeDouble(cv*Partial_Close_Pct,2);
            double st2=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
            double mn2=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
            if(st2>0) vc=MathFloor(vc/st2)*st2; vc=MathMax(vc,mn2);
            if(vc<cv){
               DoPartialClose(tk,vc);
               g_states[si].beMovedOnce=true;
               double ctp2=PositionGetDouble(POSITION_TP);
               double csl2=PositionGetDouble(POSITION_SL);
               int digs2=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
               double nsl2=NormalizeDouble(entry,digs2);
               if(nsl2<csl2) SetSLTP(tk, nsl2, ctp2);
            }
         }
      }

      // Trailing escalonado
      if(Use_Trail && favorable>=Trail_Start_Pts){
         double trail_d = GetTrailDist(g_states[si].openTime);
         double newSL=ask+trail_d;
         if(PositionSelectByTicket(tk)){
            double csl=PositionGetDouble(POSITION_SL),ctp=PositionGetDouble(POSITION_TP);
            int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
            newSL=NormalizeDouble(newSL,digs);
            if(newSL<csl) SetSLTP(tk, newSL, ctp);
         }
         if(!g_states[si].trailActive) g_states[si].trailActive=true;
      }

      if(Use_Time_Trail&&!g_states[si].timeTrailDone&&g_states[si].openTime>0){
         if((now-g_states[si].openTime)>=Time_Trail_Sec){
            if(favorable<slD*Trail_Progress_Pct){
               if(PositionSelectByTicket(tk)){
                  double ctp=PositionGetDouble(POSITION_TP);
                  double csl=PositionGetDouble(POSITION_SL);
                  int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
                  double nsl=NormalizeDouble(entry,digs);
                  if(nsl<csl) SetSLTP(tk, nsl, ctp);
               }
            }
            g_states[si].timeTrailDone=true;
         }
      }
   }

   // Limpiar estados cerrados
   npos=(int)GetTickets(tks);
   for(int i=0;i<3;i++){
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
      if(g_pauseBarsLeft>0){g_pauseBarsLeft--;return;}
      
      UpdateRegime();
      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsGoodHour(dt.hour)) return;
      if(!ATR_OK()) return; // FIX: ATR filter en lugar de solo velocidad

      // Filtro velocidad (mantenido como filtro secundario)
      double cv2=iClose(g_sym,_Period,Vel_Bars+1), cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>g_vel_threshold) return;

      // Rango señal Motor 1
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*g_zone_pct;

      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,SL_Max),SL_Min);

      if(closeNow>=upperZone && !TrendBlocksSell()){
         g_pendingDir=-1;
         g_confirmLevel=closeNow-Confirm_Points;
         g_pendingSL=slDist;
      }
      return;
   }

   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0) return;
   MqlDateTime dt; TimeToStruct(now,dt);
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
