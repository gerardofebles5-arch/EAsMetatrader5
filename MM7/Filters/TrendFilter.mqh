#ifndef MM7_FILTERS_TRENDFILTER_MQH
#define MM7_FILTERS_TRENDFILTER_MQH

//+------------------------------------------------------------------+
//|                                                TrendFilter.mqh  |
//|            MoneyMachine7 — MA(200) Trend Direction Filter        |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CTrendFilter
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   bool            m_enabled;
   int             m_maPeriod;
   int             m_hMA;
   double          m_maValue;

public:
   CTrendFilter() : m_enabled(true), m_maPeriod(200),
                    m_hMA(INVALID_HANDLE), m_maValue(0) {}

   ~CTrendFilter()
   {
      if(m_hMA != INVALID_HANDLE) IndicatorRelease(m_hMA);
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES tf, bool enabled, int maPeriod)
   {
      m_symbol   = symbol;
      m_tf       = tf;
      m_enabled  = enabled;
      m_maPeriod = maPeriod;

      if(m_enabled)
      {
         m_hMA = iMA(symbol, tf, maPeriod, 0, MODE_SMA, PRICE_CLOSE);
         if(m_hMA == INVALID_HANDLE) { Print("TrendFilter: MA handle failed"); return false; }
      }
      return true;
   }

   void Update()
   {
      if(!m_enabled || m_hMA == INVALID_HANDLE) return;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_hMA, 0, 1, 1, buf) > 0)
         m_maValue = buf[0];
   }

   bool IsBullishTrend()
   {
      if(!m_enabled) return true; // no filter = allow both
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return (price > m_maValue && m_maValue > 0);
   }

   bool IsBearishTrend()
   {
      if(!m_enabled) return true;
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return (price < m_maValue && m_maValue > 0);
   }

   double GetMAValue() const { return m_maValue; }
};


#endif // MM7_FILTERS_TRENDFILTER_MQH
