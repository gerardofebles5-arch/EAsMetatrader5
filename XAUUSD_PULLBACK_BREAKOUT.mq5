//+------------------------------------------------------------------+
//|                                XAUUSD_PULLBACK_BREAKOUT.mq5      |
//|                    V6.1: PULLBACK BREAKOUT - SIN FILTROS         |
//|           Basado en estrategia verificada - Filtros removidos    |
//+------------------------------------------------------------------+
#property copyright "Pullback Breakout Strategy - No Filters"
#property version   "6.10"
#property strict

// Parámetros de entrada
input int Magic_Number = 999999;
input double Risk_Percent = 1.0;          // Riesgo por trade (1%)
input int Max_Trades_Per_Day = 3;         // Máximo 3 trades/día

// EMAs
input int EMA_Fast = 14;                  // EMA Rápida
input int EMA_Medium = 18;                // EMA Media
input int EMA_Slow = 24;                  // EMA Lenta

// Pullback Settings
input int Max_Pullback_Candles = 3;       // Máximo 3 velas de pullback
input int Entry_Window_Periods = 2;       // Ventana de entrada (2 períodos)

// Risk Management
input double SL_ATR_Multiplier = 2.5;     // SL = 2.5 × ATR
input double TP_ATR_Multiplier = 10.0;    // TP = 10 × ATR (RR 1:4)

// Filtros
input double Min_EMA_Angle = 0.0;         // Ángulo mínimo EMA (0 = sin filtro)
input double Min_ATR_Points = 0.0;        // ATR mínimo (0 = sin filtro)
input int ATR_Period = 14;                // Período ATR

// Estados del sistema
enum ENUM_PHASE
{
    PHASE_SCANNING,      // Buscando señal
    PHASE_ARMED,         // Esperando pullback
    PHASE_WINDOW_OPEN,   // Ventana de entrada abierta
    PHASE_ENTRY          // Trade ejecutado
};

// Variables globales
datetime g_lastBarTime = 0;
int g_barCount = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;

ENUM_PHASE g_currentPhase = PHASE_SCANNING;
int g_pullbackCount = 0;
int g_windowCount = 0;
double g_breakoutLevel = 0;
int g_trendDirection = 0;  // 1=LONG, -1=SHORT, 0=NONE

// Handles de indicadores
int g_handle_EMA_Fast;
int g_handle_EMA_Medium;
int g_handle_EMA_Slow;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD PULLBACK BREAKOUT V6.1 - SIN FILTROS");
    Print("========================================");
    Print("Estrategia basada en investigación verificada");
    Print("Sistema de 4 fases: SCANNING → ARMED → WINDOW → ENTRY");
    Print("FILTROS REMOVIDOS para mayor operatividad");
    Print("Max trades/día: ", Max_Trades_Per_Day);
    Print("========================================");
    
    // Crear indicadores
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
    g_currentPhase = PHASE_SCANNING;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    // Detectar nueva vela M5
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
            Print("📅 Nuevo día - Contador reseteado");
        }
        
        // Verificar límite diario
        if(g_tradesToday >= Max_Trades_Per_Day)
        {
            return;
        }
        
        // Verificar si ya hay posición
        if(PositionSelect(_Symbol))
        {
            g_currentPhase = PHASE_ENTRY;
            return;
        }
        
        // Ejecutar máquina de estados
        ProcessStateMachine();
    }
}

//+------------------------------------------------------------------+
//| MÁQUINA DE ESTADOS - 4 FASES                                     |
//+------------------------------------------------------------------+
void ProcessStateMachine()
{
    Print("========================================");
    Print("VELA M5 #", g_barCount, " | Fase: ", EnumToString(g_currentPhase));
    Print("Trades hoy: ", g_tradesToday, "/", Max_Trades_Per_Day);
    
    switch(g_currentPhase)
    {
        case PHASE_SCANNING:
            Phase_Scanning();
            break;
            
        case PHASE_ARMED:
            Phase_Armed();
            break;
            
        case PHASE_WINDOW_OPEN:
            Phase_WindowOpen();
            break;
            
        case PHASE_ENTRY:
            // Esperando que se cierre la posición
            if(!PositionSelect(_Symbol))
            {
                g_currentPhase = PHASE_SCANNING;
                Print("✅ Posición cerrada - Volviendo a SCANNING");
            }
            break;
    }
}

