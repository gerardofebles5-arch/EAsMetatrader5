#ifndef MM7_MARKET_SMCDETECTOR_MQH
#define MM7_MARKET_SMCDETECTOR_MQH

//+------------------------------------------------------------------+
//|                                               SMCDetector.mqh   |
//|          MoneyMachine7 — Smart Money Concepts Detector           |
//|    Detects: FVG, Order Blocks, BOS, CHoCH, Liquidity Sweeps      |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CSMCDetector
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int             m_fvgLookback;
   double          m_fvgMinSize;
   int             m_obLookback;
   double          m_obMinSize;
   bool            m_drawFVG;
   bool            m_drawOB;

   FVGZone         m_fvgZones[];
   OrderBlock      m_orderBlocks[];
   int             m_fvgCount;
   int             m_obCount;

   // Structure tracking
   double          m_lastSwingHigh;
   double          m_lastSwingLow;
   bool            m_bullishStructure;

public:
   CSMCDetector() : m_fvgCount(0), m_obCount(0),
                    m_lastSwingHigh(0), m_lastSwingLow(0),
                    m_bullishStructure(true) {}

   bool Initialize(string symbol, ENUM_TIMEFRAMES tf,
                   int fvgLookback, double fvgMinSize,
                   int obLookback, double obMinSize,
                   bool drawFVG, bool drawOB)
   {
      m_symbol      = symbol;
      m_tf          = tf;
      m_fvgLookback = fvgLookback;
      m_fvgMinSize  = fvgMinSize;
      m_obLookback  = obLookback;
      m_obMinSize   = obMinSize;
      m_drawFVG     = drawFVG;
      m_drawOB      = drawOB;

      ArrayResize(m_fvgZones,    100);
      ArrayResize(m_orderBlocks, 50);
      return true;
   }

   //--- Scan recent bars for FVG zones
   void ScanFVGZones()
   {
      m_fvgCount = 0;
      int limit  = MathMin(m_fvgLookback, iBars(m_symbol, m_tf) - 2);

      for(int i = 2; i < limit; i++)
      {
         double h1 = iHigh(m_symbol,  m_tf, i+1);
         double l1 = iLow(m_symbol,   m_tf, i+1);
         double h2 = iHigh(m_symbol,  m_tf, i-1);
         double l2 = iLow(m_symbol,   m_tf, i-1);
         double mid_h = iHigh(m_symbol, m_tf, i);
         double mid_l = iLow(m_symbol,  m_tf, i);

         // Bullish FVG: gap up — low of candle[i-1] > high of candle[i+1]
         if(l2 > h1 && (l2 - h1) >= m_fvgMinSize)
         {
            if(m_fvgCount < 100)
            {
               m_fvgZones[m_fvgCount].high     = l2;
               m_fvgZones[m_fvgCount].low      = h1;
               m_fvgZones[m_fvgCount].isBullish = true;
               m_fvgZones[m_fvgCount].time     = iTime(m_symbol, m_tf, i);
               m_fvgZones[m_fvgCount].filled   = false;
               m_fvgCount++;
            }
         }
         // Bearish FVG: gap down — high of candle[i-1] < low of candle[i+1]
         if(h2 < l1 && (l1 - h2) >= m_fvgMinSize)
         {
            if(m_fvgCount < 100)
            {
               m_fvgZones[m_fvgCount].high     = l1;
               m_fvgZones[m_fvgCount].low      = h2;
               m_fvgZones[m_fvgCount].isBullish = false;
               m_fvgZones[m_fvgCount].time     = iTime(m_symbol, m_tf, i);
               m_fvgZones[m_fvgCount].filled   = false;
               m_fvgCount++;
            }
         }
      }
   }

   //--- Scan for Order Blocks
   void ScanOrderBlocks()
   {
      m_obCount = 0;
      int limit = MathMin(m_obLookback, iBars(m_symbol, m_tf) - 3);

      for(int i = 3; i < limit; i++)
      {
         double close_i  = iClose(m_symbol, m_tf, i);
         double open_i   = iOpen(m_symbol,  m_tf, i);
         double close_i1 = iClose(m_symbol, m_tf, i-1);

         // Bullish OB: down candle followed by strong up move
         if(close_i < open_i && close_i1 > iHigh(m_symbol, m_tf, i))
         {
            if(m_obCount < 50)
            {
               m_orderBlocks[m_obCount].high      = iHigh(m_symbol, m_tf, i);
               m_orderBlocks[m_obCount].low       = iLow(m_symbol,  m_tf, i);
               m_orderBlocks[m_obCount].isBullish = true;
               m_orderBlocks[m_obCount].time      = iTime(m_symbol, m_tf, i);
               m_orderBlocks[m_obCount].mitigated = false;
               m_obCount++;
            }
         }
         // Bearish OB: up candle followed by strong down move
         if(close_i > open_i && close_i1 < iLow(m_symbol, m_tf, i))
         {
            if(m_obCount < 50)
            {
               m_orderBlocks[m_obCount].high      = iHigh(m_symbol, m_tf, i);
               m_orderBlocks[m_obCount].low       = iLow(m_symbol,  m_tf, i);
               m_orderBlocks[m_obCount].isBullish = false;
               m_orderBlocks[m_obCount].time      = iTime(m_symbol, m_tf, i);
               m_orderBlocks[m_obCount].mitigated = false;
               m_obCount++;
            }
         }
      }
   }

   //--- Check if price is inside a bullish FVG (potential buy zone)
   bool IsPriceInBullishFVG(double price)
   {
      for(int i = 0; i < m_fvgCount; i++)
      {
         if(m_fvgZones[i].isBullish && !m_fvgZones[i].filled)
            if(price >= m_fvgZones[i].low && price <= m_fvgZones[i].high)
               return true;
      }
      return false;
   }

   //--- Check if price is inside a bearish FVG (potential sell zone)
   bool IsPriceInBearishFVG(double price)
   {
      for(int i = 0; i < m_fvgCount; i++)
      {
         if(!m_fvgZones[i].isBullish && !m_fvgZones[i].filled)
            if(price >= m_fvgZones[i].low && price <= m_fvgZones[i].high)
               return true;
      }
      return false;
   }

   //--- Check bullish Order Block presence near price
   bool HasBullishOrderBlock(double price, double atr)
   {
      for(int i = 0; i < m_obCount; i++)
      {
         if(m_orderBlocks[i].isBullish && !m_orderBlocks[i].mitigated)
            if(MathAbs(price - m_orderBlocks[i].high) <= atr * 2.0)
               return true;
      }
      return false;
   }

   //--- Check bearish Order Block presence near price
   bool HasBearishOrderBlock(double price, double atr)
   {
      for(int i = 0; i < m_obCount; i++)
      {
         if(!m_orderBlocks[i].isBullish && !m_orderBlocks[i].mitigated)
            if(MathAbs(price - m_orderBlocks[i].low) <= atr * 2.0)
               return true;
      }
      return false;
   }

   //--- Liquidity sweep detection: price briefly exceeded prior swing and reversed
   bool DetectBullishSweep(double currentLow, double prevLow, double atr)
   {
      // Price dipped below prior low (sweeping liquidity) then returned above
      return (currentLow < prevLow && currentLow > prevLow - atr * 3.0);
   }

   bool DetectBearishSweep(double currentHigh, double prevHigh, double atr)
   {
      return (currentHigh > prevHigh && currentHigh < prevHigh + atr * 3.0);
   }

   //--- Update swing points
   void UpdateSwings()
   {
      double h = iHigh(m_symbol, m_tf, 1);
      double l = iLow(m_symbol,  m_tf, 1);
      if(h > m_lastSwingHigh || m_lastSwingHigh == 0) m_lastSwingHigh = h;
      if(l < m_lastSwingLow  || m_lastSwingLow  == 0) m_lastSwingLow  = l;
   }

   double GetLastSwingHigh() const { return m_lastSwingHigh; }
   double GetLastSwingLow()  const { return m_lastSwingLow;  }
   bool   IsBullishStructure() const { return m_bullishStructure; }

   //--- Draw FVG zones on chart
   void DrawFVGZones()
   {
      if(!m_drawFVG) return;
      for(int i = 0; i < m_fvgCount; i++)
      {
         if(m_fvgZones[i].filled) continue;
         string name = "FVG_" + IntToString(i) + "_" + TimeToString(m_fvgZones[i].time);
         color clr = m_fvgZones[i].isBullish ? clrLimeGreen : clrOrangeRed;
         // Draw rectangle from zone time to current
         if(ObjectFind(0, name) < 0)
            ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                        m_fvgZones[i].time, m_fvgZones[i].high,
                        TimeCurrent(), m_fvgZones[i].low);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_BACK,  true);
         ObjectSetInteger(0, name, OBJPROP_FILL,  true);
      }
   }

   void ClearZoneDrawings()
   {
      // Remove all FVG objects
      for(int i = ObjectsTotal(0)-1; i >= 0; i--)
      {
         string nm = ObjectName(0, i);
         if(StringFind(nm, "FVG_") == 0)
            ObjectDelete(0, nm);
      }
   }
};


#endif // MM7_MARKET_SMCDETECTOR_MQH
