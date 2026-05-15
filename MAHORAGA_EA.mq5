//+------------------------------------------------------------------+
//|                                                  MAHORAGA_EA.mq5  |
//|                    Adaptive Evolution Trading System              |
//|                    "Adapts to any market condition"               |
//+------------------------------------------------------------------+
#property copyright "Mahoraga Adaptive System"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Inputs
input double InpBaseRisk = 1.0;              // Base Risk %
input int    InpAdaptivePeriod = 50;         // Adaptive learning period
input double InpMinConfidence = 0.65;        // Min confidence to trade
input int    InpMagic = 777777;              // Magic number

//--- Globals
CTrade trade;
datetime lastBar = 0;

// Market context structure
struct SMarketContext {
   bool isTrending;
   bool isRanging;
   bool isVolatile;
   bool isCalm;
   double strength;
   int direction; // 1=up, -1=down, 0=neutral
};

// Strategy performance tracking
struct SStrategyStats {
   int wins;
   int losses;
   double totalProfit;
   double totalLoss;
   double winRate;
   double profitFactor;
   bool isActive;
   datetime lastUpdate;
};

SStrategyStats trendStrategy, reversalStrategy, breakoutStrategy, rangeStrategy;

// Adaptive parameters
double adaptiveRisk = 1.0;
double adaptiveSL = 1.5;
double adaptiveTP = 3.0;
int consecutiveLosses = 0;
int consecutiveWins = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   
   // Initialize strategies
   trendStrategy.isActive = true;
   reversalStrategy.isActive = true;
   breakoutStrategy.isActive = true;
   rangeStrategy.isActive = true;
   
   Print("MAHORAGA EA: Adaptive system initialized");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   // Learn from closed positions
   AdaptFromHistory();
   
   // Don't trade if position exists
   if(PositionsTotal() > 0) return;
   
   // Analyze market context
   SMarketContext context = AnalyzeMarketContext();
   
   // Select best strategy for current context
   int selectedStrategy = SelectBestStrategy(context);
   
   // Execute selected strategy
   if(selectedStrategy == 1 && trendStrategy.isActive)
      ExecuteTrendStrategy(context);
   else if(selectedStrategy == 2 && reversalStrategy.isActive)
      ExecuteReversalStrategy(context);
   else if(selectedStrategy == 3 && breakoutStrategy.isActive)
      ExecuteBreakoutStrategy(context);
   else if(selectedStrategy == 4 && rangeStrategy.isActive)
      ExecuteRangeStrategy(context);
}

