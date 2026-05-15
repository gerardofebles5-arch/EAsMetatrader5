#ifndef MM7_POSITION_ORDEREXECUTOR_MQH
#define MM7_POSITION_ORDEREXECUTOR_MQH

//+------------------------------------------------------------------+
//|                                              OrderExecutor.mqh   |
//|              MoneyMachine7 — Order Execution Module              |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"
#include <Trade\Trade.mqh>

class COrderExecutor
{
private:
   CTrade   m_trade;
   int      m_magic;
   string   m_baseComment;
   int      m_slippage;

public:
   COrderExecutor(int magic, string comment, int slippage, void* unused)
   {
      m_magic       = magic;
      m_baseComment = comment;
      m_slippage    = slippage;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   }

   //--- Open market order (stealth: tp=0, sl=0)
   ulong OpenOrder(ENUM_ORDER_TYPE type, double lot, double price,
                   double sl, double tp, string comment)
   {
      double normLot = NormalizeLot(lot);
      if(normLot <= 0) return 0;

      bool result = false;
      if(type == ORDER_TYPE_BUY)
         result = m_trade.Buy(normLot, _Symbol, 0, sl, tp, comment);
      else
         result = m_trade.Sell(normLot, _Symbol, 0, sl, tp, comment);

      if(!result)
      {
         Print("OrderExecutor ERROR: ", m_trade.ResultRetcodeDescription(),
               " code=", m_trade.ResultRetcode(),
               " lot=", normLot, " type=", EnumToString(type));
         return 0;
      }
      return m_trade.ResultOrder();
   }

   //--- Close specific position by ticket
   bool ClosePosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      return m_trade.PositionClose(ticket, m_slippage);
   }

   //--- Modify SL/TP on a real position (for non-stealth fallback)
   bool ModifyPosition(ulong ticket, double sl, double tp)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      return m_trade.PositionModify(ticket, sl, tp);
   }

   int GetMagic() const { return m_magic; }

private:
   double NormalizeLot(double lot)
   {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      lot = MathFloor(lot / step) * step;
      lot = MathMax(lot, minL);
      lot = MathMin(lot, maxL);
      return NormalizeDouble(lot, 2);
   }
};


#endif // MM7_POSITION_ORDEREXECUTOR_MQH
