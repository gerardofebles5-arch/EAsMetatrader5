//+------------------------------------------------------------------+
//|                                                  Pyramis_EA.mq5  |
//|                   ESTRATEGIA PYRAMIS v1.0                        |
//|   ICT Silver Bullet + Volume Profile + FSM + Pyramiding         |
//|                                                                  |
//|  MERCADOS:  NASDAQ (NAS100/NQ) | Petróleo (USOIL/WTI)          |
//|  HORARIO:   9:44 AM - 12:00 PM (Hora Venezuela, UTC-4)          |
//|  WINRATE:   ~50.75% | RR: 1:2 | Pyramiding activo              |
//+------------------------------------------------------------------+
#property copyright  "Pyramis Strategy — Basada en ICT Silver Bullet"
#property version    "1.00"
#property description "Estrategia Pyramis: FSM con ICT Silver Bullet, Volume Profile y Pyramiding"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//============================================================
//  PARÁMETROS DE ENTRADA
//============================================================

input group "═══════════ GESTIÓN DE RIESGO ═══════════"
input double   InpRiskPercent       = 1.0;    // Riesgo macro (% del balance)
input double   InpScaleRiskPercent  = 0.5;    // Riesgo scale-in (% del balance)
input double   InpRR_Target         = 2.0;    // Ratio R:R objetivo
input int      InpMaxDailyTrades    = 2;      // Máximo de operaciones por día

input group "═══════════ ATR Y STOPS ═══════════"
input int      InpATR_Period        = 14;     // Período del ATR
input double   InpATR_Mult_NQ       = 1.5;    // Multiplicador ATR para NQ/NAS100
input double   InpATR_Mult_WTI      = 1.2;    // Multiplicador ATR para WTI/USOIL
input bool     InpUseTrailingStop   = true;   // Usar trailing stop dinámico

input group "═══════════ HORARIO VENEZUELA (UTC-4) ═══════════"
input int      InpStartHour         = 9;      // Hora inicio ventana (Venezuela)
input int      InpStartMin          = 44;     // Minuto inicio ventana
input int      InpEndHour           = 12;     // Hora fin ventana
input int      InpEndMin            = 0;      // Minuto fin
input int      InpBrokerOffset      = 0;      // Offset broker vs UTC en horas (ej: 2 para UTC+2)

input group "═══════════ DETECCIÓN FVG / VOID ═══════════"
input int      InpFVG_Lookback      = 10;     // Barras para buscar FVG en H1
input double   InpFVG_MinSize       = 5.0;    // Tamaño mínimo FVG en puntos
input bool     InpUseH4_FVG         = true;   // También buscar FVGs en H4

input group "═══════════ ORDER BLOCKS ═══════════"
input int      InpOB_Lookback       = 15;     // Barras para buscar OB en M5
input double   InpOB_ImpulseRatio   = 1.3;    // Ratio para considerar impulso fuerte

input group "═══════════ EMAs ═══════════"
input int      InpEMA_Fast          = 20;     // EMA rápida
input int      InpEMA_Mid           = 50;     // EMA media
input int      InpEMA_Slow          = 200;    // EMA lenta

input group "═══════════ RSI (Anomalía de Momentum) ═══════════"
input int      InpRSI_Period        = 14;     // Período RSI
input double   InpRSI_BullThresh    = 60.0;   // RSI mínimo para confirmar momentum alcista
input double   InpRSI_BearThresh    = 40.0;   // RSI máximo para confirmar momentum bajista

input group "═══════════ CONTROL GENERAL ═══════════"
input bool     InpTradeEnabled      = true;   // Trading habilitado (Master Switch)
input bool     InpSkipFirstCandle   = true;   // Ignorar primera vela NY (9:30-9:44)
input int      InpMagicNumber       = 202501; // Número mágico único
input string   InpComment           = "PYRAMIS";  // Comentario en operaciones
input bool     InpPrintDebug        = true;   // Imprimir logs detallados

//============================================================
//  ENUMERACIONES — MÁQUINA DE ESTADOS FINITOS (FSM)
//============================================================

enum EFSM_STATE {
    FSM_IDLE          = 0,   // Estado 0: Evaluación y búsqueda
    FSM_VOID_FOUND    = 1,   // Estado 1: FVG/Void detectado en H1/H4
    FSM_H1_CONFIRMED  = 2,   // Estado 2: Vela H1 cerrada en zona del void
    FSM_M3_BREAK      = 3,   // Estado 3: Quiebre de estructura en M3
    FSM_MACRO_ENTRY   = 4,   // Estado 4: Posición macro activa
    FSM_PYRAMIDING    = 5,   // Estado 5: Condición de pyramiding alcanzada
    FSM_MONITORING    = 6    // Estado 6: Monitoreo de ambas posiciones
};

