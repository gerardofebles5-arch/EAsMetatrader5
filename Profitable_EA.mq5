//+------------------------------------------------------------------+
//|                                                Profitable_EA.mq5  |
//|                                      Algoritmo Rentable de Trading|
//+------------------------------------------------------------------+
#property copyright "Profitable Trading System"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Input Parameters
input double InpRiskPercent = 1.0;        // Risk per trade %
input int    InpStopLoss = 30;            // Stop Loss pips
input int    InpTakeProfit = 90;          // Take Profit pips
input int    InpEMAFast = 9;              // Fast EMA
input int    InpEMASlow = 21;             // Slow EMA
input int    InpRSI = 14;                 // RSI Period
input int    InpMagic = 123456;           // Magic Number

//--- Global Variables
CTrade trade;
int emaFastHandle, emaSlowHandle, rsiHandle;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   
   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRSI, PRICE_CLOSE);
   
   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   Print("Profitable EA initialized");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   if(PositionsTotal() > 0) return;
   
   double emaFast[], emaSlow[], rsi[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(emaFastHandle, 0, 0, 3, emaFast) < 3) return;
   if(CopyBuffer(emaSlowHandle, 0, 0, 3, emaSlow) < 3) return;
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 3) return;
   
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   // Buy Signal
   if(emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2] && rsi[1] < 70 && close1 > emaFast[1])
   {
      OpenBuy();
   }
   // Sell Signal
   else if(emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2] && rsi[1] > 30 && close1 < emaFast[1])
   {
      OpenSell();
   }
}

//+------------------------------------------------------------------+
double CalculateLots()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * InpRiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slPoints = InpStopLoss * 10 * point;
   double lots = risk / (slPoints * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   return lots;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl = ask - InpStopLoss * 10 * point;
   double tp = ask + InpTakeProfit * 10 * point;
   double lots = CalculateLots();
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ProfitableEA"))
   {
      Print("BUY opened: ", lots, " lots");
   }
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl = bid + InpStopLoss * 10 * point;
   double tp = bid - InpTakeProfit * 10 * point;
   double lots = CalculateLots();
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ProfitableEA"))
   {
      Print("SELL opened: ", lots, " lots");
   }
}
//+------------------------------------------------------------------+
