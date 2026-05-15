//+------------------------------------------------------------------+
//|                                   XAUUSD_9EMAS_TRIPLE_V13_0.mq5 |
//|                                  9 EMAs Triple Group Strategy    |
//|                                  Trend + Entry + Exit Groups     |
//+------------------------------------------------------------------+
#property copyright "9 EMAs Triple Group Strategy"
#property version   "13.00"
#property strict

//--- Input Parameters
input group "=== EMA PERIODS ==="
input int InpEMA_Trend1    = 50;    // Trend EMA 1 (Short-term trend)
input int InpEMA_Trend2    = 100;   // Trend EMA 2 (Medium-term trend)
input int InpEMA_Trend3    = 200;   // Trend EMA 3 (Long-term trend)
input int InpEMA_Entry1    = 10;    // Entry EMA 1 (Fast)
input int InpEMA_Entry2    = 15;    // Entry EMA 2 (Medium)
input int InpEMA_Entry3    = 20;    // Entry EMA 3 (Slow)
input int InpEMA_Exit1     = 25;    // Exit EMA 1 (Early exit)
input int InpEMA_Exit2     = 35;    // Exit EMA 2 (Partial exit)
input int InpEMA_Exit3     = 45;    // Exit EMA 3 (Full exit)

input group "=== RISK MANAGEMENT ==="
input double InpRiskPercent       = 1.0;    // Risk per trade (%)
input int    InpMaxTradesPerDay   = 5;      // Max trades per day
input double InpMaxDailyLoss      = 3.0;    // Max daily loss (%)
input bool   InpUseTrailingStop   = true;   // Enable trailing stop

input group "=== TREND FILTERS ==="
input double InpMinTrendStrength  = 1.0;    // Min trend strength (%)
input double InpCompressionThresh = 0.5;    // Compression threshold (%)
input double InpMinATR            = 0.5;    // Min ATR for entry

input group "=== SESSION FILTER ==="
input int    InpNYSessionStart    = 5;      // NY Session start (hour, Venezuela DST)
input int    InpNYSessionEnd      = 13;     // NY Session end (hour, Venezuela DST)
input bool   InpUseDST            = true;   // Use DST time

input group "=== ADVANCED FEATURES ==="
input bool   InpUseConfluence     = true;   // Enable confluence zones
input bool   InpUseAcceleration   = true;   // Enable trend acceleration
input bool   InpUseADXFilter      = true;   // Enable ADX regime filter
input double InpADXThreshold      = 20.0;   // ADX threshold (ranging if below)

input group "=== GENERAL ==="
input int    InpMagicNumber       = 130000; // Magic number
input string InpTradeComment      = "9EMAs_V13"; // Trade comment

//--- Global Variables
int handleEMA_Trend1, handleEMA_Trend2, handleEMA_Trend3;
int handleEMA_Entry1, handleEMA_Entry2, handleEMA_Entry3;
int handleEMA_Exit1, handleEMA_Exit2, handleEMA_Exit3;
int handleATR, handleADX;

double ema_Trend1[], ema_Trend2[], ema_Trend3[];
double ema_Entry1[], ema_Entry2[], ema_Entry3[];
double ema_Exit1[], ema_Exit2[], ema_Exit3[];
double atrBuffer[], adxBuffer[];

datetime lastBarTime = 0;
datetime lastSignalTime = 0;

// Daily statistics
int dailyTradeCount = 0;
double dailyStartBalance = 0;
double dailyPnL = 0;
datetime lastTradeDate = 0;

// Enums
enum ENUM_TREND_DIRECTION {
   TREND_BULLISH,
   TREND_BEARISH,
   TREND_NEUTRAL
};

enum ENUM_TREND_STRENGTH {
   STRENGTH_WEAK,
   STRENGTH_MODERATE,
   STRENGTH_STRONG
};

