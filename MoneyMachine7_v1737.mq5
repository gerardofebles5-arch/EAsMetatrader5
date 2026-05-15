//+------------------------------------------------------------------+
//|  MoneyMachine7_v1737.mq5                                        |
//|  v17.37 — Filtro de velocidad + SL basado en volatilidad local  |
//|                                                                  |
//|  DIAGNOSTICO v17.36:                                            |
//|  742 trades | WR=25.1% | Net=+$410 ← PRIMER POSITIVO           |
//|  Factor Beneficio: 1.07 | Sharpe: 7.05                         |
//|                                                                  |
//|  PROBLEMAS IDENTIFICADOS:                                        |
//|  1. Big losses (>$30): velocidad promedio = 8.06               |
//|     Cuando el mercado cae 80-100pts en pocos minutos,           |
//|     el SL calculado sobre rango-20 es enorme → perdida masiva   |
//|  2. Vel>10: -$177 neto. Eliminarlos = +$202 al resultado        |
//|  3. SL calculado sobre rango-20 no refleja volatilidad LOCAL    |
//|     El rango-20 puede ser de 20pts pero ahora el mercado        |
//|     mueve 10pts por minuto → SL de 4pts se traga inmediatamente |
//|                                                                  |
//|  FIX v17.37:                                                     |
//|  1. FILTRO VELOCIDAD: medir movimiento de las ultimas           |
//|     Vel_Bars barras cerradas. Si precio se movio mas de          |
//|     Vel_Threshold puntos por barra → mercado trending → skip    |
//|  2. SL LOCAL: SL = max(rango ultimas 3 barras, min_SL)         |
//|     Captura la volatilidad ACTUAL, no la histórica              |
//|  3. Mantener: filtro horario, BE automatico, pausa anti-racha   |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.37"
#property strict

// Señal
input int    Range_Bars          = 20;    // Barras para zona de señal
input double Zone_Pct            = 0.15;  // % extremo para señal
input double Confirm_Points      = 1.00;  // Confirmacion antes de entrar

// SL/TP local
input int    Local_Vol_Bars      = 3;     // Barras para calcular volatilidad local (SL)
input double SL_Local_Pct        = 1.20;  // SL = rango_local * este factor
input double SL_Min              = 2.00;  // SL minimo absoluto
input double SL_Max              = 15.0;  // SL maximo absoluto (limitar perdidas)
input double TP_Ratio            = 2.0;   // TP = SL * ratio

// Filtro de velocidad
input int    Vel_Bars            = 3;     // Barras para medir velocidad
input double Vel_Threshold       = 5.0;   // Max pts/barra permitido (encima = skip)

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
input int    InpMagicNumber      = 173700;
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
// Calcula velocidad: movimiento total de las ultimas N barras / N
// Usa solo closes para medir dirección neta
double CalcVelocity()
{
   double closeOld = iClose(g_sym, _Period, Vel_Bars + 1);
   double closeNew = iClose(g_sym, _Period, 1);
   if(closeOld == 0 || closeNew == 0) return 0;
   return MathAbs(closeNew - closeOld) / Vel_Bars;
}

//+------------------------------------------------------------------+
// SL adaptativo basado en la volatilidad de las ultimas Local_Vol_Bars barras
double CalcLocalSL()
{
   double localHigh = -DBL_MAX;
   double localLow  =  DBL_MAX;
   for(int i = 1; i <= Local_Vol_Bars; i++) {
      double h = iHigh(g_sym, _Period, i);
      double l = iLow (g_sym, _Period, i);
      if(h == 0 || l == 0) return SL_Min;
      if(h > localHigh) localHigh = h;
      if(l < localLow)  localLow  = l;
   }
   double localRange = localHigh - localLow;
   double sl = localRange * SL_Local_Pct;
   sl = MathMax(sl, SL_Min);
   sl = MathMin(sl, SL_Max);
   return sl;
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
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double bePx  = NormalizeDouble(g_openEntry, digs);
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
   Print("MM7 v17.37 | ", g_sym,
         " | Range=", Range_Bars, " Zone=", Zone_Pct,
         " | LocalSL=", Local_Vol_Bars, "bars*", SL_Local_Pct,
         " [", SL_Min, "-", SL_Max, "]",
         " | Vel<=", Vel_Threshold, "/bar",
         " | BE@", BE_Trigger_Pct, "x",
         " | Pause=", Max_Consec_Losses, "→", Pause_Bars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);

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

      // Filtro horario
      MqlDateTime dt;
      TimeToStruct(curBar, dt);
      if(!IsGoodHour(dt.hour)) return;

      // Filtro de velocidad — medir antes de calcular señal
      double vel = CalcVelocity();
      if(vel > Vel_Threshold) {
         Print("MM7 SKIP velocidad=", DoubleToString(vel,2), " > ", Vel_Threshold);
         return;
      }

      // Rango de señal (20 barras para la zona)
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

      // SL basado en volatilidad LOCAL (no en el rango grande)
      double slDist = CalcLocalSL();

      if(closeNow >= upperZone) {
         g_pendingDir   = -1;
         g_confirmLevel = closeNow - Confirm_Points;
         g_pendingSL    = slDist;
      } else if(closeNow <= lowerZone) {
         g_pendingDir   = 1;
         g_confirmLevel = closeNow + Confirm_Points;
         g_pendingSL    = slDist;
      }
      return;
   }

   if(g_pauseBarsLeft > 0) return;
   if(g_pendingDir == 0)   return;

   // Verificar hora sigue siendo buena
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(!IsGoodHour(dt.hour)) { g_pendingDir = 0; return; }

   // --- CONFIRMACION ---
   if(g_pendingDir == 1 && bid >= g_confirmLevel)
      OpenOrder(ORDER_TYPE_BUY, g_pendingSL);
   else if(g_pendingDir == -1 && ask <= g_confirmLevel)
      OpenOrder(ORDER_TYPE_SELL, g_pendingSL);
}
//+------------------------------------------------------------------+
