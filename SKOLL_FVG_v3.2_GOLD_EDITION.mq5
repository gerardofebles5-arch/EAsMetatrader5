//+------------------------------------------------------------------+
//|                              SKOLL_FVG_v3.2_GOLD_EDITION.mq5    |
//|                    Optimizado para XAUUSD y Fondos de Fondeo    |
//|                    Sistema de Escalado $5K → $200K+             |
//+------------------------------------------------------------------+
#property copyright "SKOLL Trading System v3.2 GOLD"
#property version   "3.20"
#property strict

//--- Parámetros de entrada
input group "===== CONFIGURACIÓN TEMPORAL ====="
input int InpStartHour = 5;      // Hora de inicio (VET)
input int InpEndHour = 13;       // Hora de fin (VET)
input bool InpCloseAllAtNight = true;  // Cerrar posiciones a las 23:59

input group "===== VISUALIZACIÓN ====="
input bool InpShowFVG = true;          // Mostrar FVG en gráfico
input bool InpShowOB = true;           // Mostrar Order Blocks
input bool InpShowTrendH4 = true;      // Mostrar EMAs H4
input bool InpShowCompliancePanel = true;  // Panel de cumplimiento

input group "===== FILTROS DE CONTEXTO H4 (CRÍTICOS) ====="
input bool InpUseTrendFilter = true;   // Filtro de tendencia doble EMA
input int InpEMA_H4_Fast = 50;         // EMA rápida H4
input int InpEMA_H4_Slow = 200;        // EMA lenta H4 (tendencia macro)
input int InpATR_H4 = 14;              // ATR H4 para volatilidad
input double InpMinATR_H4 = 15.0;      // ATR mínimo H4 ($15)
input double InpATR_Compression = 0.6; // Ratio mínimo ATR_H1/ATR_H4

input group "===== PARÁMETROS FVG DINÁMICOS ====="
input double InpFVG_BaseToleranceXAU = 0.3;    // Tolerancia base ($0.30)
input double InpFVG_ATR_Multiplier = 0.12;     // Multiplicador ATR (dinámico)

input group "===== ORDER BLOCK OPTIMIZADO PARA ORO ====="
input double InpOB_ClosureThreshold = 0.66;    // Cierre en tercio (66%)
input double InpOB_ATR_Multiplier = 0.8;       // Rango >= 0.8x ATR M5
input double InpOB_Overlap = 0.50;             // Overlap mínimo con FVG

input group "===== CHOCH BASADO EN SWING H1 ====="
input double InpCHOCH_BaseToleranceXAU = 0.5;  // Tolerancia base ($0.50)
input double InpCHOCH_ATR_Multiplier = 0.05;   // Multiplicador ATR
input int InpEMA_M5 = 20;                      // EMA M5 para impulso
input int InpEMA_M3 = 20;                      // EMA M3 para confirmación

input group "===== GESTIÓN DE RIESGO FONDOS DE FONDEO ====="
input double InpRiskPercent = 0.3;             // Riesgo por trade (0.3%)
input double InpMaxDailyRisk = 1.5;            // Riesgo diario máximo (1.5%)
input double InpMaxDrawdownPercent = 4.0;      // Drawdown para detener (4%)
input double InpTP1_Ratio = 1.0;               // Take Profit 1 (1R)
input double InpTP2_Ratio = 2.0;               // Take Profit 2 (2R)
input double InpMinTP_XAUUSD = 12.0;           // TP mínimo ($12)
input bool InpMoveToBreakeven = true;          // Breakeven al alcanzar TP1
input int InpMaxTradesPerDay = 2;              // Máximo trades por día
input double InpMaxSpread = 0.8;               // Spread máximo ($0.80)

input group "===== FILTROS ANTI-VIOLACIÓN ====="
input bool InpUseNewsFilter = true;            // Filtro de noticias (obligatorio)
input int InpNewsWindow = 2;                   // Ventana de riesgo (2h)
input bool InpAntiScalping = true;             // Evitar scalping (<5min)
input int InpMinTradeDuration = 5;             // Duración mínima (5min)

input group "===== CONTROL OPERATIVO ====="
input bool InpEnableTrading = true;            // Habilitar trading
input int InpMagicNumber = 20250130;           // Número mágico
input string InpTradeComment = "SKOLL-GOLD";   // Comentario

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
    double atr_ratio;
};

