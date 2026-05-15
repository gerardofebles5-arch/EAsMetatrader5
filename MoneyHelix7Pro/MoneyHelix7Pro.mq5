//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO                                               |
//|  MoneyHelix7Pro.mq5  v1.0 FINAL                                |
//|                                                                  |
//|  Sistema de Trading Algoritmico Profesional                    |
//|  15 Instancias Independientes | 3 Motores | Votacion 2/3       |
//|  Timeframe: M15 | Sesiones: NY (13-21) + EU (08-16) UTC       |
//|                                                                  |
//|  Basado en 39 libros de trading cuantitativo:                  |
//|  Graham, Livermore, Grimes, Aronson, Clenow, Vince,           |
//|  Lopez de Prado, Grinold&Kahn, Carver, Chan, Narang, Tsay    |
//|                                                                  |
//|  Magic Numbers: 700001 - 700015                                |
//|  Capital por instancia: $3,333.33                             |
//|  Riesgo por trade: 2% (Kelly 25%)                             |
//+------------------------------------------------------------------+
#property copyright "MoneyHelix7 Pro - 2025"
#property version   "1.00"

// ---- Includes del sistema ----
#include "Include/MH7_Structures.mqh"
#include "Include/MH7_SymbolConfig.mqh"
#include "Include/MH7_Engines.mqh"
#include "Include/MH7_Voting.mqh"
#include "Include/MH7_Validators.mqh"
#include "Include/MH7_Execution.mqh"
#include "Include/MH7_PositionMgmt.mqh"
#include "Include/MH7_Performance.mqh"
#include "Include/MH7_Dashboard.mqh"
#include "Include/MH7_Logger.mqh"

//====================================================================
// PARAMETROS DE ENTRADA (configurables sin recompilar)
//====================================================================

// ---- Riesgo global ----
input double  InpRiskPercent       = 2.0;    // Riesgo por trade (% del balance)
input double  InpMaxDailyLossPct   = 6.0;    // Max perdida diaria (%)
input double  InpMaxTotalDDPct     = 20.0;   // Max drawdown total (%)
input double  InpSoftDDPct         = 15.0;   // DD suave - reducir 50% (%)

// ---- Filtros de senal ----
input double  InpMinQuality        = 60.0;   // Calidad minima de senal (0-100)
input int     InpMaxBarsOpen       = 48;     // Max barras M15 en posicion (12h)

// ---- Gestión de posicion (ATR-based, estos inputs son legacy) ----
input double  InpPartialClosePct   = 70.0;   // no usado
input double  InpBreakevenPct      = 60.0;   // no usado
input double  InpTrailingActPct    = 50.0;   // no usado

// ---- Opciones de sistema ----
input bool    InpEnableDashboard   = true;   // Mostrar panel en pantalla
input bool    InpEnableLogging     = true;   // Guardar log CSV
input int     InpDashboardUpdate   = 15;     // Segundos entre actualizaciones panel
input bool    InpEnableNewsFilter  = false;  // Activar filtro de noticias manual
input int     InpMLRetrainDays     = 7;      // Dias entre reentrenamientos ML

// ---- Telegram ----
input string  InpTelegramToken     = "";     // Bot Token de Telegram
input string  InpTelegramChatID    = "";     // Chat ID de Telegram
input bool    InpEnableTelegram    = false;  // Activar alertas Telegram

// ---- Selector de simbolos activos (1=activado, 0=desactivado) ----
input bool    InpEnable_XAUUSD    = true;    // 700001: XAUUSD
input bool    InpEnable_DXY       = false;   // 700002: DXY
input bool    InpEnable_EURUSD    = false;   // 700003: EURUSD
input bool    InpEnable_GBPUSD    = false;   // 700004: GBPUSD
input bool    InpEnable_USDJPY    = false;   // 700005: USDJPY
input bool    InpEnable_XAGUSD    = false;   // 700006: XAGUSD
input bool    InpEnable_WTICRUSD  = false;   // 700007: WTICRUSD
input bool    InpEnable_NATGAS    = false;   // 700008: NATGAS
input bool    InpEnable_SPX       = false;   // 700009: SPX
input bool    InpEnable_DAX       = false;   // 700010: DAX
input bool    InpEnable_FTSE      = false;   // 700011: FTSE
input bool    InpEnable_NIKKEI    = false;   // 700012: NIKKEI
input bool    InpEnable_COPPER    = false;   // 700013: COPPER
input bool    InpEnable_BTCUSD    = false;   // 700014: BTCUSD
input bool    InpEnable_VIX       = false;   // 700015: VIX

//====================================================================
// VARIABLES GLOBALES
//====================================================================

#define NUM_SYMBOLS 15

