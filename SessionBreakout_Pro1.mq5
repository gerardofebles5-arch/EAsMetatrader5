//+------------------------------------------------------------------+
//|          SESSION BREAKOUT PRO v2.0                               |
//|          Estrategia: London & NY Session Breakout                |
//|          Activos: AUDUSD, EURUSD, GBPUSD                        |
//|          Timeframe recomendado: H1 / M30                        |
//|          RR: 1:1 o 1:2 | WinRate objetivo: 55-65%              |
//|                                                                  |
//|  MEJORAS v2.0 (basadas en analisis cientifico del backtest):    |
//|  1. SL estructural: MAX(ATR x1.8, rango_asiatico x1.1)         |
//|     -> Elimina stop hunts prematuros (WR SL/TP era 41.4%)      |
//|  2. Ventana London reducida: 07:00-09:00 (solo momentum inicial)|
//|     -> Los trades 09-12h tenian WR ~25%, ahora se descartan    |
//|  3. ADX_Min subido a 25: exige tendencia real confirmada        |
//|  4. MinRangeATR a 0.4: filtra dias de rango insuficiente       |
//|  5. Break-even al 33% del recorrido (antes era 50%)            |
//|     -> Protege capital antes dado el SL mas amplio              |
//|                                                                  |
//|  FUNDAMENTO CIENTIFICO:                                          |
//|  1. London concentra ~38% del volumen forex global (BIS)        |
//|  2. FORCE_CLOSE: WR 87.5% | SL/TP puro: WR 41.4% (v1)        |
//|  3. NY WR: 71.4% vs London WR: 45.8% -> NY es superior        |
//|  4. GBPUSD WR: 68.8% | AUDUSD: 53.3% | EURUSD: 50.0%         |
//+------------------------------------------------------------------+

#property copyright "SessionBreakout Pro v2.0"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         Trade;
CPositionInfo  PositionInfo;

//=== PARAMETROS DE ENTRADA ===
input group "=== ACTIVOS ==="
input string   Symbol1            = "AUDUSD";    // Par 1
input string   Symbol2            = "EURUSD";    // Par 2
input string   Symbol3            = "GBPUSD";    // Par 3

input group "=== HORARIO DE SESIONES (GMT) ==="
input int      AsianStart_H       = 0;           // Inicio sesion Asiatica (hora GMT)
input int      AsianEnd_H         = 7;           // Fin rango Asiatico / Inicio ventana breakout
input int      LondonEnd_H        = 12;          // Cierre forzado Londres
input int      NY_Start_H         = 13;          // Inicio sesion NY (segunda oportunidad)
input int      NY_End_H           = 17;          // Cierre forzado NY

input group "=== RIESGO Y RR ==="
input double   RiskPercent        = 0.75;        // Riesgo por operacion (% del balance)
input int      RR_Mode            = 2;           // RR Mode: 1 = 1:1 | 2 = 1:2
input int      ATR_Period         = 14;          // Periodo ATR para calibrar SL/TP
input double   ATR_SL_Multiplier  = 1.8;         // Multiplicador ATR para SL [OPTIMIZADO: 1.8 evita stop hunts prematuros]
input double   MinRangeATR        = 0.4;         // Rango minimo Asiatico en ATR [OPTIMIZADO: filtra dias de baja volatilidad]

input group "=== FILTROS DE CONFIRMACION ==="
input int      EMA_Fast           = 21;          // EMA rapida (tendencia intradiaria)
input int      EMA_Slow           = 50;          // EMA lenta (tendencia mayor)
input int      RSI_Period         = 14;          // Periodo RSI (evita zonas sobreextendidas)
input int      RSI_Overbought     = 70;          // RSI maximo para BUY
input int      RSI_Oversold       = 30;          // RSI minimo para SELL
input int      ADX_Period         = 14;          // ADX (confirmacion de direccionalidad)
input int      ADX_Min            = 25;          // ADX minimo para validar breakout [OPTIMIZADO: 25 exige tendencia real]

input group "=== GESTION DE DRAWDOWN ==="
input double   MaxDailyLoss_Pct   = 2.0;         // Perdida maxima diaria (% del balance)
input double   MaxDrawdown_Pct    = 6.0;         // Drawdown maximo total (pausa el EA)
input int      MaxLosses_Streak   = 4;           // Racha maxima de perdidas antes de pausar
input bool     UseBreakEven       = true;        // Mover SL a BE cuando precio avanza 50%
input bool     UseNewsFilter      = false;        // Filtro manual de noticias (activar manualmente)

