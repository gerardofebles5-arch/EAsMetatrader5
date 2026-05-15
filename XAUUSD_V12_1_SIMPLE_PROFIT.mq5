//+------------------------------------------------------------------+
//|                      XAUUSD_V12_1_SIMPLE_PROFIT.mq5              |
//|     V12.1: SIMPLE PROFIT FOCUS - Sostenibilidad sobre ganancias |
//+------------------------------------------------------------------+
#property copyright "V12.1 - Simple Profit Focus"
#property version   "12.10"

input int Magic_Number = 999999;
input double Risk_Percent = 1.2;  // Ligeramente más agresivo
input int Max_Trades_Per_Day = 4;

// EMAs
input int EMA_Fast = 21;
input int EMA_Trend = 50;
input int EMA_Filter = 200;

// Risk - OPTIMIZADO PARA SOSTENIBILIDAD
input double SL_ATR_Multiplier = 1.6;  // Más espacio
input double TP_ATR_Multiplier = 3.2;  // RR 1:2 (más alcanzable)
input int ATR_Period = 14;

// Break Even - MÁS AGRESIVO
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 1.0;  // Activa rápido
input double BreakEven_Profit_ATR = 0.4;  // Protege bien

// Trailing Stop - BALANCE
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 2.0;
input double Trailing_Step_ATR = 0.8;

datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;

int g_handle_EMA_Fast;
int g_handle_EMA_Trend;
int g_handle_EMA_Filter;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("V12.1 - SIMPLE PROFIT FOCUS");
    Print("Sostenibilidad > Ganancias");
    Print("========================================");
    Print("Risk: ", Risk_Percent, "% | SL: ", SL_ATR_Multiplier, " | TP: ", TP_ATR_Multiplier);
    Print("RR: 1:", NormalizeDouble(TP_ATR_Multiplier/SL_ATR_Multiplier, 2));
    Print("========================================");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Trend = iMA(_Symbol, PERIOD_M5, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Filter = iMA(_Symbol, PERIOD_M5, EMA_Filter, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Trend == INVALID_HANDLE ||
       g_handle_EMA_Filter == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE)
    {
        return(INIT_FAILED);
    }
    
    Print("EA READY");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
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
            g_lastTradeDate = currentDate;
        }
        
        if(g_tradesToday < Max_Trades_Per_Day && !PositionSelect(_Symbol))
        {
            CheckForEntry();
        }
    }
    
    if(PositionSelect(_Symbol))
    {
        if(Use_Trailing_Stop) ManageTrailingStop();
        if(Use_Break_Even) ManageBreakEven();
    }
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
    double ema_fast[], ema_trend[], ema_filter[], atr[], close[], high[], low[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_trend, true);
    ArraySetAsSeries(ema_filter, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Trend, 0, 0, 5, ema_trend) <= 0 ||
       CopyBuffer(g_handle_EMA_Filter, 0, 0, 5, ema_filter) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 5, close) <= 0 ||
       CopyHigh(_Symbol, PERIOD_M5, 0, 5, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 5, low) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
    bool uptrend = (close[0] > ema_filter[0] && ema_trend[0] > ema_filter[0]);
    bool downtrend = (close[0] < ema_filter[0] && ema_trend[0] < ema_filter[0]);
    
    if(uptrend)
    {
        bool pullback = (low[1] <= ema_fast[1] || close[1] <= ema_fast[1]);
        bool bounce = (close[0] > ema_fast[0]);
        bool trend_intact = (ema_fast[0] > ema_trend[0]);
        
        if(pullback && bounce && trend_intact)
        {
            ExecuteTrade(ORDER_TYPE_BUY, current_atr);
            g_tradesToday++;
        }
    }
    
    if(downtrend)
    {
        bool pullback = (high[1] >= ema_fast[1] || close[1] >= ema_fast[1]);
        bool bounce = (close[0] < ema_fast[0]);
        bool trend_intact = (ema_fast[0] < ema_trend[0]);
        
        if(pullback && bounce && trend_intact)
        {
            ExecuteTrade(ORDER_TYPE_SELL, current_atr);
            g_tradesToday++;
        }
    }
}

//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, double atr_value)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    double sl_distance = atr_value * SL_ATR_Multiplier;
    double tp_distance = atr_value * TP_ATR_Multiplier;
    
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
    request.comment = "V12.1";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("TRADE #", g_tradesExecuted);
    }
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
void ManageBreakEven()
{
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
        OrderSend(request, result);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Trend != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Trend);
    if(g_handle_EMA_Filter != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Filter);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("V12.1 FINALIZADO - Trades: ", g_tradesExecuted);
}
//+------------------------------------------------------------------+
