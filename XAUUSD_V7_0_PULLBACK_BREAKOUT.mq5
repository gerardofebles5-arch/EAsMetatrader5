//+------------------------------------------------------------------+
//|                      XAUUSD_V7_0_PULLBACK_BREAKOUT.mq5           |
//|           V7.0: ESTRATEGIA PULLBACK + BREAKOUT CONFIRMADO        |
//|   Basada en investigación: NO entra inmediatamente, espera       |
//|   pullback y confirma breakout antes de entrar                   |
//+------------------------------------------------------------------+
#property copyright "V7.0 - Pullback Breakout System"
#property version   "7.00"
#property strict

// Parámetros de entrada
input int Magic_Number = 999999;
input double Risk_Percent = 1.0;
input int Max_Trades_Per_Day = 3;

// EMAs
input int EMA_Fast = 9;
input int EMA_Medium = 21;
input int EMA_Slow = 50;

// Risk Management
input double SL_ATR_Multiplier = 2.5;     // Basado en investigación
input double TP_ATR_Multiplier = 10.0;    // RR 1:4
input int ATR_Period = 14;

// Pullback Settings
input int Max_Pullback_Candles = 3;       // Esperar 1-3 velas pullback
input double Breakout_ATR_Multiplier = 0.5; // Nivel de breakout

// Filtros
input bool Use_ATR_Filter = true;
input double Min_ATR_Points = 20.0;

// Variables globales
datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;

// State Machine
enum ENUM_TRADE_STATE
{
    STATE_SCANNING,      // Buscando señal inicial
    STATE_ARMED,         // Señal detectada, esperando pullback
    STATE_WINDOW_OPEN    // Pullback completado, esperando breakout
};

ENUM_TRADE_STATE g_currentState = STATE_SCANNING;
datetime g_stateStartTime = 0;
int g_pullbackCandles = 0;
double g_breakoutLevel = 0;
ENUM_ORDER_TYPE g_pendingDirection = ORDER_TYPE_BUY;

// Handles de indicadores
int g_handle_EMA_Fast;
int g_handle_EMA_Medium;
int g_handle_EMA_Slow;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD V7.0 - PULLBACK BREAKOUT SYSTEM");
    Print("========================================");
    Print("Estrategia: Espera pullback + confirma breakout");
    Print("RR: 1:4 (SL 2.5×ATR, TP 10×ATR)");
    Print("Max Pullback: ", Max_Pullback_Candles, " velas");
    Print("Basado en investigación de estrategias rentables");
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
    
    g_currentState = STATE_SCANNING;
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
            ProcessStateMachine();
        }
    }
}

//+------------------------------------------------------------------+
void ProcessStateMachine()
{
    // Obtener datos
    double ema_fast[], ema_medium[], ema_slow[], atr[], close[], high[], low[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_medium, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Medium, 0, 0, 5, ema_medium) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 5, ema_slow) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 5, close) <= 0 ||
       CopyHigh(_Symbol, PERIOD_M5, 0, 5, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 5, low) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
    // Filtro de volatilidad
    if(Use_ATR_Filter && (current_atr / _Point) < Min_ATR_Points)
    {
        return;
    }
    
    // STATE MACHINE
    switch(g_currentState)
    {
        case STATE_SCANNING:
            CheckForInitialSignal(ema_fast, ema_medium, ema_slow, close);
            break;
            
        case STATE_ARMED:
            CheckForPullback(close, high, low);
            break;
            
        case STATE_WINDOW_OPEN:
            CheckForBreakout(close, high, low, current_atr);
            break;
    }
}

