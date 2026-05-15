//+------------------------------------------------------------------+
//|                         XAUUSD_V17_0_ULTIMATE.mq5                |
//|                    SISTEMA ULTIMATE - MÁXIMA SIMPLICIDAD         |
//+------------------------------------------------------------------+
#property copyright "Ultimate System V17.0"
#property version   "17.00"
#property strict

#include <Trade\Trade.mqh>

input group "=== RIESGO ==="
input double InpRiskPercent = 1.0;
input double InpMaxDailyDD = 4.0;
input double InpMaxWeeklyDD = 8.0;

input group "=== SESIÓN ==="
input int InpSessionStart = 8;
input int InpSessionEnd = 17;
input int InpGMTOffset = 0;

input group "=== BREAKOUT ==="
input int InpLookbackBars = 10;
input double InpSL_Pips = 40;
input double InpTP_Pips = 60;
input double InpBreakeven_Pips = 30;

input group "=== FILTROS ==="
input int InpEMA200Period = 200;
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;
input double InpMinATRPips = 15;
input int InpMaxTradesPerDay = 3;

input group "=== AVANZADO ==="
input int InpMagicNumber = 170001;

CTrade trade;
int emaHandle, atrHandle;
double emaBuffer[], atrBuffer[];

datetime lastBarTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;

double dailyStartBalance = 0;
double weeklyStartBalance = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;
bool dailyLimitReached = false;
bool weeklyLimitReached = false;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_M15, 14);
   
   if(emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) {
      Print("Error indicadores");
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   Print("V17.0 ULTIMATE - Breakout ", InpLookbackBars, " velas | SL:", InpSL_Pips, " TP:", InpTP_Pips);
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   CheckDrawdownLimits();
   if(dailyLimitReached || weeklyLimitReached) return;
   
   ResetDailyCounters();
   
   if(tradesToday >= InpMaxTradesPerDay) return;
   if(!IsTradingSession()) return;
   
   ManageOpenPositions();
   
   if(PositionsTotal() > 0) return;
   
   if(!UpdateIndicators()) return;
   if(!CheckATRFilter()) return;
   
   CheckBreakout();
   
   UpdateComment();
}

bool UpdateIndicators()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, emaBuffer) < 2) return false;
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) < 1) return false;
   return true;
}

bool IsTradingSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour + InpGMTOffset;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   return (currentHour >= InpSessionStart && currentHour < InpSessionEnd);
}

bool CheckATRFilter()
{
   double atr = atrBuffer[0];
   double atrPips = atr / (_Point * 10);
   return (atrPips >= InpMinATRPips);
}

void CheckBreakout()
{
   double highest = 0;
   double lowest = DBL_MAX;
   
   for(int i = 2; i <= InpLookbackBars + 1; i++) {
      double high = iHigh(_Symbol, PERIOD_M15, i);
      double low = iLow(_Symbol, PERIOD_M15, i);
      
      if(high > highest) highest = high;
      if(low < lowest) lowest = low;
   }
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   if(high1 > highest && close1 > highest) {
      if(close1 > emaBuffer[0]) {
         Print("BREAKOUT ALCISTA");
         OpenTrade(ORDER_TYPE_BUY);
      }
   }
   
   if(low1 < lowest && close1 < lowest) {
      if(close1 < emaBuffer[0]) {
         Print("BREAKOUT BAJISTA");
         OpenTrade(ORDER_TYPE_SELL);
      }
   }
}

void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double entryPrice, sl, tp;
   double slDistance = InpSL_Pips * point * 10;
   double tpDistance = InpTP_Pips * point * 10;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + tpDistance, _Digits);
   }
   else {
      entryPrice = bid;
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - tpDistance, _Digits);
   }
   
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slPips = InpSL_Pips * 10;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   bool success = false;
   if(orderType == ORDER_TYPE_BUY) {
      success = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, "V17");
   }
   else {
      success = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, "V17");
   }
   
   if(success) {
      tradesToday++;
      lastTradeDate = TimeCurrent();
      Print("Trade abierto: ", (orderType == ORDER_TYPE_BUY) ? "LONG" : "SHORT");
   }
}

double CalculateLotSize(double riskAmount, double slPips)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slInTicks = slPips * point / tickSize;
   double lotSize = riskAmount / (slInTicks * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      MoveToBreakeven(ticket);
   }
}

void MoveToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double breakevenDistance = InpBreakeven_Pips * _Point * 10;
   
   if(MathAbs(posSL - posOpenPrice) < 10 * _Point) return;
   
   bool shouldMoveBE = false;
   
   if(posType == POSITION_TYPE_BUY) {
      if(currentPrice >= posOpenPrice + breakevenDistance)
         shouldMoveBE = true;
   }
   else {
      if(currentPrice <= posOpenPrice - breakevenDistance)
         shouldMoveBE = true;
   }
   
   if(shouldMoveBE) {
      double newSL = NormalizeDouble(posOpenPrice + (1 * _Point * ((posType == POSITION_TYPE_BUY) ? 1 : -1)), _Digits);
      trade.PositionModify(ticket, newSL, posTP);
   }
}

void CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   MqlDateTime lastDayStruct;
   TimeToStruct(lastDayCheck, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      dailyStartBalance = currentBalance;
      lastDayCheck = TimeCurrent();
      dailyLimitReached = false;
   }
   
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartBalance = currentBalance;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
   }
   
   double currentDailyDD = 0;
   double currentWeeklyDD = 0;
   
   if(dailyStartBalance > 0)
      currentDailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   if(weeklyStartBalance > 0)
      currentWeeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   if(currentDailyDD >= InpMaxDailyDD && !dailyLimitReached) {
      dailyLimitReached = true;
   }
   
   if(currentWeeklyDD >= InpMaxWeeklyDD && !weeklyLimitReached) {
      weeklyLimitReached = true;
   }
}

void ResetDailyCounters()
{
   MqlDateTime currentTime, lastTradeTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastTradeDate, lastTradeTime);
   
   if(currentTime.day != lastTradeTime.day) {
      tradesToday = 0;
   }
}

void UpdateComment()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double currentDailyDD = 0;
   if(dailyStartBalance > 0)
      currentDailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   string status = "ACTIVO";
   if(dailyLimitReached) status = "DD DIARIO";
   else if(weeklyLimitReached) status = "DD SEMANAL";
   else if(tradesToday >= InpMaxTradesPerDay) status = "LIMITE";
   else if(!IsTradingSession()) status = "FUERA SESION";
   
   string comment = StringFormat(
      "V17.0 ULTIMATE\n" +
      "Estado: %s\n" +
      "Trades: %d/%d\n" +
      "DD: %.2f%%\n" +
      "Balance: $%.2f\n" +
      "Equity: $%.2f",
      status,
      tradesToday, InpMaxTradesPerDay,
      currentDailyDD,
      currentBalance,
      equity
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+
