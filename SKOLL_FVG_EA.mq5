//+------------------------------------------------------------------+
//|                                                SKOLL_FVG_EA.mq5  |
//|                                   Estrategia FVG + OB + CHOCH    |
//|                                   RR 1:2 sin trailing stop       |
//+------------------------------------------------------------------+
#property copyright "SKOLL Trading System"
#property version   "1.00"
#property strict

//--- Parámetros de entrada
input group "===== CONFIGURACIÓN TEMPORAL ====="
input int InpStartHour = 5;      // Hora de inicio (VET)
input int InpEndHour = 13;       // Hora de fin (VET)

input group "===== CONFIGURACIÓN DE INSTRUMENTOS ====="
input bool InpTradeEURUSD = true;  // Operar EURUSD
input bool InpTradeXAUUSD = true;  // Operar XAUUSD

input group "===== PARÁMETROS FVG ====="
input double InpFVG_Tolerance_EURUSD = 0.00005;  // Tolerancia FVG EURUSD (5 pips)
input double InpFVG_Tolerance_XAUUSD = 0.3;      // Tolerancia FVG XAUUSD ($0.30)

input group "===== PARÁMETROS ORDER BLOCK ====="
input double InpOB_BodyRatio = 0.7;    // Mínimo cuerpo relativo OB (70%)
input double InpOB_Overlap = 0.5;      // Mínimo overlap FVG-OB (50%)

input group "===== PARÁMETROS CHOCH ====="
input double InpCHOCH_Tolerance_EURUSD = 0.00003;  // Tolerancia CHOCH EURUSD (3 pips)
input double InpCHOCH_Tolerance_XAUUSD = 0.2;      // Tolerancia CHOCH XAUUSD ($0.20)
input int InpEMA_Period = 20;                       // Período EMA para CHOCH

input group "===== GESTIÓN DE RIESGO ====="
input double InpRiskPercent = 1.0;     // Riesgo por operación (%)
input double InpTP1_Ratio = 1.0;       // Take Profit 1 (1R - 50% posición)
input double InpTP2_Ratio = 2.0;       // Take Profit 2 (2R - 50% posición)

input group "===== FILTRO DE NOTICIAS ====="
input bool InpUseNewsFilter = true;    // Usar filtro de noticias
input int InpNewsWindow = 2;           // Ventana de riesgo (horas)

input group "===== CONTROL OPERATIVO ====="
input int InpMagicNumber = 20250129;   // Número mágico
input string InpTradeComment = "SKOLL-FVG";  // Comentario de órdenes

//--- Variables globales
struct FVG_Structure {
    datetime time;
    double upper;
    double lower;
    bool is_bullish;
    bool is_active;
};

struct OB_Structure {
    datetime time;
    double upper;
    double lower;
    bool is_bullish;
    bool is_valid;
};

struct Position_Info {
    ulong ticket;
    double entry_price;
    double sl;
    double tp1;
    double tp2;
    bool tp1_hit;
    double risk_amount;
};

FVG_Structure g_FVG_H1;
FVG_Structure g_FVG_H4;
OB_Structure g_OB_M5;
Position_Info g_Position;

int g_EMA_Handle;
double g_EMA_Buffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== Inicializando SKOLL-FVG EA ===");
    
    //--- Crear handle para EMA en M3
    g_EMA_Handle = iMA(_Symbol, PERIOD_M3, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    if(g_EMA_Handle == INVALID_HANDLE) {
        Print("Error creando indicador EMA");
        return INIT_FAILED;
    }
    
    ArraySetAsSeries(g_EMA_Buffer, true);
    
    //--- Inicializar estructuras
    ResetFVG(g_FVG_H1);
    ResetFVG(g_FVG_H4);
    ResetOB(g_OB_M5);
    ResetPosition(g_Position);
    
    Print("Parámetros cargados:");
    Print("- Horario: ", InpStartHour, ":00 - ", InpEndHour, ":00 VET");
    Print("- RR: 1:", InpTP2_Ratio);
    Print("- Riesgo: ", InpRiskPercent, "%");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_EMA_Handle != INVALID_HANDLE)
        IndicatorRelease(g_EMA_Handle);
    
    Print("=== SKOLL-FVG EA detenido ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Verificar si es hora válida de operación
    if(!IsValidTradingTime())
        return;
    
    //--- Verificar filtro de noticias
    if(InpUseNewsFilter && IsHighImpactNews())
        return;
    
    //--- Gestionar posición activa si existe
    if(g_Position.ticket > 0) {
        ManagePosition();
        return;
    }
    
    //--- Buscar nueva señal de entrada
    CheckForEntrySignal();
}