//+------------------------------------------------------------------+
//| FASE 1: SCANNING - Buscar señal de tendencia                    |
//+------------------------------------------------------------------+
void Phase_Scanning()
{
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
    
    double current_atr = atr[0] / _Point;
    double ema_angle = CalculateEMAAngle(ema_fast);
    
    // FILTRO 1: ATR mínimo (opcional)
    if(Min_ATR_Points > 0 && current_atr < Min_ATR_Points)
    {
        Print("⚠️ ATR muy bajo (", current_atr, ") - esperando volatilidad");
        return;
    }
    
    // FILTRO 2: Calcular ángulo de EMA Fast (opcional)
    if(Min_EMA_Angle > 0 && MathAbs(ema_angle) < Min_EMA_Angle)
    {
        Print("⚠️ EMA angle débil (", ema_angle, "°) - esperando momentum");
        return;
    }
    
    // DETECTAR TENDENCIA: EMAs alineadas
    bool bullish_alignment = (ema_fast[0] > ema_medium[0] && ema_medium[0] > ema_slow[0]);
    bool bearish_alignment = (ema_fast[0] < ema_medium[0] && ema_medium[0] < ema_slow[0]);
    
    if(bullish_alignment)
    {
        g_trendDirection = 1;
        g_currentPhase = PHASE_ARMED;
        g_pullbackCount = 0;
        Print("📈 TENDENCIA ALCISTA DETECTADA - Pasando a ARMED");
        Print("   ATR: ", current_atr, " | EMA Angle: ", ema_angle, "°");
    }
    else if(bearish_alignment)
    {
        g_trendDirection = -1;
        g_currentPhase = PHASE_ARMED;
        g_pullbackCount = 0;
        Print("📉 TENDENCIA BAJISTA DETECTADA - Pasando a ARMED");
        Print("   ATR: ", current_atr, " | EMA Angle: ", ema_angle, "°");
    }
}

//+------------------------------------------------------------------+
//| FASE 2: ARMED - Esperar pullback (1-3 velas contra-tendencia)   |
//+------------------------------------------------------------------+
void Phase_Armed()
{
    double close[], open[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    
    if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0 ||
       CopyOpen(_Symbol, PERIOD_M5, 0, 3, open) <= 0)
    {
        return;
    }
    
    // Verificar invalidación global (señal opuesta)
    if(CheckGlobalInvalidation())
    {
        g_currentPhase = PHASE_SCANNING;
        Print("❌ INVALIDACIÓN GLOBAL - Volviendo a SCANNING");
        return;
    }
    
    bool is_pullback_candle = false;
    
    if(g_trendDirection == 1)
    {
        // LONG: Esperando vela bajista (pullback)
        is_pullback_candle = (close[0] < open[0]);
    }
    else if(g_trendDirection == -1)
    {
        // SHORT: Esperando vela alcista (pullback)
        is_pullback_candle = (close[0] > open[0]);
    }
    
    if(is_pullback_candle)
    {
        g_pullbackCount++;
        Print("🔄 Pullback vela #", g_pullbackCount, "/", Max_Pullback_Candles);
    }
    
    // Pasar a WINDOW_OPEN después de 1+ pullback o si ya llevamos 2 velas esperando
    if(g_pullbackCount >= 1 || g_windowCount >= 2)
    {
        g_currentPhase = PHASE_WINDOW_OPEN;
        g_windowCount = 0;
        SetBreakoutLevel();
        Print("✅ Pasando a WINDOW_OPEN");
        return;
    }
    
    g_windowCount++;
    
    // Si pullback es muy largo, resetear
    if(g_pullbackCount > Max_Pullback_Candles)
    {
        Print("⚠️ Pullback demasiado largo - Volviendo a SCANNING");
        g_currentPhase = PHASE_SCANNING;
    }
}

//+------------------------------------------------------------------+
//| FASE 3: WINDOW_OPEN - Esperar breakout confirmado               |
//+------------------------------------------------------------------+
void Phase_WindowOpen()
{
    g_windowCount++;
    
    // Verificar invalidación global
    if(CheckGlobalInvalidation())
    {
        g_currentPhase = PHASE_SCANNING;
        Print("❌ INVALIDACIÓN GLOBAL - Volviendo a SCANNING");
        return;
    }
    
    double close[];
    ArraySetAsSeries(close, true);
    
    if(CopyClose(_Symbol, PERIOD_M5, 0, 2, close) <= 0)
    {
        return;
    }
    
    double current_price = close[0];
    
    Print("🚪 WINDOW OPEN - Período ", g_windowCount, "/", Entry_Window_Periods);
    Print("   Precio: ", current_price, " | Breakout Level: ", g_breakoutLevel);
    
    // Verificar breakout (más permisivo)
    bool breakout_confirmed = false;
    
    if(g_trendDirection == 1)
    {
        // LONG: Precio debe estar cerca o por encima
        breakout_confirmed = (current_price >= g_breakoutLevel * 0.9995);
    }
    else if(g_trendDirection == -1)
    {
        // SHORT: Precio debe estar cerca o por debajo
        breakout_confirmed = (current_price <= g_breakoutLevel * 1.0005);
    }
    
    if(breakout_confirmed)
    {
        Print("🔥 BREAKOUT CONFIRMADO - Ejecutando trade");
        
        if(g_trendDirection == 1)
        {
            ExecuteTrade(ORDER_TYPE_BUY);
        }
        else if(g_trendDirection == -1)
        {
            ExecuteTrade(ORDER_TYPE_SELL);
        }
        
        g_currentPhase = PHASE_ENTRY;
        g_tradesToday++;
    }
    else if(g_windowCount >= Entry_Window_Periods)
    {
        // Ventana cerrada sin breakout
        Print("⏰ WINDOW CERRADA sin breakout - Volviendo a SCANNING");
        g_currentPhase = PHASE_SCANNING;
    }
}

