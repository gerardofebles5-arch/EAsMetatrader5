//+------------------------------------------------------------------+
//|  MoneyMachine_v19.0.mq5                                         |
//|  VERSIÓN FINAL — BASADA EN v17.95 (LA QUE FUNCIONÓ)             |
//|  Análisis forense: v17.60 → v17.95 + v18.x + Quantum Queen      |
//|                                                                  |
//|  LECCIONES CLAVE:                                                |
//|  ✅ SL_USD_Cap = $12.00 (v18.x usó $1.00 → CUENTA MUERTA)       |
//|  ✅ Daily_Loss = $25.00 (v18.x usó $2.00 → BLOQUEO INMEDIATO)   |
//|  ✅ Max_Positions = 2 (v18.x usó 1 → 50% menos oportunidades)   |
//|  ✅ 6 MOTORES ACTIVOS (M1-M6 para diversificación)              |
//|  ✅ ATR_SL_Mult = 0.8, ATR_TP_Mult = 3.0 (probado óptimo)       |
//|  ✅ Partial Close $6/$15 (funciona en v17.95)                   |
//|  ✅ Trail_Start = 13pts (deja respirar winners)                 |
//+------------------------------------------------------------------+
#property copyright "Sal - Ingeniería de Sistemas"
#property version   "19.0"
#property strict
#property description "EA FINAL - Parámetros v17.95 probados"

//=== INPUTS — GESTIÓN DE CAPITAL (v17.95 PROBADO) =================
input group "══════ GESTIÓN DE CAPITAL ══════"
input double Min_Balance_To_Trade    = 30.0;   // Mínimo para operar
input double Risk_Pct_Per_Trade      = 0.02;   // 2% por trade (v17.95)
input double SL_USD_Cap_Value        = 12.0;   // $12 (v17.95) ✅ NO $1 como v18.x
input double Daily_Loss_Limit_USD    = 25.0;   // $25 (v17.95) ✅ NO $2 como v18.x
input double Weekly_Loss_Limit_USD   = 50.0;   // $50 semanal
input int    Max_Positions           = 2;      // 2 posiciones (v17.95) ✅

//=== INPUTS — COMPOUNDING ==========================================
input group "══════ COMPOUNDING ══════"
input bool   Use_Compounding         = true;
input double Lot_Hit_1_Balance       = 50.0;   // $50 → 0.01 lotes
input double Lot_Hit_2_Balance       = 100.0;  // $100 → 0.02 lotes
input double Lot_Hit_3_Balance       = 200.0;  // $200 → 0.03 lotes
input double Lot_Hit_4_Balance       = 500.0;  // $500 → 0.05 lotes
input double Max_Lot_Absolute        = 0.10;

//=== INPUTS — MOTOR 1 (REVERSIÓN H02+H07+H15) =====================
input group "══════ MOTOR 1 — REVERSIÓN ══════"
input bool   Use_Motor1              = true;
input int    M1_Magic                = 177900;
input int    M1_Range_Bars           = 50;
input double M1_Zone_Pct             = 0.555;  // v17.95 probado
input double M1_Confirm_Pts          = 4.6;    // v17.95 probado

//=== INPUTS — MOTOR 2 (BREAKOUT H08+H13) ==========================
input group "══════ MOTOR 2 — BREAKOUT ══════"
input bool   Use_Motor2              = true;
input int    M2_Magic                = 178000;
input int    M2_Breakout_Bars        = 20;
input double M2_Breakout_Pts         = 8.0;
input double M2_SL_Pts               = 12.0;
input double M2_TP_Pts               = 20.0;
input int    M2_MaxHold_Sec          = 5400;
input double M2_Risk_Pct             = 0.015;

//=== INPUTS — MOTOR 3 (BUY TENDENCIA H02+H15) =====================
input group "══════ MOTOR 3 — BUY TREND ══════"
input bool   Use_Motor3              = true;
input int    M3_Magic                = 179300;
input double M3_Zone_Pct             = 0.45;
input double M3_EMA_Fast             = 5.0;
input double M3_EMA_Slow             = 20.0;
input double M3_Trend_Min_Pts        = 15.0;
input double M3_SL_Pts               = 10.0;
input double M3_TP_Pts               = 30.0;
input int    M3_MaxHold_Sec          = 5400;
input double M3_Risk_Pct             = 0.015;

//=== INPUTS — MOTOR 4 (POST-NY H16-H17) ===========================
input group "══════ MOTOR 4 — POST-NY ══════"
input bool   Use_Motor4              = true;
input int    M4_Magic                = 179400;
input double M4_Spike_Min_Pts        = 20.0;
input double M4_SL_Pts               = 15.0;
input double M4_TP_Pts               = 25.0;
input int    M4_MaxHold_Sec          = 5400;
input double M4_Risk_Pct             = 0.015;

//=== INPUTS — MOTOR 5 (ASIÁTICA H00-H01) ==========================
input group "══════ MOTOR 5 — ASIÁTICA ══════"
input bool   Use_Motor5              = true;
input int    M5_Magic                = 179500;
input int    M5_Range_Bars           = 30;
input double M5_Zone_Pct             = 0.15;
input double M5_SL_Pts               = 8.0;
input double M5_TP_Pts               = 15.0;
input int    M5_MaxHold_Sec          = 3600;
input double M5_Risk_Pct             = 0.01;

