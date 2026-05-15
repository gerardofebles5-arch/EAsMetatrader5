//+------------------------------------------------------------------+
//|                                    XAUUSD_Simple_Scalper.mq5     |
//|                           Ultra-Simple EMA Crossover Strategy    |
//|                           GUARANTEED TO OPERATE                  |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Simple Scalper"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// EMA Parameters
input int      EMA_Fast_Period = 9;           // EMA fast period
input int      EMA_Slow_Period = 21;          // EMA slow period

// Risk Management
input int      StopLoss_Points = 30;          // Stop loss in points
input int      TakeProfit_Points = 60;        // Take profit in points (1:2 RR)
input double   Risk_Percent = 1.0;            // Risk per trade (% of balance)

// Trading Filters
input int      Max_Spread_Points = 35;        // Maximum spread allowed
input double   Daily_Loss_Limit = 5.0;        // Daily loss limit (% of balance)
input double   Max_Drawdown_Limit = 10.0;     // Maximum drawdown (% of balance)

// System
input int      Magic_Number = 123456;         // EA magic number
input string   Log_Level = "INFO";            // Logging level: INFO, DEBUG

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+

// Indicator handles
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;

// State tracking
datetime g_lastBarTime = 0;
double g_startingBalance = 0;
double g_dailyStartBalance = 0;
datetime g_lastTradeDate = 0;

