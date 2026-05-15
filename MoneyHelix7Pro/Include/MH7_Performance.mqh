//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Metricas de Performance                     |
//|  MH7_Performance.mqh  v1.0 FINAL                               |
//|  Sharpe, Sortino, DD, PF, WR, IC, Recovery                    |
//|  Refs: Grinold&Kahn, Vince, Aronson                           |
//+------------------------------------------------------------------+
#ifndef MH7_PERFORMANCE_MQH
#define MH7_PERFORMANCE_MQH
#include "MH7_Structures.mqh"

//+------------------------------------------------------------------+
//| Inicializar estructura de metricas en cero                       |
//+------------------------------------------------------------------+
void InitMetrics(PerformanceMetrics &m, string symbol)
{
   m.total_trades           = 0;
   m.winning_trades         = 0;
   m.losing_trades          = 0;
   m.consecutive_losses     = 0;
   m.max_consecutive_losses = 0;
   m.total_profit           = 0.0;
   m.gross_profit           = 0.0;
   m.gross_loss             = 0.0;
   m.largest_win            = 0.0;
   m.largest_loss           = 0.0;
   m.max_drawdown_pct       = 0.0;
   m.current_drawdown_pct   = 0.0;
   m.peak_equity            = AccountInfoDouble(ACCOUNT_EQUITY);
   m.win_rate_pct           = 0.0;
   m.profit_factor          = 0.0;
   m.expectancy             = 0.0;
   m.sharpe_ratio           = 0.0;
   m.sortino_ratio          = 0.0;
   m.recovery_factor        = 0.0;
   m.daily_pnl              = 0.0;
   m.weekly_pnl             = 0.0;
   m.monthly_pnl            = 0.0;
   m.last_trade_time        = 0;
   m.start_date             = TimeCurrent();
   m.daily_returns_count    = 0;
   ArrayInitialize(m.daily_returns, 0.0);
}

//+------------------------------------------------------------------+
//| Registrar resultado de un trade cerrado                          |
//+------------------------------------------------------------------+
void RegisterTradeResult(PerformanceMetrics &m, double profit)
{
   m.total_trades++;
   m.total_profit  += profit;
   m.last_trade_time = TimeCurrent();

   if(profit > 0)
   {
      m.winning_trades++;
      m.gross_profit       += profit;
      m.consecutive_losses  = 0;
      if(profit > m.largest_win) m.largest_win = profit;
   }
   else
   {
      m.losing_trades++;
      m.gross_loss         += MathAbs(profit);
      m.consecutive_losses++;
      if(m.consecutive_losses > m.max_consecutive_losses)
         m.max_consecutive_losses = m.consecutive_losses;
      if(MathAbs(profit) > m.largest_loss) m.largest_loss = MathAbs(profit);
   }

   // Recalcular KPIs principales
   UpdateKPIs(m);
}

//+------------------------------------------------------------------+
//| Actualizar todos los KPIs derivados                              |
//+------------------------------------------------------------------+
void UpdateKPIs(PerformanceMetrics &m)
{
   if(m.total_trades == 0) return;

   // Win Rate
   m.win_rate_pct = (m.total_trades > 0) ?
                    (double)m.winning_trades / m.total_trades * 100.0 : 0.0;

   // Profit Factor (Vince)
   m.profit_factor = (m.gross_loss > 0) ? m.gross_profit / m.gross_loss : 0.0;

   // Expectancy por trade
   double avg_win  = (m.winning_trades > 0) ? m.gross_profit / m.winning_trades : 0.0;
   double avg_loss = (m.losing_trades  > 0) ? m.gross_loss   / m.losing_trades  : 0.0;
   double wr       = m.win_rate_pct / 100.0;
   m.expectancy    = (wr * avg_win) - ((1.0 - wr) * avg_loss);

   // Drawdown actual
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > m.peak_equity) m.peak_equity = equity;
   m.current_drawdown_pct = (m.peak_equity > 0) ?
                            ((m.peak_equity - equity) / m.peak_equity) * 100.0 : 0.0;
   if(m.current_drawdown_pct > m.max_drawdown_pct)
      m.max_drawdown_pct = m.current_drawdown_pct;

   // Recovery Factor
   m.recovery_factor = (m.max_drawdown_pct > 0) ?
                       m.total_profit / m.max_drawdown_pct : 0.0;

   // Sharpe y Sortino (si hay suficientes retornos diarios)
   if(m.daily_returns_count >= 10)
   {
      m.sharpe_ratio  = CalculateSharpeRatio(m);
      m.sortino_ratio = CalculateSortino(m);
   }
}

