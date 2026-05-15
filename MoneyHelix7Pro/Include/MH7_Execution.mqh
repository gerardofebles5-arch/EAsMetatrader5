//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Ejecucion de Trades                        |
//|  MH7_Execution.mqh  v1.0 FINAL                                 |
//|  Lot sizing Kelly, SL/TP ATR-based, envio MT5                  |
//|  Refs: Vince (Kelly), Wilder (ATR), Chan (HFT)                |
//+------------------------------------------------------------------+
#ifndef MH7_EXECUTION_MQH
#define MH7_EXECUTION_MQH
#include "MH7_Structures.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Calcular ATR en pips para el simbolo                             |
//+------------------------------------------------------------------+
double GetATR_Pips(string symbol, int h_atr)
{
   if(h_atr == INVALID_HANDLE) return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   double atr_pips = 0.0;
   if(CopyBuffer(h_atr, 0, 0, 3, buf) >= 1)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point > 0) atr_pips = buf[0] / point;
   }
   return atr_pips;
}

//+------------------------------------------------------------------+
//| Calcular nivel de SL y TP dinamicos basados en ATR              |
//|  Ref: J. Welles Wilder - ATR; Vince - Risk Management          |
//+------------------------------------------------------------------+
SLTPLevels CalculateSLTP(string symbol,
                          int direction,
                          double entry_price,
                          const SymbolConfig &cfg)
{
   SLTPLevels lv;
   lv.is_valid = false;

   double atr_pips = GetATR_Pips(symbol, cfg.h_atr_exec);
   if(atr_pips <= 0) return lv;

   double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double sl_pips = atr_pips * cfg.atr_sl_multiplier;
   double tp_pips = sl_pips  * cfg.tp_ratio_to_sl;

   if(direction == +1)   // BUY
   {
      lv.stop_loss  = entry_price - sl_pips * point;
      lv.take_profit= entry_price + tp_pips * point;
   }
   else                  // SELL
   {
      lv.stop_loss  = entry_price + sl_pips * point;
      lv.take_profit= entry_price - tp_pips * point;
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   lv.stop_loss         = NormalizeDouble(lv.stop_loss,  digits);
   lv.take_profit       = NormalizeDouble(lv.take_profit, digits);
   lv.sl_distance_pips  = sl_pips;
   lv.tp_distance_pips  = tp_pips;
   lv.risk_reward_ratio = (sl_pips > 0) ? tp_pips / sl_pips : 0.0;

   // RR minimo 1.5
   lv.is_valid = (lv.risk_reward_ratio >= 1.5);
   return lv;
}

//+------------------------------------------------------------------+
//| Calcular lot size por Kelly Criterion (Vince)                   |
//|  Risk $ = Balance x Risk% | Lots = Risk$ / (SL_pips x pip_val) |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol,
                        double sl_pips,
                        const SymbolConfig &cfg,
                        double dd_adjustment = 1.0)
{
   if(sl_pips <= 0) return 0.0;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_usd = balance * (cfg.risk_percent / 100.0) * dd_adjustment;

   // Valor monetario de 1 pip para 1 lote
   // Metodo robusto: usar tick_value y tick_size del broker
   double tick_val      = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point         = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if(tick_val <= 0 || tick_size <= 0 || point <= 0) return 0.0;

   // pip_value = valor monetario de 1 pip para 1 lote
   double pip_value = tick_val * (point / tick_size);

   // Fallback si pip_value es irreal (broker en modo pips)
   if(pip_value < 0.01 && contract_size > 0)
      pip_value = contract_size * point;

   if(pip_value <= 0) return 0.0;

   // Lotes = riesgo_usd / (sl_pips * pip_value_por_lote)
   double raw_lots = risk_usd / (sl_pips * pip_value);

   double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = MathMin(cfg.max_lot_size, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX));
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(lot_step <= 0) lot_step = 0.01;

   double lots = MathFloor(raw_lots / lot_step) * lot_step;
   lots = MathMax(min_lot, MathMin(max_lot, lots));

   PrintFormat("LotCalc %s: bal=%.0f risk=%.0f sl=%.1fp pip_val=%.4f raw=%.2f → %.2f lots",
               symbol, balance, risk_usd, sl_pips, pip_value, raw_lots, lots);

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Verificar si ya existe posicion abierta del magic number        |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Enviar orden de mercado (BUY o SELL)                            |
//+------------------------------------------------------------------+
bool SendMarketOrder(string symbol,
                     int direction,
                     double lots,
                     double sl,
                     double tp,
                     int magic,
                     string comment,
                     ulong &out_ticket)
{
   CTrade trade;
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   bool result = false;
   if(direction == +1)
      result = trade.Buy(lots, symbol, 0, sl, tp, comment);
   else
      result = trade.Sell(lots, symbol, 0, sl, tp, comment);

   if(result)
   {
      out_ticket = trade.ResultOrder();
      PrintFormat("ORDER SENT: %s %s %.2f lots | SL=%.5f TP=%.5f | Ticket=%I64u",
                  (direction == 1 ? "BUY" : "SELL"), symbol, lots, sl, tp, out_ticket);
   }
   else
   {
      PrintFormat("ORDER FAILED: %s %s | Error=%d Ret=%d",
                  (direction == 1 ? "BUY" : "SELL"), symbol,
                  GetLastError(), trade.ResultRetcode());
   }
   return result;
}

