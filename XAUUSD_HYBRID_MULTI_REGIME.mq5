//+------------------------------------------------------------------+
//|                    XAUUSD_HYBRID_MULTI_REGIME.mq5                |
//|           ESTRATEGIA HÍBRIDA - Detecta régimen y adapta          |
//+------------------------------------------------------------------+
#property copyright "Hybrid Multi-Regime"
#property version   "1.00"

input int Magic_Number = 888888;
input double Risk_Percent = 1.0;
input int Max_Trades_Per_Day = 5;
input double Max_Daily_Loss_Percent = 3.0;

input int ADX_Period = 14;
input double ADX_Trend_Threshold = 25.0;
input double Distance_EMA_Percent = 2.0;

input int Trend_EMA_Fast = 21;
input int Trend_EMA_Slow = 50;
input int Trend_EMA_Filter = 200;
input double Trend_SL_ATR = 1.2;
input double Trend_TP_ATR = 3.6;

input int Range_RSI_Period = 14;
input double Range_RSI_Oversold = 30;
input double Range_RSI_Overbought = 70;
input int Range_BB_Period = 20;
input double Range_BB_Deviation = 2.0;
input double Range_SL_ATR = 2.0;
input double Range_TP_ATR = 4.0;

input int ATR_Period = 14;
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 1.5;
input double BreakEven_Profit_ATR = 0.3;
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 2.5;
input double Trailing_Step_ATR = 0.8;

datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;
double g_dailyProfit = 0.0;
bool g_dailyLossReached = false;
bool g_breakEvenActivated = false;

enum MARKET_REGIME { REGIME_TREND, REGIME_RANGE, REGIME_UNKNOWN };

int g_handle_ADX, g_handle_ATR;
int g_handle_Trend_EMA_Fast, g_handle_Trend_EMA_Slow, g_handle_Trend_EMA_Filter;
int g_handle_Range_RSI, g_handle_Range_BB, g_handle_Range_EMA50;

int OnInit()
{
    Print("========================================");
    Print("HYBRID MULTI-REGIME EA");
    Print("Risk: ", Risk_Percent, "% | Max Trades: ", Max_Trades_Per_Day);
    Print("ADX Threshold: ", ADX_Trend_Threshold);
    Print("TREND: EMA", Trend_EMA_Fast, "/", Trend_EMA_Slow, "/", Trend_EMA_Filter);
    Print("RANGE: RSI(", Range_RSI_Period, ") + BB(", Range_BB_Period, ")");
    Print("========================================");
    
    g_handle_ADX = iADX(_Symbol, PERIOD_M5, ADX_Period);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    g_handle_Trend_EMA_Fast = iMA(_Symbol, PERIOD_M5, Trend_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_Trend_EMA_Slow = iMA(_Symbol, PERIOD_M5, Trend_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_Trend_EMA_Filter = iMA(_Symbol, PERIOD_M5, Trend_EMA_Filter, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_Range_RSI = iRSI(_Symbol, PERIOD_M5, Range_RSI_Period, PRICE_CLOSE);
    g_handle_Range_BB = iBands(_Symbol, PERIOD_M5, Range_BB_Period, 0, Range_BB_Deviation, PRICE_CLOSE);
    g_handle_Range_EMA50 = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_handle_ADX == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE ||
       g_handle_Trend_EMA_Fast == INVALID_HANDLE || g_handle_Range_RSI == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators");
        return(INIT_FAILED);
    }
    
    Print("EA READY");
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    UpdateDailyProfit();
    
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
        
        if(currentDate != g_lastTradeDate)
        {
            g_tradesToday = 0;
            g_dailyProfit = 0.0;
            g_dailyLossReached = false;
            g_lastTradeDate = currentDate;
        }
        
        if(g_dailyLossReached || g_tradesToday >= Max_Trades_Per_Day) return;
        
        if(!PositionSelect(_Symbol))
        {
            g_breakEvenActivated = false;
            CheckForEntry();
        }
    }
    
    if(PositionSelect(_Symbol))
    {
        if(Use_Break_Even) ManageBreakEven();
        if(Use_Trailing_Stop) ManageTrailingStop();
    }
}

MARKET_REGIME DetectMarketRegime()
{
    double adx[], ema50[], close[];
    ArraySetAsSeries(adx, true);
    ArraySetAsSeries(ema50, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_ADX, 0, 0, 3, adx) <= 0 ||
       CopyBuffer(g_handle_Range_EMA50, 0, 0, 3, ema50) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        return REGIME_UNKNOWN;
    }
    
    double current_adx = adx[0];
    double distance_percent = MathAbs(close[0] - ema50[0]) / ema50[0] * 100.0;
    
    if(current_adx > ADX_Trend_Threshold || distance_percent > Distance_EMA_Percent)
    {
        Print("REGIME: TREND | ADX=", NormalizeDouble(current_adx, 2));
        return REGIME_TREND;
    }
    
    Print("REGIME: RANGE | ADX=", NormalizeDouble(current_adx, 2));
    return REGIME_RANGE;
}

