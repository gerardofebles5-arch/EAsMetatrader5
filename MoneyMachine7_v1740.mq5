//+------------------------------------------------------------------+
//|  MoneyMachine7_v1740.mq5                                        |
//|  v17.40 — TP 3x + trailing temporal + calidad entrada           |
//|                                                                  |
//|  DIAGNOSTICO v17.39:                                            |
//|  108 trades | WR=29.6% | Net=+$1312 | DD=4.13%                 |
//|  Required WR = 23.5% → margen de seguridad: +6.1%              |
//|                                                                  |
//|  OPORTUNIDADES IDENTIFICADAS:                                    |
//|                                                                  |
//|  1. TP_RATIO BAJO: mercado entrega 3.25x real, configurado 2.0x |
//|     Con WR=29.6%:                                               |
//|     Ratio 2.0x → breakeven 33.3% → estamos DEBAJO              |
//|     Ratio 3.0x → breakeven 25.0% → estamos ENCIMA (+4.6%)      |
//|     Simulacion: +$1,266 extra solo subiendo el ratio            |
//|                                                                  |
//|  2. BIG LOSSES (-$818): 18 trades con hold >10min que           |
//|     no alcanzan TP y revierten fuerte. Son el 66% de todas      |
//|     las perdidas. Fix: trailing stop temporal.                  |
//|     Si tras Time_Trail_Sec segundos la pos no alcanzó           |
//|     el Trail_Profit_Pct% del TP, apretar SL a breakeven        |
//|     Esto convierte perdidas de -$40-80 en cero o pequeñas      |
//|                                                                  |
//|  3. BUY WR=22.6% vs SELL WR=36.4% — diferencia de 14%         |
//|     Ajustar Trend_Min_Move para ser aun mas selectivo con BUY  |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.40"
#property strict

// Señal
input int    Range_Bars          = 20;
input double Zone_Pct            = 0.15;
input double Confirm_Points      = 1.00;

// SL/TP local
input int    Local_Vol_Bars      = 3;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 2.00;
input double SL_Max              = 12.0;
input double TP_Ratio            = 3.0;   // ← SUBIDO de 2.0 a 3.0 (mercado entrega 3.25x)

// Trailing stop temporal
// Si tras Time_Trail_Sec segundos el precio no ha alcanzado
// Trail_Progress_Pct × SL_dist en nuestro favor → mover SL a BE
input int    Time_Trail_Sec      = 600;   // 10 minutos → chequear progreso
input double Trail_Progress_Pct  = 0.40;  // Si no alcanzó 40% del SL_dist → mover BE
input bool   Use_Time_Trail      = true;

// Filtro velocidad
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;

// Filtro tendencia — más estricto para BUY (subido de 5 a 8)
input int    Trend_Bars          = 15;
input double Trend_Min_Move_Sell = 5.0;   // SELL: umbral normal
input double Trend_Min_Move_Buy  = 8.0;   // BUY: umbral más alto (más selectivo)

// Weekend
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// Breakeven
input double BE_Trigger_Pct      = 0.70;
input bool   Use_Breakeven       = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Filtro horario: 0,2,7,9,13,15,19,22
input bool   Use_Hour_Filter     = true;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 174000;
input int    InpSlippagePoints   = 10;

// Lotaje dinamico
input bool   Use_Dynamic_Lot     = true;
input double Lot_Fixed           = 0.01;
input double Margin_Per_Lot      = 1000.0;
input double Max_Lot             = 5.0;

//--- Globals
string   g_sym;
double   g_point;
int      g_magic;
datetime g_lastBarTime  = 0;

int      g_pendingDir    = 0;
double   g_confirmLevel  = 0;
double   g_pendingSL     = 0;

double   g_openEntry     = 0;
double   g_openSLDist    = 0;
int      g_openDir       = 0;
bool     g_beMoved       = false;
datetime g_openTime      = 0;   // Para trailing temporal
bool     g_timeTrailDone = false;

int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   switch(hour) {
      case 0: case 2: case 7: case 9:
      case 13: case 15: case 19: case 22:
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Tendencia: dir=1 para BUY signal, dir=-1 para SELL signal
// Retorna true si la tendencia va CONTRA esa dirección → bloquear
bool TrendBlocks(int signalDir)
{
   double closeNow = iClose(g_sym, _Period, 1);
   double closeOld = iClose(g_sym, _Period, Trend_Bars + 1);
   if(closeNow == 0 || closeOld == 0) return false;
   double move = closeNow - closeOld;
   
   if(signalDir == 1) {
      // BUY: bloqueado si mercado bajista fuerte
      return (move <= -Trend_Min_Move_Buy);
   } else {
      // SELL: bloqueado si mercado alcista fuerte
      return (move >= Trend_Min_Move_Sell);
   }
}

//+------------------------------------------------------------------+
bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC);
}

