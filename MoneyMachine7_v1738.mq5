//+------------------------------------------------------------------+
//|  MoneyMachine7_v1738.mq5                                        |
//|  v17.38 — Sin weekend + solo direccion de tendencia + SL ajustado|
//|                                                                  |
//|  DIAGNOSTICO v17.37:                                            |
//|  294 trades | WR=25.5% | Net=+$2159 | DD=7.08% | Sharpe=14     |
//|                                                                  |
//|  3 PROBLEMAS EXACTOS IDENTIFICADOS:                              |
//|                                                                  |
//|  1. WEEKEND GAP: Trade #119 abre viernes 22:05 → cierra lunes  |
//|     con -$165 por gap. Trade #246 igual. Fix: cerrar antes del  |
//|     viernes 21:00 UTC y no abrir el viernes despues de 20:00    |
//|                                                                  |
//|  2. BUY WR=19.5% vs SELL WR=32%: XAUUSD bajista en este        |
//|     periodo. Las BUYs van contra la tendencia macro.            |
//|     Fix: detectar pendiente del rango. Si el precio esta en     |
//|     tendencia bajista (close[1] < close[Range_Bars]) solo SELL. |
//|     Si alcista, solo BUY. Ambos si lateral.                     |
//|                                                                  |
//|  3. LOT DINAMICO amplifica perdidas en streak: cuando la cuenta |
//|     sube el lot sube, luego una racha de SLs borra varias       |
//|     ganancias. Fix: usar equity en vez de balance para CalcLot, |
//|     y reducir Margin_Per_Lot a escalar mas conservadoramente.   |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.38"
#property strict

// Señal
input int    Range_Bars          = 20;
input double Zone_Pct            = 0.15;
input double Confirm_Points      = 1.00;

// SL/TP local
input int    Local_Vol_Bars      = 3;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 2.00;
input double SL_Max              = 12.0;   // Bajado de 15 a 12
input double TP_Ratio            = 2.0;

// Filtro de velocidad
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;

// Filtro de tendencia
// Si close[1] vs close[Trend_Bars+1] define tendencia macro:
// bajista → solo SELL | alcista → solo BUY | lateral → ambos
input int    Trend_Bars          = 15;    // Barras para detectar tendencia macro
input double Trend_Min_Move      = 5.0;  // Movimiento minimo para considerar tendencia

// Weekend protection
input int    FriClose_Hour_UTC   = 20;   // No abrir nuevas pos despues de esta hora el viernes
input bool   Close_On_FriClose   = true; // Cerrar pos abiertas el viernes a FriClose_Hour_UTC

// Breakeven
input double BE_Trigger_Pct      = 0.70;
input bool   Use_Breakeven       = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Filtro horario
input bool   Use_Hour_Filter     = true;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 173800;
input int    InpSlippagePoints   = 10;

// Lotaje dinamico — mas conservador
input bool   Use_Dynamic_Lot     = true;
input double Lot_Fixed           = 0.01;
input double Margin_Per_Lot      = 1500.0;  // Subido de 1000 a 1500 = mas conservador
input double Max_Lot             = 5.0;

//--- Globals
string   g_sym;
double   g_point;
int      g_magic;
datetime g_lastBarTime = 0;

int      g_pendingDir    = 0;
double   g_confirmLevel  = 0;
double   g_pendingSL     = 0;

double   g_openEntry     = 0;
double   g_openSLDist    = 0;
int      g_openDir       = 0;
bool     g_beMoved       = false;

int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   switch(hour) {
      case 0: case 2: case 7: case 9:
      case 12: case 13: case 15:
      case 18: case 19: case 22:
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Retorna: 1=alcista (solo BUY), -1=bajista (solo SELL), 0=lateral (ambos)
int GetTrendBias()
{
   double closeNow = iClose(g_sym, _Period, 1);
   double closeOld = iClose(g_sym, _Period, Trend_Bars + 1);
   if(closeNow == 0 || closeOld == 0) return 0;
   double move = closeNow - closeOld;
   if(move <= -Trend_Min_Move) return -1;  // bajista → solo SELL
   if(move >=  Trend_Min_Move) return  1;  // alcista → solo BUY
   return 0;  // lateral → ambos
}

//+------------------------------------------------------------------+
// Verifica si es viernes despues de FriClose_Hour_UTC
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
   // Usar el MINIMO de balance y equity para proteger en drawdown
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
   double vol = PositionGetDouble(POSITION_VOLUME);
   ENUM_ORDER_TYPE close_type = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (close_type == ORDER_TYPE_SELL) ?
                  SymbolInfoDouble(g_sym, SYMBOL_BID) :
                  SymbolInfoDouble(g_sym, SYMBOL_ASK);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = vol;
   req.type      = close_type;
   req.price     = price;
   req.position  = ticket;
   req.deviation = InpSlippagePoints;
   req.magic     = g_magic;
   req.comment   = "MM7-" + reason;
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) {
      req.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(req, res)) {
         req.type_filling = ORDER_FILLING_RETURN;
         OrderSend(req, res);
      }
   }
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      Print("MM7 CLOSE ", reason, " ticket=", ticket);
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
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = g_sym;
   req.volume       = CalcLot();
   req.type         = type;
   req.price        = entry;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = InpSlippagePoints;
   req.magic        = g_magic;
   req.comment      = "MM7";
   req.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(req, res)) {
      req.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(req, res)) {
         req.type_filling = ORDER_FILLING_RETURN;
         OrderSend(req, res);
      }
   }

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) {
      g_pendingDir  = 0;
      g_openEntry   = entry;
      g_openSLDist  = sl_dist;
      g_openDir     = dir;
      g_beMoved     = false;
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp,
            " SLd=", DoubleToString(sl_dist,2), " lot=", req.volume);
   } else {
      Print("MM7 FAIL retcode=", res.retcode);
   }
}

