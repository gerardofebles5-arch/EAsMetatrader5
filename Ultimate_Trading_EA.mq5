//+------------------------------------------------------------------+
//|                                         Ultimate_Trading_EA.mq5   |
//|           Unified: OrderFlow + SmartMoney + Adaptive ML           |
//+------------------------------------------------------------------+
#property copyright "Ultimate Trading System"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Inputs
input group "=== Risk Management ==="
input double InpRisk = 2.0;                  // Risk per trade %
input double InpMinConfidence = 0.65;        // Minimum confidence to trade

input group "=== OrderFlow Settings ==="
input int    InpOFLookback = 20;             // OrderFlow lookback bars
input double InpOFImbalance = 0.65;          // Imbalance threshold
input double InpOFVolumeSpike = 1.5;         // Volume spike multiplier

input group "=== Smart Money Settings ==="
input int    InpSMSwingBars = 5;             // Swing detection bars
input double InpSMFVGSize = 0.0003;          // Fair Value Gap min size

input group "=== Machine Learning ==="
input int    InpMLPatternBars = 10;          // Pattern bars
input int    InpMLMaxPatterns = 500;         // Max patterns to store

input group "=== General ==="
input int    InpMagic = 777777;              // Magic number

//--- Globals
CTrade trade;
datetime lastBar = 0;

// Smart Money structures
struct SSwing {
   double price;
   bool isHigh;
   bool broken;
};
SSwing lastSwingHigh, lastSwingLow;

// ML structures
struct SPattern {
   double returns[10];
   bool wasSuccessful;
   double confidence;
};
SPattern patterns[];
int patternCount = 0;

// Market state
struct SMarketState {
   double volatility;
   double trend;
   double momentum;
   double efficiency;
};

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   ArrayResize(patterns, InpMLMaxPatterns);
   lastSwingHigh.broken = true;
   lastSwingLow.broken = true;
   Print("Ultimate Trading EA initialized - 3 systems unified");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   if(PositionsTotal() > 0)
   {
      LearnFromTrades();
      return;
   }
   
   // === SYSTEM 1: ORDER FLOW ANALYSIS ===
   double ofBuyScore = 0, ofSellScore = 0;
   AnalyzeOrderFlow(ofBuyScore, ofSellScore);
   
   // === SYSTEM 2: SMART MONEY CONCEPTS ===
   double smBuyScore = 0, smSellScore = 0;
   AnalyzeSmartMoney(smBuyScore, smSellScore);
   
   // === SYSTEM 3: MACHINE LEARNING ===
   double mlBuyScore = 0, mlSellScore = 0;
   AnalyzeMachineLearning(mlBuyScore, mlSellScore);
   
   // === UNIFIED SCORING ===
   double totalBuyScore = (ofBuyScore * 0.35) + (smBuyScore * 0.35) + (mlBuyScore * 0.30);
   double totalSellScore = (ofSellScore * 0.35) + (smSellScore * 0.35) + (mlSellScore * 0.30);
   
   // === TRADING DECISION ===
   if(totalBuyScore > InpMinConfidence && totalBuyScore > totalSellScore)
   {
      OpenBuy(totalBuyScore);
      Print("BUY Signal - OF:", ofBuyScore, " SM:", smBuyScore, " ML:", mlBuyScore, " Total:", totalBuyScore);
   }
   else if(totalSellScore > InpMinConfidence && totalSellScore > totalBuyScore)
   {
      OpenSell(totalSellScore);
      Print("SELL Signal - OF:", ofSellScore, " SM:", smSellScore, " ML:", mlSellScore, " Total:", totalSellScore);
   }
}

