//+------------------------------------------------------------------+
//|                  XAUUSD_V11_0_PROP_FIRM_MACHINE.mq5              |
//|          ARQUITECTURA PROFESIONAL PARA APROBAR FONDEOS           |
//|          Objetivo: Fase 1 (8-10%) → Fase 2 (5%) → Escalar        |
//+------------------------------------------------------------------+
#property copyright "V11.0 - Prop Firm Machine"
#property version   "11.00"
#property description "Sistema de 4 capas: Régimen → Entrada → Riesgo Dinámico → Gestión"
#property description "Prioridad: Supervivencia > Consistencia > Escalamiento"

//+------------------------------------------------------------------+
//| INPUTS - CONFIGURACIÓN PROFESIONAL                               |
//+------------------------------------------------------------------+
input group "=== IDENTIFICACIÓN ==="
input int Magic_Number = 111100;

input group "=== CAPA 1: DETECTOR DE RÉGIMEN (H1) ==="
input int Regime_EMA_Fast = 50;      // EMA rápida para régimen
input int Regime_EMA_Mid = 100;      // EMA media para régimen
input int Regime_EMA_Slow = 200;     // EMA lenta para régimen
input int Regime_ADX_Period = 14;    // ADX para fuerza de tendencia
input double Regime_ADX_Min = 22.0;  // ADX mínimo para operar
input int Regime_ATR_Period = 20;    // ATR para volatilidad

input group "=== CAPA 2: ENTRADA (M5 - Continuación) ==="
input int Entry_EMA_Fast = 15;       // EMA para pullback
input int Entry_EMA_Trend = 20;      // EMA de tendencia
input int Entry_EMA_Momentum = 10;   // EMA para momentum

input group "=== CAPA 3: GESTIÓN DE RIESGO DINÁMICA ==="
input double Risk_Base = 0.5;        // Riesgo base (%)
input double Risk_High_Equity = 0.75; // Riesgo en nuevo máximo (%)
input double Risk_DD_5 = 0.3;        // Riesgo si DD > 5% (%)
input double DD_Freeze = 7.0;        // DD para congelar trading (%)
input double DD_Max_Alert = 8.0;     // DD máximo permitido (%)

input group "=== CAPA 4: GESTIÓN DEL TRADE ==="
input double SL_Swing_Buffer = 0.2;  // Buffer adicional para SL (ATR)
input double TP_Min_RR = 2.5;        // Risk:Reward mínimo
input double BE_Trigger_RR = 1.5;    // RR para activar Break Even
input double Trail_Start_RR = 2.0;   // RR para activar Trailing
input bool Allow_Runners = true;     // Permitir runners en tendencia fuerte

input group "=== LÍMITES OPERACIONALES ==="
input int Max_Trades_Per_Day = 3;    // Máximo trades por día
input int Max_Consecutive_Losses = 3; // Máximo pérdidas consecutivas

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
// Handles de indicadores - Régimen (H1)
int h_regime_ema_fast, h_regime_ema_mid, h_regime_ema_slow;
int h_regime_adx, h_regime_atr;

// Handles de indicadores - Entrada (M5)
int h_entry_ema_fast, h_entry_ema_trend, h_entry_ema_momentum;
int h_entry_atr;

// Control de trading
datetime g_lastBarTime = 0;
datetime g_lastTradeDate = 0;
int g_tradesToday = 0;
int g_consecutiveLosses = 0;
double g_maxEquity = 0;
double g_initialBalance = 0;
bool g_tradingFrozen = false;

// Estadísticas
int g_totalTrades = 0;
int g_winningTrades = 0;
int g_losingTrades = 0;

