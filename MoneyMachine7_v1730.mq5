//+------------------------------------------------------------------+
//|  MoneyMachine7_v1730.mq5                                        |
//|  v17.30 — Momentum en ventana de tiempo, no tick-a-tick         |
//|                                                                  |
//|  DIAGNOSTICO v17.29:                                            |
//|  62163 trades | WR=33.5% | Net=-$4491 | DD=89.83%              |
//|  Causa: delta tick-a-tick = ruido puro. Sin edge estadistico.   |
//|  El spread consume el SL antes de que el precio se mueva.       |
//|                                                                  |
//|  FIX v17.30:                                                    |
//|  El precio de referencia es el bid hace N segundos (no el tick  |
//|  anterior). Si en esa ventana el precio subio >= Threshold       |
//|  → BUY. Si bajo >= Threshold → SELL.                           |
//|  Esto mide momentum real, no ruido de microsegundo.             |
//|  Una sola entrada por ventana (cooldown post-entrada).          |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.30"
#property strict

input int    Momentum_Window_Sec       = 10;    // Ventana de tiempo para medir momentum (segundos)
input double Threshold_Points          = 2.00;  // Movimiento minimo en la ventana para señal
input double TP_Fixed                  = 3.00;  // Take Profit fijo
input double SL_Fixed                  = 1.50;  // Stop Loss fijo
input int    Cooldown_Sec              = 5;     // Segundos de espera despues de abrir orden
input int    Max_Positions             = 1;
input int    InpMagicNumber            = 173000;
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
datetime g_lastOrderTime = 0;

// Historial de precios para medir momentum en ventana
#define  HIST_SIZE 600
double   g_bidHist[HIST_SIZE];
datetime g_timeHist[HIST_SIZE];
int      g_histHead = 0;
int      g_histCount = 0;

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

   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) {
      g_lastOrderTime = TimeCurrent();
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp, " lot=", req.volume);
   } else {
      Print("MM7 FAIL retcode=", res.retcode);
   }
}

//+------------------------------------------------------------------+
// Agrega el bid actual al historial circular
void PushHistory(double bid, datetime t)
{
   g_bidHist[g_histHead]  = bid;
   g_timeHist[g_histHead] = t;
   g_histHead = (g_histHead + 1) % HIST_SIZE;
   if(g_histCount < HIST_SIZE) g_histCount++;
}

//+------------------------------------------------------------------+
// Devuelve el bid mas antiguo dentro de la ventana de tiempo
// Retorna 0 si no hay suficiente historia
double GetWindowRefPrice(datetime now)
{
   if(g_histCount == 0) return 0;
   datetime cutoff = now - Momentum_Window_Sec;
   // Recorrer historial buscando el punto mas antiguo dentro de la ventana
   double refBid = 0;
   datetime refTime = now; // inicializamos con el mas reciente
   for(int i = 0; i < g_histCount; i++) {
      int idx = (g_histHead - 1 - i + HIST_SIZE) % HIST_SIZE;
      if(g_timeHist[idx] >= cutoff) {
         refBid  = g_bidHist[idx];
         refTime = g_timeHist[idx];
      } else {
         break; // ya salimos de la ventana
      }
   }
   // Solo valido si el punto de referencia esta cerca del inicio de la ventana
   if(refBid == 0) return 0;
   if((now - refTime) < Momentum_Window_Sec / 2) return 0; // ventana aun no llena
   return refBid;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym   = _Symbol;
   g_magic = InpMagicNumber;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   ArrayInitialize(g_bidHist,  0);
   ArrayInitialize(g_timeHist, 0);
   Print("MM7 v17.30 | ", g_sym,
         " | Window=", Momentum_Window_Sec, "s",
         " | Threshold=", Threshold_Points,
         " | SL=", SL_Fixed, " | TP=", TP_Fixed,
         " | Cooldown=", Cooldown_Sec, "s");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   double   bid = SymbolInfoDouble(g_sym, SYMBOL_BID);

   // Siempre registrar precio en historial
   PushHistory(bid, now);

   // Cooldown tras ultima orden
   if((now - g_lastOrderTime) < Cooldown_Sec) return;

   // Ya hay posicion abierta
   if(CountByMagic() >= Max_Positions) return;

   // Obtener precio de referencia hace N segundos
   double refBid = GetWindowRefPrice(now);
   if(refBid == 0) return;

   double delta = bid - refBid;

   if(delta >= Threshold_Points)
      OpenOrder(ORDER_TYPE_BUY);
   else if(delta <= -Threshold_Points)
      OpenOrder(ORDER_TYPE_SELL);
}
//+------------------------------------------------------------------+
