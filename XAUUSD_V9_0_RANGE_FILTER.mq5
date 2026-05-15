//+------------------------------------------------------------------+
//|                        XAUUSD_V9_0_RANGE_FILTER.mq5              |
//|          V9.0: CON FILTRO DE RANGO (ADX + DISTANCIA EMA50)       |
//|   Solo opera en mercados de rango, evita tendencias fuertes      |
//+------------------------------------------------------------------+
#property copyright "V9.0 - Range Filter"
#property version   "9.00"
#property strict

input int Magic_Number = 999999;
input double Risk_Percent = 1.0;
input int Max_Trades_Per_Day = 5;

// EMAs
input int EMA_Fast = 9;
input int EMA_Medium = 21;
input int EMA_Slow = 50;

// Risk Management
input double SL_ATR_Multiplier = 2.0;
input double TP_ATR_Multiplier = 4.0;     // RR 1:2 (más alcanzable)
input int ATR_Period = 14;

// FILTRO DE RANGO
input int ADX_Period = 14;
input double Max_ADX_Trend = 25.0;        // ADX < 25 = rango
input double Max_Distance_Percent = 2.0;  // Precio dentro 2% de EMA50

// Break-Even
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 2.0;
input double BreakEven_Profit_ATR = 0.5;

// Trailing Stop
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 3.0;
input double Trailing_Step_ATR = 1.5;

// Variables globales
datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;
int g_signalsFiltered = 0;  // Contador de señales filtradas

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
    Print("XAUUSD V9.0 - RANGE FILTER");
    Print("========================================");
    Print("FILTRO DE RANGO ACTIVO:");
    Print("  Max ADX: ", Max_ADX_Trend, " (< = rango)");
    Print("  Max Distancia: ", Max_Distance_Percent, "% de EMA50");
    Print("RR: 1:2 (SL 2.0×ATR, TP 4.0×ATR)");
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
    
    Print("✅ Todos los indicadores creados (incluido ADX)");
    
    g_lastBarTime = 0;
    g_tradesExecuted = 0;
    g_tradesToday = 0;
    g_lastTradeDate = 0;
    g_signalsFiltered = 0;
    
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
    
    if(Use_Trailing_Stop && PositionSelect(_Symbol))
    {
        ManageTrailingStop();
    }
    
    if(Use_Break_Even && PositionSelect(_Symbol))
    {
        ManageBreakEven();
    }
}

//+------------------------------------------------------------------+
bool IsRangeMarket()
{
    // Obtener ADX
    double adx[];
    ArraySetAsSeries(adx, true);
    
    if(CopyBuffer(g_handle_ADX, 0, 0, 3, adx) <= 0)
    {
        Print("⚠️ Error copiando ADX");
        return false;
    }
    
    double current_adx = adx[0];
    
    // Obtener EMA50 y precio
    double ema_slow[], close[];
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_EMA_Slow, 0, 0, 3, ema_slow) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        Print("⚠️ Error copiando EMA50 o Close");
        return false;
    }
    
    double distance_percent = MathAbs(close[0] - ema_slow[0]) / ema_slow[0] * 100.0;
    
    // FILTRO: ADX < 25 AND distancia < 2%
    bool is_range = (current_adx < Max_ADX_Trend) && (distance_percent < Max_Distance_Percent);
    
    if(!is_range)
    {
        Print("🚫 FILTRO: Mercado en TENDENCIA - ADX=", current_adx, " Dist=", distance_percent, "%");
    }
    else
    {
        Print("✅ FILTRO: Mercado en RANGO - ADX=", current_adx, " Dist=", distance_percent, "%");
    }
    
    return is_range;
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
    // PRIMERO: Verificar filtro de rango
    if(!IsRangeMarket())
    {
        g_signalsFiltered++;
        return;  // NO operar en tendencias
    }
    
    // Copiar buffers
    double ema_fast[], ema_medium[], ema_slow[], atr[], close[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_medium, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Medium, 0, 0, 5, ema_medium) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 5, ema_slow) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 5, close) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
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
        Print("📈 SEÑAL LONG EN RANGO - Ejecutando");
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
        g_tradesToday++;
    }
    else if(short_signal)
    {
        Print("📉 SEÑAL SHORT EN RANGO - Ejecutando");
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
    
    Print("=== TRADE V9.0 ===");
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
    request.comment = "V9.0-RANGE";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ TRADE #", g_tradesExecuted, " EJECUTADO EN RANGO");
    }
    else
    {
        Print("❌ TRADE FALLÓ - Retcode: ", result.retcode);
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
        Print("✅ Break-Even activado");
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
    Print("V9.0 RANGE FILTER FINALIZADO");
    Print("Total Trades: ", g_tradesExecuted);
    Print("Señales Filtradas: ", g_signalsFiltered);
    Print("========================================");
}
//+------------------------------------------------------------------+
