//+------------------------------------------------------------------+
//|                        XAUUSD_V8_0_DIAGNOSTIC.mq5                |
//|          V8.0 DIAGNOSTIC: CON LOGGING EXTENSIVO                  |
//|   Versión diagnóstica para identificar por qué no opera          |
//+------------------------------------------------------------------+
#property copyright "V8.0 - Diagnostic"
#property version   "8.00"
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
input double TP_ATR_Multiplier = 6.0;
input int ATR_Period = 14;

// Break-Even
input bool Use_Break_Even = true;
input double BreakEven_Start_ATR = 2.5;
input double BreakEven_Profit_ATR = 0.5;

// Trailing Stop
input bool Use_Trailing_Stop = true;
input double Trailing_Start_ATR = 3.5;
input double Trailing_Step_ATR = 1.2;

// Variables globales
datetime g_lastBarTime = 0;
int g_tradesExecuted = 0;
int g_tradesToday = 0;
datetime g_lastTradeDate = 0;
int g_checkEntryCallCount = 0;  // DIAGNOSTIC: Contador de llamadas

// Handles
int g_handle_EMA_Fast;
int g_handle_EMA_Medium;
int g_handle_EMA_Slow;
int g_handle_ATR;

//+------------------------------------------------------------------+
int OnInit()
{
    Print("========================================");
    Print("XAUUSD V8.0 - DIAGNOSTIC VERSION");
    Print("========================================");
    Print("CONFIGURACIÓN:");
    Print("  Magic Number: ", Magic_Number);
    Print("  Risk: ", Risk_Percent, "%");
    Print("  Max Trades/Day: ", Max_Trades_Per_Day);
    Print("  EMA Fast: ", EMA_Fast);
    Print("  EMA Medium: ", EMA_Medium);
    Print("  EMA Slow: ", EMA_Slow);
    Print("  ATR Period: ", ATR_Period);
    Print("  SL Multiplier: ", SL_ATR_Multiplier, "×ATR");
    Print("  TP Multiplier: ", TP_ATR_Multiplier, "×ATR (RR 1:3)");
    Print("  Break-Even: ", Use_Break_Even ? "ACTIVO" : "INACTIVO");
    Print("  Trailing: ", Use_Trailing_Stop ? "ACTIVO" : "INACTIVO");
    Print("========================================");
    
    // DIAGNOSTIC: Crear handles con logging detallado
    Print("🔧 Creando indicadores...");
    
    g_handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    if(g_handle_EMA_Fast == INVALID_HANDLE)
    {
        Print("❌ ERROR: No se pudo crear EMA Fast (", EMA_Fast, ")");
        return(INIT_FAILED);
    }
    Print("✅ EMA Fast creado: handle=", g_handle_EMA_Fast);
    
    g_handle_EMA_Medium = iMA(_Symbol, PERIOD_M5, EMA_Medium, 0, MODE_EMA, PRICE_CLOSE);
    if(g_handle_EMA_Medium == INVALID_HANDLE)
    {
        Print("❌ ERROR: No se pudo crear EMA Medium (", EMA_Medium, ")");
        return(INIT_FAILED);
    }
    Print("✅ EMA Medium creado: handle=", g_handle_EMA_Medium);
    
    g_handle_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    if(g_handle_EMA_Slow == INVALID_HANDLE)
    {
        Print("❌ ERROR: No se pudo crear EMA Slow (", EMA_Slow, ")");
        return(INIT_FAILED);
    }
    Print("✅ EMA Slow creado: handle=", g_handle_EMA_Slow);
    
    g_handle_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
    if(g_handle_ATR == INVALID_HANDLE)
    {
        Print("❌ ERROR: No se pudo crear ATR (", ATR_Period, ")");
        return(INIT_FAILED);
    }
    Print("✅ ATR creado: handle=", g_handle_ATR);
    
    g_lastBarTime = 0;
    g_tradesExecuted = 0;
    g_tradesToday = 0;
    g_lastTradeDate = 0;
    g_checkEntryCallCount = 0;
    
    Print("========================================");
    Print("✅ INICIALIZACIÓN EXITOSA");
    Print("========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        
        // DIAGNOSTIC: Log cada nueva vela
        MqlDateTime dt;
        TimeToStruct(currentBarTime, dt);
        Print("📊 Nueva vela M5: ", TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES));
        
        // Resetear contador diario
        datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
        
        if(currentDate != g_lastTradeDate)
        {
            if(g_tradesToday > 0)
            {
                Print("📅 Nuevo día - Trades ayer: ", g_tradesToday);
            }
            g_tradesToday = 0;
            g_lastTradeDate = currentDate;
        }
        
        // DIAGNOSTIC: Log límite diario
        if(g_tradesToday >= Max_Trades_Per_Day)
        {
            Print("⛔ Límite diario alcanzado: ", g_tradesToday, "/", Max_Trades_Per_Day);
            return;
        }
        
        // DIAGNOSTIC: Log verificación de posición
        if(!PositionSelect(_Symbol))
        {
            Print("🔍 Sin posición abierta - Verificando entrada...");
            CheckForEntry();
        }
        else
        {
            Print("📍 Posición abierta - Saltando verificación de entrada");
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
void CheckForEntry()
{
    g_checkEntryCallCount++;
    Print("🔎 CheckForEntry() llamada #", g_checkEntryCallCount);
    
    // DIAGNOSTIC: Preparar arrays
    double ema_fast[], ema_medium[], ema_slow[], atr[], close[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_medium, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(close, true);
    
    // DIAGNOSTIC: Copiar buffers con logging
    Print("📥 Copiando buffers...");
    
    int copied_fast = CopyBuffer(g_handle_EMA_Fast, 0, 0, 5, ema_fast);
    if(copied_fast <= 0)
    {
        Print("❌ ERROR: CopyBuffer EMA Fast falló, retorno=", copied_fast);
        return;
    }
    Print("✅ EMA Fast copiado: ", copied_fast, " valores");
    
    int copied_medium = CopyBuffer(g_handle_EMA_Medium, 0, 0, 5, ema_medium);
    if(copied_medium <= 0)
    {
        Print("❌ ERROR: CopyBuffer EMA Medium falló, retorno=", copied_medium);
        return;
    }
    Print("✅ EMA Medium copiado: ", copied_medium, " valores");
    
    int copied_slow = CopyBuffer(g_handle_EMA_Slow, 0, 0, 5, ema_slow);
    if(copied_slow <= 0)
    {
        Print("❌ ERROR: CopyBuffer EMA Slow falló, retorno=", copied_slow);
        return;
    }
    Print("✅ EMA Slow copiado: ", copied_slow, " valores");
    
    int copied_atr = CopyBuffer(g_handle_ATR, 0, 0, 3, atr);
    if(copied_atr <= 0)
    {
        Print("❌ ERROR: CopyBuffer ATR falló, retorno=", copied_atr);
        return;
    }
    Print("✅ ATR copiado: ", copied_atr, " valores");
    
    int copied_close = CopyClose(_Symbol, PERIOD_M5, 0, 5, close);
    if(copied_close <= 0)
    {
        Print("❌ ERROR: CopyClose falló, retorno=", copied_close);
        return;
    }
    Print("✅ Close copiado: ", copied_close, " valores");
    
    double current_atr = atr[0];
    
    // DIAGNOSTIC: Log valores actuales
    Print("📊 VALORES ACTUALES:");
    Print("  Close[0]=", close[0], " Close[1]=", close[1]);
    Print("  EMA9[0]=", ema_fast[0], " EMA9[1]=", ema_fast[1]);
    Print("  EMA21[0]=", ema_medium[0]);
    Print("  EMA50[0]=", ema_slow[0]);
    Print("  ATR=", current_atr);
    
    // SEÑAL LONG
    Print("🔍 Verificando señal LONG...");
    bool long_crossover = (close[1] < ema_fast[1] && close[0] > ema_fast[0]);
    Print("  Crossover: close[1] < ema9[1] (", close[1] < ema_fast[1], ") AND close[0] > ema9[0] (", close[0] > ema_fast[0], ") = ", long_crossover);
    
    bool long_alignment = (ema_fast[0] > ema_medium[0] && ema_medium[0] > ema_slow[0]);
    Print("  Alignment: ema9 > ema21 (", ema_fast[0] > ema_medium[0], ") AND ema21 > ema50 (", ema_medium[0] > ema_slow[0], ") = ", long_alignment);
    
    bool long_signal = long_crossover && long_alignment;
    Print("  SEÑAL LONG FINAL: ", long_signal);
    
    // SEÑAL SHORT
    Print("🔍 Verificando señal SHORT...");
    bool short_crossover = (close[1] > ema_fast[1] && close[0] < ema_fast[0]);
    Print("  Crossover: close[1] > ema9[1] (", close[1] > ema_fast[1], ") AND close[0] < ema9[0] (", close[0] < ema_fast[0], ") = ", short_crossover);
    
    bool short_alignment = (ema_fast[0] < ema_medium[0] && ema_medium[0] < ema_slow[0]);
    Print("  Alignment: ema9 < ema21 (", ema_fast[0] < ema_medium[0], ") AND ema21 < ema50 (", ema_medium[0] < ema_slow[0], ") = ", short_alignment);
    
    bool short_signal = short_crossover && short_alignment;
    Print("  SEÑAL SHORT FINAL: ", short_signal);
    
    if(long_signal)
    {
        Print("📈 ¡SEÑAL LONG DETECTADA! Ejecutando trade...");
        ExecuteTrade(ORDER_TYPE_BUY, current_atr);
        g_tradesToday++;
    }
    else if(short_signal)
    {
        Print("📉 ¡SEÑAL SHORT DETECTADA! Ejecutando trade...");
        ExecuteTrade(ORDER_TYPE_SELL, current_atr);
        g_tradesToday++;
    }
    else
    {
        Print("⚪ Sin señal - Esperando...");
    }
}

//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, double atr_value)
{
    Print("💼 ExecuteTrade() iniciado - Tipo: ", orderType==ORDER_TYPE_BUY?"BUY":"SELL");
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    Print("  Precio: Ask=", ask, " Bid=", bid, " Usado=", price);
    
    double sl_distance = atr_value * SL_ATR_Multiplier;
    double tp_distance = atr_value * TP_ATR_Multiplier;
    
    Print("  Distancias: SL=", sl_distance, " (", SL_ATR_Multiplier, "×ATR) TP=", tp_distance, " (", TP_ATR_Multiplier, "×ATR)");
    
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
    
    Print("  SL=", sl, " TP=", tp);
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * Risk_Percent / 100.0;
    double sl_points = MathAbs(price - sl) / _Point;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (sl_points * tickValue);
    
    Print("  Balance=", balance, " Risk=", riskAmount, " (", Risk_Percent, "%)");
    Print("  SL Points=", sl_points, " Tick Value=", tickValue);
    Print("  Lot Size calculado=", lotSize);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    Print("  Lot Size ajustado=", lotSize, " (Min=", minLot, " Max=", maxLot, " Step=", lotStep, ")");
    
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
    request.comment = "V8.0-DIAG";
    request.type_filling = ORDER_FILLING_IOC;
    
    Print("📤 Enviando orden...");
    bool sent = OrderSend(request, result);
    
    Print("📨 OrderSend retorno: sent=", sent, " retcode=", result.retcode);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_tradesExecuted++;
        Print("✅ ¡TRADE EJECUTADO! #", g_tradesExecuted);
        Print("  Deal=", result.deal, " Order=", result.order);
    }
    else
    {
        Print("❌ TRADE FALLÓ");
        Print("  Retcode: ", result.retcode);
        Print("  Comment: ", result.comment);
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
            Print("🔄 Trailing Stop: Moviendo SL de ", posSL, " a ", newSL);
            ModifyPosition(posTicket, newSL, posTP);
        }
    }
    else
    {
        newSL = currentPrice + trailing_step;
        newSL = NormalizeDouble(newSL, _Digits);
        
        if((posSL == 0 || newSL < posSL) && newSL > currentPrice)
        {
            Print("🔄 Trailing Stop: Moviendo SL de ", posSL, " a ", newSL);
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
        Print("⚠️ Error modificando posición: retcode=", result.retcode);
    }
    else
    {
        Print("✅ Posición modificada exitosamente");
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
        Print("⚖️ Break-Even: Moviendo SL a ", newSL);
        ModifyPosition(posTicket, newSL, posTP);
    }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Fast);
    if(g_handle_EMA_Medium != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Medium);
    if(g_handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(g_handle_EMA_Slow);
    if(g_handle_ATR != INVALID_HANDLE) IndicatorRelease(g_handle_ATR);
    
    Print("========================================");
    Print("V8.0 DIAGNOSTIC FINALIZADO");
    Print("Total CheckForEntry() llamadas: ", g_checkEntryCallCount);
    Print("Total Trades Ejecutados: ", g_tradesExecuted);
    Print("Razón deinit: ", reason);
    Print("========================================");
}
//+------------------------------------------------------------------+
