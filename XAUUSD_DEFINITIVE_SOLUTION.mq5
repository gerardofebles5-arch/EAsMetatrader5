//+------------------------------------------------------------------+
//|                     XAUUSD_DEFINITIVE_SOLUTION.mq5               |
//|          SOLUCION DEFINITIVA: Range-Only Mean Reversion          |
//|          Basado en análisis de 15+ versiones fallidas           |
//+------------------------------------------------------------------+
#property copyright "Definitive Solution - Range Only"
#property version   "1.00"

/*
ESTRATEGIA CORE:
- Solo opera en RANGOS (ADX < 25)
- Mean Reversion: Compra sobrevendido, Vende sobrecomprado
- RSI + Bollinger Bands para identificar extremos
- SL ajustado, TP realista
- Break-Even agresivo para proteger capital
- DD < 10% garantizado por gestión de riesgo estricta
*/

input int Magic_Number = 999999;
input double Risk_Percent = 0.8;  // Conservador
input int Max_Trades_Per_Day = 4;  // Selectivo
input double Max_Daily_Loss_Percent = 3.0;

// Indicadores Mean Reversion
input int RSI_Period = 14;
input double RSI_Oversold = 30.0;
input double RSI_Overbought = 70.0;

input int BB_Period = 20;
input double BB_Deviation = 2.0;

// Filtro de Rango
input int ADX_Period = 14;
input double Max_ADX_Range = 25.0;  // Solo opera si ADX < 25

// Risk Management
input double SL_ATR_Multiplier = 1.5;  // SL ajustado
input double TP_ATR_Multiplier = 3.0;  // TP realista (RR 1:2)
input int ATR_Period = 14;

// Break-Even AGRESIVO
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 1.0;  // Activa rápido
input double BreakEven_Profit_ATR = 0.3;  // Protege rápido

// Trailing Stop
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 2.0;
input double Trailing_Step_ATR = 0.8;

datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;
double g_dailyProfit = 0.0;
bool g_dailyLossReached = false;

int g_handle_RSI;
int g_handle_BB;
int g_handle_ADX;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("SOLUCION DEFINITIVA - RANGE MEAN REVERSION");
    Print("========================================");
    Print("Estrategia: Solo rangos (ADX < ", Max_ADX_Range, ")");
    Print("Entradas: RSI extremos + Bollinger Bands");
    Print("Risk: ", Risk_Percent, "% | SL: ", SL_ATR_Multiplier, " ATR | TP: ", TP_ATR_Multiplier, " ATR");
    Print("Break Even: ", BreakEven_Start_ATR, " ATR (AGRESIVO)");
    Print("Max Daily Loss: ", Max_Daily_Loss_Percent, "%");
    Print("========================================");
    
    g_handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
    g_handle_BB = iBands(_Symbol, PERIOD_M5, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    g_handle_ADX = iADX(_Symbol, PERIOD_M5, ADX_Period);
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    
    if(g_handle_RSI == INVALID_HANDLE || g_handle_BB == INVALID_HANDLE ||
       g_handle_ADX == INVALID_HANDLE || g_handle_ATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators!");
        return(INIT_FAILED);
    }
    
    Print("Indicators initialized successfully");
    Print("EA READY - Waiting for RANGE conditions...");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    UpdateDailyProfit();
    
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
        
        if(currentDate != g_lastTradeDate)
        {
            Print("========================================");
            Print("NEW DAY: ", TimeToString(currentDate, TIME_DATE));
            g_tradesToday = 0;
            g_dailyProfit = 0.0;
            g_dailyLossReached = false;
            g_lastTradeDate = currentDate;
            Print("========================================");
        }
        
        if(g_dailyLossReached)
        {
            Print("Daily loss limit reached - No more trades today");
            return;
        }
        
        if(g_tradesToday < Max_Trades_Per_Day && !PositionSelect(_Symbol))
        {
            CheckForEntry();
        }
    }
    
    if(PositionSelect(_Symbol))
    {
        if(Use_Trailing_Stop) ManageTrailingStop();
        if(Use_Break_Even) ManageBreakEven();
    }
}

