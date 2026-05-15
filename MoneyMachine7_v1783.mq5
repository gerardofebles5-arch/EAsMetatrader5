//+------------------------------------------------------------------+
//|  MoneyMachine7_v1783.mq5                                        |
//|  v17.83 — MEJORAS BASADAS EN DATOS REALES DE v17.82             |
//|                                                                  |
//|  ANÁLISIS DATOS v17.82 ($50→$221, Factor=1.68):                 |
//|                                                                  |
//|  ESTADÍSTICAS POR HORA (cierres):                               |
//|  H01: n=3   WR=67%  P=$-1.86  (sin señal Motor 1)              |
//|  H02: n=9   WR=56%  P=$+56.99 ← BUENA                         |
//|  H03: n=8   WR=25%  P=$-18.06 ← MAL, trades cierran a H03      |
//|  H07: n=4   WR=0%   P=$-24.69 ← ELIMINAR señal H07             |
//|  H08: n=2   WR=100% P=$+16.47 (Motor 2 breakout)               |
//|  H15: n=25  WR=48%  P=$+60.76 ← BUENA                         |
//|  H16: n=11  WR=73%  P=$+82.79 ← MEJOR HORA (trailing M15)      |
//|  H22: n=6   WR=50%  P=$-0.84  (marginal, HardCap pesó)         |
//|                                                                  |
//|  HALLAZGO CRÍTICO 1: H07 WR=0% en 4 trades, -$24.69            |
//|  Todos los trades de H07 son pérdidas puras (SL).               |
//|  El autoaprendizaje debería haberlo bloqueado pero              |
//|  necesitaba 10 muestras. Con solo 4, nunca bloqueó.             |
//|  FIX: Learn_Min_Samples 10→4 para bloquear antes               |
//|       + H07 pre-bloqueada con WR histórico <30%                 |
//|                                                                  |
//|  HALLAZGO CRÍTICO 2: 8 HardCaps = -$100.18 (59% de pérdidas)   |
//|  Los HardCaps son la principal fuente de pérdida.               |
//|  El SL_Min=19.2 hace trades muy anchos que aguantan mucho.      |
//|  Distribución: H01×1, H02×1, H03×1, H15×3, H22×1 → H15 es    |
//|  donde más HardCaps ocurren. Precio va contra señal rápido.     |
//|  FIX: Hard_Loss_Cap 12→9 — cortar antes (más eficiente)        |
//|       + Si 2+ HardCaps seguidos → pausa 10 barras              |
//|                                                                  |
//|  HALLAZGO 3: H16 WR=73%, +$82.79 — MEJOR HORA                  |
//|  H16 no es hora de señal (señal es a H15), son los cierres.     |
//|  Las señales de H15 que aguantan hasta H16 son las mejores.     |
//|  El trailing funciona perfecto: permite que el trade madure.     |
//|  FIX: Trail más suelto en Phase1 para aguantar hasta H16        |
//|       Trail_Dist_Phase1 13→16 (más espacio al inicio)           |
//|                                                                  |
//|  HALLAZGO 4: Grandes wins = $348 en 18 trades (82% del profit)  |
//|  Los trades >$10 generan casi todo el dinero.                   |
//|  Necesitamos MORE de esos, no matarlos con trail ajustado.      |
//|  FIX: Trail_Start_Pts 2.9→4.0 (no activar trail tan rápido)   |
//|       → dejar respirar al trade antes de fijar trailing         |
//|                                                                  |
//|  HALLAZGO 5: H03 WR=25% — los trades H02 cierran a H03         |
//|  Las señales de H02 que se extienden hasta H03 pierden.         |
//|  FIX: Time exit parcial — si trade de H02 llega a H03:00 sin   |
//|       ganancia, mover SL a BE inmediatamente.                   |
//|       (Time_Trail ya maneja esto con Time_Trail_Sec)            |
//|       Time_Trail_Sec 11520→5400 (90min en lugar de 3.2h)       |
//|                                                                  |
//|  HALLAZGO 6: WR global 50% = break even sin gestión             |
//|  El sistema gana porque avg_win($12.45) > avg_loss($7.40)       |
//|  Ratio R:R = 1.68 — hay margen para mejorar más el ratio       |
//|  FIX: Partial_USD_Trigger 6→5 + Partial_Close_Pct 40%→50%     |
//|       → asegurar más en winners grandes                         |
//|                                                                  |
//|  HALLAZGO 7: Bear Protector funcionó (Mar17-19 no fue catástrofe)|
//|  Pero aún perdimos $97 en esa semana (319→221).                 |
//|  Bear_Drop_Pts 60→50, Bear_Bars 180→120 → detectar antes        |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.83"
#property strict

