#ifndef MM7_MARKET_PRICEACTIONANALYZER_MQH
#define MM7_MARKET_PRICEACTIONANALYZER_MQH

//+------------------------------------------------------------------+
//|                                        PriceActionAnalyzer.mqh  |
//|             MoneyMachine7 — Price Action Analysis                |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CPriceActionAnalyzer
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

public:
   CPriceActionAnalyzer() {}

   bool Initialize(string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_tf     = tf;
      return true;
   }

   //--- Calculate Average Daily Range over N days
   double GetADR(int days = 1)
   {
      if(days < 1) days = 1;
      double totalRange = 0;
      int bars = iBars(m_symbol, PERIOD_D1);
      if(bars < days + 1) return 10.0; // fallback

      for(int i = 1; i <= days; i++)
      {
         double h = iHigh(m_symbol, PERIOD_D1, i);
         double l = iLow(m_symbol,  PERIOD_D1, i);
         totalRange += (h - l);
      }
      return totalRange / days;
   }

   //--- Get current bid/ask spread in points
   double GetSpreadPoints()
   {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pt  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(pt <= 0) return 0;
      return (ask - bid) / pt;
   }

   //--- Check if current volume > MA of volume (volume confirmation)
   bool IsVolumeAboveMA(int maPeriod = 10)
   {
      long volBuf[];
      ArraySetAsSeries(volBuf, true);
      if(CopyTickVolume(m_symbol, m_tf, 0, maPeriod + 2, volBuf) < maPeriod + 1)
         return false;
      long current = volBuf[1]; // confirmed bar
      long sum = 0;
      for(int i = 1; i <= maPeriod; i++) sum += volBuf[i];
      double ma = (double)sum / maPeriod;
      return (current > ma * 1.1);
   }
};


#endif // MM7_MARKET_PRICEACTIONANALYZER_MQH