//+------------------------------------------------------------------+
//| Verificar horario válido de operación (ajustado a VET)          |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    //--- Obtener hora en VET (UTC-4)
    int hour_vet = dt.hour - 4;
    if(hour_vet < 0) hour_vet += 24;
    
    //--- Verificar si está dentro del rango 05:00 - 13:00 VET
    if(hour_vet >= InpStartHour && hour_vet < InpEndHour)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Filtro de noticias de alto impacto                              |
//+------------------------------------------------------------------+
bool IsHighImpactNews()
{
    //--- Implementación básica
    //--- En producción: integrar con calendario económico
    //--- Por ahora retorna false (no hay noticias)
    return false;
}

//+------------------------------------------------------------------+
//| Buscar señal de entrada                                         |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
    //--- 1. Detectar FVG en H4
    DetectFVG(PERIOD_H4, g_FVG_H4);
    
    //--- 2. Detectar FVG en H1
    DetectFVG(PERIOD_H1, g_FVG_H1);
    
    //--- 3. Verificar si precio cerró dentro del FVG en H1
    bool fvg_entry = false;
    bool is_bullish = false;
    
    if(g_FVG_H1.is_active && IsNewBar(PERIOD_H1)) {
        double close_h1 = iClose(_Symbol, PERIOD_H1, 0);
        
        if(close_h1 >= g_FVG_H1.lower && close_h1 <= g_FVG_H1.upper) {
            fvg_entry = true;
            is_bullish = g_FVG_H1.is_bullish;
            Print("✓ Precio cerró en FVG H1 ", is_bullish ? "ALCISTA" : "BAJISTA");
        }
    }
    
    if(!fvg_entry)
        return;
    
    //--- 4. Detectar Order Block en M5
    DetectOrderBlock(is_bullish);
    
    if(!g_OB_M5.is_valid)
        return;
    
    //--- 5. Verificar overlap FVG-OB
    double overlap = CalculateOverlap(g_FVG_H1, g_OB_M5);
    double fvg_size = g_FVG_H1.upper - g_FVG_H1.lower;
    
    if(overlap / fvg_size < InpOB_Overlap) {
        Print("✗ Overlap insuficiente: ", NormalizeDouble(overlap/fvg_size*100, 2), "%");
        return;
    }
    
    Print("✓ Overlap FVG-OB: ", NormalizeDouble(overlap/fvg_size*100, 2), "%");
    
    //--- 6. Confirmar CHOCH en M3
    if(!DetectCHOCH(is_bullish))
        return;
    
    //--- 7. TODAS LAS CONDICIONES CUMPLIDAS - ABRIR POSICIÓN
    OpenPosition(is_bullish);
}