//+------------------------------------------------------------------+
// MAHORAGA ADAPTATION: Learn from every trade
void AdaptFromHistory()
{
   static ulong lastTicket = 0;
   
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      if(total > 0)
      {
         ulong ticket = HistoryDealGetTicket(total - 1);
         if(ticket != lastTicket && ticket > 0)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
            
            // Update strategy stats
            if(StringFind(comment, "TREND") >= 0)
               UpdateStrategyStats(trendStrategy, profit);
            else if(StringFind(comment, "REVERSAL") >= 0)
               UpdateStrategyStats(reversalStrategy, profit);
            else if(StringFind(comment, "BREAKOUT") >= 0)
               UpdateStrategyStats(breakoutStrategy, profit);
            else if(StringFind(comment, "RANGE") >= 0)
               UpdateStrategyStats(rangeStrategy, profit);
            
            // Adapt risk based on performance
            if(profit > 0)
            {
               consecutiveWins++;
               consecutiveLosses = 0;
               if(consecutiveWins >= 3) adaptiveRisk = MathMin(2.0, adaptiveRisk * 1.1);
            }
            else
            {
               consecutiveLosses++;
               consecutiveWins = 0;
               if(consecutiveLosses >= 2) adaptiveRisk = MathMax(0.5, adaptiveRisk * 0.7);
            }
            
            lastTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
void UpdateStrategyStats(SStrategyStats &stats, double profit)
{
   if(profit > 0)
   {
      stats.wins++;
      stats.totalProfit += profit;
   }
   else
   {
      stats.losses++;
      stats.totalLoss += MathAbs(profit);
   }
   
   int total = stats.wins + stats.losses;
   if(total > 0)
   {
      stats.winRate = (double)stats.wins / total;
      stats.profitFactor = (stats.totalLoss > 0) ? stats.totalProfit / stats.totalLoss : 0;
      
      // Deactivate strategy if performing poorly
      if(total >= 10 && (stats.winRate < 0.35 || stats.profitFactor < 0.8))
         stats.isActive = false;
      
      // Reactivate if it was good before
      if(total >= 20 && stats.winRate > 0.45 && stats.profitFactor > 1.2)
         stats.isActive = true;
   }
   
   stats.lastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
SMarketContext AnalyzeMarketContext()
{
   SMarketContext ctx;
   
   // Calculate ATR for volatility
   double atr = CalculateATR(14);
   double avgATR = CalculateATR(50);
   ctx.isVolatile = (atr > avgATR * 1.3);
   ctx.isCalm = (atr < avgATR * 0.7);
   
   // Detect trend
   double sma20 = CalculateSMA(20);
   double sma50 = CalculateSMA(50);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   ctx.isTrending = (MathAbs(sma20 - sma50) > atr * 0.5);
   ctx.isRanging = !ctx.isTrending;
   
   if(close > sma20 && sma20 > sma50)
   {
      ctx.direction = 1;
      ctx.strength = (sma20 - sma50) / atr;
   }
   else if(close < sma20 && sma20 < sma50)
   {
      ctx.direction = -1;
      ctx.strength = (sma50 - sma20) / atr;
   }
   else
   {
      ctx.direction = 0;
      ctx.strength = 0;
   }
   
   return ctx;
}

//+------------------------------------------------------------------+
int SelectBestStrategy(SMarketContext &ctx)
{
   double scores[4];
   
   // Score each strategy based on context and performance
   scores[0] = ScoreStrategy(trendStrategy, ctx.isTrending && !ctx.isVolatile);
   scores[1] = ScoreStrategy(reversalStrategy, ctx.isTrending && ctx.isVolatile);
   scores[2] = ScoreStrategy(breakoutStrategy, ctx.isRanging && ctx.isVolatile);
   scores[3] = ScoreStrategy(rangeStrategy, ctx.isRanging && ctx.isCalm);
   
   // Find best strategy
   int best = 0;
   double maxScore = scores[0];
   for(int i = 1; i < 4; i++)
   {
      if(scores[i] > maxScore)
      {
         maxScore = scores[i];
         best = i;
      }
   }
   
   return (maxScore > InpMinConfidence) ? best + 1 : 0;
}

//+------------------------------------------------------------------+
double ScoreStrategy(SStrategyStats &stats, bool contextMatch)
{
   if(!stats.isActive) return 0;
   
   double score = 0.5; // Base score
   
   // Context match bonus
   if(contextMatch) score += 0.2;
   
   // Performance bonus
   int total = stats.wins + stats.losses;
   if(total >= 5)
   {
      score += (stats.winRate - 0.5) * 0.3;
      score += (stats.profitFactor - 1.0) * 0.2;
   }
   
   return MathMax(0, MathMin(1, score));
}

//+------------------------------------------------------------------+
// STRATEGY 1: Trend Following with Pullbacks
void ExecuteTrendStrategy(SMarketContext &ctx)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double sma20 = CalculateSMA(20);
   double sma50 = CalculateSMA(50);
   
   // Find support/resistance
   double support = FindSupport(20);
   double resistance = FindResistance(20);
   
   // BUY: Uptrend + pullback to support + bounce
   if(ctx.direction == 1)
   {
      double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
      double low2 = iLow(_Symbol, PERIOD_CURRENT, 2);
      
      if(low1 <= support * 1.001 && close > low1 && close > sma20)
      {
         OpenPosition(1, "TREND_BUY", ctx);
      }
   }
   // SELL: Downtrend + pullback to resistance + rejection
   else if(ctx.direction == -1)
   {
      double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double high2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
      
      if(high1 >= resistance * 0.999 && close < high1 && close < sma20)
      {
         OpenPosition(-1, "TREND_SELL", ctx);
      }
   }
}

//+------------------------------------------------------------------+
// STRATEGY 2: Reversal at Extremes
void ExecuteReversalStrategy(SMarketContext &ctx)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   // Find swing extremes
   double swingHigh = FindSwingHigh(10);
   double swingLow = FindSwingLow(10);
   
   // BUY: Price tests swing low + rejection candle
   if(low <= swingLow * 1.002)
   {
      double bodySize = MathAbs(close - iOpen(_Symbol, PERIOD_CURRENT, 1));
      double wickSize = close - low;
      
      if(wickSize > bodySize * 2 && close > low)
      {
         OpenPosition(1, "REVERSAL_BUY", ctx);
      }
   }
   // SELL: Price tests swing high + rejection candle
   else if(high >= swingHigh * 0.998)
   {
      double bodySize = MathAbs(close - iOpen(_Symbol, PERIOD_CURRENT, 1));
      double wickSize = high - close;
      
      if(wickSize > bodySize * 2 && close < high)
      {
         OpenPosition(-1, "REVERSAL_SELL", ctx);
      }
   }
}

//+------------------------------------------------------------------+
// STRATEGY 3: Breakout Trading
void ExecuteBreakoutStrategy(SMarketContext &ctx)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   // Find consolidation range
   double rangeHigh = FindRangeHigh(15);
   double rangeLow = FindRangeLow(15);
   double rangeSize = rangeHigh - rangeLow;
   
   // Volume confirmation
   long vol1 = iVolume(_Symbol, PERIOD_CURRENT, 1);
   long avgVol = 0;
   for(int i = 2; i <= 10; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= 9;
   
   // BUY: Break above range with volume
   if(close2 <= rangeHigh && close > rangeHigh && vol1 > avgVol * 1.3)
   {
      OpenPosition(1, "BREAKOUT_BUY", ctx);
   }
   // SELL: Break below range with volume
   else if(close2 >= rangeLow && close < rangeLow && vol1 > avgVol * 1.3)
   {
      OpenPosition(-1, "BREAKOUT_SELL", ctx);
   }
}

//+------------------------------------------------------------------+
// STRATEGY 4: Range Trading
void ExecuteRangeStrategy(SMarketContext &ctx)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   double rangeHigh = FindRangeHigh(20);
   double rangeLow = FindRangeLow(20);
   double rangeMid = (rangeHigh + rangeLow) / 2;
   double rangeSize = rangeHigh - rangeLow;
   
   // BUY: Near range low
   if(close <= rangeLow + rangeSize * 0.2 && close > rangeLow)
   {
      OpenPosition(1, "RANGE_BUY", ctx);
   }
   // SELL: Near range high
   else if(close >= rangeHigh - rangeSize * 0.2 && close < rangeHigh)
   {
      OpenPosition(-1, "RANGE_SELL", ctx);
   }
}

