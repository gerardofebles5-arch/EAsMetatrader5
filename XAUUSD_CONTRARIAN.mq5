//+------------------------------------------------------------------+
//|                                    XAUUSD_CONTRARIAN.mq5         |
//|                ESTRATEGIA V4.0: PRICE ACTION PURO                |
//+------------------------------------------------------------------+
#property copyright "Pure Price Action Strategy"
#property version   "4.00"
#property strict

input int Magic_Number = 999999;
input int Trade_Every_N_Bars = 15;        // Operar cada N velas
input double Risk_Percent = 0.5;          // Riesgo por trade
input double SL_Points = 25;              // Stop Loss en points
input double TP_Points = 50;              // Take Profit en points (RR 1:2)
input bool Use_Trailing = true;           // Usar trailing stop
input double Trailing_Start = 30;         // Iniciar trailing
input double Trailing_Distance = 20;      // Distancia trailing
input int Min_Candle_Body = 15;           // Tamaño mínimo del cuerpo de vela
input double Wick_To_Body_Ratio = 2.0;    // Ratio mecha/cuerpo para rechazo

datetime g_lastBarTime = 0;
int g_tickCount = 0;
int g_barCount = 0;
int g_tradeAttempts = 0;
int g_tradesExecuted = 0;

// Sin indicadores - Price Action Puro

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD PRICE ACTION PURO V4.0");
    Print("========================================");
    Print("Metodología: Patrones de velas + Soporte/Resistencia");
    Print("Operar cada: ", Trade_Every_N_Bars, " velas");
    Print("========================================");
    
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
    
    // Gestionar trailing stop si está activado
    if(Use_Trailing && PositionSelect(_Symbol))
    {
        ManageTrailingStop();
    }
    
    // Detectar nueva vela M1
    datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        g_barCount++;
        
        // Intentar trade cada N velas
        if(g_barCount % Trade_Every_N_Bars == 0)
        {
            Print("========================================");
            Print("VELA #", g_barCount, " | ", TimeToString(currentBarTime));
            Print(">>> INTENTANDO TRADE CONTRARIAN #", (g_tradeAttempts + 1), " <<<");
            
            // Verificar si ya hay posición
            if(PositionSelect(_Symbol))
            {
                Print("⚠️ Ya hay posición abierta - esperando");
            }
            else
            {
                // DETERMINAR DIRECCIÓN CON PRICE ACTION
                int direction = DetermineContrarian();
                
                if(direction == 1)
                {
                    Print("✅ SETUP LONG: Patrón alcista confirmado");
                    ExecuteTrade(ORDER_TYPE_BUY);
                }
                else if(direction == -1)
                {
                    Print("✅ SETUP SHORT: Patrón bajista confirmado");
                    ExecuteTrade(ORDER_TYPE_SELL);
                }
                else
                {
                    Print("⚠️ Sin setup válido - esperando");
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ESTRATEGIA V4.0: PRICE ACTION PURO                               |
//+------------------------------------------------------------------+
int DetermineContrarian()
{
    // LÓGICA REVOLUCIONARIA: Solo Price Action, sin indicadores
    
    // Obtener datos de velas M5
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, PERIOD_M5, 0, 10, open) <= 0 ||
       CopyHigh(_Symbol, PERIOD_M5, 0, 10, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 10, low) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 10, close) <= 0)
    {
        return 0;
    }
    
    // 1. DETECTAR PATRÓN: PIN BAR (Rechazo fuerte)
    // Vela con mecha larga y cuerpo pequeño
    
    double body_1 = MathAbs(close[1] - open[1]) / _Point;
    double upper_wick_1 = (high[1] - MathMax(open[1], close[1])) / _Point;
    double lower_wick_1 = (MathMin(open[1], close[1]) - low[1]) / _Point;
    
    // PIN BAR ALCISTA: Mecha inferior larga, cuerpo pequeño
    bool bullish_pin = (lower_wick_1 > body_1 * Wick_To_Body_Ratio) && 
                       (body_1 > Min_Candle_Body) &&
                       (lower_wick_1 > 20);
    
    // PIN BAR BAJISTA: Mecha superior larga, cuerpo pequeño
    bool bearish_pin = (upper_wick_1 > body_1 * Wick_To_Body_Ratio) && 
                       (body_1 > Min_Candle_Body) &&
                       (upper_wick_1 > 20);
    
    if(bullish_pin)
    {
        Print("📍 PIN BAR ALCISTA: Mecha=", lower_wick_1, " Cuerpo=", body_1);
        
        // Confirmar con vela actual cerrando alcista
        if(close[0] > open[0])
        {
            Print("✅ CONFIRMACIÓN: Vela actual alcista");
            return 1;
        }
    }
    
    if(bearish_pin)
    {
        Print("📍 PIN BAR BAJISTA: Mecha=", upper_wick_1, " Cuerpo=", body_1);
        
        // Confirmar con vela actual cerrando bajista
        if(close[0] < open[0])
        {
            Print("✅ CONFIRMACIÓN: Vela actual bajista");
            return -1;
        }
    }
    
    // 2. DETECTAR PATRÓN: ENGULFING (Envolvente)
    
    double body_2 = MathAbs(close[2] - open[2]) / _Point;
    bool prev_bullish = (close[2] > open[2]);
    bool prev_bearish = (close[2] < open[2]);
    
    // ENGULFING ALCISTA: Vela alcista envuelve vela bajista anterior
    bool bullish_engulfing = (close[1] > open[1]) &&  // Vela 1 alcista
                             prev_bearish &&           // Vela 2 bajista
                             (open[1] < close[2]) &&   // Abre por debajo del cierre anterior
                             (close[1] > open[2]) &&   // Cierra por encima de la apertura anterior
                             (body_1 > body_2 * 1.5);  // Cuerpo 50% más grande
    
    // ENGULFING BAJISTA: Vela bajista envuelve vela alcista anterior
    bool bearish_engulfing = (close[1] < open[1]) &&  // Vela 1 bajista
                             prev_bullish &&           // Vela 2 alcista
                             (open[1] > close[2]) &&   // Abre por encima del cierre anterior
                             (close[1] < open[2]) &&   // Cierra por debajo de la apertura anterior
                             (body_1 > body_2 * 1.5);  // Cuerpo 50% más grande
    
    if(bullish_engulfing)
    {
        Print("🔥 ENGULFING ALCISTA: Cuerpo=", body_1, " vs ", body_2);
        return 1;
    }
    
    if(bearish_engulfing)
    {
        Print("🔥 ENGULFING BAJISTA: Cuerpo=", body_1, " vs ", body_2);
        return -1;
    }
    
    // 3. DETECTAR PATRÓN: INSIDE BAR + BREAKOUT
    
    // Inside bar: Vela 1 completamente dentro del rango de vela 2
    bool inside_bar = (high[1] < high[2]) && (low[1] > low[2]);
    
    if(inside_bar)
    {
        // Breakout alcista: Vela actual rompe el máximo de la inside bar
        if(close[0] > high[1] && close[0] > open[0])
        {
            Print("📊 INSIDE BAR BREAKOUT ALCISTA");
            return 1;
        }
        
        // Breakout bajista: Vela actual rompe el mínimo de la inside bar
        if(close[0] < low[1] && close[0] < open[0])
        {
            Print("📊 INSIDE BAR BREAKOUT BAJISTA");
            return -1;
        }
    }
    
    // 4. DETECTAR SOPORTE/RESISTENCIA SIMPLE
    
    // Encontrar máximo y mínimo de las últimas 5 velas
    double recent_high = high[ArrayMaximum(high, 1, 5)];
    double recent_low = low[ArrayMinimum(low, 1, 5)];
    double current_price = close[0];
    
    // Rebote en soporte: Precio cerca del mínimo reciente y subiendo
    double distance_from_low = (current_price - recent_low) / _Point;
    if(distance_from_low < 10 && close[0] > open[0] && body_1 > Min_Candle_Body)
    {
        Print("💪 REBOTE EN SOPORTE: Distancia=", distance_from_low);
        return 1;
    }
    
    // Rebote en resistencia: Precio cerca del máximo reciente y bajando
    double distance_from_high = (recent_high - current_price) / _Point;
    if(distance_from_high < 10 && close[0] < open[0] && body_1 > Min_Candle_Body)
    {
        Print("💪 REBOTE EN RESISTENCIA: Distancia=", distance_from_high);
        return -1;
    }
    
    return 0;
}