enum ETRADE_DIR {
    DIR_NONE  =  0,
    DIR_LONG  =  1,
    DIR_SHORT = -1
};

//============================================================
//  ESTRUCTURA PARA FVG
//============================================================
struct SFVG {
    double     high;
    double     low;
    ETRADE_DIR direction;
    datetime   time;
    bool       valid;
};

//============================================================
//  VARIABLES GLOBALES
//============================================================

CTrade         g_trade;
CPositionInfo  g_position;
CSymbolInfo    g_symbol;

// --- Estado FSM ---
EFSM_STATE     g_state           = FSM_IDLE;
ETRADE_DIR     g_direction       = DIR_NONE;

// --- Datos del setup ---
SFVG           g_activeFVG;
double         g_obHigh          = 0;
double         g_obLow           = 0;

// --- Datos de posiciones ---
ulong          g_macroTicket     = 0;
ulong          g_scaleTicket     = 0;
double         g_macroEntry      = 0;
double         g_macroSL         = 0;
double         g_macroTP         = 0;
double         g_oneR_Monetary   = 0;  // 1R en dinero para trigger de pyramiding

// --- Control de barras ---
datetime       g_lastH1Bar       = 0;
datetime       g_lastM3Bar       = 0;

// --- Control de sesión ---
bool           g_scalingDone     = false;
int            g_dailyTrades     = 0;
datetime       g_lastTradeDay    = 0;
bool           g_m3BreakDetected = false;

// --- Handles de indicadores ---
int            h_ATR_M15, h_RSI_H1;
int            h_EMA20_H1, h_EMA50_H1, h_EMA200_H1;
int            h_EMA20_M3;

//============================================================
//  INICIALIZACIÓN
//============================================================
int OnInit() {
    g_symbol.Name(Symbol());
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints(30);
    g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    g_trade.SetAsyncMode(false);
    g_trade.LogLevel(LOG_LEVEL_ERRORS);

    // Inicializar handles
    h_ATR_M15    = iATR(Symbol(), PERIOD_M15, InpATR_Period);
    h_RSI_H1     = iRSI(Symbol(), PERIOD_H1,  InpRSI_Period, PRICE_CLOSE);
    h_EMA20_H1   = iMA(Symbol(),  PERIOD_H1,  InpEMA_Fast,   0, MODE_EMA, PRICE_CLOSE);
    h_EMA50_H1   = iMA(Symbol(),  PERIOD_H1,  InpEMA_Mid,    0, MODE_EMA, PRICE_CLOSE);
    h_EMA200_H1  = iMA(Symbol(),  PERIOD_H1,  InpEMA_Slow,   0, MODE_EMA, PRICE_CLOSE);
    h_EMA20_M3   = iMA(Symbol(),  PERIOD_M3,  InpEMA_Fast,   0, MODE_EMA, PRICE_CLOSE);

    if(h_ATR_M15 == INVALID_HANDLE || h_RSI_H1 == INVALID_HANDLE ||
       h_EMA20_H1 == INVALID_HANDLE || h_EMA50_H1 == INVALID_HANDLE ||
       h_EMA200_H1 == INVALID_HANDLE || h_EMA20_M3 == INVALID_HANDLE) {
        Alert("PYRAMIS EA: Error creando handles de indicadores!");
        return INIT_FAILED;
    }

    ResetFSM();
    PrintDebug("=== PYRAMIS EA v1.0 INICIADO ===");
    PrintDebug("Símbolo: " + Symbol());
    PrintDebug("Magic: " + IntegerToString(InpMagicNumber));
    PrintDebug("Ventana: " + IntegerToString(InpStartHour) + ":" +
               (InpStartMin < 10 ? "0" : "") + IntegerToString(InpStartMin) +
               " - " + IntegerToString(InpEndHour) + ":00 (Venezuela UTC-4)");

    return INIT_SUCCEEDED;
}

//============================================================
//  DESINICIALIZACIÓN
//============================================================
void OnDeinit(const int reason) {
    IndicatorRelease(h_ATR_M15);
    IndicatorRelease(h_RSI_H1);
    IndicatorRelease(h_EMA20_H1);
    IndicatorRelease(h_EMA50_H1);
    IndicatorRelease(h_EMA200_H1);
    IndicatorRelease(h_EMA20_M3);
    PrintDebug("=== PYRAMIS EA DETENIDO (razón: " + IntegerToString(reason) + ") ===");
}