//+------------------------------------------------------------------+
//| Establecer nivel de breakout                                     |
//+------------------------------------------------------------------+
void SetBreakoutLevel()
{
    double high[], low[], atr[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(atr, true);
    
    if(CopyHigh(_Symbol, PERIOD_M5, 0, 5, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 5, low) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0)
    {
        return;
    }
    
    double atr_value = atr[0];
    
    if(g_trendDirection == 1)
    {
        // LONG: Breakout por encima del máximo reciente
        g_breakoutLevel = high[ArrayMaximum(high, 0, 3)] + (atr_value * 0.2);
    }
    else if(g_trendDirection == -1)
    {
        // SHORT: Breakout por debajo del mínimo reciente
        g_breakoutLevel = low[ArrayMinimum(low, 0, 3)] - (atr_value * 0.2);
    }
    
    g_breakoutLevel = NormalizeDouble(g_breakoutLevel, _Digits);
    Print("📍 Breakout Level establecido: ", g_breakoutLevel);
}

//+------------------------------------------------------------------+
//| Verificar invalidación global                                    |
//+------------------------------------------------------------------+
bool CheckGlobalInvalidation()
{
    double ema_fast[], ema_medium[], ema_slow[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_medium, true);
    ArraySetAsSeries(ema_slow, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 3, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Medium, 0, 0, 3, ema_medium) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 3, ema_slow) <= 0)
    {
        return false;
    }
    
    if(g_trendDirection == 1)
    {
        // LONG: Invalidar si EMAs se cruzan bajista
        if(ema_fast[0] < ema_medium[0])
        {
            return true;
        }
    }
    else if(g_trendDirection == -1)
    {
        // SHORT: Invalidar si EMAs se cruzan alcista
        if(ema_fast[0] > ema_medium[0])
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calcular ángulo de EMA                                           |
//+------------------------------------------------------------------+
double CalculateEMAAngle(const double &ema[])
{
    if(ArraySize(ema) < 3) return 0;
    
    double diff = ema[0] - ema[2];
    double angle = MathArctan(diff / (2 * _Point)) * 180 / M_PI;
    
    return angle;
}

//+------------------------------------------------------------------+
//| Ejecutar Trade                                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    // Obtener ATR para SL/TP
    double atr[];
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0)
    {
        Print("❌ Error al obtener ATR");
        return;
    }
    
    double atr_value = atr[0];
    
    // Obtener precios
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    // Calcular SL/TP basado en ATR
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
    
    // Calcular lote basado en riesgo
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * Risk_Percent / 100.0;
    double sl_points = MathAbs(price - sl) / _Point;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (sl_points * tickValue);
    
    // Ajustar a lote mínimo/máximo
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    double rr_ratio = tp_distance / sl_distance;
    
    Print("=== PARÁMETROS DE TRADE ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", SL_ATR_Multiplier, " × ATR)");
    Print("TP: ", tp, " (", TP_ATR_Multiplier, " × ATR)");
    Print("RR Ratio: 1:", NormalizeDouble(rr_ratio, 2));
    Print("Lote: ", lotSize);
    Print("Riesgo: $", NormalizeDouble(riskAmount, 2));
    
    // Preparar orden
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
    request.comment = "PullbackBO";
    request.type_filling = ORDER_FILLING_IOC;
    
    // Enviar orden
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅✅✅ TRADE EJECUTADO ✅✅✅");
        Print("Total ejecutados: ", g_tradesExecuted);
    }
    else
    {
        Print("❌ TRADE FALLÓ - Retcode: ", result.retcode);
        g_currentPhase = PHASE_SCANNING;
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
    Print("XAUUSD PULLBACK BREAKOUT - FINALIZADO");
    Print("Total Velas: ", g_barCount);
    Print("Total Ejecutados: ", g_tradesExecuted);
    Print("========================================");
}
//+------------------------------------------------------------------+