//+------------------------------------------------------------------+
//| Ejecutar Trade                                                   |
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
    
    // SL/TP ajustables
    double sl_points = SL_Points;  
    double tp_points = TP_Points; 
    
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
    
    // Lote mínimo
    double lotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    Print("=== PARÁMETROS DE ORDEN ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", sl_points, " points)");
    Print("TP: ", tp, " (", tp_points, " points)");
    Print("Lote: ", lotSize);
    
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
    request.comment = "PriceAction";
    request.type_filling = ORDER_FILLING_IOC;
    
    Print("=== ENVIANDO ORDEN CONTRARIAN ===");
    
    // Enviar orden
    bool sent = OrderSend(request, result);
    
    Print("=== RESULTADO ===");
    Print("OrderSend returned: ", sent);
    Print("Retcode: ", result.retcode);
    Print("Deal: ", result.deal);
    Print("Order: ", result.order);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅✅✅ TRADE EJECUTADO ✅✅✅");
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
//| Gestionar Trailing Stop                                          |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!PositionSelect(_Symbol)) return;
    
    double currentPrice;
    double currentSL = PositionGetDouble(POSITION_SL);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    if(posType == POSITION_TYPE_BUY)
    {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double profit_points = (currentPrice - openPrice) / _Point;
        
        // Si el profit es mayor que Trailing_Start, activar trailing
        if(profit_points >= Trailing_Start)
        {
            double newSL = currentPrice - Trailing_Distance * _Point;
            newSL = NormalizeDouble(newSL, _Digits);
            
            // Solo mover SL si es mejor que el actual
            if(newSL > currentSL)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                
                request.action = TRADE_ACTION_SLTP;
                request.symbol = _Symbol;
                request.sl = newSL;
                request.tp = PositionGetDouble(POSITION_TP);
                request.position = PositionGetInteger(POSITION_TICKET);
                
                if(OrderSend(request, result))
                {
                    Print("✅ Trailing Stop actualizado: ", newSL);
                }
            }
        }
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double profit_points = (openPrice - currentPrice) / _Point;
        
        // Si el profit es mayor que Trailing_Start, activar trailing
        if(profit_points >= Trailing_Start)
        {
            double newSL = currentPrice + Trailing_Distance * _Point;
            newSL = NormalizeDouble(newSL, _Digits);
            
            // Solo mover SL si es mejor que el actual (menor para SHORT)
            if(newSL < currentSL || currentSL == 0)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                
                request.action = TRADE_ACTION_SLTP;
                request.symbol = _Symbol;
                request.sl = newSL;
                request.tp = PositionGetDouble(POSITION_TP);
                request.position = PositionGetInteger(POSITION_TICKET);
                
                if(OrderSend(request, result))
                {
                    Print("✅ Trailing Stop actualizado: ", newSL);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("========================================");
    Print("XAUUSD PRICE ACTION PURO - FINALIZADO");
    Print("Total Velas: ", g_barCount);
    Print("Total Intentos: ", g_tradeAttempts);
    Print("Total Ejecutados: ", g_tradesExecuted);
    Print("Tasa de éxito: ", g_tradeAttempts>0 ? (g_tradesExecuted*100/g_tradeAttempts) : 0, "%");
    Print("========================================");
}
//+------------------------------------------------------------------+