//============================================================
//  TICK PRINCIPAL — DESPACHO DE LA FSM
//============================================================
void OnTick() {
    if(!InpTradeEnabled) return;
    g_symbol.RefreshRates();

    // Resetear contador diario
    CheckDailyReset();

    // Ejecutar estado actual de la FSM
    switch(g_state) {
        case FSM_IDLE:          State_Idle();         break;
        case FSM_VOID_FOUND:    State_VoidFound();    break;
        case FSM_H1_CONFIRMED:  State_H1Confirmed();  break;
        case FSM_M3_BREAK:      State_M3Break();      break;
        case FSM_MACRO_ENTRY:   State_MacroEntry();   break;
        case FSM_PYRAMIDING:    State_Pyramiding();   break;
        case FSM_MONITORING:    State_Monitoring();   break;
    }
}

//============================================================
//  ESTADO 0: IDLE — Evaluación y búsqueda
//============================================================
void State_Idle() {
    // Guard: ventana horaria
    if(!IsInTradingWindow()) return;

    // Guard: límite diario de trades
    if(g_dailyTrades >= InpMaxDailyTrades) return;

    // Guard: no operar si ya hay posiciones abiertas
    if(CountOpenPositions() > 0) return;

    // Condición 1: EMAs alineadas en H1
    ETRADE_DIR emaDir = GetEMADirection();
    if(emaDir == DIR_NONE) return;

    // Condición 2: RSI confirma momentum (no sobrecompra/sobreventa, sino anomalía)
    if(!ConfirmRSI_Momentum(emaDir)) return;

    // Condición 3: Detectar FVG/Void en H1 (y opcionalmente H4)
    SFVG foundFVG;
    foundFVG.valid = false;

    if(DetectFVG(PERIOD_H1, InpFVG_Lookback, foundFVG) && foundFVG.direction == emaDir) {
        g_activeFVG = foundFVG;
        g_direction = emaDir;
        g_state     = FSM_VOID_FOUND;
        PrintDebug("FSM[IDLE→VOID_FOUND] | Dir:" + (g_direction==DIR_LONG?"LONG":"SHORT") +
                   " | Void:" + DoubleToString(g_activeFVG.low,_Digits) +
                   "-" + DoubleToString(g_activeFVG.high,_Digits));
        return;
    }

    // Buscar en H4 también si está habilitado
    if(InpUseH4_FVG && DetectFVG(PERIOD_H4, 5, foundFVG) && foundFVG.direction == emaDir) {
        g_activeFVG = foundFVG;
        g_direction = emaDir;
        g_state     = FSM_VOID_FOUND;
        PrintDebug("FSM[IDLE→VOID_FOUND H4] | Dir:" + (g_direction==DIR_LONG?"LONG":"SHORT"));
        return;
    }
}

//============================================================
//  ESTADO 1: VOID FOUND — Esperar cierre de vela H1 en zona
//============================================================
void State_VoidFound() {
    // Guard: ventana horaria
    if(!IsInTradingWindow()) { ResetFSM(); return; }

    // Solo procesar al cierre de cada vela H1
    datetime currentH1 = iTime(Symbol(), PERIOD_H1, 0);
    if(currentH1 == g_lastH1Bar) return;
    g_lastH1Bar = currentH1;

    // Leer la vela H1 que ACABA de cerrar (índice 1)
    double h1_close = iClose(Symbol(), PERIOD_H1, 1);
    double h1_high  = iHigh(Symbol(),  PERIOD_H1, 1);
    double h1_low   = iLow(Symbol(),   PERIOD_H1, 1);

    bool confirmed = false;

    if(g_direction == DIR_LONG) {
        // La vela H1 tocó el void bajista y cerró dentro o por encima de él
        // (precio entró en la zona de desequilibrio)
        confirmed = (h1_low  <= g_activeFVG.high + InpFVG_MinSize * _Point) &&
                    (h1_close >= g_activeFVG.low);
    } else if(g_direction == DIR_SHORT) {
        // La vela H1 tocó el void alcista y cerró dentro o por debajo de él
        confirmed = (h1_high >= g_activeFVG.low  - InpFVG_MinSize * _Point) &&
                    (h1_close <= g_activeFVG.high);
    }

    if(confirmed) {
        g_state = FSM_H1_CONFIRMED;
        PrintDebug("FSM[VOID_FOUND→H1_CONFIRMED] | H1 cerró en zona del vacío");
    } else {
        // Invalidar si el precio pasó completamente el void
        if(g_direction == DIR_LONG && h1_close < g_activeFVG.low - 20*_Point)  { ResetFSM(); }
        if(g_direction == DIR_SHORT && h1_close > g_activeFVG.high + 20*_Point) { ResetFSM(); }
        // Invalidar si pasó la ventana
        if(!IsInTradingWindow()) ResetFSM();
    }
}

