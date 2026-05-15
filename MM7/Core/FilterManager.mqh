#ifndef MM7_CORE_FILTERMANAGER_MQH
#define MM7_CORE_FILTERMANAGER_MQH

//+------------------------------------------------------------------+
//|                                               FilterManager.mqh |
//|          MoneyMachine7 — Filter Aggregator                       |
//+------------------------------------------------------------------+

#include "MM7/Filters/TrendFilter.mqh"
#include "MM7/Filters/NewsFilter.mqh"
#include "MM7/Filters/SpreadFilter.mqh"
#include "MM7/Filters/ScheduleFilter.mqh"
#include "MM7/Filters/StochasticFilter.mqh"

class CFilterManager
{
private:
   CTrendFilter*      m_trend;
   CNewsFilter*       m_news;
   CSpreadFilter*     m_spread;
   CScheduleFilter*   m_schedule;
   CStochasticFilter* m_stoch;

public:
   CFilterManager() : m_trend(NULL), m_news(NULL), m_spread(NULL),
                      m_schedule(NULL), m_stoch(NULL) {}

   bool Initialize(CTrendFilter* trend, CNewsFilter* news, CSpreadFilter* spread,
                   CScheduleFilter* schedule, CStochasticFilter* stoch)
   {
      m_trend    = trend;
      m_news     = news;
      m_spread   = spread;
      m_schedule = schedule;
      m_stoch    = stoch;
      return true;
   }

   void UpdateFilters()
   {
      if(m_trend)    m_trend.Update();
      if(m_news)     m_news.Update();
      if(m_stoch)    m_stoch.Update();
   }

   bool IsGlobalTradingAllowed()
   {
      if(m_news     && !m_news.IsTradingAllowed())     return false;
      if(m_spread   && !m_spread.IsTradingAllowed())   return false;
      if(m_schedule && !m_schedule.IsTradingAllowed()) return false;
      return true;
   }

   bool AllowBuy()
   {
      if(!IsGlobalTradingAllowed()) return false;
      if(m_trend  && !m_trend.IsBullishTrend())  return false;
      if(m_stoch  && !m_stoch.AllowBuy())        return false;
      return true;
   }

   bool AllowSell()
   {
      if(!IsGlobalTradingAllowed()) return false;
      if(m_trend  && !m_trend.IsBearishTrend())  return false;
      if(m_stoch  && !m_stoch.AllowSell())        return false;
      return true;
   }

   CTrendFilter*      GetTrendFilter()    { return m_trend; }
   CStochasticFilter* GetStochFilter()    { return m_stoch; }
   CNewsFilter*       GetNewsFilter()     { return m_news; }
   CScheduleFilter*   GetScheduleFilter() { return m_schedule; }
};


#endif // MM7_CORE_FILTERMANAGER_MQH
