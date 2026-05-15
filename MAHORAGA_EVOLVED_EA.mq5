//+------------------------------------------------------------------+
//|                                         MAHORAGA_EVOLVED_EA.mq5  |
//|                    EVOLVED Adaptive Intelligence System           |
//+------------------------------------------------------------------+
#property copyright "Mahoraga Evolution"
#property version   "2.00"

#include <Trade\Trade.mqh>

input double InpBaseRisk = 0.8;
input double InpMinConfidence = 0.55;
input int    InpEvolutionSpeed = 5;
input bool   InpUseSmartFilters = true;
input int    InpMagic = 888999;

CTrade trade;
datetime lastBar = 0;

struct SMarketDNA {
   double volatilityRatio;
   double trendStrength;
   double momentumPower;
   double volumeProfile;
   double priceEfficiency;
   double marketPhase;
   int dominantPattern;
};

struct SStrategyGene {
   int wins, losses;
   double totalProfit, totalLoss;
   double winRate, profitFactor;
   double confidence;
   bool isActive;
   double adaptiveMultiplier;
   int consecutiveWins, consecutiveLosses;
};

SStrategyGene genes[6];
double globalRiskMultiplier = 1.0;
int totalTrades = 0;
double peakBalance = 0;
double currentDrawdown = 0;

struct SMarketMemory {
   double priceLevel;
   int touchCount;
   bool isBroken;
   datetime lastTouch;
   int reactionType;
};

SMarketMemory supportLevels[20];
SMarketMemory resistanceLevels[20];
int supportCount = 0, resistanceCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   for(int i = 0; i < 6; i++)
   {
      genes[i].isActive = true;
      genes[i].adaptiveMultiplier = 1.0;
      genes[i].confidence = 0.5;
   }
   
   Print("MAHORAGA EVOLVED: Maximum intelligence activated");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   EvolveFromExperience();
   UpdateMarketMemory();
   
   if(PositionsTotal() > 0)
   {
      ManageOpenPosition();
      return;
   }
   
   SMarketDNA dna = DecodeMarketDNA();
   
   int bestGene = SelectDominantGene(dna);
   if(bestGene < 0) return;
   
   double confidence = CalculateConfidence(bestGene, dna);
   if(confidence < InpMinConfidence) return;
   
   ExecuteEvolved(bestGene, dna, confidence);
}

void EvolveFromExperience()
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
            
            int geneIndex = ExtractGeneIndex(comment);
            if(geneIndex >= 0 && geneIndex < 6)
            {
               UpdateGene(genes[geneIndex], profit);
               totalTrades++;
               
               double balance = AccountInfoDouble(ACCOUNT_BALANCE);
               if(balance > peakBalance) peakBalance = balance;
               currentDrawdown = (peakBalance - balance) / peakBalance * 100;
               
               if(profit > 0)
               {
                  globalRiskMultiplier = MathMin(1.3, globalRiskMultiplier * 1.03);
                  genes[geneIndex].adaptiveMultiplier = MathMin(1.5, genes[geneIndex].adaptiveMultiplier * 1.08);
               }
               else
               {
                  globalRiskMultiplier = MathMax(0.3, globalRiskMultiplier * 0.80);
                  genes[geneIndex].adaptiveMultiplier = MathMax(0.4, genes[geneIndex].adaptiveMultiplier * 0.75);
               }
               
               if(currentDrawdown > 10)
                  globalRiskMultiplier = MathMax(0.25, globalRiskMultiplier * 0.75);
               if(currentDrawdown > 20)
                  globalRiskMultiplier = 0.2;
            }
            
            lastTicket = ticket;
         }
      }
   }
}

void UpdateGene(SStrategyGene &gene, double profit)
{
   if(profit > 0)
   {
      gene.wins++;
      gene.totalProfit += profit;
      gene.consecutiveWins++;
      gene.consecutiveLosses = 0;
   }
   else
   {
      gene.losses++;
      gene.totalLoss += MathAbs(profit);
      gene.consecutiveLosses++;
      gene.consecutiveWins = 0;
   }
   
   int total = gene.wins + gene.losses;
   if(total > 0)
   {
      gene.winRate = (double)gene.wins / total;
      gene.profitFactor = (gene.totalLoss > 0) ? gene.totalProfit / gene.totalLoss : 0;
      
      gene.confidence = (gene.winRate * 0.7 + (gene.profitFactor / 2.5) * 0.3);
      
      if(total >= 5)
      {
         if(gene.winRate < 0.35 || gene.profitFactor < 0.7)
            gene.isActive = false;
         else if(gene.winRate > 0.48 && gene.profitFactor > 1.2)
            gene.isActive = true;
      }
      
      if(gene.consecutiveLosses >= 3)
      {
         gene.isActive = false;
         gene.adaptiveMultiplier = MathMax(0.3, gene.adaptiveMultiplier * 0.6);
      }
      
      if(gene.consecutiveWins >= 2 && !gene.isActive && total >= 10)
         gene.isActive = true;
   }
}