SymbolConfig     g_cfg[NUM_SYMBOLS];          // Configuracion de 15 simbolos
PositionState    g_pos[NUM_SYMBOLS];          // Estado de posicion por simbolo
PerformanceMetrics g_metrics[NUM_SYMBOLS];   // Metricas por simbolo
SignalState      g_signals[NUM_SYMBOLS];      // Ultima senal por simbolo
MLModelParams    g_ml[NUM_SYMBOLS];           // Modelos ML por simbolo
SystemState      g_sys;                        // Estado global del sistema

bool             g_enabled[NUM_SYMBOLS];       // Simbolos habilitados
datetime         g_last_dash_update = 0;       // Control de actualizacion panel
datetime         g_last_ml_retrain  = 0;       // Control de reentrenamiento ML
datetime         g_last_daily_report = 0;      // Control de reporte diario
datetime         g_last_bar_time[NUM_SYMBOLS]; // Control de nueva barra por simbolo

//+------------------------------------------------------------------+
//| INICIALIZACION DEL EA                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==================================================");
   Print("  MONEYHELIX7 PRO v1.0 - Initializing...");
   Print("==================================================");

   // ---- 1. Inicializar configuraciones de simbolos ----
   InitSymbolConfigs(g_cfg);

   // ---- 2. Aplicar overrides de inputs ----
   for(int i = 0; i < NUM_SYMBOLS; i++)
   {
      g_cfg[i].risk_percent         = InpRiskPercent;
      g_cfg[i].signal_quality_threshold = MathMax(InpMinQuality,
                                           g_cfg[i].signal_quality_threshold);
   }

   // ---- 3. Definir simbolos habilitados ----
   bool enable_flags[NUM_SYMBOLS] = {
      InpEnable_XAUUSD, InpEnable_DXY,    InpEnable_EURUSD,
      InpEnable_GBPUSD, InpEnable_USDJPY, InpEnable_XAGUSD,
      InpEnable_WTICRUSD, InpEnable_NATGAS, InpEnable_SPX,
      InpEnable_DAX,    InpEnable_FTSE,   InpEnable_NIKKEI,
      InpEnable_COPPER, InpEnable_BTCUSD, InpEnable_VIX
   };
   for(int i = 0; i < NUM_SYMBOLS; i++) g_enabled[i] = enable_flags[i];

   // ---- 4. Inicializar estado global ----
   g_sys.is_trading_allowed     = true;
   g_sys.circuit_breaker_active = false;
   g_sys.account_dd_peak        = AccountInfoDouble(ACCOUNT_EQUITY);
   g_sys.daily_loss_accumulated = 0.0;
   g_sys.max_daily_loss_pct     = InpMaxDailyLossPct;
   g_sys.max_total_dd_pct       = InpMaxTotalDDPct;
   g_sys.soft_dd_pct            = InpSoftDDPct;
   g_sys.last_daily_reset       = TimeCurrent();
   g_sys.total_active_positions = 0;
   g_sys.news_filter_active     = InpEnableNewsFilter;
   g_sys.circuit_breaker_until  = 0;
   g_sys.news_block_until       = 0;

   // ---- 5. Inicializar metricas, posiciones, ML y senales ----
   for(int i = 0; i < NUM_SYMBOLS; i++)
   {
      g_pos[i].is_open   = false;
      g_pos[i].direction = 0;

      // Solo procesar simbolos habilitados
      if(!g_enabled[i])
      {
         PrintFormat("  [%02d] %-10s | Magic: %d | DISABLED (skipped)",
                     i+1, g_cfg[i].symbol_name, g_cfg[i].magic_number);
         continue;
      }

      // Verificar que el simbolo existe en el broker
      if(SymbolInfoDouble(g_cfg[i].symbol_name, SYMBOL_BID) == 0.0)
      {
         PrintFormat("  [%02d] %-10s | WARNING: symbol not found in broker - disabling",
                     i+1, g_cfg[i].symbol_name);
         g_enabled[i] = false;
         continue;
      }

      InitMetrics(g_metrics[i], g_cfg[i].symbol_name);
      InitMLModel(g_ml[i]);

      // Inicializar handles de indicadores persistentes
      InitSymbolHandles(g_cfg[i]);

      // Cargar historial previo si existe
      LoadHistoryFromMT5(g_metrics[i], g_cfg[i].magic_number, TimeCurrent() - 90*86400);

      // Sincronizar posiciones abiertas si el EA reinicia
      SyncPositionState(g_cfg[i].symbol_name, g_cfg[i].magic_number, g_pos[i]);

      PrintFormat("  [%02d] %-10s | Magic: %d | ENABLED",
                  i+1, g_cfg[i].symbol_name, g_cfg[i].magic_number);
   }

   // ---- 6. Inicializar logger y dashboard ----
   if(InpEnableLogging)
   {
      EnableCSVLog   = InpEnableLogging;
      EnableTelegram = InpEnableTelegram;
      TelegramToken  = InpTelegramToken;
      TelegramChatID = InpTelegramChatID;
      InitLogger("MoneyHelix7Pro");
   }
   if(InpEnableDashboard) InitDashboard(g_cfg, NUM_SYMBOLS);

   // ---- 7. Configurar timer para tareas periodicas ----
   EventSetTimer(30);

   g_last_ml_retrain    = TimeCurrent();
   g_last_daily_report  = TimeCurrent();
   ArrayInitialize(g_last_bar_time, 0);

   Print("  MONEYHELIX7 PRO - Ready. Active symbols: ", CountEnabled());
   Print("==================================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DESINICIALIZACION                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpEnableDashboard) DestroyDashboard();

   // Liberar handles de indicadores
   for(int i = 0; i < NUM_SYMBOLS; i++)
      if(g_enabled[i]) ReleaseSymbolHandles(g_cfg[i]);

   // Reporte final
   Print("==================================================");
   Print("  MONEYHELIX7 PRO - Shutting down. Reason: ", reason);
   double total = 0;
   for(int i = 0; i < NUM_SYMBOLS; i++) total += g_metrics[i].total_profit;
   PrintFormat("  Total PnL all symbols: $%.2f", total);
   Print("==================================================");
}