//+------------------------------------------------------------------+
//| Detectar Fair Value Gap                                         |
//+------------------------------------------------------------------+
void DetectFVG(ENUM_TIMEFRAMES timeframe, FVG_Structure &fvg)
{
    //--- Obtener tolerancia según instrumento
    double tolerance = GetFVGTolerance();
    
    //--- Necesitamos al menos 3 velas
    if(iBars(_Symbol, timeframe) < 3)
        return;
    
    //--- Obtener datos de las últimas 3 velas cerradas
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(_Symbol, timeframe, 1, 3, high) != 3) return;
    if(CopyLow(_Symbol, timeframe, 1, 3, low) != 3) return;
    
    //--- FVG Alcista: low[0] > high[2] + tolerance
    if(low[0] > high[2] + tolerance) {
        fvg.time = iTime(_Symbol, timeframe, 1);
        fvg.upper = low[0];
        fvg.lower = high[2];
        fvg.is_bullish = true;
        fvg.is_active = true;
        
        Print("▲ FVG ALCISTA detectado en ", EnumToString(timeframe));
        Print("  Rango: ", fvg.lower, " - ", fvg.upper);
    }
    //--- FVG Bajista: high[0] < low[2] - tolerance
    else if(high[0] < low[2] - tolerance) {
        fvg.time = iTime(_Symbol, timeframe, 1);
        fvg.upper = high[2];
        fvg.lower = low[2];
        fvg.is_bullish = false;
        fvg.is_active = true;
        
        Print("▼ FVG BAJISTA detectado en ", EnumToString(timeframe));
        Print("  Rango: ", fvg.lower, " - ", fvg.upper);
    }
}

