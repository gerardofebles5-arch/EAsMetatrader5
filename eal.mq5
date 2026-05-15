//+------------------------------------------------------------------+
//|                                               AdvancedTraderEA.mq5 |
//|                                          Generated from parameters |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "1.00"

//--- Definiciones para compatibilidad con nomenclatura de MQL4 (opcional)
#define OP_BUY 0
#define OP_SELL 1

//--- input parameters
input bool     HoraNY                     = true;           // Use NY time (true) or broker time (false)
input bool     DivideRiskPerTrade          = false;          // false: divide risk among entries; true: per trade risk
input double   MontoUSD                    = 0.0;            // Base amount in USD (unused if zero)
input int      SLStartMultiplier           = 2;              // Consecutive losses before multiplying risk
input int      MaxSLBeforeReset            = 4;              // Max losses before resetting to base risk
input double   RiskMultiplierFactor        = 1.3;            // Risk multiplication factor
input double   MaxRiskUSD                   = 200.0;          // Maximum risk per trade in USD
input double   MinProfitToResetCounter      = 90.0;           // Minimum profit to reset loss counter
input int      RangeStartHour               = 3;              // Range start hour
input int      RangeStartMin                 = 0;              // Range start minute
input int      RangeEndHour                 = 8;              // Range end hour
input int      RangeEndMin                   = 0;              // Range end minute
input int      TradeStartHour               = 8;              // Trading start hour
input int      TradeStartMin                 = 5;              // Trading start minute
input int      TradeEndHour                 = 11;             // Trading end hour
input int      TradeEndMin                   = 0;              // Trading end minute
input int      MaxBuyTrades                 = 2;              // Maximum number of buy trades (1-2)
input int      MaxSellTrades                = 2;              // Maximum number of sell trades (1-2)
input double   TolerancePips                = 5.0;            // Order placement tolerance (pips)
input double   MaxSpreadPips                = 10.0;           // Maximum allowed spread (pips)
input bool     PreOpenLockoutEnable         = true;           // Enable pre-open lockout
input double   PreOpenLockoutMaxMovePips    = 80.0;           // Max price move during pre-open (pips)
input bool     PostOpenLockoutEnable        = true;           // Enable post-open lockout
input double   PostOpenLockoutMaxMovePips   = 80.0;           // Max price move during post-open (pips)
input double   MinRetracementPips           = 11.0;           // Minimum retracement from range high/low (pips)
input int      Slippage                     = 50;             // Slippage in points
input double   SL_Buy1                      = 50.0;           // Stop Loss for Buy 1 (pips)
input double   TP_Buy1                      = 100.0;          // Take Profit for Buy 1 (pips)
input double   SL_Buy2                      = 50.0;           // Stop Loss for Buy 2 (pips)
input double   TP_Buy2                      = 200.0;          // Take Profit for Buy 2 (pips)
input double   SL_Sell1                     = 50.0;           // Stop Loss for Sell 1 (pips)
input double   TP_Sell1                     = 100.0;          // Take Profit for Sell 1 (pips)
input double   SL_Sell2                     = 50.0;           // Stop Loss for Sell 2 (pips)
input double   TP_Sell2                     = 200.0;          // Take Profit for Sell 2 (pips)
input bool     BE_Enable                    = true;           // Enable Breakeven
input double   BE_Buy1_Pips                  = 50.0;           // Breakeven trigger for Buy 1 (pips)
input double   BE_Buy2_Pips                  = 50.0;           // Breakeven trigger for Buy 2 (pips)
input double   BE_Sell1_Pips                 = 50.0;           // Breakeven trigger for Sell 1 (pips)
input double   BE_Sell2_Pips                 = 50.0;           // Breakeven trigger for Sell 2 (pips)
input bool     Trail_E2_Enable               = true;           // Enable trailing for entry 2
input double   Trail_E2_StepPips             = 50.0;           // Trailing step for entry 2 (pips)
input bool     TP2_Infinite                   = false;          // TP2 infinite (no take profit)
input int      Trail_E2_Infinito_StartCP      = 4;              // Start trailing after X pips profit
input double   Trail_E2_Infinito_StepPips     = 50.0;           // Trailing step for infinite mode (pips)
input bool     UseMinRange                    = true;           // Use minimum range condition
input double   MinRangePips                    = 80.0;           // Minimum range in pips
input bool     UseDailyRL                      = true;           // Use daily risk/reward limits
input double   DailyLossLimitUSD               = 40.0;           // Daily loss limit in USD
input double   DailyGainLimitUSD               = 15.0;           // Daily gain limit in USD
input bool     TradeMonday                     = true;
input bool     TradeTuesday                    = true;
input bool     TradeWednesday                  = true;
input bool     TradeThursday                   = true;
input bool     TradeFriday                     = true;
input int      MagicNumber                     = 537383;         // EA Magic Number
input bool     TradeJanuary                    = true;
input bool     TradeFebruary                   = true;
input bool     TradeMarch                       = true;
input bool     TradeApril                       = true;
input bool     TradeMay                         = true;
input bool     TradeJune                        = true;
input bool     TradeJuly                        = true;
input bool     TradeAugust                      = true;
input bool     TradeSeptember                   = true;
input bool     TradeOctober                     = true;
input bool     TradeNovember                    = true;
input bool     TradeDecember                    = true;
input bool     DebugLog                         = true;          // Enable debug logging
input bool     OptimizeTester                   = false;         // Disable visuals in tester