//=== INPUTS — MOTOR 6 (PRE-NY H12-H14) ============================
input group "══════ MOTOR 6 — PRE-NY ══════"
input bool   Use_Motor6              = true;
input int    M6_Magic                = 179600;
input double M6_Move_Min_Pts         = 35.0;
input double M6_SL_Pts               = 12.0;
input double M6_TP_Pts               = 20.0;
input int    M6_MaxHold_Sec          = 7200;
input double M6_Risk_Pct             = 0.015;

//=== INPUTS — SL / TP (v17.95 PROBADO) ============================
input group "══════ SL / TP ══════"
input double SL_Min_Points           = 10.0;
input double SL_Max_Points           = 35.0;
input double ATR_Period_SL           = 14.0;
input double ATR_SL_Mult             = 0.8;    // v17.95 ✅
input double ATR_TP_Mult             = 3.0;    // v17.95 ✅
input double TP_Min_Static           = 30.0;
input bool   Use_Broker_SLTP         = true;

//=== INPUTS — TRAILING (v17.95 PROBADO) ===========================
input group "══════ TRAILING ══════"
input bool   Use_Trail               = true;
input double Trail_Start_Pts         = 13.0;   // v17.95 ✅
input double Trail_Dist_Phase1       = 30.0;   // v17.95 ✅
input double Trail_Dist_Phase2       = 8.0;    // v17.95 ✅
input double Trail_Dist_Phase3       = 4.0;    // v17.95 ✅
input int    Trail_Phase1_Sec        = 600;
input int    Trail_Phase2_Sec        = 1800;

//=== INPUTS — PARTIAL CLOSE (v17.95 PROBADO) ======================
input group "══════ PARTIAL CLOSE ══════"
input bool   Use_Partial_Close       = true;
input double Partial1_USD_Trigger    = 6.0;    // v17.95 ✅
input double Partial1_Close_Pct      = 0.30;   // v17.95 ✅
input double Partial2_USD_Trigger    = 15.0;   // v17.95 ✅
input double Partial2_Close_Pct      = 0.30;   // v17.95 ✅

//=== INPUTS — FILTROS ==============================================
input group "══════ FILTROS ══════"
input bool   Use_Trend_Filter        = true;
input int    Trend_Bars              = 100;
input double Trend_Min_Move          = 30.0;
input bool   Use_Volatility_Filter   = true;
input int    Vel_Bars                = 3;
input double Vel_Threshold_Base      = 4.4;
input int    FriClose_Hour_UTC       = 20;
input bool   Close_On_FriClose       = true;
input int    Max_Consec_Losses       = 4;
input int    Pause_Bars              = 6;
input bool   Use_Hour_Filter         = true;
input bool   Use_DayOfWeek_Filter    = true;
input int    DayOfWeek_Mask          = 119;    // Bloquea Miércoles

//=== INPUTS — SISTEMA ==============================================
input group "══════ SISTEMA ══════"
input int    InpMagicNumber          = 177900;
input int    InpSlippagePoints       = 10;
input double Min_Lot                 = 0.01;
input double Max_Lot                 = 10.0;
input bool   Debug_Log               = true;

//=== GLOBALES — ESTADO DEL SISTEMA ================================
string   g_sym;
double   g_point;
int      g_digits;
datetime g_lastBarTime       = 0;
int      g_pendingDir        = 0;
double   g_confirmLevel      = 0;
double   g_pendingSL         = 0;
double   g_pendingTP         = 0;
double   g_zone_pct          = 0.555;
double   g_lot_scale         = 1.0;
double   g_vel_threshold     = 4.4;

//=== GLOBALES — GESTIÓN DE RIESGO ================================
int      g_consecLosses      = 0;
int      g_consecWins        = 0;
int      g_pauseBarsLeft     = 0;
int      g_totalTrades       = 0;
int      g_hardcap_cooldown  = 0;
double   g_today_pnl         = 0.0;
datetime g_today_date        = 0;
double   g_today_start_bal   = 0.0;
bool     g_daily_halted      = false;
bool     g_halt_closed_today = false;
double   g_weekly_pnl        = 0.0;
datetime g_weekly_date       = 0;
bool     g_weekly_halted     = false;

//=== GLOBALES — ESTADOS DE POSICIONES ============================
struct TradeState {
   ulong    ticket;
   double   entry;
   double   slDist;
   double   tpDist;
   bool     trailActive;
   bool     partial1Done;
   bool     partial2Done;
   bool     timeTrailDone;
   datetime openTime;
   ENUM_POSITION_TYPE type;
};
TradeState g_states[10];

//=== GLOBALES — HISTORIAL DE APRENDIZAJE =========================
struct TradeRecord {
   int      hour;
   double   sl_dist;
   double   profit;
   double   hold_sec;
   bool     is_win;
};
TradeRecord g_history[500];
int         g_histCount = 0;

struct HourStats {
   int      n;
   int      wins;
   double   total_profit;
   bool     blocked;
};
HourStats   g_hourStats[24];