void CheckForEntry()
{
    MARKET_REGIME regime = DetectMarketRegime();
    
    if(regime == REGIME_UNKNOWN) return;
    
    if(regime == REGIME_TREND)
        CheckTrendEntry();
    else if(regime == REGIME_RANGE)
        CheckRangeEntry();
}

void CheckTrendEntry()
{
    double ema_fast[], ema_slow[], ema_filter[], atr[], close[], high[], low[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(ema_filter, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyBuffer(g_handle_Trend_EMA_Fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(g_handle_Trend_EMA_Slow, 0, 0, 5, ema_slow) <= 0 ||
       CopyBuffer(g_handle_Trend_EMA_Filter, 0, 0, 5, ema_filter) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 5, close) <= 0 ||
       CopyHigh(_Symbol, PERIOD_M5, 0, 5, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 5, low) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
    bool uptrend = (close[0] > ema_filter[0] && ema_slow[0] > ema_filter[0]);
    bool downtrend = (close[0] < ema_filter[0] && ema_slow[0] < ema_filter[0]);
    
    if(uptrend)
    {
        bool pullback = (low[1] <= ema_fast[1] || close[1] <= ema_fast[1]);
        bool bounce = (close[0] > ema_fast[0]);
        bool trend_intact = (ema_fast[0] > ema_slow[0]);
        
        if(pullback && bounce && trend_intact)
        {
            Print("TREND LONG SIGNAL");
            ExecuteTrade(ORDER_TYPE_BUY, current_atr, Trend_SL_ATR, Trend_TP_ATR, "TREND");
            g_tradesToday++;
        }
    }
    
    if(downtrend)
    {
        bool pullback = (high[1] >= ema_fast[1] || close[1] >= ema_fast[1]);
        bool bounce = (close[0] < ema_fast[0]);
        bool trend_intact = (ema_fast[0] < ema_slow[0]);
        
        if(pullback && bounce && trend_intact)
        {
            Print("TREND SHORT SIGNAL");
            ExecuteTrade(ORDER_TYPE_SELL, current_atr, Trend_SL_ATR, Trend_TP_ATR, "TREND");
            g_tradesToday++;
        }
    }
}

void CheckRangeEntry()
{
    double rsi[], bb_upper[], bb_lower[], atr[], close[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_lower, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_Range_RSI, 0, 0, 3, rsi) <= 0 ||
       CopyBuffer(g_handle_Range_BB, 1, 0, 3, bb_upper) <= 0 ||
       CopyBuffer(g_handle_Range_BB, 2, 0, 3, bb_lower) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        return;
    }
    
    double current_rsi = rsi[0];
    double current_atr = atr[0];
    double current_price = close[0];
    
    if(current_rsi < Range_RSI_Oversold && current_price < bb_lower[0])
    {
        Print("RANGE BUY SIGNAL | RSI=", NormalizeDouble(current_rsi, 2));
        ExecuteTrade(ORDER_TYPE_BUY, current_atr, Range_SL_ATR, Range_TP_ATR, "RANGE");
        g_tradesToday++;
    }
    
    if(current_rsi > Range_RSI_Overbought && current_price > bb_upper[0])
    {
        Print("RANGE SELL SIGNAL | RSI=", NormalizeDouble(current_rsi, 2));
        ExecuteTrade(ORDER_TYPE_SELL, current_atr, Range_SL_ATR, Range_TP_ATR, "RANGE");
        g_tradesToday++;
    }
}

void ExecuteTrade(ENUM_ORDER_TYPE orderType, double atr_value, double sl_mult, double tp_mult, string strategy)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    double sl_distance = atr_value * sl_mult;
    double tp_distance = atr_value * tp_mult;
    
    double sl = (orderType == ORDER_TYPE_BUY) ? price - sl_distance : price + sl_distance;
    double tp = (orderType == ORDER_TYPE_BUY) ? price + tp_distance : price - tp_distance;
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * Risk_Percent / 100.0;
    double sl_points = MathAbs(price - sl) / _Point;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (sl_points * tickValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 50;
    request.magic = Magic_Number;
    request.comment = strategy;
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("TRADE #", g_tradesExecuted, " EXECUTED | ", strategy, " | ", 
              orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
    }
}

void ManageBreakEven()
{
    if(g_breakEvenActivated) return;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0) return;
    
    double current_atr = atr[0];
    double breakeven_start = current_atr * BreakEven_Start_ATR;
    double breakeven_profit = current_atr * BreakEven_Profit_ATR;
    
    long posType = PositionGetInteger(POSITION_TYPE);
    double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double posSL = PositionGetDouble(POSITION_SL);
    double posTP = PositionGetDouble(POSITION_TP);
    ulong posTicket = PositionGetInteger(POSITION_TICKET);
    
    double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double profit = (posType == POSITION_TYPE_BUY) ? 
                    (currentPrice - posOpenPrice) : 
                    (posOpenPrice - currentPrice);
    
    if(profit < breakeven_start) return;
    
    double newSL = (posType == POSITION_TYPE_BUY) ? 
                   posOpenPrice + breakeven_profit : 
                   posOpenPrice - breakeven_profit;
    newSL = NormalizeDouble(newSL, _Digits);
    
    bool should_modify = (posType == POSITION_TYPE_BUY) ? 
                         (newSL > posSL && newSL < currentPrice) : 
                         ((posSL == 0 || newSL < posSL) && newSL > currentPrice);
    
    if(should_modify)
    {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        request.action = TRADE_ACTION_SLTP;
        request.position = posTicket;
        request.sl = newSL;
        request.tp = posTP;
        if(OrderSend(request, result))
        {
            g_breakEvenActivated = true;
            Print("Break-Even activated");
        }
    }
}

