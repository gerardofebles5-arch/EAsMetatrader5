//+------------------------------------------------------------------+
//|                                            ELITE_TRADER_EA.mq5   |
//|                        Professional Grade Trading System          |
//+------------------------------------------------------------------+
#property copyright "Elite Trading System"
#property version   "1.00"

#include <Trade\Trade.mqh>

input double InpRiskPercent = 0.5;
input int    InpMagic = 100100;

CTrade trade;
datetime lastBar = 0;

double peakBalance = 0;
int winStreak = 0;
int lossStreak = 0;
double riskMultiplier = 1.0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("ELITE TRADER: System activated");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;
   
   LearnAndAdapt();
   
   if(PositionsTotal() > 0)
   {
      ManagePosition();
      return;
   }
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = (peakBalance - balance) / peakBalance * 100;
   
   if(drawdown > 15 || lossStreak >= 3) return;
   
   int signal = AnalyzeMarket();
   
   if(signal == 1)
      ExecuteBuy();
   else if(signal == -1)
      ExecuteSell();
}

//+------------------------------------------------------------------+
void LearnAndAdapt()
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
               winStreak++;
               lossStreak = 0;
               riskMultiplier = MathMin(1.2, riskMultiplier * 1.05);
            }
            else
            {
               lossStreak++;
               winStreak = 0;
               riskMultiplier = MathMax(0.3, riskMultiplier * 0.75);
            }
            
            lastTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
int AnalyzeMarket()
{
   double atr = CalculateATR(14);
   double atrSlow = CalculateATR(50);
   
   if(atr < atrSlow * 0.6) return 0;
   
   double sma20 = CalculateSMA(20);
   double sma50 = CalculateSMA(50);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   bool strongUptrend = (sma20 > sma50 && close > sma20 && sma20 - sma50 > atr * 0.5);
   bool strongDowntrend = (sma20 < sma50 && close < sma20 && sma50 - sma20 > atr * 0.5);
   
   if(!strongUptrend && !strongDowntrend) return 0;
   
   long vol = iVolume(_Symbol, PERIOD_CURRENT, 1);
   long avgVol = 0;
   for(int i = 2; i <= 10; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= 9;
   
   bool volumeConfirm = (vol > avgVol * 1.2);
   
   if(strongUptrend)
   {
      double support = FindKeyLevel(true, 20);
      double low = iLow(_Symbol, PERIOD_CURRENT, 1);
      
      if(low <= support + atr * 0.3 && close > low && volumeConfirm)
      {
         double wickSize = close - low;
         double bodySize = MathAbs(close - iOpen(_Symbol, PERIOD_CURRENT, 1));
         
         if(wickSize > bodySize * 0.5 || close > close2)
            return 1;
      }
   }
   
   if(strongDowntrend)
   {
      double resistance = FindKeyLevel(false, 20);
      double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
      
      if(high >= resistance - atr * 0.3 && close < high && volumeConfirm)
      {
         double wickSize = high - close;
         double bodySize = MathAbs(close - iOpen(_Symbol, PERIOD_CURRENT, 1));
         
         if(wickSize > bodySize * 0.5 || close < close2)
            return -1;
      }
   }
   
   return 0;
}

double FindKeyLevel(bool findSupport, int bars)
{
   double level = findSupport ? 999999 : 0;
   int touches = 0;
   double atr = CalculateATR(14);
   
   for(int i = 1; i <= bars; i++)
   {
      double price = findSupport ? iLow(_Symbol, PERIOD_CURRENT, i) : iHigh(_Symbol, PERIOD_CURRENT, i);
      
      int localTouches = 0;
      for(int j = 1; j <= bars; j++)
      {
         double testPrice = findSupport ? iLow(_Symbol, PERIOD_CURRENT, j) : iHigh(_Symbol, PERIOD_CURRENT, j);
         if(MathAbs(testPrice - price) < atr * 0.1)
            localTouches++;
      }
      
      if(localTouches > touches)
      {
         touches = localTouches;
         level = price;
      }
   }
   
   return level;
}

void ExecuteBuy()
{
   double atr = CalculateATR(14);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double sl = ask - atr * 1.0;
   double tp = ask + atr * 2.5;
   
   double lots = CalculateLots(atr * 1.0);
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ELITE_BUY"))
      Print("BUY: Risk=", riskMultiplier, " Lots=", lots);
}

void ExecuteSell()
{
   double atr = CalculateATR(14);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = bid + atr * 1.0;
   double tp = bid - atr * 2.5;
   
   double lots = CalculateLots(atr * 1.0);
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ELITE_SELL"))
      Print("SELL: Risk=", riskMultiplier, " Lots=", lots);
}

double CalculateLots(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * InpRiskPercent * riskMultiplier / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = risk / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

void ManagePosition()
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
      
      if(profit > atr * 1.0)
      {
         double newSL = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                        currentPrice - atr * 0.5 : currentPrice + atr * 0.5;
         
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

double CalculateSMA(int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, PERIOD_CURRENT, i);
   return sum / period;
}
//+------------------------------------------------------------------+
