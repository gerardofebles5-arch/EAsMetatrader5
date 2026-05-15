//+------------------------------------------------------------------+
//|                        XAUUSD_V11_0_HYBRID_BEST.mq5              |
//|     V11.0: HYBRID - Combina V10.0 original + Mejores prácticas  |
//+------------------------------------------------------------------+
#property copyright "V11.0 - Hybrid Best"
#property version   "11.00"

input int Magic_Number = 999999;
input double Risk_Percent = 0.8;  // Balance: no muy bajo, no muy alto
input int Max_Trades_Per_Day = 4;
input double Max_Daily_Loss_Percent = 3.0;

// EMAs - Configuración original V10.0
input int EMA_Fast = 21;
input int EMA_Trend = 50;
input int EMA_Filter = 200;

// Risk - Optimizado para rentabilidad
input double SL_ATR_Multiplier = 1.3;  // Más amplio que 1.0, más ajustado que 1.5
input double TP_ATR_Multiplier = 4.0;  // RR 1:3.08 (alcanzable)
input int ATR_Period = 14;

// Partial Close - Técnica profesional
input bool Use_Partial_Close = true;
input double Partial_Close_Percent = 50.0;
input double Partial_Close_ATR = 2.0;  // Más conservador que 1.5

// Break Even - Más conservador
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 1.2;  // Entre 0.8 y 1.6
input double BreakEven_Profit_ATR = 0.3;

// Trailing Stop - Optimizado
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 2.2;  // Entre 1.5 y 3.0
input double Trailing_Step_ATR = 0.7;

// NUEVO: Filtro de Volatilidad (de EAs rentables)
input bool Use_Volatility_Filter = true;
input double Min_ATR_Points = 3.0;  // Mínimo ATR para operar
input double Max_ATR_Points = 15.0; // Máximo ATR (evita volatilidad extrema)

// NUEVO: Filtro de Momentum (de EAs rentables)
input bool Use_Momentum_Filter = true;
input double Min_EMA_Angle = 0.0001;  // Ángulo mínimo de EMA21

datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;
double g_dailyProfit = 0.0;
bool g_dailyLossReached = false;
bool g_partialClosed = false;  // Track si ya se hizo partial close