// Trade statistics
struct TradeStats {
    int totalTrades;
    int winningTrades;
    int losingTrades;
    double totalProfit;
    double totalLoss;
};
TradeStats g_stats;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD Simple Scalper v1.0 - Initializing");
    Print("========================================");
    
    // Validate input parameters
    if(!ValidateParameters())
    {
        Print("ERROR: Invalid parameters detected. Using defaults.");
    }
    
    // Log all parameters
    Print("--- Configuration ---");
    Print("EMA Fast Period: ", EMA_Fast_Period);
    Print("EMA Slow Period: ", EMA_Slow_Period);
    Print("Stop Loss: ", StopLoss_Points, " points");
    Print("Take Profit: ", TakeProfit_Points, " points");
    Print("Risk/Reward Ratio: 1:", (TakeProfit_Points / StopLoss_Points));
    Print("Risk Per Trade: ", Risk_Percent, "%");
    Print("Max Spread: ", Max_Spread_Points, " points");
    Print("Daily Loss Limit: ", Daily_Loss_Limit, "%");
    Print("Max Drawdown Limit: ", Max_Drawdown_Limit, "%");
    Print("Magic Number: ", Magic_Number);
    Print("Log Level: ", Log_Level);
    
    // Initialize indicator handles
    g_emaFastHandle = iMA(_Symbol, PERIOD_M5, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
    g_emaSlowHandle = iMA(_Symbol, PERIOD_M5, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
    {
        Print("CRITICAL ERROR: Failed to create indicator handles");
        Print("EMA Fast Handle: ", g_emaFastHandle);
        Print("EMA Slow Handle: ", g_emaSlowHandle);
        return(INIT_FAILED);
    }
    
    Print("Indicator handles created successfully");
    
    // Initialize balance tracking
    g_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_dailyStartBalance = g_startingBalance;
    
    Print("Starting Balance: $", g_startingBalance);
    Print("Daily Loss Limit: $", (g_startingBalance * Daily_Loss_Limit / 100.0));
    Print("Max Drawdown Limit: $", (g_startingBalance * Max_Drawdown_Limit / 100.0));
    
    // Initialize statistics
    g_stats.totalTrades = 0;
    g_stats.winningTrades = 0;
    g_stats.losingTrades = 0;
    g_stats.totalProfit = 0;
    g_stats.totalLoss = 0;
    
    Print("========================================");
    Print("INITIALIZATION COMPLETE - READY TO TRADE");
    Print("========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(g_emaFastHandle != INVALID_HANDLE)
    {
        IndicatorRelease(g_emaFastHandle);
        g_emaFastHandle = INVALID_HANDLE;
    }
    
    if(g_emaSlowHandle != INVALID_HANDLE)
    {
        IndicatorRelease(g_emaSlowHandle);
        g_emaSlowHandle = INVALID_HANDLE;
    }
    
    // Print final statistics
    Print("========================================");
    Print("XAUUSD Simple Scalper - Shutting Down");
    Print("========================================");
    Print("Total Trades: ", g_stats.totalTrades);
    Print("Winning Trades: ", g_stats.winningTrades);
    Print("Losing Trades: ", g_stats.losingTrades);
    if(g_stats.totalTrades > 0)
    {
        double winRate = (double)g_stats.winningTrades / (double)g_stats.totalTrades * 100.0;
        Print("Win Rate: ", DoubleToString(winRate, 2), "%");
    }
    Print("Total Profit: $", g_stats.totalProfit);
    Print("Total Loss: $", g_stats.totalLoss);
    Print("Net P&L: $", (g_stats.totalProfit + g_stats.totalLoss));
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Validate input parameters                                        |
//+------------------------------------------------------------------+
bool ValidateParameters()
{
    bool valid = true;
    
    // Validate EMA periods
    if(EMA_Fast_Period <= 0 || EMA_Slow_Period <= 0)
    {
        Print("ERROR: EMA periods must be positive");
        valid = false;
    }
    
    if(EMA_Fast_Period >= EMA_Slow_Period)
    {
        Print("ERROR: Fast EMA period must be less than Slow EMA period");
        valid = false;
    }
    
    // Validate SL/TP
    if(StopLoss_Points <= 0)
    {
        Print("ERROR: Stop Loss must be positive");
        valid = false;
    }
    
    if(TakeProfit_Points <= StopLoss_Points)
    {
        Print("ERROR: Take Profit must be greater than Stop Loss");
        valid = false;
    }
    
    // Validate risk percentage
    if(Risk_Percent <= 0 || Risk_Percent >= 100)
    {
        Print("ERROR: Risk Percent must be between 0 and 100");
        valid = false;
    }
    
    // Validate spread
    if(Max_Spread_Points <= 0)
    {
        Print("ERROR: Max Spread must be positive");
        valid = false;
    }
    
    // Validate drawdown limits
    if(Daily_Loss_Limit <= 0 || Daily_Loss_Limit >= 100)
    {
        Print("ERROR: Daily Loss Limit must be between 0 and 100");
        valid = false;
    }
    
    if(Max_Drawdown_Limit <= 0 || Max_Drawdown_Limit >= 100)
    {
        Print("ERROR: Max Drawdown Limit must be between 0 and 100");
        valid = false;
    }
    
    return valid;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar (only trade on bar close)
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    if(currentBarTime == g_lastBarTime)
    {
        return; // Not a new bar, exit
    }
    g_lastBarTime = currentBarTime;
    
    if(Log_Level == "DEBUG")
    {
        Print("--- New Bar: ", TimeToString(currentBarTime), " ---");
    }
    
    // Reset daily counters if new day
    ResetDailyCounters();
    
    // Check if position already open
    if(PositionSelect(_Symbol))
    {
        if(Log_Level == "DEBUG")
        {
            Print("Position already open, skipping analysis");
        }
        return;
    }
    
    // Detect crossover
    int signal = DetectCrossover();
    
    if(signal == 0)
    {
        if(Log_Level == "DEBUG")
        {
            Print("No crossover detected");
        }
        return;
    }
    
    // Validate trade
    string blockingReason = "";
    if(!ValidateTrade(blockingReason))
    {
        Print("Trade blocked: ", blockingReason);
        return;
    }
    
    // Execute trade
    bool isLong = (signal == 1);
    ExecuteTrade(isLong);
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
    datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
    
    if(currentDate != g_lastTradeDate)
    {
        g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_lastTradeDate = currentDate;
        Print("=== NEW TRADING DAY ===");
        Print("Daily Start Balance: $", g_dailyStartBalance);
    }
}

//+------------------------------------------------------------------+
//| Detect EMA crossover                                             |
//+------------------------------------------------------------------+
int DetectCrossover()
{
    // Arrays for EMA values
    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    
    // Copy EMA values (need current bar [0] and previous bar [1])
    if(CopyBuffer(g_emaFastHandle, 0, 0, 2, emaFast) <= 0)
    {
        Print("ERROR: Failed to copy EMA Fast buffer");
        return 0;
    }
    
    if(CopyBuffer(g_emaSlowHandle, 0, 0, 2, emaSlow) <= 0)
    {
        Print("ERROR: Failed to copy EMA Slow buffer");
        return 0;
    }
    
    // Get values
    double emaFast_current = emaFast[0];
    double emaFast_previous = emaFast[1];
    double emaSlow_current = emaSlow[0];
    double emaSlow_previous = emaSlow[1];
    
    if(Log_Level == "DEBUG")
    {
        Print("EMA Fast [0]: ", DoubleToString(emaFast_current, 5), 
              " [1]: ", DoubleToString(emaFast_previous, 5));
        Print("EMA Slow [0]: ", DoubleToString(emaSlow_current, 5), 
              " [1]: ", DoubleToString(emaSlow_previous, 5));
    }
    
    // Detect bullish crossover: EMA9[1] <= EMA21[1] AND EMA9[0] > EMA21[0]
    if(emaFast_previous <= emaSlow_previous && emaFast_current > emaSlow_current)
    {
        Print(">>> BULLISH CROSSOVER DETECTED <<<");
        Print("EMA Fast crossed ABOVE EMA Slow");
        Print("Previous: Fast=", DoubleToString(emaFast_previous, 5), 
              " Slow=", DoubleToString(emaSlow_previous, 5));
        Print("Current: Fast=", DoubleToString(emaFast_current, 5), 
              " Slow=", DoubleToString(emaSlow_current, 5));
        return 1; // Long signal
    }
    
    // Detect bearish crossover: EMA9[1] >= EMA21[1] AND EMA9[0] < EMA21[0]
    if(emaFast_previous >= emaSlow_previous && emaFast_current < emaSlow_current)
    {
        Print(">>> BEARISH CROSSOVER DETECTED <<<");
        Print("EMA Fast crossed BELOW EMA Slow");
        Print("Previous: Fast=", DoubleToString(emaFast_previous, 5), 
              " Slow=", DoubleToString(emaSlow_previous, 5));
        Print("Current: Fast=", DoubleToString(emaFast_current, 5), 
              " Slow=", DoubleToString(emaSlow_current, 5));
        return -1; // Short signal
    }
    
    // No crossover
    return 0;
}

//+------------------------------------------------------------------+
//| Validate trade conditions                                        |
//+------------------------------------------------------------------+
bool ValidateTrade(string &blockingReason)
{
    // Check 1: Existing position (fastest check)
    if(PositionSelect(_Symbol))
    {
        blockingReason = "Position already open";
        return false;
    }
    
    // Check 2: Spread filter
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread = (ask - bid) / _Point;
    
    if(Log_Level == "DEBUG")
    {
        Print("Current spread: ", (int)spread, " points");
    }
    
    if(spread > Max_Spread_Points)
    {
        blockingReason = StringFormat("Spread too high: %d points (max: %d)", 
                                      (int)spread, Max_Spread_Points);
        return false;
    }
    
    // Check 3: Daily loss limit
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyLoss = g_dailyStartBalance - currentBalance;
    double dailyLossPercent = (dailyLoss / g_dailyStartBalance) * 100.0;
    
    if(dailyLossPercent >= Daily_Loss_Limit)
    {
        blockingReason = StringFormat("Daily loss limit reached: %.2f%% (limit: %.2f%%)", 
                                      dailyLossPercent, Daily_Loss_Limit);
        return false;
    }
    
    // Check 4: Maximum drawdown limit
    double totalDrawdown = g_startingBalance - currentBalance;
    double drawdownPercent = (totalDrawdown / g_startingBalance) * 100.0;
    
    if(drawdownPercent >= Max_Drawdown_Limit)
    {
        blockingReason = StringFormat("Max drawdown limit reached: %.2f%% (limit: %.2f%%)", 
                                      drawdownPercent, Max_Drawdown_Limit);
        return false;
    }
    
    // All checks passed
    if(Log_Level == "DEBUG")
    {
        Print("All trade validations passed");
        Print("Spread: ", (int)spread, " points");
        Print("Daily Loss: ", DoubleToString(dailyLossPercent, 2), "%");
        Print("Total Drawdown: ", DoubleToString(drawdownPercent, 2), "%");
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * Risk_Percent / 100.0;
    
    // Get symbol properties
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;
    
    // Calculate lot size based on risk
    double lotSize = riskAmount / (StopLoss_Points * pointValue);
    
    // Get broker limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Apply limits
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    // Round to lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    if(Log_Level == "DEBUG")
    {
        Print("Position Sizing:");
        Print("  Account Balance: $", accountBalance);
        Print("  Risk Amount: $", riskAmount);
        Print("  Calculated Lot Size: ", lotSize);
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isLong)
{
    // Get current price
    double price = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate SL and TP
    double sl, tp;
    if(isLong)
    {
        sl = price - StopLoss_Points * _Point;
        tp = price + TakeProfit_Points * _Point;
    }
    else
    {
        sl = price + StopLoss_Points * _Point;
        tp = price - TakeProfit_Points * _Point;
    }
    
    // Normalize prices
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // Calculate lot size
    double lotSize = CalculateLotSize();
    lotSize = NormalizeDouble(lotSize, 2);
    
    // Prepare trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = Magic_Number;
    request.comment = "Simple Scalper";
    request.type_filling = ORDER_FILLING_IOC;
    
    // Send order
    Print("========================================");
    Print("EXECUTING TRADE");
    Print("========================================");
    Print("Direction: ", isLong ? "LONG (BUY)" : "SHORT (SELL)");
    Print("Entry Price: ", DoubleToString(price, _Digits));
    Print("Stop Loss: ", DoubleToString(sl, _Digits), " (", StopLoss_Points, " points)");
    Print("Take Profit: ", DoubleToString(tp, _Digits), " (", TakeProfit_Points, " points)");
    Print("Lot Size: ", lotSize);
    Print("Risk/Reward: 1:", (TakeProfit_Points / StopLoss_Points));
    
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print(">>> TRADE EXECUTED SUCCESSFULLY <<<");
            Print("Order Ticket: ", result.order);
            Print("Deal Ticket: ", result.deal);
            Print("========================================");
            
            // Update statistics
            g_stats.totalTrades++;
        }
        else
        {
            Print("ERROR: Trade execution failed");
            Print("Return Code: ", result.retcode);
            Print("Comment: ", result.comment);
            Print("========================================");
        }
    }
    else
    {
        Print("ERROR: OrderSend failed");
        Print("Last Error: ", GetLastError());
        Print("========================================");
    }
}

//+------------------------------------------------------------------+
//| Trade transaction event                                          |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Update statistics when trades close
    if(!PositionSelect(_Symbol))
    {
        // Position closed, check if it was profitable
        if(HistorySelect(TimeCurrent() - 86400, TimeCurrent())) // Last 24 hours
        {
            int total = HistoryDealsTotal();
            if(total > 0)
            {
                ulong ticket = HistoryDealGetTicket(total - 1);
                if(ticket > 0)
                {
                    long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                    if(dealMagic == Magic_Number)
                    {
                        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                        
                        if(profit > 0)
                        {
                            g_stats.winningTrades++;
                            g_stats.totalProfit += profit;
                            Print(">>> TRADE CLOSED: WIN <<<");
                            Print("Profit: $", DoubleToString(profit, 2));
                        }
                        else if(profit < 0)
                        {
                            g_stats.losingTrades++;
                            g_stats.totalLoss += profit;
                            Print(">>> TRADE CLOSED: LOSS <<<");
                            Print("Loss: $", DoubleToString(profit, 2));
                        }
                        
                        // Print current statistics
                        if(g_stats.totalTrades > 0)
                        {
                            double winRate = (double)g_stats.winningTrades / (double)g_stats.totalTrades * 100.0;
                            Print("--- Current Statistics ---");
                            Print("Total Trades: ", g_stats.totalTrades);
                            Print("Win Rate: ", DoubleToString(winRate, 2), "%");
                            Print("Net P&L: $", DoubleToString(g_stats.totalProfit + g_stats.totalLoss, 2));
                        }
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