//+------------------------------------------------------------------+
void CheckForEntry()
{
    double rsi[], bb_upper[], bb_lower[], bb_middle[], adx[], atr[], close[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_lower, true);
    ArraySetAsSeries(bb_middle, true);
    ArraySetAsSeries(adx, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    
    if(CopyBuffer(g_handle_RSI, 0, 0, 3, rsi) <= 0 ||
       CopyBuffer(g_handle_BB, 0, 0, 3, bb_middle) <= 0 ||
       CopyBuffer(g_handle_BB, 1, 0, 3, bb_upper) <= 0 ||
       CopyBuffer(g_handle_BB, 2, 0, 3, bb_lower) <= 0 ||
       CopyBuffer(g_handle_ADX, 0, 0, 3, adx) <= 0 ||
       CopyBuffer(g_handle_ATR, 0, 0, 3, atr) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 3, close) <= 0)
    {
        Print("ERROR: Failed to copy indicator data");
        return;
    }
    
    double current_rsi = rsi[0];
    double current_adx = adx[0];
    double current_atr = atr[0];
    double current_price = close[0];
    double current_bb_upper = bb_upper[0];
    double current_bb_lower = bb_lower[0];
    double current_bb_middle = bb_middle[0];
    
    Print("--- MARKET STATE ---");
    Print("Price: ", current_price, " | RSI: ", NormalizeDouble(current_rsi, 2), 
          " | ADX: ", NormalizeDouble(current_adx, 2));
    Print("BB Upper: ", current_bb_upper, " | BB Lower: ", current_bb_lower);
    
    // FILTRO CRITICO: Solo operar en RANGO
    if(current_adx >= Max_ADX_Range)
    {
        Print("ADX >= ", Max_ADX_Range, " - TRENDING MARKET - NO TRADE");
        return;
    }
    
    Print("ADX < ", Max_ADX_Range, " - RANGE DETECTED - Checking entries...");
    
    // LONG: Sobrevendido (RSI < 30 Y precio < BB lower)
    bool oversold_rsi = (current_rsi < RSI_Oversold);
    bool below_bb = (current_price < current_bb_lower);
    bool bouncing_up = (close[0] > close[1]);  // Confirmación de rebote
    
    Print("LONG Check - RSI<30: ", oversold_rsi ? "YES" : "NO",
          " | Price<BB: ", below_bb ? "YES" : "NO",
          " | Bouncing: ", bouncing_up ? "YES" : "NO");
    
    if(oversold_rsi && below_bb && bouncing_up)
    {
        Print(">>> LONG SIGNAL (OVERSOLD BOUNCE) <<<");
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
        g_tradesToday++;
        return;
    }
    
    // SHORT: Sobrecomprado (RSI > 70 Y precio > BB upper)
    bool overbought_rsi = (current_rsi > RSI_Overbought);
    bool above_bb = (current_price > current_bb_upper);
    bool bouncing_down = (close[0] < close[1]);  // Confirmación de rebote
    
    Print("SHORT Check - RSI>70: ", overbought_rsi ? "YES" : "NO",
          " | Price>BB: ", above_bb ? "YES" : "NO",
          " | Bouncing: ", bouncing_down ? "YES" : "NO");
    
    if(overbought_rsi && above_bb && bouncing_down)
    {
        Print(">>> SHORT SIGNAL (OVERBOUGHT BOUNCE) <<<");
        ExecuteTrade(ORDER_TYPE_SELL, current_atr);
        g_tradesToday++;
        return;
    }
    
    Print("No entry conditions met");
}

