//+------------------------------------------------------------------+
//|                                      SKOLL_FVG_EA_v3.0_PRO.mq5  |
//|                       Estrategia SKOLL-FVG v3.1 Completa        |
//|                       Con todos los filtros institucionales     |
//+------------------------------------------------------------------+
#property copyright "SKOLL Trading System v3.1"
#property version   "3.00"
#property strict

//--- Parámetros de entrada
input group "===== CONFIGURACIÓN TEMPORAL ====="
input int InpStartHour = 5;      // Hora de inicio (VET)
input int InpEndHour = 13;       // Hora de fin (VET)

input group "===== VISUALIZACIÓN ====="
input bool InpShowFVG = true;          // Mostrar FVG en gráfico
input bool InpShowOB = true;           // Mostrar Order Blocks
input bool InpShowTrendH4 = true;      // Mostrar EMA50 H4
input bool InpShowEntrySignals = true; // Mostrar señales de entrada

input group "===== FILTROS DE CONTEXTO H4 ====="
input bool InpUseTrendFilter = true;   // Usar filtro de tendencia H4
input int InpEMA_H4 = 50;              // EMA H4 para tendencia
input int InpATR_H4 = 14;              // ATR H4 para volatilidad
input double InpMinATR_EURUSD = 0.00005; // ATR mínimo EURUSD (5 pips)
input double InpMinATR_XAUUSD = 5.0;     // ATR mínimo XAUUSD ($5)

input group "===== PARÁMETROS FVG ====="
input double InpFVG_Tolerance_EURUSD = 0.00005;  // Tolerancia FVG EURUSD
input double InpFVG_Tolerance_XAUUSD = 0.3;      // Tolerancia FVG XAUUSD

input group "===== PARÁMETROS ORDER BLOCK ====="
input double InpOB_BodyRatio = 0.7;    // Mínimo cuerpo relativo OB (70%)
input double InpOB_Overlap = 0.5;      // Mínimo overlap FVG-OB (50%)
input int InpATR_M5 = 20;              // ATR M5 para validación OB
input double InpOB_ATR_Multiplier = 1.5; // OB debe ser >= 1.5x ATR M5

input group "===== PARÁMETROS CHOCH ====="
input double InpCHOCH_Tolerance_EURUSD = 0.00003;
input double InpCHOCH_Tolerance_XAUUSD = 0.2;
input int InpEMA_M3 = 20;              // EMA M3 para CHOCH
input int InpEMA_M5 = 20;              // EMA M5 para dirección impulso

input group "===== GESTIÓN DE RIESGO ====="
input double InpRiskPercent = 1.0;     // Riesgo por operación (%)
input double InpMaxRisk = 1.5;         // Riesgo máximo absoluto (%)
input double InpTP1_Ratio = 1.0;       // Take Profit 1 (1R)
input double InpTP2_Ratio = 2.0;       // Take Profit 2 (2R)
input bool InpMoveToBreakeven = true;  // Mover a BE al alcanzar TP1
input double InpMinTP_EURUSD = 0.00015; // TP mínimo EURUSD (15 pips)
input double InpMinTP_XAUUSD = 8.0;     // TP mínimo XAUUSD ($8)

input group "===== FILTROS AVANZADOS ====="
input bool InpUseVolatilityFilter = true;  // Filtro de volatilidad ATR
input bool InpUseNewsFilter = false;       // Filtro de noticias
input int InpNewsWindow = 2;               // Ventana de riesgo (horas)

input group "===== CONTROL OPERATIVO ====="
input bool InpEnableTrading = true;    // Habilitar trading automático
input int InpMagicNumber = 20250130;   // Número mágico
input string InpTradeComment = "SKOLL-v3";

//--- Estructuras
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
    double atr_size;
};

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
int g_ATR_M5_Handle;
int g_EMA_M5_Handle;
int g_EMA_M3_Handle;

double g_EMA_H4_Buffer[];
double g_ATR_H4_Buffer[];
double g_ATR_M5_Buffer[];
double g_EMA_M5_Buffer[];
double g_EMA_M3_Buffer[];

FVG_Structure g_CurrentFVG;
OB_Structure g_CurrentOB;
Position_Info g_Position;