//=== GLOBALES — MOTORES 2-6 ======================================
datetime g_m2_lastBarTime = 0, g_m3_lastBarTime = 0, g_m4_lastBarTime = 0;
datetime g_m5_lastBarTime = 0, g_m6_lastBarTime = 0;
int      g_m2_pendingDir = 0, g_m3_pendingDir = 0, g_m4_pendingDir = 0;
int      g_m5_pendingDir = 0, g_m6_pendingDir = 0;
double   g_m2_pendingSL = 0, g_m3_pendingSL = 0, g_m4_pendingSL = 0;
double   g_m5_pendingSL = 0, g_m6_pendingSL = 0;
double   g_m2_pendingTP = 0, g_m3_pendingTP = 0, g_m4_pendingTP = 0;
double   g_m5_pendingTP = 0, g_m6_pendingTP = 0;
datetime g_m2_openTime = 0, g_m3_openTime = 0, g_m4_openTime = 0;
datetime g_m5_openTime = 0, g_m6_openTime = 0;
double   g_m4_h15_open = 0;

//+------------------------------------------------------------------+
//|  LOGGING DEBUG
//+------------------------------------------------------------------+
void LogDebug(string msg)
{
   if(Debug_Log) Print("[MM19.0] ", msg);
}

//+------------------------------------------------------------------+
//|  UTILIDADES ATR
//+------------------------------------------------------------------+
double CalcATR14()
{
   int period = (int)ATR_Period_SL;
   double sum = 0;
   int cnt = 0;
   for(int i = 1; i <= period + 1 && cnt < period; i++){
      double h  = iHigh(g_sym, _Period, i);
      double l  = iLow(g_sym,  _Period, i);
      double pc = iClose(g_sym, _Period, i + 1);
      if(h <= 0 || l <= 0 || pc <= 0) continue;
      double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      sum += tr;
      cnt++;
   }
   if(cnt == 0) return SL_Min_Points;
   return sum / cnt;
}

double DynamicSL()
{
   double atr = CalcATR14();
   if(atr <= 0) return SL_Min_Points;
   return MathMax(SL_Min_Points, MathMin(SL_Max_Points, atr * ATR_SL_Mult));
}

double DynamicTP()
{
   double atr = CalcATR14();
   if(atr <= 0) return TP_Min_Static;
   return MathMax(TP_Min_Static, atr * ATR_TP_Mult);
}

//+------------------------------------------------------------------+
//|  CÁLCULO DE LOTE (v17.95 PROBADO)
//+------------------------------------------------------------------+
double CalcLot(double sl_dist, double risk_pct)
{
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   
   if(bal < Min_Balance_To_Trade){
      LogDebug("BLOQUEO: Balance=$" + DoubleToString(bal, 2) + " < $" + DoubleToString(Min_Balance_To_Trade, 2));
      return 0;
   }
   
   double base_lot = Min_Lot;
   if(Use_Compounding){
      if(bal >= Lot_Hit_4_Balance) base_lot = 0.05;
      else if(bal >= Lot_Hit_3_Balance) base_lot = 0.03;
      else if(bal >= Lot_Hit_2_Balance) base_lot = 0.02;
      else if(bal >= Lot_Hit_1_Balance) base_lot = 0.01;
      else base_lot = 0.01;
   }
   
   double risk_usd = bal * risk_pct;
   if(sl_dist <= 0) sl_dist = SL_Min_Points;
   
   double value_per_point = 0.10;
   double lot_by_risk = risk_usd / (sl_dist * value_per_point * 100);
   
   double lot = MathMax(base_lot, lot_by_risk);
   lot = lot * g_lot_scale;
   
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot_Absolute, mx));
   
   if(st > 0) lot = MathFloor(lot / st) * st;
   
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//|  CONTAR POSICIONES POR MAGIC
//+------------------------------------------------------------------+
int CountByMagic(int magic)
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++){
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk)){
         if((int)PositionGetInteger(POSITION_MAGIC) == magic) n++;
      }
   }
   return n;
}

int CountAllPositions()
{
   return PositionsTotal();
}

//+------------------------------------------------------------------+
//|  OBTENER TICKETS POR MAGIC
//+------------------------------------------------------------------+
ulong GetTickets(ulong &arr[], int magic)
{
   int cnt = 0;
   ArrayResize(arr, 0);
   for(int i = 0; i < PositionsTotal(); i++){
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk)){
         if((int)PositionGetInteger(POSITION_MAGIC) == magic){
            ArrayResize(arr, cnt + 1);
            arr[cnt++] = tk;
         }
      }
   }
   return cnt;
}

//+------------------------------------------------------------------+
//|  CERRAR POSICIÓN
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double vol   = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = (pt == POSITION_TYPE_BUY) ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = vol;
   req.type      = (pt == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = price;
   req.position  = ticket;
   req.deviation = InpSlippagePoints;
   req.magic     = (int)PositionGetInteger(POSITION_MAGIC);
   req.comment   = "MM19-" + reason;
   req.type_filling = ORDER_FILLING_FOK;
   
   bool ok = OrderSend(req, res);
   if(!ok){
      req.type_filling = ORDER_FILLING_IOC;
      ok = OrderSend(req, res);
   }
   if(!ok){
      req.type_filling = ORDER_FILLING_RETURN;
      ok = OrderSend(req, res);
   }
   
   LogDebug("CERRADO ticket=" + IntegerToString(ticket) + " reason=" + reason);
}