int g_handle_EMA_Fast;
int g_handle_EMA_Trend;
int g_handle_EMA_Filter;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("V11.0 - HYBRID BEST (V10.0 + Optimizations)");
    Print("========================================");
    Print("Risk: ", Risk_Percent, "% | SL: ", SL_ATR_Multiplier, " ATR | TP: ", TP_ATR_Multiplier, " ATR");
    Print("Break Even: ", BreakEven_Start_ATR, " ATR | Trailing: ", Trailing_Start_ATR, " ATR");
    Print("Partial Close: ", Use_Partial_Close ? "ON" : "OFF", " at ", Partial_Close_ATR, " ATR");
    Print("Volatility Filter: ", Use_Volatility_Filter ? "ON" : "OFF");
    Print("Momentum Filter: ", Use_Momentum_Filter ? "ON" : "OFF");
    Print("========================================");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Trend = iMA(_Symbol, PERIOD_M5, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Filter = iMA(_Symbol, PERIOD_M5, EMA_Filter, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Trend == INVALID_HANDLE ||
       g_handle_EMA_Filter == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators!");
        return(INIT_FAILED);
    }
    
    Print("EA READY - Waiting for signals...");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
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
        
        if(g_dailyLossReached) return;
        
        if(g_tradesToday < Max_Trades_Per_Day && !PositionSelect(_Symbol))
        {
            g_partialClosed = false;  // Reset para nuevo trade
            CheckForEntry();
        }
    }
    
    if(PositionSelect(_Symbol))
    {
        if(Use_Partial_Close && !g_partialClosed) ManagePartialClose();
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
    
    // FILTRO DE VOLATILIDAD (de EAs rentables)
    if(Use_Volatility_Filter)
    {
        if(current_atr < Min_ATR_Points || current_atr > Max_ATR_Points)
        {
            Print("Volatility filter: ATR ", current_atr, " out of range [", Min_ATR_Points, "-", Max_ATR_Points, "]");
            return;
        }
    }
    
    // FILTRO DE MOMENTUM (de EAs rentables)
    if(Use_Momentum_Filter)
    {
        double ema_angle = (ema_fast[0] - ema_fast[2]) / ema_fast[2];
        if(MathAbs(ema_angle) < Min_EMA_Angle)
        {
            Print("Momentum filter: EMA angle too flat");
            return;
        }
    }
    
    // Tendencia alcista
    bool uptrend = (close[0] > ema_filter[0] && ema_trend[0] > ema_filter[0]);
    
    // Tendencia bajista
    bool downtrend = (close[0] < ema_filter[0] && ema_trend[0] < ema_filter[0]);
    
    // LONG: Tendencia alcista + Pullback
    if(uptrend)
    {
        bool pullback = (low[1] <= ema_fast[1] || close[1] <= ema_fast[1]);
        bool bounce = (close[0] > ema_fast[0]);
        bool trend_intact = (ema_fast[0] > ema_trend[0]);
        
        if(pullback && bounce && trend_intact)
        {
            Print(">>> LONG SIGNAL <<<");
            ExecuteTrade(ORDER_TYPE_BUY, current_atr);
            g_tradesToday++;
        }
    }
    
    // SHORT: Tendencia bajista + Pullback
    if(downtrend)
    {
        bool pullback = (high[1] >= ema_fast[1] || close[1] >= ema_fast[1]);
        bool bounce = (close[0] < ema_fast[0]);
        bool trend_intact = (ema_fast[0] < ema_trend[0]);
        
        if(pullback && bounce && trend_intact)
        {
            Print(">>> SHORT SIGNAL <<<");
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
    request.comment = "V11.0";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("TRADE #", g_tradesExecuted, " EXECUTED | Ticket: ", result.order);
    }
    else
    {
        Print("TRADE FAILED: ", result.retcode, " - ", result.comment);
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
void ManagePartialClose()
{
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0) return;
    
    double current_atr = atr[0];
    double partial_target = current_atr * Partial_Close_ATR;
    
    long posType = PositionGetInteger(POSITION_TYPE);
    double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double posVolume = PositionGetDouble(POSITION_VOLUME);
    ulong posTicket = PositionGetInteger(POSITION_TICKET);
    
    double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double profit = (posType == POSITION_TYPE_BUY) ? 
                    (currentPrice - posOpenPrice) : 
                    (posOpenPrice - currentPrice);
    
    if(profit < partial_target) return;
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(posVolume <= minLot * 1.5) return;
    
    double closeVolume = posVolume * (Partial_Close_Percent / 100.0);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
    closeVolume = MathMax(minLot, closeVolume);
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    request.action = TRADE_ACTION_DEAL;
    request.position = posTicket;
    request.symbol = _Symbol;
    request.volume = closeVolume;
    request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = currentPrice;
    request.deviation = 50;
    request.magic = Magic_Number;
    request.comment = "Partial";
    request.type_filling = ORDER_FILLING_IOC;
    
    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE)
    {
        g_partialClosed = true;
        Print("Partial Close: ", closeVolume, " lots");
    }
}

//+------------------------------------------------------------------+
void UpdateDailyProfit()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_dailyProfit = equity - balance;
    
    double dailyLossLimit = balance * (Max_Daily_Loss_Percent / 100.0);
    
    if(g_dailyProfit <= -dailyLossLimit && !g_dailyLossReached)
    {
        g_dailyLossReached = true;
        Print("DAILY LOSS LIMIT REACHED: ", g_dailyProfit);
        
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
            request.comment = "Daily Loss";
            request.type_filling = ORDER_FILLING_IOC;
            
            OrderSend(request, result);
        }
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Trend != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Trend);
    if(g_handle_EMA_Filter != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Filter);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("V11.0 FINALIZADO - Trades: ", g_tradesExecuted);
}
//+------------------------------------------------------------------+
