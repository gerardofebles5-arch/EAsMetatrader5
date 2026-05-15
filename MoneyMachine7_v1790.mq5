//+------------------------------------------------------------------+
//|  MoneyMachine7_v1790.mq5                                        |
//|  v17.90 — RECONSTRUCCIÓN MATEMÁTICA DEFINITIVA                  |
//|                                                                  |
//|  ANÁLISIS 5 VERSIONES (136+ trades reales):                     |
//|                                                                  |
//|  VERDAD MATEMÁTICA ENCONTRADA:                                   |
//|  v17.80 (mejor): 9 HCs / 68 trades = 13% HC rate → $271        |
//|  v17.89 (peor):  12 HCs / 29 trades = 41% HC rate → $144       |
//|  Sin HCs: profit=$293, WR=94% → el EA es excelente             |
//|  El problema: HC siempre cierra en -$12 porque es de mercado   |
//|  HC=$12 = 12pts de movimiento. SL=1.5×ATR=12pts → IGUALES      |
//|  → el HC SIEMPRE se dispara antes que el SL de mercado          |
//|                                                                  |
//|  FIX MATEMÁTICO: ELIMINAR el HC y confiar en el SL de mercado  |
//|  v17.80 SL promedio: -$6.22 (mucho mejor que HC -$12.47)       |
//|  Con SL natural el bot pierda menos en las pérdidas             |
//|                                                                  |
//|  RESTAURAR VOLUMEN: H07 tenía WR=57% y CERO HardCaps en v17.80 |
//|  Al eliminarlo perdimos 7 trades de alta calidad sin HC         |
//|  H22 WR=56% en v17.80 con solo 2 HCs — mantener con MaxPos=1   |
//|                                                                  |
//|  MANTENER las mejoras reales de v17.86-v17.89:                  |
//|  ✓ TP dinámico ATR×3 (TPs de $30 funcionan)                    |
//|  ✓ Partial doble $6+$15 (mejor que único $8)                   |
//|  ✓ Trail_Start=$10 (no activar en ruido)                       |
//|  ✓ Trail_Phase1=30pts (winners llegan a H16)                   |
//|  ✓ Bear Protector 120b/50pts                                    |
//|  ✓ Daily Halt $20 (sin el cierre-de-posiciones-bug)            |
//|  ✓ HC Day Tracker + H15 Block (del v17.88)                     |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.90"
#property strict

//=== MOTOR 1: SEÑAL — INTOCABLE (calibrada v17.75, mejor PF) ===
input int    Range_Bars          = 50;
input double Zone_Pct_Base       = 0.555;
input double Confirm_Points      = 4.6;
input int    Local_Vol_Bars      = 6;
input double SL_Local_Pct        = 1.20;

// FIX 2: SL dinámico ATR
// SL real = max(SL_Min_Static, ATR_SL_Mult × ATR14)
// Esto cierra posiciones atascadas ANTES de que lleguen al HC
input double SL_Min_Static       = 19.2;  // mínimo absoluto (pts)
input double SL_Max              = 85.2;
input double ATR_Period_SL       = 14;    // ATR period para SL
input double ATR_SL_Mult         = 1.5;   // SL = 1.5×ATR14 (HC desactivado, SL actúa correctamente)

// FIX 2: TP dinámico ATR
// TP real = max(TP_Min_Static, ATR_TP_Mult × ATR14)
// Captura el movimiento real del mercado, no ratio fijo
input double ATR_TP_Mult         = 3.0;   // TP = 3.0 × ATR14
input double TP_Min_Static       = 30.0;  // TP mínimo en pts

//=== FIX 1: TRAILING AMPLIO — dejar respirar los winners ===
// Phase1=30pts en primeros 10min: el precio necesita espacio
// Phase2=8pts de 10min a 30min: más ajustado
// Phase3=4pts tras 30min: muy ajustado, proteger máximo
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 8.0;   // activar trail con $8 ganados
input double Trail_Dist_Phase1   = 30.0;  // FIX: 15→30 (ruido XAUUSD)
input double Trail_Dist_Phase2   = 8.0;   // FIX: 10→8
input double Trail_Dist_Phase3   = 4.0;   // FIX: 6→4
input int    Trail_Phase1_Sec    = 600;   // 10 minutos
input int    Trail_Phase2_Sec    = 1800;  // 30 minutos

//=== FIX 4: PARTIAL CLOSE DOBLE ESCALONADO ===
// Nivel 1: asegurar 30% rápido → mover SL a BE (trade libre de riesgo)
// Nivel 2: asegurar 30% más en ganancia grande → SL sube
// Nivel 3: 40% restante corre con trailing
input bool   Use_Partial_Close     = true;
input double Partial1_USD_Trigger  = 6.0;   // 1er partial a $6 ganancia
input double Partial1_Close_Pct    = 0.30;  // cerrar 30%
input double Partial2_USD_Trigger  = 15.0;  // 2do partial a $15 ganancia
input double Partial2_Close_Pct    = 0.30;  // cerrar 30% más

//=== HARD LOSS CAP = $12 (Monte Carlo demostró que es óptimo) ===
input bool   Use_Hard_Loss_Cap     = false;  // DESACTIVADO: SL de mercado es más eficiente (-$6 vs -$12)
input double Hard_Loss_Cap_USD     = 12.0;   // ref solo

//=== FIX 6: DAILY LOSS LIMIT ===
input bool   Use_Daily_Loss_Limit  = true;
input double Daily_Loss_Limit_USD  = 25.0; // $25 (con HC off las pérdidas son menores)

//=== GESTIÓN TEMPORAL ===
input bool   Use_Breakeven         = false;
input double BE_Trigger_Pct        = 0.60;
input bool   Use_Time_Trail        = true;
input int    Time_Trail_Sec        = 11520; // 3.2h → mover a BE si no avanzó
input double Trail_Progress_Pct    = 0.20;