//+------------------------------------------------------------------+
//| TICK PRINCIPAL - Se ejecuta en cada precio nuevo               |
//+------------------------------------------------------------------+
void OnTick()
{
   // ---- Verificacion de sistema ----
   if(!g_sys.is_trading_allowed && !g_sys.circuit_breaker_active) return;

   // ---- Reset diario ----
   DailyReset(g_sys, g_metrics[0]);

   // ---- Contador de posiciones abiertas ----
   g_sys.total_active_positions = 0;

   // ---- Loop principal: procesar cada simbolo ----
   for(int i = 0; i < NUM_SYMBOLS; i++)
   {
      if(!g_enabled[i]) continue;

      string sym = g_cfg[i].symbol_name;

      // ---- A. Gestionar posicion abierta si existe ----
      if(g_pos[i].is_open)
      {
         ManageOpenPosition(sym, g_pos[i], g_cfg[i], InpMaxBarsOpen);
         if(g_pos[i].is_open) g_sys.total_active_positions++;
         continue;  // No buscar nueva senal si hay posicion abierta
      }

      // ---- Throttle: solo evaluar senales en nueva barra M15 ----
      datetime bar_time = iTime(sym, PERIOD_M15, 0);
      if(bar_time == g_last_bar_time[i]) continue;
      g_last_bar_time[i] = bar_time;

      // ---- B. Generar senal (3 motores + votacion) ----
      VotingResult vote = GenerateSignal(sym, g_cfg[i], g_ml[i]);
      FillSignalState(g_signals[i], vote,
                      MotorA_ValueScore(sym, g_cfg[i].structure_lookback_bars, g_cfg[i].h_ma200_d1),
                      MotorB_MomentumScore(sym, g_cfg[i].momentum_bars),
                      MotorC_MLScore(sym, g_ml[i],
                                     g_cfg[i].h_atr_m15, g_cfg[i].h_rsi_m15,
                                     g_cfg[i].h_ma50_m15, g_cfg[i].h_ma200_m15));

      // ---- C. Si no hay senal valida, continuar ----
      if(!vote.threshold_passed) continue;

      // ---- D. Ejecutar validadores pre-trade ----
      double dd_adj = 1.0;
      if(!RunAllValidators(sym, g_cfg[i], g_sys, g_metrics[i], dd_adj, vote.direction))
         continue;

      // ---- E. Ejecutar trade ----
      bool opened = ExecuteTrade(sym, vote.direction, g_cfg[i], dd_adj, g_pos[i]);

      if(opened)
      {
         g_sys.total_active_positions++;

         // Ajustar parametros de gestion segun inputs
         g_pos[i].partial_exit_pct        = InpPartialClosePct;
         g_pos[i].trailing_activation_pct = InpTrailingActPct;

         // Registrar apertura en log
         if(InpEnableLogging)
            LogTradeOpen(g_cfg[i], g_pos[i], g_signals[i]);

         AlertTradeOpen(sym, vote.direction, g_pos[i].lot_size,
                        g_pos[i].entry_price, g_pos[i].current_stop_loss,
                        g_pos[i].take_profit, vote.quality_score);
      }
   }

   // ---- F. Actualizar dashboard ----
   if(InpEnableDashboard && TimeCurrent() - g_last_dash_update >= InpDashboardUpdate)
   {
      UpdateDashboard(g_cfg, g_pos, g_metrics, g_signals, g_sys, NUM_SYMBOLS);
      g_last_dash_update = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| TIMER - Tareas periodicas cada 30 segundos                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // ---- Reentrenamiento ML semanal ----
   int days_since_train = (int)((TimeCurrent() - g_last_ml_retrain) / 86400);
   if(days_since_train >= InpMLRetrainDays)
   {
      for(int i = 0; i < NUM_SYMBOLS; i++)
         if(g_enabled[i])
            RetrainMLModel(g_ml[i], g_cfg[i].symbol_name, 90);
      g_last_ml_retrain = TimeCurrent();
   }

   // ---- Reporte diario (al cierre NY ~22:00 UTC) - una vez por dia ----
   MqlDateTime dt;  TimeToStruct(TimeGMT(), dt);
   MqlDateTime ldt; TimeToStruct(g_last_daily_report, ldt);
   if(dt.hour == 22 && dt.min < 1 && dt.day != ldt.day)
   {
      SendDailyReport(g_cfg, g_metrics, NUM_SYMBOLS);
      g_last_daily_report = TimeGMT();
   }

   // ---- Actualizar peak equity global ----
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_sys.account_dd_peak) g_sys.account_dd_peak = eq;
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION - Detectar cierres para actualizar metricas   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong deal_ticket = trans.deal;
   if(!HistoryDealSelect(deal_ticket)) return;

   ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   if(deal_entry != DEAL_ENTRY_OUT) return;

   int    deal_magic  = (int)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(deal_ticket, DEAL_SWAP)   +
                        HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   double deal_price  = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);

   // Encontrar el simbolo correspondiente por magic number
   for(int i = 0; i < NUM_SYMBOLS; i++)
   {
      if(g_cfg[i].magic_number == deal_magic && g_cfg[i].symbol_name == deal_symbol)
      {
         // Actualizar metricas
         RegisterTradeResult(g_metrics[i], deal_profit);

         // Actualizar perdida diaria acumulada
         if(deal_profit < 0)
            g_sys.daily_loss_accumulated += MathAbs(deal_profit);

         // Log de cierre
         string exit_reason = "TP_SL";
         if(g_pos[i].partial_close_executed)  exit_reason = "PARTIAL";
         if(g_pos[i].trailing_stop_active)    exit_reason = "TRAILING";
         if(g_pos[i].breakeven_moved)         exit_reason = "BREAKEVEN";
         if(g_pos[i].divergence_exit_triggered) exit_reason = "DIVERGENCE";
         if(g_pos[i].time_trail_done)         exit_reason = "TIME";

         if(InpEnableLogging)
            LogTradeClose(g_cfg[i], g_pos[i], g_metrics[i], g_signals[i],
                          deal_price, deal_profit, exit_reason);

         AlertTradeClose(deal_symbol, deal_profit, exit_reason,
                         g_metrics[i].win_rate_pct, g_metrics[i].total_profit);

         // Resetear estado de posicion
         g_pos[i].is_open                   = false;
         g_pos[i].direction                 = 0;
         g_pos[i].partial_close_executed    = false;
         g_pos[i].trailing_stop_active      = false;
         g_pos[i].breakeven_moved           = false;
         g_pos[i].time_trail_done           = false;
         g_pos[i].divergence_exit_triggered = false;
         g_pos[i].high_water_mark           = 0.0;

         PrintFormat("TRADE CLOSED: %s | P&L=$%.2f | %s | WR=%.1f%% | Total=$%.2f",
                     deal_symbol, deal_profit, exit_reason,
                     g_metrics[i].win_rate_pct, g_metrics[i].total_profit);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| FUNCIONES AUXILIARES                                             |
//+------------------------------------------------------------------+

int CountEnabled()
{
   int cnt = 0;
   for(int i = 0; i < NUM_SYMBOLS; i++)
      if(g_enabled[i]) cnt++;
   return cnt;
}

//+------------------------------------------------------------------+
//| Bloquear trading por noticias (llamar externamente si es        |
//| necesario bloquear manualmente un periodo de noticias)          |
//+------------------------------------------------------------------+
void BlockForNews(int minutes = 30)
{
   g_sys.news_filter_active = true;
   g_sys.news_block_until   = TimeCurrent() + minutes * 60;
   PrintFormat("News block activated: %d minutes", minutes);
}

//+------------------------------------------------------------------+
//| Forzar cierre de todas las posiciones (emergencia)              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason = "EMERGENCY")
{
   for(int i = 0; i < NUM_SYMBOLS; i++)
   {
      if(g_pos[i].is_open)
      {
         ClosePosition(g_cfg[i].symbol_name, g_cfg[i].magic_number, reason);
         g_pos[i].is_open = false;
      }
   }
}
