//+------------------------------------------------------------------+
//|                        XAUUSD_V6_2B_CONFIG_A_AGRESIVO.mq5        |
//|                    CONFIGURACIÓN A: RR 1:4 AGRESIVO              |
//|    SL 1.2×ATR, TP 4.8×ATR - Objetivo: PF 3.0+                   |
//+------------------------------------------------------------------+
#property copyright "V6.2B Config A - Agresivo"
#property version   "6.22"
#property strict

// Parámetros de entrada
input int Magic_Number = 999999;
input double Risk_Percent = 1.0;
input int Max_Trades_Per_Day = 5;

// EMAs
input int EMA_Fast = 9;
input int EMA_Medium = 21;
input int EMA_Slow = 50;

// Risk Management - CONFIGURACIÓN A
input double SL_ATR_Multiplier = 1.2;     // SL MÁS AJUSTADO
input double TP_ATR_Multiplier = 4.8;     // RR 1:4
input int ATR_Period = 14;

// Break-Even - CONFIGURACIÓN A
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 1.5;
input double BreakEven_Profit_ATR = 0.3;

// Trailing Stop - CONFIGURACIÓN A
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 2.5;
input double Trailing_Step_ATR = 0.8;

// Filtro de Sesión
input bool Filter_Session = false;
input int Session_Start_Hour = 8;
input int Session_End_Hour = 16;

// Variables globales
datetime g_lastBarTime = 0;
int g_barCount = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;

// Handles de indicadores
int g_handle_EMA_Fast;
int g_handle_EMA_Medium;
int g_handle_EMA_Slow;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD V6.2B - CONFIGURACIÓN A AGRESIVO");
    Print("========================================");
    Print("RR: 1:4 (SL 1.2×ATR, TP 4.8×ATR)");
    Print("Break-Even: 1.5×ATR → +0.3×ATR");
    Print("Trailing: Start 2.5×ATR, Step 0.8×ATR");
    Print("Objetivo: PF 3.0+");
    Print("========================================");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Medium = iMA(_Symbol, PERIOD_M5, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Medium == INVALID_HANDLE ||
       g_handle_EMA_Slow == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE)
    {
        Print("❌ Error al crear indicadores");
        return(INIT_FAILED);
    }
    
    g_lastBarTime = 0;
    g_barCount = 0;
    g_tradesExecuted = 0;
    g_tradesToday = 0;
    g_lastTradeDate = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        g_barCount++;
        
        // Resetear contador diario
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
        
        if(currentDate != g_lastTradeDate)
        {
            g_tradesToday = 0;
            g_lastTradeDate = currentDate;
        }
        
        if(g_tradesToday >= Max_Trades_Per_Day)
        {
            return;
        }
        
        if(!PositionSelect(_Symbol))
        {
            CheckForEntry();
        }
    }
    
    if(Use_Trailing_Stop && PositionSelect(_Symbol))
    {
        ManageTrailingStop();
    }
    
    if(Use_Break_Even && PositionSelect(_Symbol))
    {
        ManageBreakEven();
    }
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
    if(Filter_Session)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        
        if(dt.hour < Session_Start_Hour || dt.hour >= Session_End_Hour)
        {
            return;
        }
    }
    
    double ema_fast[], ema_medium[], ema_slow[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_medium, true);
    ArraySetAsSeries(ema_slow, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Medium, 0, 0, 5, ema_medium) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 5, ema_slow) <= 0)
    {
        return;
    }
    
    double atr[];
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
    double close[];
    ArraySetAsSeries(close, true);
    
    if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        return;
    }
    
    bool long_signal = false;
    if(close[1] < ema_fast[1] && close[0] > ema_fast[0])
    {
        if(ema_fast[0] > ema_medium[0] && ema_medium[0] > ema_slow[0])
        {
            long_signal = true;
        }
    }
    
    bool short_signal = false;
    if(close[1] > ema_fast[1] && close[0] < ema_fast[0])
    {
        if(ema_fast[0] < ema_medium[0] && ema_medium[0] < ema_slow[0])
        {
            short_signal = true;
        }
    }
    
    if(long_signal)
    {
        Print("📈 SEÑAL LONG - Config A");
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
        g_tradesToday++;
    }
    else if(short_signal)
    {
        Print("📉 SEÑAL SHORT - Config A");
        ExecuteTrade(ORDER_TYPE_SELL, current_atr);
        g_tradesToday++;
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
    
    double sl, tp;
    if(orderType == ORDER_TYPE_BUY)
    {
        sl = price - sl_distance;
        tp = price + tp_distance;
    }
    else
    {
        sl = price + sl_distance;
        tp = price - tp_distance;
    }
    
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
    request.comment = "V6.2B-A";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ TRADE #", g_tradesExecuted, " | RR 1:4");
    }
}

//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!PositionSelect(_Symbol)) return;
    
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
    
    double newSL = 0;
    
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = currentPrice - trailing_step;
        newSL = NormalizeDouble(newSL, _Digits);
        
        if(newSL > posSL && newSL < currentPrice)
        {
            ModifyPosition(posTicket, newSL, posTP);
        }
    }
    else
    {
        newSL = currentPrice + trailing_step;
        newSL = NormalizeDouble(newSL, _Digits);
        
        if((posSL == 0 || newSL < posSL) && newSL > currentPrice)
        {
            ModifyPosition(posTicket, newSL, posTP);
        }
    }
}

//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl, double tp)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = sl;
    request.tp = tp;
    
    bool sent = OrderSend(request, result);
    if(!sent || result.retcode != TRADE_RETCODE_DONE)
    {
        Print("⚠️ Error modificando posición: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
void ManageBreakEven()
{
    if(!PositionSelect(_Symbol)) return;
    
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
    
    double newSL = 0;
    bool shouldModify = false;
    
    if(posType == POSITION_TYPE_BUY)
    {
        newSL = posOpenPrice + breakeven_profit;
        newSL = NormalizeDouble(newSL, _Digits);
        
        if(newSL > posSL && newSL < currentPrice)
        {
            shouldModify = true;
        }
    }
    else
    {
        newSL = posOpenPrice - breakeven_profit;
        newSL = NormalizeDouble(newSL, _Digits);
        
        if((posSL == 0 || newSL < posSL) && newSL > currentPrice)
        {
            shouldModify = true;
        }
    }
    
    if(shouldModify)
    {
        ModifyPosition(posTicket, newSL, posTP);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Medium != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Medium);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("========================================");
    Print("CONFIG A FINALIZADO");
    Print("Total Trades: ", g_tradesExecuted);
    Print("========================================");
}
//+------------------------------------------------------------------+