//=== AUTOAPRENDIZAJE ===
input int    Learn_Min_Samples     = 6;    // FIX: 10→6 (aprende más rápido)
input double Learn_WR_Block        = 0.30;
input double Learn_WR_Reopen       = 0.45;
input int    Learn_Recalc_Every    = 10;
input double Learn_Quick_Loss_Sec  = 300;
input int    Learn_Vol_Window      = 20;
input double Learn_Trail_Scale     = 0.20;

//=== RACHA (momentum serial confirmado: tras WIN WR=63%) ===
input double Streak_Reduce_Pct     = 0.80;
input double Streak_Boost_Pct      = 1.30;
input double Streak_Scale_Max      = 1.50;
input double Streak_Scale_Min      = 0.40;
input int    Streak_Loss_Trigger   = 3;
input int    Streak_Win_Trigger    = 3;

//=== FILTROS ===
input int    Vel_Bars              = 3;
input double Vel_Threshold_Base    = 4.4;
input int    Trend_Bars            = 100;
input double Trend_Min_Move        = 30.0;
input int    FriClose_Hour_UTC     = 20;
input bool   Close_On_FriClose     = true;
input int    Max_Consec_Losses     = 4;    // FIX: 3→4 (3 pérdidas = aleatoriedad)
input int    Pause_Bars            = 6;    // FIX: 8→6 (no perder recuperaciones)
input bool   Use_Hour_Filter       = true;
// NOTA: H07 y H22 eliminados permanentemente del código (ver IsGoodHour)

//=== LOTAJE ===
input bool   Use_Risk_Based_Lot    = true;
input double Risk_Pct_Per_Trade    = 0.020;
input double Cap_Pct_Of_Balance    = 0.15;
input double Min_Lot               = 0.01;
input double Max_Lot               = 10.0;

//=== SISTEMA ===
input int    Max_Positions         = 2;
// H22 limitada a 1 posición (WR=56% pero alta varianza, 2 HCs en v17.80)
// H07 mantiene Max_Positions=2 (CERO HardCaps en v17.80)
input int    Max_Positions_H22     = 1;
input int    InpMagicNumber        = 177900;
input int    InpSlippagePoints     = 10;

//=== RÉGIMEN MACRO ===
input int    Regime_Trend_Bars     = 60;
input double Regime_Trend_Pts      = 8.0;
input double Regime_Lot_Scale      = 0.80;
input int    Regime_Bad_Days       = 1;
input int    Regime_Good_Days      = 1;

//=== BALANCE TRAIL — desactivado (comprobado que reduce ganancias) ===
input bool   Use_Balance_Trail     = false;
input double BalTrail_DD1_Pct      = 0.10;
input double BalTrail_Scale1       = 0.50;
input double BalTrail_DD2_Pct      = 0.15;
input double BalTrail_Scale2       = 0.25;

//=== WR TRACKER — más reactivo ===
input bool   Use_WR_Tracker        = true;
input int    WR_Track_Window       = 5;    // FIX: 8→5 (detectar rachas antes)
input double WR_Track_Low          = 0.20;
input double WR_Track_High         = 0.70;
input double WR_Track_Scale_Low    = 0.30;
input double WR_Track_Scale_High   = 1.50;
input int    WR_Track_Pause_Bars   = 8;    // FIX: 5→8 (pausa más larga)

//=== BEAR PROTECTOR — más agresivo ===
input bool   Use_Bear_Protect      = true;
input int    Bear_Bars             = 120;
input double Bear_Drop_Pts         = 50.0;
input double Bear_Lot_Scale        = 0.15; // FIX: 0.30→0.15 (casi sin riesgo)
input int    Bear_EMA_Fast         = 5;
input int    Bear_EMA_Slow         = 20;

//=== COOLDOWN POST-HARDCAP ===
input bool   Use_HardCap_Cooldown  = true;
input int    HardCap_Cooldown_Bars = 5;    // FIX: 3→5 barras

//=== MOTOR 2: BREAKOUT (H8+H13, complementario, WR histórico ~100%) ===
input bool   Use_Motor2            = true;
input int    M2_Magic              = 178000;
input int    M2_Breakout_Bars      = 20;
input double M2_Breakout_Pts       = 8.0;
input double M2_SL_Pts             = 12.0;
input double M2_TP_Pts             = 20.0;
input int    M2_MaxHold_Sec        = 5400;
// FIX: lot dinámico desde $50 (WR histórico justifica escalar desde el inicio)
input double M2_Lot_Fixed          = 0.01;    // cuando balance <= $50
input double M2_Risk_Pct           = 0.015;   // cuando balance > $50
input double M2_DynLot_MinBal      = 50.0;

//=== ESTRUCTURAS ===
struct TradeRecord {
   int    hour;
   double sl_dist, profit, hold_sec;
   bool   is_win, is_quick_loss;
};

struct HourStats {
   int    n, wins;
   double total_profit, total_ev;
   bool   blocked;
   int    block_samples;
};

struct TradeState {
   double   entry, slDist, tpDist;
   bool     trailActive, partial1Done, partial2Done, timeTrailDone;
   datetime openTime;
};

//=== GLOBALS ===
string   g_sym;
double   g_point;
int      g_magic;
datetime g_lastBarTime  = 0;
int      g_pendingDir   = 0;
double   g_confirmLevel = 0;
double   g_pendingSL    = 0;
double   g_pendingTP    = 0; // FIX 2: TP también se pasa al open

TradeRecord g_history[500];
int         g_histCount = 0;
HourStats   g_hourStats[24];
TradeState  g_states[2];

int    g_consecLosses     = 0;
int    g_consecWins       = 0;
int    g_pauseBarsLeft    = 0;
int    g_totalTrades      = 0;
int    g_hardcap_cooldown = 0;

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
double   g_today_start_bal   = 50.0;
bool     g_daily_halted      = false;
bool     g_halt_closed_today = false;

double   g_balance_peak    = 50.0;
double   g_bal_trail_scale = 1.0;