//============================================================
//  ESTADO 2: H1 CONFIRMED — Buscar quiebre de estructura en M3
//============================================================
void State_H1Confirmed() {
    if(!IsInTradingWindow()) { ResetFSM(); return; }

    // Detectar quiebre de estructura en M3
    if(DetectStructureBreak_M3()) {
        g_m3BreakDetected = true;
        g_state = FSM_M3_BREAK;
        PrintDebug("FSM[H1_CONFIRMED→M3_BREAK] | Quiebre estructural confirmado en M3");
    }
}

//============================================================
//  ESTADO 3: M3 BREAK — Identificar Order Block en M5
//============================================================
void State_M3Break() {
    if(!IsInTradingWindow()) { ResetFSM(); return; }

    double obH = 0, obL = 0;
    if(DetectOrderBlock_M5(obH, obL)) {
        g_obHigh = obH;
        g_obLow  = obL;
        PrintDebug("FSM[M3_BREAK→MACRO_ENTRY] | OB en M5: " +
                   DoubleToString(g_obLow,_Digits) + " - " + DoubleToString(g_obHigh,_Digits));
        g_state = FSM_MACRO_ENTRY;
        ExecuteMacroEntry();
    }
}

//============================================================
//  ESTADO 4: MACRO ENTRY — Monitorear posición base
//============================================================
void State_MacroEntry() {
    if(!PositionExistsByTicket(g_macroTicket)) {
        PrintDebug("FSM: Posición macro cerrada externamente. Reset.");
        ResetFSM();
        return;
    }

    // Verificar si alcanzó +1R para activar pyramiding
    if(!g_scalingDone) {
        double profit = GetPositionProfit(g_macroTicket);
        if(profit >= g_oneR_Monetary) {
            MoveSLtoBreakEven(g_macroTicket, g_macroEntry);
            g_state = FSM_PYRAMIDING;
            PrintDebug("FSM[MACRO_ENTRY→PYRAMIDING] | +1R alcanzado ($" +
                       DoubleToString(profit,2) + ") | SL→BE");
        }
    }

    // Cerrar si salimos de la ventana y la posición no llegó a pyramiding
    if(!IsInTradingWindow() && !g_scalingDone) {
        PrintDebug("Ventana cerrada con posición abierta. Continuando hasta TP/SL.");
    }
}

//============================================================
//  ESTADO 5: PYRAMIDING — Buscar retroceso para Scale-In
//============================================================
void State_Pyramiding() {
    if(g_scalingDone) {
        g_state = FSM_MONITORING;
        return;
    }

    // Verificar que la macro sigue abierta
    if(!PositionExistsByTicket(g_macroTicket)) {
        ResetFSM();
        return;
    }

    // Buscar pullback en EMA20 en M3 para el scale-in
    if(IsPullbackAtEMA_M3()) {
        ExecuteScaleEntry();
        g_scalingDone = true;
        g_state = FSM_MONITORING;
        PrintDebug("FSM[PYRAMIDING→MONITORING] | Scale-In ejecutado");
    }
}

//============================================================
//  ESTADO 6: MONITORING — Gestión activa de ambas posiciones
//============================================================
void State_Monitoring() {
    bool macroOpen = PositionExistsByTicket(g_macroTicket);
    bool scaleOpen = (g_scaleTicket > 0) && PositionExistsByTicket(g_scaleTicket);

    if(!macroOpen && !scaleOpen) {
        PrintDebug("FSM[MONITORING]: Todas las posiciones cerradas. Ciclo completo.");
        g_dailyTrades++;
        ResetFSM();
        return;
    }

    // Aplicar trailing stop dinámico basado en ATR
    if(InpUseTrailingStop) {
        if(macroOpen) ApplyTrailingStop(g_macroTicket);
        if(scaleOpen) ApplyTrailingStop(g_scaleTicket);
    }
}

