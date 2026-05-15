#ifndef MM7_FILTERS_NEWSFILTER_MQH
#define MM7_FILTERS_NEWSFILTER_MQH

//+------------------------------------------------------------------+
//|                                                 NewsFilter.mqh  |
//|          MoneyMachine7 — News Event Filter                       |
//|   Note: In Strategy Tester, news data not available → always OK  |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CNewsFilter
{
private:
   bool  m_enabled;
   int   m_minsBefore;
   int   m_minsAfter;

   struct NewsEvent
   {
      datetime time;
      string   currency;
      int      impact;
   };

   NewsEvent m_events[];
   int       m_eventCount;

public:
   CNewsFilter() : m_enabled(true), m_minsBefore(30), m_minsAfter(30), m_eventCount(0) {}

   bool Initialize(bool enabled, int minsBefore, int minsAfter)
   {
      m_enabled    = enabled;
      m_minsBefore = minsBefore;
      m_minsAfter  = minsAfter;
      ArrayResize(m_events, 50);
      return true;
   }

   //--- In Strategy Tester or when no news data is available, always return true
   bool IsTradingAllowed()
   {
      if(!m_enabled) return true;
      // In backtesting/tester environment, news is not applicable
      if(MQLInfoInteger(MQL_TESTER)) return true;

      datetime now = TimeCurrent();
      for(int i = 0; i < m_eventCount; i++)
      {
         if(m_events[i].impact < 3) continue; // only high-impact (3)
         datetime before = m_events[i].time - m_minsBefore * 60;
         datetime after  = m_events[i].time + m_minsAfter  * 60;
         if(now >= before && now <= after) return false;
      }
      return true;
   }

   void Update() { /* News update would fetch calendar in live mode */ }
};


#endif // MM7_FILTERS_NEWSFILTER_MQH
