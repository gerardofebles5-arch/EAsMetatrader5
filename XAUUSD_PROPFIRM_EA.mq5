//+------------------------------------------------------------------+
//|                                  XAUUSD_PROPFIRM_EA.mq5          |
//|                    ESTRATEGIA PARA APROBAR PROP FIRMS            |
//+------------------------------------------------------------------+
#property copyright "PropFirm EA"
#property version   "1.00"
#property strict

// Inputs optimizados para prop firms
input int Magic_Number = 888888;
input double Risk_Percent = 0.5;              // Risk conservador
input double RR_Ratio = 2.0;                  // Risk/Reward 1:2 mínimo
input int Min_Bars_Between_Trades = 30;       // Espaciar trades
input int Max_Daily_Trades = 5;               // Máximo 5 trades/día
input double Max_Daily_Loss_Percent = 3.0;    // Stop diario 3%

// Parámetros de estrategia
input int ATR_Period = 14;
input double ATR_SL_Multiplier = 1.5;
input double Break_Even_ATR = 1.0;

datetime g_lastBarTime = 0;
datetime g_lastTradeTime = 0;
int g_dailyTrades = 0;
double g_dailyPnL = 0;
datetime g_currentDay = 0;

int g_handle_ATR;
int g_handle_EMA_Fast;
int g_handle_EMA_Slow;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD PROP FIRM EA - INICIADO");
    Print("========================================");
    Print("Risk: ", Risk_Percent, "% | RR: 1:", RR_Ratio);
    Print("Max trades/día: ", Max_Daily_Trades);
    Print("========================================");
    
    g_handle_ATR = iATR(_Symbol, PERIOD_M15, ATR_Period);
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_handle_ATR == INVALID_HANDLE || g_handle_EMA_Fast == INVALID_HANDLE || 
       g_handle_EMA_Slow == INVALID_HANDLE)
    {
        Print("❌ Error creando indicadores");
        return(INIT_FAILED);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        
        // Reset contadores diarios
        ResetDailyCounters();
        
        // Gestionar posición abierta
        if(PositionSelect(_Symbol))
        {
            ManagePosition();
            return;
        }
        
        // Verificar límites
        if(!CheckTradingLimits())
            return;
        
        // Analizar señal
        int signal = AnalyzeSetup();
        
        if(signal == 1)
        {
            Print("✅ SETUP LONG");
            ExecuteTrade(ORDER_TYPE_BUY);
        }
        else if(signal == -1)
        {
            Print("✅ SETUP SHORT");
            ExecuteTrade(ORDER_TYPE_SELL);
        }
    }
    else if(PositionSelect(_Symbol))
    {
        ManagePosition();
    }
}

//+------------------------------------------------------------------+
void ResetDailyCounters()
{
    datetime today = iTime(_Symbol, PERIOD_D1, 0);
    
    if(today != g_currentDay)
    {
        g_currentDay = today;
        g_dailyTrades = 0;
        g_dailyPnL = 0;
        Print("=== NUEVO DÍA ===");
    }
}