//============================================================
//  EJECUCIÓN: ENTRADA MACRO (1% del balance)
//============================================================
void ExecuteMacroEntry() {
    double ask = g_symbol.Ask();
    double bid = g_symbol.Bid();
    double spread = ask - bid;

    // Obtener ATR para cálculo del stop
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_ATR_M15, 0, 0, 3, atr) < 0) {
        PrintDebug("Error obteniendo ATR para macro entry");
        ResetFSM();
        return;
    }

    double atrMult = IsNQSymbol() ? InpATR_Mult_NQ : InpATR_Mult_WTI;
    double entryPrice, slPrice, tpPrice;

    if(g_direction == DIR_LONG) {
        entryPrice = ask;
        // SL: detrás del OB bajo, con buffer ATR
        slPrice    = g_obLow - atr[0] * atrMult;
        tpPrice    = entryPrice + (entryPrice - slPrice) * InpRR_Target;
    } else {
        entryPrice = bid;
        // SL: encima del OB alto, con buffer ATR
        slPrice    = g_obHigh + atr[0] * atrMult;
        tpPrice    = entryPrice - (slPrice - entryPrice) * InpRR_Target;
    }

    // Normalizar precios
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    slPrice    = NormalizeDouble(slPrice, digits);
    tpPrice    = NormalizeDouble(tpPrice, digits);

    // Calcular tamaño de lote (1% del balance)
    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount   = balance * InpRiskPercent / 100.0;
    double slDistance   = MathAbs(entryPrice - slPrice);
    double lotSize      = CalcLotSize(riskAmount, slDistance);

    if(lotSize <= 0) {
        PrintDebug("Error: Lote calculado inválido (" + DoubleToString(lotSize,2) + ")");
        ResetFSM();
        return;
    }

    // Guardar datos para gestión posterior
    g_macroEntry      = entryPrice;
    g_macroSL         = slPrice;
    g_macroTP         = tpPrice;
    g_oneR_Monetary   = riskAmount;

    // Ejecutar orden
    bool result = false;
    if(g_direction == DIR_LONG)
        result = g_trade.Buy(lotSize, Symbol(), 0, slPrice, tpPrice, InpComment + "_MACRO");
    else
        result = g_trade.Sell(lotSize, Symbol(), 0, slPrice, tpPrice, InpComment + "_MACRO");

    if(result && g_trade.ResultOrder() > 0) {
        g_macroTicket = g_trade.ResultOrder();
        PrintDebug("✅ MACRO ENTRY | Ticket:" + IntegerToString(g_macroTicket) +
                   " | Dir:" + (g_direction==DIR_LONG?"BUY":"SELL") +
                   " | Lot:" + DoubleToString(lotSize,2) +
                   " | Entry:" + DoubleToString(entryPrice,digits) +
                   " | SL:" + DoubleToString(slPrice,digits) +
                   " | TP:" + DoubleToString(tpPrice,digits) +
                   " | Riesgo:$" + DoubleToString(riskAmount,2));
    } else {
        PrintDebug("❌ ERROR MACRO ENTRY: " + IntegerToString(g_trade.ResultRetcode()) +
                   " - " + g_trade.ResultRetcodeDescription());
        ResetFSM();
    }
}

//============================================================
//  EJECUCIÓN: SCALE-IN PYRAMIDING (0.5% del balance)
//============================================================
void ExecuteScaleEntry() {
    double ask = g_symbol.Ask();
    double bid = g_symbol.Bid();

    // SL estructural en M3 para el scale
    double scaleSL = CalculateScaleSL_M3();
    double entryP  = (g_direction == DIR_LONG) ? ask : bid;

    // TP idéntico al de la macro
    double scaleTP = g_macroTP;

    // Calcular lote para 0.5% del balance
    double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * InpScaleRiskPercent / 100.0;
    double slDist     = MathAbs(entryP - scaleSL);
    double lotSize    = CalcLotSize(riskAmount, slDist);

    if(lotSize <= 0) {
        PrintDebug("Error en cálculo de lote para scale-in");
        return;
    }

    bool result = false;
    if(g_direction == DIR_LONG)
        result = g_trade.Buy(lotSize, Symbol(), 0, scaleSL, scaleTP, InpComment + "_SCALE");
    else
        result = g_trade.Sell(lotSize, Symbol(), 0, scaleSL, scaleTP, InpComment + "_SCALE");

    if(result && g_trade.ResultOrder() > 0) {
        g_scaleTicket = g_trade.ResultOrder();
        PrintDebug("📈 SCALE-IN | Ticket:" + IntegerToString(g_scaleTicket) +
                   " | Lot:" + DoubleToString(lotSize,2) +
                   " | SL:" + DoubleToString(scaleSL,_Digits) +
                   " | TP:" + DoubleToString(scaleTP,_Digits) +
                   " | Riesgo:$" + DoubleToString(riskAmount,2));
    } else {
        PrintDebug("❌ ERROR SCALE-IN: " + g_trade.ResultRetcodeDescription());
    }
}

//============================================================
//  HELPERS — DETECCIÓN DE CONDICIONES
//============================================================

// Verificar si el símbolo es NASDAQ
bool IsNQSymbol() {
    string sym = Symbol();
    return (StringFind(sym, "NAS") >= 0 || StringFind(sym, "NQ")  >= 0 ||
            StringFind(sym, "US100") >= 0 || StringFind(sym, "NDX") >= 0);
}

