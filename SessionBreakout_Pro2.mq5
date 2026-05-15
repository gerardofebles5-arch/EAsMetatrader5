//+------------------------------------------------------------------+
//|          SESSION BREAKOUT PRO v3.0                               |
//|          Estrategia: London & NY Session Breakout                |
//|          Activos: AUDUSD, EURUSD, GBPUSD                        |
//|          Timeframe: H1 (señales) + M5 (ejecucion)              |
//|                                                                  |
//|  ARQUITECTURA v3.0 - DIAGNOSTICO CIENTIFICO APLICADO:           |
//|                                                                  |
//|  ROOT CAUSE v1→v2 fallo: SL estructural encogió los lotes       |
//|  ROOT CAUSE v1 suboptimo: TP fijo cortaba prematuramente        |
//|  Los cierres forzados (fin sesion) tenian WR 87.5% porque       |
//|  el precio seguia yendo en direccion correcta MAS ALLA del TP   |
//|                                                                  |
//|  SOLUCION v3:                                                    |
//|  1. SL = ATR x1.2 (preserva lotes grandes, probado ok)         |
//|  2. TP ELIMINADO - Trailing Stop por estructura de velas H1     |
//|  3. Trailing sube SL a cada nuevo swing high/low confirmado     |
//|  4. BE al 60% del primer ATR de recorrido                       |
//|  5. Ventana London 07:00-11:00 GMT (recupera trades buenos)     |
//|  6. ADX minimo 22 (balance calidad/cantidad)                    |
//|  7. Cierre forzado fin sesion como red de seguridad             |
//|  8. Modo Fondeo: protege capital ante reglas FTMO/MyForex       |
//|  9. Filtro H1 close: anti-fakeout estructural                   |
//|                                                                  |
//|  REGLAS PROP FIRMS SOPORTADAS:                                  |
//|  - Max daily loss: configurable (default 4%)                    |
//|  - Max overall DD: configurable (default 8%)                    |
//|  - No overnight: cierre forzado 16:55 GMT                       |
//|  - No weekend: cierre viernes 16:00 GMT                         |
//+------------------------------------------------------------------+

#property copyright "SessionBreakout Pro v3.0"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         Trade;
CPositionInfo  PositionInfo;

//=== PARAMETROS DE ENTRADA ===

input group "====== ACTIVOS ======"
input string   Symbol1            = "AUDUSD";
input string   Symbol2            = "EURUSD";
input string   Symbol3            = "GBPUSD";

input group "====== HORARIO DE SESIONES (GMT) ======"
input int      AsianStart_H       = 0;           // Inicio rango Asiatico
input int      AsianEnd_H         = 7;           // Fin rango / Inicio breakout London
input int      LondonBreakout_End = 11;          // Fin ventana London (07-11h = mejores 4h)
input int      NY_Start_H         = 13;          // Inicio sesion NY
input int      NY_End_H           = 17;          // Fin sesion NY
input int      ForceClose_H       = 16;          // Hora cierre diario forzado (fondeo)
input int      ForceClose_M       = 55;          // Minuto cierre forzado

input group "====== RIESGO ======"
input double   RiskPercent        = 0.75;        // Riesgo por operacion % del balance
input int      ATR_Period         = 14;          // Periodo ATR H1
input double   ATR_SL_Mult        = 1.2;         // SL = ATR x 1.2 (preserva lotes grandes)
input double   MinRangeATR        = 0.3;         // Rango asiatico minimo vs ATR
input double   BE_ATR_Trigger     = 0.6;         // Activar BE cuando precio avanza ATR x N
input double   Trail_ATR_Step     = 0.5;         // Paso minimo del trailing (en ATR)

input group "====== FILTROS DE SENAL ======"
input int      EMA_Fast           = 21;
input int      EMA_Slow           = 50;
input int      RSI_Period         = 14;
input int      RSI_OB             = 72;          // Overbought (ligeramente permisivo)
input int      RSI_OS             = 28;          // Oversold (ligeramente permisivo)
input int      ADX_Period         = 14;
input int      ADX_Min            = 22;          // Compromiso 20-25
input bool     RequireH1Close     = true;        // Requerir cierre H1 fuera del rango

