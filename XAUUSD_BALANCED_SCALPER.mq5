//+------------------------------------------------------------------+
//|                                  XAUUSD_BALANCED_SCALPER.mq5     |
//|                    VERSIÓN BALANCEADA - Opera + Calidad          |
//+------------------------------------------------------------------+
#property copyright "Balanced Scalper"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input double   Risk_Percent = 1.0;            // Riesgo por trade (%)
input int      ATR_Period = 14;               // Período ATR
input double   ATR_SL_Multiplier = 2.5;       // Multiplicador ATR para SL
input double   ATR_TP_Multiplier = 5.0;       // Multiplicador ATR para TP (RR 1:2)
input int      Magic_Number = 777777;         // Magic Number

// Filtros de calidad
input int      EMA_Fast = 20;                 // EMA Rápida
input int      EMA_Slow = 50;                 // EMA Lenta
input int      RSI_Period = 14;               // Período RSI
input int      RSI_Oversold = 30;             // RSI Sobreventa
input int      RSI_Overbought = 70;           // RSI Sobrecompra
input int      Min_Bars_Between_Trades = 5;   // Mínimo velas entre trades
input double   Max_Spread_Points = 50;        // Spread máximo (points)

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
datetime g_lastTradeTime = 0;
int g_tradeCount = 0;
int g_handle_ATR;
int g_handle_EMA_Fast;
int g_handle_EMA_Slow;
int g_handle_RSI;