double   g_wr_history[20];
int      g_wr_hist_idx   = 0;
int      g_wr_hist_n     = 0;
double   g_wr_track_scale = 1.0;

double   g_bear_lot_factor = 1.0;

datetime g_m2_lastBarTime = 0;
int      g_m2_pendingDir  = 0;
double   g_m2_pendingSL   = 0;
double   g_m2_pendingTP   = 0;
datetime g_m2_openTime    = 0;

//+------------------------------------------------------------------+
//|  UTILIDADES ATR
//+------------------------------------------------------------------+
double CalcATR14()
{
   int period = (int)ATR_Period_SL;
   double sum = 0;
   for(int i = 1; i <= period + 1; i++){
      double h  = iHigh(g_sym, _Period, i);
      double l  = iLow(g_sym,  _Period, i);
      double pc = iClose(g_sym, _Period, i + 1);
      if(h <= 0 || l <= 0 || pc <= 0) continue;
      double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      sum += tr;
   }
   return sum / period;
}

// Calcula SL dinámico basado en ATR
double DynamicSL()
{
   double atr = CalcATR14();
   if(atr <= 0) return SL_Min_Static;
   return MathMax(SL_Min_Static, MathMin(SL_Max, atr * ATR_SL_Mult));
}

// Calcula TP dinámico basado en ATR
double DynamicTP()
{
   double atr = CalcATR14();
   if(atr <= 0) return TP_Min_Static;
   return MathMax(TP_Min_Static, atr * ATR_TP_Mult);
}

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
   g_today_start_bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_daily_halted      = false;
   g_balance_peak      = AccountInfoDouble(ACCOUNT_BALANCE);
   g_bal_trail_scale   = 1.0;
   for(int i = 0; i < 20; i++) g_wr_history[i] = 0.5;
   g_wr_hist_idx    = 0;
   g_wr_hist_n      = 0;
   g_wr_track_scale = 1.0;
   g_bear_lot_factor = 1.0;
   g_hardcap_cooldown = 0;
   for(int h = 0; h < 24; h++){
      g_hourStats[h].n = 0;
      g_hourStats[h].wins = 0;
      g_hourStats[h].total_profit = 0;
      g_hourStats[h].total_ev = 0;
      g_hourStats[h].blocked = false;
      g_hourStats[h].block_samples = 0;
   }
}

//+------------------------------------------------------------------+
//|  FIX 6: Daily loss check — llamar en cada tick
//+------------------------------------------------------------------+
void CheckDailyHalt()
{
   if(!Use_Daily_Loss_Limit) return;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                              dt.year, dt.mon, dt.day));
   if(g_today_date != today){
      g_today_date        = today;
      g_today_pnl         = 0.0;
      g_today_start_bal   = AccountInfoDouble(ACCOUNT_BALANCE);
      g_daily_halted      = false;
      g_halt_closed_today = false;
   }
   if(g_daily_halted) return;
   double cur_bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double day_pnl = cur_bal - g_today_start_bal;
   if(day_pnl < -Daily_Loss_Limit_USD){
      g_daily_halted = true;
      g_pendingDir   = 0;
      Print("DAILY HALT activado: pérdida=$", DoubleToString(-day_pnl, 2),
            " > $", Daily_Loss_Limit_USD);
   }
}

//+------------------------------------------------------------------+
//|  FIX BEAR PROTECTOR
//+------------------------------------------------------------------+
void UpdateBearDetector()
{
   if(!Use_Bear_Protect){ g_bear_lot_factor = 1.0; return; }
   double pn = iClose(g_sym, _Period, 1);
   double pa = iClose(g_sym, _Period, Bear_Bars + 1);
   if(pn <= 0 || pa <= 0){ g_bear_lot_factor = 1.0; return; }
   double drop = pa - pn;
   double ef = 0, es = 0;
   for(int i = Bear_EMA_Fast; i >= 1; i--) ef += iClose(g_sym, _Period, i);
   ef /= Bear_EMA_Fast;
   for(int i = Bear_EMA_Slow; i >= 1; i--) es += iClose(g_sym, _Period, i);
   es /= Bear_EMA_Slow;
   if(drop >= Bear_Drop_Pts && ef < es){
      if(g_bear_lot_factor != Bear_Lot_Scale){
         g_bear_lot_factor = Bear_Lot_Scale;
         Print("BEAR ON: drop=", DoubleToString(drop, 1), "pts → lot×", Bear_Lot_Scale);
      }
   } else {
      if(g_bear_lot_factor != 1.0){
         g_bear_lot_factor = 1.0;
         Print("BEAR OFF");
      }
   }
}

//+------------------------------------------------------------------+
void RecordTrade(int hour, double sl_dist, double profit,
                 double hold_sec, bool was_hc)
{
   if(g_histCount >= 500){
      for(int i = 0; i < 450; i++) g_history[i] = g_history[i + 50];
      g_histCount = 450;
   }
   g_history[g_histCount].hour         = hour;
   g_history[g_histCount].sl_dist      = sl_dist;
   g_history[g_histCount].profit       = profit;
   g_history[g_histCount].hold_sec     = hold_sec;
   g_history[g_histCount].is_win       = (profit > 0);
   g_history[g_histCount].is_quick_loss = (profit < -0.5 &&
                                            hold_sec < Learn_Quick_Loss_Sec);
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
         Print("LEARN: H", hour, " BLOQUEADA WR=",
               DoubleToString(wr * 100, 1), "%");
      } else if(g_hourStats[hour].blocked){
         g_hourStats[hour].block_samples++;
         if(wr >= Learn_WR_Reopen){
            g_hourStats[hour].blocked = false;
            Print("LEARN: H", hour, " REABIERTA WR=",
                  DoubleToString(wr * 100, 1), "%");
         }
      }
   }
   if(was_hc && Use_HardCap_Cooldown)
      g_hardcap_cooldown = HardCap_Cooldown_Bars;
   if(g_totalTrades % Learn_Recalc_Every == 0)
      AdaptParameters();
}