struct Position_Info {
    ulong ticket_tp1;
    ulong ticket_tp2;
    datetime open_time;
    double entry_price;
    double sl;
    double tp1;
    double tp2;
    bool tp1_hit;
    bool moved_to_be;
};

struct DailyStats {
    datetime date;
    int trades_today;
    double daily_pnl;
    double peak_equity;
    double current_drawdown;
    bool trading_stopped;
};

//--- Variables globales
int g_EMA_H4_Fast_Handle;
int g_EMA_H4_Slow_Handle;
int g_ATR_H4_Handle;
int g_ATR_H1_Handle;
int g_ATR_M5_Handle;
int g_EMA_M5_Handle;
int g_EMA_M3_Handle;

double g_EMA_H4_Fast_Buffer[];
double g_EMA_H4_Slow_Buffer[];
double g_ATR_H4_Buffer[];
double g_ATR_H1_Buffer[];
double g_ATR_M5_Buffer[];
double g_EMA_M5_Buffer[];
double g_EMA_M3_Buffer[];

Position_Info g_Position;
DailyStats g_Stats;

int g_SignalCounter = 0;
int g_FVGCounter = 0;
int g_OBCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("═══════════════════════════════════════════════════════");
    Print("     SKOLL-FVG v3.2 GOLD EDITION - INICIALIZANDO      ");
    Print("     Optimizado para XAUUSD y Fondos de Fondeo        ");
    Print("═══════════════════════════════════════════════════════");
    
    //--- Validar símbolo
    if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) {
        Print("⚠️ ADVERTENCIA: Este EA está optimizado para XAUUSD");
    }
    
    //--- Limpiar objetos
    DeleteAllObjects();
    
    //--- Crear indicadores
    g_EMA_H4_Fast_Handle = iMA(_Symbol, PERIOD_H4, InpEMA_H4_Fast, 0, MODE_EMA, PRICE_CLOSE);
    g_EMA_H4_Slow_Handle = iMA(_Symbol, PERIOD_H4, InpEMA_H4_Slow, 0, MODE_EMA, PRICE_CLOSE);
    g_ATR_H4_Handle = iATR(_Symbol, PERIOD_H4, InpATR_H4);
    g_ATR_H1_Handle = iATR(_Symbol, PERIOD_H1, 14);
    g_ATR_M5_Handle = iATR(_Symbol, PERIOD_M5, 20);
    g_EMA_M5_Handle = iMA(_Symbol, PERIOD_M5, InpEMA_M5, 0, MODE_EMA, PRICE_CLOSE);
    g_EMA_M3_Handle = iMA(_Symbol, PERIOD_M3, InpEMA_M3, 0, MODE_EMA, PRICE_CLOSE);
    
    if(g_EMA_H4_Fast_Handle == INVALID_HANDLE || g_EMA_H4_Slow_Handle == INVALID_HANDLE ||
       g_ATR_H4_Handle == INVALID_HANDLE || g_ATR_H1_Handle == INVALID_HANDLE ||
       g_ATR_M5_Handle == INVALID_HANDLE || g_EMA_M5_Handle == INVALID_HANDLE ||
       g_EMA_M3_Handle == INVALID_HANDLE) {
        Print("❌ Error creando indicadores");
        return INIT_FAILED;
    }
    
    //--- Configurar buffers
    ArraySetAsSeries(g_EMA_H4_Fast_Buffer, true);
    ArraySetAsSeries(g_EMA_H4_Slow_Buffer, true);
    ArraySetAsSeries(g_ATR_H4_Buffer, true);
    ArraySetAsSeries(g_ATR_H1_Buffer, true);
    ArraySetAsSeries(g_ATR_M5_Buffer, true);
    ArraySetAsSeries(g_EMA_M5_Buffer, true);
    ArraySetAsSeries(g_EMA_M3_Buffer, true);
    
    //--- Inicializar estructuras
    ResetPosition(g_Position);
    InitDailyStats();
    
    //--- Crear paneles
    CreateCompliancePanel();
    
    //--- Mostrar configuración
    Print("✅ CONFIGURACIÓN PARA FONDOS DE FONDEO:");
    Print("   💰 Riesgo por trade: ", InpRiskPercent, "%");
    Print("   📊 Riesgo diario máx: ", InpMaxDailyRisk, "%");
    Print("   🛑 Drawdown stop: ", InpMaxDrawdownPercent, "%");
    Print("   🎯 Trades/día máx: ", InpMaxTradesPerDay);
    Print("   📈 Target TP min: $", InpMinTP_XAUUSD);
    Print("   ⏰ Horario: ", InpStartHour, ":00 - ", InpEndHour, ":00 VET");
    Print("   🔒 Filtros activos: Tendencia H4, Volatilidad, Noticias");
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("═══════════════════════════════════════════════════════");
    Print("💵 Balance inicial: $", balance);
    Print("🎯 Meta de escalado: $", balance * 40, " (x40)");
    Print("📅 Tiempo estimado: 12 meses");
    Print("═══════════════════════════════════════════════════════");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_EMA_H4_Fast_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_H4_Fast_Handle);
    if(g_EMA_H4_Slow_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_H4_Slow_Handle);
    if(g_ATR_H4_Handle != INVALID_HANDLE) IndicatorRelease(g_ATR_H4_Handle);
    if(g_ATR_H1_Handle != INVALID_HANDLE) IndicatorRelease(g_ATR_H1_Handle);
    if(g_ATR_M5_Handle != INVALID_HANDLE) IndicatorRelease(g_ATR_M5_Handle);
    if(g_EMA_M5_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_M5_Handle);
    if(g_EMA_M3_Handle != INVALID_HANDLE) IndicatorRelease(g_EMA_M3_Handle);
    
    Print("═══════════════════════════════════════════════════════");
    Print("     SKOLL-FVG v3.2 GOLD EDITION - DETENIDO           ");
    Print("═══════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Actualizar estadísticas diarias
    UpdateDailyStats();
    
    //--- Verificar si se alcanzó drawdown máximo
    if(g_Stats.trading_stopped) {
        UpdateCompliancePanel();
        return;
    }
    
    //--- Cerrar posiciones antes de medianoche
    if(InpCloseAllAtNight) {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        if(dt.hour == 23 && dt.min >= 55) {
            CloseAllPositions("End of day");
        }
    }
    
    //--- Gestionar posición activa
    if(g_Position.ticket_tp1 > 0 || g_Position.ticket_tp2 > 0) {
        ManagePosition();
        UpdateCompliancePanel();
        return;
    }
    
    //--- Solo buscar señal en nueva barra H1
    if(!IsNewBar(PERIOD_H1))
        return;
    
    //--- Verificar condiciones básicas
    if(!InpEnableTrading)
        return;
    
    if(!IsValidTradingTime())
        return;
    
    if(g_Stats.trades_today >= InpMaxTradesPerDay) {
        Print("⚠️ Límite de trades diarios alcanzado (", InpMaxTradesPerDay, ")");
        return;
    }
    
    if(InpUseNewsFilter && IsHighImpactNews())
        return;
    
    //--- Buscar señal
    CheckForEntrySignal();
    
    //--- Actualizar panel
    UpdateCompliancePanel();
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
    
    bool valid_vet = (hour_vet >= InpStartHour && hour_vet < InpEndHour);
    
    int start_utc = InpStartHour + 4;
    int end_utc = InpEndHour + 4;
    bool valid_utc = (hour_utc >= start_utc && hour_utc < end_utc);
    
    // No operar viernes después de 15:00 VET
    if(dt.day_of_week == 5 && hour_vet >= 15)
        return false;
    
    return valid_vet || valid_utc;
}