void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--){
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk)) ClosePosition(tk, reason);
   }
}

//+------------------------------------------------------------------+
//|  ACTUALIZAR SL/TP
//+------------------------------------------------------------------+
void SetSLTP(ulong ticket, double newSL, double newTP)
{
   if(ticket <= 0) return;
   if(!PositionSelectByTicket(ticket)) return;
   
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = g_sym;
   req.position = ticket;
   req.sl       = newSL;
   req.tp       = newTP;
   
   OrderSend(req, res);
}

//+------------------------------------------------------------------+
//|  PARTIAL CLOSE
//+------------------------------------------------------------------+
bool DoPartialClose(ulong ticket, double pct, string label)
{
   if(!PositionSelectByTicket(ticket)) return false;
   
   double cv    = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = (pt == POSITION_TYPE_BUY) ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double vc    = NormalizeDouble(cv * pct, 2);
   
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   
   if(st > 0) vc = MathFloor(vc / st) * st;
   vc = MathMax(vc, mn);
   
   if(vc >= cv) return false;
   
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = vc;
   req.type      = (pt == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = price;
   req.position  = ticket;
   req.deviation = InpSlippagePoints;
   req.magic     = (int)PositionGetInteger(POSITION_MAGIC);
   req.comment   = "MM19-partial-" + label;
   req.type_filling = ORDER_FILLING_FOK;
   
   bool ok = OrderSend(req, res);
   if(!ok){
      req.type_filling = ORDER_FILLING_IOC;
      ok = OrderSend(req, res);
   }
   
   LogDebug("PARTIAL " + label + " vol=" + DoubleToString(vc, 2));
   return ok;
}

//+------------------------------------------------------------------+
//|  ABRIR OPERACIÓN
//+------------------------------------------------------------------+
void OpenTrade(int dir, double sl_dist, double tp_dist, int magic, string label, double risk_pct)
{
   double bid  = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask  = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   int    digs = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   
   ENUM_ORDER_TYPE otype = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (dir == 1) ? ask : bid;
   
   double sl = (dir == 1) ? NormalizeDouble(price - sl_dist, digs) : NormalizeDouble(price + sl_dist, digs);
   double tp = (dir == 1) ? NormalizeDouble(price + tp_dist, digs) : NormalizeDouble(price - tp_dist, digs);
   
   double lot = CalcLot(sl_dist, risk_pct);
   
   if(lot <= 0){
      LogDebug("OpenTrade BLOQUEADO: lot=" + DoubleToString(lot, 2));
      return;
   }
   
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = lot;
   req.type      = otype;
   req.price     = price;
   req.sl        = Use_Broker_SLTP ? sl : 0;
   req.tp        = Use_Broker_SLTP ? tp : 0;
   req.deviation = InpSlippagePoints;
   req.magic     = magic;
   req.comment   = label;
   req.type_filling = ORDER_FILLING_FOK;
   
   bool ok = OrderSend(req, res);
   if(!ok){
      req.type_filling = ORDER_FILLING_IOC;
      ok = OrderSend(req, res);
   }
   
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED){
      LogDebug(label + " " + (dir==1?"BUY":"SELL") + " lot=" + DoubleToString(lot, 2));
   }
}

//+------------------------------------------------------------------+
//|  CHECK DAILY HALT
//+------------------------------------------------------------------+
void CheckDailyHalt()
{
   if(Daily_Loss_Limit_USD <= 0) return;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   
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
      LogDebug("DAILY HALT: pérdida=$" + DoubleToString(-day_pnl, 2));
   }
}

void CheckWeeklyHalt()
{
   if(Weekly_Loss_Limit_USD <= 0) return;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime week_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day - dt.day_of_week + 1));
   
   if(g_weekly_date != week_start){
      g_weekly_date  = week_start;
      g_weekly_pnl   = 0.0;
      g_weekly_halted = false;
   }
   
   if(g_weekly_halted) return;
   
   if(g_weekly_pnl < -Weekly_Loss_Limit_USD){
      g_weekly_halted = true;
      LogDebug("WEEKLY HALT: pérdida=$" + DoubleToString(-g_weekly_pnl, 2));
   }
}

//+------------------------------------------------------------------+
//|  FILTROS
//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   if(hour != 2 && hour != 7 && hour != 15) return false;
   if(g_hourStats[hour].blocked && g_hourStats[hour].n >= 6) return false;
   return true;
}

bool IsGoodDay(int dow)
{
   if(!Use_DayOfWeek_Filter) return true;
   int bit = 1 << dow;
   return ((DayOfWeek_Mask & bit) != 0);
}

bool TrendBlocksSell()
{
   if(!Use_Trend_Filter) return false;
   double cn = iClose(g_sym, _Period, 1);
   double co = iClose(g_sym, _Period, Trend_Bars + 1);
   if(cn <= 0 || co <= 0) return false;
   return (cn - co >= Trend_Min_Move);
}

