#ifndef MM7_MARKET_INDICATORCACHE_MQH
#define MM7_MARKET_INDICATORCACHE_MQH

//+------------------------------------------------------------------+
//|                                             IndicatorCache.mqh   |
//|                     MoneyMachine7 — Indicator Cache              |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CIndicatorCache
{
private:
   int      m_hATR;
   int      m_hMA;
   int      m_hRSI;
   int      m_hStoch;

   double   m_atr;
   double   m_ma;
   double   m_rsi;
   double   m_stochK;
   double   m_stochD;

   string   m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int      m_atrPeriod;
   int      m_maPeriod;
   int      m_rsiPeriod;
   int      m_stochK_period;
   int      m_stochD_period;
   int      m_stochSlowing;

public:
   CIndicatorCache() : m_hATR(INVALID_HANDLE), m_hMA(INVALID_HANDLE),
                       m_hRSI(INVALID_HANDLE), m_hStoch(INVALID_HANDLE),
                       m_atr(0.5), m_ma(0), m_rsi(50), m_stochK(50), m_stochD(50) {}

   ~CIndicatorCache()
   {
      if(m_hATR   != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hMA    != INVALID_HANDLE) IndicatorRelease(m_hMA);
      if(m_hRSI   != INVALID_HANDLE) IndicatorRelease(m_hRSI);
      if(m_hStoch != INVALID_HANDLE) IndicatorRelease(m_hStoch);
   }

   bool Initialize(string symbol, ENUM_TIMEFRAMES tf,
                   int atrPeriod, int maPeriod,
                   int rsiPeriod, int stochK, int stochD, int stochSlowing)
   {
      m_symbol       = symbol;
      m_tf           = tf;
      m_atrPeriod    = atrPeriod;
      m_maPeriod     = maPeriod;
      m_rsiPeriod    = rsiPeriod;
      m_stochK_period= stochK;
      m_stochD_period= stochD;
      m_stochSlowing = stochSlowing;

      m_hATR   = iATR(symbol, tf, atrPeriod);
      m_hMA    = iMA(symbol, tf, maPeriod, 0, MODE_SMA, PRICE_CLOSE);
      m_hRSI   = iRSI(symbol, tf, rsiPeriod, PRICE_CLOSE);
      m_hStoch = iStochastic(symbol, tf, stochK, stochD, stochSlowing, MODE_SMA, STO_LOWHIGH);

      if(m_hATR==INVALID_HANDLE || m_hMA==INVALID_HANDLE ||
         m_hRSI==INVALID_HANDLE || m_hStoch==INVALID_HANDLE)
      {
         Print("ERROR: Failed to create indicator handles. ATR=", m_hATR,
               " MA=", m_hMA, " RSI=", m_hRSI, " Stoch=", m_hStoch);
         return false;
      }
      return true;
   }

   //--- Called on every new bar (bar 0 = current forming bar for real-time ATR)
   void UpdateIndicators()
   {
      double buf[];
      ArraySetAsSeries(buf, true);

      if(m_hATR != INVALID_HANDLE)
      {
         if(CopyBuffer(m_hATR, 0, 0, 3, buf) > 0)
            m_atr = buf[0];   // bar 0 = current bar — real-time ATR ≈ 0.50 pts M1 XAUUSD
      }
      if(m_hMA != INVALID_HANDLE)
      {
         if(CopyBuffer(m_hMA, 0, 0, 3, buf) > 0)
            m_ma = buf[1];    // bar 1 = confirmed close for trend
      }
      if(m_hRSI != INVALID_HANDLE)
      {
         if(CopyBuffer(m_hRSI, 0, 0, 3, buf) > 0)
            m_rsi = buf[1];
      }
      if(m_hStoch != INVALID_HANDLE)
      {
         double kBuf[], dBuf[];
         ArraySetAsSeries(kBuf, true);
         ArraySetAsSeries(dBuf, true);
         if(CopyBuffer(m_hStoch, 0, 0, 3, kBuf) > 0 &&
            CopyBuffer(m_hStoch, 1, 0, 3, dBuf) > 0)
         {
            m_stochK = kBuf[1];
            m_stochD = dBuf[1];
         }
      }
   }

   // Getters
   double GetATR()    const { return (m_atr > 0) ? m_atr : 0.5; }
   double GetMA()     const { return m_ma; }
   double GetRSI()    const { return m_rsi; }
   double GetStochK() const { return m_stochK; }
   double GetStochD() const { return m_stochD; }
};


#endif // MM7_MARKET_INDICATORCACHE_MQH
