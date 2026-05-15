//+------------------------------------------------------------------+
//|                            SKOLL_FVG_v4.0_ULTIMATE.mq5          |
//|                    VERSIÓN FINAL OPERATIVA - CORRIGE FALLOS     |
//|                    Optimizado para operar EN SERIO              |
//+------------------------------------------------------------------+
#property copyright "SKOLL v4.0 ULTIMATE"
#property version   "4.00"
#property strict

//--- Parámetros de entrada
input group "===== CONFIGURACIÓN TEMPORAL ====="
input int InpStartHour = 5;      // Hora de inicio (VET)
input int InpEndHour = 13;       // Hora de fin (VET)

input group "===== FILTROS PRINCIPALES ====="
input bool InpUseTrendFilter = true;   // Usar filtro de tendencia H4
input int InpEMA_H4 = 50;              // EMA H4 para tendencia
input bool InpUseATRFilter = false;     // Filtro de volatilidad (DESACTIVADO por defecto)
input double InpMinATR_XAUUSD = 5.0;   // ATR mínimo XAUUSD ($5)

input group "===== PARÁMETROS FVG (RELAJADOS) ====="
input double InpFVG_Tolerance_EURUSD = 0.00003;  // Tolerancia FVG EURUSD (3 pips)
input double InpFVG_Tolerance_XAUUSD = 0.5;      // Tolerancia FVG XAUUSD ($0.50)

input group "===== ORDER BLOCK (SIMPLIFICADO) ====="
input double InpOB_BodyRatio = 0.60;    // Mínimo cuerpo relativo (60% - RELAJADO)
input double InpOB_Overlap = 0.30;      // Mínimo overlap FVG-OB (30% - RELAJADO)

input group "===== CHOCH (SIMPLIFICADO) ====="
input double InpCHOCH_Tolerance_EURUSD = 0.00002;  // Tolerancia CHOCH EURUSD (2 pips)
input double InpCHOCH_Tolerance_XAUUSD = 0.3;      // Tolerancia CHOCH XAUUSD ($0.30)
input int InpEMA_M5 = 20;                          // EMA M5 para CHOCH

input group "===== GESTIÓN DE RIESGO ====="
input double InpRiskPercent = 1.0;     // Riesgo por operación (%)
input double InpTP1_Ratio = 1.0;       // Take Profit 1 (1R)
input double InpTP2_Ratio = 2.0;       // Take Profit 2 (2R)
input bool InpMoveToBreakeven = true;  // Mover a BE al alcanzar TP1

input group "===== CONTROL OPERATIVO ====="
input bool InpEnableTrading = true;    // Habilitar trading
input bool InpShowVisuals = true;      // Mostrar gráficos
input int InpMagicNumber = 20250130;   // Número mágico
input string InpTradeComment = "SKOLL";

//--- Estructuras
struct Position_Info {
    ulong ticket_tp1;
    ulong ticket_tp2;
    double entry_price;
    double sl;
    double tp1;
    double tp2;
    bool tp1_hit;
    bool moved_to_be;
};

//--- Variables globales
int g_EMA_H4_Handle;
int g_ATR_H4_Handle;
int g_EMA_M5_Handle;

double g_EMA_H4_Buffer[];
double g_ATR_H4_Buffer[];
double g_EMA_M5_Buffer[];

Position_Info g_Position;
datetime g_LastBarTime_H1 = 0;