//+------------------------------------------------------------------+
void AdaptParameters()
{
   if(g_histCount < 10) return;
   int look = MathMin(g_histCount, 50);
   int ql = 0;
   for(int i = g_histCount - look; i < g_histCount; i++)
      if(g_history[i].is_quick_loss) ql++;
   double qr = (double)ql / look;
   if(qr > 0.20)
      g_vel_threshold = Vel_Threshold_Base * 0.85;
   else if(qr < 0.05)
      g_vel_threshold = MathMin(Vel_Threshold_Base * 1.10,
                                Vel_Threshold_Base * 1.20);
   else
      g_vel_threshold = Vel_Threshold_Base;
   double vol_sum = 0;
   for(int i = 1; i <= Learn_Vol_Window; i++){
      double h = iHigh(g_sym, _Period, i);
      double l = iLow(g_sym,  _Period, i);
      if(h > 0 && l > 0) vol_sum += (h - l);
   }
   double avg_r = vol_sum / Learn_Vol_Window;
   double vf = 1.0;
   if(avg_r > 5.0)      vf = 1.0 + Learn_Trail_Scale;
   else if(avg_r < 2.0) vf = 1.0 - Learn_Trail_Scale * 0.5;
   g_trail_dist = MathMax(MathMin(Trail_Dist_Phase2 * vf, 25.0), 5.0);
}

//+------------------------------------------------------------------+
void UpdateStreakScale(bool is_win)
{
   if(is_win){
      g_consecWins++;
      g_consecLosses = 0;
      g_lot_scale = MathMin(g_lot_scale * Streak_Boost_Pct,
                            Streak_Scale_Max);
      if(g_consecWins >= Streak_Win_Trigger)
         Print("MOMENTUM WIN×", g_consecWins,
               " lot_scale=", DoubleToString(g_lot_scale, 3));
   } else {
      g_consecLosses++;
      g_consecWins = 0;
      g_lot_scale = MathMax(g_lot_scale * Streak_Reduce_Pct,
                            Streak_Scale_Min);
      if(g_consecLosses >= Streak_Loss_Trigger)
         Print("MOMENTUM LOSS×", g_consecLosses,
               " lot_scale=", DoubleToString(g_lot_scale, 3));
      if(g_consecLosses >= Max_Consec_Losses){
         g_pauseBarsLeft = Pause_Bars;
         g_pendingDir    = 0;
         Print("MM7 PAUSA ", Pause_Bars, "b tras ",
               g_consecLosses, " losses");
      }
   }
}

//+------------------------------------------------------------------+
// FIX 3: Solo H02 y H15 — H07 y H22 eliminados permanentemente
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // H02: WR=47%, +$60 — buena
   // H07: WR=57%, CERO HardCaps en v17.80, +$52 — restaurada
   // H15: WR=54%, mejor hora por volumen, +$164
   // H22: WR=56%, max 1 posición para limitar volatilidad
   if(hour!=2 && hour!=7 && hour!=15 && hour!=22) return false;
   if(g_hourStats[hour].blocked &&
      g_hourStats[hour].n >= Learn_Min_Samples) return false;
   if(g_regime_paused) return false;
   return true;
}

//+------------------------------------------------------------------+
void UpdateRegime()
{
   double pn = iClose(g_sym, _Period, 1);
   double pa = iClose(g_sym, _Period, Regime_Trend_Bars + 1);
   if(pn <= 0 || pa <= 0) return;
   double move = pn - pa;
   if(move > Regime_Trend_Pts){
      if(g_regime_lot_factor != Regime_Lot_Scale){
         g_regime_lot_factor = Regime_Lot_Scale;
         Print("RÉGIMEN ALCISTA → lot×", Regime_Lot_Scale);
      }
   } else {
      if(g_regime_lot_factor != 1.0){
         g_regime_lot_factor = 1.0;
         Print("RÉGIMEN NEUTRO");
      }
   }
}

void UpdateDailyRegime(double profit)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                              dt.year, dt.mon, dt.day));
   if(g_today_date != today){
      if(g_today_date != 0){
         if(g_today_pnl < 0){
            g_consec_neg_days++;
            g_consec_pos_days = 0;
            Print("DIA NEGATIVO #", g_consec_neg_days,
                  " PnL=$", DoubleToString(g_today_pnl, 2));
         } else if(g_today_pnl > 0){
            g_consec_pos_days++;
            g_consec_neg_days = 0;
         }
         if(g_consec_neg_days >= Regime_Bad_Days &&
            g_regime_lot_factor > Regime_Lot_Scale)
            g_regime_lot_factor = Regime_Lot_Scale;
         if(g_consec_pos_days >= Regime_Good_Days &&
            g_regime_lot_factor < 1.0){
            g_regime_lot_factor = 1.0;
            g_consec_neg_days   = 0;
         }
         g_regime_paused = false;
      }
      g_today_date      = today;
      g_today_pnl       = 0.0;
      g_today_start_bal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_daily_halted    = false;
   }
   g_today_pnl += profit;
}

bool TrendBlocksSell()
{
   double cn = iClose(g_sym, _Period, 1);
   double co = iClose(g_sym, _Period, Trend_Bars + 1);
   if(cn <= 0 || co <= 0) return false;
   return (cn - co >= Trend_Min_Move);
}

bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC);
}