//+------------------------------------------------------------------+
//| Filtro de noticias                                              |
//+------------------------------------------------------------------+
bool IsHighImpactNews()
{
    // Implementación básica - en producción usar calendario económico
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // NFP: primer viernes del mes a las 12:30 UTC
    if(dt.day_of_week == 5 && dt.day <= 7 && dt.hour >= 10 && dt.hour <= 14)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Buscar señal de entrada con todos los filtros                   |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("🔍 ESCANEO NUEVO - ", TimeToString(TimeCurrent()));
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    //--- CAPA 1: Filtro de tendencia H4 doble EMA
    if(InpUseTrendFilter) {
        int trend = CheckTrendH4();
        if(trend == 0) {
            Print("❌ Tendencia H4: No clara (neutral/rango)");
            return;
        }
        Print("✅ Tendencia H4: ", trend > 0 ? "ALCISTA" : "BAJISTA");
    }
    
    //--- CAPA 2: Filtro de volatilidad
    if(!CheckVolatility()) {
        Print("❌ Volatilidad: Insuficiente o compresión extrema");
        return;
    }
    Print("✅ Volatilidad: Adecuada para operar");
    
    //--- CAPA 3: Verificar spread
    double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(spread > InpMaxSpread) {
        Print("❌ Spread muy alto: $", spread, " > $", InpMaxSpread);
        return;
    }
    Print("✅ Spread: $", NormalizeDouble(spread, 2));
    
    //--- CAPA 4: Detectar FVG con tolerancia dinámica
    FVG_Structure fvg;
    if(!DetectFVG_Dynamic(PERIOD_H1, fvg)) {
        Print("❌ FVG: No detectado");
        return;
    }
    
    double close_h1 = iClose(_Symbol, PERIOD_H1, 0);
    if(close_h1 < fvg.lower || close_h1 > fvg.upper) {
        Print("❌ FVG: Precio no cerró dentro");
        return;
    }
    
    bool is_bullish = fvg.is_bullish;
    Print("✅ FVG ", is_bullish ? "ALCISTA" : "BAJISTA");
    Print("   Rango: $", fvg.lower, " - $", fvg.upper);
    Print("   Cierre: $", close_h1);
    
    //--- CAPA 5: Order Block optimizado para oro
    OB_Structure ob;
    if(!DetectOrderBlock_Gold(is_bullish, ob)) {
        Print("❌ Order Block: No encontrado");
        return;
    }
    Print("✅ Order Block válido");
    Print("   Rango: $", ob.lower, " - $", ob.upper);
    Print("   ATR Ratio: ", NormalizeDouble(ob.atr_ratio, 2), "x");
    
    //--- CAPA 6: Overlap
    double overlap = CalculateOverlap(fvg, ob);
    double fvg_size = fvg.upper - fvg.lower;
    
    if(fvg_size > 0 && overlap / fvg_size < InpOB_Overlap) {
        Print("❌ Overlap: ", NormalizeDouble(overlap/fvg_size*100, 1), "% < ", InpOB_Overlap*100, "%");
        return;
    }
    Print("✅ Overlap: ", NormalizeDouble(overlap/fvg_size*100, 1), "%");
    
    //--- CAPA 7: CHOCH basado en swing H1
    if(!DetectCHOCH_SwingH1(is_bullish)) {
        Print("❌ CHOCH: No confirmado");
        return;
    }
    Print("✅ CHOCH: Confirmado");
    
    //--- CAPA 8: Validaciones finales
    double tp_expected = CalculateExpectedTP(ob, is_bullish);
    if(tp_expected < InpMinTP_XAUUSD) {
        Print("❌ TP muy pequeño: $", tp_expected, " < $", InpMinTP_XAUUSD);
        return;
    }
    Print("✅ TP esperado: $", NormalizeDouble(tp_expected, 2));
    
    //--- SEÑAL VÁLIDA
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    Print("🎯 TODAS LAS CONDICIONES CUMPLIDAS");
    Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    if(InpShowFVG) DrawFVG(fvg);
    if(InpShowOB) DrawOB(ob);
    
    if(InpEnableTrading) {
        OpenPosition(is_bullish, ob, fvg);
    }
}

