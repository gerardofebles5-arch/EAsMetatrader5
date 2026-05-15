//+------------------------------------------------------------------+
//|  MoneyMachine7_v1734.mq5                                        |
//|  v17.34 — Rango + entrada confirmada por precio en tiempo real  |
//|                                                                  |
//|  DIAGNOSTICO v17.33:                                            |
//|  3095 trades | WR=33% | Net=-$666 | DD=24%                     |
//|  Problema 1: rango dispara en casi cada barra (precio siempre  |
//|    esta en extremo de rango 20-barra → no es señal real)        |
//|  Problema 2: SL adaptativo sigue siendo muy estrecho            |
//|  Problema 3: SLs en <60s = entrada prematura                   |
//|                                                                  |
//|  INSIGHT del analisis hold-time (v17.32):                       |
//|  WR <1min=15% | WR 1-5min=42% | WR 5-15min=51%                |
//|  → Las entradas que sobreviven >1min tienen WR positivo         |
//|  → Las entradas que mueren <1min destruyen el edge              |
//|                                                                  |
//|  FIX v17.34:                                                     |
//|  Señal = precio en extremo del rango (igual que v17.33)         |
//|  PERO: la entrada se activa solo si en los ticks siguientes     |
//|  el precio CONFIRMA la dirección de la mean-reversion:          |
//|  - SELL signal: esperar que el precio baje >= Confirm_Points    |
//|    desde el close de la barra señal antes de entrar             |
//|  - BUY signal: esperar que el precio suba >= Confirm_Points     |
//|  Esto filtra los SLs inmediatos: si el precio confirma,        |
//|  ya tiene momentum en nuestra dirección                         |
//|  SL y TP basados en rango, ratio 2:1                           |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.34"
#property strict

input int    Range_Bars      = 20;    // Barras para el rango
input double Zone_Pct        = 0.15;  // % extremo del rango para señal
input double Confirm_Points  = 1.00;  // Puntos de confirmacion antes de entrar
input double SL_Range_Pct    = 0.20;  // SL como % del rango
input double TP_Ratio        = 2.0;   // TP = SL * ratio
input int    Max_Positions   = 1;
input int    InpMagicNumber  = 173400;
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
datetime g_lastBarTime = 0;

// Estado de señal pendiente
// g_pendingDir: 1=esperando confirmacion BUY, -1=SELL, 0=nada
int      g_pendingDir     = 0;
double   g_confirmLevel   = 0; // precio que debe cruzar para confirmar
double   g_pendingSL      = 0;

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
      g_pendingDir = 0; // señal consumida
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
   Print("MM7 v17.34 | ", g_sym,
         " | RangeBars=", Range_Bars, " Zone=", Zone_Pct,
         " | Confirm=", Confirm_Points,
         " | SL_pct=", SL_Range_Pct, " TP_ratio=", TP_Ratio);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(CountByMagic() >= Max_Positions) {
      g_pendingDir = 0; // cancelar señal pendiente si ya hay posicion
      return;
   }

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);

   // --- PASO 1: detectar nueva barra y generar señal ---
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      g_pendingDir  = 0; // resetear señal al inicio de barra

      // Calcular rango de las ultimas Range_Bars barras cerradas
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

      double closeNow  = iClose(g_sym, _Period, 1);
      if(closeNow == 0) return;

      double upperZone = rangeHigh - range * Zone_Pct;
      double lowerZone = rangeLow  + range * Zone_Pct;
      double slDist    = MathMax(range * SL_Range_Pct, 1.5);

      // Generar señal pendiente — la entrada se ejecutara cuando el precio confirme
      if(closeNow >= upperZone) {
         // Precio en top del rango → SELL
         // Confirma cuando el precio baje Confirm_Points desde el close actual
         g_pendingDir   = -1;
         g_confirmLevel = closeNow - Confirm_Points; // precio debe BAJAR hasta aqui
         g_pendingSL    = slDist;
      } else if(closeNow <= lowerZone) {
         // Precio en bottom del rango → BUY
         // Confirma cuando el precio suba Confirm_Points desde el close actual
         g_pendingDir   = 1;
         g_confirmLevel = closeNow + Confirm_Points; // precio debe SUBIR hasta aqui
         g_pendingSL    = slDist;
      }
   }

   // --- PASO 2: en cada tick, verificar si el precio confirma ---
   if(g_pendingDir == 0) return;

   if(g_pendingDir == 1 && bid >= g_confirmLevel) {
      // Precio subio lo suficiente → confirma BUY
      OpenOrder(ORDER_TYPE_BUY, g_pendingSL);
   } else if(g_pendingDir == -1 && ask <= g_confirmLevel) {
      // Precio bajo lo suficiente → confirma SELL
      OpenOrder(ORDER_TYPE_SELL, g_pendingSL);
   }
}
//+------------------------------------------------------------------+
