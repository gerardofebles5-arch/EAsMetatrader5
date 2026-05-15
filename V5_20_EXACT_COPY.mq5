//+------------------------------------------------------------------+
//|                                        V5_20_EXACT_COPY.mq5      |
//|                    COPIA EXACTA DE LA VERSIÓN QUE SÍ OPERÓ       |
//+------------------------------------------------------------------+
#property copyright "V5.20 Exact Copy"
#property version   "5.20"
#property strict

// ============ INPUTS ============
input double RiskPercent = 1.5;
input int ScalpingTimeframe = 1;             // 1=M1, 5=M5
input int MagicNumber = 123457;
input int MinScoreToTrade = 3;               // ULTRA BAJO como v5.20

// Indicadores
input int EMA_Fast_M15 = 20;
input int EMA_Slow_M15 = 50;
input int RSI_Period = 14;
input int RSI_Level = 50;
input int ATR_Period = 14;

// Filtros
input int MaxSpreadPips_Other = 8;
input int MaxDailyRangePips = 500;
input int MaxTradesPerDay = 50;
input int MaxTradesPerHour = 10;

// SL/TP
input bool UseATRforSLTP = true;
input double ATRMultiplierSL = 2.0;
input double ATRMultiplierTP = 4.0;
input int ManualStopLossPips = 15;
input int ManualTakeProfitPips = 30;

// ============ VARIABLES ============
int handle_EMA_Fast_M15, handle_EMA_Slow_M15, handle_RSI_M5, handle_ATR_M5;
datetime lastBarTime = 0;
int tradesToday = 0;
int tradesThisHour = 0;
datetime lastTradeDate = 0;
datetime lastTradeHour = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== V5.20 EXACT COPY - Iniciando ===");
    Print("Score mínimo: ", MinScoreToTrade, " (ULTRA BAJO)");
    Print("Timeframe: M", ScalpingTimeframe);
    
    // Crear handles
    handle_EMA_Fast_M15 = iMA(_Symbol, PERIOD_M15, EMA_Fast_M15, 0, MODE_EMA, PRICE_CLOSE);
    handle_EMA_Slow_M15 = iMA(_Symbol, PERIOD_M15, EMA_Slow_M15, 0, MODE_EMA, PRICE_CLOSE);
    handle_RSI_M5 = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    handle_ATR_M5 = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(handle_EMA_Fast_M15 == INVALID_HANDLE || handle_EMA_Slow_M15 == INVALID_HANDLE ||
       handle_RSI_M5 == INVALID_HANDLE || handle_ATR_M5 == INVALID_HANDLE)
    {
        Print("ERROR: Handles inválidos");
        return(INIT_FAILED);
    }
    
    Print("=== LISTO PARA OPERAR ===");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(handle_EMA_Fast_M15 != INVALID_HANDLE) IndicatorRelease(handle_EMA_Fast_M15);
    if(handle_EMA_Slow_M15 != INVALID_HANDLE) IndicatorRelease(handle_EMA_Slow_M15);
    if(handle_RSI_M5 != INVALID_HANDLE) IndicatorRelease(handle_RSI_M5);
    if(handle_ATR_M5 != INVALID_HANDLE) IndicatorRelease(handle_ATR_M5);
}

//+------------------------------------------------------------------+
void OnTick()
{
    // Detectar nueva vela en el timeframe correcto
    ENUM_TIMEFRAMES tf_main = (ScalpingTimeframe == 1) ? PERIOD_M1 : PERIOD_M5;
    datetime currentBarTime = iTime(_Symbol, tf_main, 0);
    
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;
    
    Print("🔄 === NUEVA VELA ", TimeToString(currentBarTime), " ===");
    
    // Reset contadores
    ResetCounters();
    
    // Si hay posición, salir
    if(PositionSelect(_Symbol))
    {
        Print("Posición abierta");
        return;
    }
    
    // Verificar filtros globales
    if(!CheckGlobalFilters())
    {
        Print("❌ Filtros globales NO pasados");
        return;
    }
    
    // Analizar mercado (EXACTO como v5.20)
    int signal = AnalyzeMarket();
    
    if(signal == 1)
    {
        Print("✅ EJECUTANDO LONG");
        OpenTrade(ORDER_TYPE_BUY);
    }
    else if(signal == -1)
    {
        Print("✅ EJECUTANDO SHORT");
        OpenTrade(ORDER_TYPE_SELL);
    }
    else
    {
        Print("⏸️ Sin señal");
    }
}

//+------------------------------------------------------------------+
void ResetCounters()
{
    datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
    if(currentDate != lastTradeDate)
    {
        tradesToday = 0;
        tradesThisHour = 0;
        lastTradeDate = currentDate;
        Print("=== NUEVO DÍA ===");
    }
    
    datetime currentHour = iTime(_Symbol, PERIOD_H1, 0);
    if(currentHour != lastTradeHour)
    {
        tradesThisHour = 0;
        lastTradeHour = currentHour;
    }
}

