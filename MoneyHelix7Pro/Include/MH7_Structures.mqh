//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Estructuras de Datos Globales               |
//|  MH7_Structures.mqh  v1.0 FINAL                                |
//|  Basado en: 39 libros + 100 respuestas del operador            |
//|  Refs: Vince, Grinold&Kahn, Lopez de Prado, Grimes, Aronson   |
//+------------------------------------------------------------------+
#ifndef MH7_STRUCTURES_MQH
#define MH7_STRUCTURES_MQH

//+------------------------------------------------------------------+
//| Configuracion individual de cada simbolo (15 instancias)        |
//+------------------------------------------------------------------+
struct SymbolConfig
{
   string   symbol_name;
   int      magic_number;
   double   allocated_capital;
   double   risk_percent;
   int      structure_lookback_bars;
   int      momentum_bars;
   double   min_volatility_atr;
   double   signal_quality_threshold;
   bool     trading_in_ny_session;
   bool     trading_in_eu_session;
   double   correlation_with_xauusd;
   double   session_risk_multiplier;
   int      atr_period;
   double   atr_sl_multiplier;
   double   tp_ratio_to_sl;
   double   max_lot_size;
   // ---- Handles de indicadores persistentes (init una vez) ----
   int      h_atr_m15;      // ATR M15
   int      h_rsi_m15;      // RSI 14 M15
   int      h_ma50_m15;     // SMA 50 M15
   int      h_ma200_m15;    // SMA 200 M15
   int      h_ma200_d1;     // SMA 200 D1 (Motor A - valor justo)
   int      h_atr_exec;     // ATR M15 para ejecucion (puede ser el mismo)
};

//+------------------------------------------------------------------+
//| Estado completo de posicion abierta                              |
//+------------------------------------------------------------------+
struct PositionState
{
   bool     is_open;
   int      direction;              // +1 BUY / -1 SELL / 0 NONE
   double   entry_price;
   double   current_stop_loss;
   double   take_profit;
   double   lot_size;
   double   unrealized_pnl;
   datetime open_time;
   ulong    ticket;
   bool     partial_close_executed;
   bool     trailing_stop_active;
   bool     breakeven_moved;
   bool     time_trail_done;
   bool     divergence_exit_triggered;
   double   partial_exit_pct;
   double   trailing_activation_pct;
   double   sl_pips;
   double   tp_pips;
   double   breakeven_buffer_pips;
   double   high_water_mark;        // Precio mas favorable alcanzado (para trailing)
};

//+------------------------------------------------------------------+
//| Estado completo de senal generada                                |
//+------------------------------------------------------------------+
struct SignalState
{
   double   value_score;            // Motor A: Graham Value (0-100)
   double   momentum_score;         // Motor B: Clenow Momentum (0-100)
   double   ml_score;               // Motor C: ML Ensemble (0-100)
   double   final_quality;          // Score combinado final
   int      direction;              // +1 BUY / -1 SELL / 0 NEUTRAL
   int      buy_votes;              // Votos BUY (0-3)
   int      sell_votes;             // Votos SELL (0-3)
   datetime signal_time;
   string   reason;
   bool     quality_passed;
};

//+------------------------------------------------------------------+
//| Niveles calculados de SL y TP                                    |
//+------------------------------------------------------------------+
struct SLTPLevels
{
   double   stop_loss;
   double   take_profit;
   double   sl_distance_pips;
   double   tp_distance_pips;
   double   risk_reward_ratio;
   bool     is_valid;
};

//+------------------------------------------------------------------+
//| Metricas de performance por instancia EA                         |
//+------------------------------------------------------------------+
struct PerformanceMetrics
{
   int      total_trades;
   int      winning_trades;
   int      losing_trades;
   int      consecutive_losses;
   int      max_consecutive_losses;
   double   total_profit;
   double   gross_profit;
   double   gross_loss;
   double   largest_win;
   double   largest_loss;
   double   max_drawdown_pct;
   double   current_drawdown_pct;
   double   peak_equity;
   double   win_rate_pct;
   double   profit_factor;
   double   expectancy;
   double   sharpe_ratio;
   double   sortino_ratio;
   double   recovery_factor;
   double   daily_pnl;
   double   weekly_pnl;
   double   monthly_pnl;
   datetime last_trade_time;
   datetime start_date;
   double   daily_returns[252];
   int      daily_returns_count;
};

//+------------------------------------------------------------------+
//| Resultado del sistema de votacion 2/3                            |
//+------------------------------------------------------------------+
struct VotingResult
{
   int      direction;
   double   quality_score;
   string   voting_details;
   bool     threshold_passed;
};

//+------------------------------------------------------------------+
//| Estado global del sistema                                        |
//+------------------------------------------------------------------+
struct SystemState
{
   bool     is_trading_allowed;
   bool     circuit_breaker_active;
   double   account_dd_peak;
   double   daily_loss_accumulated;
   double   max_daily_loss_pct;
   double   max_total_dd_pct;
   double   soft_dd_pct;
   datetime circuit_breaker_until;
   datetime last_daily_reset;
   int      total_active_positions;
   bool     news_filter_active;
   datetime news_block_until;
};

//+------------------------------------------------------------------+
//| Parametros del modelo ML (proxy implementacion en MQL5)          |
//+------------------------------------------------------------------+
struct MLModelParams
{
   double   rf_weights[20];
   double   rf_bias;
   double   rf_threshold;
   double   svm_weights[20];
   double   svm_bias;
   double   svm_threshold;
   double   gb_weights[20];
   double   gb_bias;
   double   gb_threshold;
   datetime last_retrained;
   int      training_samples;
   double   in_sample_accuracy;
   double   out_sample_accuracy;
   bool     is_trained;
};

#endif // MH7_STRUCTURES_MQH