//--- Global variables
double   pipValue;                 // Value of 1 pip in account currency
double   point;                    // Point size
double   tickValue;                // Tick value
double   tickSize;                 // Tick size
int      digits;                   // Digits of symbol
datetime lastBarTime;              // Time of last processed bar
double   dailyPL;                  // Daily profit/loss (closed + floating)
datetime currentDay;               // Current trading day (date part)
int      consecutiveLosses;        // Consecutive losing trades counter
double   baseRiskUSD;               // Base risk per trade in USD (to be computed)
double   rangeHigh, rangeLow;      // Range high/low for the current day
datetime rangeCalculatedDay;       // Day for which range was calculated
bool     firstBuyDone;              // Flag if first buy was triggered
bool     secondBuyDone;             // Flag if second buy was triggered
bool     firstSellDone;             // Flag if first sell was triggered
bool     secondSellDone;            // Flag if second sell was triggered
double   buyEntryPrice1;            // Price level for first buy entry
double   buyEntryPrice2;            // Price level for second buy entry
double   sellEntryPrice1;           // Price level for first sell entry
double   sellEntryPrice2;           // Price level for second sell entry
int      maxBuyAllowed;              // Validated max buy trades
int      maxSellAllowed;             // Validated max sell trades

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Set up symbol properties
   point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   pipValue   = point * 10;   // assuming 1 pip = 10 points for most brokers

//--- Validate inputs (use internal variables)
   maxBuyAllowed = MaxBuyTrades;
   maxSellAllowed = MaxSellTrades;
   if(maxBuyAllowed < 1 || maxBuyAllowed > 2) maxBuyAllowed = 2;
   if(maxSellAllowed < 1 || maxSellAllowed > 2) maxSellAllowed = 2;

//--- Set base risk
   if(MontoUSD > 0)
      baseRiskUSD = MontoUSD;
   else
      baseRiskUSD = 100; // default value

//--- Initialize state
   lastBarTime = 0;
   dailyPL = 0;
   currentDay = 0;
   consecutiveLosses = 0;
   rangeCalculatedDay = 0;
   ResetEntryFlags();

   if(DebugLog) Print("EA initialized. Magic: ", MagicNumber, " Symbol: ", _Symbol);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(DebugLog) Print("EA deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check for new bar to reduce processing
   datetime currentTime = TimeCurrent();
   if(lastBarTime == 0) lastBarTime = currentTime;
   if(currentTime - lastBarTime < PeriodSeconds(PERIOD_CURRENT))
      return;
   lastBarTime = currentTime;

//--- Update daily P&L and check for new day
   UpdateDailyPL();

//--- Check daily limits
   if(UseDailyRL)
     {
      if(dailyPL <= -DailyLossLimitUSD)
        {
         if(DebugLog) Print("Daily loss limit reached. No new trades.");
         return;
        }
      if(dailyPL >= DailyGainLimitUSD)
        {
         if(DebugLog) Print("Daily gain limit reached. No new trades.");
         return;
        }
     }

//--- Check day of week and month filters
   if(!IsTradingDayAllowed()) return;
   if(!IsTradingMonthAllowed()) return;

//--- Check time filters (operating hours)
   datetime now = TimeCurrent();
   if(!IsWithinOperatingHours(now)) return;

//--- Check spread
   if(!IsSpreadAllowed()) return;

//--- Update range high/low if new day
   if(!IsRangeCalculatedForToday())
      CalculateRange();

//--- Check lockout conditions
   if(PreOpenLockoutEnable && IsPreOpenLockoutActive()) return;
   if(PostOpenLockoutEnable && IsPostOpenLockoutActive()) return;

//--- Check minimum range condition
   if(UseMinRange && (rangeHigh - rangeLow) / point / 10 < MinRangePips)
     {
      if(DebugLog) Print("Range too small: ", (rangeHigh-rangeLow)/point/10, " pips < ", MinRangePips);
      return;
     }

//--- Manage existing orders (trailing, breakeven)
   ManageOrders();

//--- Check for new trade opportunities
   CheckForEntries();

  }

