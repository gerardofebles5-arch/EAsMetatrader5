//+------------------------------------------------------------------+
//|                          XAUUSD_CONTRARIAN_OPTIMIZED.mq5         |
//|                    ESTRATEGIA CONTRARIAN OPTIMIZADA              |
//+------------------------------------------------------------------+
#property copyright "Contrarian Optimized"
#property version   "2.00"
#property strict

input int Magic_Number = 999999;
input int Trade_Every_N_Bars = 20;        // Más selectivo (antes 10)
input double Risk_Percent = 0.5;          // Menos riesgo (antes 1.0)

// Nuevos filtros de calidad
input int RSI_Period = 14;
input int RSI_Extreme_High = 70;          // RSI sobrecompra
input int RSI_Extreme_Low = 30;           // RSI sobreventa
input double Min_ATR_Multiplier = 1.5;    // Volatilidad mínima
input int ATR_Period = 14;

datetime g_lastBarTime = 0;
int g_barCount = 0;
int g_tradeAttempts = 0;
int g_tradesExecuted = 0;

// Handles
int g_handle_EMA_Fast;
int g_handle_EMA_Slow;
int g_handle_RSI;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD CONTRARIAN OPTIMIZED");
    Print("========================================");
    Print("Contrarian + RSI extremos + ATR filter");
    Print("Trade cada: ", Trade_Every_N_Bars, " velas");
    Print("Risk: ", Risk_Percent, "%");
    Print("========================================");
    
    // Crear indicadores
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Slow == INVALID_HANDLE ||
       g_handle_RSI == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE)
    {
        Print("❌ Error al crear indicadores");
        return(INIT_FAILED);
    }
    
    g_lastBarTime = 0;
    g_barCount = 0;
    g_tradeAttempts = 0;
    g_tradesExecuted = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        g_barCount++;
        
        if(g_barCount % Trade_Every_N_Bars == 0)
        {
            if(PositionSelect(_Symbol))
            {
                ManagePosition();
                return;
            }
            
            Print("========================================");
            Print("VELA #", g_barCount);
            
            int direction = AnalyzeContrarian();
            
            if(direction == 1)
            {
                Print("✅ CONTRARIAN LONG");
                ExecuteTrade(ORDER_TYPE_BUY);
            }
            else if(direction == -1)
            {
                Print("✅ CONTRARIAN SHORT");
                ExecuteTrade(ORDER_TYPE_SELL);
            }
            else
            {
                Print("⏸️ Sin señal de calidad");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Análisis Contrarian con filtros de calidad                       |
//+------------------------------------------------------------------+
int AnalyzeContrarian()
{
    // PASO 1: Obtener RSI
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(g_handle_RSI, 0, 0, 2, rsi) <= 0)
    {
        Print("❌ Error RSI");
        return 0;
    }
    
    // PASO 2: Obtener ATR para filtro de volatilidad
    double atr[];
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(g_handle_ATR, 0, 0, 1, atr) <= 0)
    {
        Print("❌ Error ATR");
        return 0;
    }
    
    double atr_value = atr[0] / _Point;
    
    // Filtro: Volatilidad mínima
    if(atr_value < 20)  // ATR mínimo 20 points
    {
        Print("⚠️ ATR bajo: ", (int)atr_value, " points");
        return 0;
    }
    
    // PASO 3: Determinar bias del mercado
    double ema_fast[], ema_slow[], close_m15[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(close_m15, true);
    
    bool market_bullish = false;
    bool market_bearish = false;
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 1, ema_fast) > 0 &&
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 1, ema_slow) > 0 &&
       CopyClose(_Symbol, PERIOD_M15, 0, 1, close_m15) > 0)
    {
        // Mercado alcista fuerte
        if(close_m15[0] > ema_fast[0] && ema_fast[0] > ema_slow[0])
        {
            market_bullish = true;
            Print("📈 Mercado ALCISTA fuerte");
        }
        // Mercado bajista fuerte
        else if(close_m15[0] < ema_fast[0] && ema_fast[0] < ema_slow[0])
        {
            market_bearish = true;
            Print("📉 Mercado BAJISTA fuerte");
        }
        // Mercado alcista débil
        else if(close_m15[0] > ema_fast[0])
        {
            market_bullish = true;
            Print("📈 Mercado alcista débil");
        }
        // Mercado bajista débil
        else
        {
            market_bearish = true;
            Print("📉 Mercado bajista débil");
        }
    }
    
    // PASO 4: ESTRATEGIA CONTRARIAN MEJORADA
    // Solo operar cuando RSI está en EXTREMOS
    
    // LONG Contrarian: Mercado alcista + RSI sobrecompra
    if(market_bullish && rsi[0] > RSI_Extreme_High)
    {
        Print("🔄 CONTRARIAN LONG: Mercado alcista + RSI ", (int)rsi[0], " (sobrecompra)");
        Print("   Esperamos reversión bajista → Compramos");
        return 1;
    }
    
    // SHORT Contrarian: Mercado bajista + RSI sobreventa
    if(market_bearish && rsi[0] < RSI_Extreme_Low)
    {
        Print("🔄 CONTRARIAN SHORT: Mercado bajista + RSI ", (int)rsi[0], " (sobreventa)");
        Print("   Esperamos reversión alcista → Vendemos");
        return -1;
    }
    
    Print("⚠️ RSI no en extremo: ", (int)rsi[0], " (necesita <", RSI_Extreme_Low, " o >", RSI_Extreme_High, ")");
    return 0;
}