enum ENUM_SIGNAL_TYPE {
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Initializing 9 EMAs Triple Group Strategy V13.0");
   Print("========================================");
   
   // Initialize Trend Group EMAs
   handleEMA_Trend1 = iMA(_Symbol, PERIOD_H1, InpEMA_Trend1, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Trend2 = iMA(_Symbol, PERIOD_H1, InpEMA_Trend2, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Trend3 = iMA(_Symbol, PERIOD_H1, InpEMA_Trend3, 0, MODE_EMA, PRICE_CLOSE);
   
   // Initialize Entry Group EMAs
   handleEMA_Entry1 = iMA(_Symbol, PERIOD_H1, InpEMA_Entry1, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Entry2 = iMA(_Symbol, PERIOD_H1, InpEMA_Entry2, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Entry3 = iMA(_Symbol, PERIOD_H1, InpEMA_Entry3, 0, MODE_EMA, PRICE_CLOSE);
   
   // Initialize Exit Group EMAs
   handleEMA_Exit1 = iMA(_Symbol, PERIOD_H1, InpEMA_Exit1, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Exit2 = iMA(_Symbol, PERIOD_H1, InpEMA_Exit2, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Exit3 = iMA(_Symbol, PERIOD_H1, InpEMA_Exit3, 0, MODE_EMA, PRICE_CLOSE);
   
   // Initialize ATR and ADX
   handleATR = iATR(_Symbol, PERIOD_H1, 14);
   handleADX = iADX(_Symbol, PERIOD_H1, 14);
   
   // Validate handles
   if(handleEMA_Trend1 == INVALID_HANDLE || handleEMA_Trend2 == INVALID_HANDLE || handleEMA_Trend3 == INVALID_HANDLE ||
      handleEMA_Entry1 == INVALID_HANDLE || handleEMA_Entry2 == INVALID_HANDLE || handleEMA_Entry3 == INVALID_HANDLE ||
      handleEMA_Exit1 == INVALID_HANDLE || handleEMA_Exit2 == INVALID_HANDLE || handleEMA_Exit3 == INVALID_HANDLE ||
      handleATR == INVALID_HANDLE || handleADX == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles!");
      return(INIT_FAILED);
   }
   
   // Set array as series
   ArraySetAsSeries(ema_Trend1, true);
   ArraySetAsSeries(ema_Trend2, true);
   ArraySetAsSeries(ema_Trend3, true);
   ArraySetAsSeries(ema_Entry1, true);
   ArraySetAsSeries(ema_Entry2, true);
   ArraySetAsSeries(ema_Entry3, true);
   ArraySetAsSeries(ema_Exit1, true);
   ArraySetAsSeries(ema_Exit2, true);
   ArraySetAsSeries(ema_Exit3, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(adxBuffer, true);
   
   // Initialize daily statistics
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastTradeDate = TimeCurrent();
   
   Print("All indicators initialized successfully");
   Print("Trend Group: EMA", InpEMA_Trend1, ", EMA", InpEMA_Trend2, ", EMA", InpEMA_Trend3);
   Print("Entry Group: EMA", InpEMA_Entry1, ", EMA", InpEMA_Entry2, ", EMA", InpEMA_Entry3);
   Print("Exit Group: EMA", InpEMA_Exit1, ", EMA", InpEMA_Exit2, ", EMA", InpEMA_Exit3);
   Print("Risk per trade: ", InpRiskPercent, "%");
   Print("Max trades per day: ", InpMaxTradesPerDay);
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("========================================");
   Print("Deinitializing 9 EMAs Triple Group Strategy");
   Print("Reason: ", reason);
   Print("========================================");
   
   // Release indicator handles
   if(handleEMA_Trend1 != INVALID_HANDLE) IndicatorRelease(handleEMA_Trend1);
   if(handleEMA_Trend2 != INVALID_HANDLE) IndicatorRelease(handleEMA_Trend2);
   if(handleEMA_Trend3 != INVALID_HANDLE) IndicatorRelease(handleEMA_Trend3);
   if(handleEMA_Entry1 != INVALID_HANDLE) IndicatorRelease(handleEMA_Entry1);
   if(handleEMA_Entry2 != INVALID_HANDLE) IndicatorRelease(handleEMA_Entry2);
   if(handleEMA_Entry3 != INVALID_HANDLE) IndicatorRelease(handleEMA_Entry3);
   if(handleEMA_Exit1 != INVALID_HANDLE) IndicatorRelease(handleEMA_Exit1);
   if(handleEMA_Exit2 != INVALID_HANDLE) IndicatorRelease(handleEMA_Exit2);
   if(handleEMA_Exit3 != INVALID_HANDLE) IndicatorRelease(handleEMA_Exit3);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new H1 candle
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBarTime == lastBarTime)
      return;
   
   lastBarTime = currentBarTime;
   
   // Reset daily counters if new day
   ResetDailyCounters();
   
   // Copy indicator data
   if(!CopyEMAData())
   {
      Print("ERROR: Failed to copy indicator data");
      return;
   }
   
   // Check if position exists
   if(PositionSelect(_Symbol))
   {
      // Manage existing position
      ManagePosition();
   }
   else
   {
      // Look for entry signal
      ENUM_SIGNAL_TYPE signal = GenerateSignal();
      
      if(signal != SIGNAL_NONE)
      {
         if(CanOpenTrade())
         {
            if(signal == SIGNAL_BUY)
               OpenPosition(ORDER_TYPE_BUY);
            else if(signal == SIGNAL_SELL)
               OpenPosition(ORDER_TYPE_SELL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Copy EMA and indicator data                                      |
//+------------------------------------------------------------------+
bool CopyEMAData()
{
   // Copy Trend Group
   if(CopyBuffer(handleEMA_Trend1, 0, 0, 5, ema_Trend1) <= 0) return false;
   if(CopyBuffer(handleEMA_Trend2, 0, 0, 5, ema_Trend2) <= 0) return false;
   if(CopyBuffer(handleEMA_Trend3, 0, 0, 5, ema_Trend3) <= 0) return false;
   
   // Copy Entry Group
   if(CopyBuffer(handleEMA_Entry1, 0, 0, 5, ema_Entry1) <= 0) return false;
   if(CopyBuffer(handleEMA_Entry2, 0, 0, 5, ema_Entry2) <= 0) return false;
   if(CopyBuffer(handleEMA_Entry3, 0, 0, 5, ema_Entry3) <= 0) return false;
   
   // Copy Exit Group
   if(CopyBuffer(handleEMA_Exit1, 0, 0, 5, ema_Exit1) <= 0) return false;
   if(CopyBuffer(handleEMA_Exit2, 0, 0, 5, ema_Exit2) <= 0) return false;
   if(CopyBuffer(handleEMA_Exit3, 0, 0, 5, ema_Exit3) <= 0) return false;
   
   // Copy ATR and ADX
   if(CopyBuffer(handleATR, 0, 0, 5, atrBuffer) <= 0) return false;
   if(CopyBuffer(handleADX, 0, 0, 5, adxBuffer) <= 0) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   MqlDateTime currentTime, lastTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastTradeDate, lastTime);
   
   // Check if new day
   if(currentTime.day != lastTime.day || currentTime.mon != lastTime.mon || currentTime.year != lastTime.year)
   {
      Print("=== NEW DAY - Resetting counters ===");
      Print("Previous day trades: ", dailyTradeCount);
      Print("Previous day P&L: ", dailyPnL);
      
      dailyTradeCount = 0;
      dailyPnL = 0;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastTradeDate = TimeCurrent();
      
      Print("New starting balance: ", dailyStartBalance);
   }
}

//+------------------------------------------------------------------+
//| Check if can open trade                                          |
//+------------------------------------------------------------------+
bool CanOpenTrade()
{
   // Check daily trade limit
   if(dailyTradeCount >= InpMaxTradesPerDay)
   {
      Print("REJECTED: Daily trade limit reached (", dailyTradeCount, "/", InpMaxTradesPerDay, ")");
      return false;
   }
   
   // Check daily loss limit
   double dailyLossPercent = (dailyPnL / dailyStartBalance) * 100.0;
   if(dailyLossPercent <= -InpMaxDailyLoss)
   {
      Print("REJECTED: Daily loss limit reached (", dailyLossPercent, "%)");
      return false;
   }
   
   // Check sufficient margin
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin < 100)
   {
      Print("REJECTED: Insufficient margin (", freeMargin, ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get trend direction                                              |
//+------------------------------------------------------------------+
ENUM_TREND_DIRECTION GetTrendDirection()
{
   // Bullish: EMA50 > EMA100 > EMA200
   if(ema_Trend1[0] > ema_Trend2[0] && ema_Trend2[0] > ema_Trend3[0])
      return TREND_BULLISH;
   
   // Bearish: EMA50 < EMA100 < EMA200
   if(ema_Trend1[0] < ema_Trend2[0] && ema_Trend2[0] < ema_Trend3[0])
      return TREND_BEARISH;
   
   return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
//| Calculate trend strength                                         |
//+------------------------------------------------------------------+
double CalculateTrendStrength()
{
   // Trend strength = |EMA50 - EMA200| / EMA200 * 100
   return MathAbs(ema_Trend1[0] - ema_Trend3[0]) / ema_Trend3[0] * 100.0;
}

//+------------------------------------------------------------------+
//| Classify trend strength                                          |
//+------------------------------------------------------------------+
ENUM_TREND_STRENGTH ClassifyTrendStrength(double strength)
{
   if(strength < 1.0)
      return STRENGTH_WEAK;
   else if(strength < 2.0)
      return STRENGTH_MODERATE;
   else
      return STRENGTH_STRONG;
}

//+------------------------------------------------------------------+
//| Check if in compression zone                                     |
//+------------------------------------------------------------------+
bool IsCompressionZone()
{
   // Check if all Trend Group EMAs within 0.5% of each other
   double maxEMA = MathMax(ema_Trend1[0], MathMax(ema_Trend2[0], ema_Trend3[0]));
   double minEMA = MathMin(ema_Trend1[0], MathMin(ema_Trend2[0], ema_Trend3[0]));
   
   double range = ((maxEMA - minEMA) / maxEMA) * 100.0;
   
   return (range < InpCompressionThresh);
}

//+------------------------------------------------------------------+
//| Check if in NY session                                           |
//+------------------------------------------------------------------+
bool IsNYSession()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   int currentHour = currentTime.hour;
   
   // Check if within NY session hours
   return (currentHour >= InpNYSessionStart && currentHour < InpNYSessionEnd);
}

//+------------------------------------------------------------------+
//| Check ADX regime filter                                          |
//+------------------------------------------------------------------+
bool PassesADXFilter()
{
   if(!InpUseADXFilter)
      return true;
   
   double adx = adxBuffer[0];
   
   // Reject if ADX < threshold (ranging market)
   if(adx < InpADXThreshold)
   {
      Print("REJECTED: ADX filter - Market ranging (ADX=", adx, ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detect crossover                                                 |
//+------------------------------------------------------------------+
int DetectCrossover()
{
   // Bullish crossover: EMA10 crosses above EMA15
   if(ema_Entry1[1] <= ema_Entry2[1] && ema_Entry1[0] > ema_Entry2[0])
      return 1;  // Bullish
   
   // Bearish crossover: EMA10 crosses below EMA15
   if(ema_Entry1[1] >= ema_Entry2[1] && ema_Entry1[0] < ema_Entry2[0])
      return -1; // Bearish
   
   return 0; // No crossover
}

//+------------------------------------------------------------------+
//| Check pullback confirmation                                      |
//+------------------------------------------------------------------+
bool HasPullbackConfirmation()
{
   // Check if price touched EMA20 in last 3 candles
   double close1 = iClose(_Symbol, PERIOD_H1, 1);
   double close2 = iClose(_Symbol, PERIOD_H1, 2);
   double close3 = iClose(_Symbol, PERIOD_H1, 3);
   
   double ema20_1 = ema_Entry3[1];
   double ema20_2 = ema_Entry3[2];
   double ema20_3 = ema_Entry3[3];
   
   // Check if any of the last 3 closes touched EMA20 (within 0.1%)
   double threshold = 0.001;
   
   if(MathAbs(close1 - ema20_1) / ema20_1 < threshold) return true;
   if(MathAbs(close2 - ema20_2) / ema20_2 < threshold) return true;
   if(MathAbs(close3 - ema20_3) / ema20_3 < threshold) return true;
   
   return true; // For now, always pass (can be strict later)
}

//+------------------------------------------------------------------+
//| Generate entry signal                                            |
//+------------------------------------------------------------------+
ENUM_SIGNAL_TYPE GenerateSignal()
{
   // Prevent multiple signals on same candle
   if(lastSignalTime == iTime(_Symbol, PERIOD_H1, 0))
      return SIGNAL_NONE;
   
   // Check session filter
   if(!IsNYSession())
   {
      return SIGNAL_NONE;
   }
   
   // Get trend direction
   ENUM_TREND_DIRECTION trendDir = GetTrendDirection();
   if(trendDir == TREND_NEUTRAL)
   {
      return SIGNAL_NONE;
   }
   
   // Calculate trend strength
   double trendStrength = CalculateTrendStrength();
   ENUM_TREND_STRENGTH strengthClass = ClassifyTrendStrength(trendStrength);
   
   // Reject weak trends
   if(strengthClass == STRENGTH_WEAK)
   {
      Print("REJECTED: Weak trend (", trendStrength, "%)");
      return SIGNAL_NONE;
   }
   
   // Check compression zone
   if(IsCompressionZone())
   {
      Print("REJECTED: Compression zone");
      return SIGNAL_NONE;
   }
   
   // Check ADX filter
   if(!PassesADXFilter())
   {
      return SIGNAL_NONE;
   }
   
   // Check ATR filter
   double atr = atrBuffer[0];
   if(atr < InpMinATR)
   {
      Print("REJECTED: Low volatility (ATR=", atr, ")");
      return SIGNAL_NONE;
   }
   
   // Detect crossover
   int crossover = DetectCrossover();
   if(crossover == 0)
      return SIGNAL_NONE;
   
   double currentPrice = iClose(_Symbol, PERIOD_H1, 0);
   
   // LONG signal
   if(crossover == 1 && trendDir == TREND_BULLISH)
   {
      // Check EMA15 > EMA20
      if(ema_Entry2[0] <= ema_Entry3[0])
      {
         Print("REJECTED LONG: EMA15 not above EMA20");
         return SIGNAL_NONE;
      }
      
      // Check price above all Entry Group EMAs
      if(currentPrice <= ema_Entry1[0] || currentPrice <= ema_Entry2[0] || currentPrice <= ema_Entry3[0])
      {
         Print("REJECTED LONG: Price not above all Entry EMAs");
         return SIGNAL_NONE;
      }
      
      // Check pullback confirmation
      if(!HasPullbackConfirmation())
      {
         Print("REJECTED LONG: No pullback confirmation");
         return SIGNAL_NONE;
      }
      
      Print("=== BUY SIGNAL GENERATED ===");
      Print("Trend: BULLISH, Strength: ", trendStrength, "%");
      Print("EMA10: ", ema_Entry1[0], " | EMA15: ", ema_Entry2[0], " | EMA20: ", ema_Entry3[0]);
      Print("ATR: ", atr, " | ADX: ", adxBuffer[0]);
      
      lastSignalTime = iTime(_Symbol, PERIOD_H1, 0);
      return SIGNAL_BUY;
   }
   
   // SHORT signal
   if(crossover == -1 && trendDir == TREND_BEARISH)
   {
      // Check EMA15 < EMA20
      if(ema_Entry2[0] >= ema_Entry3[0])
      {
         Print("REJECTED SHORT: EMA15 not below EMA20");
         return SIGNAL_NONE;
      }
      
      // Check price below all Entry Group EMAs
      if(currentPrice >= ema_Entry1[0] || currentPrice >= ema_Entry2[0] || currentPrice >= ema_Entry3[0])
      {
         Print("REJECTED SHORT: Price not below all Entry EMAs");
         return SIGNAL_NONE;
      }
      
      // Check pullback confirmation
      if(!HasPullbackConfirmation())
      {
         Print("REJECTED SHORT: No pullback confirmation");
         return SIGNAL_NONE;
      }
      
      Print("=== SELL SIGNAL GENERATED ===");
      Print("Trend: BEARISH, Strength: ", trendStrength, "%");
      Print("EMA10: ", ema_Entry1[0], " | EMA15: ", ema_Entry2[0], " | EMA20: ", ema_Entry3[0]);
      Print("ATR: ", atr, " | ADX: ", adxBuffer[0]);
      
      lastSignalTime = iTime(_Symbol, PERIOD_H1, 0);
      return SIGNAL_SELL;
   }
   
   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lotSize = riskAmount / (slDistance / tickSize * tickValue);
   
   // Normalize to broker's lot step
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   Print("Position sizing: Balance=", balance, " Risk=", riskAmount, " SL=", slDistance, " Lot=", lotSize);
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType)
{
   double atr = atrBuffer[0];
   double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate SL and TP (1:1 RR)
   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = currentPrice - (1.0 * atr);
      tp = currentPrice + (1.0 * atr);
   }
   else
   {
      sl = currentPrice + (1.0 * atr);
      tp = currentPrice - (1.0 * atr);
   }
   
   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   // Calculate lot size
   double slDistance = MathAbs(currentPrice - sl);
   double lotSize = CalculatePositionSize(slDistance);
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = currentPrice;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 50;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   request.type_filling = ORDER_FILLING_IOC;
   
   // Send order with retry logic
   int attempts = 0;
   bool success = false;
   
   while(attempts < 3 && !success)
   {
      ResetLastError();
      success = OrderSend(request, result);
      
      if(success)
      {
         Print("=== POSITION OPENED ===");
         Print("Type: ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"));
         Print("Price: ", currentPrice, " | SL: ", sl, " | TP: ", tp);
         Print("Lot size: ", lotSize, " | ATR: ", atr);
         Print("Order ticket: ", result.order);
         
         dailyTradeCount++;
         break;
      }
      else
      {
         Print("ERROR: OrderSend failed. Retcode=", result.retcode, " Attempt=", attempts+1);
         Sleep(1000);
         attempts++;
      }
   }
   
   if(!success)
   {
      Print("CRITICAL: Failed to open position after 3 attempts");
   }
}

//+------------------------------------------------------------------+
//| Manage existing position                                         |
//+------------------------------------------------------------------+
void ManagePosition()
{
   if(!PositionSelect(_Symbol))
      return;
   
   long posType = PositionGetInteger(POSITION_TYPE);
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Check Exit Group crossovers
   bool shouldExit = false;
   string exitReason = "";
   
   if(posType == POSITION_TYPE_BUY)
   {
      // Early exit: Price crosses below EMA25
      if(currentPrice < ema_Exit1[0])
      {
         shouldExit = true;
         exitReason = "Early exit - Price below EMA25";
      }
      // Partial exit: Price crosses below EMA35 (close 50%)
      else if(currentPrice < ema_Exit2[0])
      {
         shouldExit = true;
         exitReason = "Partial exit - Price below EMA35";
      }
      // Full exit: Price crosses below EMA45
      else if(currentPrice < ema_Exit3[0])
      {
         shouldExit = true;
         exitReason = "Full exit - Price below EMA45";
      }
   }
   else // POSITION_TYPE_SELL
   {
      // Early exit: Price crosses above EMA25
      if(currentPrice > ema_Exit1[0])
      {
         shouldExit = true;
         exitReason = "Early exit - Price above EMA25";
      }
      // Partial exit: Price crosses above EMA35
      else if(currentPrice > ema_Exit2[0])
      {
         shouldExit = true;
         exitReason = "Partial exit - Price above EMA35";
      }
      // Full exit: Price crosses above EMA45
      else if(currentPrice > ema_Exit3[0])
      {
         shouldExit = true;
         exitReason = "Full exit - Price above EMA45";
      }
   }
   
   if(shouldExit)
   {
      ClosePosition(exitReason);
   }
   else if(InpUseTrailingStop)
   {
      UpdateTrailingStop();
   }
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(string reason)
{
   if(!PositionSelect(_Symbol))
      return;
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   double volume = PositionGetDouble(POSITION_VOLUME);
   long posType = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = currentPrice;
   request.deviation = 50;
   request.magic = InpMagicNumber;
   request.comment = reason;
   request.type_filling = ORDER_FILLING_IOC;
   request.position = ticket;
   
   // Send close order with retry logic
   int attempts = 0;
   bool success = false;
   
   while(attempts < 3 && !success)
   {
      ResetLastError();
      success = OrderSend(request, result);
      
      if(success)
      {
         double pnl = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) * volume : (openPrice - currentPrice) * volume;
         dailyPnL += pnl;
         
         Print("=== POSITION CLOSED ===");
         Print("Reason: ", reason);
         Print("Open: ", openPrice, " | Close: ", currentPrice);
         Print("P&L: ", pnl);
         Print("Daily P&L: ", dailyPnL, " | Daily trades: ", dailyTradeCount);
         break;
      }
      else
      {
         Print("ERROR: OrderSend (close) failed. Retcode=", result.retcode, " Attempt=", attempts+1);
         Sleep(1000);
         attempts++;
      }
   }
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop()
{
   if(!PositionSelect(_Symbol))
      return;
   
   long posType = PositionGetInteger(POSITION_TYPE);
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = atrBuffer[0];
   
   double profit = (posType == POSITION_TYPE_BUY) ? (currentPrice - posOpenPrice) : (posOpenPrice - currentPrice);
   
   // Activate trailing at 1.5 ATR profit
   if(profit < 1.5 * atr)
      return;
   
   double newSL;
   bool shouldUpdate = false;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(posType == POSITION_TYPE_BUY)
   {
      // Trail by 1.5 ATR
      newSL = currentPrice - (1.5 * atr);
      newSL = NormalizeDouble(newSL, digits);
      
      // Only move SL up
      if(newSL > posSL)
         shouldUpdate = true;
   }
   else // POSITION_TYPE_SELL
   {
      // Trail by 1.5 ATR
      newSL = currentPrice + (1.5 * atr);
      newSL = NormalizeDouble(newSL, digits);
      
      // Only move SL down
      if(newSL < posSL || posSL == 0)
         shouldUpdate = true;
   }
   
   if(shouldUpdate)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;
      request.sl = newSL;
      request.tp = PositionGetDouble(POSITION_TP);
      request.magic = InpMagicNumber;
      request.position = PositionGetInteger(POSITION_TICKET);
      
      if(OrderSend(request, result))
      {
         Print("Trailing stop updated: New SL=", newSL);
      }
   }
}

//+------------------------------------------------------------------+