int g_SignalCounter = 0;
int g_TradesOpened = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════════════════════════");
    Print("         SKOLL-FVG v4.0 ULTIMATE - INICIALIZANDO         ");
    Print("         VERSIÓN OPERATIVA - CORRIGE TODOS LOS FALLOS    ");
    Print("═══════════════════════════════════════════════════════════");
    
    //--- Crear indicadores
    g_EMA_H4_Handle = iMA(_Symbol, PERIOD_H4, InpEMA_H4, 0, MODE_EMA, PRICE_CLOSE);
    g_ATR_H4_Handle = iATR(_Symbol, PERIOD_H4, 14);
    g_EMA_M5_Handle = iMA(_Symbol, PERIOD_M5, InpEMA_M5, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_EMA_H4_Handle == INVALID_HANDLE || g_ATR_H4_Handle == INVALID_HANDLE ||
       g_EMA_M5_Handle == INVALID_HANDLE) {
        Print("❌ Error creando indicadores");
        return INIT_FAILED;
    }
    
    ArraySetAsSeries(g_EMA_H4_Buffer, true);
    ArraySetAsSeries(g_ATR_H4_Buffer, true);
    ArraySetAsSeries(g_EMA_M5_Buffer, true);
    
    ResetPosition(g_Position);
    
    Print("✅ CONFIGURACIÓN:");
    Print("   Horario: ", InpStartHour, ":00 - ", InpEndHour, ":00 VET");
    Print("   Filtro tendencia: ", InpUseTrendFilter ? "ON" : "OFF");
    Print("   Filtro ATR: ", InpUseATRFilter ? "ON" : "OFF");
    Print("   Riesgo: ", InpRiskPercent, "%");
    Print("   RR: 1:", InpTP2_Ratio);
    Print("   Trading: ", InpEnableTrading ? "HABILITADO" : "DESHABILITADO");
    Print("═══════════════════════════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_EMA_H4_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_H4_Handle);
    if(g_ATR_H4_Handle != INVALID_HANDLE) IndicatorRelease(g_ATR_H4_Handle);
    if(g_EMA_M5_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_M5_Handle);
    
    Print("═══════════════════════════════════════════════════════════");
    Print("         SKOLL-FVG v4.0 - DETENIDO                        ");
    Print("         Trades ejecutados: ", g_TradesOpened);
    Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Gestionar posición activa
    if(g_Position.ticket_tp1 > 0 || g_Position.ticket_tp2 > 0) {
        ManagePosition();
        return;
    }
    
    //--- Solo buscar señal en nueva barra H1
    datetime current_bar = iTime(_Symbol, PERIOD_H1, 0);
    if(current_bar == g_LastBarTime_H1)
        return;
    
    g_LastBarTime_H1 = current_bar;
    
    //--- Verificar condiciones básicas
    if(!InpEnableTrading)
        return;
    
    if(!IsValidTradingTime())
        return;
    
    //--- Buscar señal
    CheckForEntrySignal();
}

//+------------------------------------------------------------------+
//| Verificar horario válido                                        |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int hour_utc = dt.hour;
    int hour_vet = hour_utc - 4;
    if(hour_vet < 0) hour_vet += 24;
    
    // Horario VET
    bool valid_vet = (hour_vet >= InpStartHour && hour_vet < InpEndHour);
    
    // Horario UTC (para backtest)
    int start_utc = InpStartHour + 4;
    int end_utc = InpEndHour + 4;
    bool valid_utc = (hour_utc >= start_utc && hour_utc < end_utc);
    
    return valid_vet || valid_utc;
}

//+------------------------------------------------------------------+
//| Buscar señal de entrada (SIMPLIFICADA Y OPERATIVA)              |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("🔍 ESCANEO - ", TimeToString(TimeCurrent()));
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    //--- PASO 1: Filtro de tendencia H4 (OPCIONAL)
    int trend_direction = 0;
    if(InpUseTrendFilter) {
        trend_direction = CheckTrendH4();
        if(trend_direction == 0) {
            Print("❌ Tendencia H4: Neutral/Rango");
            return;
        }
        Print("✅ Tendencia H4: ", trend_direction > 0 ? "ALCISTA" : "BAJISTA");
    } else {
        Print("⚠️ Filtro H4: DESACTIVADO - Se permiten ambas direcciones");
    }
    
    //--- PASO 2: Filtro de volatilidad (OPCIONAL)
    if(InpUseATRFilter) {
        if(!CheckVolatility()) {
            Print("❌ Volatilidad: Insuficiente");
            return;
        }
        Print("✅ Volatilidad: OK");
    }
    
    //--- PASO 3: Detectar FVG en H1
    bool fvg_found = false;
    bool fvg_bullish = false;
    double fvg_upper = 0, fvg_lower = 0;
    
    if(DetectFVG(fvg_bullish, fvg_upper, fvg_lower)) {
        // Verificar si precio cerró en FVG
        double close_h1 = iClose(_Symbol, PERIOD_H1, 0);
        
        if(close_h1 >= fvg_lower && close_h1 <= fvg_upper) {
            fvg_found = true;
            Print("✅ FVG ", fvg_bullish ? "ALCISTA" : "BAJISTA", " detectado");
            Print("   Rango: ", fvg_lower, " - ", fvg_upper);
            Print("   Cierre H1: ", close_h1);
        }
    }
    
    if(!fvg_found) {
        Print("❌ FVG: No detectado o precio no cerró dentro");
        return;
    }
    
    //--- Validar con tendencia si está activo
    if(InpUseTrendFilter) {
        if((fvg_bullish && trend_direction < 0) || (!fvg_bullish && trend_direction > 0)) {
            Print("❌ FVG contrario a tendencia H4");
            return;
        }
    }
    
    //--- PASO 4: Detectar Order Block en M5 (SIMPLIFICADO)
    bool ob_found = false;
    double ob_upper = 0, ob_lower = 0;
    
    if(DetectOrderBlock(fvg_bullish, ob_upper, ob_lower)) {
        // Verificar overlap con FVG
        double overlap = CalculateOverlap(fvg_upper, fvg_lower, ob_upper, ob_lower);
        double fvg_size = fvg_upper - fvg_lower;
        
        if(fvg_size > 0 && overlap / fvg_size >= InpOB_Overlap) {
            ob_found = true;
            Print("✅ Order Block encontrado");
            Print("   Rango: ", ob_lower, " - ", ob_upper);
            Print("   Overlap: ", NormalizeDouble(overlap/fvg_size*100, 1), "%");
        } else {
            Print("❌ Overlap insuficiente: ", NormalizeDouble(overlap/fvg_size*100, 1), "%");
            return;
        }
    } else {
        Print("❌ Order Block: No encontrado");
        return;
    }
    
    //--- PASO 5: Confirmar CHOCH en M5 (SIMPLIFICADO - usa M5 en vez de M3)
    if(!DetectCHOCH_Simple(fvg_bullish)) {
        Print("❌ CHOCH: No confirmado");
        return;
    }
    Print("✅ CHOCH: Confirmado");
    
    //--- TODAS LAS CONDICIONES CUMPLIDAS
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("🎯 SEÑAL VÁLIDA - ABRIENDO POSICIÓN");
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    if(InpEnableTrading) {
        OpenPosition(fvg_bullish, ob_upper, ob_lower);
    }
}