int g_SignalCounter = 0;
int g_FVGCounter = 0;
int g_OBCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═════════════════════════════════════════════");
    Print("   SKOLL-FVG v3.0 PRO - Inicializando");
    Print("   Versión Institucional Completa");
    Print("═════════════════════════════════════════════");
    
    //--- Limpiar objetos anteriores
    DeleteAllObjects();
    
    //--- Crear indicadores
    g_EMA_H4_Handle = iMA(_Symbol, PERIOD_H4, InpEMA_H4, 0, MODE_EMA, PRICE_CLOSE);
    g_ATR_H4_Handle = iATR(_Symbol, PERIOD_H4, InpATR_H4);
    g_ATR_M5_Handle = iATR(_Symbol, PERIOD_M5, InpATR_M5);
    g_EMA_M5_Handle = iMA(_Symbol, PERIOD_M5, InpEMA_M5, 0, MODE_EMA, PRICE_CLOSE);
    g_EMA_M3_Handle = iMA(_Symbol, PERIOD_M3, InpEMA_M3, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_EMA_H4_Handle == INVALID_HANDLE || g_ATR_H4_Handle == INVALID_HANDLE ||
       g_ATR_M5_Handle == INVALID_HANDLE || g_EMA_M5_Handle == INVALID_HANDLE ||
       g_EMA_M3_Handle == INVALID_HANDLE) {
        Print("❌ Error creando indicadores");
        return INIT_FAILED;
    }
    
    //--- Configurar buffers
    ArraySetAsSeries(g_EMA_H4_Buffer, true);
    ArraySetAsSeries(g_ATR_H4_Buffer, true);
    ArraySetAsSeries(g_ATR_M5_Buffer, true);
    ArraySetAsSeries(g_EMA_M5_Buffer, true);
    ArraySetAsSeries(g_EMA_M3_Buffer, true);
    
    //--- Inicializar estructuras
    ResetFVG(g_CurrentFVG);
    ResetOB(g_CurrentOB);
    ResetPosition(g_Position);
    
    //--- Crear panel
    CreateInfoPanel();
    
    //--- Mostrar configuración
    Print("✅ Configuración cargada:");
    Print("   • Horario: ", InpStartHour, ":00 - ", InpEndHour, ":00 VET");
    Print("   • Filtro H4: ", InpUseTrendFilter ? "ACTIVO" : "INACTIVO");
    Print("   • Filtro ATR: ", InpUseVolatilityFilter ? "ACTIVO" : "INACTIVO");
    Print("   • Breakeven: ", InpMoveToBreakeven ? "ACTIVO" : "INACTIVO");
    Print("   • RR: 1:", InpTP2_Ratio);
    Print("   • Trading: ", InpEnableTrading ? "HABILITADO" : "DESHABILITADO");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Liberar indicadores
    if(g_EMA_H4_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_H4_Handle);
    if(g_ATR_H4_Handle != INVALID_HANDLE) IndicatorRelease(g_ATR_H4_Handle);
    if(g_ATR_M5_Handle != INVALID_HANDLE) IndicatorRelease(g_ATR_M5_Handle);
    if(g_EMA_M5_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_M5_Handle);
    if(g_EMA_M3_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_M3_Handle);
    
    Print("═════════════════════════════════════════════");
    Print("   SKOLL-FVG v3.0 PRO - Detenido");
    Print("═════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Actualizar panel
    UpdateInfoPanel();
    
    //--- Gestionar posición activa
    if(g_Position.ticket_tp1 > 0 || g_Position.ticket_tp2 > 0) {
        ManagePosition();
        return;
    }
    
    //--- Solo buscar nueva señal en nueva barra H1
    if(!IsNewBar(PERIOD_H1))
        return;
    
    //--- Verificar condiciones básicas
    if(!InpEnableTrading)
        return;
    
    if(!IsValidTradingTime())
        return;
    
    if(InpUseNewsFilter && IsHighImpactNews())
        return;
    
    //--- Buscar señal de entrada
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
//| Filtro de noticias                                              |
//+------------------------------------------------------------------+
bool IsHighImpactNews()
{
    return false; // Implementación básica
}

//+------------------------------------------------------------------+
//| Buscar señal de entrada con todos los filtros                   |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("🔍 ESCANEANDO NUEVA SEÑAL - ", TimeToString(TimeCurrent()));
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    //--- PASO 1: Filtro de tendencia H4
    if(InpUseTrendFilter) {
        if(!CheckTrendH4()) {
            Print("❌ Filtro H4: Tendencia no clara");
            return;
        }
        Print("✅ Filtro H4: Tendencia confirmada");
    }
    
    //--- PASO 2: Filtro de volatilidad
    if(InpUseVolatilityFilter) {
        if(!CheckVolatility()) {
            Print("❌ Filtro ATR: Volatilidad insuficiente");
            return;
        }
        Print("✅ Filtro ATR: Volatilidad adecuada");
    }
    
    //--- PASO 3: Detectar FVG en H1
    FVG_Structure fvg;
    if(!DetectFVG(PERIOD_H1, fvg)) {
        Print("❌ No se detectó FVG válido en H1");
        return;
    }
    
    //--- PASO 4: Verificar cierre dentro del FVG
    double close_h1 = iClose(_Symbol, PERIOD_H1, 0);
    if(close_h1 < fvg.lower || close_h1 > fvg.upper) {
        Print("❌ Precio no cerró dentro del FVG");
        return;
    }
    
    bool is_bullish = fvg.is_bullish;
    Print("✅ FVG ", is_bullish ? "ALCISTA" : "BAJISTA", " confirmado");
    Print("   Rango: ", fvg.lower, " - ", fvg.upper);
    Print("   Cierre H1: ", close_h1);
    
    //--- PASO 5: Detectar Order Block en M5
    OB_Structure ob;
    if(!DetectOrderBlock(is_bullish, ob)) {
        Print("❌ No se encontró Order Block válido");
        return;
    }
    Print("✅ Order Block encontrado");
    Print("   Rango: ", ob.lower, " - ", ob.upper);
    Print("   ATR Size: ", ob.atr_size);
    
    //--- PASO 6: Verificar overlap FVG-OB
    double overlap = CalculateOverlap(fvg, ob);
    double fvg_size = fvg.upper - fvg.lower;
    
    if(fvg_size > 0 && overlap / fvg_size < InpOB_Overlap) {
        Print("❌ Overlap insuficiente: ", NormalizeDouble(overlap/fvg_size*100, 2), "%");
        return;
    }
    Print("✅ Overlap FVG-OB: ", NormalizeDouble(overlap/fvg_size*100, 2), "%");
    
    //--- PASO 7: Confirmar CHOCH en M3
    if(!DetectCHOCH_Advanced(is_bullish)) {
        Print("❌ CHOCH no confirmado");
        return;
    }
    Print("✅ CHOCH confirmado");
    
    //--- PASO 8: Dibujar señal
    if(InpShowEntrySignals) {
        DrawEntrySignal(is_bullish);
    }
    
    //--- PASO 9: Abrir posición
    if(InpEnableTrading) {
        OpenPosition(is_bullish, ob, fvg);
    }
    
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

//+------------------------------------------------------------------+
//| Verificar tendencia H4 con EMA50                                |
//+------------------------------------------------------------------+
bool CheckTrendH4()
{
    if(CopyBuffer(g_EMA_H4_Handle, 0, 0, 2, g_EMA_H4_Buffer) != 2)
        return false;
    
    double close_h4 = iClose(_Symbol, PERIOD_H4, 0);
    double ema50 = g_EMA_H4_Buffer[0];
    
    // Tendencia debe ser clara (no aceptar mercados planos)
    bool bullish_trend = close_h4 > ema50;
    bool bearish_trend = close_h4 < ema50;
    
    // Guardar dirección de tendencia para validación posterior
    g_CurrentFVG.is_bullish = bullish_trend;
    
    if(InpShowTrendH4) {
        string name = "EMA50_H4";
        if(ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_HLINE, 0, 0, ema50);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
        } else {
            ObjectSetDouble(0, name, OBJPROP_PRICE, ema50);
        }
    }
    
    Print("   Precio H4: ", close_h4);
    Print("   EMA50 H4: ", ema50);
    Print("   Dirección: ", bullish_trend ? "ALCISTA" : (bearish_trend ? "BAJISTA" : "NEUTRAL"));
    
    return bullish_trend || bearish_trend;
}

