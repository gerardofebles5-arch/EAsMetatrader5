#ifndef MM7_POSITION_BASKETMANAGER_MQH
#define MM7_POSITION_BASKETMANAGER_MQH

//+------------------------------------------------------------------+
//|                                              BasketManager.mqh  |
//|          MoneyMachine7 — Basket Profit/Loss Management           |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"
#include "MM7/Position/PositionTracker.mqh"
#include "MM7/Position/OrderExecutor.mqh"

class CBasketManager
{
private:
   CPositionTracker* m_tracker;
   COrderExecutor*   m_executor;
   double            m_profitTarget;   // 0 = disabled
   double            m_lossLimit;      // 0 = disabled
   int               m_magic;

public:
   CBasketManager() : m_tracker(NULL), m_executor(NULL),
                      m_profitTarget(0), m_lossLimit(0), m_magic(0) {}

   bool Initialize(CPositionTracker* tracker, COrderExecutor* executor,
                   double profitUSD, double lossUSD, int magic)
   {
      m_tracker      = tracker;
      m_executor     = executor;
      m_profitTarget = profitUSD;
      m_lossLimit    = lossUSD;
      m_magic        = magic;
      return true;
   }

   void ManageBasket()
   {
      if(m_tracker == NULL) return;
      if(m_profitTarget <= 0 && m_lossLimit <= 0) return;

      double floating = m_tracker.GetTotalFloatingProfit();

      bool closeAll = false;
      if(m_profitTarget > 0 && floating >= m_profitTarget)  closeAll = true;
      if(m_lossLimit    > 0 && floating <= -m_lossLimit)    closeAll = true;

      if(closeAll) CloseAllPositions();
   }

   void CloseAllPositions()
   {
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         m_executor.ClosePosition(ticket);
      }
   }
};


#endif // MM7_POSITION_BASKETMANAGER_MQH