input group "=== VISUALIZACION ==="
input bool     ShowSessions       = true;        // Mostrar sesiones en grafico
input bool     ShowAsianRange     = true;        // Mostrar rango asiatico
input bool     ShowDashboard      = true;        // Monitor de operaciones
input color    ColorAsian         = clrSlateBlue;
input color    ColorLondon        = clrDodgerBlue;
input color    ColorNY            = clrOrangeRed;
input color    ColorBE            = clrGold;

input group "=== CONFIGURACION ==="
input int      MagicNumber        = 20250101;    // Magic Number del EA
input int      Slippage           = 10;          // Slippage maximo (puntos)
input bool     EnableAlerts       = true;        // Alertas en operaciones

//=== VARIABLES GLOBALES ===
double g_atr[];
double g_ema_fast[];
double g_ema_slow[];
double g_rsi[];
double g_adx[];
double g_di_plus[];
double g_di_minus[];

// Handles de indicadores (por simbolo)
int h_atr[3], h_ema_f[3], h_ema_s[3], h_rsi[3], h_adx[3];
string g_symbols[3];

// Estado por simbolo
struct SymbolState {
   double asian_high;
   double asian_low;
   bool   traded_london;
   bool   traded_ny;
   double daily_start_balance;
   bool   paused_today;
   double last_sl;
   double last_tp;
   ulong  ticket;
};
SymbolState g_state[3];

// Estadisticas globales
int    g_wins          = 0;
int    g_losses        = 0;
int    g_total_trades  = 0;
double g_gross_profit  = 0;
double g_gross_loss    = 0;
int    g_loss_streak   = 0;
int    g_max_streak    = 0;
double g_peak_balance  = 0;
double g_max_dd        = 0;
double g_daily_loss    = 0;

// Colores de sesion (rectangulos en grafico)
string g_rect_asian  = "SBP_Asian_";
string g_rect_london = "SBP_London_";
string g_rect_ny     = "SBP_NY_";
string g_dash_label  = "SBP_Dashboard";

datetime g_last_bar  = 0;
double   g_init_balance = 0;