int ExtractGeneIndex(string comment)
{
   if(StringFind(comment, "G0") >= 0) return 0;
   if(StringFind(comment, "G1") >= 0) return 1;
   if(StringFind(comment, "G2") >= 0) return 2;
   if(StringFind(comment, "G3") >= 0) return 3;
   if(StringFind(comment, "G4") >= 0) return 4;
   if(StringFind(comment, "G5") >= 0) return 5;
   return -1;
}

SMarketDNA DecodeMarketDNA()
{
   SMarketDNA dna;
   
   double atr14 = CalculateATR(14);
   double atr50 = CalculateATR(50);
   dna.volatilityRatio = (atr50 > 0) ? atr14 / atr50 : 1.0;
   
   double sma10 = CalculateSMA(10);
   double sma30 = CalculateSMA(30);
   double sma100 = CalculateSMA(100);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   dna.trendStrength = 0;
   if(sma10 > sma30 && sma30 > sma100) dna.trendStrength = (sma10 - sma100) / atr14;
   else if(sma10 < sma30 && sma30 < sma100) dna.trendStrength = -(sma100 - sma10) / atr14;
   
   double close5 = iClose(_Symbol, PERIOD_CURRENT, 5);
   double close20 = iClose(_Symbol, PERIOD_CURRENT, 20);
   dna.momentumPower = (close - close20) / atr14;
   
   long avgVol = 0;
   for(int i = 1; i <= 20; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= 20;
   long currentVol = iVolume(_Symbol, PERIOD_CURRENT, 1);
   dna.volumeProfile = (avgVol > 0) ? (double)currentVol / avgVol : 1.0;
   
   double directMove = MathAbs(close - iClose(_Symbol, PERIOD_CURRENT, 30));
   double pathLength = 0;
   for(int i = 1; i < 30; i++)
      pathLength += MathAbs(iClose(_Symbol, PERIOD_CURRENT, i) - iClose(_Symbol, PERIOD_CURRENT, i + 1));
   dna.priceEfficiency = (pathLength > 0) ? directMove / pathLength : 0;
   
   if(dna.priceEfficiency > 0.6 && MathAbs(dna.trendStrength) > 1.5)
      dna.marketPhase = 1;
   else if(dna.priceEfficiency < 0.3 && MathAbs(dna.trendStrength) < 0.5)
      dna.marketPhase = 2;
   else if(dna.volatilityRatio > 1.4)
      dna.marketPhase = 3;
   else
      dna.marketPhase = 4;
   
   dna.dominantPattern = DetectDominantPattern();
   
   return dna;
}

int DetectDominantPattern()
{
   double closes[10];
   for(int i = 0; i < 10; i++)
      closes[i] = iClose(_Symbol, PERIOD_CURRENT, i + 1);
   
   int higherHighs = 0, lowerLows = 0;
   for(int i = 0; i < 8; i++)
   {
      if(closes[i] > closes[i + 1]) higherHighs++;
      if(closes[i] < closes[i + 1]) lowerLows++;
   }
   
   if(higherHighs >= 6) return 1;
   if(lowerLows >= 6) return -1;
   
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double body = MathAbs(closes[0] - iOpen(_Symbol, PERIOD_CURRENT, 1));
   double upperWick = high1 - MathMax(closes[0], iOpen(_Symbol, PERIOD_CURRENT, 1));
   double lowerWick = MathMin(closes[0], iOpen(_Symbol, PERIOD_CURRENT, 1)) - low1;
   
   if(upperWick > body * 2 && upperWick > lowerWick * 2) return 2;
   if(lowerWick > body * 2 && lowerWick > upperWick * 2) return 3;
   
   return 0;
}

int SelectDominantGene(SMarketDNA &dna)
{
   double scores[6];
   
   scores[0] = ScoreGene(genes[0], dna.marketPhase == 1 && dna.trendStrength > 1.0);
   scores[1] = ScoreGene(genes[1], dna.marketPhase == 1 && dna.trendStrength < -1.0);
   scores[2] = ScoreGene(genes[2], dna.marketPhase == 3 && dna.dominantPattern == 2);
   scores[3] = ScoreGene(genes[3], dna.marketPhase == 3 && dna.dominantPattern == 3);
   scores[4] = ScoreGene(genes[4], dna.marketPhase == 2 && dna.volatilityRatio < 1.0);
   scores[5] = ScoreGene(genes[5], dna.volumeProfile > 1.5 && dna.priceEfficiency > 0.5);
   
   int best = -1;
   double maxScore = 0.40;
   
   for(int i = 0; i < 6; i++)
   {
      if(scores[i] > maxScore && genes[i].isActive)
      {
         maxScore = scores[i];
         best = i;
      }
   }
   
   return best;
}

double ScoreGene(SStrategyGene &gene, bool contextMatch)
{
   if(!gene.isActive) return 0;
   
   double score = 0.4;
   
   if(contextMatch) score += 0.3;
   
   score += gene.confidence * 0.2;
   score += gene.adaptiveMultiplier * 0.1;
   
   if(gene.consecutiveWins >= 2) score += 0.1;
   if(gene.consecutiveLosses >= 2) score -= 0.1;
   
   return MathMax(0, MathMin(1, score));
}

double CalculateConfidence(int geneIndex, SMarketDNA &dna)
{
   double confidence = genes[geneIndex].confidence;
   
   if(dna.volatilityRatio > 1.6) confidence *= 0.85;
   if(dna.volatilityRatio < 0.7) confidence *= 0.90;
   if(dna.volumeProfile > 2.0) confidence *= 1.15;
   if(MathAbs(dna.trendStrength) > 2.5) confidence *= 1.2;
   if(dna.priceEfficiency > 0.75) confidence *= 1.15;
   
   if(currentDrawdown > 8) confidence *= 0.80;
   if(currentDrawdown > 15) confidence *= 0.70;
   if(currentDrawdown > 25) confidence *= 0.50;
   
   int total = genes[geneIndex].wins + genes[geneIndex].losses;
   if(total >= 5 && genes[geneIndex].winRate < 0.40)
      confidence *= 0.75;
   
   return MathMax(0, MathMin(1, confidence));
}

void ExecuteEvolved(int geneIndex, SMarketDNA &dna, double confidence)
{
   if(geneIndex == 0) ExecuteTrendFollowBuy(dna, confidence);
   else if(geneIndex == 1) ExecuteTrendFollowSell(dna, confidence);
   else if(geneIndex == 2) ExecuteReversalSell(dna, confidence);
   else if(geneIndex == 3) ExecuteReversalBuy(dna, confidence);
   else if(geneIndex == 4) ExecuteRangeTrading(dna, confidence);
   else if(geneIndex == 5) ExecuteBreakoutTrading(dna, confidence);
}

void ExecuteTrendFollowBuy(SMarketDNA &dna, double confidence)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double sma20 = CalculateSMA(20);
   
   double support = FindIntelligentSupport(30);
   double atr = CalculateATR(14);
   
   if(close > sma20 * 0.998 && close <= support + atr * 0.5)
   {
      double reactionStrength = AnalyzeReaction(support, true);
      if(reactionStrength > 0.4 || dna.trendStrength > 1.5)
      {
         OpenIntelligentPosition(1, "G0_TrendBuy", dna, confidence);
      }
   }
}

