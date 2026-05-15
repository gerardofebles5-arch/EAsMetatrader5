//+------------------------------------------------------------------+
//|  MoneyMachine7_v1729.mq5                                        |
//|  v17.29 — Pure price action + dynamic lot only                  |
//|  Logica: precio sube → BUY | precio baja → SELL                 |
//|  Decision en cada tick, sin indicadores, sin filtros            |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.29"
#property strict

input double Threshold_Points          = 0.50;   // Movimiento minimo para señal (en precio)
input double TP_Fixed                  = 1.00;   // Take Profit fijo
input double SL_Fixed                  = 0.50;   // Stop Loss fijo
input int    Max_Positions             = 1;
input int    InpMagicNumber            = 172900;
input int    InpSlippagePoints         = 10;

// Lotaje dinamico
input bool   Use_Dynamic_Lot           = true;
input double Lot_Fixed                 = 0.01;
input double Margin_Per_Lot            = 1000.0; // Capital necesario por cada 0.01 lot
input double Max_Lot                   = 5.0;

//--- Globals
string   g_sym;
double   g_point;
int      g_magic;
double   g_lastBid = 0;

//+------------------------------------------------------------------+
double CalcLot()
{
   if(!Use_Dynamic_Lot) return NormalizeDouble(Lot_Fixed, 2);

   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   double lot = MathFloor(bal / Margin_Per_Lot) * 0.01;

   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);

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
void OpenOrder(ENUM_ORDER_TYPE type)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   int    dir   = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp    = NormalizeDouble(entry + dir * TP_Fixed, digs);
   double sl    = NormalizeDouble(entry - dir * SL_Fixed, digs);

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

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp, " lot=", req.volume);
   else
      Print("MM7 FAIL retcode=", res.retcode);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   g_lastBid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   Print("MM7 v17.29 | ", g_sym, " | Threshold=", Threshold_Points,
         " | SL=", SL_Fixed, " | TP=", TP_Fixed);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(CountByMagic() >= Max_Positions) return;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);

   // Primera inicializacion
   if(g_lastBid == 0) { g_lastBid = bid; return; }

   double delta = bid - g_lastBid;

   if(delta >= Threshold_Points)
      OpenOrder(ORDER_TYPE_BUY);
   else if(delta <= -Threshold_Points)
      OpenOrder(ORDER_TYPE_SELL);

   g_lastBid = bid;
}
//+------------------------------------------------------------------+