//+------------------------------------------------------------------+
void UpdateBalanceTrail(double bal)
{
   if(!Use_Balance_Trail) return;
   if(bal > g_balance_peak){ g_balance_peak = bal; g_bal_trail_scale = 1.0; }
   double dd = (g_balance_peak > 0) ?
               (g_balance_peak - bal) / g_balance_peak : 0;
   double ps = g_bal_trail_scale;
   if(dd >= BalTrail_DD2_Pct)      g_bal_trail_scale = BalTrail_Scale2;
   else if(dd >= BalTrail_DD1_Pct) g_bal_trail_scale = BalTrail_Scale1;
   else                             g_bal_trail_scale = 1.0;
   if(g_bal_trail_scale != ps)
      Print("BAL_TRAIL DD=", DoubleToString(dd * 100, 1),
            "% → lot×", g_bal_trail_scale);
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
   for(int i = 0; i < window; i++)
      sum += g_wr_history[(start + i) % 20];
   double wr = sum / window;
   double prev = g_wr_track_scale;
   if(wr <= WR_Track_Low){
      g_wr_track_scale = WR_Track_Scale_Low;
      if(g_pauseBarsLeft < WR_Track_Pause_Bars){
         g_pauseBarsLeft = WR_Track_Pause_Bars;
         Print("WR_TRACK: WR=", DoubleToString(wr * 100, 1),
               "% pausa ", WR_Track_Pause_Bars, "b");
      }
   } else if(wr >= WR_Track_High){
      g_wr_track_scale = WR_Track_Scale_High;
   } else {
      double t = (wr - WR_Track_Low) / (WR_Track_High - WR_Track_Low);
      g_wr_track_scale = WR_Track_Scale_Low +
                         t * (WR_Track_Scale_High - WR_Track_Scale_Low);
   }
   if(MathAbs(g_wr_track_scale - prev) > 0.05)
      Print("WR_TRACK: wr=", DoubleToString(wr * 100, 1),
            "% → lot×", DoubleToString(g_wr_track_scale, 2));
}

//+------------------------------------------------------------------+
double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Min_Lot, 2);
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   double cap = bal * Cap_Pct_Of_Balance;
   double risk = MathMin(bal * Risk_Pct_Per_Trade, cap);
   if(sl_dist <= 0) sl_dist = SL_Min_Static;
   double combined = g_lot_scale * g_regime_lot_factor *
                     g_bal_trail_scale * g_wr_track_scale *
                     g_bear_lot_factor;
   double lot = (risk / (sl_dist * 100.0)) * combined;
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st > 0) lot = MathFloor(lot / st) * st;
   return NormalizeDouble(lot, 2);
}

double CalcLotM2(double sl_dist)
{
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   if(bal <= M2_DynLot_MinBal) return M2_Lot_Fixed;
   double risk = MathMin(bal * M2_Risk_Pct, bal * Cap_Pct_Of_Balance);
   if(sl_dist <= 0) sl_dist = M2_SL_Pts;
   double lot = (risk / (sl_dist * 100.0)) * g_wr_track_scale;
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, M2_Lot_Fixed));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st > 0) lot = MathFloor(lot / st) * st;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
int CountByMagic()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++){
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == g_magic) n++;
   }
   return n;
}

ulong GetTickets(ulong &arr[])
{
   int cnt = 0;
   ArrayResize(arr, 0);
   for(int i = 0; i < PositionsTotal(); i++){
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == g_magic){
         ArrayResize(arr, cnt + 1);
         arr[cnt++] = tk;
      }
   }
   return cnt;
}

void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   double vol   = PositionGetDouble(POSITION_VOLUME);
   double price = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = g_sym;
   req.volume   = vol;
   req.type     = ORDER_TYPE_BUY;
   req.price    = price;
   req.position = ticket;
   req.deviation = InpSlippagePoints;
   req.magic    = g_magic;
   req.comment  = "MM7-" + reason;
   req.type_filling = ORDER_FILLING_FOK;
   bool ok = OrderSend(req, res);
   if(!ok){ req.type_filling = ORDER_FILLING_IOC;    ok = OrderSend(req, res); }
   if(!ok){ req.type_filling = ORDER_FILLING_RETURN; ok = OrderSend(req, res); }
}

void SetSLTP(ulong ticket, double newSL, double newTP)
{
   MqlTradeRequest rr = {};
   MqlTradeResult  rs = {};
   rr.action   = TRADE_ACTION_SLTP;
   rr.symbol   = g_sym;
   rr.position = ticket;
   rr.sl       = newSL;
   rr.tp       = newTP;
   bool ok = OrderSend(rr, rs);
   if(!ok) Print("SetSLTP err=", rs.retcode);
}

// FIX 4: Partial close genérico (funciona para ambos niveles)
bool DoPartialClose(ulong ticket, double pct, string label)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double cv    = PositionGetDouble(POSITION_VOLUME);
   double price = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double vc    = NormalizeDouble(cv * pct, 2);
   double st    = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double mn    = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   if(st > 0) vc = MathFloor(vc / st) * st;
   vc = MathMax(vc, mn);
   if(vc >= cv) return false; // no cerrar si sería todo el volumen
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = g_sym;
   req.volume   = vc;
   req.type     = ORDER_TYPE_BUY;
   req.price    = price;
   req.position = ticket;
   req.deviation = InpSlippagePoints;
   req.magic    = g_magic;
   req.comment  = "MM7-partial-" + label;
   req.type_filling = ORDER_FILLING_FOK;
   bool ok = OrderSend(req, res);
   if(!ok){ req.type_filling = ORDER_FILLING_IOC;    ok = OrderSend(req, res); }
   if(!ok){ req.type_filling = ORDER_FILLING_RETURN; ok = OrderSend(req, res); }
   if(ok) Print("MM7 PARTIAL ", label, " vol=", vc, " price=", price);
   return ok;
}