//+------------------------------------------------------------------+
//| Inicialización                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD BALANCED SCALPER - INICIADO");
    Print("========================================");
    Print("Símbolo: ", _Symbol);
    Print("Risk: ", Risk_Percent, "%");
    Print("ATR SL/TP: ", ATR_SL_Multiplier, "x / ", ATR_TP_Multiplier, "x");
    Print("Min velas entre trades: ", Min_Bars_Between_Trades);
    Print("========================================");
    
    // Crear indicadores
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M15, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M15, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    
    if(g_handle_ATR == INVALID_HANDLE || g_handle_EMA_Fast == INVALID_HANDLE ||
       g_handle_EMA_Slow == INVALID_HANDLE || g_handle_RSI == INVALID_HANDLE)
    {
        Print("❌ Error al crear indicadores");
        return(INIT_FAILED);
    }
    
    Print("✅ Indicadores creados correctamente");
    
    g_lastBarTime = 0;
    g_lastTradeTime = 0;
    g_tradeCount = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
    // Detectar nueva vela M1
    datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
    
    if(currentBarTime == g_lastBarTime)
        return;
    
    g_lastBarTime = currentBarTime;
    
    // Si ya hay posición, no abrir otra
    if(PositionSelect(_Symbol))
        return;
    
    // Verificar filtros básicos
    if(!CheckBasicFilters())
        return;
    
    // Analizar señal
    int signal = AnalyzeMarket();
    
    if(signal == 1)
    {
        Print("🟢 SEÑAL LONG");
        ExecuteTrade(ORDER_TYPE_BUY);
    }
    else if(signal == -1)
    {
        Print("🔴 SEÑAL SHORT");
        ExecuteTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Verificar filtros básicos                                        |
//+------------------------------------------------------------------+
bool CheckBasicFilters()
{
    // Filtro 1: Spread
    double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
    if(spread > Max_Spread_Points)
    {
        Print("❌ Spread alto: ", (int)spread, " points");
        return false;
    }
    
    // Filtro 2: Tiempo mínimo entre trades
    int barsSinceLastTrade = iBarShift(_Symbol, PERIOD_M1, g_lastTradeTime);
    if(barsSinceLastTrade >= 0 && barsSinceLastTrade < Min_Bars_Between_Trades)
    {
        Print("⏳ Esperando ", (Min_Bars_Between_Trades - barsSinceLastTrade), " velas más");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Analizar mercado - Sistema de Fallback Triple                    |
//+------------------------------------------------------------------+
int AnalyzeMarket()
{
    int score = 0;
    bool biasLong = false;
    bool biasShort = false;
    
    // PASO 1: Bias M15 con EMAs
    double ema_fast[], ema_slow[], close_m15[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(close_m15, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 2, ema_fast) > 0 &&
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 2, ema_slow) > 0 &&
       CopyClose(_Symbol, PERIOD_M15, 0, 2, close_m15) > 0)
    {
        // Método 1: Bias fuerte (precio > EMA fast > EMA slow)
        if(close_m15[0] > ema_fast[0] && ema_fast[0] > ema_slow[0])
        {
            biasLong = true;
            score += 3;
            Print("📈 Bias FUERTE alcista");
        }
        else if(close_m15[0] < ema_fast[0] && ema_fast[0] < ema_slow[0])
        {
            biasShort = true;
            score += 3;
            Print("📉 Bias FUERTE bajista");
        }
        // Método 2: Bias débil (solo precio vs EMA fast)
        else if(close_m15[0] > ema_fast[0])
        {
            biasLong = true;
            score += 1;
            Print("📈 Bias débil alcista");
        }
        else if(close_m15[0] < ema_fast[0])
        {
            biasShort = true;
            score += 1;
            Print("📉 Bias débil bajista");
        }
    }
    
    // Método 3: Fallback con vela M5 (SIEMPRE genera bias)
    if(!biasLong && !biasShort)
    {
        double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
        double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
        
        if(close_m5 > open_m5)
        {
            biasLong = true;
            score += 1;
            Print("📊 Bias M5 alcista (fallback)");
        }
        else
        {
            biasShort = true;
            score += 1;
            Print("📊 Bias M5 bajista (fallback)");
        }
    }
    
    // PASO 2: Confirmación con RSI
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(g_handle_RSI, 0, 0, 2, rsi) > 0)
    {
        // RSI en zona de sobreventa (bueno para LONG)
        if(biasLong && rsi[0] < RSI_Oversold)
        {
            score += 2;
            Print("✅ RSI sobreventa: ", (int)rsi[0]);
        }
        // RSI en zona de sobrecompra (bueno para SHORT)
        else if(biasShort && rsi[0] > RSI_Overbought)
        {
            score += 2;
            Print("✅ RSI sobrecompra: ", (int)rsi[0]);
        }
        // RSI neutral pero en dirección del bias
        else if(biasLong && rsi[0] > 50)
        {
            score += 1;
            Print("✓ RSI alcista: ", (int)rsi[0]);
        }
        else if(biasShort && rsi[0] < 50)
        {
            score += 1;
            Print("✓ RSI bajista: ", (int)rsi[0]);
        }
    }
    
    // PASO 3: Confirmación con vela M1
    double open_m1 = iOpen(_Symbol, PERIOD_M1, 1);
    double close_m1 = iClose(_Symbol, PERIOD_M1, 1);
    double high_m1 = iHigh(_Symbol, PERIOD_M1, 1);
    double low_m1 = iLow(_Symbol, PERIOD_M1, 1);
    
    double body = MathAbs(close_m1 - open_m1);
    double range = high_m1 - low_m1;
    
    if(range > 0)
    {
        // Vela alcista fuerte
        if(biasLong && close_m1 > open_m1 && body > range * 0.6)
        {
            score += 2;
            Print("✅ Vela M1 alcista fuerte");
        }
        // Vela bajista fuerte
        else if(biasShort && close_m1 < open_m1 && body > range * 0.6)
        {
            score += 2;
            Print("✅ Vela M1 bajista fuerte");
        }
        // Vela en dirección del bias
        else if(biasLong && close_m1 > open_m1)
        {
            score += 1;
            Print("✓ Vela M1 alcista");
        }
        else if(biasShort && close_m1 < open_m1)
        {
            score += 1;
            Print("✓ Vela M1 bajista");
        }
    }
    
    // Decisión final
    Print("📊 Score total: ", score);
    
    // Score mínimo: 3 puntos
    if(score >= 3)
    {
        if(biasLong)
            return 1;
        else if(biasShort)
            return -1;
    }
    else
    {
        Print("⚠️ Score insuficiente: ", score, " < 3");
    }
    
    return 0;
}

//+------------------------------------------------------------------+
//| Ejecutar Trade                                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    // Obtener ATR para SL/TP dinámico
    double atr[];
    ArraySetAsSeries(atr, true);
    
    double sl_points = 30;  // Fallback
    double tp_points = 60;
    
    if(CopyBuffer(g_handle_ATR, 0, 0, 1, atr) > 0)
    {
        sl_points = atr[0] * ATR_SL_Multiplier / _Point;
        tp_points = atr[0] * ATR_TP_Multiplier / _Point;
        
        // Límites
        if(sl_points < 20) sl_points = 20;
        if(sl_points > 100) sl_points = 100;
        if(tp_points < 40) tp_points = 40;
        if(tp_points > 200) tp_points = 200;
    }
    
    // Obtener precio
    double price = (orderType == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calcular SL y TP
    double sl, tp;
    if(orderType == ORDER_TYPE_BUY)
    {
        sl = price - sl_points * _Point;
        tp = price + tp_points * _Point;
    }
    else
    {
        sl = price + sl_points * _Point;
        tp = price - tp_points * _Point;
    }
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // Calcular lote
    double lotSize = CalculateLotSize(sl_points);
    lotSize = NormalizeDouble(lotSize, 2);
    
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
    request.comment = "Balanced Scalper";
    request.type_filling = ORDER_FILLING_IOC;
    
    Print("=== EJECUTANDO TRADE ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", (int)sl_points, " points)");
    Print("TP: ", tp, " (", (int)tp_points, " points)");
    Print("Lote: ", lotSize);
    
    // Enviar orden
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            g_tradeCount++;
            g_lastTradeTime = iTime(_Symbol, PERIOD_M1, 0);
            Print("✅ TRADE EJECUTADO | Total: ", g_tradeCount);
        }
        else
        {
            Print("❌ Trade falló | Retcode: ", result.retcode);
        }
    }
    else
    {
        Print("❌ OrderSend falló | Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote                                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_points)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * Risk_Percent / 100.0;
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;
    
    double lotSize = riskAmount / (sl_points * pointValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Desinicialización                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    if(g_handle_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_RSI);
    
    Print("========================================");
    Print("BALANCED SCALPER - DETENIDO");
    Print("Total Trades: ", g_tradeCount);
    Print("========================================");
}
//+------------------------------------------------------------------+