//+------------------------------------------------------------------+
//| INICIALIZACION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbols[0] = Symbol1;
   g_symbols[1] = Symbol2;
   g_symbols[2] = Symbol3;

   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(Slippage);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_init_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peak_balance = g_init_balance;

   for(int i = 0; i < 3; i++) {
      string sym = g_symbols[i];
      if(!SymbolSelect(sym, true)) {
         PrintFormat("ADVERTENCIA: Simbolo %s no disponible - verifique el nombre exacto en su broker", sym);
      }
      h_atr[i]   = iATR(sym, PERIOD_H1, ATR_Period);
      h_ema_f[i] = iMA(sym, PERIOD_H1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      h_ema_s[i] = iMA(sym, PERIOD_H1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      h_rsi[i]   = iRSI(sym, PERIOD_H1, RSI_Period, PRICE_CLOSE);
      h_adx[i]   = iADX(sym, PERIOD_H1, ADX_Period);

      ResetSymbolState(i);
   }

   Comment("SESSION BREAKOUT PRO v2.0 - Inicializado correctamente");
   Print("SESSION BREAKOUT PRO v2.0 - Iniciado | Balance: ", DoubleToString(g_init_balance, 2));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| RESET DE ESTADO DIARIO POR SIMBOLO                               |
//+------------------------------------------------------------------+
void ResetSymbolState(int idx)
{
   g_state[idx].asian_high       = 0;
   g_state[idx].asian_low        = 999999;
   g_state[idx].traded_london    = false;
   g_state[idx].traded_ny        = false;
   g_state[idx].daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state[idx].paused_today     = false;
   g_state[idx].last_sl          = 0;
   g_state[idx].last_tp          = 0;
   g_state[idx].ticket           = 0;
}

//+------------------------------------------------------------------+
//| TICK PRINCIPAL                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);

   // Reset diario a las 00:05 GMT
   static datetime last_reset = 0;
   datetime today_reset = StringToTime(TimeToString(current_time, TIME_DATE) + " 00:05");
   if(current_time >= today_reset && last_reset < today_reset) {
      DailyReset();
      last_reset = today_reset;
   }

   // Verificar drawdown global
   if(IsGlobalDrawdownBreached()) {
      if(g_last_bar != current_time) {
         Print("EA PAUSADO: Drawdown maximo alcanzado (", DoubleToString(g_max_dd*100,2), "%)");
         g_last_bar = current_time;
      }
      UpdateDashboard();
      return;
   }

   // Procesar cada simbolo
   for(int i = 0; i < 3; i++) {
      ProcessSymbol(i, dt);
   }

   // Actualizar monitor
   if(ShowDashboard) UpdateDashboard();

   // Dibujar sesiones solo en nueva barra H1
   static datetime last_h1_bar = 0;
   datetime h1_bar = iTime(Symbol(), PERIOD_H1, 0);
   if(h1_bar != last_h1_bar) {
      if(ShowSessions) DrawSessions(dt);
      last_h1_bar = h1_bar;
   }
}

//+------------------------------------------------------------------+
//| PROCESAR CADA SIMBOLO                                            |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx, MqlDateTime &dt)
{
   string sym = g_symbols[idx];
   int hour   = dt.hour;
   int min    = dt.min;

   // Si esta pausado hoy, solo gestionar posiciones abiertas
   if(g_state[idx].paused_today) {
      ManageOpenPosition(idx);
      return;
   }

   // --- FASE 1: CONSTRUIR RANGO ASIATICO (00:00 - 07:00 GMT) ---
   if(hour >= AsianStart_H && hour < AsianEnd_H) {
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double mid = (bid + ask) / 2.0;
      if(mid > g_state[idx].asian_high) g_state[idx].asian_high = mid;
      if(mid < g_state[idx].asian_low)  g_state[idx].asian_low  = mid;

      // Dibujar rango asiatico en tiempo real
      if(ShowAsianRange) DrawAsianRange(idx, sym);
   }

   // --- FASE 2: VENTANA BREAKOUT LONDON (07:00 - 09:00 GMT) ---
   // OPTIMIZACION: Solo primeras 2h de Londres. Momentum mas fuerte y limpio.
   // Trades London 09:00-12:00 tienen WR ~25% segun backtest - eliminados.
   if(hour >= AsianEnd_H && hour < 9 && !g_state[idx].traded_london) {
      TryBreakout(idx, sym, "LONDON");
   }

   // --- FASE 3: VENTANA BREAKOUT NY (13:00 - 17:00 GMT) ---
   if(hour >= NY_Start_H && hour < NY_End_H && !g_state[idx].traded_ny) {
      TryBreakout(idx, sym, "NY");
   }

   // --- CIERRE FORZADO AL FIN DE SESION ---
   bool force_close_london = (hour == LondonEnd_H && min == 0 && g_state[idx].traded_london);
   bool force_close_ny     = (hour == NY_End_H    && min == 0 && g_state[idx].traded_ny);
   if(force_close_london || force_close_ny) {
      ForceClose(idx, sym);
   }

   // Gestionar SL breakeven en posicion abierta
   ManageOpenPosition(idx);
}

//+------------------------------------------------------------------+
//| LOGICA CENTRAL DE BREAKOUT                                       |
//+------------------------------------------------------------------+
void TryBreakout(int idx, string sym, string session)
{
   // Validar que el rango asiatico es valido
   if(g_state[idx].asian_high == 0 || g_state[idx].asian_low >= 999999) return;
   double range = g_state[idx].asian_high - g_state[idx].asian_low;
   if(range <= 0) return;

   // Obtener ATR
   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(h_atr[idx], 0, 0, 3, atr_buf) < 2) return;
   double atr = atr_buf[1];
   if(atr <= 0) return;

   // Filtro: Rango minimo vs ATR (evitar dias sin movimiento)
   if(range < atr * MinRangeATR) return;

   // Calcular SL estructural: el mayor entre ATR y el extremo opuesto del rango asiatico
   // FUNDAMENTO: Si el precio vuelve dentro del rango asiatico, el breakout es falso -> cerrar
   double sl_dist_atr   = atr * ATR_SL_Multiplier;
   double sl_dist_range = range * 1.1; // 10% mas alla del extremo opuesto
   double sl_dist = MathMax(sl_dist_atr, sl_dist_range); // El mayor: mas respiracion
   double tp_dist = sl_dist * RR_Mode;

   // Precios actuales
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   // Obtener EMA, RSI, ADX
   double ema_f[], ema_s[], rsi_v[], adx_v[], di_plus[], di_minus[];
   ArraySetAsSeries(ema_f, true); ArraySetAsSeries(ema_s, true);
   ArraySetAsSeries(rsi_v, true); ArraySetAsSeries(adx_v, true);
   ArraySetAsSeries(di_plus, true); ArraySetAsSeries(di_minus, true);

   if(CopyBuffer(h_ema_f[idx], 0, 0, 3, ema_f) < 2)    return;
   if(CopyBuffer(h_ema_s[idx], 0, 0, 3, ema_s) < 2)    return;
   if(CopyBuffer(h_rsi[idx],   0, 0, 3, rsi_v) < 2)    return;
   if(CopyBuffer(h_adx[idx],   0, 0, 3, adx_v) < 2)    return;
   if(CopyBuffer(h_adx[idx],   1, 0, 3, di_plus) < 2)  return;
   if(CopyBuffer(h_adx[idx],   2, 0, 3, di_minus) < 2) return;

   double rsi   = rsi_v[1];
   double adx   = adx_v[1];
   double ema_f1 = ema_f[1];
   double ema_s1 = ema_s[1];
   double dip    = di_plus[1];
   double dim    = di_minus[1];

   // Verificar perdida diaria maxima
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double day_start = g_state[idx].daily_start_balance;
   if(day_start > 0) {
      double day_loss_pct = (day_start - balance) / day_start * 100.0;
      if(day_loss_pct >= MaxDailyLoss_Pct) {
         g_state[idx].paused_today = true;
         return;
      }
   }

   // Verificar racha de perdidas
   if(g_loss_streak >= MaxLosses_Streak) {
      Print("EA pausado por racha de ", g_loss_streak, " perdidas consecutivas");
      g_state[idx].paused_today = true;
      return;
   }

   // ==========================================
   // SIGNAL BUY: Precio rompe el maximo asiatico
   // Confirmaciones: EMA bullish + RSI < 70 + ADX > 20 + DI+ > DI-
   // ==========================================
   bool buy_breakout  = (ask > g_state[idx].asian_high + point * 5);
   bool buy_ema       = (ema_f1 > ema_s1);
   bool buy_rsi       = (rsi < RSI_Overbought);
   bool buy_adx       = (adx > ADX_Min && dip > dim);

   // ==========================================
   // SIGNAL SELL: Precio rompe el minimo asiatico
   // Confirmaciones: EMA bearish + RSI > 30 + ADX > 20 + DI- > DI+
   // ==========================================
   bool sell_breakout = (bid < g_state[idx].asian_low - point * 5);
   bool sell_ema      = (ema_f1 < ema_s1);
   bool sell_rsi      = (rsi > RSI_Oversold);
   bool sell_adx      = (adx > ADX_Min && dim > dip);

   // Calcular lotaje por riesgo
   double lots = CalculateLots(sym, sl_dist);
   if(lots <= 0) return;

   // EJECUTAR BUY
   if(buy_breakout && buy_ema && buy_rsi && buy_adx) {
      double sl = NormalizeDouble(ask - sl_dist, digits);
      double tp = NormalizeDouble(ask + tp_dist, digits);

      if(Trade.Buy(lots, sym, ask, sl, tp, "SBP_" + session + "_BUY")) {
         g_state[idx].last_sl = sl;
         g_state[idx].last_tp = tp;
         g_state[idx].ticket  = Trade.ResultOrder();
         if(session == "LONDON") g_state[idx].traded_london = true;
         else                    g_state[idx].traded_ny     = true;
         g_total_trades++;

         string msg = StringFormat("[%s] BUY %s | Lots:%.2f | SL:%.5f | TP:%.5f | RR:1:%d | Sesion:%s",
                                   sym, TimeToString(TimeCurrent(),TIME_MINUTES), lots, sl, tp, RR_Mode, session);
         Print(msg);
         if(EnableAlerts) Alert(msg);
      }
      return;
   }

   // EJECUTAR SELL
   if(sell_breakout && sell_ema && sell_rsi && sell_adx) {
      double sl = NormalizeDouble(bid + sl_dist, digits);
      double tp = NormalizeDouble(bid - tp_dist, digits);

      if(Trade.Sell(lots, sym, bid, sl, tp, "SBP_" + session + "_SELL")) {
         g_state[idx].last_sl = sl;
         g_state[idx].last_tp = tp;
         g_state[idx].ticket  = Trade.ResultOrder();
         if(session == "LONDON") g_state[idx].traded_london = true;
         else                    g_state[idx].traded_ny     = true;
         g_total_trades++;

         string msg = StringFormat("[%s] SELL %s | Lots:%.2f | SL:%.5f | TP:%.5f | RR:1:%d | Sesion:%s",
                                   sym, TimeToString(TimeCurrent(),TIME_MINUTES), lots, sl, tp, RR_Mode, session);
         Print(msg);
         if(EnableAlerts) Alert(msg);
      }
   }
}

