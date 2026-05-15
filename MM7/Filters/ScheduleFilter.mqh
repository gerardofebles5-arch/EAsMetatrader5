#ifndef MM7_FILTERS_SCHEDULEFILTER_MQH
#define MM7_FILTERS_SCHEDULEFILTER_MQH

//+------------------------------------------------------------------+
//|                                              ScheduleFilter.mqh |
//|          MoneyMachine7 — Trading Schedule Filter                 |
//|   Mon-Thu: 05:00-21:00 | Fri: 05:00-18:00 | Sat/Sun: OFF        |
//+------------------------------------------------------------------+


struct DaySchedule
{
   bool  enabled;
   int   startHour;
   int   endHour;
};

class CScheduleFilter
{
private:
   DaySchedule m_schedule[7]; // 0=Sun, 1=Mon, ... 6=Sat

public:
   CScheduleFilter() {}

   bool Initialize()
   {
      // Default: all OFF
      for(int i = 0; i < 7; i++)
      {
         m_schedule[i].enabled   = false;
         m_schedule[i].startHour = 0;
         m_schedule[i].endHour   = 0;
      }
      return true;
   }

   void SetDaySchedule(int dayOfWeek, bool enabled, int startHour, int endHour)
   {
      if(dayOfWeek < 0 || dayOfWeek > 6) return;
      m_schedule[dayOfWeek].enabled   = enabled;
      m_schedule[dayOfWeek].startHour = startHour;
      m_schedule[dayOfWeek].endHour   = endHour;
   }

   bool IsTradingAllowed()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int dow  = dt.day_of_week; // 0=Sun, 1=Mon...6=Sat
      int hour = dt.hour;

      if(!m_schedule[dow].enabled) return false;
      if(hour < m_schedule[dow].startHour) return false;
      if(hour >= m_schedule[dow].endHour)  return false;
      return true;
   }
};


#endif // MM7_FILTERS_SCHEDULEFILTER_MQH