//+------------------------------------------------------------------+
//| Gestionar posición abierta                                       |
//+------------------------------------------------------------------+
void ManagePosition()
{
    if(!PositionSelect(_Symbol))
        return;
    
    double position_profit = PositionGetDouble(POSITION_PROFIT);
    double position_open = PositionGetDouble(POSITION_PRICE_OPEN);
    double position_current = PositionGetDouble(POSITION_PRICE_CURRENT);
    long position_type = PositionGetInteger(POSITION_TYPE);
    
    double profit_points = 0;
    
    if(position_type == POSITION_TYPE_BUY)
        profit_points = (position_current - position_open) / _Point;
    else
        profit_points = (position_open - position_current) / _Point;
    
    // Break Even a 30 points
    if(profit_points >= 30)
    {
        double current_sl = PositionGetDouble(POSITION_SL);
        double new_sl = position_open;
        
        if(position_type == POSITION_TYPE_BUY && current_sl < position_open)
        {
            ModifySL(new_sl);
            Print("✅ Break Even activado en +", (int)profit_points, " points");
        }
        else if(position_type == POSITION_TYPE_SELL && current_sl > position_open)
        {
            ModifySL(new_sl);
            Print("✅ Break Even activado en +", (int)profit_points, " points");
        }
    }
}

//+------------------------------------------------------------------+
//| Modificar SL                                                     |
//+------------------------------------------------------------------+
void ModifySL(double new_sl)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.sl = NormalizeDouble(new_sl, _Digits);
    request.tp = PositionGetDouble(POSITION_TP);
    request.position = PositionGetInteger(POSITION_TICKET);
    
    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Ejecutar Trade                                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    g_tradeAttempts++;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    // Obtener ATR para SL/TP dinámico
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(g_handle_ATR, 0, 0, 1, atr);
    
    double sl_points = atr[0] * 2.0 / _Point;  // SL = ATR x 2
    double tp_points = atr[0] * 4.0 / _Point;  // TP = ATR x 4 (RR 1:2)
    
    // Límites
    if(sl_points < 40) sl_points = 40;
    if(sl_points > 100) sl_points = 100;
    if(tp_points < 80) tp_points = 80;
    if(tp_points > 200) tp_points = 200;
    
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
    
    // Calcular lote con riesgo reducido
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
    lotSize = NormalizeDouble(lotSize, 2);
    
    Print("=== TRADE CONTRARIAN OPTIMIZADO ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", (int)sl_points, " points)");
    Print("TP: ", tp, " (", (int)tp_points, " points)");
    Print("Lote: ", lotSize);
    Print("Risk: $", riskAmount);
    
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
    request.comment = "Contrarian Opt";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ TRADE EJECUTADO | Total: ", g_tradesExecuted);
    }
    else
    {
        Print("❌ TRADE FALLÓ | Retcode: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    if(g_handle_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_RSI);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("========================================");
    Print("CONTRARIAN OPTIMIZED - FINALIZADO");
    Print("Total Intentos: ", g_tradeAttempts);
    Print("Total Ejecutados: ", g_tradesExecuted);
    double wr = g_tradeAttempts>0 ? (g_tradesExecuted*100.0/g_tradeAttempts) : 0;
    Print("Tasa ejecución: ", DoubleToString(wr, 1), "%");
    Print("========================================");
}
//+------------------------------------------------------------------+