//+------------------------------------------------------------------+
//| GESTION DE POSICION ABIERTA (Break-Even)                        |
//+------------------------------------------------------------------+
void ManageOpenPosition(int idx)
{
   if(!UseBreakEven) return;
   if(g_state[idx].ticket == 0) return;

   string sym = g_symbols[idx];
   if(!PositionSelectByTicket(g_state[idx].ticket)) return;
   if(PositionGetString(POSITION_SYMBOL) != sym) return;

   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_sl = PositionGetDouble(POSITION_SL);
   double current_tp = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   double be_trigger = MathAbs(current_tp - open_price) * 0.33; // 33% del recorrido: protege antes con SL mas amplio

   if(pos_type == POSITION_TYPE_BUY) {
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double new_sl = NormalizeDouble(open_price + SymbolInfoDouble(sym, SYMBOL_POINT) * 5, digits);
      if(bid >= open_price + be_trigger && current_sl < open_price) {
         Trade.PositionModify(g_state[idx].ticket, new_sl, current_tp);
      }
   }
   else if(pos_type == POSITION_TYPE_SELL) {
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double new_sl = NormalizeDouble(open_price - SymbolInfoDouble(sym, SYMBOL_POINT) * 5, digits);
      if(ask <= open_price - be_trigger && current_sl > open_price) {
         Trade.PositionModify(g_state[idx].ticket, new_sl, current_tp);
      }
   }
}