// Verificar ventana horaria Venezuela (UTC-4)
// IMPORTANTE: Ajustar InpBrokerOffset según tu broker
bool IsInTradingWindow() {
    datetime serverTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);

    // Convertir hora del servidor a Venezuela (UTC-4)
    // Si broker está en UTC: offset = 0 (Venezuela = UTC - 4, entonces restamos 4)
    // Si broker está en UTC+2: offset = 2 (Venezuela = broker - 6)
    // Para convertir broker→Venezuela: venezuelaHour = brokerHour - (4 + InpBrokerOffset)
    int totalHours   = dt.hour - (4 + InpBrokerOffset);
    if(totalHours < 0)  totalHours += 24;
    if(totalHours >= 24) totalHours -= 24;

    int totalMinutes = totalHours * 60 + dt.min;
    int startMinutes = InpStartHour * 60 + InpStartMin;
    int endMinutes   = InpEndHour   * 60 + InpEndMin;

    return (totalMinutes >= startMinutes && totalMinutes < endMinutes);
}

// Obtener dirección de la tendencia según EMAs en H1
ETRADE_DIR GetEMADirection() {
    double ema20[], ema50[], ema200[];
    ArraySetAsSeries(ema20,  true);
    ArraySetAsSeries(ema50,  true);
    ArraySetAsSeries(ema200, true);

    if(CopyBuffer(h_EMA20_H1,  0, 0, 3, ema20)  < 0) return DIR_NONE;
    if(CopyBuffer(h_EMA50_H1,  0, 0, 3, ema50)  < 0) return DIR_NONE;
    if(CopyBuffer(h_EMA200_H1, 0, 0, 3, ema200) < 0) return DIR_NONE;

    // Alcista: EMA20 > EMA50 > EMA200
    if(ema20[0] > ema50[0] && ema50[0] > ema200[0]) return DIR_LONG;
    // Bajista: EMA20 < EMA50 < EMA200
    if(ema20[0] < ema50[0] && ema50[0] < ema200[0]) return DIR_SHORT;

    return DIR_NONE;
}

// Confirmar anomalía de momentum en RSI (no sobrecompra/venta tradicional)
bool ConfirmRSI_Momentum(ETRADE_DIR dir) {
    double rsi[];
    ArraySetAsSeries(rsi, true);
    if(CopyBuffer(h_RSI_H1, 0, 0, 3, rsi) < 0) return true; // En caso de error, no filtrar

    if(dir == DIR_LONG  && rsi[0] >= InpRSI_BullThresh) return true;
    if(dir == DIR_SHORT && rsi[0] <= InpRSI_BearThresh)  return true;

    return false;
}

// Detectar FVG en el timeframe especificado
bool DetectFVG(ENUM_TIMEFRAMES tf, int lookback, SFVG &fvg) {
    double high[], low[];
    datetime times[];
    ArraySetAsSeries(high,  true);
    ArraySetAsSeries(low,   true);
    ArraySetAsSeries(times, true);

    int needed = lookback + 5;
    if(CopyHigh(Symbol(), tf, 0, needed, high)    < 0) return false;
    if(CopyLow(Symbol(),  tf, 0, needed, low)     < 0) return false;
    if(CopyTime(Symbol(), tf, 0, needed, times)   < 0) return false;

    double minSize = InpFVG_MinSize * _Point;

    for(int i = 1; i <= lookback; i++) {
        // Bullish FVG: low[i] > high[i+2] (espacio sin negociación entre velas)
        if(i+2 < needed) {
            if(low[i] > high[i+2] + minSize) {
                fvg.low       = high[i+2];
                fvg.high      = low[i];
                fvg.direction = DIR_LONG;
                fvg.time      = times[i+2];
                fvg.valid     = true;
                return true;
            }
            // Bearish FVG: high[i] < low[i+2]
            if(high[i] < low[i+2] - minSize) {
                fvg.low       = high[i];
                fvg.high      = low[i+2];
                fvg.direction = DIR_SHORT;
                fvg.time      = times[i+2];
                fvg.valid     = true;
                return true;
            }
        }
    }
    return false;
}

// Detectar quiebre de estructura en M3
bool DetectStructureBreak_M3() {
    double high[], low[], close[];
    ArraySetAsSeries(high,  true);
    ArraySetAsSeries(low,   true);
    ArraySetAsSeries(close, true);

    if(CopyHigh(Symbol(),  PERIOD_M3, 0, 25, high)  < 0) return false;
    if(CopyLow(Symbol(),   PERIOD_M3, 0, 25, low)   < 0) return false;
    if(CopyClose(Symbol(), PERIOD_M3, 0, 25, close) < 0) return false;

    if(g_direction == DIR_LONG) {
        // Encontrar swing low reciente
        double swingLow = low[3];
        for(int i = 4; i <= 15; i++) if(low[i] < swingLow) swingLow = low[i];
        // Quiebre: cierre actual por encima del swing high previo
        double swingHigh = high[3];
        for(int i = 4; i <= 10; i++) if(high[i] > swingHigh) swingHigh = high[i];
        return close[0] > swingHigh && close[0] > close[1];
    }

    if(g_direction == DIR_SHORT) {
        // Quiebre: cierre actual por debajo del swing low previo
        double swingLow2 = low[3];
        for(int i = 4; i <= 10; i++) if(low[i] < swingLow2) swingLow2 = low[i];
        return close[0] < swingLow2 && close[0] < close[1];
    }

    return false;
}