//=== SEÑAL MOTOR 1 — NO TOCAR ZONA/CONFIRM/SL (calibrados) ===
input int    Range_Bars          = 50;
input double Zone_Pct_Base       = 0.555;
input double Confirm_Points      = 4.6;
input int    Local_Vol_Bars      = 6;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 19.2;
input double SL_Max              = 85.2;
input double TP_Ratio            = 16.0;

//=== TRAILING — FIX 3+4: más espacio al inicio, misma fase final ===
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 4.0;    // FIX: 2.9→4.0 no activar tan rápido
input double Trail_Dist_Phase1   = 16.0;  // FIX: 13→16 más espacio, trades maduran
input double Trail_Dist_Phase2   = 10.0;
input double Trail_Dist_Phase3   = 6.0;
input int    Trail_Phase1_Sec    = 600;
input int    Trail_Phase2_Sec    = 1800;

//=== PARTIAL CLOSE — FIX 6 ===
input bool   Use_Partial_Close    = true;
input double Partial_USD_Trigger  = 5.0;   // FIX: 6→5 asegurar antes
input double Partial_Close_Pct    = 0.50;  // FIX: 40%→50% más porcentaje asegurado

//=== HARD LOSS CAP — FIX 2 ===
input bool   Use_Hard_Loss_Cap   = true;
input double Hard_Loss_Cap_USD   = 9.0;   // FIX: 12→9 cortar antes (avg loss $7.4)

input bool   Use_Breakeven       = false;
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 5400;  // FIX: 11520→5400 (90min) para H02→H03
input double Trail_Progress_Pct  = 0.20;

//=== AUTOAPRENDIZAJE — FIX 1 ===
input int    Learn_Min_Samples   = 4;    // FIX: 10→4 bloquear horas malas antes
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

//=== FIX 2B: DOBLE HARDCAP PAUSE ===
// Si ocurren 2 HardCaps seguidos → pausa extendida
// Indica que el mercado está en tendencia fuerte contra señal
input bool   Use_DoubleHardCap_Pause = true;
input int    DoubleHardCap_Pause_Bars = 12; // pausar 12 barras (vs 8 normal)

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

//=== BEAR PROTECTOR — FIX 7: más reactivo ===
input bool   Use_Bear_Protect    = true;
input int    Bear_Bars           = 120;   // FIX: 180→120 detectar antes (2h)
input double Bear_Drop_Pts       = 50.0;  // FIX: 60→50 más sensible
input double Bear_Lot_Scale      = 0.30;
input int    Bear_EMA_Fast       = 5;
input int    Bear_EMA_Slow       = 20;

//=== COOLDOWN POST-HARDCAP ===
input bool   Use_HardCap_Cooldown   = true;
input int    HardCap_Cooldown_Bars  = 3;

//=== MOTOR 2: BREAKOUT (igual v17.82) ===
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

TradeState  g_states[2];

int    g_consecLosses     = 0;
int    g_consecWins       = 0;
int    g_pauseBarsLeft    = 0;
int    g_totalTrades      = 0;
int    g_hardcap_cooldown = 0;
int    g_consec_hardcaps  = 0;   // FIX 2B: contador de HardCaps consecutivos

double g_zone_pct      = 0;
double g_trail_dist    = 0;
double g_vel_threshold = 0;
double g_lot_scale     = 1.0;

double   g_regime_lot_factor = 1.0;
bool     g_regime_paused     = false;
int      g_consec_neg_days   = 0;
int      g_consec_pos_days   = 0;
double   g_today_pnl         = 0.0;
datetime g_today_date        = 0;

double   g_balance_peak      = 30.0;
double   g_bal_trail_scale   = 1.0;

double   g_wr_history[20];
int      g_wr_hist_idx = 0;
int      g_wr_hist_n   = 0;
double   g_wr_track_scale= 1.0;

double   g_bear_lot_factor = 1.0;