//+------------------------------------------------------------------+
double CalcLot()
{
   if(!Use_Dynamic_Lot) return NormalizeDouble(Lot_Fixed, 2);
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   double lot = MathFloor(bal / Margin_Per_Lot) * 0.01;
   double mn  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, mn);
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st > 0) lot = MathFloor(lot / st) * st;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
int CountByMagic()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == g_magic) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
ulong GetOpenTicket()
{
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == g_magic) return tk;
   }
   return 0;
}

//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double vol   = PositionGetDouble(POSITION_VOLUME);
   ENUM_ORDER_TYPE ct = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (ct == ORDER_TYPE_SELL) ? SymbolInfoDouble(g_sym, SYMBOL_BID)
                                          : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym; req.volume = vol; req.type = ct;
   req.price     = price; req.position = ticket;
   req.deviation = InpSlippagePoints; req.magic = g_magic;
   req.comment   = "MM7-" + reason;
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) { req.type_filling = ORDER_FILLING_IOC; if(!OrderSend(req,res)) { req.type_filling=ORDER_FILLING_RETURN; OrderSend(req,res); } }
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      Print("MM7 CLOSE ", reason);
}

//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type, double sl_dist)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   int    dir   = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp    = NormalizeDouble(entry + dir * sl_dist * TP_Ratio, digs);
   double sl    = NormalizeDouble(entry - dir * sl_dist, digs);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL; req.symbol = g_sym;
   req.volume       = CalcLot(); req.type = type; req.price = entry;
   req.sl           = sl; req.tp = tp; req.deviation = InpSlippagePoints;
   req.magic        = g_magic; req.comment = "MM7";
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) { req.type_filling = ORDER_FILLING_IOC; if(!OrderSend(req,res)) { req.type_filling=ORDER_FILLING_RETURN; OrderSend(req,res); } }

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) {
      g_pendingDir   = 0; g_openEntry = entry; g_openSLDist = sl_dist;
      g_openDir      = dir; g_beMoved = false;
      g_openTime     = TimeCurrent(); g_timeTrailDone = false;
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp,
            " SLd=", DoubleToString(sl_dist,2), " lot=", req.volume);
   } else { Print("MM7 FAIL retcode=", res.retcode); }
}