//+------------------------------------------------------------------+
//| Verificar tendencia H4 con doble EMA                            |
//+------------------------------------------------------------------+
int CheckTrendH4()
{
    if(CopyBuffer(g_EMA_H4_Fast_Handle, 0, 0, 2, g_EMA_H4_Fast_Buffer) != 2) return 0;
    if(CopyBuffer(g_EMA_H4_Slow_Handle, 0, 0, 2, g_EMA_H4_Slow_Buffer) != 2) return 0;
    
    double close_h4 = iClose(_Symbol, PERIOD_H4, 0);
    double ema50 = g_EMA_H4_Fast_Buffer[0];
    double ema200 = g_EMA_H4_Slow_Buffer[0];
    
    Print("   Precio H4: $", close_h4);
    Print("   EMA50: $", ema50);
    Print("   EMA200: $", ema200);
    
    // Tendencia alcista: precio > EMA50 Y EMA50 > EMA200
    if(close_h4 > ema50 && ema50 > ema200)
        return 1;
    
    // Tendencia bajista: precio < EMA50 Y EMA50 < EMA200
    if(close_h4 < ema50 && ema50 < ema200)
        return -1;
    
    return 0; // Neutral
}

//+------------------------------------------------------------------+
//| Verificar volatilidad con ATR                                   |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
    if(CopyBuffer(g_ATR_H4_Handle, 0, 0, 1, g_ATR_H4_Buffer) != 1) return false;
    if(CopyBuffer(g_ATR_H1_Handle, 0, 0, 1, g_ATR_H1_Buffer) != 1) return false;
    
    double atr_h4 = g_ATR_H4_Buffer[0];
    double atr_h1 = g_ATR_H1_Buffer[0];
    
    Print("   ATR H4: $", NormalizeDouble(atr_h4, 2));
    Print("   ATR H1: $", NormalizeDouble(atr_h1, 2));
    Print("   Ratio H1/H4: ", NormalizeDouble(atr_h1/atr_h4, 2));
    
    // Mercado debe estar vivo
    if(atr_h4 < InpMinATR_H4)
        return false;
    
    // No operar en compresión extrema
    if(atr_h1 < atr_h4 * InpATR_Compression)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detectar FVG con tolerancia dinámica                            |