// Detectar Order Block en M5 (SIEMPRE en M5, nunca en M3)
bool DetectOrderBlock_M5(double &obHigh, double &obLow) {
    double open[], high[], low[], close[];
    ArraySetAsSeries(open,  true);
    ArraySetAsSeries(high,  true);
    ArraySetAsSeries(low,   true);
    ArraySetAsSeries(close, true);

    int needed = InpOB_Lookback + 3;
    if(CopyOpen(Symbol(),  PERIOD_M5, 0, needed, open)  < 0) return false;
    if(CopyHigh(Symbol(),  PERIOD_M5, 0, needed, high)  < 0) return false;
    if(CopyLow(Symbol(),   PERIOD_M5, 0, needed, low)   < 0) return false;
    if(CopyClose(Symbol(), PERIOD_M5, 0, needed, close) < 0) return false;

    for(int i = 2; i < needed - 2; i++) {
        double bodySize_prev = MathAbs(close[i]   - open[i]);
        double bodySize_next = MathAbs(close[i-1] - open[i-1]);

        if(g_direction == DIR_LONG) {
            // OB Alcista: vela bajista (roja) antes de impulso alcista fuerte
            bool isBearCandle = close[i] < open[i];
            bool isImpulse    = bodySize_next >= bodySize_prev * InpOB_ImpulseRatio;
            bool isBullishNext = close[i-1] > open[i-1];

            if(isBearCandle && isImpulse && isBullishNext) {
                obHigh = MathMax(open[i], close[i]);
                obLow  = MathMin(open[i], close[i]);
                // Verificar que el precio actual esté cerca del OB
                double ask = g_symbol.Ask();
                if(ask <= obHigh + 20*_Point) return true;
            }
        }

        if(g_direction == DIR_SHORT) {
            // OB Bajista: vela alcista (verde) antes de impulso bajista fuerte
            bool isBullCandle  = close[i] > open[i];
            bool isImpulse     = bodySize_next >= bodySize_prev * InpOB_ImpulseRatio;
            bool isBearishNext = close[i-1] < open[i-1];

            if(isBullCandle && isImpulse && isBearishNext) {
                obHigh = MathMax(open[i], close[i]);
                obLow  = MathMin(open[i], close[i]);
                double bid = g_symbol.Bid();
                if(bid >= obLow - 20*_Point) return true;
            }
        }
    }
    return false;
}

// Detectar pullback en EMA20 en M3 para el scale-in
bool IsPullbackAtEMA_M3() {
    double ema20[];
    ArraySetAsSeries(ema20, true);
    if(CopyBuffer(h_EMA20_M3, 0, 0, 5, ema20) < 0) return false;

    double low[], high[], close[];
    ArraySetAsSeries(low,   true);
    ArraySetAsSeries(high,  true);
    ArraySetAsSeries(close, true);
    CopyLow(Symbol(),   PERIOD_M3, 0, 5, low);
    CopyHigh(Symbol(),  PERIOD_M3, 0, 5, high);
    CopyClose(Symbol(), PERIOD_M3, 0, 5, close);

    double tolerance = 8 * _Point;

    if(g_direction == DIR_LONG) {
        // Vela previa tocó EMA20 y el cierre actual está por encima (rebote)
        bool touchedEMA = low[1] <= ema20[1] + tolerance;
        bool bouncedUp  = close[0] > ema20[0];
        return touchedEMA && bouncedUp;
    }

    if(g_direction == DIR_SHORT) {
        // Vela previa tocó EMA20 por arriba y el cierre actual está por debajo (rechazo)
        bool touchedEMA = high[1] >= ema20[1] - tolerance;
        bool rejectedDown = close[0] < ema20[0];
        return touchedEMA && rejectedDown;
    }

    return false;
}

//============================================================
//  HELPERS — GESTIÓN DE POSICIONES
//============================================================

