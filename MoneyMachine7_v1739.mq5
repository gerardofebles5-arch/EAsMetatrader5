//+------------------------------------------------------------------+
//|  MoneyMachine7_v1739.mq5                                        |
//|  v17.39 — Fusion v17.37+v17.38: lot dinamico + tendencia + weekend|
//|                                                                  |
//|  COMPARATIVA:                                                    |
//|  v17.37: 294 trades | Net=+$2159 | WR=25.5% | AvgTP=$98        |
//|          Lot dinamico 0.04-0.07 | DD=7%                         |
//|          PROBLEMA: BUY contra tendencia + weekend gaps           |
//|                                                                  |
//|  v17.38: 135 trades | Net=+$662  | WR=27.4% | AvgTP=$44        |
//|          Lot FIJO 0.03 (Margin=1500 paraliza el scaling)        |
//|          BUENO: sin weekend gaps, trend filter funciona          |
//|                                                                  |
//|  FUSION v17.39:                                                  |
//|  + Lot dinamico de v17.37 (Margin=1000) → escala con cuenta     |
//|  + Filtro tendencia de v17.38 → no BUY en bajista              |
//|  + Proteccion weekend de v17.38 → sin gaps                      |
//|  + Horas refinadas: quitar 12h y 18h (negativas en v17.38)     |
//|    Mantener: 0,2,7,9,13,15,19,22 (todas positivas)             |
//|  + SL_Max=12 (v17.38) — limita perdidas grandes                 |
//|  + BE en 70% del TP (igual en ambas)                            |
//|  + Pausa anti-racha tras 3 SLs (igual)                         |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.39"
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
input double TP_Ratio            = 2.0;

// Filtro velocidad
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;

// Filtro tendencia
input int    Trend_Bars          = 15;
input double Trend_Min_Move      = 5.0;

// Weekend
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// Breakeven
input double BE_Trigger_Pct      = 0.70;
input bool   Use_Breakeven       = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Filtro horario refinado
// Horas positivas en AMBAS versiones v17.37 y v17.38:
// 0(+6.34), 2(+9.21), 7(+6.74), 9(+0.48), 13(+5.67), 15(+24.58), 19(+5.75), 22(+4.68)
// Eliminadas: 12(-3.61) y 18(-4.11) — negativas en v17.38
input bool   Use_Hour_Filter     = true;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 173900;
input int    InpSlippagePoints   = 10;

// Lotaje dinamico — volver a v17.37 (1000/lot)
input bool   Use_Dynamic_Lot     = true;
input double Lot_Fixed           = 0.01;
input double Margin_Per_Lot      = 1000.0;
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
// Horas con edge positivo demostrado en AMBAS versiones
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // 0,2,7,9,13,15,19,22 — todas positivas en v17.37 y v17.38
   // 12 y 18 eliminadas (negativas en v17.38)
   switch(hour) {
      case 0: case 2: case 7: case 9:
      case 13: case 15: case 19: case 22:
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Tendencia macro: bajista=-1, alcista=1, lateral=0
int GetTrendBias()
{
   double closeNow = iClose(g_sym, _Period, 1);
   double closeOld = iClose(g_sym, _Period, Trend_Bars + 1);
   if(closeNow == 0 || closeOld == 0) return 0;
   double move = closeNow - closeOld;
   if(move <= -Trend_Min_Move) return -1;
   if(move >=  Trend_Min_Move) return  1;
   return 0;
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
   double price = (ct == ORDER_TYPE_SELL) ?
                  SymbolInfoDouble(g_sym, SYMBOL_BID) :
                  SymbolInfoDouble(g_sym, SYMBOL_ASK);
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = vol;
   req.type      = ct;
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
   Print("MM7 v17.39 | ", g_sym,
         " | Horas:0,2,7,9,13,15,19,22",
         " | SL_local=", Local_Vol_Bars, "x", SL_Local_Pct, "[", SL_Min, "-", SL_Max, "]",
         " | TP=", TP_Ratio, "x | BE@", BE_Trigger_Pct,
         " | Vel<=", Vel_Threshold,
         " | Trend=", Trend_Bars, "b/", Trend_Min_Move, "pts",
         " | Margin/lot=", Margin_Per_Lot,
         " | FriClose=", FriClose_Hour_UTC, "h");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);

   // --- WEEKEND: cerrar y bloquear el viernes tarde ---
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

      MqlDateTime dt;
      TimeToStruct(curBar, dt);

      // No abrir el viernes tarde
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

      // Tendencia macro
      int trendBias = GetTrendBias();

      // Rango señal (20 barras)
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

      double closeNow = iClose(g_sym, _Period, 1);
      if(closeNow == 0) return;

      double upperZone = rangeHigh - range * Zone_Pct;
      double lowerZone = rangeLow  + range * Zone_Pct;

      // SL local (3 barras)
      double lH = -DBL_MAX, lL = DBL_MAX;
      for(int i = 1; i <= Local_Vol_Bars; i++) {
         double h = iHigh(g_sym, _Period, i);
         double l = iLow (g_sym, _Period, i);
         if(h > lH) lH = h;
         if(l < lL) lL = l;
      }
      double slDist = MathMax(MathMin((lH - lL) * SL_Local_Pct, SL_Max), SL_Min);

      // Señal con filtro de tendencia
      if(closeNow >= upperZone && trendBias != 1) {
         g_pendingDir   = -1;
         g_confirmLevel = closeNow - Confirm_Points;
         g_pendingSL    = slDist;
      } else if(closeNow <= lowerZone && trendBias != -1) {
         g_pendingDir   = 1;
         g_confirmLevel = closeNow + Confirm_Points;
         g_pendingSL    = slDist;
      }
      return;
   }

   if(g_pauseBarsLeft > 0) return;
   if(g_pendingDir == 0)   return;

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