//+------------------------------------------------------------------+
bool DetectFVG_Dynamic(ENUM_TIMEFRAMES timeframe, FVG_Structure &fvg)
{
    if(iBars(_Symbol, timeframe) < 3) return false;
    
    // Obtener ATR H1 para tolerancia dinámica
    if(CopyBuffer(g_ATR_H1_Handle, 0, 0, 1, g_ATR_H1_Buffer) != 1) return false;
    double atr_h1 = g_ATR_H1_Buffer[0];
    
    // Tolerancia dinámica: max(base, ATR * multiplier)
    double tolerance = MathMax(InpFVG_BaseToleranceXAU, atr_h1 * InpFVG_ATR_Multiplier);
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(_Symbol, timeframe, 1, 3, high) != 3) return false;
    if(CopyLow(_Symbol, timeframe, 1, 3, low) != 3) return false;
    
    // FVG Alcista
    if(low[0] > high[2] + tolerance) {
        fvg.time = iTime(_Symbol, timeframe, 1);
        fvg.upper = low[0];
        fvg.lower = high[2];
        fvg.is_bullish = true;
        fvg.is_active = true;
        return true;
    }
    // FVG Bajista
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
//| Detectar Order Block optimizado para oro                        |
//+------------------------------------------------------------------+
bool DetectOrderBlock_Gold(bool look_for_bullish, OB_Structure &ob)
{
    if(CopyBuffer(g_ATR_M5_Handle, 0, 0, 50, g_ATR_M5_Buffer) != 50) return false;
    if(CopyBuffer(g_EMA_M5_Handle, 0, 0, 50, g_EMA_M5_Buffer) != 50) return false;
    
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
        double range = high[i] - low[i];
        double atr_m5 = g_ATR_M5_Buffer[i];
        double ema_m5 = g_EMA_M5_Buffer[i];
        
        // Validar rango significativo
        if(range < atr_m5 * InpOB_ATR_Multiplier)
            continue;
        
        if(look_for_bullish) {
            // Cierre en tercio superior (≥66%)
            double closure_level = (close[i] - low[i]) / range;
            
            if(closure_level >= InpOB_ClosureThreshold && close[i] > ema_m5) {
                // Confirmación de impulso
                if(close[i-1] > high[i] && close[i-2] > high[i]) {
                    ob.time = iTime(_Symbol, PERIOD_M5, i);
                    ob.upper = high[i];
                    ob.lower = low[i];
                    ob.is_bullish = true;
                    ob.is_valid = true;
                    ob.atr_ratio = range / atr_m5;
                    return true;
                }
            }
        } else {
            // Cierre en tercio inferior (≤34%)
            double closure_level = (close[i] - low[i]) / range;
            
            if(closure_level <= (1.0 - InpOB_ClosureThreshold) && close[i] < ema_m5) {
                if(close[i-1] < low[i] && close[i-2] < low[i]) {
                    ob.time = iTime(_Symbol, PERIOD_M5, i);
                    ob.upper = high[i];
                    ob.lower = low[i];
                    ob.is_bullish = false;
                    ob.is_valid = true;
                    ob.atr_ratio = range / atr_m5;
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detectar CHOCH basado en swing H1                               |
//+------------------------------------------------------------------+
bool DetectCHOCH_SwingH1(bool look_for_bullish)
{
    // Obtener datos H1 para detectar swing
    double high_h1[], low_h1[];
    ArraySetAsSeries(high_h1, true);
    ArraySetAsSeries(low_h1, true);
    
    if(CopyHigh(_Symbol, PERIOD_H1, 0, 50, high_h1) != 50) return false;
    if(CopyLow(_Symbol, PERIOD_H1, 0, 50, low_h1) != 50) return false;
    
    // Obtener datos M5 para confirmación
    double close_m5[];
    ArraySetAsSeries(close_m5, true);
    
    if(CopyClose(_Symbol, PERIOD_M5, 0, 10, close_m5) != 10) return false;
    if(CopyBuffer(g_EMA_M5_Handle, 0, 0, 10, g_EMA_M5_Buffer) != 10) return false;
    
    // Tolerancia dinámica
    if(CopyBuffer(g_ATR_H1_Handle, 0, 0, 1, g_ATR_H1_Buffer) != 1) return false;
    double tolerance = MathMax(InpCHOCH_BaseToleranceXAU, g_ATR_H1_Buffer[0] * InpCHOCH_ATR_Multiplier);
    
    double current_close = close_m5[0];
    double current_ema = g_EMA_M5_Buffer[0];
    
    if(look_for_bullish) {
        // Buscar último swing high en H1
        double last_swing_high = 0;
        
        for(int i = 2; i < 48; i++) {
            if(high_h1[i] > high_h1[i-1] && high_h1[i] > high_h1[i-2] &&
               high_h1[i] > high_h1[i+1] && high_h1[i] > high_h1[i+2]) {
                last_swing_high = high_h1[i];
                Print("   Swing High H1: $", last_swing_high, " (barra ", i, ")");
                break;
            }
        }
        
        if(last_swing_high == 0) return false;
        
        if(current_close > last_swing_high + tolerance && current_close > current_ema) {
            Print("   Cierre M5: $", current_close);
            Print("   EMA20 M5: $", current_ema);
            return true;
        }
        
    } else {
        // Buscar último swing low en H1
        double last_swing_low = 999999;
        
        for(int i = 2; i < 48; i++) {
            if(low_h1[i] < low_h1[i-1] && low_h1[i] < low_h1[i-2] &&
               low_h1[i] < low_h1[i+1] && low_h1[i] < low_h1[i+2]) {
                last_swing_low = low_h1[i];
                Print("   Swing Low H1: $", last_swing_low, " (barra ", i, ")");
                break;
            }
        }
        
        if(last_swing_low == 999999) return false;
        
        if(current_close < last_swing_low - tolerance && current_close < current_ema) {
            Print("   Cierre M5: $", current_close);
            Print("   EMA20 M5: $", current_ema);
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
//| Calcular TP esperado                                            |
//+------------------------------------------------------------------+
double CalculateExpectedTP(const OB_Structure &ob, bool is_buy)
{
    double range = ob.upper - ob.lower;
    double tp = range * InpTP2_Ratio;
    return tp;
}

//+------------------------------------------------------------------+
//| Abrir posición con gestión de riesgo para fondos                |
//+------------------------------------------------------------------+
void OpenPosition(bool is_buy, const OB_Structure &ob, const FVG_Structure &fvg)
{
    double price = SymbolInfoDouble(_Symbol, is_buy ? SYMBOL_ASK : SYMBOL_BID);
    double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // SL inteligente con buffer de spread
    double sl_buffer = MathMax(0.5, 0.6 * spread);
    double sl = is_buy ? ob.lower - sl_buffer : ob.upper + sl_buffer;
    double risk = MathAbs(price - sl);
    
    // TPs
    double tp1 = is_buy ? price + risk * InpTP1_Ratio : price - risk * InpTP1_Ratio;
    double tp2 = is_buy ? price + risk * InpTP2_Ratio : price - risk * InpTP2_Ratio;
    
    // Validar riesgo diario
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_money = balance * InpRiskPercent / 100.0;
    double max_daily = balance * InpMaxDailyRisk / 100.0;
    
    if(g_Stats.daily_pnl < 0 && MathAbs(g_Stats.daily_pnl) + risk_money > max_daily) {
        Print("❌ Riesgo diario excedido");
        return;
    }
    
    // Calcular volumen dinámico
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
        return;
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
    g_Position.open_time = TimeCurrent();
    g_Position.entry_price = price;
    g_Position.sl = sl;
    g_Position.tp1 = tp1;
    g_Position.tp2 = tp2;
    g_Position.tp1_hit = false;
    g_Position.moved_to_be = false;
    
    g_Stats.trades_today++;
    
    Print("══════════════════════════════════════════════════════");
    Print("🚀 POSICIÓN ABIERTA - ", is_buy ? "COMPRA" : "VENTA");
    Print("══════════════════════════════════════════════════════");
    Print("📍 Entrada: $", price);
    Print("🛑 SL: $", sl, " (riesgo: $", NormalizeDouble(risk, 2), ")");
    Print("🎯 TP1 (1R): $", tp1);
    Print("🎯 TP2 (2R): $", tp2);
    Print("💰 Volumen: ", volume);
    Print("💵 Riesgo: $", NormalizeDouble(risk_money, 2));
    Print("📊 Potencial: $", NormalizeDouble(risk_money * 2, 2));
    Print("📈 Trades hoy: ", g_Stats.trades_today, "/", InpMaxTradesPerDay);
    Print("══════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Gestionar posición con breakeven                                |
//+------------------------------------------------------------------+
void ManagePosition()
{
    // Verificar anti-scalping
    if(InpAntiScalping) {
        int duration = (int)((TimeCurrent() - g_Position.open_time) / 60);
        if(duration < InpMinTradeDuration) {
            // Trade muy nuevo, esperar
            return;
        }
    }
    
    // TP1 hit
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
                        Print("✅ BREAKEVEN activado en TP2");
                    }
                }
            }
        }
    }
    
    // TP2 completo
    if(g_Position.ticket_tp2 > 0) {
        if(!PositionSelectByTicket(g_Position.ticket_tp2)) {
            Print("✅ TP2 ALCANZADO - Trade cerrado");
            ResetPosition(g_Position);
        }
    } else {
        ResetPosition(g_Position);
    }
}

//+------------------------------------------------------------------+
//| Cerrar todas las posiciones                                     |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    if(g_Position.ticket_tp1 > 0) {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        if(PositionSelectByTicket(g_Position.ticket_tp1)) {
            request.action = TRADE_ACTION_DEAL;
            request.position = g_Position.ticket_tp1;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            OrderSend(request, result);
        }
    }
    
    if(g_Position.ticket_tp2 > 0) {
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        if(PositionSelectByTicket(g_Position.ticket_tp2)) {
            request.action = TRADE_ACTION_DEAL;
            request.position = g_Position.ticket_tp2;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            OrderSend(request, result);
        }
    }
    
    Print("🔒 Posiciones cerradas: ", reason);
    ResetPosition(g_Position);
}

//+------------------------------------------------------------------+
//| Actualizar estadísticas diarias                                 |
//+------------------------------------------------------------------+
void UpdateDailyStats()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime current_date = StringToTime(IntegerToString(dt.year) + "." + 
                                         IntegerToString(dt.mon) + "." + 
                                         IntegerToString(dt.day));
    
    // Nueva día
    if(g_Stats.date != current_date) {
        InitDailyStats();
    }
    
    // Actualizar equity peak
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity > g_Stats.peak_equity) {
        g_Stats.peak_equity = equity;
    }
    
    // Calcular drawdown
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_Stats.current_drawdown = ((g_Stats.peak_equity - equity) / balance) * 100.0;
    
    // Detener trading si drawdown excede límite
    if(g_Stats.current_drawdown >= InpMaxDrawdownPercent && !g_Stats.trading_stopped) {
        g_Stats.trading_stopped = true;
        CloseAllPositions("Drawdown limit reached");
        Print("🛑 TRADING DETENIDO - Drawdown: ", NormalizeDouble(g_Stats.current_drawdown, 2), "%");
    }
    
    // Calcular P&L diario
    g_Stats.daily_pnl = equity - balance;
}