//+------------------------------------------------------------------+
bool CheckGlobalFilters()
{
    // Spread
    double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point / 10;
    if(spread > MaxSpreadPips_Other)
    {
        Print("❌ Spread: ", (int)spread, "p (máx: ", MaxSpreadPips_Other, ")");
        return false;
    }
    
    // Rango diario
    double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
    double dailyLow = iLow(_Symbol, PERIOD_D1, 0);
    double dailyRange = (dailyHigh - dailyLow) / _Point / 10;
    if(dailyRange > MaxDailyRangePips)
    {
        Print("❌ Rango: ", (int)dailyRange, "p");
        return false;
    }
    
    // Límites
    if(tradesToday >= MaxTradesPerDay)
    {
        Print("❌ Límite diario: ", tradesToday);
        return false;
    }
    
    if(tradesThisHour >= MaxTradesPerHour)
    {
        Print("❌ Límite por hora: ", tradesThisHour);
        return false;
    }
    
    Print("✅ Filtros OK | Spread:", (int)spread, "p | Rango:", (int)dailyRange, "p");
    return true;
}

//+------------------------------------------------------------------+
// EXACTO COMO V5.20: 3 MÉTODOS FALLBACK PARA BIAS
//+------------------------------------------------------------------+
int AnalyzeMarket()
{
    int score = 0;
    bool biasLong = false;
    bool biasShort = false;
    
    // MÉTODO 1: Bias M15 fuerte (precio > EMA fast > EMA slow)
    double ema_fast[], ema_slow[], close_m15[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(close_m15, true);
    
    if(CopyBuffer(handle_EMA_Fast_M15, 0, 0, 1, ema_fast) > 0 &&
       CopyBuffer(handle_EMA_Slow_M15, 0, 0, 1, ema_slow) > 0 &&
       CopyClose(_Symbol, PERIOD_M15, 0, 1, close_m15) > 0)
    {
        // Bias fuerte alcista
        if(close_m15[0] > ema_fast[0] && ema_fast[0] > ema_slow[0])
        {
            biasLong = true;
            score += 3;
            Print("Bias M15 FUERTE alcista");
        }
        // Bias fuerte bajista
        else if(close_m15[0] < ema_fast[0] && ema_fast[0] < ema_slow[0])
        {
            biasShort = true;
            score += 3;
            Print("Bias M15 FUERTE bajista");
        }
        // MÉTODO 2: Bias M15 débil (solo precio vs EMA fast)
        else if(close_m15[0] > ema_fast[0])
        {
            biasLong = true;
            score += 2;
            Print("Bias M15 DÉBIL alcista");
        }
        else if(close_m15[0] < ema_fast[0])
        {
            biasShort = true;
            score += 2;
            Print("Bias M15 DÉBIL bajista");
        }
    }
    
    // MÉTODO 3: Si aún no hay bias, usar vela M5 (SIEMPRE genera bias)
    if(!biasLong && !biasShort)
    {
        double open_m5 = iOpen(_Symbol, PERIOD_M5, 0);
        double close_m5 = iClose(_Symbol, PERIOD_M5, 0);
        
        if(close_m5 > open_m5)
        {
            biasLong = true;
            score += 2;
            Print("Bias M5 alcista (vela)");
        }
        else
        {
            biasShort = true;
            score += 2;
            Print("Bias M5 bajista (vela)");
        }
    }
    
    // Verificar score mínimo
    Print("📊 Score: ", score, " | Mínimo: ", MinScoreToTrade);
    
    if(score < MinScoreToTrade)
    {
        Print("⚠️ Score insuficiente");
        return 0;
    }
    
    // Generar señal
    if(biasLong)
    {
        Print("🟢 SEÑAL LONG | Score:", score);
        return 1;
    }
    else if(biasShort)
    {
        Print("🔴 SEÑAL SHORT | Score:", score);
        return -1;
    }
    
    return 0;
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
    double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calcular SL/TP
    int sl_pips, tp_pips;
    if(UseATRforSLTP)
    {
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(handle_ATR_M5, 0, 0, 1, atr) > 0)
        {
            double atr_value = atr[0] / _Point / 10;
            sl_pips = (int)(atr_value * ATRMultiplierSL);
            tp_pips = (int)(atr_value * ATRMultiplierTP);
            
            if(sl_pips < 8) sl_pips = 8;
            if(sl_pips > 25) sl_pips = 25;
            if(tp_pips < 15) tp_pips = 15;
            if(tp_pips > 50) tp_pips = 50;
        }
        else
        {
            sl_pips = ManualStopLossPips;
            tp_pips = ManualTakeProfitPips;
        }
    }
    else
    {
        sl_pips = ManualStopLossPips;
        tp_pips = ManualTakeProfitPips;
    }
    
    double sl, tp;
    if(orderType == ORDER_TYPE_BUY)
    {
        sl = price - sl_pips * _Point * 10;
        tp = price + tp_pips * _Point * 10;
    }
    else
    {
        sl = price + sl_pips * _Point * 10;
        tp = price - tp_pips * _Point * 10;
    }
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // Calcular lote
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;
    double lotSize = riskAmount / (sl_pips * 10 * pointValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = NormalizeDouble(lotSize, 2);
    
    // Ejecutar
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "V5.20 Copy";
    request.type_filling = ORDER_FILLING_IOC;
    
    Print("========================================");
    Print("EJECUTANDO TRADE");
    Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", sl_pips, "p)");
    Print("TP: ", tp, " (", tp_pips, "p)");
    Print("Lote: ", lotSize);
    
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("✅ TRADE EJECUTADO");
            Print("Order: ", result.order);
            tradesToday++;
            tradesThisHour++;
        }
        else
        {
            Print("❌ Error: ", result.retcode);
        }
    }
    else
    {
        Print("❌ OrderSend falló: ", GetLastError());
    }
    Print("========================================");
}
//+------------------------------------------------------------------+