//+------------------------------------------------------------------+
void CheckForInitialSignal(double &ema_fast[], double &ema_medium[], double &ema_slow[], double &close[])
{
    // LONG: Precio cruza EMA Fast + EMAs alineadas
    bool long_signal = false;
    if(close[1] < ema_fast[1] && close[0] > ema_fast[0])
    {
        if(ema_fast[0] > ema_medium[0] && ema_medium[0] > ema_slow[0])
        {
            long_signal = true;
        }
    }
    
    // SHORT: Precio cruza EMA Fast + EMAs alineadas
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
        Print("📊 FASE 1: Señal LONG detectada - Esperando pullback");
        g_currentState = STATE_ARMED;
        g_pendingDirection = ORDER_TYPE_BUY;
        g_stateStartTime = TimeCurrent();
        g_pullbackCandles = 0;
    }
    else if(short_signal)
    {
        Print("📊 FASE 1: Señal SHORT detectada - Esperando pullback");
        g_currentState = STATE_ARMED;
        g_pendingDirection = ORDER_TYPE_SELL;
        g_stateStartTime = TimeCurrent();
        g_pullbackCandles = 0;
    }
}

//+------------------------------------------------------------------+
void CheckForPullback(double &close[], double &high[], double &low[])
{
    g_pullbackCandles++;
    
    // Verificar si hay pullback (movimiento contra-tendencia)
    bool pullback_detected = false;
    
    if(g_pendingDirection == ORDER_TYPE_BUY)
    {
        // Para LONG, pullback = vela bajista
        if(close[0] < close[1])
        {
            pullback_detected = true;
        }
    }
    else
    {
        // Para SHORT, pullback = vela alcista
        if(close[0] > close[1])
        {
            pullback_detected = true;
        }
    }
    
    if(pullback_detected && g_pullbackCandles <= Max_Pullback_Candles)
    {
        Print("📊 FASE 2: Pullback detectado (", g_pullbackCandles, "/", Max_Pullback_Candles, ") - Abriendo ventana");
        g_currentState = STATE_WINDOW_OPEN;
        
        // Establecer nivel de breakout
        if(g_pendingDirection == ORDER_TYPE_BUY)
        {
            g_breakoutLevel = high[0]; // Romper máximo del pullback
        }
        else
        {
            g_breakoutLevel = low[0];  // Romper mínimo del pullback
        }
    }
    else if(g_pullbackCandles > Max_Pullback_Candles)
    {
        Print("⚠️ Pullback excedió máximo - Volviendo a SCANNING");
        g_currentState = STATE_SCANNING;
    }
}

//+------------------------------------------------------------------+
void CheckForBreakout(double &close[], double &high[], double &low[], double current_atr)
{
    bool breakout = false;
    
    if(g_pendingDirection == ORDER_TYPE_BUY)
    {
        // LONG: Precio rompe por encima del nivel
        if(close[0] > g_breakoutLevel)
        {
            breakout = true;
        }
    }
    else
    {
        // SHORT: Precio rompe por debajo del nivel
        if(close[0] < g_breakoutLevel)
        {
            breakout = true;
        }
    }
    
    if(breakout)
    {
        Print("🚀 FASE 3: BREAKOUT CONFIRMADO - Ejecutando trade");
        ExecuteTrade(g_pendingDirection, current_atr);
        g_tradesToday++;
        g_currentState = STATE_SCANNING;
    }
    else
    {
        // Si pasan 5 velas sin breakout, cancelar
        if((TimeCurrent() - g_stateStartTime) > 5 * PeriodSeconds(PERIOD_M5))
        {
            Print("⚠️ Ventana cerrada sin breakout - Volviendo a SCANNING");
            g_currentState = STATE_SCANNING;
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
    
    Print("=== TRADE V7.0 PULLBACK BREAKOUT ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price, " | SL: ", sl, " | TP: ", tp);
    Print("RR: 1:4 | Lote: ", lotSize);
    
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
    request.comment = "V7.0-PB";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ TRADE #", g_tradesExecuted, " EJECUTADO (Pullback+Breakout)");
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
    
    Print("========================================");
    Print("V7.0 PULLBACK BREAKOUT FINALIZADO");
    Print("Total Trades: ", g_tradesExecuted);
    Print("========================================");
}
//+------------------------------------------------------------------+