datetime g_m2_lastBarTime   = 0;
int      g_m2_pendingDir    = 0;
double   g_m2_pendingSL     = 0;
double   g_m2_pendingTP     = 0;
datetime g_m2_openTime      = 0;
double   g_m2_openEntry     = 0;

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
   g_bear_lot_factor = 1.0;
   g_hardcap_cooldown = 0;
   g_consec_hardcaps  = 0;

   for(int h=0; h<24; h++){
      g_hourStats[h].n=0; g_hourStats[h].wins=0;
      g_hourStats[h].total_profit=0; g_hourStats[h].total_ev=0;
      g_hourStats[h].blocked=false; g_hourStats[h].block_samples=0;
   }
   // FIX 1: Pre-bloquear H07 con historial de WR=0% real
   // Datos v17.80+v17.82: H07 = 0 wins en 4 trades consecutivos
   // Con Learn_Min_Samples=4, se necesitan 4 pérdidas reales para bloquear
   // Pre-cargamos 2 pérdidas como "historial anterior" para acelerar el bloqueo
   g_hourStats[7].n = 2; g_hourStats[7].wins = 0;
   Print("MM7 v17.83: H07 pre-cargada con 2 pérdidas históricas (WR=0%)");
}

//+------------------------------------------------------------------+
// FIX 7: Bear Protector más reactivo (120 barras, 50 pts)
void UpdateBearDetector()
{
   if(!Use_Bear_Protect){ g_bear_lot_factor = 1.0; return; }
   double price_now = iClose(g_sym, _Period, 1);
   double price_ago = iClose(g_sym, _Period, Bear_Bars + 1);
   if(price_now == 0 || price_ago == 0){ g_bear_lot_factor = 1.0; return; }
   double drop = price_ago - price_now;

   double ema_fast = 0, ema_slow = 0;
   for(int i=Bear_EMA_Fast; i>=1; i--) ema_fast += iClose(g_sym,_Period,i);
   ema_fast /= Bear_EMA_Fast;
   for(int i=Bear_EMA_Slow; i>=1; i--) ema_slow += iClose(g_sym,_Period,i);
   ema_slow /= Bear_EMA_Slow;

   double prev_factor = g_bear_lot_factor;
   if(drop >= Bear_Drop_Pts && ema_fast < ema_slow){
      if(g_bear_lot_factor != Bear_Lot_Scale){
         g_bear_lot_factor = Bear_Lot_Scale;
         Print("BEAR PROTECT ON: caída=",DoubleToString(drop,1),"pts/",Bear_Bars,"b → lot×",Bear_Lot_Scale);
      }
   } else {
      if(g_bear_lot_factor != 1.0){
         g_bear_lot_factor = 1.0;
         Print("BEAR PROTECT OFF: mercado normalizado");
      }
   }
}

//+------------------------------------------------------------------+
void RecordTrade(int hour, double sl_dist, double profit, double hold_sec, bool was_hardcap)
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

   // FIX 1: Learn_Min_Samples=4 — bloquear con solo 4 muestras
   if(g_hourStats[hour].n >= Learn_Min_Samples){
      double wr = (double)g_hourStats[hour].wins / g_hourStats[hour].n;
      if(!g_hourStats[hour].blocked && wr < Learn_WR_Block){
         g_hourStats[hour].blocked = true;
         g_hourStats[hour].block_samples = 0;
         Print("LEARN: Hora ",hour," BLOQUEADA (WR=",DoubleToString(wr*100,1),"% tras ",g_hourStats[hour].n," trades)");
      } else if(g_hourStats[hour].blocked){
         g_hourStats[hour].block_samples++;
         if(wr >= Learn_WR_Reopen){
            g_hourStats[hour].blocked = false;
            Print("LEARN: Hora ",hour," REABIERTA (WR=",DoubleToString(wr*100,1),"%)");
         }
      }
   }

   // FIX 2: HardCap tracking
   if(was_hardcap){
      g_consec_hardcaps++;
      if(Use_HardCap_Cooldown) g_hardcap_cooldown = HardCap_Cooldown_Bars;
      // FIX 2B: doble hardcap → pausa extendida
      if(Use_DoubleHardCap_Pause && g_consec_hardcaps >= 2){
         g_pauseBarsLeft = MathMax(g_pauseBarsLeft, DoubleHardCap_Pause_Bars);
         g_pendingDir = 0;
         Print("DOBLE HARDCAP: pausa ",DoubleHardCap_Pause_Bars,"b (tendencia fuerte)");
      }
   } else {
      if(profit > 0) g_consec_hardcaps = 0; // resetear con primer win
   }

   if(g_totalTrades % Learn_Recalc_Every == 0) AdaptParameters();
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
   g_trail_dist = MathMax(g_trail_dist, 5.0);
   g_trail_dist = MathMin(g_trail_dist, 25.0);
   Print("LEARN Adapt: vel=",DoubleToString(g_vel_threshold,2),
         " trail=",DoubleToString(g_trail_dist,2),"pts",
         " vol=",DoubleToString(avg_bar_range,2),"pts/barra");
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
            Print("RÉGIMEN ALCISTA → lot×",Regime_Lot_Scale);
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
         if(g_today_pnl < 0){ g_consec_neg_days++; g_consec_pos_days = 0;
            Print("DIA NEGATIVO #",g_consec_neg_days," PnL=$",DoubleToString(g_today_pnl,2));
         } else if(g_today_pnl > 0){ g_consec_pos_days++; g_consec_neg_days = 0; }
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
   double combined = g_lot_scale * g_regime_lot_factor *
                     g_bal_trail_scale * g_wr_track_scale * g_bear_lot_factor;
   double lot = (risk / (sl_dist * 100.0)) * combined;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st>0) lot = MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