bool VolatilityFilter()
{
   if(!Use_Volatility_Filter) return true;
   double cv = iClose(g_sym, _Period, Vel_Bars + 1);
   double cn = iClose(g_sym, _Period, 1);
   if(cv <= 0 || cn <= 0) return true;
   double velocity = MathAbs(cn - cv) / Vel_Bars;
   return (velocity <= g_vel_threshold);
}

bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC);
}

//+------------------------------------------------------------------+
//|  MOTOR 1 — REVERSIÓN (v17.95 PROBADO)
//+------------------------------------------------------------------+
void RunMotor1(double bid, double ask, datetime now)
{
   if(!Use_Motor1 || g_daily_halted || g_weekly_halted) return;
   if(g_pauseBarsLeft > 0) return;
   if(g_hardcap_cooldown > 0) return;
   if(CountAllPositions() >= Max_Positions) return;
   
   datetime curBar = iTime(g_sym, _Period, 0);
   
   if(curBar != g_lastBarTime){
      g_lastBarTime = curBar;
      g_pendingDir  = 0;
      
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      
      if(Close_On_FriClose && IsFridayClose()) return;
      if(!IsGoodDay(dt.day_of_week)) return;
      if(!IsGoodHour(dt.hour)) return;
      if(!VolatilityFilter()) return;
      if(TrendBlocksSell()) return;
      
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= M1_Range_Bars; i++){
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h <= 0 || l <= 0) return;
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      
      double range = rH - rL;
      if(range <= 0) return;
      
      double closeNow = iClose(g_sym, _Period, 1);
      if(closeNow <= 0) return;
      
      double upperZone = rH - range * g_zone_pct;
      double sl_dyn = DynamicSL();
      double tp_dyn = DynamicTP();
      
      if(tp_dyn < sl_dyn * 1.5) tp_dyn = sl_dyn * 1.5;
      
      if(closeNow >= upperZone){
         g_pendingDir   = -1;
         g_confirmLevel = closeNow - M1_Confirm_Pts;
         g_pendingSL    = sl_dyn;
         g_pendingTP    = tp_dyn;
      }
      
      return;
   }
   
   if(g_pendingDir == 0) return;
   
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(!IsGoodHour(dt.hour)){
      g_pendingDir = 0;
      return;
   }
   
   if(g_pendingDir == -1 && ask <= g_confirmLevel){
      OpenTrade(-1, g_pendingSL, g_pendingTP, InpMagicNumber, "MM19", Risk_Pct_Per_Trade);
      g_pendingDir = 0;
   }
}

//+------------------------------------------------------------------+
//|  MOTOR 2 — BREAKOUT
//+------------------------------------------------------------------+
void RunMotor2(double bid, double ask, datetime now)
{
   if(!Use_Motor2 || g_daily_halted) return;
   
   if(CountByMagic(M2_Magic) > 0 && g_m2_openTime > 0 && (int)(now - g_m2_openTime) >= M2_MaxHold_Sec){
      ulong tks[];
      GetTickets(tks, M2_Magic);
      for(int i = 0; i < ArraySize(tks); i++) ClosePosition(tks[i], "M2-TimeExit");
      g_m2_openTime = 0;
      g_m2_pendingDir = 0;
   }
   
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_m2_lastBarTime){
      g_m2_lastBarTime = curBar;
      g_m2_pendingDir  = 0;
      
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(dt.hour != 8 && dt.hour != 13) return;
      
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= M2_Breakout_Bars; i++){
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      
      double cn = iClose(g_sym, _Period, 1);
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
   
   if(g_m2_pendingDir != 0 && CountByMagic(M2_Magic) == 0){
      OpenTrade(g_m2_pendingDir, M2_SL_Pts, M2_TP_Pts, M2_Magic, "M2", M2_Risk_Pct);
      g_m2_openTime = now;
      g_m2_pendingDir = 0;
   }
}