input group "====== MODO FONDEO (PROP FIRM) ======"
input bool     PropFirmMode       = true;        // Activa reglas de prop firm
input double   PropMaxDailyLoss   = 4.0;         // Max perdida diaria % (FTMO:5%, MFF:4%)
input double   PropMaxTotalDD     = 8.0;         // Max DD total % (FTMO:10%)
input bool     NoOvernightTrades  = true;        // Cerrar todo antes del cierre del dia
input bool     NoWeekendTrades    = true;        // Cerrar todo el viernes
input int      FridayClose_H      = 16;          // Hora cierre viernes

input group "====== GESTION DRAWDOWN ======"
input double   MaxDailyLoss_Pct   = 2.0;         // Limite diario estandar (sin PropFirmMode)
input double   MaxDrawdown_Pct    = 6.0;         // Limite DD estandar
input int      MaxLossStreak      = 4;           // Racha maxima de perdidas

input group "====== VISUAL ======"
input bool     ShowSessions       = true;
input bool     ShowAsianRange     = true;
input bool     ShowDashboard      = true;
input color    ColorAsian         = clrSlateBlue;
input color    ColorLondon        = clrDodgerBlue;
input color    ColorNY            = clrOrangeRed;

input group "====== CONFIG ======"
input int      MagicNumber        = 20260301;
input int      Slippage           = 10;
input bool     EnableAlerts       = true;

//=== ESTRUCTURA DE ESTADO POR SIMBOLO ===
struct SymbolState {
   double   asian_high;
   double   asian_low;
   bool     traded_london;
   bool     traded_ny;
   bool     paused_today;
   double   day_start_balance;
   ulong    ticket;
   double   entry_price;
   double   current_sl;
   double   atr_at_entry;
   bool     be_done;
   string   session;
   datetime last_trail_time;
};

//=== HANDLES DE INDICADORES ===
int h_atr[3], h_emaf[3], h_emas[3], h_rsi[3], h_adx[3];
string g_syms[3];
SymbolState g_st[3];

//=== ESTADISTICAS GLOBALES ===
int    g_wins = 0, g_losses = 0, g_total = 0;
double g_gprofit = 0, g_gloss = 0;
int    g_lstreak = 0, g_maxstreak = 0;
double g_peak_bal = 0, g_max_dd = 0, g_init_bal = 0;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_syms[0] = Symbol1;
   g_syms[1] = Symbol2;
   g_syms[2] = Symbol3;

   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(Slippage);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_init_bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peak_bal = g_init_bal;

   for(int i = 0; i < 3; i++) {
      if(!SymbolSelect(g_syms[i], true))
         PrintFormat("AVISO: Simbolo %s no visible en MarketWatch", g_syms[i]);

      h_atr[i]  = iATR(g_syms[i],  PERIOD_H1, ATR_Period);
      h_emaf[i] = iMA(g_syms[i],   PERIOD_H1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      h_emas[i] = iMA(g_syms[i],   PERIOD_H1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      h_rsi[i]  = iRSI(g_syms[i],  PERIOD_H1, RSI_Period, PRICE_CLOSE);
      h_adx[i]  = iADX(g_syms[i],  PERIOD_H1, ADX_Period);
      ResetState(i);
   }

   Print("SESSION BREAKOUT PRO v3.0 iniciado | Balance: ", g_init_bal,
         " | Modo Fondeo: ", (PropFirmMode ? "SI" : "NO"));
   return INIT_SUCCEEDED;
}

void ResetState(int i)
{
   g_st[i].asian_high       = 0;
   g_st[i].asian_low        = DBL_MAX;
   g_st[i].traded_london    = false;
   g_st[i].traded_ny        = false;
   g_st[i].paused_today     = false;
   g_st[i].day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_st[i].ticket           = 0;
   g_st[i].entry_price      = 0;
   g_st[i].current_sl       = 0;
   g_st[i].atr_at_entry     = 0;
   g_st[i].be_done          = false;
   g_st[i].session          = "";
   g_st[i].last_trail_time  = 0;
}

//+------------------------------------------------------------------+
//| TICK PRINCIPAL                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // Reset diario a las 00:05 GMT
   static datetime last_reset = 0;
   datetime reset_t = StringToTime(TimeToString(now, TIME_DATE) + " 00:05");
   if(now >= reset_t && last_reset < reset_t) {
      for(int i = 0; i < 3; i++) ResetState(i);
      g_lstreak = 0;
      last_reset = reset_t;
      Print("=== RESET DIARIO ===");
   }

   // Drawdown global
   double dd = CheckDD();
   double dd_limit = PropFirmMode ? PropMaxTotalDD : MaxDrawdown_Pct;
   if(dd >= dd_limit) {
      Comment("EA PAUSADO - Drawdown " + DoubleToString(dd, 2) + "% limite: " + DoubleToString(dd_limit, 2) + "%");
      if(ShowDashboard) UpdateDash(dt);
      return;
   }

   // Modo fondeo: cierre global forzado
   bool is_friday = (dt.day_of_week == 5);
   if((NoOvernightTrades && dt.hour == ForceClose_H && dt.min >= ForceClose_M) ||
      (NoWeekendTrades && is_friday && dt.hour >= FridayClose_H)) {
      for(int i = 0; i < 3; i++) CloseAll(i, "CIERRE_FONDEO");
      if(ShowDashboard) UpdateDash(dt);
      return;
   }

   // Procesar cada simbolo
   for(int i = 0; i < 3; i++) ProcessSym(i, dt);

   if(ShowDashboard) UpdateDash(dt);

   // Dibujar sesiones en nueva barra H1
   static datetime last_h1 = 0;
   datetime cur_h1 = iTime(Symbol(), PERIOD_H1, 0);
   if(cur_h1 != last_h1) {
      if(ShowSessions) DrawSessions(dt);
      last_h1 = cur_h1;
   }
}

