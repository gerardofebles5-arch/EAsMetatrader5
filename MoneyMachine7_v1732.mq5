//+------------------------------------------------------------------+
//|  MoneyMachine7_v1732.mq5                                        |
//|  v17.32 — Alta selectividad + SL/TP con espacio real            |
//|                                                                  |
//|  DIAGNOSTICO v17.31:                                            |
//|  6241 trades | WR=32.6% | Net=-$1996 | DD=42.8%                |
//|  Threshold=1.5 dispara en casi toda barra M1 de XAUUSD          |
//|  SL=1.5 demasiado cerca: spread+ruido lo toca antes del TP      |
//|  Math: 0.326*3.0=0.978 vs 0.674*1.5=1.011 → edge negativo      |
//|                                                                  |
//|  FIX v17.32:                                                     |
//|  - Threshold alto (5.0) → solo barras con movimiento REAL       |
//|  - SL ancho (3.0) → espacio para respirar sin SL instantaneo   |
//|  - TP (9.0) → ratio 3:1 para ser rentable con WR=33%           |
//|  - Contexto de 3 barras: no entrar contra tendencia fuerte       |
//|    (si las 3 barras previas van todas en la misma direccion,    |
//|     no hacer mean-reversion contra esa tendencia)               |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.32"
#property strict

input double Threshold_Points          = 5.00;  // Movimiento minimo de barra para señal
input double TP_Fixed                  = 9.00;  // Take Profit (ratio 3:1)
input double SL_Fixed                  = 3.00;  // Stop Loss (espacio real)
input int    Trend_Bars                = 3;     // Barras de contexto anti-tendencia
input int    Max_Positions             = 1;
input int    InpMagicNumber            = 173200;
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
// Verifica si las ultimas N barras van todas en la misma direccion
// dir=1 → chequea tendencia alcista | dir=-1 → bajista
// Retorna true si hay tendencia fuerte (no hacer reversion contra ella)
bool StrongTrend(int dir)
{
   int confirmCount = 0;
   for(int i = 2; i <= Trend_Bars + 1; i++) {
      double o = iOpen (g_sym, _Period, i);
      double c = iClose(g_sym, _Period, i);
      if(o == 0 || c == 0) return false;
      if(dir == 1  && c > o) confirmCount++;
      if(dir == -1 && c < o) confirmCount++;
   }
   return (confirmCount >= Trend_Bars);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   Print("MM7 v17.32 | ", g_sym,
         " | Threshold=", Threshold_Points,
         " | SL=", SL_Fixed, " | TP=", TP_Fixed,
         " | TrendBars=", Trend_Bars);
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
      return; // solo primer tick de cada barra
   }

   if(g_firedThisBar)                    return;
   if(CountByMagic() >= Max_Positions)   return;

   double prevOpen  = iOpen (g_sym, _Period, 1);
   double prevClose = iClose(g_sym, _Period, 1);
   if(prevOpen == 0 || prevClose == 0)   return;

   double barMove = prevClose - prevOpen;

   // MEAN REVERSION con filtro de tendencia fuerte
   // Barra bajo fuerte → BUY, pero NO si las 3 barras previas son todas bajistas
   if(barMove <= -Threshold_Points && !StrongTrend(-1))
      OpenOrder(ORDER_TYPE_BUY);
   // Barra subio fuerte → SELL, pero NO si las 3 barras previas son todas alcistas
   else if(barMove >= Threshold_Points && !StrongTrend(1))
      OpenOrder(ORDER_TYPE_SELL);
}
//+------------------------------------------------------------------+
