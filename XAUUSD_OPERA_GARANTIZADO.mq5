//+------------------------------------------------------------------+
//|                              XAUUSD_OPERA_GARANTIZADO.mq5        |
//|              BASADO EN DIAGNOSTICO_EXTREMO + FILTROS MÍNIMOS     |
//+------------------------------------------------------------------+
#property copyright "Opera Garantizado"
#property version   "1.00"
#property strict

input int Magic_Number = 888888;
input int Trade_Every_N_Bars = 10;        // Operar cada N velas (10 = más selectivo)
input double Risk_Percent = 1.0;          // Riesgo por trade

datetime g_lastBarTime = 0;
int g_tickCount = 0;
int g_barCount = 0;
int g_tradeAttempts = 0;
int g_tradesExecuted = 0;

// Handles de indicadores
int g_handle_EMA_Fast;
int g_handle_EMA_Slow;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD OPERA GARANTIZADO - INICIADO");
    Print("========================================");
    Print("Basado en DIAGNOSTICO_EXTREMO que operó 13,771 trades");
    Print("Operar cada: ", Trade_Every_N_Bars, " velas");
    Print("========================================");
    
    // Crear indicadores simples
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Slow == INVALID_HANDLE)
    {
        Print("⚠️ Error al crear indicadores - continuando sin ellos");
    }
    
    g_lastBarTime = 0;
    g_tickCount = 0;
    g_barCount = 0;
    g_tradeAttempts = 0;
    g_tradesExecuted = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    g_tickCount++;
    
    // Detectar nueva vela M1 (IGUAL QUE DIAGNOSTICO_EXTREMO)
    datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        g_barCount++;
        
        // Intentar trade cada N velas (IGUAL QUE DIAGNOSTICO_EXTREMO pero ajustable)
        if(g_barCount % Trade_Every_N_Bars == 0)
        {
            Print("========================================");
            Print("VELA #", g_barCount, " | ", TimeToString(currentBarTime));
            Print(">>> INTENTANDO TRADE #", (g_tradeAttempts + 1), " <<<");
            
            // Verificar si ya hay posición
            if(PositionSelect(_Symbol))
            {
                Print("⚠️ Ya hay posición abierta - esperando");
            }
            else
            {
                // DETERMINAR DIRECCIÓN CON FILTRO MÍNIMO
                int direction = DetermineDirection();
                
                if(direction == 1)
                {
                    Print("✅ Dirección: LONG");
                    ExecuteTrade(ORDER_TYPE_BUY);
                }
                else if(direction == -1)
                {
                    Print("✅ Dirección: SHORT");
                    ExecuteTrade(ORDER_TYPE_SELL);
                }
                else
                {
                    Print("⚠️ Sin dirección clara - saltando");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Determinar dirección con filtro MÍNIMO                           |
//+------------------------------------------------------------------+
int DetermineDirection()
{
    // MÉTODO 1: Usar EMAs si están disponibles
    if(g_handle_EMA_Fast != INVALID_HANDLE && g_handle_EMA_Slow != INVALID_HANDLE)
    {
        double ema_fast[], ema_slow[], close_m15[];
        ArraySetAsSeries(ema_fast, true);
        ArraySetAsSeries(ema_slow, true);
        ArraySetAsSeries(close_m15, true);
        
        if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 1, ema_fast) > 0 &&
           CopyBuffer(g_handle_EMA_Slow, 0, 0, 1, ema_slow) > 0 &&
           CopyClose(_Symbol, PERIOD_M15, 0, 1, close_m15) > 0)
        {
            // Bias alcista: precio > EMA fast
            if(close_m15[0] > ema_fast[0])
            {
                Print("📈 EMA: Bias alcista");
                return 1;
            }
            // Bias bajista: precio < EMA fast
            else if(close_m15[0] < ema_fast[0])
            {
                Print("📉 EMA: Bias bajista");
                return -1;
            }
        }
    }
    
    // MÉTODO 2: Fallback - Usar vela M5 (SIEMPRE funciona)
    double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
    double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
    
    if(close_m5 > open_m5)
    {
        Print("📊 M5: Vela alcista");
        return 1;
    }
    else
    {
        Print("📊 M5: Vela bajista");
        return -1;
    }
}

//+------------------------------------------------------------------+
//| Ejecutar Trade (IGUAL QUE DIAGNOSTICO_EXTREMO)                   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    g_tradeAttempts++;
    
    // Obtener precios
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread = (ask - bid) / _Point;
    
    Print("=== INFORMACIÓN DE MERCADO ===");
    Print("Ask: ", ask);
    Print("Bid: ", bid);
    Print("Spread: ", spread, " points");
    
    // Precio de entrada
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    // SL/TP simples pero más amplios
    double sl_points = 50;  // 50 points = $5 en XAUUSD
    double tp_points = 100; // 100 points = $10 en XAUUSD (RR 1:2)
    
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
    
    // Lote mínimo (IGUAL QUE DIAGNOSTICO_EXTREMO)
    double lotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    Print("=== PARÁMETROS DE ORDEN ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", sl_points, " points)");
    Print("TP: ", tp, " (", tp_points, " points)");
    Print("Lote: ", lotSize);
    
    // Preparar orden (IGUAL QUE DIAGNOSTICO_EXTREMO)
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
    request.comment = "Opera Garantizado";
    request.type_filling = ORDER_FILLING_IOC;
    
    Print("=== ENVIANDO ORDEN ===");
    
    // Enviar orden (IGUAL QUE DIAGNOSTICO_EXTREMO)
    bool sent = OrderSend(request, result);
    
    Print("=== RESULTADO ===");
    Print("OrderSend returned: ", sent);
    Print("Retcode: ", result.retcode);
    Print("Deal: ", result.deal);
    Print("Order: ", result.order);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅✅✅ TRADE EJECUTADO EXITOSAMENTE ✅✅✅");
        Print("Total ejecutados: ", g_tradesExecuted);
    }
    else
    {
        Print("❌❌❌ TRADE FALLÓ ❌❌❌");
        Print("Error Code: ", GetLastError());
    }
    
    Print("========================================");
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    
    Print("========================================");
    Print("XAUUSD OPERA GARANTIZADO - FINALIZADO");
    Print("Total Velas: ", g_barCount);
    Print("Total Intentos: ", g_tradeAttempts);
    Print("Total Ejecutados: ", g_tradesExecuted);
    Print("Tasa de éxito: ", g_tradeAttempts>0 ? (g_tradesExecuted*100/g_tradeAttempts) : 0, "%");
    Print("========================================");
}
//+------------------------------------------------------------------+