void ManageTrailingStop()
{
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0) return;
    
    double current_atr = atr[0];
    double trailing_start = current_atr * Trailing_Start_ATR;
    double trailing_step = current_atr * Trailing_Step_ATR;
    
    long posType = PositionGetInteger(POSITION_TYPE);
    double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double posSL = PositionGetDouble(POSITION_SL);
    double posTP = PositionGetDouble(POSITION_TP);
    ulong posTicket = PositionGetInteger(POSITION_TICKET);
    
    double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double profit = (posType == POSITION_TYPE_BUY) ? 
                    (currentPrice - posOpenPrice) : 
                    (posOpenPrice - currentPrice);
    
    if(profit < trailing_start) return;
    
    double newSL = (posType == POSITION_TYPE_BUY) ? 
                   currentPrice - trailing_step : 
                   currentPrice + trailing_step;
    newSL = NormalizeDouble(newSL, _Digits);
    
    bool should_modify = (posType == POSITION_TYPE_BUY) ? 
                         (newSL > posSL && newSL < currentPrice) : 
                         ((posSL == 0 || newSL < posSL) && newSL > currentPrice);
    
    if(should_modify)
    {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        request.action = TRADE_ACTION_SLTP;
        request.position = posTicket;
        request.sl = newSL;
        request.tp = posTP;
        OrderSend(request, result);
    }
}

void UpdateDailyProfit()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_dailyProfit = equity - balance;
    
    double dailyLossLimit = balance * (Max_Daily_Loss_Percent / 100.0);
    
    if(g_dailyProfit <= -dailyLossLimit && !g_dailyLossReached)
    {
        g_dailyLossReached = true;
        Print("DAILY LOSS LIMIT REACHED");
        
        if(PositionSelect(_Symbol))
        {
            ulong posTicket = PositionGetInteger(POSITION_TICKET);
            long posType = PositionGetInteger(POSITION_TYPE);
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_DEAL;
            request.position = posTicket;
            request.symbol = _Symbol;
            request.volume = posVolume;
            request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (posType == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 50;
            request.magic = Magic_Number;
            request.comment = "Daily Loss Limit";
            request.type_filling = ORDER_FILLING_IOC;
            
            OrderSend(request, result);
        }
    }
}

void OnDeinit(const int reason)
{
    if(g_handle_ADX != INVALID_HANDLE) IndicatorRelease(g_handle_ADX);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    if(g_handle_Trend_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_Trend_EMA_Fast);
    if(g_handle_Trend_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_Trend_EMA_Slow);
    if(g_handle_Trend_EMA_Filter != INVALID_HANDLE) IndicatorRelease(g_handle_Trend_EMA_Filter);
    if(g_handle_Range_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_Range_RSI);
    if(g_handle_Range_BB != INVALID_HANDLE) IndicatorRelease(g_handle_Range_BB);
    if(g_handle_Range_EMA50 != INVALID_HANDLE) IndicatorRelease(g_handle_Range_EMA50);
    
    Print("HYBRID EA STOPPED - Trades: ", g_tradesExecuted);
}
//+------------------------------------------------------------------+