//+------------------------------------------------------------------+
//| Ejecutar trade completo: validar, calcular, enviar              |
//+------------------------------------------------------------------+
bool ExecuteTrade(string symbol,
                  int direction,
                  const SymbolConfig &cfg,
                  double dd_adjustment,
                  PositionState &pos)
{
   // Verificar que no haya posicion abierta para este magic
   if(HasOpenPosition(symbol, cfg.magic_number))
   {
      return false;
   }

   // Precio de entrada
   double entry = (direction == +1) ?
                  SymbolInfoDouble(symbol, SYMBOL_ASK) :
                  SymbolInfoDouble(symbol, SYMBOL_BID);
   if(entry <= 0) return false;

   // Calcular SL/TP
   SLTPLevels lv = CalculateSLTP(symbol, direction, entry, cfg);
   if(!lv.is_valid)
   {
      PrintFormat("%s: Invalid SLTP (RR=%.2f) → SKIP", symbol, lv.risk_reward_ratio);
      return false;
   }

   // Calcular lotes
   double lots = CalculateLotSize(symbol, lv.sl_distance_pips, cfg, dd_adjustment);
   if(lots <= 0)
   {
      PrintFormat("%s: Lot size zero → SKIP", symbol);
      return false;
   }

   // Enviar orden
   ulong ticket = 0;
   string comment = StringFormat("MH7|%s|Q%.0f", symbol, 0.0);
   bool ok = SendMarketOrder(symbol, direction, lots, lv.stop_loss, lv.take_profit,
                              cfg.magic_number, comment, ticket);
   if(!ok) return false;

   // Actualizar estado de posicion
   pos.is_open                   = true;
   pos.direction                 = direction;
   pos.entry_price               = entry;
   pos.current_stop_loss         = lv.stop_loss;
   pos.take_profit               = lv.take_profit;
   pos.lot_size                  = lots;
   pos.open_time                 = TimeCurrent();
   pos.ticket                    = ticket;
   pos.sl_pips                   = lv.sl_distance_pips;
   pos.tp_pips                   = lv.tp_distance_pips;
   pos.partial_close_executed    = false;
   pos.trailing_stop_active      = false;
   pos.breakeven_moved           = false;
   pos.time_trail_done           = false;
   pos.divergence_exit_triggered = false;
   pos.partial_exit_pct          = 40.0;   // Cierre parcial al 40% del TP
   pos.trailing_activation_pct   = 20.0;   // Trailing al 20% ganancia
   pos.breakeven_buffer_pips     = 2.0;

   return true;
}

//+------------------------------------------------------------------+
//| Cerrar posicion completa por ticket                             |
//+------------------------------------------------------------------+
bool ClosePosition(string symbol, int magic, string reason = "")
{
   CTrade trade;
   trade.SetExpertMagicNumber(magic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         if(trade.PositionClose(ticket))
         {
            PrintFormat("CLOSED: %s | Ticket=%I64u | Reason=%s", symbol, ticket, reason);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cierre parcial de posicion (50% del volumen)                    |
//+------------------------------------------------------------------+
bool PartialClosePosition(string symbol, int magic, double close_ratio = 0.5)
{
   CTrade trade;
   trade.SetExpertMagicNumber(magic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         double volume     = PositionGetDouble(POSITION_VOLUME);
         double close_vol  = NormalizeDouble(volume * close_ratio, 2);
         double min_vol    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

         if(close_vol < min_vol) close_vol = min_vol;
         if(close_vol >= volume) return ClosePosition(symbol, magic, "Full close (partial)");

         if(trade.PositionClosePartial(ticket, close_vol))
         {
            PrintFormat("PARTIAL CLOSE: %s %.2f lots | Ticket=%I64u", symbol, close_vol, ticket);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Modificar Stop Loss de posicion abierta                         |
//+------------------------------------------------------------------+
bool ModifyPositionSL(string symbol, int magic, double new_sl)
{
   CTrade trade;
   trade.SetExpertMagicNumber(magic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         double tp = PositionGetDouble(POSITION_TP);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         new_sl = NormalizeDouble(new_sl, digits);
         return trade.PositionModify(ticket, new_sl, tp);
      }
   }
   return false;
}

#endif // MH7_EXECUTION_MQH