//+------------------------------------------------------------------+
//| PROCESAR SIMBOLO                                                 |
//+------------------------------------------------------------------+
void ProcessSym(int idx, MqlDateTime &dt)
{
   string sym  = g_syms[idx];
   int    hour = dt.hour;
   int    min  = dt.min;

   // Trailing siempre activo si hay posicion
   if(g_st[idx].ticket > 0) ManageTrail(idx);

   if(g_st[idx].paused_today) return;

   // Fase 1: Rango asiatico
   if(hour >= AsianStart_H && hour < AsianEnd_H) {
      double mid = (SymbolInfoDouble(sym, SYMBOL_BID) + SymbolInfoDouble(sym, SYMBOL_ASK)) * 0.5;
      if(mid > g_st[idx].asian_high) g_st[idx].asian_high = mid;
      if(mid < g_st[idx].asian_low)  g_st[idx].asian_low  = mid;
      if(ShowAsianRange) DrawAsianRange(idx, sym);
      return;
   }

   if(g_st[idx].asian_high == 0 || g_st[idx].asian_low == DBL_MAX) return;

   // Fase 2: London breakout
   if(hour >= AsianEnd_H && hour < LondonBreakout_End && !g_st[idx].traded_london)
      TryEntry(idx, sym, "LONDON");

   // Fase 3: NY breakout
   if(hour >= NY_Start_H && hour < NY_End_H && !g_st[idx].traded_ny)
      TryEntry(idx, sym, "NY");

   // Cierre forzado al cierre de sesion (backup si trailing no se activo)
   if(hour == 12 && min == 0 && g_st[idx].traded_london && g_st[idx].session == "LONDON")
      CloseAll(idx, "FIN_LONDON");
   if(hour == NY_End_H && min == 0 && g_st[idx].traded_ny && g_st[idx].session == "NY")
      CloseAll(idx, "FIN_NY");
}

