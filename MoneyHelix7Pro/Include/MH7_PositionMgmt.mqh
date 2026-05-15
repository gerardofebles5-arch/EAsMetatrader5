//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Gestion de Posiciones                       |
//|  MH7_PositionMgmt.mqh  TIER RESTORE                            |
//|  Trailing HWM 1.0x activacion / 1.2x distancia                |
//+------------------------------------------------------------------+
#ifndef MH7_POSITIONMGMT_MQH
#define MH7_POSITIONMGMT_MQH
#include "MH7_Structures.mqh"
#include "MH7_Execution.mqh"
#include "MH7_Engines.mqh"

double GetCurrentPrice(string symbol, int direction)
{
   return (direction == +1) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                            : SymbolInfoDouble(symbol, SYMBOL_ASK);
}

double GetUnrealizedPips(string symbol, const PositionState &pos)
{
   double current = GetCurrentPrice(symbol, pos.direction);
   double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0) return 0.0;
   double diff = (pos.direction == +1) ? (current - pos.entry_price)
                                       : (pos.entry_price - current);
   return diff / point;
}

// TRAILING STOP BASADO EN HIGH WATER MARK — parametros tier
void ManageTrailingStop(string symbol, PositionState &pos, const SymbolConfig &cfg)
{
   if(cfg.h_atr_m15 == INVALID_HANDLE) return;

   double atr_buf[];
   ArraySetAsSeries(atr_buf, true);
   if(CopyBuffer(cfg.h_atr_m15, 0, 0, 3, atr_buf) < 1) return;

   double atr   = atr_buf[0];
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(atr <= 0 || point <= 0) return;

   double current = GetCurrentPrice(symbol, pos.direction);

   if(pos.direction == +1)
   {
      if(current > pos.high_water_mark || pos.high_water_mark == 0.0)
         pos.high_water_mark = current;
   }
   else
   {
      if(current < pos.high_water_mark || pos.high_water_mark == 0.0)
         pos.high_water_mark = current;
   }

   double hwm_pips = (pos.direction == +1) ?
                     (pos.high_water_mark - pos.entry_price) / point :
                     (pos.entry_price - pos.high_water_mark) / point;

   double activation_pips = atr / point * 0.8;  // MR: activar al ganar 0.8x ATR
   double trail_pips      = atr / point * 1.2;  // MR: trailing 1.2x ATR del pico

   if(hwm_pips < activation_pips) return;

   double new_sl;
   if(pos.direction == +1)
      new_sl = pos.high_water_mark - trail_pips * point;
   else
      new_sl = pos.high_water_mark + trail_pips * point;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   new_sl = NormalizeDouble(new_sl, digits);

   bool should_move = (pos.direction == +1 && new_sl > pos.current_stop_loss + point) ||
                      (pos.direction == -1 && new_sl < pos.current_stop_loss - point);

   if(should_move)
   {
      if(ModifyPositionSL(symbol, cfg.magic_number, new_sl))
      {
         if(!pos.trailing_stop_active)
         {
            pos.trailing_stop_active = true;
            PrintFormat("%s: Trailing ON | HWM=%.5f SL→%.5f | peak=%.1f pips",
                        symbol, pos.high_water_mark, new_sl, hwm_pips);
         }
         pos.current_stop_loss = new_sl;
      }
   }
}

// SALIDA POR TIEMPO
void ManageTimeBasedExit(string symbol, PositionState &pos, const SymbolConfig &cfg,
                          int max_bars_open = 48)
{
   if(pos.time_trail_done) return;
   int bars = (int)((TimeCurrent() - pos.open_time) / (15 * 60));
   if(bars < max_bars_open) return;
   double roc = CalculateROC(symbol, cfg.momentum_bars, 0);
   if(MathAbs(roc) > 0.3) return;
   PrintFormat("%s: Time exit %d bars ROC=%.3f", symbol, bars, roc);
   ClosePosition(symbol, cfg.magic_number, "TIME");
   pos.is_open       = false;
   pos.time_trail_done = true;
}

// GESTOR PRINCIPAL
void ManageOpenPosition(string symbol, PositionState &pos, const SymbolConfig &cfg,
                        int max_bars_open = 48)
{
   if(!pos.is_open) return;
   if(!HasOpenPosition(symbol, cfg.magic_number))
   {
      pos.is_open = false;
      PrintFormat("%s: Closed by broker (TP/SL)", symbol);
      return;
   }
   ManageTrailingStop(symbol, pos, cfg);
   ManageTimeBasedExit(symbol, pos, cfg, max_bars_open);
}

bool SyncPositionState(string symbol, int magic, PositionState &pos)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         pos.is_open           = true;
         pos.ticket            = ticket;
         pos.entry_price       = PositionGetDouble(POSITION_PRICE_OPEN);
         pos.current_stop_loss = PositionGetDouble(POSITION_SL);
         pos.take_profit       = PositionGetDouble(POSITION_TP);
         pos.lot_size          = PositionGetDouble(POSITION_VOLUME);
         pos.unrealized_pnl    = PositionGetDouble(POSITION_PROFIT);
         pos.open_time         = (datetime)PositionGetInteger(POSITION_TIME);
         pos.high_water_mark   = 0.0;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         pos.direction = (pt == POSITION_TYPE_BUY) ? +1 : -1;
         return true;
      }
   }
   return false;
}

#endif // MH7_POSITIONMGMT_MQH