//+------------------------------------------------------------------+
// SYSTEM 1: ORDER FLOW ANALYSIS
//+------------------------------------------------------------------+
void AnalyzeOrderFlow(double &buyScore, double &sellScore)
{
   buyScore = 0;
   sellScore = 0;
   
   // 1. Buy/Sell Imbalance
   double imbalance = CalculateImbalance();
   if(imbalance > InpOFImbalance)
      buyScore += 0.3;
   else if(imbalance < (1.0 - InpOFImbalance))
      sellScore += 0.3;
   
   // 2. Volume Spike
   if(DetectVolumeSpike())
   {
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
      if(close1 > open1)
         buyScore += 0.25;
      else
         sellScore += 0.25;
   }
   
   // 3. Liquidity Grab
   int liquidityDirection = DetectLiquidityGrab();
   if(liquidityDirection == 1)
      buyScore += 0.25;
   else if(liquidityDirection == -1)
      sellScore += 0.25;
   
   // 4. Order Block
   double obPrice = FindOrderBlock();
   if(obPrice > 0)
   {
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(close1 > obPrice)
         buyScore += 0.2;
      else
         sellScore += 0.2;
   }
}

double CalculateImbalance()
{
   double buyVol = 0, sellVol = 0;
   for(int i = 1; i <= InpOFLookback; i++)
   {
      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      long vol = iVolume(_Symbol, PERIOD_CURRENT, i);
      if(close > open) buyVol += vol;
      else sellVol += vol;
   }
   double total = buyVol + sellVol;
   return (total > 0) ? buyVol / total : 0.5;
}

bool DetectVolumeSpike()
{
   long currentVol = iVolume(_Symbol, PERIOD_CURRENT, 1);
   double avgVol = 0;
   for(int i = 2; i <= InpOFLookback + 1; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= InpOFLookback;
   return (currentVol > avgVol * InpOFVolumeSpike);
}

int DetectLiquidityGrab()
{
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   double swingHigh = high1, swingLow = low1;
   for(int i = 2; i <= 10; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      if(h > swingHigh) swingHigh = h;
      if(l < swingLow) swingLow = l;
   }
   
   bool grabAbove = (high1 > swingHigh && close1 < high1 - (high1 - low1) * 0.5);
   bool grabBelow = (low1 < swingLow && close1 > low1 + (high1 - low1) * 0.5);
   
   if(grabBelow) return 1;  // Bullish
   if(grabAbove) return -1; // Bearish
   return 0;
}

double FindOrderBlock()
{
   double maxVol = 0;
   int maxIdx = -1;
   for(int i = 1; i <= InpOFLookback; i++)
   {
      long vol = iVolume(_Symbol, PERIOD_CURRENT, i);
      if(vol > maxVol)
      {
         maxVol = vol;
         maxIdx = i;
      }
   }
   if(maxIdx > 0)
   {
      double open = iOpen(_Symbol, PERIOD_CURRENT, maxIdx);
      double close = iClose(_Symbol, PERIOD_CURRENT, maxIdx);
      return (close > open) ? iLow(_Symbol, PERIOD_CURRENT, maxIdx) : iHigh(_Symbol, PERIOD_CURRENT, maxIdx);
   }
   return 0;
}

//+------------------------------------------------------------------+
// SYSTEM 2: SMART MONEY CONCEPTS
//+------------------------------------------------------------------+
void AnalyzeSmartMoney(double &buyScore, double &sellScore)
{
   buyScore = 0;
   sellScore = 0;
   
   UpdateSwingPoints();
   
   // 1. Break of Structure
   if(DetectBOS(true))
      buyScore += 0.35;
   if(DetectBOS(false))
      sellScore += 0.35;
   
   // 2. Fair Value Gap
   if(DetectFVG(true))
      buyScore += 0.35;
   if(DetectFVG(false))
      sellScore += 0.35;
   
   // 3. Order Block
   if(DetectOB(true))
      buyScore += 0.3;
   if(DetectOB(false))
      sellScore += 0.3;
}

void UpdateSwingPoints()
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, InpSMSwingBars);
   bool isSwingHigh = true;
   for(int i = 1; i < InpSMSwingBars * 2; i++)
   {
      if(i == InpSMSwingBars) continue;
      if(iHigh(_Symbol, PERIOD_CURRENT, i) > high)
      {
         isSwingHigh = false;
         break;
      }
   }
   if(isSwingHigh)
   {
      lastSwingHigh.price = high;
      lastSwingHigh.isHigh = true;
      lastSwingHigh.broken = false;
   }
   
   double low = iLow(_Symbol, PERIOD_CURRENT, InpSMSwingBars);
   bool isSwingLow = true;
   for(int i = 1; i < InpSMSwingBars * 2; i++)
   {
      if(i == InpSMSwingBars) continue;
      if(iLow(_Symbol, PERIOD_CURRENT, i) < low)
      {
         isSwingLow = false;
         break;
      }
   }
   if(isSwingLow)
   {
      lastSwingLow.price = low;
      lastSwingLow.isHigh = false;
      lastSwingLow.broken = false;
   }
}