void ExecuteTrendFollowSell(SMarketDNA &dna, double confidence)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double sma20 = CalculateSMA(20);
   
   double resistance = FindIntelligentResistance(30);
   double atr = CalculateATR(14);
   
   if(close < sma20 * 1.002 && close >= resistance - atr * 0.5)
   {
      double reactionStrength = AnalyzeReaction(resistance, false);
      if(reactionStrength > 0.4 || dna.trendStrength < -1.5)
      {
         OpenIntelligentPosition(-1, "G1_TrendSell", dna, confidence);
      }
   }
}

void ExecuteReversalSell(SMarketDNA &dna, double confidence)
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   
   double swingHigh = FindSwingExtreme(15, true);
   
   if(high >= swingHigh * 0.997)
   {
      double wickRatio = (high - MathMax(close, open)) / (high - iLow(_Symbol, PERIOD_CURRENT, 1));
      if(wickRatio > 0.5 || close < open)
      {
         OpenIntelligentPosition(-1, "G2_ReversalSell", dna, confidence);
      }
   }
}

void ExecuteReversalBuy(SMarketDNA &dna, double confidence)
{
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   
   double swingLow = FindSwingExtreme(15, false);
   
   if(low <= swingLow * 1.003)
   {
      double wickRatio = (MathMin(close, open) - low) / (iHigh(_Symbol, PERIOD_CURRENT, 1) - low);
      if(wickRatio > 0.5 || close > open)
      {
         OpenIntelligentPosition(1, "G3_ReversalBuy", dna, confidence);
      }
   }
}

