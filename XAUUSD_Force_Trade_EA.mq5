//+------------------------------------------------------------------+
//|                                    XAUUSD_Force_Trade_EA.mq5     |
//|                    FUERZA TRADES CADA 10 VELAS                   |
//|                    PARA VERIFICAR QUE EL CÓDIGO FUNCIONA         |
//+------------------------------------------------------------------+
#property copyright "Force Trade EA"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input int      StopLoss_Points = 30;          // Stop loss in points
input int      TakeProfit_Points = 60;        // Take profit in points
input double   Risk_Percent = 1.0;            // Risk per trade (% of balance)
input int      Magic_Number = 999999;         // EA magic number
input int      Bars_Between_Trades = 10;      // Velas entre trades (FORZADO)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
int g_barCounter = 0;
bool g_nextTradeLong = true;  // Alternar entre long y short
int g_totalTrades = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("FORCE TRADE EA - INICIADO");
    Print("========================================");
    Print("Este EA FUERZA un trade cada ", Bars_Between_Trades, " velas");
    Print("Alterna entre LONG y SHORT automáticamente");
    Print("SL: ", StopLoss_Points, "p | TP: ", TakeProfit_Points, "p");
    Print("========================================");
    
    g_barCounter = 0;
    g_nextTradeLong = true;
    g_totalTrades = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Detectar nueva vela
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    if(currentBarTime == g_lastBarTime)
    {
        return; // No es nueva vela
    }
    g_lastBarTime = currentBarTime;
    
    // Incrementar contador
    g_barCounter++;
    
    Print("Vela #", g_barCounter, " | Próximo trade en: ", (Bars_Between_Trades - g_barCounter), " velas");
    
    // Si ya hay posición, no hacer nada
    if(PositionSelect(_Symbol))
    {
        Print("Posición abierta, esperando cierre...");
        return;
    }
    
    // Cada X velas, FORZAR un trade
    if(g_barCounter >= Bars_Between_Trades)
    {
        Print("========================================");
        Print(">>> FORZANDO TRADE #", (g_totalTrades + 1), " <<<");
        Print("========================================");
        
        // Alternar dirección
        ExecuteTrade(g_nextTradeLong);
        g_nextTradeLong = !g_nextTradeLong;  // Cambiar para próximo trade
        
        // Reset contador
        g_barCounter = 0;
    }
}

//+------------------------------------------------------------------+
//| Execute trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(bool isLong)
{
    // Get current price
    double price = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate SL and TP
    double sl, tp;
    if(isLong)
    {
        sl = price - StopLoss_Points * _Point;
        tp = price + TakeProfit_Points * _Point;
    }
    else
    {
        sl = price + StopLoss_Points * _Point;
        tp = price - TakeProfit_Points * _Point;
    }
    
    // Normalize prices
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // Calculate lot size
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * Risk_Percent / 100.0;
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * _Point;
    
    double lotSize = riskAmount / (StopLoss_Points * pointValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = NormalizeDouble(lotSize, 2);
    
    // Prepare trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = Magic_Number;
    request.comment = "Force Trade";
    request.type_filling = ORDER_FILLING_IOC;
    
    // Send order
    Print("EJECUTANDO TRADE FORZADO:");
    Print("  Dirección: ", isLong ? "LONG (BUY)" : "SHORT (SELL)");
    Print("  Precio: ", DoubleToString(price, _Digits));
    Print("  SL: ", DoubleToString(sl, _Digits), " (", StopLoss_Points, " points)");
    Print("  TP: ", DoubleToString(tp, _Digits), " (", TakeProfit_Points, " points)");
    Print("  Lote: ", lotSize);
    
    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            g_totalTrades++;
            Print("✅ TRADE EJECUTADO EXITOSAMENTE");
            Print("  Order: ", result.order);
            Print("  Deal: ", result.deal);
            Print("  Total Trades: ", g_totalTrades);
        }
        else
        {
            Print("❌ ERROR: Trade falló");
            Print("  Return Code: ", result.retcode);
            Print("  Comment: ", result.comment);
        }
    }
    else
    {
        Print("❌ ERROR: OrderSend falló");
        Print("  Last Error: ", GetLastError());
    }
    
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("========================================");
    Print("FORCE TRADE EA - DETENIDO");
    Print("Total Trades Ejecutados: ", g_totalTrades);
    Print("========================================");
}
//+------------------------------------------------------------------+