double CalcLotM2(double sl_dist)
{
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   if(bal <= M2_DynLot_MinBal) return M2_Lot_Fixed;
   double cap_usd = bal * Cap_Pct_Of_Balance;
   double risk    = MathMin(bal * M2_Risk_Pct, cap_usd);
   if(sl_dist <= 0) sl_dist = M2_SL_Pts;
   double lot = (risk / (sl_dist * 100.0)) * g_wr_track_scale;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, M2_Lot_Fixed));
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
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment="MM7";
   req.type_filling=ORDER_FILLING_FOK;
   bool oks=OrderSend(req,res);
   if(!oks){req.type_filling=ORDER_FILLING_IOC;oks=OrderSend(req,res);}
   if(!oks){req.type_filling=ORDER_FILLING_RETURN;oks=OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0;
      Print("MM7 SELL bid=",bid," SL=",sl," TP=",tp," lot=",lot,
            " bear=",DoubleToString(g_bear_lot_factor,2),
            " wr=",DoubleToString(g_wr_track_scale,2));
   } else { Print("MM7 FAIL retcode=",res.retcode); }
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
// MOTOR 2 — BREAKOUT
// ================================================================
bool IsM2Hour(int hour){ return (hour==8 || hour==13); }

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
      req.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?
                ORDER_TYPE_SELL:ORDER_TYPE_BUY;
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
   double sl_dist = MathAbs(price - sl);
   double lot = CalcLotM2(sl_dist);
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
      Print("M2 OPEN ",((dir==1)?"BUY":"SELL")," lot=",lot);
   } else { Print("M2 FAIL retcode=",res.retcode); }
   g_m2_pendingDir=0;
}

