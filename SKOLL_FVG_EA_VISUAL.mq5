//+------------------------------------------------------------------+
//|                                        SKOLL_FVG_EA_VISUAL.mq5  |
//|                       Estrategia FVG + OB + CHOCH con Gráficos  |
//|                                   RR 1:2 con visualización      |
//+------------------------------------------------------------------+
#property copyright "SKOLL Trading System"
#property version   "2.00"
#property strict

//--- Parámetros de entrada
input group "===== CONFIGURACIÓN TEMPORAL ====="
input int InpStartHour = 5;      // Hora de inicio (VET)
input int InpEndHour = 13;       // Hora de fin (VET)

input group "===== VISUALIZACIÓN ====="
input bool InpShowFVG = true;          // Mostrar FVG en gráfico
input bool InpShowOB = true;           // Mostrar Order Blocks
input bool InpShowCHOCH = true;        // Mostrar puntos CHOCH
input bool InpShowEntrySignals = true; // Mostrar señales de entrada
input bool InpShowHistoricalSetups = true; // Mostrar setups históricos
input int InpHistoricalBars = 500;     // Barras históricas a analizar

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
input bool InpUseNewsFilter = false;    // Usar filtro de noticias
input int InpNewsWindow = 2;           // Ventana de riesgo (horas)

input group "===== CONTROL OPERATIVO ====="
input bool InpEnableTrading = true;    // Habilitar trading automático
input int InpMagicNumber = 20250129;   // Número mágico
input string InpTradeComment = "SKOLL-FVG";  // Comentario de órdenes

//--- Estructuras
struct FVG_Structure {
    datetime time;
    double upper;
    double lower;
    bool is_bullish;
    bool is_active;
    int bar_index;
};

struct OB_Structure {
    datetime time;
    double upper;
    double lower;
    bool is_bullish;
    bool is_valid;
    int bar_index;
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

struct EntrySignal {
    datetime time;
    double price;
    bool is_buy;
    string reason;
};

//--- Variables globales
FVG_Structure g_FVG_H1;
FVG_Structure g_FVG_H4;
OB_Structure g_OB_M5;
Position_Info g_Position;

int g_EMA_Handle;
double g_EMA_Buffer[];

datetime g_LastBarTime_M3 = 0;
datetime g_LastBarTime_M5 = 0;
datetime g_LastBarTime_H1 = 0;

int g_SignalCounter = 0;
int g_FVGCounter = 0;
int g_OBCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== Inicializando SKOLL-FVG EA v2.0 ===");
    Print("=== VERSIÓN CON VISUALIZACIÓN GRÁFICA ===");
    
    //--- Limpiar objetos anteriores
    DeleteAllObjects();
    
    //--- Crear handle para EMA en M3
    g_EMA_Handle = iMA(_Symbol, PERIOD_M3, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    if(g_EMA_Handle == INVALID_HANDLE) {
        Print("❌ Error creando indicador EMA");
        return INIT_FAILED;
    }
    
    ArraySetAsSeries(g_EMA_Buffer, true);
    
    //--- Inicializar estructuras
    ResetFVG(g_FVG_H1);
    ResetFVG(g_FVG_H4);
    ResetOB(g_OB_M5);
    ResetPosition(g_Position);
    
    //--- Análisis histórico
    if(InpShowHistoricalSetups) {
        Print("🔍 Analizando setups históricos...");
        AnalyzeHistoricalSetups();
    }
    
    //--- Crear panel de información
    CreateInfoPanel();
    
    Print("✅ EA inicializado correctamente");
    Print("⏰ Horario operativo: ", InpStartHour, ":00 - ", InpEndHour, ":00 VET");
    Print("💰 Riesgo por trade: ", InpRiskPercent, "%");
    Print("🎯 RR configurado: 1:", InpTP2_Ratio);
    Print("🤖 Trading automático: ", InpEnableTrading ? "ACTIVADO" : "DESACTIVADO");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_EMA_Handle != INVALID_HANDLE)
        IndicatorRelease(g_EMA_Handle);
    