//+------------------------------------------------------------------+
bool CheckTradingLimits()
{
    // Límite de trades diarios
    if(g_dailyTrades >= Max_Daily_Trades)
    {
        Print("⏸️ Límite diario alcanzado: ", g_dailyTrades, " trades");
        return false;
    }
    
    // Stop loss diario
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double maxLoss = accountBalance * Max_Daily_Loss_Percent / 100.0;
    
    if(g_dailyPnL <= -maxLoss)
    {
        Print("🛑 Stop diario activado: $", g_dailyPnL);
        return false;
    }
    
    // Tiempo mínimo entre trades
    int barsSinceLastTrade = iBarShift(_Symbol, PERIOD_M5, g_lastTradeTime);
    if(barsSinceLastTrade >= 0 && barsSinceLastTrade < Min_Bars_Between_Trades)
    {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
int AnalyzeSetup()
{
    // Obtener ATR
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_handle_ATR, 0, 0, 2, atr) <= 0)
        return 0;
    
    // Obtener EMAs
    double ema_fast[], ema_slow[], close_m15[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(close_m15, true);
    
    if(CopyBuffer(g_handle_EMA_Fast, 0, 0, 3, ema_fast) <= 0 ||
       CopyBuffer(g_handle_EMA_Slow, 0, 0, 3, ema_slow) <= 0 ||
       CopyClose(_Symbol, PERIOD_M15, 0, 3, close_m15) <= 0)
        return 0;
    
    // SETUP 1: Pullback en tendencia alcista
    if(ema_fast[0] > ema_slow[0])  // Tendencia alcista
    {
        // Precio hizo pullback a EMA fast
        if(close_m15[1] < ema_fast[1] && close_m15[0] > ema_fast[0])
        {
            // Confirmar con vela M5 alcista
            double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
            double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
            
            if(close_m5 > open_m5)
            {
                Print("📈 Pullback alcista confirmado");
                return 1;
            }
        }
    }
    
    // SETUP 2: Pullback en tendencia bajista
    if(ema_fast[0] < ema_slow[0])  // Tendencia bajista
    {
        // Precio hizo pullback a EMA fast
        if(close_m15[1] > ema_fast[1] && close_m15[0] < ema_fast[0])
        {
            // Confirmar con vela M5 bajista
            double open_m5 = iOpen(_Symbol, PERIOD_M5, 1);
            double close_m5 = iClose(_Symbol, PERIOD_M5, 1);
            
            if(close_m5 < open_m5)
            {
                Print("📉 Pullback bajista confirmado");
                return -1;
            }
        }
    }
    
    return 0;
}

//+------------------------------------------------------------------+
void ManagePosition()
{
    if(!PositionSelect(_Symbol))
        return;
    
    double position_open = PositionGetDouble(POSITION_PRICE_OPEN);
    double position_current = PositionGetDouble(POSITION_PRICE_CURRENT);
    long position_type = PositionGetInteger(POSITION_TYPE);
    double current_sl = PositionGetDouble(POSITION_SL);
    
    // Obtener ATR
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_handle_ATR, 0, 0, 1, atr) <= 0)
        return;
    
    double atr_points = atr[0] / _Point;
    double break_even_distance = atr_points * Break_Even_ATR;
    
    double profit_points = 0;
    if(position_type == POSITION_TYPE_BUY)
        profit_points = (position_current - position_open) / _Point;
    else
        profit_points = (position_open - position_current) / _Point;
    
    // Break Even
    if(profit_points >= break_even_distance)
    {
        double new_sl = position_open + (10 * _Point);  // BE + 10 points
        
        if(position_type == POSITION_TYPE_BUY && new_sl > current_sl)
        {
            ModifySL(new_sl);
            Print("✅ Break Even LONG activado");
        }
        else if(position_type == POSITION_TYPE_SELL && (new_sl < current_sl || current_sl == 0))
        {
            ModifySL(new_sl);
            Print("✅ Break Even SHORT activado");
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
    // Obtener ATR para SL/TP
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_handle_ATR, 0, 0, 1, atr) <= 0)
        return;
    
    double atr_points = atr[0] / _Point;
    double sl_points = atr_points * ATR_SL_Multiplier;
    double tp_points = sl_points * RR_Ratio;
    
    // Límites
    if(sl_points < 30) sl_points = 30;
    if(sl_points > 80) sl_points = 80;
    tp_points = sl_points * RR_Ratio;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
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
    
    // Calcular lote con risk management
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
    
    Print("=== PROP FIRM TRADE ===");
    Print("Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    Print("SL: ", (int)sl_points, "p | TP: ", (int)tp_points, "p | RR: 1:", RR_Ratio);
    Print("Risk: $", riskAmount, " | Lote: ", lotSize);
    
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
    request.comment = "PropFirm";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_dailyTrades++;
        g_lastTradeTime = iTime(_Symbol, PERIOD_M5, 0);
        Print("✅ TRADE EJECUTADO | Trades hoy: ", g_dailyTrades);
    }
    else
    {
        Print("❌ TRADE FALLÓ | Retcode: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    
    Print("========================================");
    Print("PROP FIRM EA - FINALIZADO");
    Print("========================================");
}
//+------------------------------------------------------------------+