//+------------------------------------------------------------------+
//| Verificar tendencia H4                                          |
//+------------------------------------------------------------------+
int CheckTrendH4()
{
    if(CopyBuffer(g_EMA_H4_Handle, 0, 0, 1, g_EMA_H4_Buffer) != 1)
        return 0;
    
    double close_h4 = iClose(_Symbol, PERIOD_H4, 0);
    double ema50 = g_EMA_H4_Buffer[0];
    
    Print("   Precio H4: ", close_h4);
    Print("   EMA50 H4: ", ema50);
    
    double diff = MathAbs(close_h4 - ema50);
    double threshold = close_h4 * 0.001; // 0.1% mínimo de separación
    
    if(diff < threshold) {
        Print("   Diferencia muy pequeña - NEUTRAL");
        return 0;
    }
    
    if(close_h4 > ema50)
        return 1; // Alcista
    else
        return -1; // Bajista
}

//+------------------------------------------------------------------+
//| Verificar volatilidad                                           |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
    if(CopyBuffer(g_ATR_H4_Handle, 0, 0, 1, g_ATR_H4_Buffer) != 1)
        return true; // Si falla, permitir trade
    
    double atr_h4 = g_ATR_H4_Buffer[0];
    double min_atr = GetMinATR();
    
    Print("   ATR H4: ", atr_h4);
    Print("   ATR mín: ", min_atr);
    
    return atr_h4 >= min_atr;
}