//+------------------------------------------------------------------+
//| Detectar Order Block en M5                                      |
//+------------------------------------------------------------------+
void DetectOrderBlock(bool look_for_bullish)
{
    ResetOB(g_OB_M5);
    
    //--- Buscar en las últimas 50 velas M5
    int lookback = 50;
    
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, PERIOD_M5, 0, lookback, open) != lookback) return;
    if(CopyHigh(_Symbol, PERIOD_M5, 0, lookback, high) != lookback) return;
    if(CopyLow(_Symbol, PERIOD_M5, 0, lookback, low) != lookback) return;
    if(CopyClose(_Symbol, PERIOD_M5, 0, lookback, close) != lookback) return;
    
    //--- Buscar OB (de atrás hacia adelante)
    for(int i = lookback - 3; i >= 2; i--) {
        if(look_for_bullish) {
            //--- OB Alcista: vela alcista con cuerpo >= 70%
            if(close[i] > open[i]) {
                double body = close[i] - open[i];
                double range = high[i] - low[i];
                
                if(range > 0 && body / range >= InpOB_BodyRatio) {
                    //--- Verificar que las 2 velas siguientes rompan el high
                    if(close[i-1] > high[i] && close[i-2] > high[i]) {
                        g_OB_M5.time = iTime(_Symbol, PERIOD_M5, i);
                        g_OB_M5.upper = high[i];
                        g_OB_M5.lower = low[i];
                        g_OB_M5.is_bullish = true;
                        g_OB_M5.is_valid = true;
                        
                        Print("✓ ORDER BLOCK ALCISTA encontrado en M5");
                        Print("  Rango: ", g_OB_M5.lower, " - ", g_OB_M5.upper);
                        return;
                    }
                }
            }
        } else {
            //--- OB Bajista: vela bajista con cuerpo >= 70%
            if(close[i] < open[i]) {
                double body = open[i] - close[i];
                double range = high[i] - low[i];
                
                if(range > 0 && body / range >= InpOB_BodyRatio) {
                    //--- Verificar que las 2 velas siguientes rompan el low
                    if(close[i-1] < low[i] && close[i-2] < low[i]) {
                        g_OB_M5.time = iTime(_Symbol, PERIOD_M5, i);
                        g_OB_M5.upper = high[i];
                        g_OB_M5.lower = low[i];
                        g_OB_M5.is_bullish = false;
                        g_OB_M5.is_valid = true;
                        
                        Print("✓ ORDER BLOCK BAJISTA encontrado en M5");
                        Print("  Rango: ", g_OB_M5.lower, " - ", g_OB_M5.upper);
                        return;
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calcular overlap entre FVG y OB                                 |
//+------------------------------------------------------------------+
double CalculateOverlap(const FVG_Structure &fvg, const OB_Structure &ob)
{
    double overlap_low = MathMax(fvg.lower, ob.lower);
    double overlap_high = MathMin(fvg.upper, ob.upper);
    
    if(overlap_high > overlap_low)
        return overlap_high - overlap_low;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Detectar CHOCH (Change of Character) en M3                      |
//+------------------------------------------------------------------+
bool DetectCHOCH(bool look_for_bullish)
{
    //--- Obtener tolerancia según instrumento
    double tolerance = GetCHOCHTolerance();
    
    //--- Copiar datos de M3
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    int bars_needed = 50;
    if(CopyHigh(_Symbol, PERIOD_M3, 0, bars_needed, high) != bars_needed) return false;
    if(CopyLow(_Symbol, PERIOD_M3, 0, bars_needed, low) != bars_needed) return false;
    if(CopyClose(_Symbol, PERIOD_M3, 0, bars_needed, close) != bars_needed) return false;
    
    //--- Copiar EMA
    if(CopyBuffer(g_EMA_Handle, 0, 0, bars_needed, g_EMA_Buffer) != bars_needed)
        return false;
    
    double current_close = close[0];
    double current_ema = g_EMA_Buffer[0];
    
    if(look_for_bullish) {
        //--- Buscar último swing high
        double last_swing_high = 0;
        
        for(int i = 1; i < bars_needed - 1; i++) {
            if(high[i] > high[i-1] && high[i] > high[i+1]) {
                last_swing_high = high[i];
                break;
            }
        }
        
        if(last_swing_high == 0)
            return false;
        
        //--- CHOCH alcista: cierre > swing high + tolerancia Y cierre > EMA
        if(current_close > last_swing_high + tolerance && current_close > current_ema) {
            Print("✓ CHOCH ALCISTA confirmado en M3");
            Print("  Swing High roto: ", last_swing_high);
            Print("  Cierre actual: ", current_close);
            return true;
        }
        
    } else {
        //--- Buscar último swing low
        double last_swing_low = 999999;
        
        for(int i = 1; i < bars_needed - 1; i++) {
            if(low[i] < low[i-1] && low[i] < low[i+1]) {
                last_swing_low = low[i];
                break;
            }
        }
        
        if(last_swing_low == 999999)
            return false;
        
        //--- CHOCH bajista: cierre < swing low - tolerancia Y cierre < EMA
        if(current_close < last_swing_low - tolerance && current_close < current_ema) {
            Print("✓ CHOCH BAJISTA confirmado en M3");
            Print("  Swing Low roto: ", last_swing_low);
            Print("  Cierre actual: ", current_close);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Abrir posición                                                   |
//+------------------------------------------------------------------+
void OpenPosition(bool is_buy)
{
    double price = SymbolInfoDouble(_Symbol, is_buy ? SYMBOL_ASK : SYMBOL_BID);
    double tolerance = GetFVGTolerance();
    
    //--- Calcular SL basado en el OB
    double sl = is_buy ? g_OB_M5.lower - tolerance : g_OB_M5.upper + tolerance;
    
    //--- Calcular riesgo en precio
    double risk = MathAbs(price - sl);
    
    //--- Calcular TPs (1R y 2R)
    double tp1 = is_buy ? price + risk * InpTP1_Ratio : price - risk * InpTP1_Ratio;
    double tp2 = is_buy ? price + risk * InpTP2_Ratio : price - risk * InpTP2_Ratio;
    
    //--- Calcular volumen basado en riesgo
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_money = balance * InpRiskPercent / 100.0;
    
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double risk_points = risk / point;
    double volume = (risk_money / risk_points) / tick_value;
    
    //--- Normalizar volumen
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    volume = MathFloor(volume / lot_step) * lot_step;
    volume = MathMax(min_lot, MathMin(max_lot, volume));
    
    //--- Abrir orden principal (50% del volumen para TP2)
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = volume / 2.0; // 50% para TP2
    request.type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = price;
    request.sl = sl;
    request.tp = tp2;
    request.deviation = 10;
    request.magic = InpMagicNumber;
    request.comment = InpTradeComment + "_TP2";
    
    if(!OrderSend(request, result)) {
        Print("Error abriendo posición TP2: ", GetLastError());
        return;
    }
    
    Print("✓ Posición TP2 abierta: Ticket #", result.order);
    
    //--- Abrir orden para TP1 (50% del volumen)
    request.volume = volume / 2.0;
    request.tp = tp1;
    request.comment = InpTradeComment + "_TP1";
    
    if(!OrderSend(request, result)) {
        Print("Error abriendo posición TP1: ", GetLastError());
        return;
    }
    
    Print("✓ Posición TP1 abierta: Ticket #", result.order);
    
    //--- Guardar información de la posición
    g_Position.ticket = result.order;
    g_Position.entry_price = price;
    g_Position.sl = sl;
    g_Position.tp1 = tp1;
    g_Position.tp2 = tp2;
    g_Position.tp1_hit = false;
    g_Position.risk_amount = risk;
    
    //--- Log detallado
    Print("======================================");
    Print("POSICIÓN ABIERTA - ", is_buy ? "COMPRA" : "VENTA");
    Print("Entrada: ", price);
    Print("SL: ", sl);
    Print("TP1 (1R): ", tp1);
    Print("TP2 (2R): ", tp2);
    Print("Volumen: ", volume, " (50% + 50%)");
    Print("Riesgo: ", risk_money, " USD");
    Print("======================================");
}

//+------------------------------------------------------------------+
//| Gestionar posición activa                                       |
//+------------------------------------------------------------------+
void ManagePosition()
{
    //--- Verificar si las posiciones siguen abiertas
    if(!PositionSelectByTicket(g_Position.ticket)) {
        //--- Posición cerrada, resetear
        ResetPosition(g_Position);
        ResetFVG(g_FVG_H1);
        ResetFVG(g_FVG_H4);
        ResetOB(g_OB_M5);
    }
}

//+------------------------------------------------------------------+
//| Verificar si es nueva barra                                     |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, timeframe, 0);
    
    if(current_bar_time != last_bar_time) {
        last_bar_time = current_bar_time;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Obtener tolerancia FVG según instrumento                        |
//+------------------------------------------------------------------+
double GetFVGTolerance()
{
    if(_Symbol == "EURUSD" || _Symbol == "EURUSD.raw")
        return InpFVG_Tolerance_EURUSD;
    else if(_Symbol == "XAUUSD" || _Symbol == "XAUUSD.raw" || _Symbol == "GOLD")
        return InpFVG_Tolerance_XAUUSD;
    
    return InpFVG_Tolerance_EURUSD; // Default
}

//+------------------------------------------------------------------+
//| Obtener tolerancia CHOCH según instrumento                      |
//+------------------------------------------------------------------+
double GetCHOCHTolerance()
{
    if(_Symbol == "EURUSD" || _Symbol == "EURUSD.raw")
        return InpCHOCH_Tolerance_EURUSD;
    else if(_Symbol == "XAUUSD" || _Symbol == "XAUUSD.raw" || _Symbol == "GOLD")
        return InpCHOCH_Tolerance_XAUUSD;
    
    return InpCHOCH_Tolerance_EURUSD; // Default
}

//+------------------------------------------------------------------+
//| Resetear estructura FVG                                         |
//+------------------------------------------------------------------+
void ResetFVG(FVG_Structure &fvg)
{
    fvg.time = 0;
    fvg.upper = 0;
    fvg.lower = 0;
    fvg.is_bullish = false;
    fvg.is_active = false;
}

//+------------------------------------------------------------------+
//| Resetear estructura OB                                          |
//+------------------------------------------------------------------+
void ResetOB(OB_Structure &ob)
{
    ob.time = 0;
    ob.upper = 0;
    ob.lower = 0;
    ob.is_bullish = false;
    ob.is_valid = false;
}

//+------------------------------------------------------------------+
//| Resetear información de posición                                |
//+------------------------------------------------------------------+
void ResetPosition(Position_Info &pos)
{
    pos.ticket = 0;
    pos.entry_price = 0;
    pos.sl = 0;
    pos.tp1 = 0;
    pos.tp2 = 0;
    pos.tp1_hit = false;
    pos.risk_amount = 0;
}

//+------------------------------------------------------------------+
