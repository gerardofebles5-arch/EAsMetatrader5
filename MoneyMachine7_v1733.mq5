//+------------------------------------------------------------------+
//|  MoneyMachine7_v1733.mq5                                        |
//|  v17.33 — Posicion en rango + SL/TP adaptativo                 |
//|                                                                  |
//|  DIAGNOSTICO v17.32:                                            |
//|  754 trades | WR=26% | Net=-$234 | DD=12.2%                    |
//|  Problema: mean-reversion contra impulso de 1 barra NO funciona |
//|  64% de SLs en <60s — el impulso continua, no revierte         |
//|  Una barra fuerte aislada no predice reversal                   |
//|                                                                  |
//|  INSIGHT: La reversal ocurre cuando el precio esta en extremo  |
//|  estadistico de su RANGO RECIENTE, no por una barra sola        |
//|                                                                  |
//|  LOGICA v17.33:                                                  |
//|  1. Calcular rango (High-Low) de las ultimas Range_Bars barras  |
//|  2. Si close actual > RangeHigh - (rango * Zone) → SELL        |
//|  3. Si close actual < RangeLow  + (rango * Zone) → BUY         |
//|  4. SL = fraccion del rango (adaptativo)                        |
//|  5. TP = 2x el SL (ratio 2:1 minimo)                           |
//|  6. Solo una entrada por barra                                  |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.33"
#property strict

input int    Range_Bars     = 20;    // Barras para calcular el rango
input double Zone_Pct       = 0.20;  // % del rango que define extremo (0.20 = top/bottom 20%)
input double SL_Range_Pct   = 0.15;  // SL como fraccion del rango
input double TP_Ratio        = 2.0;  // TP = SL * ratio
input int    Max_Positions  = 1;
input int    InpMagicNumber = 173300;
input int    InpSlippagePoints = 10;

// Lotaje dinamico
input bool   Use_Dynamic_Lot    = true;
input double Lot_Fixed          = 0.01;
input double Margin_Per_Lot     = 1000.0;
input double Max_Lot            = 5.0;

//--- Globals
string   g_sym;
double   g_point;
int      g_magic;
datetime g_lastBarTime  = 0;
bool     g_firedThisBar = false;

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
      g_firedThisBar = true;
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp,
            " SL_dist=", DoubleToString(sl_dist,2), " lot=", req.volume);
   } else {
      Print("MM7 FAIL retcode=", res.retcode);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   Print("MM7 v17.33 | ", g_sym,
         " | RangeBars=", Range_Bars,
         " | Zone=", Zone_Pct,
         " | SL_pct=", SL_Range_Pct,
         " | TP_ratio=", TP_Ratio);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime curBar = iTime(g_sym, _Period, 0);
   bool     newBar = (curBar != g_lastBarTime);

   if(newBar) {
      g_lastBarTime  = curBar;
      g_firedThisBar = false;
   } else {
      return;
   }

   if(g_firedThisBar)                  return;
   if(CountByMagic() >= Max_Positions) return;

   // Calcular rango de las ultimas Range_Bars barras cerradas (indices 1..Range_Bars)
   double rangeHigh = -DBL_MAX;
   double rangeLow  =  DBL_MAX;
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

   // Zonas de extremo
   double upperZone = rangeHigh - range * Zone_Pct; // top 20% del rango
   double lowerZone = rangeLow  + range * Zone_Pct; // bottom 20% del rango

   // SL adaptativo: fraccion del rango total
   double slDist = range * SL_Range_Pct;
   // Minimo absoluto para no ser ridiculo en mercado quieto
   double minSL = 1.0;
   if(slDist < minSL) slDist = minSL;

   // SEÑAL: precio en extremo del rango → mean-reversion
   if(closeNow >= upperZone)
      OpenOrder(ORDER_TYPE_SELL, slDist);
   else if(closeNow <= lowerZone)
      OpenOrder(ORDER_TYPE_BUY, slDist);
}
//+------------------------------------------------------------------+