//+------------------------------------------------------------------+
//| Detectar FVG en H1                                              |
//+------------------------------------------------------------------+
bool DetectFVG(bool &is_bullish, double &upper, double &lower)
{
    if(iBars(_Symbol, PERIOD_H1) < 3)
        return false;
    
    double tolerance = GetFVGTolerance();
    
    double high[], low_arr[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low_arr, true);
    
    if(CopyHigh(_Symbol, PERIOD_H1, 1, 3, high) != 3) return false;
    if(CopyLow(_Symbol, PERIOD_H1, 1, 3, low_arr) != 3) return false;
    
    // FVG Alcista: low[0] > high[2] + tolerance
    if(low_arr[0] > high[2] + tolerance) {
        is_bullish = true;
        upper = low_arr[0];
        lower = high[2];
        return true;
    }
    // FVG Bajista: high[0] < low[2] - tolerance
    else if(high[0] < low_arr[2] - tolerance) {
        is_bullish = false;
        upper = high[2];
        lower = low_arr[2];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detectar Order Block en M5 (SIMPLIFICADO)                      |
//+------------------------------------------------------------------+
bool DetectOrderBlock(bool look_for_bullish, double &upper, double &lower)
{
    int lookback = 30; // Reducido para más señales
    
    double open[], high[], low_arr[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low_arr, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, PERIOD_M5, 0, lookback, open) != lookback) return false;
    if(CopyHigh(_Symbol, PERIOD_M5, 0, lookback, high) != lookback) return false;
    if(CopyLow(_Symbol, PERIOD_M5, 0, lookback, low_arr) != lookback) return false;
    if(CopyClose(_Symbol, PERIOD_M5, 0, lookback, close) != lookback) return false;
    
    for(int i = lookback - 3; i >= 2; i--) {
        double range = high[i] - low_arr[i];
        if(range <= 0) continue;
        
        if(look_for_bullish) {
            // Vela alcista con cuerpo >= 60%
            if(close[i] > open[i]) {
                double body = close[i] - open[i];
                
                if(body / range >= InpOB_BodyRatio) {
                    // Confirmación: al menos 1 vela cierra por encima
                    if(close[i-1] > high[i] || close[i-2] > high[i]) {
                        upper = high[i];
                        lower = low_arr[i];
                        return true;
                    }
                }
            }
        } else {
            // Vela bajista con cuerpo >= 60%
            if(close[i] < open[i]) {
                double body = open[i] - close[i];
                
                if(body / range >= InpOB_BodyRatio) {
                    // Confirmación: al menos 1 vela cierra por debajo
                    if(close[i-1] < low_arr[i] || close[i-2] < low_arr[i]) {
                        upper = high[i];
                        lower = low_arr[i];
                        return true;
                    }
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detectar CHOCH simplificado en M5                               |
//+------------------------------------------------------------------+
bool DetectCHOCH_Simple(bool look_for_bullish)
{
    double tolerance = GetCHOCHTolerance();
    
    // Usar M5 en vez de M3 para reducir ruido
    double high[], low_arr[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low_arr, true);
    ArraySetAsSeries(close, true);
    
    int bars = 30;
    if(CopyHigh(_Symbol, PERIOD_M5, 0, bars, high) != bars) return false;
    if(CopyLow(_Symbol, PERIOD_M5, 0, bars, low_arr) != bars) return false;
    if(CopyClose(_Symbol, PERIOD_M5, 0, bars, close) != bars) return false;
    if(CopyBuffer(g_EMA_M5_Handle, 0, 0, bars, g_EMA_M5_Buffer) != bars) return false;
    
    double current_close = close[0];
    double current_ema = g_EMA_M5_Buffer[0];
    
    if(look_for_bullish) {
        // Buscar último swing high
        double last_swing = 0;
        
        for(int i = 1; i < bars - 1; i++) {
            if(high[i] > high[i-1] && high[i] > high[i+1]) {
                last_swing = high[i];
                Print("   Swing High M5: ", last_swing);
                break;
            }
        }
        
        if(last_swing == 0)
            return false;
        
        if(current_close > last_swing + tolerance && current_close > current_ema) {
            Print("   Cierre M5: ", current_close);
            Print("   EMA20 M5: ", current_ema);
            return true;
        }
        
    } else {
        // Buscar último swing low
        double last_swing = 999999;
        
        for(int i = 1; i < bars - 1; i++) {
            if(low_arr[i] < low_arr[i-1] && low_arr[i] < low_arr[i+1]) {
                last_swing = low_arr[i];
                Print("   Swing Low M5: ", last_swing);
                break;
            }
        }
        
        if(last_swing == 999999)
            return false;
        
        if(current_close < last_swing - tolerance && current_close < current_ema) {
            Print("   Cierre M5: ", current_close);
            Print("   EMA20 M5: ", current_ema);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calcular overlap                                                 |
//+------------------------------------------------------------------+
double CalculateOverlap(double fvg_up, double fvg_low, double ob_up, double ob_low)
{
    double overlap_low = MathMax(fvg_low, ob_low);
    double overlap_high = MathMin(fvg_up, ob_up);
    
    if(overlap_high > overlap_low)
        return overlap_high - overlap_low;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Abrir posición                                                   |
//+------------------------------------------------------------------+
void OpenPosition(bool is_buy, double ob_upper, double ob_lower)
{
    double price = SymbolInfoDouble(_Symbol, is_buy ? SYMBOL_ASK : SYMBOL_BID);
    
    // SL basado en OB
    double sl = is_buy ? ob_lower - GetFVGTolerance() : ob_upper + GetFVGTolerance();
    double risk = MathAbs(price - sl);
    
    // TPs
    double tp1 = is_buy ? price + risk * InpTP1_Ratio : price - risk * InpTP1_Ratio;
    double tp2 = is_buy ? price + risk * InpTP2_Ratio : price - risk * InpTP2_Ratio;
    
    // Calcular volumen
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_money = balance * InpRiskPercent / 100.0;
    
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double risk_points = risk / point;
    double volume = risk_money / (risk_points * tick_value);
    
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    volume = MathFloor(volume / lot_step) * lot_step;
    volume = MathMax(min_lot, MathMin(max_lot, volume));
    
    // Normalizar
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    price = NormalizeDouble(price, digits);
    sl = NormalizeDouble(sl, digits);
    tp1 = NormalizeDouble(tp1, digits);
    tp2 = NormalizeDouble(tp2, digits);
    
    // Abrir órdenes
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = volume / 2.0;
    request.type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = price;
    request.sl = sl;
    request.tp = tp2;
    request.deviation = 20;
    request.magic = InpMagicNumber;
    request.comment = InpTradeComment + "_TP2";
    request.type_filling = ORDER_FILLING_FOK;
    
    if(!OrderSend(request, result)) {
        Print("❌ Error TP2: ", GetLastError());
        // Intentar con ORDER_FILLING_IOC
        request.type_filling = ORDER_FILLING_IOC;
        if(!OrderSend(request, result)) {
            Print("❌ Error TP2 (IOC): ", GetLastError());
            return;
        }
    }
    
    g_Position.ticket_tp2 = result.order;
    Print("✅ TP2 abierto: #", result.order);
    
    request.volume = volume / 2.0;
    request.tp = tp1;
    request.comment = InpTradeComment + "_TP1";
    
    if(!OrderSend(request, result)) {
        Print("❌ Error TP1: ", GetLastError());
        return;
    }
    
    g_Position.ticket_tp1 = result.order;
    g_Position.entry_price = price;
    g_Position.sl = sl;
    g_Position.tp1 = tp1;
    g_Position.tp2 = tp2;
    g_Position.tp1_hit = false;
    g_Position.moved_to_be = false;
    
    g_TradesOpened++;
    
    Print("══════════════════════════════════════════════════════════");
    Print("🚀 POSICIÓN ", g_TradesOpened, " - ", is_buy ? "COMPRA" : "VENTA");
    Print("══════════════════════════════════════════════════════════");
    Print("📍 Entrada: ", price);
    Print("🛑 SL: ", sl);
    Print("🎯 TP1 (1R): ", tp1);
    Print("🎯 TP2 (2R): ", tp2);
    Print("💰 Volumen: ", volume);
    Print("💵 Riesgo: $", NormalizeDouble(risk_money, 2));
    Print("══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Gestionar posición                                              |
//+------------------------------------------------------------------+
void ManagePosition()
{
    // TP1 alcanzado
    if(!g_Position.tp1_hit && g_Position.ticket_tp1 > 0) {
        if(!PositionSelectByTicket(g_Position.ticket_tp1)) {
            g_Position.tp1_hit = true;
            Print("✅ TP1 ALCANZADO - 1R asegurado");
            
            // Breakeven
            if(InpMoveToBreakeven && !g_Position.moved_to_be && g_Position.ticket_tp2 > 0) {
                if(PositionSelectByTicket(g_Position.ticket_tp2)) {
                    MqlTradeRequest request = {};
                    MqlTradeResult result = {};
                    
                    request.action = TRADE_ACTION_SLTP;
                    request.position = g_Position.ticket_tp2;
                    request.sl = g_Position.entry_price;
                    request.tp = g_Position.tp2;
                    
                    if(OrderSend(request, result)) {
                        g_Position.moved_to_be = true;
                        Print("✅ BREAKEVEN activado");
                    }
                }
            }
        }
    }
    
    // TP2 alcanzado
    if(g_Position.ticket_tp2 > 0) {
        if(!PositionSelectByTicket(g_Position.ticket_tp2)) {
            Print("✅ TP2 ALCANZADO - Trade completo");
            ResetPosition(g_Position);
        }
    } else {
        ResetPosition(g_Position);
    }
}

//+------------------------------------------------------------------+
//| Funciones auxiliares                                            |
//+------------------------------------------------------------------+
double GetFVGTolerance()
{
    if(StringFind(_Symbol, "EURUSD") >= 0)
        return InpFVG_Tolerance_EURUSD;
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
        return InpFVG_Tolerance_XAUUSD;
    return InpFVG_Tolerance_EURUSD;
}

double GetCHOCHTolerance()
{
    if(StringFind(_Symbol, "EURUSD") >= 0)
        return InpCHOCH_Tolerance_EURUSD;
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
        return InpCHOCH_Tolerance_XAUUSD;
    return InpCHOCH_Tolerance_EURUSD;
}

double GetMinATR()
{
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
        return InpMinATR_XAUUSD;
    return 0.00005; // EURUSD default
}

void ResetPosition(Position_Info &pos)
{
    pos.ticket_tp1 = 0;
    pos.ticket_tp2 = 0;
    pos.entry_price = 0;
    pos.sl = 0;
    pos.tp1 = 0;
    pos.tp2 = 0;
    pos.tp1_hit = false;
    pos.moved_to_be = false;
}
//+------------------------------------------------------------------+
