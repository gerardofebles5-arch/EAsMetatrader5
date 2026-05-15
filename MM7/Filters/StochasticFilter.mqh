#ifndef MM7_FILTERS_STOCHASTICFILTER_MQH
#define MM7_FILTERS_STOCHASTICFILTER_MQH

//+------------------------------------------------------------------+
//|                                           StochasticFilter.mqh  |
//|      MoneyMachine7 — Stochastic Direction Filter                 |
//|   Buy signal: Stoch K < 30 (oversold)                            |
//|   Sell signal: Stoch K > 70 (overbought)                         |
//+------------------------------------------------------------------+


class CStochasticFilter
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   bool            m_enabled;
   double          m_buyLevel;   // 30
   double          m_sellLevel;  // 70
   int             m_hStoch;
   double          m_stochK;
   double          m_stochD;

public:
   CStochasticFilter() : m_enabled(true), m_buyLevel(30.0), m_sellLevel(70.0),
                          m_hStoch(INVALID_HANDLE), m_stochK(50), m_stochD(50) {}

   ~CStochasticFilter()
   {
      if(m_hStoch != INVALID_HANDLE) IndicatorRelease(m_hStoch);
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES tf, bool enabled,
                   double buyLevel, double sellLevel,
                   int kPeriod, int dPeriod, int slowing)
   {
      m_symbol    = symbol;
      m_tf        = tf;
      m_enabled   = enabled;
      m_buyLevel  = buyLevel;
      m_sellLevel = sellLevel;

      if(m_enabled)
      {
         m_hStoch = iStochastic(symbol, tf, kPeriod, dPeriod, slowing, MODE_SMA, STO_LOWHIGH);
         if(m_hStoch == INVALID_HANDLE) { Print("StochFilter: handle failed"); return false; }
      }
      return true;
   }

   void Update()
   {
      if(!m_enabled || m_hStoch == INVALID_HANDLE) return;
      double kBuf[], dBuf[];
      ArraySetAsSeries(kBuf, true);
      ArraySetAsSeries(dBuf, true);
      if(CopyBuffer(m_hStoch, 0, 1, 1, kBuf) > 0 &&
         CopyBuffer(m_hStoch, 1, 1, 1, dBuf) > 0)
      {
         m_stochK = kBuf[0];
         m_stochD = dBuf[0];
      }
   }

   //--- Stochastic acts as DIRECTION filter (not frequency filter)
   bool AllowBuy()
   {
      if(!m_enabled) return true;
      Update();
      return (m_stochK <= m_buyLevel);
   }

   bool AllowSell()
   {
      if(!m_enabled) return true;
      Update();
      return (m_stochK >= m_sellLevel);
   }

   double GetStochK() const { return m_stochK; }
   double GetStochD() const { return m_stochD; }
};


#endif // MM7_FILTERS_STOCHASTICFILTER_MQH