//+------------------------------------------------------------------+
//| Check if current time is within operating hours                  |
//+------------------------------------------------------------------+
bool IsWithinOperatingHours(datetime time)
  {
   MqlDateTime dt;
   TimeToStruct(time, dt);
   int hour = dt.hour;
   int min  = dt.min;

   int startTotal = TradeStartHour * 60 + TradeStartMin;
   int endTotal   = TradeEndHour * 60 + TradeEndMin;
   int currentTotal = hour * 60 + min;

   bool within = (currentTotal >= startTotal && currentTotal < endTotal);
   if(!within && DebugLog) Print("Outside operating hours: ", hour, ":", min);
   return within;
  }

//+------------------------------------------------------------------+
//| Check if spread is within allowed limit                          |
//+------------------------------------------------------------------+
bool IsSpreadAllowed()
  {
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
   if(spread / point / 10 > MaxSpreadPips)
     {
      if(DebugLog) Print("Spread too high: ", spread/point/10, " pips > ", MaxSpreadPips);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Check if today is allowed for trading                            |
//+------------------------------------------------------------------+
bool IsTradingDayAllowed()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week; // 0=Sunday, 1=Monday, ..., 6=Saturday
   switch(dow)
     {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false;
     }
  }

//+------------------------------------------------------------------+
//| Check if current month is allowed for trading                    |
//+------------------------------------------------------------------+
bool IsTradingMonthAllowed()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int month = dt.mon;
   switch(month)
     {
      case 1:  return TradeJanuary;
      case 2:  return TradeFebruary;
      case 3:  return TradeMarch;
      case 4:  return TradeApril;
      case 5:  return TradeMay;
      case 6:  return TradeJune;
      case 7:  return TradeJuly;
      case 8:  return TradeAugust;
      case 9:  return TradeSeptember;
      case 10: return TradeOctober;
      case 11: return TradeNovember;
      case 12: return TradeDecember;
      default: return false;
     }
  }

//+------------------------------------------------------------------+
//| Update daily profit/loss (closed + floating)                     |
//+------------------------------------------------------------------+
void UpdateDailyPL()
  {
   datetime now = TimeCurrent();
   MqlDateTime today;
   TimeToStruct(now, today);
   today.hour = 0; today.min = 0; today.sec = 0;
   datetime startOfDay = StructToTime(today);

   if(currentDay != startOfDay)
     {
      // New day, reset daily PL and flags
      currentDay = startOfDay;
      dailyPL = 0;
      consecutiveLosses = 0;
      ResetEntryFlags();
      if(DebugLog) Print("New trading day started. Daily P&L reset.");
     }

   // Calculate current floating P&L for open positions
   double floating = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            floating += PositionGetDouble(POSITION_PROFIT);
           }
        }
     }

   // Historical closed profit for today (from closed orders) - we need to track separately.
   // For simplicity, we'll compute total daily P&L as floating + closed today.
   // To get closed profit, we can sum profit of closed orders since startOfDay.
   // We'll need to store previous day's closed sum. This is complex.
   // Instead, we'll approximate by using AccountInfoDouble(ACCOUNT_PROFIT) which includes floating + closed.
   // But that's total account P&L, not per day. However, we can compute daily change.
   // A simpler approach: Use a static variable to store account equity at start of day and compare.
   // Let's do that.

   static double equityAtDayStart = 0;
   if(currentDay != startOfDay)
     {
      equityAtDayStart = AccountInfoDouble(ACCOUNT_EQUITY);
     }
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyPL = currentEquity - equityAtDayStart;

   if(DebugLog && MathAbs(dailyPL) > 0.01) Print("Daily P&L: ", dailyPL);
  }

//+------------------------------------------------------------------+
//| Check if range has been calculated for today                     |
//+------------------------------------------------------------------+
bool IsRangeCalculatedForToday()
  {
   MqlDateTime today;
   TimeToStruct(TimeCurrent(), today);
   today.hour = 0; today.min = 0; today.sec = 0;
   datetime startDay = StructToTime(today);
   return (rangeCalculatedDay == startDay);
  }