void RunMotor2(double bid, double ask, datetime now)
{
   if(!Use_Motor2) return;
   if(M2_HasPosition() && g_m2_openTime>0){
      if((int)(now-g_m2_openTime)>=M2_MaxHold_Sec){
         M2_ClosePosition(); g_m2_openTime=0; g_m2_pendingDir=0;
      }
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
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double breakH = rH + M2_Breakout_Pts;
      double breakL = rL - M2_Breakout_Pts;
      if(closeNow >= breakH){
         g_m2_pendingDir=1; g_m2_pendingSL=closeNow-M2_SL_Pts; g_m2_pendingTP=closeNow+M2_TP_Pts;
      } else if(closeNow <= breakL){
         g_m2_pendingDir=-1; g_m2_pendingSL=closeNow+M2_SL_Pts; g_m2_pendingTP=closeNow-M2_TP_Pts;
      }
      return;
   }
   if(g_m2_pendingDir==0) return;
   if(M2_HasPosition()){ g_m2_pendingDir=0; return; }
   MqlDateTime dt2; TimeToStruct(now,dt2);
   if(!IsM2Hour(dt2.hour)){ g_m2_pendingDir=0; return; }
   if(g_m2_pendingDir==1) M2_OpenTrade(1, ask, g_m2_pendingSL, g_m2_pendingTP);
   else if(g_m2_pendingDir==-1) M2_OpenTrade(-1, bid, g_m2_pendingSL, g_m2_pendingTP);
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
   double profit  = HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal,DEAL_COMMENT);
   if(StringFind(comment,"partial")>=0) return;
   bool was_hardcap = (StringFind(comment,"HardCap")>=0);

   datetime open_t = (datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   MqlDateTime dt; TimeToStruct(open_t, dt);
   double hold_sec = 0;
   for(int i=0;i<2;i++){
      if(g_states[i].entry>0){
         hold_sec = (double)(open_t - g_states[i].openTime);
         RecordTrade(dt.hour, g_states[i].slDist, profit, hold_sec, was_hardcap);
         g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
         g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
         g_states[i].timeTrailDone=false; g_states[i].openTime=0;
         break;
      }
   }
   if(hold_sec == 0) RecordTrade(dt.hour, SL_Min, profit, 0, was_hardcap);

   bool is_win = (profit > 0);
   UpdateStreakScale(is_win);
   UpdateWRTracker(is_win);
   UpdateDailyRegime(profit);
   UpdateBalanceTrail(AccountInfoDouble(ACCOUNT_BALANCE));
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
   Print("MM7 v17.83 | ",g_sym,
         " | M1:SELL H2,7,15,22 | M2:Breakout H8,13",
         " | HardCap=$",Hard_Loss_Cap_USD,
         " | Trail_Start=",Trail_Start_Pts,"pts Phase1=",Trail_Dist_Phase1,"pts",
         " | Partial@$",Partial_USD_Trigger,"x",Partial_Close_Pct*100,"%",
         " | Learn_Min=",Learn_Min_Samples,
         " | Bear ",Bear_Bars,"b/",Bear_Drop_Pts,"pts→lot×",Bear_Lot_Scale,
         " | TimeTrail=",Time_Trail_Sec/60,"min");
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

   RunMotor2(bid, ask, now);

   // GESTIÓN POSICIONES
   ulong tks[]; int npos=(int)GetTickets(tks);
   for(int pi=0;pi<npos;pi++){
      ulong tk=tks[pi];
      if(!PositionSelectByTicket(tk)) continue;
      double entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double favorable= entry - ask;
      int si=-1;
      for(int i=0;i<2;i++){
         if(MathAbs(g_states[i].entry-entry)<0.01&&g_states[i].entry>0){si=i;break;}
      }
      if(si<0){
         for(int i=0;i<2;i++){
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

      // 1. HARD LOSS CAP (FIX 2: $9)
      if(Use_Hard_Loss_Cap && PositionSelectByTicket(tk)){
         double pnl = PositionGetDouble(POSITION_PROFIT);
         if(pnl < -Hard_Loss_Cap_USD){
            ClosePosition(tk,"HardCap");
            if(Use_HardCap_Cooldown) g_hardcap_cooldown = HardCap_Cooldown_Bars;
            Print("MM7 HARD CAP pnl=",DoubleToString(pnl,2));
            continue;
         }
      }

      // 2. PARTIAL CLOSE (FIX 6: $5, 50%)
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

      // 3. TRAILING (FIX 3+4: Trail_Start=4.0, Phase1=16pts)
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

      // 4. TIME TRAIL (FIX 5: 90min → mover a BE si no avanzó)
      if(Use_Time_Trail&&!g_states[si].timeTrailDone&&g_states[si].openTime>0){
         if((now-g_states[si].openTime)>=Time_Trail_Sec){
            if(favorable<slD*Trail_Progress_Pct){
               if(PositionSelectByTicket(tk)){
                  double ctp=PositionGetDouble(POSITION_TP);
                  double csl=PositionGetDouble(POSITION_SL);
                  int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
                  double nsl=NormalizeDouble(entry,digs);
                  if(nsl<csl) SetSLTP(tk, nsl, ctp);
                  Print("MM7 TIME_TRAIL: movido a BE tras ",Time_Trail_Sec/60,"min");
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
      if(g_hardcap_cooldown > 0){ g_hardcap_cooldown--; return; }
      if(g_pauseBarsLeft>0){g_pauseBarsLeft--;return;}

      UpdateBearDetector(); // FIX 7
      UpdateRegime();

      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsGoodHour(dt.hour)) return;

      double cv2=iClose(g_sym,_Period,Vel_Bars+1), cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>g_vel_threshold) return;

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

   if(g_hardcap_cooldown > 0) return;
   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0) return;
   MqlDateTime dt; TimeToStruct(now,dt);
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