//+------------------------------------------------------------------+
//| Inicializar estadísticas diarias                                |
//+------------------------------------------------------------------+
void InitDailyStats()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    g_Stats.date = StringToTime(IntegerToString(dt.year) + "." + 
                                 IntegerToString(dt.mon) + "." + 
                                 IntegerToString(dt.day));
    g_Stats.trades_today = 0;
    g_Stats.daily_pnl = 0;
    g_Stats.peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_Stats.current_drawdown = 0;
    g_Stats.trading_stopped = false;
}

//+------------------------------------------------------------------+
//| Verificar nueva barra                                           |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    static datetime last_time = 0;
    datetime current_time = iTime(_Symbol, timeframe, 0);
    
    if(current_time != last_time) {
        last_time = current_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Crear panel de cumplimiento                                     |
//+------------------------------------------------------------------+
void CreateCompliancePanel()
{
    if(!InpShowCompliancePanel) return;
    
    string name = "COMPLIANCE_PANEL";
    if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
        ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
    }
}

//+------------------------------------------------------------------+
//| Actualizar panel de cumplimiento                                |
//+------------------------------------------------------------------+
void UpdateCompliancePanel()
{
    if(!InpShowCompliancePanel) return;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    color panel_color = g_Stats.trading_stopped ? clrRed : clrLime;
    
    string text = "═══ SKOLL GOLD v3.2 ═══\n";
    text += "💰 Balance: $" + DoubleToString(balance, 2) + "\n";
    text += "📊 Equity: $" + DoubleToString(equity, 2) + "\n";
    text += "📉 DD: " + DoubleToString(g_Stats.current_drawdown, 2) + "%\n";
    text += "📈 Trades: " + IntegerToString(g_Stats.trades_today) + "/" + IntegerToString(InpMaxTradesPerDay) + "\n";
    text += "💵 P&L: $" + DoubleToString(g_Stats.daily_pnl, 2) + "\n";
    text += "🎯 Status: " + (g_Stats.trading_stopped ? "STOPPED" : "ACTIVE");
    
    ObjectSetString(0, "COMPLIANCE_PANEL", OBJPROP_TEXT, text);
    ObjectSetInteger(0, "COMPLIANCE_PANEL", OBJPROP_COLOR, panel_color);
}