//+------------------------------------------------------------------+
//|  MOTOR 3 — BUY TENDENCIA
//+------------------------------------------------------------------+
void RunMotor3(double bid, double ask, datetime now)
{
   if(!Use_Motor3 || g_daily_halted) return;
   
   if(CountByMagic(M3_Magic) > 0 && g_m3_openTime > 0 && (int)(now - g_m3_openTime) >= M3_MaxHold_Sec){
      ulong tks[];
      GetTickets(tks, M3_Magic);
      for(int i = 0; i < ArraySize(tks); i++) ClosePosition(tks[i], "M3-TimeExit");
      g_m3_openTime = 0;
   }
   
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_m3_lastBarTime){
      g_m3_lastBarTime = curBar;
      
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(dt.hour != 2 && dt.hour != 15) return;
      
      double ema_f = iMA(g_sym, _Period, (int)M3_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
      double ema_s = iMA(g_sym, _Period, (int)M3_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
      
      if(ema_f <= 0 || ema_s <= 0) return;
      if((ema_f - ema_s) < M3_Trend_Min_Pts) return;
      
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= M1_Range_Bars; i++){
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      
      double range = rH - rL;
      if(range <= 0) return;
      
      double closeNow = iClose(g_sym, _Period, 1);
      double lowerZone = rL + range * M3_Zone_Pct;
      
      if(closeNow <= lowerZone && CountByMagic(M3_Magic) == 0){
         OpenTrade(1, M3_SL_Pts, M3_TP_Pts, M3_Magic, "M3-BUY", M3_Risk_Pct);
         g_m3_openTime = now;
      }
   }
}

//+------------------------------------------------------------------+
//|  MOTOR 4 — POST-NY
//+------------------------------------------------------------------+
void RunMotor4(double bid, double ask, datetime now)
{
   if(!Use_Motor4 || g_daily_halted) return;
   
   if(CountByMagic(M4_Magic) > 0 && g_m4_openTime > 0 && (int)(now - g_m4_openTime) >= M4_MaxHold_Sec){
      ulong tks[];
      GetTickets(tks, M4_Magic);
      for(int i = 0; i < ArraySize(tks); i++) ClosePosition(tks[i], "M4-TimeExit");
      g_m4_openTime = 0;
   }
   
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_m4_lastBarTime){
      g_m4_lastBarTime = curBar;
      
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(dt.hour == 15 && dt.min == 0) g_m4_h15_open = iOpen(g_sym, _Period, 1);
      if(dt.hour != 16 && dt.hour != 17) return;
      
      if(g_m4_h15_open <= 0) return;
      double closeNow = iClose(g_sym, _Period, 1);
      double spike = (closeNow - g_m4_h15_open) / g_point;
      
      if(spike >= M4_Spike_Min_Pts && CountByMagic(M4_Magic) == 0){
         OpenTrade(-1, M4_SL_Pts, M4_TP_Pts, M4_Magic, "M4-SELL", M4_Risk_Pct);
         g_m4_openTime = now;
      } else if(spike <= -M4_Spike_Min_Pts && CountByMagic(M4_Magic) == 0){
         OpenTrade(1, M4_SL_Pts, M4_TP_Pts, M4_Magic, "M4-BUY", M4_Risk_Pct);
         g_m4_openTime = now;
      }
   }
}

//+------------------------------------------------------------------+
//|  MOTOR 5 — ASIÁTICA
//+------------------------------------------------------------------+
void RunMotor5(double bid, double ask, datetime now)
{
   if(!Use_Motor5 || g_daily_halted) return;
   
   if(CountByMagic(M5_Magic) > 0 && g_m5_openTime > 0 && (int)(now - g_m5_openTime) >= M5_MaxHold_Sec){
      ulong tks[];
      GetTickets(tks, M5_Magic);
      for(int i = 0; i < ArraySize(tks); i++) ClosePosition(tks[i], "M5-TimeExit");
      g_m5_openTime = 0;
   }
   
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_m5_lastBarTime){
      g_m5_lastBarTime = curBar;
      
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(dt.hour != 0 && dt.hour != 1) return;
      
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= M5_Range_Bars; i++){
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      
      double range = rH - rL;
      if(range < 10 * g_point) return;
      
      double closeNow = iClose(g_sym, _Period, 1);
      double upper_zone = rH - range * M5_Zone_Pct;
      double lower_zone = rL + range * M5_Zone_Pct;
      
      if(closeNow >= upper_zone && CountByMagic(M5_Magic) == 0){
         OpenTrade(-1, M5_SL_Pts, M5_TP_Pts, M5_Magic, "M5-SELL", M5_Risk_Pct);
         g_m5_openTime = now;
      } else if(closeNow <= lower_zone && CountByMagic(M5_Magic) == 0){
         OpenTrade(1, M5_SL_Pts, M5_TP_Pts, M5_Magic, "M5-BUY", M5_Risk_Pct);
         g_m5_openTime = now;
      }
   }
}

//+------------------------------------------------------------------+
//|  MOTOR 6 — PRE-NY
//+------------------------------------------------------------------+
void RunMotor6(double bid, double ask, datetime now)
{
   if(!Use_Motor6 || g_daily_halted) return;
   
   if(CountByMagic(M6_Magic) > 0 && g_m6_openTime > 0 && (int)(now - g_m6_openTime) >= M6_MaxHold_Sec){
      ulong tks[];
      GetTickets(tks, M6_Magic);
      for(int i = 0; i < ArraySize(tks); i++) ClosePosition(tks[i], "M6-TimeExit");
      g_m6_openTime = 0;
   }
   
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_m6_lastBarTime){
      g_m6_lastBarTime = curBar;
      
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(dt.hour < 12 || dt.hour > 14) return;
      
      MqlDateTime day_dt;
      TimeToStruct(curBar, day_dt);
      datetime day_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00", day_dt.year, day_dt.mon, day_dt.day));
      
      double day_high = -DBL_MAX, day_low = DBL_MAX;
      for(int i = 1; i <= 780; i++){
         datetime bt = iTime(g_sym, _Period, i);
         if(bt < day_start) break;
         double h = iHigh(g_sym, _Period, i);
         double l = iLow(g_sym,  _Period, i);
         if(h > day_high) day_high = h;
         if(l < day_low) day_low = l;
      }
      
      double closeNow = iClose(g_sym, _Period, 1);
      double drop_from_high = (day_high - closeNow) / g_point;
      double rise_from_low = (closeNow - day_low) / g_point;
      
      if(drop_from_high >= M6_Move_Min_Pts && CountByMagic(M6_Magic) == 0){
         OpenTrade(1, M6_SL_Pts, M6_TP_Pts, M6_Magic, "M6-BUY", M6_Risk_Pct);
         g_m6_openTime = now;
      } else if(rise_from_low >= M6_Move_Min_Pts && CountByMagic(M6_Magic) == 0){
         OpenTrade(-1, M6_SL_Pts, M6_TP_Pts, M6_Magic, "M6-SELL", M6_Risk_Pct);
         g_m6_openTime = now;
      }
   }
}