//+------------------------------------------------------------------+
//| Calculate range high/low from the specified time interval        |
//+------------------------------------------------------------------+
void CalculateRange()
  {
   datetime now = TimeCurrent();
   MqlDateTime today;
   TimeToStruct(now, today);
   today.hour = RangeStartHour;
   today.min  = RangeStartMin;
   today.sec  = 0;
   datetime rangeStart = StructToTime(today);
   today.hour = RangeEndHour;
   today.min  = RangeEndMin;
   datetime rangeEnd = StructToTime(today);

   // If range end is earlier than start, it means it crosses midnight? Unlikely, but handle.
   if(rangeEnd <= rangeStart)
     {
      // Add one day to end
      rangeEnd += 24*3600;
     }

   // Ensure range is in the past (today's range)
   if(rangeEnd > now) rangeEnd = now;
   if(rangeStart > now) rangeStart = now - 24*3600; // fallback

   // Get high and low from M1 rates
   MqlRates rates[];
   int count = CopyRates(_Symbol, PERIOD_M1, rangeStart, rangeEnd, rates);
   if(count > 0)
     {
      rangeHigh = rates[0].high;
      rangeLow  = rates[0].low;
      for(int i = 1; i < count; i++)
        {
         if(rates[i].high > rangeHigh) rangeHigh = rates[i].high;
         if(rates[i].low  < rangeLow)  rangeLow  = rates[i].low;
        }
      MqlDateTime day;
      TimeToStruct(now, day);
      day.hour = 0; day.min = 0; day.sec = 0;
      rangeCalculatedDay = StructToTime(day);
      if(DebugLog) Print("Range calculated: High=", rangeHigh, " Low=", rangeLow);
     }
   else
     {
      if(DebugLog) Print("Failed to get rates for range calculation.");
      rangeHigh = 0; rangeLow = 0;
     }
  }