//+------------------------------------------------------------------+
//| Dibujar FVG                                                      |
//+------------------------------------------------------------------+
void DrawFVG(const FVG_Structure &fvg)
{
    string name = "FVG_" + IntegerToString(g_FVGCounter++);
    datetime time2 = iTime(_Symbol, PERIOD_H1, 0) + PeriodSeconds(PERIOD_H1) * 10;
    
    if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, fvg.time, fvg.lower, time2, fvg.upper)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, fvg.is_bullish ? clrDodgerBlue : clrOrangeRed);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}

//+------------------------------------------------------------------+
//| Dibujar Order Block                                             |
//+------------------------------------------------------------------+
void DrawOB(const OB_Structure &ob)
{
    string name = "OB_" + IntegerToString(g_OBCounter++);
    datetime time2 = iTime(_Symbol, PERIOD_M5, 0) + PeriodSeconds(PERIOD_M5) * 20;
    
    if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, ob.time, ob.lower, time2, ob.upper)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, ob.is_bullish ? clrLimeGreen : clrTomato);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
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
           StringFind(name, "COMPLIANCE_") == 0) {
            ObjectDelete(0, name);
        }
    }
}

//+------------------------------------------------------------------+
//| Reset position                                                   |
//+------------------------------------------------------------------+
void ResetPosition(Position_Info &pos)
{
    pos.ticket_tp1 = 0;
    pos.ticket_tp2 = 0;
    pos.open_time = 0;
    pos.entry_price = 0;
    pos.sl = 0;
    pos.tp1 = 0;
    pos.tp2 = 0;
    pos.tp1_hit = false;
    pos.moved_to_be = false;
}
//+------------------------------------------------------------------+