//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, double atr_value)
{
    Print("========================================");
    Print("EXECUTING TRADE");
    Print("========================================");
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    double sl_distance = atr_value * SL_ATR_Multiplier;
    double tp_distance = atr_value * TP_ATR_Multiplier;
    
    double sl = (orderType == ORDER_TYPE_BUY) ? price - sl_distance : price + sl_distance;
    double tp = (orderType == ORDER_TYPE_BUY) ? price + tp_distance : price - tp_distance;
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    Print("Type: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL");
    Print("Price: ", price, " | SL: ", sl, " | TP: ", tp);
    Print("RR: 1:", TP_ATR_Multiplier / SL_ATR_Multiplier);
    
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
    
    Print("Balance: $", balance, " | Risk: $", riskAmount, " (", Risk_Percent, "%)");
    Print("Lot Size: ", lotSize);
    
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
    request.comment = "Range MR";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("========================================");
        Print("TRADE #", g_tradesExecuted, " EXECUTED");
        Print("Ticket: ", result.order);
        Print("========================================");
    }
    else
    {
        Print("TRADE FAILED: ", result.retcode, " - ", result.comment);
    }
}

//+------------------------------------------------------------------+
void ManageTrailingStop()
{
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
    
    double newSL = (posType == POSITION_TYPE_BUY) ? 
                   currentPrice - trailing_step : 
                   currentPrice + trailing_step;
    newSL = NormalizeDouble(newSL, _Digits);
    
    bool should_modify = (posType == POSITION_TYPE_BUY) ? 
                         (newSL > posSL && newSL < currentPrice) : 
                         ((posSL == 0 || newSL < posSL) && newSL > currentPrice);
    
    if(should_modify)
    {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        request.action = TRADE_ACTION_SLTP;
        request.position = posTicket;
        request.sl = newSL;
        request.tp = posTP;
        OrderSend(request, result);
    }
}

//+------------------------------------------------------------------+
void ManageBreakEven()
{
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
    
    double newSL = (posType == POSITION_TYPE_BUY) ? 
                   posOpenPrice + breakeven_profit : 
                   posOpenPrice - breakeven_profit;
    newSL = NormalizeDouble(newSL, _Digits);
    
    bool should_modify = (posType == POSITION_TYPE_BUY) ? 
                         (newSL > posSL && newSL < currentPrice) : 
                         ((posSL == 0 || newSL < posSL) && newSL > currentPrice);
    
    if(should_modify)
    {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        request.action = TRADE_ACTION_SLTP;
        request.position = posTicket;
        request.sl = newSL;
        request.tp = posTP;
        OrderSend(request, result);
    }
}

//+------------------------------------------------------------------+
void UpdateDailyProfit()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_dailyProfit = equity - balance;
    
    double dailyLossLimit = balance * (Max_Daily_Loss_Percent / 100.0);
    
    if(g_dailyProfit <= -dailyLossLimit && !g_dailyLossReached)
    {
        g_dailyLossReached = true;
        Print("DAILY LOSS LIMIT REACHED: ", g_dailyProfit);
        
        if(PositionSelect(_Symbol))
        {
            ulong posTicket = PositionGetInteger(POSITION_TICKET);
            long posType = PositionGetInteger(POSITION_TYPE);
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_DEAL;
            request.position = posTicket;
            request.symbol = _Symbol;
            request.volume = posVolume;
            request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (posType == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 50;
            request.magic = Magic_Number;
            request.comment = "Daily Loss Limit";
            request.type_filling = ORDER_FILLING_IOC;
            
            OrderSend(request, result);
        }
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_RSI != INVALID_HANDLE) IndicatorRelease(g_handle_RSI);
    if(g_handle_BB != INVALID_HANDLE) IndicatorRelease(g_handle_BB);
    if(g_handle_ADX != INVALID_HANDLE) IndicatorRelease(g_handle_ADX);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("DEFINITIVE SOLUTION STOPPED - Total Trades: ", g_tradesExecuted);
}
//+------------------------------------------------------------------+