//+------------------------------------------------------------------+
//| Verificar volatilidad con ATR H1                                |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
    if(CopyBuffer(g_ATR_H4_Handle, 0, 0, 1, g_ATR_H4_Buffer) != 1)
        return false;
    
    double atr_h4 = g_ATR_H4_Buffer[0];
    double min_atr = GetMinATR();
    
    Print("   ATR H4: ", atr_h4);
    Print("   ATR mínimo: ", min_atr);
    
    return atr_h4 >= min_atr;
}

//+------------------------------------------------------------------+
//| Detectar FVG                                                     |
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
        
        if(InpShowFVG) {
            string name = "FVG_Bull_" + IntegerToString(g_FVGCounter++);
            DrawRectangle(name, fvg.time, fvg.lower, iTime(_Symbol, timeframe, 0), fvg.upper,
                          clrDodgerBlue, STYLE_SOLID, 1, true);
        }
        
        return true;
    }
    //--- FVG Bajista
    else if(high[0] < low[2] - tolerance) {
        fvg.time = iTime(_Symbol, timeframe, 1);
        fvg.upper = high[2];
        fvg.lower = low[2];
        fvg.is_bullish = false;
        fvg.is_active = true;
        
        if(InpShowFVG) {
            string name = "FVG_Bear_" + IntegerToString(g_FVGCounter++);
            DrawRectangle(name, fvg.time, fvg.upper, iTime(_Symbol, timeframe, 0), fvg.lower,
                          clrOrangeRed, STYLE_SOLID, 1, true);
        }
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detectar Order Block mejorado con ATR y EMA                     |
//+------------------------------------------------------------------+
bool DetectOrderBlock(bool look_for_bullish, OB_Structure &ob)
{
    ResetOB(ob);
    
    //--- Copiar ATR M5
    if(CopyBuffer(g_ATR_M5_Handle, 0, 0, 50, g_ATR_M5_Buffer) != 50)
        return false;
    
    //--- Copiar EMA M5
    if(CopyBuffer(g_EMA_M5_Handle, 0, 0, 50, g_EMA_M5_Buffer) != 50)
        return false;
    
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
        double atr_m5 = g_ATR_M5_Buffer[i];
        double ema_m5 = g_EMA_M5_Buffer[i];
        
        if(look_for_bullish) {
            if(close[i] > open[i]) {
                double body = close[i] - open[i];
                double range = high[i] - low[i];
                
                // Validaciones mejoradas:
                // 1. Cuerpo >= 70%
                // 2. Range >= 1.5x ATR (significancia)
                // 3. Cierre por encima de EMA20 (impulso alcista)
                if(range > 0 && body / range >= InpOB_BodyRatio &&
                   range >= atr_m5 * InpOB_ATR_Multiplier &&
                   close[i] > ema_m5) {
                    
                    // Confirmación de impulso
                    if(close[i-1] > high[i] && close[i-2] > high[i]) {
                        ob.time = iTime(_Symbol, PERIOD_M5, i);
                        ob.upper = high[i];
                        ob.lower = low[i];
                        ob.is_bullish = true;
                        ob.is_valid = true;
                        ob.atr_size = range / atr_m5;
                        
                        if(InpShowOB) {
                            string name = "OB_Bull_" + IntegerToString(g_OBCounter++);
                            DrawRectangle(name, ob.time, ob.lower,
                                          iTime(_Symbol, PERIOD_M5, 0), ob.upper,
                                          clrLimeGreen, STYLE_DOT, 2, true);
                        }
                        
                        return true;
                    }
                }
            }
        } else {
            if(close[i] < open[i]) {
                double body = open[i] - close[i];
                double range = high[i] - low[i];
                
                if(range > 0 && body / range >= InpOB_BodyRatio &&
                   range >= atr_m5 * InpOB_ATR_Multiplier &&
                   close[i] < ema_m5) {
                    
                    if(close[i-1] < low[i] && close[i-2] < low[i]) {
                        ob.time = iTime(_Symbol, PERIOD_M5, i);
                        ob.upper = high[i];
                        ob.lower = low[i];
                        ob.is_bullish = false;
                        ob.is_valid = true;
                        ob.atr_size = range / atr_m5;
                        
                        if(InpShowOB) {
                            string name = "OB_Bear_" + IntegerToString(g_OBCounter++);
                            DrawRectangle(name, ob.time, ob.upper,
                                          iTime(_Symbol, PERIOD_M5, 0), ob.lower,
                                          clrTomato, STYLE_DOT, 2, true);
                        }
                        
                        return true;
                    }
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detectar CHOCH avanzado (rompe swing de M5, no M3)             |
//+------------------------------------------------------------------+
bool DetectCHOCH_Advanced(bool look_for_bullish)
{
    double tolerance = GetCHOCHTolerance();
    
    //--- Copiar datos M5 para detectar swing
    double high_m5[], low_m5[];
    ArraySetAsSeries(high_m5, true);
    ArraySetAsSeries(low_m5, true);
    
    if(CopyHigh(_Symbol, PERIOD_M5, 0, 50, high_m5) != 50) return false;
    if(CopyLow(_Symbol, PERIOD_M5, 0, 50, low_m5) != 50) return false;
    
    //--- Copiar datos M3 para confirmación
    double close_m3[];
    ArraySetAsSeries(close_m3, true);
    
    if(CopyClose(_Symbol, PERIOD_M3, 0, 10, close_m3) != 10) return false;
    if(CopyBuffer(g_EMA_M3_Handle, 0, 0, 10, g_EMA_M3_Buffer) != 10) return false;
    
    double current_close = close_m3[0];
    double current_ema = g_EMA_M3_Buffer[0];
    
    if(look_for_bullish) {
        //--- Buscar último swing high en M5
        double last_swing_high = 0;
        
        for(int i = 1; i < 49; i++) {
            if(high_m5[i] > high_m5[i-1] && high_m5[i] > high_m5[i+1]) {
                last_swing_high = high_m5[i];
                Print("   Último Swing High M5: ", last_swing_high, " (barra ", i, ")");
                break;
            }
        }
        
        if(last_swing_high == 0)
            return false;
        
        //--- Verificar ruptura en M3
        if(current_close > last_swing_high + tolerance && current_close > current_ema) {
            Print("   Cierre M3: ", current_close);
            Print("   EMA20 M3: ", current_ema);
            return true;
        }
        
    } else {
        //--- Buscar último swing low en M5
        double last_swing_low = 999999;
        
        for(int i = 1; i < 49; i++) {
            if(low_m5[i] < low_m5[i-1] && low_m5[i] < low_m5[i+1]) {
                last_swing_low = low_m5[i];
                Print("   Último Swing Low M5: ", last_swing_low, " (barra ", i, ")");
                break;
            }
        }
        
        if(last_swing_low == 999999)
            return false;
        
        if(current_close < last_swing_low - tolerance && current_close < current_ema) {
            Print("   Cierre M3: ", current_close);
            Print("   EMA20 M3: ", current_ema);
            return true;
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
//| Abrir posición con validaciones avanzadas                       |
//+------------------------------------------------------------------+
void OpenPosition(bool is_buy, const OB_Structure &ob, const FVG_Structure &fvg)
{
    double price = SymbolInfoDouble(_Symbol, is_buy ? SYMBOL_ASK : SYMBOL_BID);
    double tolerance = GetFVGTolerance();
    
    //--- Calcular SL
    double sl = is_buy ? ob.lower - tolerance : ob.upper + tolerance;
    double risk = MathAbs(price - sl);
    
    //--- Calcular TPs
    double tp1 = is_buy ? price + risk * InpTP1_Ratio : price - risk * InpTP1_Ratio;
    double tp2 = is_buy ? price + risk * InpTP2_Ratio : price - risk * InpTP2_Ratio;
    
    //--- Validar TP mínimo
    double min_tp = GetMinTP();
    if(MathAbs(tp1 - price) < min_tp) {
        Print("❌ TP muy pequeño: ", MathAbs(tp1 - price), " < ", min_tp);
        return;
    }
    
    //--- Calcular volumen
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_money = balance * InpRiskPercent / 100.0;
    double max_risk_money = balance * InpMaxRisk / 100.0;
    
    if(risk_money > max_risk_money) {
        Print("❌ Riesgo excede límite máximo");
        return;
    }
    
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
    
    //--- Abrir orden TP2 (50%)
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
    
    g_Position.ticket_tp2 = result.order;
    Print("✅ Posición TP2 abierta: #", result.order);
    
    //--- Abrir orden TP1 (50%)
    request.volume = volume / 2.0;
    request.tp = tp1;
    request.comment = InpTradeComment + "_TP1";
    
    if(!OrderSend(request, result)) {
        Print("❌ Error orden TP1: ", GetLastError());
        return;
    }
    
    g_Position.ticket_tp1 = result.order;
    g_Position.entry_price = price;
    g_Position.sl = sl;
    g_Position.tp1 = tp1;
    g_Position.tp2 = tp2;
    g_Position.tp1_hit = false;
    g_Position.moved_to_be = false;
    
    Print("✅ Posición TP1 abierta: #", result.order);
    
    Print("═════════════════════════════════════════════");
    Print("🚀 POSICIÓN COMPLETA ABIERTA - ", is_buy ? "COMPRA" : "VENTA");
    Print("═════════════════════════════════════════════");
    Print("📍 Entrada: ", price);
    Print("🛑 SL: ", sl, " (", NormalizeDouble(risk / point, 1), " pips)");
    Print("🎯 TP1 (1R): ", tp1);
    Print("🎯 TP2 (2R): ", tp2);
    Print("💰 Volumen total: ", volume, " (50% + 50%)");
    Print("💵 Riesgo: $", NormalizeDouble(risk_money, 2));
    Print("📊 Potencial 2R: $", NormalizeDouble(risk_money * 2, 2));
    Print("═════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Gestionar posición activa con breakeven                         |
//+------------------------------------------------------------------+
void ManagePosition()
{
    //--- Verificar si TP1 fue alcanzado
    if(!g_Position.tp1_hit && g_Position.ticket_tp1 > 0) {
        if(!PositionSelectByTicket(g_Position.ticket_tp1)) {
            g_Position.tp1_hit = true;
            Print("✅ TP1 ALCANZADO - 1R asegurado");
            
            //--- Mover TP2 a breakeven si está configurado
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
                        Print("✅ TP2 movido a BREAKEVEN");
                    }
                }
            }
        }
    }
    
    //--- Verificar si TP2 sigue abierto
    if(g_Position.ticket_tp2 > 0) {
        if(!PositionSelectByTicket(g_Position.ticket_tp2)) {
            Print("✅ TP2 ALCANZADO - Trade completo cerrado");
            ResetPosition(g_Position);
        }
    } else {
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
    if(timeframe == PERIOD_H1) tf_index = 0;
    
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
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 4);
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
    string name = "INFO_PANEL";
    if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
    }
}

//+------------------------------------------------------------------+
//| Actualizar panel de información                                 |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    string text = "═══ SKOLL-FVG v3.0 PRO ═══\n";
    text += "Trading: " + (InpEnableTrading ? "ON" : "OFF") + "\n";
    text += "Filtro H4: " + (InpUseTrendFilter ? "ON" : "OFF") + "\n";
    text += "Filtro ATR: " + (InpUseVolatilityFilter ? "ON" : "OFF") + "\n";
    text += "Breakeven: " + (InpMoveToBreakeven ? "ON" : "OFF") + "\n";
    text += "Señales: " + IntegerToString(g_SignalCounter);
    
    ObjectSetString(0, "INFO_PANEL", OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Eliminar objetos                                                 |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "FVG_") == 0 || StringFind(name, "OB_") == 0 || 
           StringFind(name, "SIGNAL_") == 0 || StringFind(name, "INFO_") == 0 ||
           StringFind(name, "EMA50_") == 0) {
            ObjectDelete(0, name);
        }
    }
}

//+------------------------------------------------------------------+
//| Funciones auxiliares                                            |
//+------------------------------------------------------------------+
double GetFVGTolerance()
{
    if(StringFind(_Symbol, "EURUSD") >= 0) return InpFVG_Tolerance_EURUSD;
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0) return InpFVG_Tolerance_XAUUSD;
    return InpFVG_Tolerance_EURUSD;
}

double GetCHOCHTolerance()
{
    if(StringFind(_Symbol, "EURUSD") >= 0) return InpCHOCH_Tolerance_EURUSD;
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0) return InpCHOCH_Tolerance_XAUUSD;
    return InpCHOCH_Tolerance_EURUSD;
}

double GetMinATR()
{
    if(StringFind(_Symbol, "EURUSD") >= 0) return InpMinATR_EURUSD;
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0) return InpMinATR_XAUUSD;
    return InpMinATR_EURUSD;
}

double GetMinTP()
{
    if(StringFind(_Symbol, "EURUSD") >= 0) return InpMinTP_EURUSD;
    if(StringFind(_Symbol, "XAUUSD") >= 0 || StringFind(_Symbol, "GOLD") >= 0) return InpMinTP_XAUUSD;
    return InpMinTP_EURUSD;
}

void ResetFVG(FVG_Structure &fvg)
{
    fvg.time = 0;
    fvg.upper = 0;
    fvg.lower = 0;
    fvg.is_bullish = false;
    fvg.is_active = false;
}

void ResetOB(OB_Structure &ob)
{
    ob.time = 0;
    ob.upper = 0;
    ob.lower = 0;
    ob.is_bullish = false;
    ob.is_valid = false;
    ob.atr_size = 0;
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