//+------------------------------------------------------------------+
void OpenPosition(int direction, string comment, SMarketContext &ctx)
{
   double atr = CalculateATR(14);
   double price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Adaptive SL/TP based on context
   double slMultiplier = adaptiveSL;
   double tpMultiplier = adaptiveTP;
   
   if(ctx.isVolatile)
   {
      slMultiplier *= 1.3;
      tpMultiplier *= 1.3;
   }
   
   double sl = (direction > 0) ? price - atr * slMultiplier : price + atr * slMultiplier;
   double tp = (direction > 0) ? price + atr * tpMultiplier : price - atr * tpMultiplier;
   
   // Calculate lots with adaptive risk
   double lots = CalculateLots(atr * slMultiplier);
   
   bool result = false;
   if(direction > 0)
      result = trade.Buy(lots, _Symbol, price, sl, tp, comment);
   else
      result = trade.Sell(lots, _Symbol, price, sl, tp, comment);
   
   if(result)
      Print("Position opened: ", comment, " Lots=", lots, " Risk=", adaptiveRisk, "%");
}

//+------------------------------------------------------------------+
double CalculateLots(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * adaptiveRisk * InpBaseRisk / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = risk / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
double CalculateATR(int period)
{
   double atr = 0;
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      double prevClose = iClose(_Symbol, PERIOD_CURRENT, i + 1);
      double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      atr += tr;
   }
   return atr / period;
}

//+------------------------------------------------------------------+
double CalculateSMA(int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, PERIOD_CURRENT, i);
   return sum / period;
}

//+------------------------------------------------------------------+
double FindSupport(int bars)
{
   double lowest = iLow(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= bars; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      if(low < lowest) lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
double FindResistance(int bars)
{
   double highest = iHigh(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 2; i <= bars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(high > highest) highest = high;
   }
   return highest;
}

//+------------------------------------------------------------------+
double FindSwingHigh(int bars)
{
   double highest = 0;
   for(int i = 1; i <= bars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      for(int j = MathMax(1, i - 2); j <= MathMin(bars, i + 2); j++)
      {
         if(j != i && iHigh(_Symbol, PERIOD_CURRENT, j) > high)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && high > highest) highest = high;
   }
   return highest;
}

//+------------------------------------------------------------------+
double FindSwingLow(int bars)
{
   double lowest = 999999;
   for(int i = 1; i <= bars; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      for(int j = MathMax(1, i - 2); j <= MathMin(bars, i + 2); j++)
      {
         if(j != i && iLow(_Symbol, PERIOD_CURRENT, j) < low)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && low < lowest) lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
double FindRangeHigh(int bars)
{
   double sum = 0;
   int count = 0;
   for(int i = 1; i <= bars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(high > sum / MathMax(1, count))
      {
         sum += high;
         count++;
      }
   }
   return (count > 0) ? sum / count : iHigh(_Symbol, PERIOD_CURRENT, 1);
}

//+------------------------------------------------------------------+
double FindRangeLow(int bars)
{
   double sum = 0;
   int count = 0;
   for(int i = 1; i <= bars; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      if(count == 0 || low < sum / count)
      {
         sum += low;
         count++;
      }
   }
   return (count > 0) ? sum / count : iLow(_Symbol, PERIOD_CURRENT, 1);
}
//+------------------------------------------------------------------+