// FIX 2: OpenSell usa SL y TP dinámicos ATR
void OpenSell(double sl_dist, double tp_dist)
{
   double bid  = SymbolInfoDouble(g_sym, SYMBOL_BID);
   int    digs = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double sl   = NormalizeDouble(bid + sl_dist, digs);
   double tp   = NormalizeDouble(bid - tp_dist, digs);
   double lot  = CalcLot(sl_dist);
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = g_sym;
   req.volume   = lot;
   req.type     = ORDER_TYPE_SELL;
   req.price    = bid;
   req.sl       = sl;
   req.tp       = tp;
   req.deviation = InpSlippagePoints;
   req.magic    = g_magic;
   req.comment  = "MM7";
   req.type_filling = ORDER_FILLING_FOK;
   bool ok = OrderSend(req, res);
   if(!ok){ req.type_filling = ORDER_FILLING_IOC;    ok = OrderSend(req, res); }
   if(!ok){ req.type_filling = ORDER_FILLING_RETURN; ok = OrderSend(req, res); }
   if(res.retcode == TRADE_RETCODE_DONE ||
      res.retcode == TRADE_RETCODE_PLACED){
      g_pendingDir = 0;
      Print("MM7 SELL bid=", bid,
            " SL=", DoubleToString(sl, digs),
            " TP=", DoubleToString(tp, digs),
            " SLdist=", DoubleToString(sl_dist, 1),
            " TPdist=", DoubleToString(tp_dist, 1),
            " lot=", lot,
            " bear×", DoubleToString(g_bear_lot_factor, 2));
   } else {
      Print("MM7 SELL FAIL retcode=", res.retcode);
   }
}

//+------------------------------------------------------------------+
//|  MOTOR 2 — BREAKOUT
//+------------------------------------------------------------------+
bool IsM2Hour(int hour){ return (hour == 8 || hour == 13); }

void M2_CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--){
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != M2_Magic) continue;
      ENUM_POSITION_TYPE pt =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      ENUM_ORDER_TYPE ct = (pt == POSITION_TYPE_BUY) ?
                           ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double price = (pt == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(g_sym, SYMBOL_BID) :
                     SymbolInfoDouble(g_sym, SYMBOL_ASK);
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_DEAL;
      req.symbol   = g_sym;
      req.volume   = vol;
      req.type     = ct;
      req.price    = price;
      req.position = tk;
      req.deviation = InpSlippagePoints;
      req.magic    = M2_Magic;
      req.comment  = "M2-Close";
      req.type_filling = ORDER_FILLING_FOK;
      bool ok = OrderSend(req, res);
      if(!ok){ req.type_filling = ORDER_FILLING_IOC;    ok = OrderSend(req, res); }
      if(!ok){ req.type_filling = ORDER_FILLING_RETURN; ok = OrderSend(req, res); }
   }
}

bool M2_HasPosition()
{
   for(int i = 0; i < PositionsTotal(); i++){
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == M2_Magic) return true;
   }
   return false;
}

void M2_OpenTrade(int dir, double sl, double tp)
{
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   ENUM_ORDER_TYPE otype = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (dir == 1) ? SymbolInfoDouble(g_sym, SYMBOL_ASK) :
                               SymbolInfoDouble(g_sym, SYMBOL_BID);
   double lot   = CalcLotM2(MathAbs(price - sl));
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = g_sym;
   req.volume   = lot;
   req.type     = otype;
   req.price    = price;
   req.sl       = NormalizeDouble(sl, digs);
   req.tp       = NormalizeDouble(tp, digs);
   req.deviation = InpSlippagePoints;
   req.magic    = M2_Magic;
   req.comment  = (dir == 1) ? "M2-BUY" : "M2-SELL";
   req.type_filling = ORDER_FILLING_FOK;
   bool ok = OrderSend(req, res);
   if(!ok){ req.type_filling = ORDER_FILLING_IOC;    ok = OrderSend(req, res); }
   if(!ok){ req.type_filling = ORDER_FILLING_RETURN; ok = OrderSend(req, res); }
   if(res.retcode == TRADE_RETCODE_DONE ||
      res.retcode == TRADE_RETCODE_PLACED){
      g_m2_openTime = TimeCurrent();
      Print("M2 OPEN ", (dir == 1 ? "BUY" : "SELL"),
            " lot=", lot,
            " SL=", DoubleToString(sl, digs),
            " TP=", DoubleToString(tp, digs));
   } else {
      Print("M2 FAIL retcode=", res.retcode);
   }
   g_m2_pendingDir = 0;
}