    //--- Opcional: mantener objetos en el gráfico
    // DeleteAllObjects();
    
    Print("=== SKOLL-FVG EA detenido ===");
    Print("Razón: ", GetDeinitReasonText(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Actualizar panel de información
    UpdateInfoPanel();
    
    //--- Verificar nueva barra en M5 para escanear
    if(IsNewBar(PERIOD_M5)) {
        ScanAndDrawMarketStructure();
    }
    
    //--- Solo operar si está habilitado
    if(!InpEnableTrading)
        return;
    
    //--- Verificar si es hora válida de operación
    if(!IsValidTradingTime()) {
        return;
    }
    
    //--- Verificar filtro de noticias
    if(InpUseNewsFilter && IsHighImpactNews())
        return;
    
    //--- Gestionar posición activa si existe
    if(g_Position.ticket > 0) {
        ManagePosition();
        return;
    }
    
    //--- Buscar nueva señal de entrada (solo en nueva barra H1)
    if(IsNewBar(PERIOD_H1)) {
        CheckForEntrySignal();
    }
}

//+------------------------------------------------------------------+
//| Escanear y dibujar estructura del mercado                       |
//+------------------------------------------------------------------+
void ScanAndDrawMarketStructure()
{
    //--- Detectar y dibujar FVGs en H1
    if(InpShowFVG) {
        DetectAndDrawFVG(PERIOD_H1);
    }
    
    //--- Detectar y dibujar Order Blocks en M5
    if(InpShowOB) {
        DetectAndDrawOrderBlocks();
    }
}

//+------------------------------------------------------------------+
//| Detectar y dibujar FVG                                          |
//+------------------------------------------------------------------+
void DetectAndDrawFVG(ENUM_TIMEFRAMES timeframe)
{
    double tolerance = GetFVGTolerance();
    
    if(iBars(_Symbol, timeframe) < 3)
        return;
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(_Symbol, timeframe, 1, 3, high) != 3) return;
    if(CopyLow(_Symbol, timeframe, 1, 3, low) != 3) return;
    
    datetime time1 = iTime(_Symbol, timeframe, 1);
    
    //--- FVG Alcista
    if(low[0] > high[2] + tolerance) {
        string name = "FVG_Bull_" + IntegerToString(g_FVGCounter++);
        DrawRectangle(name, time1, high[2], iTime(_Symbol, timeframe, 0), low[0], 
                      clrDodgerBlue, STYLE_SOLID, 1, true);
        
        Print("▲ FVG ALCISTA: ", high[2], " - ", low[0]);
    }
    //--- FVG Bajista
    else if(high[0] < low[2] - tolerance) {
        string name = "FVG_Bear_" + IntegerToString(g_FVGCounter++);
        DrawRectangle(name, time1, low[2], iTime(_Symbol, timeframe, 0), high[0], 
                      clrOrangeRed, STYLE_SOLID, 1, true);
        
        Print("▼ FVG BAJISTA: ", high[0], " - ", low[2]);
    }
}

//+------------------------------------------------------------------+
//| Detectar y dibujar Order Blocks                                 |
//+------------------------------------------------------------------+
void DetectAndDrawOrderBlocks()
{
    int lookback = 20;
    
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, PERIOD_M5, 0, lookback, open) != lookback) return;
    if(CopyHigh(_Symbol, PERIOD_M5, 0, lookback, high) != lookback) return;
    if(CopyLow(_Symbol, PERIOD_M5, 0, lookback, low) != lookback) return;
    if(CopyClose(_Symbol, PERIOD_M5, 0, lookback, close) != lookback) return;
    
    //--- Buscar OB alcista
    for(int i = lookback - 3; i >= 2; i--) {
        if(close[i] > open[i]) {
            double body = close[i] - open[i];
            double range = high[i] - low[i];
            
            if(range > 0 && body / range >= InpOB_BodyRatio) {
                if(close[i-1] > high[i] && close[i-2] > high[i]) {
                    datetime time_ob = iTime(_Symbol, PERIOD_M5, i);
                    string name = "OB_Bull_" + IntegerToString(g_OBCounter++);
                    
                    DrawRectangle(name, time_ob, low[i], 
                                  iTime(_Symbol, PERIOD_M5, 0), high[i],
                                  clrLimeGreen, STYLE_DOT, 2, true);
                }
            }
        }
    }
    
    //--- Buscar OB bajista
    for(int i = lookback - 3; i >= 2; i--) {
        if(close[i] < open[i]) {
            double body = open[i] - close[i];
            double range = high[i] - low[i];
            
            if(range > 0 && body / range >= InpOB_BodyRatio) {
                if(close[i-1] < low[i] && close[i-2] < low[i]) {
                    datetime time_ob = iTime(_Symbol, PERIOD_M5, i);
                    string name = "OB_Bear_" + IntegerToString(g_OBCounter++);
                    
                    DrawRectangle(name, time_ob, high[i], 
                                  iTime(_Symbol, PERIOD_M5, 0), low[i],
                                  clrTomato, STYLE_DOT, 2, true);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Analizar setups históricos                                      |
//+------------------------------------------------------------------+
void AnalyzeHistoricalSetups()
{
    int total_setups = 0;
    int bullish_setups = 0;
    int bearish_setups = 0;
    
    Print("📊 Analizando últimas ", InpHistoricalBars, " barras H1...");
    
    //--- Aquí iría la lógica completa de análisis histórico
    //--- Por simplicidad, dibujaremos los FVGs y OBs más recientes
    
    // Detectar FVGs en las últimas 100 barras H1
    for(int i = 3; i < 100; i++) {
        double high[], low[];
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        
        if(CopyHigh(_Symbol, PERIOD_H1, i, 3, high) != 3) continue;
        if(CopyLow(_Symbol, PERIOD_H1, i, 3, low) != 3) continue;
        
        double tolerance = GetFVGTolerance();
        
        //--- FVG Alcista histórico
        if(low[0] > high[2] + tolerance) {
            datetime time1 = iTime(_Symbol, PERIOD_H1, i);
            string name = "HIST_FVG_Bull_" + IntegerToString(i);
            DrawRectangle(name, time1, high[2], iTime(_Symbol, PERIOD_H1, i-2), low[0], 
                          clrDodgerBlue, STYLE_DOT, 1, true);
            bullish_setups++;
        }
        //--- FVG Bajista histórico
        else if(high[0] < low[2] - tolerance) {
            datetime time1 = iTime(_Symbol, PERIOD_H1, i);
            string name = "HIST_FVG_Bear_" + IntegerToString(i);
            DrawRectangle(name, time1, low[2], iTime(_Symbol, PERIOD_H1, i-2), high[0], 
                          clrOrangeRed, STYLE_DOT, 1, true);
            bearish_setups++;
        }
    }
    
    total_setups = bullish_setups + bearish_setups;
    
    Print("✅ Análisis histórico completado:");
    Print("   📈 Setups alcistas: ", bullish_setups);
    Print("   📉 Setups bajistas: ", bearish_setups);
    Print("   🎯 Total: ", total_setups);
}

//+------------------------------------------------------------------+
//| Verificar horario válido de operación                          |
//+------------------------------------------------------------------+
bool IsValidTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    //--- Ajuste a VET (UTC-4)
    // En backtest usar directamente la hora UTC del broker
    int hour_utc = dt.hour;
    
    // Convertir a VET: VET = UTC - 4
    int hour_vet = hour_utc - 4;
    if(hour_vet < 0) hour_vet += 24;
    
    //--- Para backtest, también aceptar horas UTC equivalentes
    // 05:00 VET = 09:00 UTC
    // 13:00 VET = 17:00 UTC
    
    // Verificar en VET
    bool valid_vet = (hour_vet >= InpStartHour && hour_vet < InpEndHour);
    
    // Verificar en UTC (para backtest)
    int start_utc = InpStartHour + 4;
    int end_utc = InpEndHour + 4;
    bool valid_utc = (hour_utc >= start_utc && hour_utc < end_utc);
    
    return valid_vet || valid_utc;
}

//+------------------------------------------------------------------+
//| Filtro de noticias                                              |
//+------------------------------------------------------------------+
bool IsHighImpactNews()
{
    return false; // Implementación básica
}

//+------------------------------------------------------------------+
//| Buscar señal de entrada                                         |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
    //--- 1. Detectar FVG en H1
    FVG_Structure fvg_h1;
    if(!DetectFVG(PERIOD_H1, fvg_h1)) {
        return;
    }
    
    //--- 2. Verificar si precio cerró dentro del FVG
    double close_h1 = iClose(_Symbol, PERIOD_H1, 0);
    
    if(close_h1 < fvg_h1.lower || close_h1 > fvg_h1.upper) {
        return;
    }
    
    bool is_bullish = fvg_h1.is_bullish;
    Print("✓ Precio cerró en FVG H1 ", is_bullish ? "ALCISTA" : "BAJISTA");
    Print("  FVG: ", fvg_h1.lower, " - ", fvg_h1.upper);
    Print("  Cierre H1: ", close_h1);
    
    //--- 3. Detectar Order Block en M5
    OB_Structure ob_m5;
    if(!DetectOrderBlock(is_bullish, ob_m5)) {
        Print("✗ No se encontró Order Block válido");
        return;
    }
    
    Print("✓ Order Block encontrado: ", ob_m5.lower, " - ", ob_m5.upper);
    
    //--- 4. Verificar overlap
    double overlap = CalculateOverlap(fvg_h1, ob_m5);
    double fvg_size = fvg_h1.upper - fvg_h1.lower;
    
    if(fvg_size > 0 && overlap / fvg_size < InpOB_Overlap) {
        Print("✗ Overlap insuficiente: ", NormalizeDouble(overlap/fvg_size*100, 2), "%");
        return;
    }
    
    Print("✓ Overlap: ", NormalizeDouble(overlap/fvg_size*100, 2), "%");
    
    //--- 5. Confirmar CHOCH en M3
    if(!DetectCHOCH(is_bullish)) {
        Print("✗ CHOCH no confirmado");
        return;
    }
    
    Print("✓ CHOCH confirmado");
    
    //--- 6. Dibujar señal de entrada
    if(InpShowEntrySignals) {
        DrawEntrySignal(is_bullish);
    }
    
    //--- 7. Abrir posición si trading está habilitado
    if(InpEnableTrading) {
        OpenPosition(is_bullish, ob_m5);
    }
}

//+------------------------------------------------------------------+
//| Detectar FVG (retorna estructura)                               |
//+------------------------------------------------------------------+
bool DetectFVG(ENUM_TIMEFRAMES timeframe, FVG_Structure &fvg)
{
    ResetFVG(fvg);
    
    double tolerance = GetFVGTolerance();
    
    if(iBars(_Symbol, timeframe) < 3)
        return false;
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(_Symbol, timeframe, 1, 3, high) != 3) return false;
    if(CopyLow(_Symbol, timeframe, 1, 3, low) != 3) return false;
    
    //--- FVG Alcista
    if(low[0] > high[2] + tolerance) {
        fvg.time = iTime(_Symbol, timeframe, 1);
        fvg.upper = low[0];
        fvg.lower = high[2];
        fvg.is_bullish = true;
        fvg.is_active = true;
        return true;
    }
    //--- FVG Bajista
    else if(high[0] < low[2] - tolerance) {
        fvg.time = iTime(_Symbol, timeframe, 1);
        fvg.upper = high[2];
        fvg.lower = low[2];
        fvg.is_bullish = false;
        fvg.is_active = true;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detectar Order Block (retorna estructura)                       |
//+------------------------------------------------------------------+
bool DetectOrderBlock(bool look_for_bullish, OB_Structure &ob)
{
    ResetOB(ob);
    
    int lookback = 50;
    
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, PERIOD_M5, 0, lookback, open) != lookback) return false;
    if(CopyHigh(_Symbol, PERIOD_M5, 0, lookback, high) != lookback) return false;
    if(CopyLow(_Symbol, PERIOD_M5, 0, lookback, low) != lookback) return false;
    if(CopyClose(_Symbol, PERIOD_M5, 0, lookback, close) != lookback) return false;
    
    for(int i = lookback - 3; i >= 2; i--) {
        if(look_for_bullish) {
            if(close[i] > open[i]) {
                double body = close[i] - open[i];
                double range = high[i] - low[i];
                
                if(range > 0 && body / range >= InpOB_BodyRatio) {
                    if(close[i-1] > high[i] && close[i-2] > high[i]) {
                        ob.time = iTime(_Symbol, PERIOD_M5, i);
                        ob.upper = high[i];
                        ob.lower = low[i];
                        ob.is_bullish = true;
                        ob.is_valid = true;
                        return true;
                    }
                }
            }
        } else {
            if(close[i] < open[i]) {
                double body = open[i] - close[i];
                double range = high[i] - low[i];
                
                if(range > 0 && body / range >= InpOB_BodyRatio) {
                    if(close[i-1] < low[i] && close[i-2] < low[i]) {
                        ob.time = iTime(_Symbol, PERIOD_M5, i);
                        ob.upper = high[i];
                        ob.lower = low[i];
                        ob.is_bullish = false;
                        ob.is_valid = true;
                        return true;
                    }
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calcular overlap                                                 |
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
//| Detectar CHOCH                                                   |
//+------------------------------------------------------------------+
bool DetectCHOCH(bool look_for_bullish)
{
    double tolerance = GetCHOCHTolerance();
    
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    int bars_needed = 50;
    if(CopyHigh(_Symbol, PERIOD_M3, 0, bars_needed, high) != bars_needed) return false;
    if(CopyLow(_Symbol, PERIOD_M3, 0, bars_needed, low) != bars_needed) return false;
    if(CopyClose(_Symbol, PERIOD_M3, 0, bars_needed, close) != bars_needed) return false;
    
    if(CopyBuffer(g_EMA_Handle, 0, 0, bars_needed, g_EMA_Buffer) != bars_needed)
        return false;
    
    double current_close = close[0];
    double current_ema = g_EMA_Buffer[0];
    
    if(look_for_bullish) {
        double last_swing_high = 0;
        
        for(int i = 1; i < bars_needed - 1; i++) {
            if(high[i] > high[i-1] && high[i] > high[i+1]) {
                last_swing_high = high[i];
                break;
            }
        }
        
        if(last_swing_high == 0)
            return false;
        
        if(current_close > last_swing_high + tolerance && current_close > current_ema) {
            Print("✓ CHOCH ALCISTA:");
            Print("  Swing High: ", last_swing_high);
            Print("  Cierre: ", current_close);
            Print("  EMA: ", current_ema);
            return true;
        }
        
    } else {
        double last_swing_low = 999999;
        
        for(int i = 1; i < bars_needed - 1; i++) {
            if(low[i] < low[i-1] && low[i] < low[i+1]) {
                last_swing_low = low[i];
                break;
            }
        }
        
        if(last_swing_low == 999999)
            return false;
        
        if(current_close < last_swing_low - tolerance && current_close < current_ema) {
            Print("✓ CHOCH BAJISTA:");
            Print("  Swing Low: ", last_swing_low);
            Print("  Cierre: ", current_close);
            Print("  EMA: ", current_ema);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Abrir posición                                                   |
//+------------------------------------------------------------------+
void OpenPosition(bool is_buy, const OB_Structure &ob)
{
    double price = SymbolInfoDouble(_Symbol, is_buy ? SYMBOL_ASK : SYMBOL_BID);
    double tolerance = GetFVGTolerance();
    
    double sl = is_buy ? ob.lower - tolerance : ob.upper + tolerance;
    double risk = MathAbs(price - sl);
    
    double tp1 = is_buy ? price + risk * InpTP1_Ratio : price - risk * InpTP1_Ratio;
    double tp2 = is_buy ? price + risk * InpTP2_Ratio : price - risk * InpTP2_Ratio;
    
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
    
    //--- Normalizar precios
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    price = NormalizeDouble(price, digits);
    sl = NormalizeDouble(sl, digits);
    tp1 = NormalizeDouble(tp1, digits);
    tp2 = NormalizeDouble(tp2, digits);
    
    //--- Orden TP2
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
        Print("❌ Error orden TP2: ", GetLastError());
        return;
    }
    
    Print("✅ Posición TP2 abierta: #", result.order);
    
    //--- Orden TP1
    request.volume = volume / 2.0;
    request.tp = tp1;
    request.comment = InpTradeComment + "_TP1";
    
    if(!OrderSend(request, result)) {
        Print("❌ Error orden TP1: ", GetLastError());
        return;
    }
    
    Print("✅ Posición TP1 abierta: #", result.order);
    
    g_Position.ticket = result.order;
    g_Position.entry_price = price;
    g_Position.sl = sl;
    g_Position.tp1 = tp1;
    g_Position.tp2 = tp2;
    
    Print("═══════════════════════════════════");
    Print("🚀 POSICIÓN ABIERTA - ", is_buy ? "COMPRA" : "VENTA");
    Print("📍 Entrada: ", price);
    Print("🛑 SL: ", sl, " (", NormalizeDouble(risk * MathPow(10, digits), 2), " pips)");
    Print("🎯 TP1: ", tp1);
    Print("🎯 TP2: ", tp2);
    Print("💰 Volumen: ", volume);
    Print("💵 Riesgo: $", NormalizeDouble(risk_money, 2));
    Print("═══════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Gestionar posición                                              |
//+------------------------------------------------------------------+
void ManagePosition()
{
    if(!PositionSelectByTicket(g_Position.ticket)) {
        ResetPosition(g_Position);
    }
}

//+------------------------------------------------------------------+
//| Verificar nueva barra                                           |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    static datetime last_times[10];
    static bool initialized = false;
    
    if(!initialized) {
        ArrayInitialize(last_times, 0);
        initialized = true;
    }
    
    int tf_index = 0;
    if(timeframe == PERIOD_M3) tf_index = 0;
    else if(timeframe == PERIOD_M5) tf_index = 1;
    else if(timeframe == PERIOD_H1) tf_index = 2;
    
    datetime current_time = iTime(_Symbol, timeframe, 0);
    
    if(current_time != last_times[tf_index]) {
        last_times[tf_index] = current_time;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Dibujar señal de entrada                                        |
//+------------------------------------------------------------------+
void DrawEntrySignal(bool is_buy)
{
    string name = "SIGNAL_" + IntegerToString(g_SignalCounter++);
    datetime time = iTime(_Symbol, PERIOD_M3, 0);
    double price = iClose(_Symbol, PERIOD_M3, 0);
    
    if(ObjectCreate(0, name, OBJ_ARROW, 0, time, price)) {
        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, is_buy ? 233 : 234);
        ObjectSetInteger(0, name, OBJPROP_COLOR, is_buy ? clrLime : clrRed);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
        ObjectSetString(0, name, OBJPROP_TEXT, is_buy ? "BUY SIGNAL" : "SELL SIGNAL");
    }
}

//+------------------------------------------------------------------+
//| Dibujar rectángulo                                              |
//+------------------------------------------------------------------+
void DrawRectangle(string name, datetime time1, double price1, datetime time2, double price2,
                   color clr, ENUM_LINE_STYLE style, int width, bool back)
{
    if(ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);
    
    if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_BACK, back);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}

//+------------------------------------------------------------------+
//| Crear panel de información                                      |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
    string label_name = "INFO_PANEL";
    int x = 10;
    int y = 20;
    
    if(ObjectCreate(0, label_name, OBJ_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, label_name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, label_name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, label_name, OBJPROP_FONT, "Consolas");
    }
}

//+------------------------------------------------------------------+
//| Actualizar panel de información                                 |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    string text = "═══ SKOLL-FVG v2.0 ═══\n";
    text += "Trading: " + (InpEnableTrading ? "ON" : "OFF") + "\n";
    text += "Horario: " + IntegerToString(InpStartHour) + ":00-" + IntegerToString(InpEndHour) + ":00 VET\n";
    text += "FVGs: " + IntegerToString(g_FVGCounter) + "\n";
    text += "OBs: " + IntegerToString(g_OBCounter) + "\n";
    text += "Señales: " + IntegerToString(g_SignalCounter);
    
    ObjectSetString(0, "INFO_PANEL", OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Eliminar todos los objetos                                      |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "FVG_") == 0 || 
           StringFind(name, "OB_") == 0 || 
           StringFind(name, "SIGNAL_") == 0 ||
           StringFind(name, "HIST_") == 0 ||
           StringFind(name, "INFO_") == 0) {
            ObjectDelete(0, name);
        }
    }
}

//+------------------------------------------------------------------+
//| Obtener tolerancia FVG                                          |
//+------------------------------------------------------------------+
double GetFVGTolerance()
{
    string symbol = _Symbol;
    if(StringFind(symbol, "EURUSD") >= 0)
        return InpFVG_Tolerance_EURUSD;
    else if(StringFind(symbol, "XAUUSD") >= 0 || StringFind(symbol, "GOLD") >= 0)
        return InpFVG_Tolerance_XAUUSD;
    
    return InpFVG_Tolerance_EURUSD;
}

//+------------------------------------------------------------------+
//| Obtener tolerancia CHOCH                                        |
//+------------------------------------------------------------------+
double GetCHOCHTolerance()
{
    string symbol = _Symbol;
    if(StringFind(symbol, "EURUSD") >= 0)
        return InpCHOCH_Tolerance_EURUSD;
    else if(StringFind(symbol, "XAUUSD") >= 0 || StringFind(symbol, "GOLD") >= 0)
        return InpCHOCH_Tolerance_XAUUSD;
    
    return InpCHOCH_Tolerance_EURUSD;
}

//+------------------------------------------------------------------+
//| Resetear estructuras                                            |
//+------------------------------------------------------------------+
void ResetFVG(FVG_Structure &fvg)
{
    fvg.time = 0;
    fvg.upper = 0;
    fvg.lower = 0;
    fvg.is_bullish = false;
    fvg.is_active = false;
    fvg.bar_index = 0;
}

void ResetOB(OB_Structure &ob)
{
    ob.time = 0;
    ob.upper = 0;
    ob.lower = 0;
    ob.is_bullish = false;
    ob.is_valid = false;
    ob.bar_index = 0;
}

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
//| Obtener texto de razón de desinicialización                     |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
    switch(reason) {
        case REASON_PROGRAM: return "Expert removido del gráfico";
        case REASON_REMOVE: return "Expert eliminado";
        case REASON_RECOMPILE: return "Expert recompilado";
        case REASON_CHARTCHANGE: return "Cambio de símbolo/período";
        case REASON_CHARTCLOSE: return "Gráfico cerrado";
        case REASON_PARAMETERS: return "Cambio de parámetros";
        case REASON_ACCOUNT: return "Cambio de cuenta";
        default: return "Razón desconocida";
    }
}
//+------------------------------------------------------------------+
