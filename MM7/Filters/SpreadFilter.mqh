#ifndef MM7_FILTERS_SPREADFILTER_MQH
#define MM7_FILTERS_SPREADFILTER_MQH

//+------------------------------------------------------------------+
//|                                                SpreadFilter.mqh |
//|              MoneyMachine7 — Spread Filter                       |
//+------------------------------------------------------------------+


class CSpreadFilter
{
private:
   string m_symbol;
   int    m_maxSpreadPts;  // InpMaxSpreadPoints = 10000 (effectively OFF)

public:
   CSpreadFilter() : m_maxSpreadPts(10000) {}

   bool Initialize(string symbol, int maxSpreadPoints)
   {
      m_symbol       = symbol;
      m_maxSpreadPts = maxSpreadPoints;
      return true;
   }

   bool IsTradingAllowed()
   {
      if(m_maxSpreadPts <= 0 || m_maxSpreadPts >= 9999) return true;

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double pt  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(pt <= 0) return true;

      double spreadPts = (ask - bid) / pt;
      return (spreadPts <= m_maxSpreadPts);
   }
};


#endif // MM7_FILTERS_SPREADFILTER_MQH
