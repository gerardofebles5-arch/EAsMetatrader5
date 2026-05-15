//+------------------------------------------------------------------+
//|  MoneyMachine7_v1731.mq5                                        |
//|  v17.31 — Mean-reversion pura en barra cerrada                  |
//|                                                                  |
//|  DIAGNOSTICO v17.30:                                            |
//|  14549 trades | WR=32.4% | Net=-$3232 | DD=66%                 |
//|  Bug: ventana de tiempo no funcionaba, seguia siendo tick noise |
//|  Ademas: seguir momentum en microestructura = edge NEGATIVO.    |
//|  XAUUSD revierte en ventanas cortas. Habia que invertir.        |
//|                                                                  |
//|  LOGICA v17.31:                                                  |
//|  - Decision basada en cierre de barra cerrada (indice 1)        |
//|  - Barra bajo >= Threshold → BUY (espera rebote)                |
//|  - Barra subio >= Threshold → SELL (espera caida)               |
//|  - Una sola entrada por barra nueva (primer tick)               |
//|  - Sin re-entradas hasta la siguiente barra                     |
//|  - Lotaje dinamico intacto                                       |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.31"
#property strict

input double Threshold_Points          = 1.50;  // Movimiento minimo de barra para señal
input double TP_Fixed                  = 3.00;  // Take Profit
input double SL_Fixed                  = 1.50;  // Stop Loss
input int    Max_Positions             = 1;
input int    InpMagicNumber            = 173100;
input int    InpSlippagePoints         = 10;

// Lotaje dinamico
input bool   Use_Dynamic_Lot           = true;
input double Lot_Fixed                 = 0.01;
input double Margin_Per_Lot            = 1000.0;
input double Max_Lot                   = 5.0;

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

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) {
      g_firedThisBar = true;
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp, " lot=", req.volume);
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
   Print("MM7 v17.31 | ", g_sym,
         " | Threshold=", Threshold_Points,
         " | SL=", SL_Fixed, " | TP=", TP_Fixed);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime curBar  = iTime(g_sym, _Period, 0);
   bool     newBar  = (curBar != g_lastBarTime);

   if(newBar) {
      g_lastBarTime  = curBar;
      g_firedThisBar = false;
   } else {
      return; // solo actuamos en el primer tick de cada barra
   }

   if(g_firedThisBar)        return;
   if(CountByMagic() >= Max_Positions) return;

   // Leer barra cerrada (indice 1)
   double prevOpen  = iOpen (g_sym, _Period, 1);
   double prevClose = iClose(g_sym, _Period, 1);
   if(prevOpen == 0 || prevClose == 0) return;

   double barMove = prevClose - prevOpen;

   // MEAN REVERSION
   // Barra bajo fuerte → precio probablemente rebota → BUY
   // Barra subio fuerte → precio probablemente cae  → SELL
   if(barMove <= -Threshold_Points)
      OpenOrder(ORDER_TYPE_BUY);
   else if(barMove >= Threshold_Points)
      OpenOrder(ORDER_TYPE_SELL);
}
//+------------------------------------------------------------------+
