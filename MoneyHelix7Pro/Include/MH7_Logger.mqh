//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Sistema de Logging y Alertas               |
//|  MH7_Logger.mqh  v1.0 FINAL                                    |
//|  CSV de trades + alertas por Telegram/Email                    |
//+------------------------------------------------------------------+
#ifndef MH7_LOGGER_MQH
#define MH7_LOGGER_MQH
#include "MH7_Structures.mqh"

// Configuracion de Telegram (rellenar con tu bot token y chat ID)
// Nota: estos valores se sobreescriben desde los inputs del EA principal
string TelegramToken  = "";         // Bot Token de Telegram
string TelegramChatID = "";         // Chat ID de Telegram
bool   EnableTelegram = false;      // Activar alertas Telegram
bool   EnableCSVLog   = true;       // Activar log CSV
bool   EnablePrintLog = true;       // Activar Print() en consola

string g_log_file_path = "";

//+------------------------------------------------------------------+
//| Inicializar logger (abrir/crear CSV)                             |
//+------------------------------------------------------------------+
void InitLogger(string ea_name)
{
   g_log_file_path = ea_name + "_trades_" +
                     TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   StringReplace(g_log_file_path, ":", "-");
   StringReplace(g_log_file_path, " ", "_");

   if(!EnableCSVLog) return;

   int fh = FileOpen(g_log_file_path, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return;

   // Encabezados del CSV
   FileWrite(fh,
             "Timestamp", "Symbol", "Magic", "Direction", "Lots",
             "Entry", "SL", "TP", "SL_pips", "TP_pips", "RR",
             "Exit_Price", "Profit_USD", "Profit_Pips",
             "Exit_Reason", "Duration_mins",
             "WR%", "PF", "Total_PnL", "DD%", "Sharpe",
             "ValueScore", "MomScore", "MLScore", "Quality", "Votes");
   FileClose(fh);

   if(EnablePrintLog) Print("Logger initialized: ", g_log_file_path);
}

//+------------------------------------------------------------------+
//| Registrar apertura de trade en CSV                               |
//+------------------------------------------------------------------+
void LogTradeOpen(const SymbolConfig &cfg,
                   const PositionState &pos,
                   const SignalState &sig)
{
   if(!EnableCSVLog) return;

   int fh = FileOpen(g_log_file_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);

   FileWrite(fh,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             cfg.symbol_name,
             cfg.magic_number,
             (pos.direction == +1 ? "BUY" : "SELL"),
             pos.lot_size,
             pos.entry_price,
             pos.current_stop_loss,
             pos.take_profit,
             pos.sl_pips,
             pos.tp_pips,
             NormalizeDouble(pos.tp_pips / MathMax(pos.sl_pips, 0.001), 2),
             "", "", "", "OPEN", "",
             "", "", "", "", "",
             sig.value_score,
             sig.momentum_score,
             sig.ml_score,
             sig.final_quality,
             sig.buy_votes + sig.sell_votes);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Registrar cierre de trade en CSV                                 |
//+------------------------------------------------------------------+
void LogTradeClose(const SymbolConfig &cfg,
                    const PositionState &pos,
                    const PerformanceMetrics &m,
                    const SignalState &sig,
                    double exit_price,
                    double profit_usd,
                    string exit_reason)
{
   if(!EnableCSVLog) return;

   double point = SymbolInfoDouble(cfg.symbol_name, SYMBOL_POINT);
   double profit_pips = (point > 0) ?
      ((pos.direction == +1) ? (exit_price - pos.entry_price) :
                                (pos.entry_price - exit_price)) / point : 0.0;

   int duration_mins = (int)((TimeCurrent() - pos.open_time) / 60);

   int fh = FileOpen(g_log_file_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);

   FileWrite(fh,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             cfg.symbol_name,
             cfg.magic_number,
             (pos.direction == +1 ? "BUY" : "SELL"),
             pos.lot_size,
             pos.entry_price,
             pos.current_stop_loss,
             pos.take_profit,
             pos.sl_pips,
             pos.tp_pips,
             NormalizeDouble(pos.tp_pips / MathMax(pos.sl_pips, 0.001), 2),
             exit_price,
             NormalizeDouble(profit_usd, 2),
             NormalizeDouble(profit_pips, 1),
             exit_reason,
             duration_mins,
             NormalizeDouble(m.win_rate_pct, 1),
             NormalizeDouble(m.profit_factor, 2),
             NormalizeDouble(m.total_profit, 2),
             NormalizeDouble(m.max_drawdown_pct, 1),
             NormalizeDouble(m.sharpe_ratio, 2),
             sig.value_score,
             sig.momentum_score,
             sig.ml_score,
             sig.final_quality,
             sig.buy_votes + sig.sell_votes);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Enviar alerta por Telegram (requiere WebRequest habilitado)     |
//+------------------------------------------------------------------+
void SendTelegramAlert(string message)
{
   if(!EnableTelegram || TelegramToken == "" || TelegramChatID == "") return;

   string url = StringFormat(
      "https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",
      TelegramToken, TelegramChatID,
      StringReplace(message, " ", "%20"));

   char   post_data[];
   char   result_data[];
   string result_headers;

   int res = WebRequest("GET", url, "", 5000, post_data, result_data, result_headers);
   if(res == -1 && EnablePrintLog)
      PrintFormat("Telegram: WebRequest error %d (check 'Allow WebRequests')", GetLastError());
}

//+------------------------------------------------------------------+
//| Alerta de trade abierto                                          |
//+------------------------------------------------------------------+
void AlertTradeOpen(string symbol, int direction, double lots,
                    double entry, double sl, double tp, double quality)
{
   string msg = StringFormat(
      "MH7 OPEN | %s %s | %.2f lots | Entry=%.5f | SL=%.5f | TP=%.5f | Q=%.1f",
      symbol, (direction == +1 ? "BUY" : "SELL"),
      lots, entry, sl, tp, quality);

   if(EnablePrintLog) Print(msg);
   SendTelegramAlert(msg);
}

//+------------------------------------------------------------------+
//| Alerta de trade cerrado                                          |
//+------------------------------------------------------------------+
void AlertTradeClose(string symbol, double profit, string reason,
                     double win_rate, double total_pnl)
{
   string emoji = profit >= 0 ? "[WIN]" : "[LOSS]";
   string msg   = StringFormat(
      "MH7 CLOSE %s | %s | P&L=$%.2f | WR=%.1f%% | Total=$%.2f | %s",
      emoji, symbol, profit, win_rate, total_pnl, reason);

   if(EnablePrintLog) Print(msg);
   SendTelegramAlert(msg);
}

//+------------------------------------------------------------------+
//| Alerta de circuit breaker                                        |
//+------------------------------------------------------------------+
void AlertCircuitBreaker(double dd_pct, string reason)
{
   string msg = StringFormat(
      "!!! MH7 CIRCUIT BREAKER !!! DD=%.1f%% | %s | TRADING STOPPED 24H",
      dd_pct, reason);

   Print(msg);
   Alert(msg);
   SendTelegramAlert(msg);
}

//+------------------------------------------------------------------+
//| Reporte diario de performance                                    |
//+------------------------------------------------------------------+
void SendDailyReport(const SymbolConfig &cfg[],
                      const PerformanceMetrics &metrics[],
                      int n)
{
   double total_pnl = 0;
   int    total_tr  = 0;
   double best_wr   = 0;

   for(int i = 0; i < n; i++)
   {
      total_pnl += metrics[i].total_profit;
      total_tr  += metrics[i].total_trades;
      if(metrics[i].win_rate_pct > best_wr) best_wr = metrics[i].win_rate_pct;
   }

   string msg = StringFormat(
      "MH7 DAILY REPORT | %s | Total PnL=$%.2f | Trades=%d | Best WR=%.1f%%",
      TimeToString(TimeCurrent(), TIME_DATE), total_pnl, total_tr, best_wr);

   Print(msg);
   SendTelegramAlert(msg);
}

#endif // MH7_LOGGER_MQH
