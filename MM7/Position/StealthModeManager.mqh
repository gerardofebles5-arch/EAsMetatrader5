#ifndef MM7_POSITION_STEALTHMODEMANAGER_MQH
#define MM7_POSITION_STEALTHMODEMANAGER_MQH

//+------------------------------------------------------------------+
//|                                          StealthModeManager.mqh |
//|   MoneyMachine7 — Stealth TP/SL (virtual, tick-level monitor)    |
//|   MachinePRO EXACT: broker sees tp=0, sl=0 on ALL positions      |
//|   Avg trade duration ~40s due to tick-level TP/SL monitoring     |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"
#include "MM7/Position/PositionTracker.mqh"
#include "MM7/Position/OrderExecutor.mqh"

class CStealthModeManager
{
private:
   CPositionTracker* m_tracker;
   COrderExecutor*   m_executor;
   bool              m_enabled;

   struct StealthData
   {
      ulong    ticket;
      double   virtualTP;
      double   virtualSL;
      bool     active;
   };

   StealthData m_stealthMap[];
   int         m_mapCount;

public:
   CStealthModeManager() : m_tracker(NULL), m_executor(NULL),
                            m_enabled(true), m_mapCount(0)
   {
      ArrayResize(m_stealthMap, 500);
   }

   void Init(CPositionTracker* tracker, COrderExecutor* executor,
             bool enabled, void* unused)
   {
      m_tracker  = tracker;
      m_executor = executor;
      m_enabled  = enabled;
   }

   //--- Register virtual TP/SL for a newly opened position
   void RegisterPosition(ulong ticket, double vTP, double vSL)
   {
      if(!m_enabled) return;

      // Check if already registered
      for(int i = 0; i < m_mapCount; i++)
         if(m_stealthMap[i].ticket == ticket) { 
            m_stealthMap[i].virtualTP = vTP; 
            m_stealthMap[i].virtualSL = vSL;
            m_stealthMap[i].active    = true;
            return; 
         }

      if(m_mapCount >= ArraySize(m_stealthMap))
         ArrayResize(m_stealthMap, m_mapCount + 100);

      m_stealthMap[m_mapCount].ticket    = ticket;
      m_stealthMap[m_mapCount].virtualTP = vTP;
      m_stealthMap[m_mapCount].virtualSL = vSL;
      m_stealthMap[m_mapCount].active    = true;
      m_mapCount++;

      // Also update tracker
      if(m_tracker != NULL)
         m_tracker.SetVirtualTPSL(ticket, vTP, vSL);
   }

   //--- Called every tick — checks all open positions against virtual levels
   //--- This is what produces the ~40 second average duration
   void ManageStealthMode()
   {
      if(!m_enabled || m_executor == NULL) return;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      for(int i = 0; i < m_mapCount; i++)
      {
         if(!m_stealthMap[i].active) continue;

         ulong ticket = m_stealthMap[i].ticket;
         if(!PositionSelectByTicket(ticket))
         {
            m_stealthMap[i].active = false; // position already closed
            continue;
         }

         int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         double currentPrice = (dir == 1) ? bid : ask;

         bool hitTP = false;
         bool hitSL = false;

         if(dir == 1)  // BUY
         {
            hitTP = (m_stealthMap[i].virtualTP > 0 && currentPrice >= m_stealthMap[i].virtualTP);
            hitSL = (m_stealthMap[i].virtualSL > 0 && currentPrice <= m_stealthMap[i].virtualSL);
         }
         else           // SELL
         {
            hitTP = (m_stealthMap[i].virtualTP > 0 && currentPrice <= m_stealthMap[i].virtualTP);
            hitSL = (m_stealthMap[i].virtualSL > 0 && currentPrice >= m_stealthMap[i].virtualSL);
         }

         if(hitTP || hitSL)
         {
            string reason = hitTP ? "vTP" : "vSL";
            if(m_executor.ClosePosition(ticket))
            {
               m_stealthMap[i].active = false;
               // Duration is time from open to close (tick-level) → avg 40s
            }
         }
      }
   }

   //--- Get virtual TP/SL for a ticket
   bool GetVirtualLevels(ulong ticket, double &vTP, double &vSL)
   {
      for(int i = 0; i < m_mapCount; i++)
         if(m_stealthMap[i].ticket == ticket)
         {
            vTP = m_stealthMap[i].virtualTP;
            vSL = m_stealthMap[i].virtualSL;
            return true;
         }
      return false;
   }

   //--- Update virtual SL (for trailing stop)
   void UpdateVirtualSL(ulong ticket, double newSL)
   {
      for(int i = 0; i < m_mapCount; i++)
         if(m_stealthMap[i].ticket == ticket)
         {
            m_stealthMap[i].virtualSL = newSL;
            if(m_tracker != NULL)
            {
               double vTP = m_stealthMap[i].virtualTP;
               m_tracker.SetVirtualTPSL(ticket, vTP, newSL);
            }
            return;
         }
   }

   bool IsEnabled() const { return m_enabled; }
};


#endif // MM7_POSITION_STEALTHMODEMANAGER_MQH