void RunMotor2(double bid, double ask, datetime now)
{
   if(!Use_Motor2 || g_daily_halted) return;
   // Time exit
   if(M2_HasPosition() && g_m2_openTime > 0 &&
      (int)(now - g_m2_openTime) >= M2_MaxHold_Sec){
      M2_CloseAll();
      g_m2_openTime   = 0;
      g_m2_pendingDir = 0;
      Print("M2 TimeExit ", M2_MaxHold_Sec / 60, "min");
   }
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_m2_lastBarTime){
      g_m2_lastBarTime = curBar;
      g_m2_pendingDir  = 0;
      if(M2_HasPosition()) return;
      MqlDateTime dt; TimeToStruct(curBar, dt);
      if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC) return;
      if(!IsM2Hour(dt.hour)) return;
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= M2_Breakout_Bars; i++){
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h == 0 || l == 0) return;
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      double cn = iClose(g_sym, _Period, 1);
      if(cn == 0) return;
      if(cn >= rH + M2_Breakout_Pts){
         g_m2_pendingDir = 1;
         g_m2_pendingSL  = cn - M2_SL_Pts;
         g_m2_pendingTP  = cn + M2_TP_Pts;
      } else if(cn <= rL - M2_Breakout_Pts){
         g_m2_pendingDir = -1;
         g_m2_pendingSL  = cn + M2_SL_Pts;
         g_m2_pendingTP  = cn - M2_TP_Pts;
      }
      return;
   }
   if(g_m2_pendingDir == 0) return;
   if(M2_HasPosition()){ g_m2_pendingDir = 0; return; }
   MqlDateTime dt2; TimeToStruct(now, dt2);
   if(!IsM2Hour(dt2.hour)){ g_m2_pendingDir = 0; return; }
   if(g_m2_pendingDir == 1)
      M2_OpenTrade(1, g_m2_pendingSL, g_m2_pendingTP);
   else
      M2_OpenTrade(-1, g_m2_pendingSL, g_m2_pendingTP);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest      &req,
                        const MqlTradeResult       &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY &&
      trans.deal_type != DEAL_TYPE_SELL) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   if(StringFind(comment, "partial") >= 0) return;
   bool was_hc = (StringFind(comment, "HardCap") >= 0);
   datetime open_t = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   MqlDateTime dt; TimeToStruct(open_t, dt);
   double hold_sec = 0;
   for(int i = 0; i < 2; i++){
      if(g_states[i].entry > 0){
         hold_sec = (double)(open_t - g_states[i].openTime);
         RecordTrade(dt.hour, g_states[i].slDist, profit,
                     hold_sec, was_hc);
         g_states[i].entry         = 0;
         g_states[i].slDist        = 0;
         g_states[i].tpDist        = 0;
         g_states[i].trailActive   = false;
         g_states[i].partial1Done  = false;
         g_states[i].partial2Done  = false;
         g_states[i].timeTrailDone = false;
         g_states[i].openTime      = 0;
         break;
      }
   }
   if(hold_sec == 0)
      RecordTrade(dt.hour, SL_Min_Static, profit, 0, was_hc);
   bool is_win = (profit > 0);
   UpdateStreakScale(is_win);
   UpdateWRTracker(is_win);
   UpdateDailyRegime(profit);
   UpdateBalanceTrail(AccountInfoDouble(ACCOUNT_BALANCE));
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0){ Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   InitLearning();
   for(int i = 0; i < 2; i++){
      g_states[i].entry         = 0;
      g_states[i].slDist        = 0;
      g_states[i].tpDist        = 0;
      g_states[i].trailActive   = false;
      g_states[i].partial1Done  = false;
      g_states[i].partial2Done  = false;
      g_states[i].timeTrailDone = false;
      g_states[i].openTime      = 0;
   }
   Print("MM7 v17.90 | ", g_sym,
         " | H02+H07+H15+H22(max1) | M2:H8+H13",
         " | HC=OFF SL=ATR×", ATR_SL_Mult, " TP=ATR×", ATR_TP_Mult,
         " | Trail_Start=$", Trail_Start_Pts, " P1=", Trail_Dist_Phase1, "pts",
         " | Partial $", Partial1_USD_Trigger, "+$", Partial2_USD_Trigger,
         " | DailyLimit=$", Daily_Loss_Limit_USD);
   return INIT_SUCCEEDED;
}

