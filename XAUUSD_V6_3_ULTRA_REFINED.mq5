//+------------------------------------------------------------------+
//|                           XAUUSD_V6_3_ULTRA_REFINED.mq5          |
//|                V6.3: ULTRA REFINADO - FILTROS OPCIONALES         |
//|      Filtros desactivados por defecto para mayor operatividad   |
//+------------------------------------------------------------------+
#property copyright "V6.3 - Ultra Refined - Filters Optional"
#property version   "6.30"
#property strict

// Parámetros de entrada
input int Magic_Number = 999999;
input double Risk_Percent = 1.0;
input int Max_Trades_Per_Day = 5;

// EMAs
input int EMA_Fast = 9;
input int EMA_Medium = 21;
input int EMA_Slow = 50;

// RSI Filter
input bool Use_RSI_Filter = false;        // Desactivado por defecto
input int RSI_Period = 14;
input int RSI_Overbought = 70;
input int RSI_Oversold = 30;

// ADX Filter (Trend Strength)
input bool Use_ADX_Filter = false;        // Desactivado por defecto
input int ADX_Period = 14;
input double ADX_Min_Level = 20.0;

// Risk Management
input double SL_ATR_Multiplier = 1.5;
input double TP_ATR_Multiplier = 4.5;
input int ATR_Period = 14;

// Break-Even
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 2.0;
input double BreakEven_Profit_ATR = 0.5;

// Trailing Stop
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 3.0;
input double Trailing_Step_ATR = 1.0;

// Filtro de Sesión
input bool Filter_Session = false;        // Desactivado por defecto
input int Session_Start_Hour = 8;
input int Session_End_Hour = 16;

// Variables globales
datetime g_lastBarTime = 0;
int g_barCount = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;
datetime g_lastTradeBar = 0;  // Evitar múltiples trades en misma vela

// Handles de indicadores
int g_handle_EMA_Fast;
int g_handle_EMA_Medium;
int g_handle_EMA_Slow;
int g_handle_ATR;
int g_handle_RSI;
int g_handle_ADX;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD V6.3 ULTRA REFINED");
    Print("========================================");
    Print("SEÑAL: EMAs alineadas (SIN cruce requerido)");
    Print("Filtros RSI/ADX/Sesión DESACTIVADOS");
    Print("Break-Even y Trailing Stop ACTIVOS");
    Print("========================================");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Medium = iMA(_Symbol, PERIOD_M5, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    g_handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    g_handle_ADX = iADX(_Symbol, PERIOD_M5, ADX_Period);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Medium == INVALID_HANDLE ||
       g_handle_EMA_Slow == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE ||
       g_handle_RSI == INVALID_HANDLE || g_handle_ADX == INVALID_HANDLE)
    {
        Print("❌ Error al crear indicadores");
        return(INIT_FAILED);
    }
    
    g_lastBarTime = 0;
    g_barCount = 0;
    g_tradesExecuted = 0;
    g_tradesToday = 0;
    g_lastTradeDate = 0;
    g_lastTradeBar = 0;
    
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
    
    // Gestión de posición
    if(PositionSelect(_Symbol))
    {
        if(Use_Break_Even)
        {
            ManageBreakEven();
        }
        
        if(Use_Trailing_Stop)
        {
            ManageTrailingStop();
        }
    }
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
    // Evitar múltiples trades en la misma vela
    datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
    if(currentBar == g_lastTradeBar)
    {
        return;
    }
    
    // Filtro de sesión
    if(Filter_Session)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        
        if(dt.hour < Session_Start_Hour || dt.hour >= Session_End_Hour)
        {
            return;
        }
    }
    
    // Obtener EMAs
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
    
    // Obtener ATR
    double atr[];
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
    // Obtener RSI
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(Use_RSI_Filter && CopyBuffer(g_handle_RSI, 0, 0, 3, rsi) <= 0)
    {
        return;
    }
    
    // Obtener ADX
    double adx_main[];
    ArraySetAsSeries(adx_main, true);
    
    if(Use_ADX_Filter && CopyBuffer(g_handle_ADX, 0, 0, 3, adx_main) <= 0)
    {
        return;
    }
    
    // Filtro ADX: Solo operar en tendencias fuertes
    if(Use_ADX_Filter && adx_main[0] < ADX_Min_Level)
    {
        return;
    }
    
    // Obtener precio
    double close[];
    ArraySetAsSeries(close, true);
    
    if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        return;
    }
    
    // SEÑAL LONG: EMAs alineadas alcista
    bool long_signal = false;
    if(ema_fast[0] > ema_medium[0] && ema_medium[0] > ema_slow[0])
    {
        // Filtro RSI: No comprar si está sobrecomprado
        if(!Use_RSI_Filter || rsi[0] < RSI_Overbought)
        {
            long_signal = true;
        }
    }
    
    // SEÑAL SHORT: EMAs alineadas bajista
    bool short_signal = false;
    if(ema_fast[0] < ema_medium[0] && ema_medium[0] < ema_slow[0])
    {
        // Filtro RSI: No vender si está sobrevendido
        if(!Use_RSI_Filter || rsi[0] > RSI_Oversold)
        {
            short_signal = true;
        }
    }
    
    if(long_signal)
    {
        Print("📈 SEÑAL LONG | RSI: ", rsi[0], " | ADX: ", adx_main[0]);
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
        g_tradesToday++;
        g_lastTradeBar = iTime(_Symbol, PERIOD_M5, 0);
    }
    else if(short_signal)
    {
        Print("📉 SEÑAL SHORT | RSI: ", rsi[0], " | ADX: ", adx_main[0]);
        ExecuteTrade(ORDER_TYPE_SELL, current_atr);
        g_tradesToday++;
        g_lastTradeBar = iTime(_Symbol, PERIOD_M5, 0);
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
    
    Print("=== TRADE ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price, " | SL: ", sl, " | TP: ", tp);
    Print("RR: 1:", NormalizeDouble(tp_distance/sl_distance, 1));
    
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
    request.comment = "V6.3";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ TRADE #", g_tradesExecuted);
    }
    else
    {
        Print("❌ FALLÓ - Retcode: ", result.retcode);
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
        Print("✅ Break-Even activado: SL = ", newSL);
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
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Medium != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Medium);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    if(g_handle_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_RSI);
    if(g_handle_ADX != INVALID_HANDLE) IndicatorRelease(g_handle_ADX);
    
    Print("========================================");
    Print("V6.3 FINALIZADO");
    Print("Total Ejecutados: ", g_tradesExecuted);
    Print("========================================");
}
//+------------------------------------------------------------------+