//+------------------------------------------------------------------+
//| LOGICA DE ENTRADA                                                |
//+------------------------------------------------------------------+
void TryEntry(int idx, string sym, string session)
{
   double range = g_st[idx].asian_high - g_st[idx].asian_low;
   if(range <= 0) return;

   // ATR H1
   double atrbuf[]; ArraySetAsSeries(atrbuf, true);
   if(CopyBuffer(h_atr[idx], 0, 0, 3, atrbuf) < 2) return;
   double atr = atrbuf[1];
   if(atr <= 0) return;

   // Filtro rango minimo
   if(range < atr * MinRangeATR) return;

   // SL distance
   double sl_dist = atr * ATR_SL_Mult;

   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double pt    = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    dg    = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   // Indicadores
   double ef[3], es[3], rv[3], av[3], dp[3], dm[3];
   ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
   ArraySetAsSeries(rv,true); ArraySetAsSeries(av,true);
   ArraySetAsSeries(dp,true); ArraySetAsSeries(dm,true);

   if(CopyBuffer(h_emaf[idx],0,0,3,ef)<2) return;
   if(CopyBuffer(h_emas[idx],0,0,3,es)<2) return;
   if(CopyBuffer(h_rsi[idx], 0,0,3,rv)<2) return;
   if(CopyBuffer(h_adx[idx], 0,0,3,av)<2) return;
   if(CopyBuffer(h_adx[idx], 1,0,3,dp)<2) return;
   if(CopyBuffer(h_adx[idx], 2,0,3,dm)<2) return;

   // Limites de riesgo diario
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double lim = PropFirmMode ? PropMaxDailyLoss : MaxDailyLoss_Pct;
   if(g_st[idx].day_start_balance > 0) {
      double dloss = (g_st[idx].day_start_balance - bal) / g_st[idx].day_start_balance * 100.0;
      if(dloss >= lim) { g_st[idx].paused_today = true; return; }
   }
   if(g_lstreak >= MaxLossStreak) { g_st[idx].paused_today = true; return; }

   // Condiciones de breakout
   bool price_buy  = (ask > g_st[idx].asian_high + pt * 3);
   bool price_sell = (bid < g_st[idx].asian_low  - pt * 3);

   // Filtro H1 close: la ultima vela H1 cerrada debe confirmar la ruptura
   if(RequireH1Close) {
      double h1close[2]; ArraySetAsSeries(h1close, true);
      if(CopyClose(sym, PERIOD_H1, 1, 2, h1close) < 2) return;
      double lc = h1close[0];
      price_buy  = price_buy  && (lc > g_st[idx].asian_high);
      price_sell = price_sell && (lc < g_st[idx].asian_low);
   }

   bool ema_bull = (ef[1] > es[1]);
   bool ema_bear = (ef[1] < es[1]);
   bool rsi_ok_b = (rv[1] < RSI_OB);
   bool rsi_ok_s = (rv[1] > RSI_OS);
   bool adx_ok   = (av[1] > ADX_Min);
   bool dip_dom  = (dp[1] > dm[1]);
   bool dim_dom  = (dm[1] > dp[1]);

   bool sig_buy  = price_buy  && ema_bull && rsi_ok_b && adx_ok && dip_dom;
   bool sig_sell = price_sell && ema_bear && rsi_ok_s && adx_ok && dim_dom;

   if(!sig_buy && !sig_sell) return;

   double lots = CalcLots(sym, sl_dist);
   if(lots <= 0) return;

   if(sig_buy) {
      double sl = NormalizeDouble(ask - sl_dist, dg);
      if(Trade.Buy(lots, sym, ask, sl, 0, "SBP3_" + session + "_B")) {
         SetupPos(idx, session, ask, sl, atr, Trade.ResultOrder());
         if(session=="LONDON") g_st[idx].traded_london = true;
         else                  g_st[idx].traded_ny     = true;
         g_total++;
         string msg = StringFormat("[BUY] %s | %.2f lots | Entry:%.5f SL:%.5f | %s", sym, lots, ask, sl, session);
         Print(msg); if(EnableAlerts) Alert(msg);
      }
   }
   else {
      double sl = NormalizeDouble(bid + sl_dist, dg);
      if(Trade.Sell(lots, sym, bid, sl, 0, "SBP3_" + session + "_S")) {
         SetupPos(idx, session, bid, sl, atr, Trade.ResultOrder());
         if(session=="LONDON") g_st[idx].traded_london = true;
         else                  g_st[idx].traded_ny     = true;
         g_total++;
         string msg = StringFormat("[SELL] %s | %.2f lots | Entry:%.5f SL:%.5f | %s", sym, lots, bid, sl, session);
         Print(msg); if(EnableAlerts) Alert(msg);
      }
   }
}

