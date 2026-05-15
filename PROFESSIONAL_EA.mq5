//+------------------------------------------------------------------+
//|                                          PROFESSIONAL_EA.mq5     |
//|                        Real Professional Trading System           |
//+------------------------------------------------------------------+
#property copyright "Professional Trading"
#property version   "1.00"

#include <Trade\Trade.mqh>

input double InpRisk = 0.5;
input int    InpMagic = 777888;

CTrade trade;
datetime lastBar = 0;

double peakBalance = 0;
int totalWins = 0;
int totalLosses = 0;
double riskFactor = 1.0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("PROFESSIONAL EA: Activated");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   UpdatePerformance();
   
   if(PositionsTotal() > 0)
   {
      ManageActivePosition();
      return;
   }
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd = (peakBalance - balance) / peakBalance * 100;
   
   if(dd > 15) return;
   
   int signal = GetProfessionalSignal();
   
   if(signal == 1)
      OpenBuy();
   else if(signal == -1)
      OpenSell();
}

//+------------------------------------------------------------------+
void UpdatePerformance()
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
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            if(balance > peakBalance) peakBalance = balance;
            
            if(profit > 0)
            {
               totalWins++;
               riskFactor = MathMin(1.15, riskFactor * 1.03);
            }
            else
            {
               totalLosses++;
               riskFactor = MathMax(0.35, riskFactor * 0.80);
            }
            
            lastTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
int GetProfessionalSignal()
{
   double atr = CalculateATR(14);
   double atr50 = CalculateATR(50);
   
   if(atr < atr50 * 0.7) return 0;
   
   double ema9 = CalculateEMA(9);
   double ema21 = CalculateEMA(21);
   double ema50 = CalculateEMA(50);
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   
   bool bullishTrend = (ema9 > ema21 && ema21 > ema50 && close > ema9);
   bool bearishTrend = (ema9 < ema21 && ema21 < ema50 && close < ema9);
   
   if(!bullishTrend && !bearishTrend) return 0;
   
   long vol = iVolume(_Symbol, PERIOD_CURRENT, 1);
   long avgVol = 0;
   for(int i = 2; i <= 15; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= 14;
   
   if(vol < avgVol * 1.1) return 0;
   
   if(bullishTrend)
   {
      double swingLow = FindSwingLow(15);
      
      if(low <= swingLow * 1.002)
      {
         double lowerWick = MathMin(close, open) - low;
         double bodySize = MathAbs(close - open);
         double totalSize = high - low;
         
         if(lowerWick > bodySize && lowerWick > totalSize * 0.5 && close > open)
            return 1;
         
         if(close > close2 && close > ema9)
            return 1;
      }
      
      if(close2 < ema21 && close > ema21 && close > open)
         return 1;
   }
   
   if(bearishTrend)
   {
      double swingHigh = FindSwingHigh(15);
      
      if(high >= swingHigh * 0.998)
      {
         double upperWick = high - MathMax(close, open);
         double bodySize = MathAbs(close - open);
         double totalSize = high - low;
         
         if(upperWick > bodySize && upperWick > totalSize * 0.5 && close < open)
            return -1;
         
         if(close < close2 && close < ema9)
            return -1;
      }
      
      if(close2 > ema21 && close < ema21 && close < open)
         return -1;
   }
   
   return 0;
}

double FindSwingLow(int bars)
{
   double lowest = 999999;
   
   for(int i = 3; i <= bars; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      for(int j = i - 2; j <= i + 2; j++)
      {
         if(j == i || j < 1) continue;
         if(iLow(_Symbol, PERIOD_CURRENT, j) < low)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && low < lowest)
         lowest = low;
   }
   
   return lowest;
}

double FindSwingHigh(int bars)
{
   double highest = 0;
   
   for(int i = 3; i <= bars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      for(int j = i - 2; j <= i + 2; j++)
      {
         if(j == i || j < 1) continue;
         if(iHigh(_Symbol, PERIOD_CURRENT, j) > high)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && high > highest)
         highest = high;
   }
   
   return highest;
}

void OpenBuy()
{
   double atr = CalculateATR(14);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double sl = ask - atr * 0.9;
   double tp = ask + atr * 2.2;
   
   double lots = CalculateLots(atr * 0.9);
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "PRO_BUY"))
   {
      int total = totalWins + totalLosses;
      double wr = (total > 0) ? (double)totalWins / total * 100 : 0;
      Print("BUY: WR=", DoubleToString(wr, 1), "% Risk=", DoubleToString(riskFactor, 2), " Lots=", lots);
   }
}

void OpenSell()
{
   double atr = CalculateATR(14);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = bid + atr * 0.9;
   double tp = bid - atr * 2.2;
   
   double lots = CalculateLots(atr * 0.9);
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "PRO_SELL"))
   {
      int total = totalWins + totalLosses;
      double wr = (total > 0) ? (double)totalWins / total * 100 : 0;
      Print("SELL: WR=", DoubleToString(wr, 1), "% Risk=", DoubleToString(riskFactor, 2), " Lots=", lots);
   }
}

double CalculateLots(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * InpRisk * riskFactor / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = risk / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

void ManageActivePosition()
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
      
      if(profit > atr * 0.8)
      {
         double newSL = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                        currentPrice - atr * 0.4 : currentPrice + atr * 0.4;
         
         double currentSL = PositionGetDouble(POSITION_SL);
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL > currentSL)
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && (currentSL == 0 || newSL < currentSL))
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
   }
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

double CalculateEMA(int period)
{
   double multiplier = 2.0 / (period + 1);
   double ema = iClose(_Symbol, PERIOD_CURRENT, period);
   
   for(int i = period - 1; i >= 1; i--)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      ema = (close - ema) * multiplier + ema;
   }
   
   return ema;
}
//+------------------------------------------------------------------+