//+------------------------------------------------------------------+
void MoveToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double bePx  = NormalizeDouble(g_openEntry, (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS));
   if(g_openDir == 1  && bePx <= curSL) return;
   if(g_openDir == -1 && bePx >= curSL) return;
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = g_sym;
   req.position = ticket;
   req.sl       = bePx;
   req.tp       = curTP;
   if(OrderSend(req, res)) Print("MM7 BE→", bePx);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
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
         g_pauseBarsLeft = Pause_Bars;
         g_pendingDir    = 0;
         Print("MM7 PAUSA ", g_consecLosses, " SLs → ", Pause_Bars, " barras");
      }
   } else {
      g_consecLosses = 0;
   }
   g_openEntry  = 0;
   g_openSLDist = 0;
   g_openDir    = 0;
   g_beMoved    = false;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   Print("MM7 v17.38 | ", g_sym,
         " | LocalSL=", Local_Vol_Bars, "x", SL_Local_Pct, "[", SL_Min, "-", SL_Max, "]",
         " | Vel<=", Vel_Threshold,
         " | Trend=", Trend_Bars, "bars/", Trend_Min_Move, "pts",
         " | FriClose=", FriClose_Hour_UTC, "h",
         " | Margin/lot=", Margin_Per_Lot);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);

   // --- PROTECCION WEEKEND: cerrar pos abiertas el viernes ---
   if(Close_On_FriClose && IsFridayClose()) {
      ulong tk = GetOpenTicket();
      if(tk > 0) ClosePosition(tk, "FriClose");
      g_pendingDir = 0;
      return;
   }

   // --- BREAKEVEN ---
   ulong ticket = GetOpenTicket();
   if(ticket > 0 && Use_Breakeven && !g_beMoved && g_openEntry > 0 && g_openSLDist > 0) {
      double beThreshold = g_openEntry + g_openDir * g_openSLDist * BE_Trigger_Pct;
      if((g_openDir == 1 && bid >= beThreshold) ||
         (g_openDir == -1 && ask <= beThreshold)) {
         MoveToBreakeven(ticket);
         g_beMoved = true;
      }
   }

   if(CountByMagic() >= Max_Positions) { g_pendingDir = 0; return; }

   // --- NUEVA BARRA ---
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      g_pendingDir  = 0;

      if(g_pauseBarsLeft > 0) { g_pauseBarsLeft--; return; }

      // No abrir el viernes tarde
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC) return;

      // Filtro horario
      if(!IsGoodHour(dt.hour)) return;

      // Filtro velocidad
      double closeOld = iClose(g_sym, _Period, Vel_Bars + 1);
      double closeNew = iClose(g_sym, _Period, 1);
      if(closeOld > 0 && closeNew > 0) {
         double vel = MathAbs(closeNew - closeOld) / Vel_Bars;
         if(vel > Vel_Threshold) return;
      }

      // Sesgo de tendencia macro
      int trendBias = GetTrendBias();

      // Rango de señal
      double rangeHigh = -DBL_MAX, rangeLow = DBL_MAX;
      for(int i = 1; i <= Range_Bars; i++) {
         double h = iHigh(g_sym, _Period, i);
         double l = iLow (g_sym, _Period, i);
         if(h == 0 || l == 0) return;
         if(h > rangeHigh) rangeHigh = h;
         if(l < rangeLow)  rangeLow  = l;
      }
      double range = rangeHigh - rangeLow;
      if(range <= 0) return;

      double closeNow  = iClose(g_sym, _Period, 1);
      if(closeNow == 0) return;

      double upperZone = rangeHigh - range * Zone_Pct;
      double lowerZone = rangeLow  + range * Zone_Pct;

      // SL local
      double localHigh = -DBL_MAX, localLow = DBL_MAX;
      for(int i = 1; i <= Local_Vol_Bars; i++) {
         double h = iHigh(g_sym, _Period, i);
         double l = iLow (g_sym, _Period, i);
         if(h > localHigh) localHigh = h;
         if(l < localLow)  localLow  = l;
      }
      double slDist = MathMax(MathMin((localHigh - localLow) * SL_Local_Pct, SL_Max), SL_Min);

      // Señal filtrada por tendencia
      // trendBias=-1 (bajista) → solo SELL (precio en top → SELL ✓, precio en bottom → BUY ✗)
      // trendBias= 1 (alcista) → solo BUY  (precio en bottom → BUY ✓, precio en top → SELL ✗)
      // trendBias= 0 (lateral) → ambos
      if(closeNow >= upperZone) {
         if(trendBias != 1) {  // No hacer SELL si tendencia alcista fuerte
            g_pendingDir   = -1;
            g_confirmLevel = closeNow - Confirm_Points;
            g_pendingSL    = slDist;
         }
      } else if(closeNow <= lowerZone) {
         if(trendBias != -1) {  // No hacer BUY si tendencia bajista fuerte
            g_pendingDir   = 1;
            g_confirmLevel = closeNow + Confirm_Points;
            g_pendingSL    = slDist;
         }
      }
      return;
   }

   if(g_pauseBarsLeft > 0) return;
   if(g_pendingDir == 0)   return;

   // Verificar hora y weekend en tick
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(!IsGoodHour(dt.hour)) { g_pendingDir = 0; return; }
   if(dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC) { g_pendingDir = 0; return; }

   if(g_pendingDir == 1 && bid >= g_confirmLevel)
      OpenOrder(ORDER_TYPE_BUY, g_pendingSL);
   else if(g_pendingDir == -1 && ask <= g_confirmLevel)
      OpenOrder(ORDER_TYPE_SELL, g_pendingSL);
}
//+------------------------------------------------------------------+