void SetupPos(int idx, string session, double entry, double sl, double atr, ulong ticket)
{
   g_st[idx].ticket          = ticket;
   g_st[idx].entry_price     = entry;
   g_st[idx].current_sl      = sl;
   g_st[idx].atr_at_entry    = atr;
   g_st[idx].be_done         = false;
   g_st[idx].session         = session;
   g_st[idx].last_trail_time = TimeCurrent();
}

//+------------------------------------------------------------------+
//| TRAILING STOP POR ESTRUCTURA H1                                  |
//|                                                                  |
//| Logica de 3 fases:                                               |
//|  FASE 1 - Precio en territorio inicial (< BE trigger):          |
//|    SL fijo, dejar respirar                                       |
//|  FASE 2 - Precio avanza ATR x 0.6: mover SL a BE (+3 pips)     |
//|  FASE 3 - Trailing por min/max de velas H1 confirmadas          |
//|    BUY:  SL sube al minimo de las ultimas 3 velas H1            |
//|    SELL: SL baja al maximo de las ultimas 3 velas H1            |
//|                                                                  |
//| Efecto: captura movimientos largos que el TP fijo cortaba       |
//+------------------------------------------------------------------+
void ManageTrail(int idx)
{
   if(g_st[idx].ticket == 0) return;
   string sym = g_syms[idx];

   if(!PositionSelectByTicket(g_st[idx].ticket)) {
      g_st[idx].ticket = 0; return;
   }
   if(PositionGetString(POSITION_SYMBOL) != sym) return;
   if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) return;

   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open_p  = PositionGetDouble(POSITION_PRICE_OPEN);
   double cur_sl  = PositionGetDouble(POSITION_SL);
   double atr     = g_st[idx].atr_at_entry;
   int    dg      = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pp      = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(atr <= 0) return;

   double be_trig   = atr * BE_ATR_Trigger;
   double trail_min = atr * Trail_ATR_Step;

   // Obtener ultimas 3 velas H1 para estructura
   double h1lo[3], h1hi[3];
   ArraySetAsSeries(h1lo, true); ArraySetAsSeries(h1hi, true);
   bool h1ok = (CopyLow(sym, PERIOD_H1, 1, 3, h1lo) >= 3 &&
                CopyHigh(sym, PERIOD_H1, 1, 3, h1hi) >= 3);

   if(pt == POSITION_TYPE_BUY) {
      double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
      double dist = bid - open_p;

      // Fase 2: Break-even
      if(!g_st[idx].be_done && dist >= be_trig) {
         double nsl = NormalizeDouble(open_p + pp * 3, dg);
         if(nsl > cur_sl && Trade.PositionModify(g_st[idx].ticket, nsl, 0)) {
            g_st[idx].current_sl = nsl;
            g_st[idx].be_done    = true;
            PrintFormat("BE activado [%s] SL→%.5f | ganancia bloqueada: %.1f pips", sym, nsl, dist/pp);
         }
         return;
      }

      // Fase 3: Trailing estructural H1
      if(g_st[idx].be_done && h1ok) {
         // Minimo de las 3 velas H1 recientes = soporte estructural
         double struct_sl = MathMin(h1lo[0], MathMin(h1lo[1], h1lo[2])) - pp * 5;
         double nsl = NormalizeDouble(struct_sl, dg);

         // Avanzar solo si: sube, supera el paso minimo, y queda por encima del BE
         if(nsl > cur_sl + trail_min && nsl > open_p) {
            if(Trade.PositionModify(g_st[idx].ticket, nsl, 0)) {
               g_st[idx].current_sl      = nsl;
               g_st[idx].last_trail_time = TimeCurrent();
               PrintFormat("TRAIL BUY [%s] SL→%.5f", sym, nsl);
            }
         }
      }
   }
   else if(pt == POSITION_TYPE_SELL) {
      double ask  = SymbolInfoDouble(sym, SYMBOL_ASK);
      double dist = open_p - ask;

      // Fase 2: Break-even
      if(!g_st[idx].be_done && dist >= be_trig) {
         double nsl = NormalizeDouble(open_p - pp * 3, dg);
         if(nsl < cur_sl && Trade.PositionModify(g_st[idx].ticket, nsl, 0)) {
            g_st[idx].current_sl = nsl;
            g_st[idx].be_done    = true;
            PrintFormat("BE activado [%s] SL→%.5f | ganancia bloqueada: %.1f pips", sym, nsl, dist/pp);
         }
         return;
      }

      // Fase 3: Trailing estructural H1
      if(g_st[idx].be_done && h1ok) {
         double struct_sl = MathMax(h1hi[0], MathMax(h1hi[1], h1hi[2])) + pp * 5;
         double nsl = NormalizeDouble(struct_sl, dg);

         if(nsl < cur_sl - trail_min && nsl < open_p) {
            if(Trade.PositionModify(g_st[idx].ticket, nsl, 0)) {
               g_st[idx].current_sl      = nsl;
               g_st[idx].last_trail_time = TimeCurrent();
               PrintFormat("TRAIL SELL [%s] SL→%.5f", sym, nsl);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CERRAR POSICIONES                                                |
//+------------------------------------------------------------------+
void CloseAll(int idx, string reason)
{
   string sym = g_syms[idx];
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(PositionGetSymbol(i) != sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ulong t = PositionGetInteger(POSITION_TICKET);
      if(Trade.PositionClose(t))
         PrintFormat("Cerrado [%s] razon: %s", sym, reason);
   }
   g_st[idx].ticket = 0;
}

//+------------------------------------------------------------------+
//| CALCULAR LOTES POR RIESGO                                        |
//+------------------------------------------------------------------+
double CalcLots(string sym, double sl_dist)
{
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk   = bal * RiskPercent / 100.0;
   double tv     = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double ts     = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double minl   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxl   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   if(tv <= 0 || ts <= 0 || sl_dist <= 0) return minl;
   double lots = risk / (sl_dist / ts * tv);
   return MathMax(minl, MathMin(maxl, MathFloor(lots / step) * step));
}

//+------------------------------------------------------------------+
//| DRAWDOWN GLOBAL                                                  |
//+------------------------------------------------------------------+
double CheckDD()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal > g_peak_bal) g_peak_bal = bal;
   double dd = (g_peak_bal > 0) ? (g_peak_bal - eq) / g_peak_bal * 100.0 : 0;
   if(dd > g_max_dd) g_max_dd = dd;
   return dd;
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& req,
                        const MqlTradeResult& res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string dsym   = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

   if(profit >= 0) {
      g_wins++; g_gprofit += profit; g_lstreak = 0;
   } else {
      g_losses++; g_gloss += MathAbs(profit); g_lstreak++;
      if(g_lstreak > g_maxstreak) g_maxstreak = g_lstreak;
   }
   for(int i = 0; i < 3; i++)
      if(g_syms[i] == dsym) { g_st[i].ticket = 0; break; }
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void UpdateDash(MqlDateTime &dt)
{
   double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   int    tot   = g_wins + g_losses;
   double wr    = (tot > 0) ? (double)g_wins / tot * 100.0 : 0;
   double pf    = (g_gloss > 0) ? g_gprofit / g_gloss : 0;
   double net   = bal - g_init_bal;
   double dd    = (g_peak_bal > 0) ? (g_peak_bal - eq) / g_peak_bal * 100.0 : 0;
   double ddlim = PropFirmMode ? PropMaxTotalDD : MaxDrawdown_Pct;
   double dlim  = PropFirmMode ? PropMaxDailyLoss : MaxDailyLoss_Pct;

   string d = "\n";
   d += "╔══════════════════════════════════════════╗\n";
   d += "║     SESSION BREAKOUT PRO  v3.0           ║\n";
   d += "╠══════════════════════════════════════════╣\n";
   d += StringFormat("║  Balance:    %12.2f                ║\n", bal);
   d += StringFormat("║  Equity:     %12.2f                ║\n", eq);
   d += StringFormat("║  P&L Neto:   %+12.2f                ║\n", net);
   d += "╠══════════════════════════════════════════╣\n";
   d += StringFormat("║  Trades: %3d  | W:%3d | L:%3d         ║\n", tot, g_wins, g_losses);
   d += StringFormat("║  WinRate:    %5.1f%%                    ║\n", wr);
   d += StringFormat("║  Profit Factor: %6.2f                 ║\n", pf);
   d += StringFormat("║  DD actual: %5.1f%% | Limite: %5.1f%%    ║\n", dd, ddlim);
   d += StringFormat("║  Racha Perd: %4d | Max: %4d          ║\n", g_lstreak, g_maxstreak);
   d += "╠══════════════════════════════════════════╣\n";
   d += StringFormat("║  Modo Fondeo: %-28s║\n", PropFirmMode ? "ACTIVADO" : "Desactivado");
   d += StringFormat("║  Max Diario: %.1f%% | Max DD: %.1f%%      ║\n", dlim, ddlim);
   d += "╠══════════════════════════════════════════╣\n";
   d += "║  ESTADO POR SIMBOLO:                     ║\n";

   for(int i = 0; i < 3; i++) {
      string sym   = g_syms[i];
      string state = "Esperando rango/señal";
      if(g_st[i].paused_today)
         state = "PAUSADO (limite alcanzado)";
      else if(g_st[i].ticket > 0) {
         double pnl = 0;
         if(PositionSelectByTicket(g_st[i].ticket))
            pnl = PositionGetDouble(POSITION_PROFIT);
         state = StringFormat("EN TRADE%s | P&L:%.2f", g_st[i].be_done?" [BE]":"", pnl);
      }
      d += StringFormat("║  %-8s: %-33s║\n", sym, state);
   }

   // Sesion activa
   int hr = dt.hour;
   string sess = "Fuera de sesion";
   if(hr < AsianEnd_H) sess = "Rango Asiatico";
   else if(hr < LondonBreakout_End) sess = "Londres ACTIVA";
   else if(hr >= NY_Start_H && hr < NY_End_H) sess = "Nueva York ACTIVA";

   d += "╠══════════════════════════════════════════╣\n";
   d += StringFormat("║  Sesion: %-35s║\n", sess);
   d += "╚══════════════════════════════════════════╝";
   Comment(d);
}

//+------------------------------------------------------------------+
//| DIBUJAR RANGO ASIATICO                                          |
//+------------------------------------------------------------------+
void DrawAsianRange(int idx, string sym)
{
   if(sym != Symbol()) return;
   double hi = g_st[idx].asian_high;
   double lo = g_st[idx].asian_low;
   if(hi == 0 || lo == DBL_MAX) return;

   string nh = "SBP_AR_H_" + sym;
   string nl = "SBP_AR_L_" + sym;

   if(ObjectFind(0, nh) < 0) ObjectCreate(0, nh, OBJ_HLINE, 0, 0, hi);
   else ObjectSetDouble(0, nh, OBJPROP_PRICE, hi);
   ObjectSetInteger(0, nh, OBJPROP_COLOR, ColorAsian);
   ObjectSetInteger(0, nh, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nh, OBJPROP_WIDTH, 2);

   if(ObjectFind(0, nl) < 0) ObjectCreate(0, nl, OBJ_HLINE, 0, 0, lo);
   else ObjectSetDouble(0, nl, OBJPROP_PRICE, lo);
   ObjectSetInteger(0, nl, OBJPROP_COLOR, ColorAsian);
   ObjectSetInteger(0, nl, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nl, OBJPROP_WIDTH, 2);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DIBUJAR SESIONES                                                 |
//+------------------------------------------------------------------+
void DrawSessions(MqlDateTime &dt)
{
   datetime now  = TimeCurrent();
   datetime dop  = StringToTime(TimeToString(now, TIME_DATE) + " 00:00");

   DrawRect("SBP_Ses_Asian",  dop,                         dop + AsianEnd_H*3600,       ColorAsian,  "Asiatica");
   DrawRect("SBP_Ses_London", dop + AsianEnd_H*3600,       dop + 12*3600,               ColorLondon, "Londres");
   DrawRect("SBP_Ses_NY",     dop + NY_Start_H*3600,       dop + NY_End_H*3600,         ColorNY,     "Nueva York");
}

void DrawRect(string name, datetime t1, datetime t2, color clr, string label)
{
   double hi = ChartGetDouble(0, CHART_PRICE_MAX);
   double lo = ChartGetDouble(0, CHART_PRICE_MIN);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, hi);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 1, lo);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,    label);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "SBP_");
   Comment("");
   Print("SESSION BREAKOUT PRO v3.0 - Detenido");
}
//+------------------------------------------------------------------+