//+------------------------------------------------------------------+
//| INICIALIZACIÓN                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("╔════════════════════════════════════════════════════════════╗");
    Print("║  XAUUSD V11.0 - PROP FIRM MACHINE                          ║");
    Print("║  Arquitectura: 4 Capas Profesionales                       ║");
    Print("║  Objetivo: Aprobar Fondeos + Escalar Capital               ║");
    Print("╚════════════════════════════════════════════════════════════╝");
    
    // Inicializar balance y equity
    g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_maxEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // CAPA 1: Indicadores de Régimen (H1)
    h_regime_ema_fast = iMA(_Symbol, PERIOD_H1, Regime_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_regime_ema_mid = iMA(_Symbol, PERIOD_H1, Regime_EMA_Mid, 0, MODE_EMA, PRICE_CLOSE);
    h_regime_ema_slow = iMA(_Symbol, PERIOD_H1, Regime_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h_regime_adx = iADX(_Symbol, PERIOD_H1, Regime_ADX_Period);
    h_regime_atr = iATR(_Symbol, PERIOD_H1, Regime_ATR_Period);
    
    // CAPA 2: Indicadores de Entrada (M5)
    h_entry_ema_fast = iMA(_Symbol, PERIOD_M5, Entry_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_entry_ema_trend = iMA(_Symbol, PERIOD_M5, Entry_EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
    h_entry_ema_momentum = iMA(_Symbol, PERIOD_M5, Entry_EMA_Momentum, 0, MODE_EMA, PRICE_CLOSE);
    h_entry_atr = iATR(_Symbol, PERIOD_M5, 14);
    
    // Validar handles
    if(h_regime_ema_fast == INVALID_HANDLE || h_regime_ema_mid == INVALID_HANDLE ||
       h_regime_ema_slow == INVALID_HANDLE || h_regime_adx == INVALID_HANDLE ||
       h_regime_atr == INVALID_HANDLE || h_entry_ema_fast == INVALID_HANDLE ||
       h_entry_ema_trend == INVALID_HANDLE || h_entry_ema_momentum == INVALID_HANDLE ||
       h_entry_atr == INVALID_HANDLE)
    {
        Print("ERROR: No se pudieron crear los indicadores");
        return(INIT_FAILED);
    }
    
    Print("✓ Sistema inicializado correctamente");
    Print("✓ Balance inicial: ", g_initialBalance);
    Print("✓ Riesgo base: ", Risk_Base, "%");
    Print("✓ DD máximo permitido: ", DD_Max_Alert, "%");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| ONTICK - LÓGICA PRINCIPAL                                         |
//+------------------------------------------------------------------+
void OnTick()
{
    // Actualizar equity máximo
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity > g_maxEquity)
        g_maxEquity = currentEquity;
    
    // Control de nueva barra M5
    datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
    if(currentBarTime == g_lastBarTime)
        return;
    
    g_lastBarTime = currentBarTime;
    
    // Reset contador diario
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
    
    if(currentDate != g_lastTradeDate)
    {
        g_tradesToday = 0;
        g_lastTradeDate = currentDate;
        g_tradingFrozen = false; // Reset freeze diario
        Print("═══ NUEVO DÍA DE TRADING ═══");
    }
    
    // CAPA 3: Verificar estado de riesgo
    CheckRiskStatus();
    
    // Gestión de posiciones abiertas
    if(PositionSelect(_Symbol))
    {
        ManageOpenPosition();
    }
    else
    {
        // Buscar nuevas entradas solo si no hay posición
        if(!g_tradingFrozen && g_tradesToday < Max_Trades_Per_Day && 
           g_consecutiveLosses < Max_Consecutive_Losses)
        {
            CheckForEntry();
        }
    }
}

//+------------------------------------------------------------------+
//| CAPA 3: VERIFICAR ESTADO DE RIESGO                               |
//+------------------------------------------------------------------+
void CheckRiskStatus()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double currentDD = ((g_initialBalance - currentEquity) / g_initialBalance) * 100.0;
    
    // Congelar trading si DD > 7%
    if(currentDD >= DD_Freeze)
    {
        if(!g_tradingFrozen)
        {
            g_tradingFrozen = true;
            Print("⚠️ TRADING CONGELADO - DD: ", DoubleToString(currentDD, 2), "%");
            Print("⚠️ Se reanudará mañana");
        }
        return;
    }
    
    // Alerta crítica si DD > 8%
    if(currentDD >= DD_Max_Alert)
    {
        Print("🚨 ALERTA CRÍTICA - DD: ", DoubleToString(currentDD, 2), "%");
        Print("🚨 CERRAR TODAS LAS POSICIONES MANUALMENTE");
    }
}

//+------------------------------------------------------------------+
//| CAPA 3: CALCULAR RIESGO DINÁMICO                                 |
//+------------------------------------------------------------------+
double GetDynamicRisk()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentDD = ((g_initialBalance - currentEquity) / g_initialBalance) * 100.0;
    
    // Si equity en nuevo máximo → aumentar riesgo
    if(currentEquity >= g_maxEquity * 0.999) // Tolerancia 0.1%
    {
        Print("✓ Equity en máximo → Riesgo: ", Risk_High_Equity, "%");
        return Risk_High_Equity;
    }
    
    // Si DD > 5% → reducir riesgo
    if(currentDD >= 5.0)
    {
        Print("⚠️ DD > 5% → Riesgo reducido: ", Risk_DD_5, "%");
        return Risk_DD_5;
    }
    
    // Riesgo base normal
    return Risk_Base;
}

//+------------------------------------------------------------------+
//| CAPA 1: DETECTOR DE RÉGIMEN (H1)                                 |
//+------------------------------------------------------------------+
bool IsMarketInTrendingRegime()
{
    double ema_fast[], ema_mid[], ema_slow[], adx_main[], atr_current[], atr_avg[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_mid, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(adx_main, true);
    ArraySetAsSeries(atr_current, true);
    ArraySetAsSeries(atr_avg, true);
    
    if(CopyBuffer(h_regime_ema_fast, 0, 0, 3, ema_fast) <= 0 ||
       CopyBuffer(h_regime_ema_mid, 0, 0, 3, ema_mid) <= 0 ||
       CopyBuffer(h_regime_ema_slow, 0, 0, 3, ema_slow) <= 0 ||
       CopyBuffer(h_regime_adx, 0, 0, 3, adx_main) <= 0 ||
       CopyBuffer(h_regime_atr, 0, 0, 1, atr_current) <= 0 ||
       CopyBuffer(h_regime_atr, 0, 0, 20, atr_avg) <= 0)
    {
        return false;
    }
    
    // 1. Verificar alineación de EMAs
    bool bullish_alignment = (ema_fast[0] > ema_mid[0] && ema_mid[0] > ema_slow[0]);
    bool bearish_alignment = (ema_fast[0] < ema_mid[0] && ema_mid[0] < ema_slow[0]);
    
    if(!bullish_alignment && !bearish_alignment)
    {
        Print("❌ Régimen: EMAs no alineadas - NO OPERAR");
        return false;
    }
    
    // 2. Verificar ADX (fuerza de tendencia)
    double current_adx = adx_main[0];
    if(current_adx < Regime_ADX_Min)
    {
        Print("❌ Régimen: ADX débil (", DoubleToString(current_adx, 1), ") - NO OPERAR");
        return false;
    }
    
    // 3. Verificar que no hay compresión entre EMAs
    double ema_spread_50_100 = MathAbs(ema_fast[0] - ema_mid[0]);
    double ema_spread_100_200 = MathAbs(ema_mid[0] - ema_slow[0]);
    double min_spread = atr_current[0] * 0.5; // Mínimo 0.5 ATR de separación
    
    if(ema_spread_50_100 < min_spread || ema_spread_100_200 < min_spread)
    {
        Print("❌ Régimen: EMAs comprimidas - NO OPERAR");
        return false;
    }
    
    // 4. Verificar volatilidad (ATR actual vs promedio)
    double atr_sum = 0;
    for(int i = 0; i < 20; i++)
        atr_sum += atr_avg[i];
    double atr_average = atr_sum / 20.0;
    
    if(atr_current[0] < atr_average * 0.8)
    {
        Print("❌ Régimen: Volatilidad baja - NO OPERAR");
        return false;
    }
    
    // ✅ RÉGIMEN VÁLIDO
    string regime_type = bullish_alignment ? "ALCISTA" : "BAJISTA";
    Print("✅ Régimen ", regime_type, " confirmado - ADX: ", DoubleToString(current_adx, 1));
    
    return true;
}

//+------------------------------------------------------------------+
//| CAPA 2: BUSCAR ENTRADA (Continuación Estructural)                |
//+------------------------------------------------------------------+
void CheckForEntry()
{
    // Primero verificar régimen en H1
    if(!IsMarketInTrendingRegime())
        return;
    
    // Obtener datos de entrada M5
    double ema_fast[], ema_trend[], ema_momentum[], close[], high[], low[], atr[];
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_trend, true);
    ArraySetAsSeries(ema_momentum, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(atr, true);
    
    if(CopyBuffer(h_entry_ema_fast, 0, 0, 5, ema_fast) <= 0 ||
       CopyBuffer(h_entry_ema_trend, 0, 0, 5, ema_trend) <= 0 ||
       CopyBuffer(h_entry_ema_momentum, 0, 0, 5, ema_momentum) <= 0 ||
       CopyClose(_Symbol, PERIOD_M5, 0, 5, close) <= 0 ||
       CopyHigh(_Symbol, PERIOD_M5, 0, 5, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 5, low) <= 0 ||
       CopyBuffer(h_entry_atr, 0, 0, 3, atr) <= 0)
    {
        return;
    }
    
    double current_atr = atr[0];
    
    // Determinar dirección de tendencia H1
    double regime_ema_fast[], regime_ema_slow[];
    ArraySetAsSeries(regime_ema_fast, true);
    ArraySetAsSeries(regime_ema_slow, true);
    
    if(CopyBuffer(h_regime_ema_fast, 0, 0, 1, regime_ema_fast) <= 0 ||
       CopyBuffer(h_regime_ema_slow, 0, 0, 1, regime_ema_slow) <= 0)
        return;
    
    bool h1_bullish = regime_ema_fast[0] > regime_ema_slow[0];
    bool h1_bearish = regime_ema_fast[0] < regime_ema_slow[0];
    
    // LONG: Pullback a zona EMA15-20 + Confirmación
    if(h1_bullish)
    {
        // 1. Pullback: precio tocó zona EMA15-20
        bool pullback = (low[1] <= ema_fast[1] || low[1] <= ema_trend[1]);
        
        // 2. Confirmación: cierre fuerte por encima
        bool strong_close = (close[0] > ema_fast[0] && close[0] > close[1]);
        
        // 3. Momentum creciente: EMA10 acelerando
        bool momentum_up = (ema_momentum[0] > ema_momentum[1] && 
                           ema_momentum[1] > ema_momentum[2]);
        
        // 4. Estructura intacta: EMA15 > EMA20
        bool structure_intact = (ema_fast[0] > ema_trend[0]);
        
        if(pullback && strong_close && momentum_up && structure_intact)
        {
            Print("🔵 SEÑAL LONG - Continuación estructural confirmada");
            ExecuteTrade(ORDER_TYPE_BUY, current_atr);
            return;
        }
    }
    
    // SHORT: Pullback a zona EMA15-20 + Confirmación
    if(h1_bearish)
    {
        // 1. Pullback: precio tocó zona EMA15-20
        bool pullback = (high[1] >= ema_fast[1] || high[1] >= ema_trend[1]);
        
        // 2. Confirmación: cierre fuerte por debajo
        bool strong_close = (close[0] < ema_fast[0] && close[0] < close[1]);
        
        // 3. Momentum creciente: EMA10 acelerando
        bool momentum_down = (ema_momentum[0] < ema_momentum[1] && 
                             ema_momentum[1] < ema_momentum[2]);
        
        // 4. Estructura intacta: EMA15 < EMA20
        bool structure_intact = (ema_fast[0] < ema_trend[0]);
        
        if(pullback && strong_close && momentum_down && structure_intact)
        {
            Print("🔴 SEÑAL SHORT - Continuación estructural confirmada");
            ExecuteTrade(ORDER_TYPE_SELL, current_atr);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| CAPA 4: EJECUTAR TRADE (SL Estructural + TP 2.5R)                |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, double atr_value)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;
    
    // SL ESTRUCTURAL: Buscar swing anterior
    double sl = CalculateStructuralSL(orderType, atr_value);
    if(sl == 0)
    {
        Print("❌ No se pudo calcular SL estructural");
        return;
    }
    
    // TP: Mínimo 2.5R
    double sl_distance = MathAbs(price - sl);
    double tp_distance = sl_distance * TP_Min_RR;
    double tp = (orderType == ORDER_TYPE_BUY) ? price + tp_distance : price - tp_distance;
    
    sl = NormalizeDouble(sl, _Digits);
    tp = NormalizeDouble(tp, _Digits);
    
    // CAPA 3: Calcular riesgo dinámico
    double risk_percent = GetDynamicRisk();
    
    // Calcular lotaje
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * risk_percent / 100.0;
    double sl_points = MathAbs(price - sl) / _Point;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskAmount / (sl_points * tickValue);
    
    // Normalizar lotaje
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Enviar orden
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
    request.comment = "V11.0_PropFirm";
    request.type_filling = ORDER_FILLING_IOC;
    
    bool sent = OrderSend(request, result);
    
    if(sent && result.retcode == TRADE_RETCODE_DONE)
    {
        g_totalTrades++;
        g_tradesToday++;
        
        double rr_ratio = tp_distance / sl_distance;
        Print("✅ TRADE EJECUTADO #", g_totalTrades);
        Print("   Tipo: ", (orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT"));
        Print("   Lote: ", lotSize);
        Print("   Riesgo: ", risk_percent, "%");
        Print("   RR: 1:", DoubleToString(rr_ratio, 2));
        Print("   SL: ", sl, " | TP: ", tp);
    }
    else
    {
        Print("❌ Error al enviar orden: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| CALCULAR SL ESTRUCTURAL (Swing anterior + buffer)                |
//+------------------------------------------------------------------+
double CalculateStructuralSL(ENUM_ORDER_TYPE orderType, double atr_value)
{
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    // Buscar en últimas 20 velas M5
    if(CopyHigh(_Symbol, PERIOD_M5, 0, 20, high) <= 0 ||
       CopyLow(_Symbol, PERIOD_M5, 0, 20, low) <= 0)
        return 0;
    
    double swing_level = 0;
    double buffer = atr_value * SL_Swing_Buffer;
    
    if(orderType == ORDER_TYPE_BUY)
    {
        // Buscar swing low más reciente
        swing_level = low[1];
        for(int i = 2; i < 20; i++)
        {
            if(low[i] < swing_level)
                swing_level = low[i];
        }
        return swing_level - buffer;
    }
    else
    {
        // Buscar swing high más reciente
        swing_level = high[1];
        for(int i = 2; i < 20; i++)
        {
            if(high[i] > swing_level)
                swing_level = high[i];
        }
        return swing_level + buffer;
    }
}

//+------------------------------------------------------------------+
//| CAPA 4: GESTIÓN DE POSICIÓN ABIERTA                              |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    long posType = PositionGetInteger(POSITION_TYPE);
    double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double posSL = PositionGetDouble(POSITION_SL);
    double posTP = PositionGetDouble(POSITION_TP);
    ulong posTicket = PositionGetInteger(POSITION_TICKET);
    
    double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double profit_distance = (posType == POSITION_TYPE_BUY) ? 
                             (currentPrice - posOpenPrice) : 
                             (posOpenPrice - currentPrice);
    
    double sl_distance = MathAbs(posOpenPrice - posSL);
    double current_rr = (sl_distance > 0) ? (profit_distance / sl_distance) : 0;
    
    // 1. Break Even a 1.5R
    if(current_rr >= BE_Trigger_RR && posSL != posOpenPrice)
    {
        double newSL = posOpenPrice;
        ModifyPosition(posTicket, newSL, posTP, "Break Even");
        return;
    }
    
    // 2. Trailing Stop a partir de 2R
    if(current_rr >= Trail_Start_RR)
    {
        ApplyTrailingStop(posTicket, posType, posOpenPrice, posSL, posTP, currentPrice, sl_distance);
    }
}

//+------------------------------------------------------------------+
//| TRAILING STOP ESTRUCTURAL                                        |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, long posType, double openPrice, double currentSL, 
                       double currentTP, double currentPrice, double original_sl_distance)
{
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_entry_atr, 0, 0, 1, atr) <= 0)
        return;
    
    double trail_distance = atr[0] * 1.0; // 1 ATR de trailing
    
    double newSL = (posType == POSITION_TYPE_BUY) ? 
                   currentPrice - trail_distance : 
                   currentPrice + trail_distance;
    
    newSL = NormalizeDouble(newSL, _Digits);
    
    // Solo mover SL si mejora la posición
    bool should_modify = false;
    
    if(posType == POSITION_TYPE_BUY)
    {
        if(newSL > currentSL && newSL < currentPrice)
            should_modify = true;
    }
    else
    {
        if((currentSL == 0 || newSL < currentSL) && newSL > currentPrice)
            should_modify = true;
    }
    
    if(should_modify)
    {
        ModifyPosition(ticket, newSL, currentTP, "Trailing Stop");
    }
}

//+------------------------------------------------------------------+
//| MODIFICAR POSICIÓN                                                |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double newSL, double newTP, string reason)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = newSL;
    request.tp = newTP;
    
    if(OrderSend(request, result))
    {
        Print("✓ ", reason, " aplicado - Nuevo SL: ", newSL);
    }
    else
    {
        Print("❌ Error al modificar posición (", reason, "): ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| EVENTO: TRADE EJECUTADO                                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Detectar cierre de posición
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(HistoryDealSelect(trans.deal))
        {
            long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            
            if(dealEntry == DEAL_ENTRY_OUT) // Posición cerrada
            {
                double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                
                if(profit > 0)
                {
                    g_winningTrades++;
                    g_consecutiveLosses = 0;
                    Print("✅ TRADE GANADOR - Profit: ", DoubleToString(profit, 2));
                }
                else if(profit < 0)
                {
                    g_losingTrades++;
                    g_consecutiveLosses++;
                    Print("❌ TRADE PERDEDOR - Loss: ", DoubleToString(profit, 2));
                    
                    if(g_consecutiveLosses >= Max_Consecutive_Losses)
                    {
                        Print("⚠️ ", Max_Consecutive_Losses, " pérdidas consecutivas - Pausar trading");
                    }
                }
                
                // Actualizar estadísticas
                PrintStatistics();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| IMPRIMIR ESTADÍSTICAS                                            |
//+------------------------------------------------------------------+
void PrintStatistics()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double totalProfit = currentBalance - g_initialBalance;
    double profitPercent = (totalProfit / g_initialBalance) * 100.0;
    double currentDD = ((g_initialBalance - currentEquity) / g_initialBalance) * 100.0;
    
    int totalClosed = g_winningTrades + g_losingTrades;
    double winRate = (totalClosed > 0) ? ((double)g_winningTrades / totalClosed * 100.0) : 0;
    
    Print("═══════════════════════════════════════════════════════");
    Print("📊 ESTADÍSTICAS DEL SISTEMA");
    Print("═══════════════════════════════════════════════════════");
    Print("Balance inicial: ", DoubleToString(g_initialBalance, 2));
    Print("Balance actual: ", DoubleToString(currentBalance, 2));
    Print("Equity actual: ", DoubleToString(currentEquity, 2));
    Print("Profit total: ", DoubleToString(totalProfit, 2), " (", DoubleToString(profitPercent, 2), "%)");
    Print("Drawdown actual: ", DoubleToString(currentDD, 2), "%");
    Print("───────────────────────────────────────────────────────");
    Print("Trades totales: ", g_totalTrades);
    Print("Trades ganadores: ", g_winningTrades);
    Print("Trades perdedores: ", g_losingTrades);
    Print("Win Rate: ", DoubleToString(winRate, 1), "%");
    Print("Pérdidas consecutivas: ", g_consecutiveLosses);
    Print("═══════════════════════════════════════════════════════");
    
    // Alertas de progreso
    if(profitPercent >= 8.0 && profitPercent < 10.0)
        Print("🎯 CERCA DE COMPLETAR FASE 1 (8-10%)");
    else if(profitPercent >= 10.0)
        Print("🎉 FASE 1 COMPLETADA - Profit: ", DoubleToString(profitPercent, 2), "%");
}

//+------------------------------------------------------------------+
//| DEINICIALIZACIÓN                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Liberar indicadores
    if(h_regime_ema_fast != INVALID_HANDLE) IndicatorRelease(h_regime_ema_fast);
    if(h_regime_ema_mid != INVALID_HANDLE) IndicatorRelease(h_regime_ema_mid);
    if(h_regime_ema_slow != INVALID_HANDLE) IndicatorRelease(h_regime_ema_slow);
    if(h_regime_adx != INVALID_HANDLE) IndicatorRelease(h_regime_adx);
    if(h_regime_atr != INVALID_HANDLE) IndicatorRelease(h_regime_atr);
    if(h_entry_ema_fast != INVALID_HANDLE) IndicatorRelease(h_entry_ema_fast);
    if(h_entry_ema_trend != INVALID_HANDLE) IndicatorRelease(h_entry_ema_trend);
    if(h_entry_ema_momentum != INVALID_HANDLE) IndicatorRelease(h_entry_ema_momentum);
    if(h_entry_atr != INVALID_HANDLE) IndicatorRelease(h_entry_atr);
    
    Print("═══════════════════════════════════════════════════════");
    Print("🏁 SISTEMA DETENIDO");
    PrintStatistics();
    Print("═══════════════════════════════════════════════════════");
}
//+------------------------------------------------------------------+