//+------------------------------------------------------------------+
void MoveSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   newSL = NormalizeDouble(newSL, digs);
   if(g_openDir == 1  && newSL <= curSL) return;
   if(g_openDir == -1 && newSL >= curSL) return;
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action = TRADE_ACTION_SLTP; req.symbol = g_sym;
   req.position = ticket; req.sl = newSL; req.tp = curTP;
   if(OrderSend(req, res)) Print("MM7 SL→", newSL);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   if(StringFind(comment, "sl") >= 0 && profit < -0.5) {
      g_consecLosses++;
      if(g_consecLosses >= Max_Consec_Losses) {
         g_pauseBarsLeft = Pause_Bars; g_pendingDir = 0;
         Print("MM7 PAUSA ", g_consecLosses, " SLs → ", Pause_Bars, " barras");
      }
   } else { g_consecLosses = 0; }
   g_openEntry = 0; g_openSLDist = 0; g_openDir = 0;
   g_beMoved = false; g_openTime = 0; g_timeTrailDone = false;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol; g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   Print("MM7 v17.40 | ", g_sym,
         " | TP=", TP_Ratio, "x SL_Max=", SL_Max,
         " | BE@", BE_Trigger_Pct, "x Trail@", Time_Trail_Sec, "s/", Trail_Progress_Pct,
         " | Vel<=", Vel_Threshold,
         " | TrendBUY>=", Trend_Min_Move_Buy, " TrendSELL>=", Trend_Min_Move_Sell,
         " | Margin/lot=", Margin_Per_Lot);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);

   // --- WEEKEND ---
   if(Close_On_FriClose && IsFridayClose()) {
      ulong tk = GetOpenTicket();
      if(tk > 0) ClosePosition(tk, "FriClose");
      g_pendingDir = 0; return;
   }

   // --- GESTIÓN DE POSICION ABIERTA ---
   ulong ticket = GetOpenTicket();
   if(ticket > 0 && g_openEntry > 0 && g_openSLDist > 0) {
      datetime now = TimeCurrent();
      double favorable = g_openDir == 1 ? (bid - g_openEntry) : (g_openEntry - ask);

      // 1. BREAKEVEN clásico: cuando precio llega al 70% del TP
      if(Use_Breakeven && !g_beMoved) {
         double beThreshold = g_openSLDist * BE_Trigger_Pct;
         if(favorable >= beThreshold) {
            MoveSL(ticket, g_openEntry);
            g_beMoved = true;
            g_timeTrailDone = true; // no hace falta trailing temporal si ya hay BE
         }
      }

      // 2. TRAILING TEMPORAL: si pasaron Time_Trail_Sec y no progresó suficiente
      // Solo si el BE aún no se movió
      if(Use_Time_Trail && !g_timeTrailDone && !g_beMoved && g_openTime > 0) {
         if((now - g_openTime) >= Time_Trail_Sec) {
            double minProgress = g_openSLDist * Trail_Progress_Pct;
            if(favorable < minProgress) {
               // No progresó lo suficiente → mover SL a breakeven para proteger
               MoveSL(ticket, g_openEntry);
               g_timeTrailDone = true;
               Print("MM7 TIME-TRAIL: progreso=", DoubleToString(favorable,2),
                     " < ", DoubleToString(minProgress,2), " → BE");
            } else {
               g_timeTrailDone = true; // progresó bien, no hacer nada más
            }
         }
      }
   }

   if(CountByMagic() >= Max_Positions) { g_pendingDir = 0; return; }

   // --- NUEVA BARRA ---
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      g_pendingDir  = 0;
      if(g_pauseBarsLeft > 0) { g_pauseBarsLeft--; return; }

      MqlDateTime dt; TimeToStruct(curBar, dt);
      if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC) return;
      if(!IsGoodHour(dt.hour)) return;

      // Velocidad
      double cv = iClose(g_sym, _Period, Vel_Bars + 1);
      double cn = iClose(g_sym, _Period, 1);
      if(cv > 0 && cn > 0 && MathAbs(cn - cv) / Vel_Bars > Vel_Threshold) return;

      // Rango señal
      double rH = -DBL_MAX, rL = DBL_MAX;
      for(int i = 1; i <= Range_Bars; i++) {
         double h = iHigh(g_sym, _Period, i), l = iLow(g_sym, _Period, i);
         if(h == 0 || l == 0) return;
         if(h > rH) rH = h;
         if(l < rL) rL = l;
      }
      double range = rH - rL;
      if(range <= 0) return;
      double closeNow = iClose(g_sym, _Period, 1);
      if(closeNow == 0) return;

      double upperZone = rH - range * Zone_Pct;
      double lowerZone = rL + range * Zone_Pct;

      // SL local
      double lH = -DBL_MAX, lL = DBL_MAX;
      for(int i = 1; i <= Local_Vol_Bars; i++) {
         double h = iHigh(g_sym, _Period, i), l = iLow(g_sym, _Period, i);
         if(h > lH) lH = h;
         if(l < lL) lL = l;
      }
      double slDist = MathMax(MathMin((lH - lL) * SL_Local_Pct, SL_Max), SL_Min);

      // Señal con filtro de tendencia asimétrico
      if(closeNow >= upperZone && !TrendBlocks(-1)) {
         g_pendingDir   = -1;
         g_confirmLevel = closeNow - Confirm_Points;
         g_pendingSL    = slDist;
      } else if(closeNow <= lowerZone && !TrendBlocks(1)) {
         g_pendingDir   = 1;
         g_confirmLevel = closeNow + Confirm_Points;
         g_pendingSL    = slDist;
      }
      return;
   }

   if(g_pauseBarsLeft > 0) return;
   if(g_pendingDir == 0)   return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(!IsGoodHour(dt.hour)) { g_pendingDir = 0; return; }
   if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC) { g_pendingDir = 0; return; }

   if(g_pendingDir == 1 && bid >= g_confirmLevel)
      OpenOrder(ORDER_TYPE_BUY, g_pendingSL);
   else if(g_pendingDir == -1 && ask <= g_confirmLevel)
      OpenOrder(ORDER_TYPE_SELL, g_pendingSL);
}
//+------------------------------------------------------------------+
