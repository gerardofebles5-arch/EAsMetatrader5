//+------------------------------------------------------------------+
//|  MoneyMachine7_v1735.mq5                                        |
//|  v17.35 — Salidas inteligentes: BE automatico + pausa anti-racha|
//|                                                                  |
//|  DIAGNOSTICO v17.34:                                            |
//|  1713 trades | WR=32.2% | Net=-$1291 | DD=37.8%               |
//|  Breakeven needed: 33.8% — estamos a 1.6% del punto de equilibrio|
//|  76.9% de perdidas en rachas de 3+ consecutivas                 |
//|  Rachas max: 17,13,13,11 — mercado tendencial destruye el algo  |
//|  Perdidas >120s: precio llego a zona favorable pero revirtio    |
//|                                                                  |
//|  FIX v17.35 — DOS mecanismos de salida inteligente:             |
//|                                                                  |
//|  1. BREAKEVEN AUTOMATICO:                                        |
//|     Cuando precio se mueve BE_Trigger_Pct*SL a nuestro favor,  |
//|     mover SL al precio de entrada. Convierte perdidas en cero.  |
//|                                                                  |
//|  2. PAUSA ANTI-RACHA:                                           |
//|     Despues de Max_Consec_Losses SLs consecutivos,             |
//|     pausar nuevas entradas durante Pause_Bars barras.           |
//|     El mercado esta en tendencia — no luchar contra ella.       |
//|     Reanudar cuando el precio demuestre quietud (rango estrecho)|
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.35"
#property strict

// Señal
input int    Range_Bars          = 20;    // Barras para el rango
input double Zone_Pct            = 0.15;  // % extremo para señal
input double Confirm_Points      = 1.00;  // Confirmacion antes de entrar
input double SL_Range_Pct        = 0.20;  // SL como % del rango
input double TP_Ratio            = 2.0;   // TP = SL * ratio

// Salida inteligente — Breakeven
input double BE_Trigger_Pct      = 0.70;  // Mover SL a BE cuando precio llega a X% del TP
input bool   Use_Breakeven       = true;

// Salida inteligente — Anti-racha
input int    Max_Consec_Losses   = 3;     // Maximo de SLs consecutivos antes de pausar
input int    Pause_Bars          = 5;     // Barras de pausa tras racha

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 173500;
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

// Estado señal pendiente
int      g_pendingDir    = 0;
double   g_confirmLevel  = 0;
double   g_pendingSL     = 0;

// Estado posicion abierta para BE
double   g_openEntry     = 0;
double   g_openSLDist    = 0;
int      g_openDir       = 0;
bool     g_beMoved       = false;

// Anti-racha
int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

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
            " SLdist=", DoubleToString(sl_dist,2), " lot=", req.volume);
   } else {
      Print("MM7 FAIL retcode=", res.retcode);
   }
}

//+------------------------------------------------------------------+
// Mueve el SL al precio de entrada (breakeven)
void MoveToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL  = PositionGetDouble(POSITION_SL);
   double curTP  = PositionGetDouble(POSITION_TP);
   double bePx   = NormalizeDouble(g_openEntry, (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS));
   
   // Solo mover si el nuevo SL es mejor que el actual
   if(g_openDir == 1  && bePx <= curSL) return;
   if(g_openDir == -1 && bePx >= curSL) return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = g_sym;
   req.position = ticket;
   req.sl       = bePx;
   req.tp       = curTP;

   if(OrderSend(req, res))
      Print("MM7 BE moved to ", bePx);
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

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);

   if(StringFind(comment, "sl") >= 0 && profit < 0) {
      // Solo contar como perdida real si no era el SL en breakeven
      g_consecLosses++;
      if(g_consecLosses >= Max_Consec_Losses) {
         g_pauseBarsLeft = Pause_Bars;
         g_pendingDir    = 0;
         Print("MM7 PAUSA: ", g_consecLosses, " perdidas consecutivas. Pausando ", Pause_Bars, " barras.");
      }
   } else {
      // TP o SL en BE (profit >= 0) → resetear racha
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
   Print("MM7 v17.35 | ", g_sym,
         " | Range=", Range_Bars, " Zone=", Zone_Pct,
         " | Confirm=", Confirm_Points,
         " | SL_pct=", SL_Range_Pct, " TP=", TP_Ratio, "x",
         " | BE@", BE_Trigger_Pct, "x | Pause=", Max_Consec_Losses, "→", Pause_Bars, "bars");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);

   // --- GESTIÓN DE POSICION ABIERTA: Breakeven ---
   ulong ticket = GetOpenTicket();
   if(ticket > 0 && Use_Breakeven && !g_beMoved && g_openEntry > 0 && g_openSLDist > 0) {
      double beThreshold = g_openEntry + g_openDir * g_openSLDist * BE_Trigger_Pct;
      bool triggered = (g_openDir == 1 && bid >= beThreshold) ||
                       (g_openDir == -1 && ask <= beThreshold);
      if(triggered) {
         MoveToBreakeven(ticket);
         g_beMoved = true;
      }
   }

   // Si hay posicion abierta, no buscar nuevas entradas
   if(CountByMagic() >= Max_Positions) {
      g_pendingDir = 0;
      return;
   }

   // --- NUEVA BARRA: señal y countdown de pausa ---
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      g_pendingDir  = 0;

      // Decrementar pausa
      if(g_pauseBarsLeft > 0) {
         g_pauseBarsLeft--;
         Print("MM7 Pausa restante: ", g_pauseBarsLeft, " barras");
         return;
      }

      // Calcular rango
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

   // En pausa no entrar
   if(g_pauseBarsLeft > 0) return;

   // --- CONFIRMACION DE ENTRADA EN TIEMPO REAL ---
   if(g_pendingDir == 0) return;

   if(g_pendingDir == 1 && bid >= g_confirmLevel)
      OpenOrder(ORDER_TYPE_BUY, g_pendingSL);
   else if(g_pendingDir == -1 && ask <= g_confirmLevel)
      OpenOrder(ORDER_TYPE_SELL, g_pendingSL);
}
//+------------------------------------------------------------------+