void ExecuteRangeTrading(SMarketDNA &dna, double confidence)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   double rangeHigh = FindRangeExtreme(25, true);
   double rangeLow = FindRangeExtreme(25, false);
   double rangeMid = (rangeHigh + rangeLow) / 2;
   double rangeSize = rangeHigh - rangeLow;
   
   if(rangeSize < CalculateATR(14) * 4)
   {
      if(close <= rangeLow + rangeSize * 0.35)
         OpenIntelligentPosition(1, "G4_RangeBuy", dna, confidence);
      else if(close >= rangeHigh - rangeSize * 0.35)
         OpenIntelligentPosition(-1, "G4_RangeSell", dna, confidence);
   }
}

void ExecuteBreakoutTrading(SMarketDNA &dna, double confidence)
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   double consolidationHigh = FindRangeExtreme(20, true);
   double consolidationLow = FindRangeExtreme(20, false);
   
   if(dna.volumeProfile > 1.3)
   {
      if(close2 <= consolidationHigh && close > consolidationHigh)
         OpenIntelligentPosition(1, "G5_BreakoutBuy", dna, confidence);
      else if(close2 >= consolidationLow && close < consolidationLow)
         OpenIntelligentPosition(-1, "G5_BreakoutSell", dna, confidence);
   }
}

void OpenIntelligentPosition(int direction, string comment, SMarketDNA &dna, double confidence)
{
   double atr = CalculateATR(14);
   double price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double slMultiplier = 1.0;
   double tpMultiplier = 2.5;
   
   if(dna.volatilityRatio > 1.5)
   {
      slMultiplier *= 1.3;
      tpMultiplier *= 1.2;
   }
   else if(dna.volatilityRatio < 0.8)
   {
      slMultiplier *= 0.85;
      tpMultiplier *= 1.15;
   }
   
   if(dna.priceEfficiency > 0.7)
      tpMultiplier *= 1.25;
   
   if(MathAbs(dna.trendStrength) > 2.0)
      tpMultiplier *= 1.15;
   
   double sl = (direction > 0) ? price - atr * slMultiplier : price + atr * slMultiplier;
   double tp = (direction > 0) ? price + atr * tpMultiplier : price - atr * tpMultiplier;
   
   double lots = CalculateIntelligentLots(atr * slMultiplier, confidence);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      return;
   
   bool result = false;
   if(direction > 0)
      result = trade.Buy(lots, _Symbol, price, sl, tp, comment);
   else
      result = trade.Sell(lots, _Symbol, price, sl, tp, comment);
   
   if(result)
      Print("EVOLVED: ", comment, " | Conf:", DoubleToString(confidence, 2), " | Risk:", DoubleToString(globalRiskMultiplier, 2), " | Lots:", lots, " | DD:", DoubleToString(currentDrawdown, 1), "%");
}

double CalculateIntelligentLots(double slDistance, double confidence)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double baseRisk = InpBaseRisk * globalRiskMultiplier * confidence;
   double risk = balance * baseRisk / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = risk / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

void ManageOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double atr = CalculateATR(14);
      double profit = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                      (currentPrice - openPrice) : (openPrice - currentPrice);
      
      double profitATR = profit / atr;
      
      if(profitATR > 1.2)
      {
         double newSL = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                        currentPrice - atr * 0.6 : currentPrice + atr * 0.6;
         
         double currentSL = PositionGetDouble(POSITION_SL);
         bool shouldUpdate = false;
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL > currentSL)
            shouldUpdate = true;
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && (currentSL == 0 || newSL < currentSL))
            shouldUpdate = true;
         
         if(shouldUpdate)
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
      
      if(profitATR < -0.8 && currentDrawdown > 12)
      {
         trade.PositionClose(ticket);
         Print("Emergency close due to drawdown: ", currentDrawdown, "%");
      }
   }
}