// Mover SL a Break Even
void MoveSLtoBreakEven(ulong ticket, double entryPrice) {
    if(!g_position.SelectByTicket(ticket)) return;

    double spread   = g_symbol.Ask() - g_symbol.Bid();
    double newSL;

    if(g_direction == DIR_LONG)
        newSL = entryPrice + spread;  // BE + spread para cubrir costos
    else
        newSL = entryPrice - spread;

    newSL = NormalizeDouble(newSL, _Digits);

    if(g_trade.PositionModify(ticket, newSL, g_position.TakeProfit()))
        PrintDebug("🔐 BE activado | Ticket:" + IntegerToString(ticket) +
                   " | Nuevo SL:" + DoubleToString(newSL,_Digits));
    else
        PrintDebug("Error moviendo SL a BE: " + g_trade.ResultRetcodeDescription());
}

// Aplicar trailing stop dinámico basado en ATR
void ApplyTrailingStop(ulong ticket) {
    if(!g_position.SelectByTicket(ticket)) return;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_ATR_M15, 0, 0, 3, atr) < 0) return;

    double currentSL = g_position.StopLoss();
    double currentTP = g_position.TakeProfit();
    double newSL;
    double atrMult = IsNQSymbol() ? InpATR_Mult_NQ : InpATR_Mult_WTI;

    if(g_direction == DIR_LONG) {
        newSL = NormalizeDouble(g_symbol.Bid() - atr[0] * atrMult * 0.8, _Digits);
        if(newSL > currentSL + _Point * 5 && newSL > g_macroEntry)
            g_trade.PositionModify(ticket, newSL, currentTP);
    } else {
        newSL = NormalizeDouble(g_symbol.Ask() + atr[0] * atrMult * 0.8, _Digits);
        if(newSL < currentSL - _Point * 5 && newSL < g_macroEntry)
            g_trade.PositionModify(ticket, newSL, currentTP);
    }
}

// Calcular SL estructural para scale en M3
double CalculateScaleSL_M3() {
    double low[], high[];
    ArraySetAsSeries(low,  true);
    ArraySetAsSeries(high, true);
    CopyLow(Symbol(),  PERIOD_M3, 0, 8, low);
    CopyHigh(Symbol(), PERIOD_M3, 0, 8, high);

    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

    if(g_direction == DIR_LONG) {
        double minLow = low[0];
        for(int i = 1; i < 8; i++) if(low[i] < minLow) minLow = low[i];
        return NormalizeDouble(minLow - 5*_Point, digits);
    }

    double maxHigh = high[0];
    for(int i = 1; i < 8; i++) if(high[i] > maxHigh) maxHigh = high[i];
    return NormalizeDouble(maxHigh + 5*_Point, digits);
}

// Calcular tamaño de lote basado en riesgo monetario
double CalcLotSize(double riskMoney, double slDistance) {
    if(slDistance <= 0) return 0;

    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lotStep   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);

    if(tickValue <= 0 || tickSize <= 0) return minLot;

    double slTicks   = slDistance / tickSize;
    double lotSize   = riskMoney / (slTicks * tickValue);

    // Redondear al step del lote
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);

    return NormalizeDouble(lotSize, 2);
}

// Verificar si ticket existe en posiciones abiertas
bool PositionExistsByTicket(ulong ticket) {
    if(ticket == 0) return false;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetTicket(i) == ticket &&
           PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return true;
    }
    return false;
}

// Obtener profit de una posición
double GetPositionProfit(ulong ticket) {
    if(g_position.SelectByTicket(ticket))
        return g_position.Profit() + g_position.Swap() - g_position.Commission();
    return 0;
}

// Contar posiciones abiertas del EA
int CountOpenPositions() {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetTicket(i) > 0 &&
           PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
    }
    return count;
}

// Verificar reseteo del contador diario
void CheckDailyReset() {
    datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if(today != g_lastTradeDay) {
        g_dailyTrades = 0;
        g_lastTradeDay = today;
        PrintDebug("📅 Nuevo día de trading. Contador reseteado.");
    }
}

// Resetear toda la FSM al estado inicial
void ResetFSM() {
    g_state           = FSM_IDLE;
    g_direction       = DIR_NONE;
    g_activeFVG.valid = false;
    g_obHigh          = 0;
    g_obLow           = 0;
    g_macroTicket     = 0;
    g_scaleTicket     = 0;
    g_macroEntry      = 0;
    g_macroSL         = 0;
    g_macroTP         = 0;
    g_oneR_Monetary   = 0;
    g_lastH1Bar       = 0;
    g_lastM3Bar       = 0;
    g_scalingDone     = false;
    g_m3BreakDetected = false;
}

// Log con timestamp
void PrintDebug(string msg) {
    if(InpPrintDebug)
        Print("[PYRAMIS][", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), "] ", msg);
}

//============================================================
//  EVENTO: CIERRE DE OPERACIÓN (Logging)
//============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL) {
            double profit = trans.price;
            PrintDebug("💰 DEAL cerrado | Symbol:" + trans.symbol +
                       " | Profit:" + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PROFIT), 2));
        }
    }
}