//+------------------------------------------------------------------+
//| Sharpe Ratio anualizado (Grinold & Kahn)                        |
//|  SR = (mean_return * 252) / (stddev * sqrt(252))               |
//+------------------------------------------------------------------+
double CalculateSharpeRatio(const PerformanceMetrics &m)
{
   int n = m.daily_returns_count;
   if(n < 5) return 0.0;

   double sum = 0;
   for(int i = 0; i < n; i++) sum += m.daily_returns[i];
   double mean_ret = sum / n;

   double var = 0;
   for(int i = 0; i < n; i++)
   {
      double diff = m.daily_returns[i] - mean_ret;
      var += diff * diff;
   }
   double stddev = (n > 1) ? MathSqrt(var / (n - 1)) : 0.0;
   if(stddev == 0) return 0.0;

   // Anualizar asumiendo 252 dias de trading
   return (mean_ret * 252.0) / (stddev * MathSqrt(252.0));
}

//+------------------------------------------------------------------+
//| Sortino Ratio (solo volatilidad negativa)                        |
//|  ST = (mean_return * 252) / (downside_std * sqrt(252))         |
//+------------------------------------------------------------------+
double CalculateSortino(const PerformanceMetrics &m)
{
   int n = m.daily_returns_count;
   if(n < 5) return 0.0;

   double sum = 0;
   for(int i = 0; i < n; i++) sum += m.daily_returns[i];
   double mean_ret = sum / n;

   // Solo dias negativos para el denominador
   double downside_var = 0;
   int    neg_count    = 0;
   for(int i = 0; i < n; i++)
   {
      if(m.daily_returns[i] < 0)
      {
         downside_var += m.daily_returns[i] * m.daily_returns[i];
         neg_count++;
      }
   }
   if(neg_count == 0) return 99.0;  // Sin dias negativos = excelente
   double downside_std = MathSqrt(downside_var / neg_count);
   if(downside_std == 0) return 0.0;

   return (mean_ret * 252.0) / (downside_std * MathSqrt(252.0));
}

//+------------------------------------------------------------------+
//| Registrar retorno diario (para Sharpe/Sortino)                  |
//+------------------------------------------------------------------+
void AddDailyReturn(PerformanceMetrics &m, double daily_return_pct)
{
   int idx = m.daily_returns_count % 252;
   m.daily_returns[idx] = daily_return_pct;
   m.daily_returns_count++;
   m.daily_pnl = daily_return_pct;
}

//+------------------------------------------------------------------+
//| Cargar historial de trades desde Deal history de MT5            |
//+------------------------------------------------------------------+
void LoadHistoryFromMT5(PerformanceMetrics &m, int magic, datetime from_date)
{
   if(!HistorySelect(from_date, TimeCurrent())) return;

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;
      if((int)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != magic) continue;
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(deal_ticket, DEAL_SWAP)   +
                      HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

      RegisterTradeResult(m, profit);
   }
}

//+------------------------------------------------------------------+
//| Generar resumen de performance en texto                          |
//+------------------------------------------------------------------+
string FormatPerformanceSummary(const PerformanceMetrics &m, string symbol)
{
   return StringFormat(
      "%s | Trades:%d | WR:%.1f%% | PF:%.2f | DD:%.1f%% | "
      "Sharpe:%.2f | Sortino:%.2f | Exp:$%.2f | PnL:$%.2f",
      symbol,
      m.total_trades,
      m.win_rate_pct,
      m.profit_factor,
      m.max_drawdown_pct,
      m.sharpe_ratio,
      m.sortino_ratio,
      m.expectancy,
      m.total_profit
   );
}

#endif // MH7_PERFORMANCE_MQH