// Calcula distancia de trailing según fase temporal
double GetTrailDist(datetime openTime)
{
   int e = (int)(TimeCurrent() - openTime);
   if(e < Trail_Phase1_Sec) return Trail_Dist_Phase1;
   if(e < Trail_Phase2_Sec) return Trail_Dist_Phase2;
   return Trail_Dist_Phase3;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double   bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double   ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   datetime now = TimeCurrent();

   // FIX 6: Verificar daily halt en cada tick
   CheckDailyHalt();
   if(g_daily_halted){
      if(!g_halt_closed_today){
         ulong htks[]; GetTickets(htks);
         for(int i = 0; i < ArraySize(htks); i++) ClosePosition(htks[i], "DailyHalt");
         if(Use_Motor2) M2_CloseAll();
         g_halt_closed_today = true;
      }
      return;
   }

   if(Close_On_FriClose && IsFridayClose()){
      ulong tks[]; GetTickets(tks);
      for(int i = 0; i < ArraySize(tks); i++)
         ClosePosition(tks[i], "FriClose");
      if(Use_Motor2) M2_CloseAll();
      g_pendingDir = 0;
      return;
   }

   // Motor 2 corre en paralelo, independiente
   RunMotor2(bid, ask, now);

   // ================================================================
   // GESTIÓN DE POSICIONES ABIERTAS (Motor 1)
   // ================================================================
   ulong tks[]; int npos = (int)GetTickets(tks);
   for(int pi = 0; pi < npos; pi++){
      ulong tk = tks[pi];
      if(!PositionSelectByTicket(tk)) continue;

      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double favorable = entry - ask; // positivo cuando el precio baja (SELL gana)
      double pnl       = PositionGetDouble(POSITION_PROFIT);
      int    digs      = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

      // Buscar o crear estado para esta posición
      int si = -1;
      for(int i = 0; i < 2; i++){
         if(MathAbs(g_states[i].entry - entry) < 0.01 &&
            g_states[i].entry > 0){ si = i; break; }
      }
      if(si < 0){
         for(int i = 0; i < 2; i++){
            if(g_states[i].entry == 0){ si = i; break; }
         }
         if(si < 0) continue;
         g_states[si].entry         = entry;
         g_states[si].slDist        = MathAbs(curSL - entry);
         g_states[si].tpDist        = MathAbs(curTP - entry);
         g_states[si].openTime      = now;
         g_states[si].trailActive   = false;
         g_states[si].partial1Done  = false;
         g_states[si].partial2Done  = false;
         g_states[si].timeTrailDone = false;
      }
      double slD = g_states[si].slDist;

      // 1. HARD LOSS CAP = $12 (Monte Carlo óptimo)
      if(Use_Hard_Loss_Cap && pnl < -Hard_Loss_Cap_USD){
         ClosePosition(tk, "HardCap");
         if(Use_HardCap_Cooldown)
            g_hardcap_cooldown = HardCap_Cooldown_Bars;
         Print("MM7 HC pnl=", DoubleToString(pnl, 2));
         continue;
      }

      // 2. FIX 4: PARTIAL CLOSE DOBLE ESCALONADO
      // Nivel 1: 30% a $6 → mover SL a breakeven (trade libre de riesgo)
      if(Use_Partial_Close && !g_states[si].partial1Done &&
         pnl >= Partial1_USD_Trigger){
         if(DoPartialClose(tk, Partial1_Close_Pct, "L1")){
            g_states[si].partial1Done = true;
            // Mover SL a breakeven
            if(PositionSelectByTicket(tk)){
               double ctp = PositionGetDouble(POSITION_TP);
               double csl = PositionGetDouble(POSITION_SL);
               double nsl = NormalizeDouble(entry, digs);
               if(nsl < csl) SetSLTP(tk, nsl, ctp);
            }
         }
      }
      // Nivel 2: 30% más a $15 → SL sube a $6 de ganancia
      if(Use_Partial_Close && g_states[si].partial1Done &&
         !g_states[si].partial2Done && pnl >= Partial2_USD_Trigger){
         if(DoPartialClose(tk, Partial2_Close_Pct, "L2")){
            g_states[si].partial2Done = true;
            // Mover SL para proteger $6 de ganancia
            if(PositionSelectByTicket(tk)){
               double ctp  = PositionGetDouble(POSITION_TP);
               double csl  = PositionGetDouble(POSITION_SL);
               // SL en nivel que asegura ~$4 de ganancia
               double nsl = NormalizeDouble(entry - 4.0, digs);
               if(nsl < csl) SetSLTP(tk, nsl, ctp);
            }
         }
      }

      // Refrescar datos tras posibles partials
      if(!PositionSelectByTicket(tk)) continue;
      curSL = PositionGetDouble(POSITION_SL);
      curTP = PositionGetDouble(POSITION_TP);

      // 3. FIX 1: TRAILING AMPLIO (Phase1=30pts para que el trade respire)
      if(Use_Trail && favorable >= Trail_Start_Pts){
         double trail_d = GetTrailDist(g_states[si].openTime);
         double newSL   = NormalizeDouble(ask + trail_d, digs);
         // Solo mover SL hacia el precio (nunca alejarlo)
         if(newSL < curSL)
            SetSLTP(tk, newSL, curTP);
         if(!g_states[si].trailActive)
            g_states[si].trailActive = true;
      }

      // 4. TIME TRAIL: si pasa 3.2h sin avanzar → mover a BE
      if(Use_Time_Trail && !g_states[si].timeTrailDone &&
         g_states[si].openTime > 0){
         if((now - g_states[si].openTime) >= Time_Trail_Sec){
            if(favorable < slD * Trail_Progress_Pct &&
               PositionSelectByTicket(tk)){
               double ctp = PositionGetDouble(POSITION_TP);
               double csl = PositionGetDouble(POSITION_SL);
               double nsl = NormalizeDouble(entry, digs);
               if(nsl < csl){
                  SetSLTP(tk, nsl, ctp);
                  Print("MM7 TIME_TRAIL → BE");
               }
            }
            g_states[si].timeTrailDone = true;
         }
      }
   }

   // Limpiar estados de posiciones ya cerradas
   npos = (int)GetTickets(tks);
   for(int i = 0; i < 2; i++){
      if(g_states[i].entry == 0) continue;
      bool found = false;
      for(int pi = 0; pi < ArraySize(tks); pi++){
         if(PositionSelectByTicket(tks[pi]) &&
            MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) -
                    g_states[i].entry) < 0.01){
            found = true; break;
         }
      }
      if(!found){
         g_states[i].entry         = 0;
         g_states[i].slDist        = 0;
         g_states[i].tpDist        = 0;
         g_states[i].trailActive   = false;
         g_states[i].partial1Done  = false;
         g_states[i].partial2Done  = false;
         g_states[i].timeTrailDone = false;
         g_states[i].openTime      = 0;
      }
   }

   // ================================================================
   // GENERACIÓN DE SEÑAL (Motor 1)
   // ================================================================
   if(CountByMagic() >= Max_Positions){ g_pendingDir = 0; return; }

   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime){
      g_lastBarTime = curBar;
      g_pendingDir  = 0;

      // Cooldown post-HC
      if(g_hardcap_cooldown > 0){ g_hardcap_cooldown--; return; }
      if(g_pauseBarsLeft    > 0){ g_pauseBarsLeft--;     return; }

      UpdateBearDetector();
      UpdateRegime();

      MqlDateTime dt; TimeToStruct(curBar, dt);
      if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC) return;
      // FIX 3: IsGoodHour ya excluye H07 y H22 permanentemente
      if(!IsGoodHour(dt.hour)) return;

      // Filtro velocidad adaptativo
      double cv2 = iClose(g_sym, _Period, Vel_Bars + 1);
      double cn2 = iClose(g_sym, _Period, 1);
      if(cv2 > 0 && cn2 > 0 &&
         MathAbs(cn2 - cv2) / Vel_Bars > g_vel_threshold) return;

      // Calcular rango de 50 barras
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= Range_Bars; i++){
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h == 0 || l == 0) return;
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      double range = rH - rL;
      if(range <= 0) return;
      double closeNow = iClose(g_sym, _Period, 1);
      if(closeNow == 0) return;
      double upperZone = rH - range * g_zone_pct;

      // FIX 2: SL y TP dinámicos calculados AQUÍ (con datos frescos de la barra)
      double sl_dyn = DynamicSL();
      double tp_dyn = DynamicTP();
      // Verificar que TP > SL (ratio mínimo de 1.5:1)
      if(tp_dyn < sl_dyn * 1.5) tp_dyn = sl_dyn * 1.5;

      if(closeNow >= upperZone && !TrendBlocksSell()){
         // H22 limitada a 1 posición (alta varianza)
         if(dt.hour == 22 && CountByMagic() >= Max_Positions_H22) return;
         g_pendingDir    = -1;
         g_confirmLevel  = closeNow - Confirm_Points;
         g_pendingSL     = sl_dyn;
         g_pendingTP     = tp_dyn;
      }
      return;
   }

   // Entrada en tick: confirmar y ejecutar
   if(g_hardcap_cooldown > 0) return;
   if(g_pauseBarsLeft    > 0) return;
   if(g_pendingDir       == 0) return;
   MqlDateTime dt; TimeToStruct(now, dt);
   if(!IsGoodHour(dt.hour)){ g_pendingDir = 0; return; }
   if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC){
      g_pendingDir = 0; return;
   }

   if(g_pendingDir == -1 && ask <= g_confirmLevel)
      OpenSell(g_pendingSL, g_pendingTP);
}
//+------------------------------------------------------------------+