//+------------------------------------------------------------------+
//|  GESTIÓN DE POSICIONES ABIERTAS
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int mi = 0; mi < 10; mi++){
      if(g_states[mi].ticket == 0) continue;
      if(!PositionSelectByTicket(g_states[mi].ticket)){
         g_states[mi].ticket = 0;
         continue;
      }
      
      ulong tk = g_states[mi].ticket;
      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      double pnl       = PositionGetDouble(POSITION_PROFIT);
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int    digs      = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
      datetime now     = TimeCurrent();
      
      // SL_USD_CAP ($12 - v17.95 PROBADO)
      if(pnl < -SL_USD_Cap_Value){
         ClosePosition(tk, "SL_Cap");
         if(Use_HardCap_Cooldown) g_hardcap_cooldown = HardCap_Cooldown_Bars;
         continue;
      }
      
      // PARTIAL 1 ($6)
      if(Use_Partial_Close && !g_states[mi].partial1Done && pnl >= Partial1_USD_Trigger){
         if(DoPartialClose(tk, Partial1_Close_Pct, "L1")){
            g_states[mi].partial1Done = true;
            double nsl = NormalizeDouble(entry, digs);
            if(curSL == 0 || (pt == POSITION_TYPE_SELL && nsl < curSL) || (pt == POSITION_TYPE_BUY && nsl > curSL)){
               SetSLTP(tk, nsl, curTP);
            }
         }
      }
      
      // PARTIAL 2 ($15)
      if(Use_Partial_Close && g_states[mi].partial1Done && !g_states[mi].partial2Done && pnl >= Partial2_USD_Trigger){
         if(DoPartialClose(tk, Partial2_Close_Pct, "L2")){
            g_states[mi].partial2Done = true;
            double profit_lock = 4.0;
            double nsl = (pt == POSITION_TYPE_SELL) ? NormalizeDouble(entry - profit_lock, digs) : NormalizeDouble(entry + profit_lock, digs);
            if(curSL == 0 || (pt == POSITION_TYPE_SELL && nsl < curSL) || (pt == POSITION_TYPE_BUY && nsl > curSL)){
               SetSLTP(tk, nsl, curTP);
            }
         }
      }
      
      // TRAILING
      if(Use_Trail){
         double favorable_pts = 0;
         double current_price = (pt == POSITION_TYPE_SELL) ? SymbolInfoDouble(g_sym, SYMBOL_BID) : SymbolInfoDouble(g_sym, SYMBOL_ASK);
         
         if(pt == POSITION_TYPE_SELL) favorable_pts = (entry - current_price) / g_point;
         else favorable_pts = (current_price - entry) / g_point;
         
         if(favorable_pts >= Trail_Start_Pts){
            int e = (int)(now - g_states[mi].openTime);
            double trail_d = Trail_Dist_Phase1;
            if(e >= Trail_Phase2_Sec) trail_d = Trail_Dist_Phase3;
            else if(e >= Trail_Phase1_Sec) trail_d = Trail_Dist_Phase2;
            
            double newSL = (pt == POSITION_TYPE_SELL) ? NormalizeDouble(current_price + trail_d, digs) : NormalizeDouble(current_price - trail_d, digs);
            
            if(curSL == 0 || (pt == POSITION_TYPE_SELL && newSL < curSL) || (pt == POSITION_TYPE_BUY && newSL > curSL)){
               SetSLTP(tk, newSL, curTP);
               g_states[mi].trailActive = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|  REGISTRAR TRADE
//+------------------------------------------------------------------+
void RecordTrade(int hour, double sl_dist, double profit, double hold_sec)
{
   if(g_histCount >= 500){
      for(int i = 0; i < 450; i++) g_history[i] = g_history[i + 50];
      g_histCount = 450;
   }
   
   g_history[g_histCount].hour     = hour;
   g_history[g_histCount].sl_dist  = sl_dist;
   g_history[g_histCount].profit   = profit;
   g_history[g_histCount].hold_sec = hold_sec;
   g_history[g_histCount].is_win   = (profit > 0);
   g_histCount++;
   
   g_totalTrades++;
   
   g_hourStats[hour].n++;
   g_hourStats[hour].total_profit += profit;
   if(profit > 0) g_hourStats[hour].wins++;
   
   if(profit > 0){
      g_consecWins++;
      g_consecLosses = 0;
      g_lot_scale = MathMin(g_lot_scale * 1.30, 1.50);
   } else {
      g_consecLosses++;
      g_consecWins = 0;
      g_lot_scale = MathMax(g_lot_scale * 0.80, 0.40);
      
      if(g_consecLosses >= Max_Consec_Losses){
         g_pauseBarsLeft = Pause_Bars;
         LogDebug("PAUSA " + IntegerToString(Pause_Bars) + " barras");
      }
   }
   
   g_today_pnl += profit;
   g_weekly_pnl += profit;
}

//+------------------------------------------------------------------+
//|  ONTRADETRANSACTION
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest      &req,
                        const MqlTradeResult       &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) return;
   
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   
   double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   
   if(StringFind(comment, "partial") >= 0) return;
   
   datetime open_t = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   MqlDateTime dt;
   TimeToStruct(open_t, dt);
   
   double hold_sec = 0;
   double sl_dist = SL_Min_Points;
   
   for(int i = 0; i < 10; i++){
      if(g_states[i].ticket > 0){
         hold_sec = (double)(open_t - g_states[i].openTime);
         sl_dist = g_states[i].slDist;
         g_states[i].ticket = 0;
         break;
      }
   }
   
   RecordTrade(dt.hour, sl_dist, profit, hold_sec);
   
   LogDebug("TRADE CERRADO: profit=$" + DoubleToString(profit, 2) + " total=" + IntegerToString(g_totalTrades));
}

//+------------------------------------------------------------------+
//|  INICIALIZACIÓN
//+------------------------------------------------------------------+
void InitLearning()
{
   g_zone_pct      = M1_Zone_Pct;
   g_vel_threshold = Vel_Threshold_Base;
   g_lot_scale     = 1.0;
   g_consecLosses  = 0;
   g_consecWins    = 0;
   g_pauseBarsLeft = 0;
   g_totalTrades   = 0;
   g_hardcap_cooldown = 0;
   g_today_pnl     = 0.0;
   g_today_date    = 0;
   g_today_start_bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_daily_halted  = false;
   
   for(int i = 0; i < 10; i++){
      g_states[i].ticket       = 0;
      g_states[i].entry        = 0;
      g_states[i].slDist       = 0;
      g_states[i].tpDist       = 0;
      g_states[i].trailActive  = false;
      g_states[i].partial1Done = false;
      g_states[i].partial2Done = false;
      g_states[i].timeTrailDone = false;
      g_states[i].openTime     = 0;
   }
   
   for(int h = 0; h < 24; h++){
      g_hourStats[h].n            = 0;
      g_hourStats[h].wins         = 0;
      g_hourStats[h].total_profit = 0;
      g_hourStats[h].blocked      = false;
   }
}

//+------------------------------------------------------------------+
//|  ONINIT
//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   
   if(g_point <= 0){
      Alert("ERROR: Invalid SYMBOL_POINT");
      return INIT_FAILED;
   }
   
   InitLearning();
   
   Print("═══════════════════════════════════════════════════════");
   Print("  MONEY MACHINE v19.0 — FINAL");
   Print("═══════════════════════════════════════════════════════");
   Print("  Símbolo: ", g_sym);
   Print("  Balance Mínimo: $", Min_Balance_To_Trade);
   Print("  SL Cap: $", SL_USD_Cap_Value, " (v17.95 PROBADO)");
   Print("  Daily Limit: $", Daily_Loss_Limit_USD, " (v17.95)");
   Print("  Max Posiciones: ", Max_Positions);
   Print("  Motores: M1-M6 ACTIVOS");
   Print("  Horas: H02, H07, H15 UTC");
   Print("═══════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  ONTICK
//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   datetime now = TimeCurrent();
   
   if(g_sym == ""){
      g_sym   = _Symbol;
      g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
      g_digits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
      if(g_point <= 0){
         Alert("ERROR: Invalid SYMBOL_POINT");
         return;
      }
   }
   
   CheckDailyHalt();
   if(g_daily_halted){
      if(!g_halt_closed_today){
         CloseAllPositions("DailyHalt");
         g_halt_closed_today = true;
      }
      return;
   }
   
   CheckWeeklyHalt();
   if(g_weekly_halted) return;
   
   if(Close_On_FriClose && IsFridayClose()){
      CloseAllPositions("FriClose");
      return;
   }
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal < MIN_BALANCE_EMERGENCY){
      LogDebug("EMERGENCIA: Balance=$" + DoubleToString(bal, 2));
      CloseAllPositions("Emergency");
      return;
   }
   
   ManageOpenPositions();
   
   RunMotor1(bid, ask, now);
   RunMotor2(bid, ask, now);
   RunMotor3(bid, ask, now);
   RunMotor4(bid, ask, now);
   RunMotor5(bid, ask, now);
   RunMotor6(bid, ask, now);
   
   if(g_pauseBarsLeft > 0) g_pauseBarsLeft--;
   if(g_hardcap_cooldown > 0) g_hardcap_cooldown--;
}

//+------------------------------------------------------------------+
//|  ONDEINIT
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("MM19.0 CERRADO reason=", reason);
   Print("Total Trades: ", g_totalTrades);
   Print("Balance Final: $", AccountInfoDouble(ACCOUNT_BALANCE));
}

const double MIN_BALANCE_EMERGENCY = 15.0;
const int HardCap_Cooldown_Bars = 5;
const bool Use_HardCap_Cooldown = true;
//+------------------------------------------------------------------+