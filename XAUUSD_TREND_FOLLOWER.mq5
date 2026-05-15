//+------------------------------------------------------------------+
//|                              XAUUSD_TREND_FOLLOWER.mq5           |
//|                    ESTRATEGIA REFINADA - TREND FOLLOWING         |
//+------------------------------------------------------------------+
#property copyright "Trend Follower"
#property version   "1.00"
#property strict

input int Magic_Number = 777777;
input int Trade_Every_N_Bars = 10;
input double Risk_Percent = 1.0;
input double SL_Points = 40;
input double TP_Points = 120;
input bool Use_Trailing_Stop = true;
input double Trailing_Start_Points = 50;
input double Trailing_Distance_Points = 30;

datetime g_lastBarTime = 0;
int g_barCount = 0;
int g_tradesExecuted = 0;

int g_handle_EMA_Fast;
int g_handle_EMA_Slow;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD TREND FOLLOWER");
    Print("========================================");
    Print("Estrategia: Seguir la tendencia (NO contrarian)");
    Print("Trade cada: ", Trade_Every_N_Bars, " velas");
    Print("SL/TP: ", SL_Points, "/", TP_Points, " points");
    Print("========================================");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_handle_EMA_Fast == INVALID_HANDLE || g_handle_EMA_Slow == INVALID_HANDLE)
    {
        Print("❌ Error al crear indicadores");
        return(INIT_FAILED);
    }
    
    g_lastBarTime = 0;
    g_barCount = 0;
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
                if(Use_Trailing_Stop)
                    ManageTrailingStop();
                return;
            }
            
            Print("========================================");
            Print("VELA #", g_barCount);
            
            int direction = AnalyzeTrend();
            
            if(direction == 1)
            {
                Print("✅ TREND LONG");
                ExecuteTrade(ORDER_TYPE_BUY);
            }
            else if(direction == -1)
            {
                Print("✅ TREND SHORT");
                ExecuteTrade(ORDER_TYPE_SELL);
            }
        }
    }
    else if(PositionSelect(_Symbol) && Use_Trailing_Stop)
    {
        ManageTrailingStop();
    }
}

//+------------------------------------------------------------------+
//| Analizar tendencia - SEGUIR LA TENDENCIA                         |
//+------------------------------------------------------------------+
int AnalyzeTrend()
{
    double ema_fast[], ema_slow[], close_m15[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(close_m15, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 2, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 2, ema_slow) <= 0 ||
       CopyClose(_Symbol, PERIOD_M15, 0, 2, close_m15) <= 0)
    {
        Print("❌ Error obteniendo datos");
        return 0;
    }
    
    // TREND FOLLOWING: Operar A FAVOR de la tendencia
    
    // Tendencia alcista fuerte: Precio > EMA Fast > EMA Slow
    if(close_m15[0] > ema_fast[0] && ema_fast[0] > ema_slow[0])
    {
        // Confirmar con vela M5
        double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
        double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
        
        if(close_m5 > open_m5)  // Vela alcista confirma
        {
            Print("📈 Tendencia ALCISTA fuerte + Vela alcista");
            return 1;  // LONG
        }
    }
    
    // Tendencia bajista fuerte: Precio < EMA Fast < EMA Slow
    if(close_m15[0] < ema_fast[0] && ema_fast[0] < ema_slow[0])
    {
        // Confirmar con vela M5
        double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
        double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
        
        if(close_m5 < open_m5)  // Vela bajista confirma
        {
            Print("📉 Tendencia BAJISTA fuerte + Vela bajista");
            return -1;  // SHORT
        }
    }
    
    // Tendencia alcista débil
    if(close_m15[0] > ema_fast[0])
    {
        double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
        double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
        
        if(close_m5 > open_m5)
        {
            Print("📈 Tendencia alcista débil + Vela alcista");
            return 1;
        }
    }
    
    // Tendencia bajista débil
    if(close_m15[0] < ema_fast[0])
    {
        double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
        double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
        
        if(close_m5 < open_m5)
        {
            Print("📉 Tendencia bajista débil + Vela bajista");
            return -1;
        }
    }
    
    Print("⏸️ Sin tendencia clara");
    return 0;
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    if(!PositionSelect(_Symbol))
        return;
    
    double position_open = PositionGetDouble(POSITION_PRICE_OPEN);
    double position_current = PositionGetDouble(POSITION_PRICE_CURRENT);
    long position_type = PositionGetInteger(POSITION_TYPE);
    double current_sl = PositionGetDouble(POSITION_SL);
    
    double profit_points = 0;
    
    if(position_type == POSITION_TYPE_BUY)
        profit_points = (position_current - position_open) / _Point;
    else
        profit_points = (position_open - position_current) / _Point;
    
    // Activar trailing si profit > Trailing_Start_Points
    if(profit_points >= Trailing_Start_Points)
    {
        double new_sl = 0;
        
        if(position_type == POSITION_TYPE_BUY)
        {
            new_sl = position_current - Trailing_Distance_Points * _Point;
            if(new_sl > current_sl)
            {
                ModifySL(new_sl);
                Print("✅ Trailing LONG: SL movido a ", new_sl);
            }
        }
        else
        {
            new_sl = position_current + Trailing_Distance_Points * _Point;
            if(new_sl < current_sl || current_sl == 0)
            {
                ModifySL(new_sl);
                Print("✅ Trailing SHORT: SL movido a ", new_sl);
            }
        }
    }
}

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
    
    if(!OrderSend(request, result))
    {
        Print("❌ Error modificando SL: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    double sl, tp;
    if(orderType == ORDER_TYPE_BUY)
    {
        sl = price - SL_Points * _Point;
        tp = price + TP_Points * _Point;
    }
    else
    {
        sl = price + SL_Points * _Point;
        tp = price - TP_Points * _Point;
    }
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    double lotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    Print("=== TRADE TREND FOLLOWING ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("Precio: ", price);
    Print("SL: ", sl, " (", SL_Points, " points)");
    Print("TP: ", tp, " (", TP_Points, " points)");
    Print("Lote: ", lotSize);
    
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
    request.comment = "Trend Follower";
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
    
    Print("========================================");
    Print("TREND FOLLOWER - FINALIZADO");
    Print("Total Ejecutados: ", g_tradesExecuted);
    Print("========================================");
}
//+------------------------------------------------------------------+