void UpdateMarketMemory()
{
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double atr = CalculateATR(14);
   
   for(int i = 0; i < supportCount; i++)
   {
      if(MathAbs(close - supportLevels[i].priceLevel) < atr * 0.2)
      {
         supportLevels[i].touchCount++;
         supportLevels[i].lastTouch = TimeCurrent();
         
         if(close < supportLevels[i].priceLevel)
            supportLevels[i].isBroken = true;
      }
   }
   
   for(int i = 0; i < resistanceCount; i++)
   {
      if(MathAbs(close - resistanceLevels[i].priceLevel) < atr * 0.2)
      {
         resistanceLevels[i].touchCount++;
         resistanceLevels[i].lastTouch = TimeCurrent();
         
         if(close > resistanceLevels[i].priceLevel)
            resistanceLevels[i].isBroken = true;
      }
   }
   
   if(totalTrades % 10 == 0)
   {
      supportCount = 0;
      resistanceCount = 0;
      
      for(int i = 5; i <= 50; i += 5)
      {
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         if(supportCount < 20)
         {
            supportLevels[supportCount].priceLevel = low;
            supportLevels[supportCount].touchCount = 1;
            supportLevels[supportCount].isBroken = false;
            supportCount++;
         }
         
         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         if(resistanceCount < 20)
         {
            resistanceLevels[resistanceCount].priceLevel = high;
            resistanceLevels[resistanceCount].touchCount = 1;
            resistanceLevels[resistanceCount].isBroken = false;
            resistanceCount++;
         }
      }
   }
}

double FindIntelligentSupport(int bars)
{
   double bestSupport = 0;
   int maxTouches = 0;
   
   for(int i = 0; i < supportCount; i++)
   {
      if(!supportLevels[i].isBroken && supportLevels[i].touchCount > maxTouches)
      {
         maxTouches = supportLevels[i].touchCount;
         bestSupport = supportLevels[i].priceLevel;
      }
   }
   
   if(bestSupport == 0)
   {
      bestSupport = iLow(_Symbol, PERIOD_CURRENT, 1);
      for(int i = 2; i <= bars; i++)
      {
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         if(low < bestSupport) bestSupport = low;
      }
   }
   
   return bestSupport;
}

double FindIntelligentResistance(int bars)
{
   double bestResistance = 0;
   int maxTouches = 0;
   
   for(int i = 0; i < resistanceCount; i++)
   {
      if(!resistanceLevels[i].isBroken && resistanceLevels[i].touchCount > maxTouches)
      {
         maxTouches = resistanceLevels[i].touchCount;
         bestResistance = resistanceLevels[i].priceLevel;
      }
   }
   
   if(bestResistance == 0)
   {
      bestResistance = iHigh(_Symbol, PERIOD_CURRENT, 1);
      for(int i = 2; i <= bars; i++)
      {
         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         if(high > bestResistance) bestResistance = high;
      }
   }
   
   return bestResistance;
}

double AnalyzeReaction(double level, bool isSupport)
{
   double strength = 0;
   int reactions = 0;
   
   for(int i = 1; i <= 20; i++)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      double open = iOpen(_Symbol, PERIOD_CURRENT, i);
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      
      if(isSupport && low <= level * 1.001 && close > open)
      {
         strength += (close - low) / (high - low);
         reactions++;
      }
      else if(!isSupport && high >= level * 0.999 && close < open)
      {
         strength += (high - close) / (high - low);
         reactions++;
      }
   }
   
   return (reactions > 0) ? strength / reactions : 0;
}

double FindSwingExtreme(int bars, bool findHigh)
{
   double extreme = findHigh ? 0 : 999999;
   
   for(int i = 3; i <= bars; i++)
   {
      double price = findHigh ? iHigh(_Symbol, PERIOD_CURRENT, i) : iLow(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      for(int j = i - 2; j <= i + 2; j++)
      {
         if(j == i || j < 1) continue;
         double comparePrice = findHigh ? iHigh(_Symbol, PERIOD_CURRENT, j) : iLow(_Symbol, PERIOD_CURRENT, j);
         
         if(findHigh && comparePrice > price)
         {
            isSwing = false;
            break;
         }
         else if(!findHigh && comparePrice < price)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing)
      {
         if(findHigh && price > extreme) extreme = price;
         else if(!findHigh && price < extreme) extreme = price;
      }
   }
   
   return extreme;
}

double FindRangeExtreme(int bars, bool findHigh)
{
   double sum = 0;
   int count = 0;
   
   for(int i = 1; i <= bars; i++)
   {
      double price = findHigh ? iHigh(_Symbol, PERIOD_CURRENT, i) : iLow(_Symbol, PERIOD_CURRENT, i);
      sum += price;
      count++;
   }
   
   double avg = sum / count;
   double extreme = findHigh ? 0 : 999999;
   
   for(int i = 1; i <= bars; i++)
   {
      double price = findHigh ? iHigh(_Symbol, PERIOD_CURRENT, i) : iLow(_Symbol, PERIOD_CURRENT, i);
      
      if(findHigh && price > avg && price > extreme)
         extreme = price;
      else if(!findHigh && price < avg && price < extreme)
         extreme = price;
   }
   
   return extreme;
}

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

double CalculateSMA(int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, PERIOD_CURRENT, i);
   return sum / period;
}
//+------------------------------------------------------------------+