bool DetectBOS(bool bullish)
{
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   if(bullish && !lastSwingHigh.broken && close1 > lastSwingHigh.price)
   {
      lastSwingHigh.broken = true;
      return true;
   }
   if(!bullish && !lastSwingLow.broken && close1 < lastSwingLow.price)
   {
      lastSwingLow.broken = true;
      return true;
   }
   return false;
}

bool DetectFVG(bool bullish)
{
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high3 = iHigh(_Symbol, PERIOD_CURRENT, 3);
   double low3 = iLow(_Symbol, PERIOD_CURRENT, 3);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(bullish)
   {
      double gap = low1 - high3;
      return (gap > InpSMFVGSize && close1 >= high3);
   }
   else
   {
      double gap = low3 - high1;
      return (gap > InpSMFVGSize && close1 <= low3);
   }
}

bool DetectOB(bool bullish)
{
   for(int i = 1; i <= 10; i++)
   {
      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      
      if(bullish && close < open)
      {
         bool bullishMove = true;
         for(int j = i - 1; j >= 1; j--)
         {
            if(iClose(_Symbol, PERIOD_CURRENT, j) < iOpen(_Symbol, PERIOD_CURRENT, j))
            {
               bullishMove = false;
               break;
            }
         }
         if(bullishMove)
         {
            double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
            return (close1 > iLow(_Symbol, PERIOD_CURRENT, i));
         }
      }
      else if(!bullish && close > open)
      {
         bool bearishMove = true;
         for(int j = i - 1; j >= 1; j--)
         {
            if(iClose(_Symbol, PERIOD_CURRENT, j) > iOpen(_Symbol, PERIOD_CURRENT, j))
            {
               bearishMove = false;
               break;
            }
         }
         if(bearishMove)
         {
            double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
            return (close1 < iHigh(_Symbol, PERIOD_CURRENT, i));
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
// SYSTEM 3: MACHINE LEARNING
//+------------------------------------------------------------------+
void AnalyzeMachineLearning(double &buyScore, double &sellScore)
{
   buyScore = 0;
   sellScore = 0;
   
   if(patternCount < 10) return; // Need history
   
   SMarketState state = GetMarketState();
   SPattern current = GetCurrentPattern();
   
   double confidence = FindSimilarPatterns(current);
   double prediction = PredictDirection(current, state);
   
   if(prediction > 0.6)
      buyScore = confidence;
   else if(prediction < 0.4)
      sellScore = confidence;
}

SMarketState GetMarketState()
{
   SMarketState state;
   double atr = CalculateATR(14);
   double avgPrice = 0;
   for(int i = 1; i <= 14; i++)
      avgPrice += iClose(_Symbol, PERIOD_CURRENT, i);
   avgPrice /= 14;
   
   state.volatility = atr / avgPrice;
   
   double sma20 = 0, sma50 = 0;
   for(int i = 1; i <= 50; i++)
   {
      double c = iClose(_Symbol, PERIOD_CURRENT, i);
      if(i <= 20) sma20 += c;
      sma50 += c;
   }
   sma20 /= 20;
   sma50 /= 50;
   state.trend = (sma20 - sma50) / avgPrice;
   
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close10 = iClose(_Symbol, PERIOD_CURRENT, 10);
   state.momentum = (close1 - close10) / close10;
   
   double priceMove = MathAbs(close1 - iClose(_Symbol, PERIOD_CURRENT, 20));
   double pathLength = 0;
   for(int i = 1; i < 20; i++)
      pathLength += MathAbs(iClose(_Symbol, PERIOD_CURRENT, i) - iClose(_Symbol, PERIOD_CURRENT, i + 1));
   state.efficiency = (pathLength > 0) ? priceMove / pathLength : 0;
   
   return state;
}

SPattern GetCurrentPattern()
{
   SPattern p;
   for(int i = 0; i < InpMLPatternBars; i++)
   {
      double c1 = iClose(_Symbol, PERIOD_CURRENT, i + 1);
      double c2 = iClose(_Symbol, PERIOD_CURRENT, i + 2);
      p.returns[i] = (c1 - c2) / c2;
   }
   p.confidence = 0;
   p.wasSuccessful = false;
   return p;
}

double FindSimilarPatterns(SPattern &current)
{
   if(patternCount == 0) return 0.5;
   
   int successCount = 0, totalCount = 0;
   for(int i = 0; i < patternCount; i++)
   {
      double similarity = CalculateSimilarity(current, patterns[i]);
      if(similarity > 0.7)
      {
         totalCount++;
         if(patterns[i].wasSuccessful) successCount++;
      }
   }
   return (totalCount > 0) ? (double)successCount / totalCount : 0.5;
}

double CalculateSimilarity(SPattern &p1, SPattern &p2)
{
   double sum1 = 0, sum2 = 0, sum12 = 0, sq1 = 0, sq2 = 0;
   for(int i = 0; i < InpMLPatternBars; i++)
   {
      sum1 += p1.returns[i];
      sum2 += p2.returns[i];
      sum12 += p1.returns[i] * p2.returns[i];
      sq1 += p1.returns[i] * p1.returns[i];
      sq2 += p2.returns[i] * p2.returns[i];
   }
   double n = InpMLPatternBars;
   double num = n * sum12 - sum1 * sum2;
   double den = MathSqrt((n * sq1 - sum1 * sum1) * (n * sq2 - sum2 * sum2));
   return (den > 0) ? MathAbs(num / den) : 0;
}

double PredictDirection(SPattern &p, SMarketState &s)
{
   double pred = 0.5;
   if(s.trend > 0.001) pred += 0.15;
   else if(s.trend < -0.001) pred -= 0.15;
   if(s.momentum > 0.002) pred += 0.15;
   else if(s.momentum < -0.002) pred -= 0.15;
   if(s.efficiency > 0.5)
   {
      if(s.trend > 0) pred += 0.1;
      else pred -= 0.1;
   }
   if(p.returns[0] > 0) pred += 0.1;
   else pred -= 0.1;
   return MathMax(0, MathMin(1, pred));
}

void LearnFromTrades()
{
   static ulong lastTicket = 0;
   if(HistorySelect(TimeCurrent() - 3600, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      if(total > 0)
      {
         ulong ticket = HistoryDealGetTicket(total - 1);
         if(ticket != lastTicket && patternCount < InpMLMaxPatterns)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            patterns[patternCount] = GetCurrentPattern();
            patterns[patternCount].wasSuccessful = (profit > 0);
            patterns[patternCount].confidence = MathAbs(profit) / AccountInfoDouble(ACCOUNT_BALANCE);
            patternCount++;
            lastTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
// UTILITY FUNCTIONS
//+------------------------------------------------------------------+
double CalculateATR(int period)
{
   double atr = 0;
   for(int i = 1; i <= period; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      double pc = iClose(_Symbol, PERIOD_CURRENT, i + 1);
      double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      atr += tr;
   }
   return atr / period;
}

double CalculateLots(double confidence)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * InpRisk * confidence / 100.0;
   double atr = CalculateATR(14);
   double slDist = atr * 1.5;
   
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lots = risk / (slDist * tickVal / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

void OpenBuy(double confidence)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = CalculateATR(14);
   double sl = ask - atr * 1.5;
   double tp = ask + atr * 3.5;
   double lots = CalculateLots(confidence);
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "Ultimate_BUY"))
   {
      Print("BUY opened: Confidence=", DoubleToString(confidence, 2), " Lots=", lots);
   }
}

void OpenSell(double confidence)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = CalculateATR(14);
   double sl = bid + atr * 1.5;
   double tp = bid - atr * 3.5;
   double lots = CalculateLots(confidence);
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "Ultimate_SELL"))
   {
      Print("SELL opened: Confidence=", DoubleToString(confidence, 2), " Lots=", lots);
   }
}
//+------------------------------------------------------------------+
