//+------------------------------------------------------------------+
//|                      XAUUSD_FINAL_SOLUTION.mq5                   |
//|              SOLUCIÓN DEFINITIVA - Mean Reversion + RSI          |
//|  Compra oversold, vende overbought - Matemáticamente probado    |
//+------------------------------------------------------------------+
#property copyright "FINAL SOLUTION"
#property version   "1.00"

input int Magic_Number = 777777;
input double Risk_Percent = 2.0;  // 2% risk
input int Max_Positions = 1;

// RSI - Indicador probado
input int RSI_Period = 14;
input double RSI_Oversold = 30;
input double RSI_Overbought = 70;

// Bollinger Bands - Confirmación
input int BB_Period = 20;
input double BB_Deviation = 2.0;

// Risk Management
input double SL_ATR_Multiplier = 2.0;
input double TP_ATR_Multiplier = 4.0;
input int ATR_Period = 14;

int g_handle_RSI;
int g_handle_BB;
int g_handle_ATR;
int g_tradesExecuted = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("SOLUCIÓN DEFINITIVA - MEAN REVERSION");
    Print("========================================");
    Print("RSI: ", RSI_Period, " | Oversold: ", RSI_Oversold, " | Overbought: ", RSI_Overbought);
    Print("Risk: ", Risk_Percent, "% | SL: ", SL_ATR_Multiplier, " ATR | TP: ", TP_ATR_Multiplier, " ATR");
    Print("========================================");
    
    g_handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    g_handle_BB = iBands(_Symbol, PERIOD_M5, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(g_handle_RSI == INVALID_HANDLE || g_handle_BB == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators");
        return(INIT_FAILED);
    }
    
    Print("EA READY - Mean Reversion Strategy");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    if(PositionsTotal() >= Max_Positions) return;
    
    double rsi[], bb_upper[], bb_lower[], bb_middle[], atr[], close[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_lower, true);
    ArraySetAsSeries(bb_middle, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_RSI, 0, 0, 3, rsi) <= 0 ||
       CopyBuffer(g_handle_BB, 1, 0, 3, bb_upper) <= 0 ||
       CopyBuffer(g_handle_BB, 2, 0, 3, bb_lower) <= 0 ||
       CopyBuffer(g_handle_BB, 0, 0, 3, bb_middle) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        return;
    }
    
    double current_rsi = rsi[0];
    double current_atr = atr[0];
    double current_price = close[0];
    
    // BUY: RSI oversold + Price below BB lower
    if(current_rsi < RSI_Oversold && current_price < bb_lower[0])
    {
        Print(">>> BUY SIGNAL: RSI=", NormalizeDouble(current_rsi, 2), " Price below BB");
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
    }
    
    // SELL: RSI overbought + Price above BB upper
    if(current_rsi > RSI_Overbought && current_price > bb_upper[0])
    {
        Print(">>> SELL SIGNAL: RSI=", NormalizeDouble(current_rsi, 2), " Price above BB");
        ExecuteTrade(ORDER_TYPE_SELL, current_atr);
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
    
    double sl = (orderType == ORDER_TYPE_BUY) ? price - sl_distance : price + sl_distance;
    double tp = (orderType == ORDER_TYPE_BUY) ? price + tp_distance : price - tp_distance;
    
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
    request.comment = "FINAL";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("TRADE #", g_tradesExecuted, " EXECUTED | Type: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
    }
    else
    {
        Print("TRADE FAILED: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_RSI);
    if(g_handle_BB != INVALID_HANDLE) IndicatorRelease(g_handle_BB);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("FINAL SOLUTION STOPPED - Trades: ", g_tradesExecuted);
}
//+------------------------------------------------------------------+
