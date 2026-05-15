#ifndef MM7_POSITION_POSITIONTRACKER_MQH
#define MM7_POSITION_POSITIONTRACKER_MQH

//+------------------------------------------------------------------+
//|                                            PositionTracker.mqh  |
//|       MoneyMachine7 — Position Tracker with Virtual TP/SL        |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CPositionTracker
{
private:
   PositionInfo  m_positions[];
   int           m_count;
   int           m_magic;
   bool          m_controlUser;   // filter by magic only vs. all orders

public:
   CPositionTracker() : m_count(0), m_magic(0), m_controlUser(true) {}

   void Init(int magic, bool controlUser, void* unused)
   {
      m_magic       = magic;
      m_controlUser = controlUser;
      ArrayResize(m_positions, 500);
   }

   //--- Refresh positions from broker (called every tick)
   void UpdatePositions()
   {
      m_count = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(m_controlUser && PositionGetInteger(POSITION_MAGIC) != m_magic) continue;

         if(m_count >= ArraySize(m_positions))
            ArrayResize(m_positions, m_count + 100);

         m_positions[m_count].ticket    = ticket;
         m_positions[m_count].entryPrice= PositionGetDouble(POSITION_PRICE_OPEN);
         m_positions[m_count].lot       = PositionGetDouble(POSITION_VOLUME);
         m_positions[m_count].direction = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ? 1 : -1;
         m_positions[m_count].openTime  = (datetime)PositionGetInteger(POSITION_TIME);
         m_positions[m_count].comment   = PositionGetString(POSITION_COMMENT);

         // Preserve virtual TP/SL if already set
         bool found = false;
         for(int j = 0; j < m_count; j++)
         {
            if(m_positions[j].ticket == ticket) { found = true; break; }
         }
         if(!found)
         {
            m_positions[m_count].virtualTP = 0;
            m_positions[m_count].virtualSL = 0;
            m_positions[m_count].isG2      = (StringFind(m_positions[m_count].comment, "G2") >= 0);
         }
         m_count++;
      }
   }

   //--- Set virtual TP/SL on a tracked position
   void SetVirtualTPSL(ulong ticket, double vTP, double vSL)
   {
      for(int i = 0; i < m_count; i++)
         if(m_positions[i].ticket == ticket)
         {
            m_positions[i].virtualTP = vTP;
            m_positions[i].virtualSL = vSL;
            return;
         }
   }

   //--- Get all current positions
   void GetAllPositions(PositionInfo &out[])
   {
      ArrayResize(out, m_count);
      for(int i = 0; i < m_count; i++)
         out[i] = m_positions[i];
   }

   //--- Count buys / sells
   int CountBuys()
   {
      int cnt = 0;
      for(int i = 0; i < m_count; i++)
         if(m_positions[i].direction == 1 && !m_positions[i].isG2) cnt++;
      return cnt;
   }

   int CountSells()
   {
      int cnt = 0;
      for(int i = 0; i < m_count; i++)
         if(m_positions[i].direction == -1 && !m_positions[i].isG2) cnt++;
      return cnt;
   }

   int CountG2()
   {
      int cnt = 0;
      for(int i = 0; i < m_count; i++)
         if(m_positions[i].isG2) cnt++;
      return cnt;
   }

   int TotalOpen()    const { return m_count; }
   int GetMagic()     const { return m_magic; }

   //--- Check if a ticket is still open
   bool IsOpen(ulong ticket)
   {
      for(int i = 0; i < m_count; i++)
         if(m_positions[i].ticket == ticket) return true;
      return false;
   }

   //--- Get position data by ticket
   bool GetPosition(ulong ticket, PositionInfo &info)
   {
      for(int i = 0; i < m_count; i++)
         if(m_positions[i].ticket == ticket) { info = m_positions[i]; return true; }
      return false;
   }

   //--- Get last opened legacy position (for G2 reference)
   bool GetLastLegacyPosition(PositionInfo &info)
   {
      datetime latest = 0;
      int idx = -1;
      for(int i = 0; i < m_count; i++)
      {
         if(!m_positions[i].isG2 && m_positions[i].openTime > latest)
         {
            latest = m_positions[i].openTime;
            idx    = i;
         }
      }
      if(idx < 0) return false;
      info = m_positions[idx];
      return true;
   }

   //--- Total floating profit of all positions
   double GetTotalFloatingProfit()
   {
      double total = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong t = PositionGetTicket(i);
         if(m_controlUser && PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         total += PositionGetDouble(POSITION_PROFIT);
      }
      return total;
   }
};


#endif // MM7_POSITION_POSITIONTRACKER_MQH