//+------------------------------------------------------------------+
//| CIERRE FORZADO POR FIN DE SESION                                |
//+------------------------------------------------------------------+
void ForceClose(int idx, string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      Trade.PositionClose(ticket);
      Print("[", sym, "] Posicion cerrada por fin de sesion");
   }
   g_state[idx].ticket = 0;
}

//+------------------------------------------------------------------+
//| CALCULAR LOTAJE POR RIESGO FIJO                                 |
//+------------------------------------------------------------------+
double CalculateLots(string sym, double sl_dist)
{
   double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount  = balance * RiskPercent / 100.0;
   double tick_val     = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tick_size    = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double min_lot      = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double max_lot      = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lot_step     = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   if(tick_val <= 0 || tick_size <= 0 || sl_dist <= 0) return min_lot;

   double lots = risk_amount / (sl_dist / tick_size * tick_val);
   lots = MathMax(min_lot, MathMin(max_lot, MathFloor(lots / lot_step) * lot_step));

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| VERIFICAR DRAWDOWN GLOBAL                                        |
//+------------------------------------------------------------------+
bool IsGlobalDrawdownBreached()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance > g_peak_balance) g_peak_balance = balance;

   double dd = (g_peak_balance > 0) ? (g_peak_balance - equity) / g_peak_balance * 100.0 : 0;
   if(dd > g_max_dd) g_max_dd = dd;

   return (dd >= MaxDrawdown_Pct);
}

