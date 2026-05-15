//+------------------------------------------------------------------+
//|                         XAUUSD_V7_1_RANGE_ONLY.mq5               |
//|          V7.1: SOLO OPERA EN RANGOS - EVITA TENDENCIAS           |
//|   Aprendizaje: Config A ganó en rangos, perdió en tendencias     |
//+------------------------------------------------------------------+
#property copyright "V7.1 - Range Only System"
#property version   "7.10"
#property strict

input int Magic_Number = 999999;
input double Risk_Percent = 1.0;
input int Max_Trades_Per_Day = 5;

// EMAs
input int EMA_Fast = 9;
input int EMA_Medium = 21;
input int EMA_Slow = 50;

// Risk Management (AJUSTADO PARA RANGOS)
input double SL_ATR_Multiplier = 1.8;     // Más amplio que Config A
input double TP_ATR_Multiplier = 3.6;     // Más cercano (RR 1:2)
input int ATR_Period = 14;

// FILTROS DE TENDENCIA (NUEVO)
input bool Use_ADX_Filter = true;
input int ADX_Period = 14;
input double Max_ADX_Trend = 35.0;        // ADX > 35 = tendencia FUERTE (NO operar)

input bool Use_Distance_Filter = true;
input double Max_Distance_Percent = 3.5;  // Max 3.5% distancia a EMA 50

// Filtro ATR
input bool Use_ATR_Filter = true;
input double Min_ATR_Points = 10.0;
input double Max_ATR_Points = 80.0;       // NUEVO: No operar con volatilidad extrema

// Variables globales
datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;

// Handles
int g_handle_EMA_Fast;
int g_handle_EMA_Medium;
int g_handle_EMA_Slow;
int g_handle_ATR;
int g_handle_ADX;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD V7.1 - RANGE ONLY SYSTEM");
    Print("========================================");
    Print("Estrategia: Solo opera en RANGOS");
    Print("Filtro ADX: ", Use_ADX_Filter ? "ACTIVO" : "OFF");
    Print("Filtro Distancia: ", Use_Distance_Filter ? "ACTIVO" : "OFF");
    Print("RR: 1:2 (SL 1.8×ATR, TP 3.6×ATR)");
    Print("Aprendizaje: Evita tendencias fuertes");
    Print("========================================");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Medium = iMA(_Symbol, PERIOD_M5, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    g_handle_ADX = iADX(_Symbol, PERIOD_M5, ADX_Period);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Medium == INVALID_HANDLE ||
       g_handle_EMA_Slow == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE ||
       g_handle_ADX == INVALID_HANDLE)
    {
        Print("❌ Error al crear indicadores");
        return(INIT_FAILED);
    }
    
    g_lastBarTime = 0;
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
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
    // Obtener datos
    double ema_fast[], ema_medium[], ema_slow[], atr[], adx[], close[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_medium, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(adx, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Medium, 0, 0, 5, ema_medium) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 5, ema_slow) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyBuffer(g_handle_ADX, 0, 0, 3, adx) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 5, close) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    double current_adx = adx[0];
    
    // FILTRO 1: ATR (Volatilidad)
    if(Use_ATR_Filter)
    {
        double atr_points = current_atr / _Point;
        if(atr_points < Min_ATR_Points || atr_points > Max_ATR_Points)
        {
            return; // Volatilidad muy baja o muy alta
        }
    }
    
    // FILTRO 2: ADX (Detectar tendencia)
    if(Use_ADX_Filter)
    {
        if(current_adx > Max_ADX_Trend)
        {
            Print("⚠️ ADX = ", current_adx, " > ", Max_ADX_Trend, " - TENDENCIA detectada, NO operar");
            return; // Mercado en tendencia, NO operar
        }
    }
    
    // FILTRO 3: Distancia a EMA 50 (Detectar tendencia)
    if(Use_Distance_Filter)
    {
        double distance = MathAbs(close[0] - ema_slow[0]) / ema_slow[0] * 100;
        if(distance > Max_Distance_Percent)
        {
            Print("⚠️ Distancia a EMA50 = ", distance, "% > ", Max_Distance_Percent, "% - TENDENCIA detectada, NO operar");
            return; // Precio muy lejos de EMA 50 = tendencia
        }
    }
    
    // SEÑAL LONG
    bool long_signal = false;
    if(close[1] < ema_fast[1] && close[0] > ema_fast[0])
    {
        if(ema_fast[0] > ema_medium[0] && ema_medium[0] > ema_slow[0])
        {
            long_signal = true;
        }
    }
    
    // SEÑAL SHORT
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
        Print("✅ RANGO detectado (ADX=", current_adx, ") - SEÑAL LONG");
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
        g_tradesToday++;
    }
    else if(short_signal)
    {
        Print("✅ RANGO detectado (ADX=", current_adx, ") - SEÑAL SHORT");
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
    
    Print("=== TRADE V7.1 RANGE ONLY ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price, " | SL: ", sl, " | TP: ", tp);
    Print("RR: 1:2 | Lote: ", lotSize);
    
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
    request.comment = "V7.1-RNG";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ TRADE #", g_tradesExecuted, " EJECUTADO (Range Only)");
    }
    else
    {
        Print("❌ TRADE FALLÓ - Retcode: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Medium != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Medium);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    if(g_handle_ADX != INVALID_HANDLE) IndicatorRelease(g_handle_ADX);
    
    Print("========================================");
    Print("V7.1 RANGE ONLY FINALIZADO");
    Print("Total Trades: ", g_tradesExecuted);
    Print("========================================");
}
//+------------------------------------------------------------------+