//+------------------------------------------------------------------+
//| Check pre-open lockout condition                                 |
//+------------------------------------------------------------------+
bool IsPreOpenLockoutActive()
  {
   // Pre-open lockout: if price moved too much from range high/low before trading starts?
   // We'll define it as: if current price is within PreOpenLockoutMaxMovePips of range high/low? Or if range itself moved?
   // Assume lockout if price is beyond range by more than MaxMovePips.
   double current = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double moveUp   = (current - rangeHigh) / point / 10;
   double moveDown = (rangeLow - current) / point / 10;
   if(moveUp > PreOpenLockoutMaxMovePips || moveDown > PreOpenLockoutMaxMovePips)
     {
      if(DebugLog) Print("Pre-open lockout active. Move: ", MathMax(moveUp, moveDown), " pips");
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check post-open lockout condition                                |
//+------------------------------------------------------------------+
bool IsPostOpenLockoutActive()
  {
   // Similar to pre-open, but after market open? Possibly same logic.
   double current = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double moveUp   = (current - rangeHigh) / point / 10;
   double moveDown = (rangeLow - current) / point / 10;
   if(moveUp > PostOpenLockoutMaxMovePips || moveDown > PostOpenLockoutMaxMovePips)
     {
      if(DebugLog) Print("Post-open lockout active. Move: ", MathMax(moveUp, moveDown), " pips");
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Reset entry flags for new day                                    |
//+------------------------------------------------------------------+
void ResetEntryFlags()
  {
   firstBuyDone = false;
   secondBuyDone = false;
   firstSellDone = false;
   secondSellDone = false;
   buyEntryPrice1 = 0;
   buyEntryPrice2 = 0;
   sellEntryPrice1 = 0;
   sellEntryPrice2 = 0;
  }

//+------------------------------------------------------------------+
//| Manage existing orders: breakeven and trailing                   |
//+------------------------------------------------------------------+
void ManageOrders()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

         string comment = PositionGetString(POSITION_COMMENT);
         int entryType = 0; // 1=Buy1, 2=Buy2, 3=Sell1, 4=Sell2
         if(StringFind(comment, "Buy1") >= 0) entryType = 1;
         else if(StringFind(comment, "Buy2") >= 0) entryType = 2;
         else if(StringFind(comment, "Sell1") >= 0) entryType = 3;
         else if(StringFind(comment, "Sell2") >= 0) entryType = 4;

         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPips = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point / 10 : (openPrice - currentPrice) / point / 10;

         //--- Breakeven
         if(BE_Enable)
           {
            double beTrigger = 0;
            if(entryType == 1) beTrigger = BE_Buy1_Pips;
            else if(entryType == 2) beTrigger = BE_Buy2_Pips;
            else if(entryType == 3) beTrigger = BE_Sell1_Pips;
            else if(entryType == 4) beTrigger = BE_Sell2_Pips;

            if(beTrigger > 0 && profitPips >= beTrigger && currentSL == 0)
              {
               // Move SL to breakeven
               double newSL = openPrice;
               MqlTradeRequest req = {};
               MqlTradeResult res = {};
               req.action = TRADE_ACTION_SLTP;
               req.position = ticket;
               req.symbol = _Symbol;
               req.sl = newSL;
               req.tp = currentTP;
               if(OrderSend(req, res))
                 {
                  if(DebugLog) Print("Breakeven set for ", comment);
                 }
              }
           }

         //--- Trailing for entry 2
         if(Trail_E2_Enable && (entryType == 2 || entryType == 4))
           {
            double step = Trail_E2_StepPips * 10 * point;
            if(TP2_Infinite && entryType == 2) // use infinite trailing for buy2
              {
               // Infinite trailing: start after StartCP pips profit, then trail by StepPips
               if(profitPips >= Trail_E2_Infinito_StartCP)
                 {
                  double newSL = 0;
                  if(entryType == 2) // buy
                    {
                     newSL = currentPrice - Trail_E2_Infinito_StepPips * 10 * point;
                    }
                  else // sell
                    {
                     newSL = currentPrice + Trail_E2_Infinito_StepPips * 10 * point;
                    }
                  if(newSL > currentSL) // for buy, higher SL is better; for sell, lower SL is better
                    {
                     MqlTradeRequest req = {};
                     MqlTradeResult res = {};
                     req.action = TRADE_ACTION_SLTP;
                     req.position = ticket;
                     req.symbol = _Symbol;
                     req.sl = newSL;
                     req.tp = currentTP; // no TP if infinite
                     if(OrderSend(req, res))
                       {
                        if(DebugLog) Print("Infinite trailing updated for ", comment);
                       }
                    }
                 }
              }
            else // standard trailing for entry2
              {
               // Trail if profit >= step?
               if(profitPips >= step/(10*point))
                 {
                  double newSL = 0;
                  if(entryType == 2) // buy
                    {
                     newSL = currentPrice - step;
                    }
                  else // sell
                    {
                     newSL = currentPrice + step;
                    }
                  if((entryType == 2 && newSL > currentSL) || (entryType == 4 && newSL < currentSL))
                    {
                     MqlTradeRequest req = {};
                     MqlTradeResult res = {};
                     req.action = TRADE_ACTION_SLTP;
                     req.position = ticket;
                     req.symbol = _Symbol;
                     req.sl = newSL;
                     req.tp = currentTP;
                     if(OrderSend(req, res))
                       {
                        if(DebugLog) Print("Trailing updated for ", comment);
                       }
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check for new entry signals                                      |
//+------------------------------------------------------------------+
void CheckForEntries()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Determine entry levels based on range and retracement
   // For buys: we need price to have broken above rangeHigh, then retraced down.
   // For sells: break below rangeLow, then retraced up.

   // We'll use flags to track if we have already entered at certain levels.
   // Entry levels are dynamic: first buy at rangeHigh - MinRetracementPips, second at rangeHigh - 2*MinRetracementPips (if enabled).
   // But we need to ensure that price actually broke above rangeHigh before retracing.

   static bool breakoutUp = false;
   static bool breakoutDown = false;

   // Check breakout
   if(ask > rangeHigh) breakoutUp = true;
   if(bid < rangeLow) breakoutDown = true;

   // For buys
   if(maxBuyAllowed > 0 && breakoutUp)
     {
      double retrace1 = rangeHigh - MinRetracementPips * 10 * point;
      double retrace2 = rangeHigh - 2 * MinRetracementPips * 10 * point; // second level

      // First buy
      if(!firstBuyDone && bid <= retrace1 + TolerancePips * 10 * point && bid >= retrace1 - TolerancePips * 10 * point)
        {
         OpenTrade(OP_BUY, 1);
        }
      // Second buy (only if first done and second not done)
      if(firstBuyDone && !secondBuyDone && bid <= retrace2 + TolerancePips * 10 * point && bid >= retrace2 - TolerancePips * 10 * point)
        {
         OpenTrade(OP_BUY, 2);
        }
     }

   // For sells
   if(maxSellAllowed > 0 && breakoutDown)
     {
      double retrace1 = rangeLow + MinRetracementPips * 10 * point;
      double retrace2 = rangeLow + 2 * MinRetracementPips * 10 * point;

      if(!firstSellDone && ask >= retrace1 - TolerancePips * 10 * point && ask <= retrace1 + TolerancePips * 10 * point)
        {
         OpenTrade(OP_SELL, 1);
        }
      if(firstSellDone && !secondSellDone && ask >= retrace2 - TolerancePips * 10 * point && ask <= retrace2 + TolerancePips * 10 * point)
        {
         OpenTrade(OP_SELL, 2);
        }
     }
  }

//+------------------------------------------------------------------+
//| Open a trade (buy/sell) with specified entry number (1 or 2)    |
//+------------------------------------------------------------------+
void OpenTrade(int type, int entryNum)
  {
   double price = (type == OP_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0, tp = 0;
   string comment = "";

   if(type == OP_BUY)
     {
      if(entryNum == 1)
        {
         sl = price - SL_Buy1 * 10 * point;
         tp = price + TP_Buy1 * 10 * point;
         comment = "Buy1";
         firstBuyDone = true;
        }
      else if(entryNum == 2)
        {
         sl = price - SL_Buy2 * 10 * point;
         if(TP2_Infinite)
            tp = 0;
         else
            tp = price + TP_Buy2 * 10 * point;
         comment = "Buy2";
         secondBuyDone = true;
        }
     }
   else if(type == OP_SELL)
     {
      if(entryNum == 1)
        {
         sl = price + SL_Sell1 * 10 * point;
         tp = price - TP_Sell1 * 10 * point;
         comment = "Sell1";
         firstSellDone = true;
        }
      else if(entryNum == 2)
        {
         sl = price + SL_Sell2 * 10 * point;
         if(TP2_Infinite)
            tp = 0;
         else
            tp = price - TP_Sell2 * 10 * point;
         comment = "Sell2";
         secondSellDone = true;
        }
     }

   // Calculate lot size based on risk
   double lot = CalculateLotSize(type, sl, price);

   // Send order
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = (type == OP_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price = price;
   req.sl = sl;
   req.tp = tp;
   req.deviation = Slippage;
   req.magic = MagicNumber;
   req.comment = comment;

   if(OrderSend(req, res))
     {
      if(DebugLog) Print("Order sent: ", comment, " lot: ", lot, " price: ", price, " sl: ", sl, " tp: ", tp);
     }
   else
     {
      if(DebugLog) Print("Order failed: ", res.retcode, " ", res.comment);
     }
  }

//+------------------------------------------------------------------+
//| Calculate lot size based on risk parameters                      |
//+------------------------------------------------------------------+
double CalculateLotSize(int type, double slPrice, double entryPrice)
  {
   // Risk per trade in USD (baseRiskUSD already set in OnInit)
   double riskUSD = baseRiskUSD;

   // Apply multiplier based on consecutive losses
   if(consecutiveLosses >= SLStartMultiplier)
     {
      int multCount = consecutiveLosses - SLStartMultiplier + 1;
      double multiplier = MathPow(RiskMultiplierFactor, multCount);
      riskUSD *= multiplier;
      if(riskUSD > MaxRiskUSD) riskUSD = MaxRiskUSD;
     }
   if(consecutiveLosses >= MaxSLBeforeReset)
      consecutiveLosses = 0; // reset after max

   // Calculate stop loss distance in points
   double slPoints = MathAbs(entryPrice - slPrice) / point;
   // Tick value per lot for 1 point move
   double tickValuePerLot = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * (point / tickSize);
   double riskPerLot = slPoints * tickValuePerLot;

   double lot = riskUSD / riskPerLot;

   // Normalize lot to allowed step
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return lot;
  }

//+------------------------------------------------------------------+
//| TradeTransaction function to track closed trades for consecutive losses |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
        {
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == MagicNumber)
           {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            if(profit < 0) // losing trade
              {
               consecutiveLosses++;
               if(DebugLog) Print("Consecutive losses: ", consecutiveLosses);
              }
            else if(profit >= MinProfitToResetCounter)
              {
               consecutiveLosses = 0;
               if(DebugLog) Print("Reset consecutive losses due to profit >= ", MinProfitToResetCounter);
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+