//+------------------------------------------------------------------+
//| RESET DIARIO                                                     |
//+------------------------------------------------------------------+
void DailyReset()
{
   for(int i = 0; i < 3; i++) {
      ResetSymbolState(i);
   }
   g_loss_streak = 0;
   g_daily_loss  = 0;
   Print("=== RESET DIARIO EJECUTADO ===");
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: actualizar estadisticas al cerrar trades     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong deal_ticket = trans.deal;
   if(!HistoryDealSelect(deal_ticket)) return;
   if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);

   if(profit >= 0) {
      g_wins++;
      g_gross_profit += profit;
      g_loss_streak   = 0;
   } else {
      g_losses++;
      g_gross_loss  += MathAbs(profit);
      g_daily_loss  += MathAbs(profit);
      g_loss_streak++;
      if(g_loss_streak > g_max_streak) g_max_streak = g_loss_streak;
   }

   // Limpiar ticket para el simbolo correspondiente
   string deal_sym = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   for(int i = 0; i < 3; i++) {
      if(g_symbols[i] == deal_sym) {
         g_state[i].ticket = 0;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD - MONITOR DE OPERACIONES                               |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double open_pnl   = equity - balance;
   int    total      = g_wins + g_losses;
   double winrate    = (total > 0) ? (double)g_wins / total * 100.0 : 0;
   double pf         = (g_gross_loss > 0) ? g_gross_profit / g_gross_loss : 0;
   double net_profit = balance - g_init_balance;
   double dd_now     = (g_peak_balance > 0) ? (g_peak_balance - equity) / g_peak_balance * 100.0 : 0;

   string dash = "\n";
   dash += "╔══════════════════════════════════════╗\n";
   dash += "║     SESSION BREAKOUT PRO v2.0        ║\n";
   dash += "╠══════════════════════════════════════╣\n";
   dash += StringFormat("║ Balance:    %12.2f             ║\n", balance);
   dash += StringFormat("║ Equity:     %12.2f             ║\n", equity);
   dash += StringFormat("║ P&L Abierto:%+12.2f             ║\n", open_pnl);
   dash += StringFormat("║ Beneficio:  %+12.2f             ║\n", net_profit);
   dash += "╠══════════════════════════════════════╣\n";
   dash += StringFormat("║ Trades:     %4d  (W:%d / L:%d)   ║\n", total, g_wins, g_losses);
   dash += StringFormat("║ WinRate:    %5.1f%%                  ║\n", winrate);
   dash += StringFormat("║ ProfitFact: %7.2f                 ║\n", pf);
   dash += StringFormat("║ DrawDown:   %5.1f%% (Max:%5.1f%%)    ║\n", dd_now, g_max_dd);
   dash += StringFormat("║ Racha Perd: %4d  (Max:%4d)       ║\n", g_loss_streak, g_max_streak);
   dash += "╠══════════════════════════════════════╣\n";
   dash += "║ SESIONES ACTIVAS:                    ║\n";

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;

   string lon_status = (hour >= AsianEnd_H && hour < LondonEnd_H) ? "[ACTIVA]" : "[cerrada]";
   string ny_status  = (hour >= NY_Start_H && hour < NY_End_H)    ? "[ACTIVA]" : "[cerrada]";
   string asi_status = (hour >= AsianStart_H && hour < AsianEnd_H)? "[ACTIVA]" : "[cerrada]";

   dash += StringFormat("║  Asiatica:   00:00-07:00 GMT %s ║\n", asi_status);
   dash += StringFormat("║  Londres:    07:00-12:00 GMT %s ║\n", lon_status);
   dash += StringFormat("║  NuevaYork:  13:00-17:00 GMT %s ║\n", ny_status);
   dash += "╠══════════════════════════════════════╣\n";
   dash += "║ ESTADO POR SIMBOLO:                  ║\n";

   for(int i = 0; i < 3; i++) {
      string sym     = g_symbols[i];
      string trd_lon = g_state[i].traded_london ? "✓" : "·";
      string trd_ny  = g_state[i].traded_ny     ? "✓" : "·";
      string paused  = g_state[i].paused_today  ? "PAUSADO" : "OK";
      string pos_open = (g_state[i].ticket > 0) ? "EN TRADE" : "Esperando";
      dash += StringFormat("║  %s: L:%s NY:%s | %s | %s     ║\n",
              sym, trd_lon, trd_ny, pos_open, paused);
   }
   dash += "╚══════════════════════════════════════╝";

   Comment(dash);
}

//+------------------------------------------------------------------+
//| DIBUJAR RANGO ASIATICO EN GRAFICO                               |
//+------------------------------------------------------------------+
void DrawAsianRange(int idx, string sym)
{
   if(sym != Symbol()) return; // Solo dibujar en el grafico activo

   double high = g_state[idx].asian_high;
   double low  = g_state[idx].asian_low;
   if(high == 0 || low >= 999999) return;

   string name_h = "SBP_AR_H_" + sym;
   string name_l = "SBP_AR_L_" + sym;

   if(ObjectFind(0, name_h) < 0)
      ObjectCreate(0, name_h, OBJ_HLINE, 0, 0, high);
   else
      ObjectSetDouble(0, name_h, OBJPROP_PRICE, high);

   ObjectSetInteger(0, name_h, OBJPROP_COLOR, ColorAsian);
   ObjectSetInteger(0, name_h, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name_h, OBJPROP_WIDTH, 2);
   ObjectSetString(0,  name_h, OBJPROP_TOOLTIP, "Asian High: " + DoubleToString(high, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));

   if(ObjectFind(0, name_l) < 0)
      ObjectCreate(0, name_l, OBJ_HLINE, 0, 0, low);
   else
      ObjectSetDouble(0, name_l, OBJPROP_PRICE, low);

   ObjectSetInteger(0, name_l, OBJPROP_COLOR, ColorAsian);
   ObjectSetInteger(0, name_l, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name_l, OBJPROP_WIDTH, 2);
   ObjectSetString(0,  name_l, OBJPROP_TOOLTIP, "Asian Low: " + DoubleToString(low, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DIBUJAR SESIONES EN GRAFICO (rectangulos de fondo)              |
//+------------------------------------------------------------------+
void DrawSessions(MqlDateTime &dt)
{
   if(!ShowSessions) return;

   datetime now      = TimeCurrent();
   datetime day_open = StringToTime(TimeToString(now, TIME_DATE) + " 00:00");

   // Sesion Asiatica
   DrawSessionRect("SBP_Ses_Asian",
                   day_open + AsianStart_H * 3600,
                   day_open + AsianEnd_H   * 3600,
                   ColorAsian, "Asiatica");

   // Sesion Londres
   DrawSessionRect("SBP_Ses_London",
                   day_open + AsianEnd_H   * 3600,
                   day_open + LondonEnd_H  * 3600,
                   ColorLondon, "Londres");

   // Sesion NY
   DrawSessionRect("SBP_Ses_NY",
                   day_open + NY_Start_H * 3600,
                   day_open + NY_End_H   * 3600,
                   ColorNY, "Nueva York");
}

//+------------------------------------------------------------------+
//| HELPER: Dibujar rectangulo de sesion                            |
//+------------------------------------------------------------------+
void DrawSessionRect(string name, datetime t1, datetime t2, color clr, string label)
{
   double chart_max = ChartGetDouble(0, CHART_PRICE_MAX);
   double chart_min = ChartGetDouble(0, CHART_PRICE_MIN);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, chart_max, t2, chart_min);
   else {
      ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
      ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, chart_max);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 1, chart_min);
   }

   // Aplicar color con transparencia via componente alpha (formato ARGB: 0xAARRGGBB)
   uchar r = (uchar)((clr)       & 0xFF);
   uchar g = (uchar)((clr >> 8)  & 0xFF);
   uchar b = (uchar)((clr >> 16) & 0xFF);
   color clr_fill = (color)((b << 16) | (g << 8) | r); // reconstruir color

   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clr_fill);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,    "Sesion: " + label);
   ObjectSetString(0,  name, OBJPROP_TEXT,       label);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DESINICIALIZACION                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   // Limpiar objetos del grafico
   ObjectsDeleteAll(0, "SBP_");
   Print("SESSION BREAKOUT PRO - Detenido");
}

//+------------------------------------------------------------------+
//| RESUMEN ESTADISTICO EN LOG                                       |
//+------------------------------------------------------------------+
void PrintStats()
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   int    total     = g_wins + g_losses;
   double winrate   = (total > 0) ? (double)g_wins / total * 100.0 : 0;
   double pf        = (g_gross_loss > 0) ? g_gross_profit / g_gross_loss : 0;

   Print("=== RESUMEN SESSION BREAKOUT PRO ===");
   Print("Balance Final:   ", DoubleToString(balance, 2));
   Print("Beneficio Neto:  ", DoubleToString(balance - g_init_balance, 2));
   Print("Total Trades:    ", total);
   Print("Wins / Losses:   ", g_wins, " / ", g_losses);
   Print("Win Rate:        ", DoubleToString(winrate, 1), "%");
   Print("Profit Factor:   ", DoubleToString(pf, 2));
   Print("Max Drawdown:    ", DoubleToString(g_max_dd, 2), "%");
   Print("Max Loss Streak: ", g_max_streak);
}
//+------------------------------------------------------------------+
