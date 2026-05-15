//+------------------------------------------------------------------+
//|                                                      ORB_EA.mq5  |
//|              OPENING RANGE BREAKOUT — EA Operativo v1.0          |
//|                                                                   |
//|  LÓGICA:  Define el rango 9:30-9:44 AM. Opera el breakout.      |
//|  EDGE:    Estrategia documentada académicamente. No overfitting. |
//|  FILTRO:  VWAP + ATR range filter para evitar rangos pequeños   |
//|  RIESGO:  1% por trade. SL = lado opuesto del rango + buffer    |
//|  TP:      1.5× el tamaño del rango (ajustable)                  |
//|  MAX:     1 trade por día. Cierra si no toca TP/SL antes del    |
//|           cierre de sesión.                                      |
//|                                                                   |
//|  MERCADOS: NAS100 · USOIL · Cualquier índice o commodity        |
//|  TIMEFRAME: M1 o M5 (para mayor precisión en el rango)          |
//+------------------------------------------------------------------+
#property copyright "ORB EA v1.0"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//============================================================
//  INPUTS
//============================================================
input group "═══ RANGO (Opening Range) ═══"
input int    RangeStart_Hour  = 9;    // Hora inicio del rango (Venezuela UTC-4)
input int    RangeStart_Min   = 30;   // Minuto inicio (apertura NY = 9:30 AM VEN)
input int    RangeEnd_Hour    = 9;    // Hora fin del rango
input int    RangeEnd_Min     = 44;   // Minuto fin (14 minutos de rango)
input int    BrokerUTC        = 0;    // Offset UTC de tu broker (0=UTC, 2=UTC+2, 3=UTC+3)

input group "═══ ENTRADA Y SALIDA ═══"
input double TP_RangeMultiple = 1.5;  // TP = rango × este múltiplo (1.5 = 1.5R mínimo)
input double SL_Buffer_ATR    = 0.3;  // Buffer adicional al SL en múltiplos de ATR
input double MinRange_ATR     = 0.5;  // Rango mínimo válido (× ATR). Filtra días planos.
input double MaxRange_ATR     = 3.0;  // Rango máximo válido (× ATR). Filtra días caóticos.
input int    ATR_Period        = 14;   // Período ATR para filtros
input int    SessionClose_Hour = 15;   // Hora cierre de posición si sigue abierta (Venezuela)
input int    SessionClose_Min  = 30;   // Minuto cierre de sesión

input group "═══ RIESGO ═══"
input double RiskPercent      = 1.0;  // Riesgo por trade (% del balance)
input int    MagicNumber      = 202504;

input group "═══ FILTROS OPCIONALES ═══"
input bool   UseVWAP_Filter   = true; // Filtro VWAP: solo breakout en dirección del VWAP
input bool   UseTrend_Filter  = true; // Filtro tendencia H1: EMA50 direction
input bool   CloseEOD         = true; // Cerrar posición abierta al cierre de sesión
input bool   PrintLogs        = true;

//============================================================
//  VARIABLES GLOBALES
//============================================================
CTrade        Trade;
CPositionInfo Pos;

int    h_atr, h_ema;

// Estado del rango diario
double rangeHigh    = 0;
double rangeLow     = 0;
bool   rangeFormed  = false;
bool   tradeToday   = false;   // Solo 1 trade por día
datetime lastDay    = 0;
datetime lastBar    = 0;
ulong    ticket     = 0;

//============================================================
//  INIT
//============================================================
int OnInit() {
    Trade.SetExpertMagicNumber(MagicNumber);
    Trade.SetDeviationInPoints(30);
    Trade.SetTypeFilling(ORDER_FILLING_IOC);

    h_atr = iATR(Symbol(), PERIOD_M5, ATR_Period);
    h_ema = iMA(Symbol(),  PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);

    if(h_atr == INVALID_HANDLE || h_ema == INVALID_HANDLE) {
        Alert("ORB EA: Error en handles"); return INIT_FAILED;
    }

    Log("ORB EA iniciado | " + Symbol());
    Log("Rango: " + IntegerToString(RangeStart_Hour) + ":" +
        (RangeStart_Min<10?"0":"") + IntegerToString(RangeStart_Min) +
        " → " + IntegerToString(RangeEnd_Hour) + ":" +
        (RangeEnd_Min<10?"0":"") + IntegerToString(RangeEnd_Min) + " (Venezuela)");
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    IndicatorRelease(h_atr);
    IndicatorRelease(h_ema);
}

//============================================================
//  TICK PRINCIPAL
//============================================================
void OnTick() {
    // Reset diario
    datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if(today != lastDay) {
        rangeHigh   = 0;
        rangeLow    = 0;
        rangeFormed = false;
        tradeToday  = false;
        ticket      = 0;
        lastDay     = today;
        Log("─── Nuevo día. Esperando formación del rango ───");
    }

    int  venHour, venMin;
    VenTime(venHour, venMin);
    int  venTotal    = venHour * 60 + venMin;
    int  rangeStartM = RangeStart_Hour * 60 + RangeStart_Min;
    int  rangeEndM   = RangeEnd_Hour   * 60 + RangeEnd_Min;
    int  closeM      = SessionClose_Hour * 60 + SessionClose_Min;

    // ── 1. ACUMULAR EL RANGO (9:30 → 9:44 AM Venezuela) ──
    if(venTotal >= rangeStartM && venTotal < rangeEndM && !rangeFormed) {
        double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        if(rangeHigh == 0) { rangeHigh = ask; rangeLow = bid; }
        if(ask > rangeHigh) rangeHigh = ask;
        if(bid < rangeLow)  rangeLow  = bid;
        return; // Solo construir rango, no operar todavía
    }

    // ── 2. CONFIRMAR RANGO AL CIERRE DEL PERÍODO ──
    if(venTotal == rangeEndM && !rangeFormed && rangeHigh > 0) {
        double atr = GetATR();
        double rangeSize = rangeHigh - rangeLow;

        // Filtro: rango debe ser significativo (ni muy pequeño ni muy grande)
        if(rangeSize < atr * MinRange_ATR) {
            Log("⚠ Rango muy pequeño (" + DoubleToString(rangeSize/_Point,0) +
                " pts). Mínimo: " + DoubleToString(atr*MinRange_ATR/_Point,0) + " pts. Saltando.");
            rangeFormed = true; // Marcamos como formado pero no operamos
            tradeToday  = true; // Skip
            return;
        }
        if(rangeSize > atr * MaxRange_ATR) {
            Log("⚠ Rango muy grande (" + DoubleToString(rangeSize/_Point,0) +
                " pts). Máximo: " + DoubleToString(atr*MaxRange_ATR/_Point,0) + " pts. Saltando.");
            rangeFormed = true;
            tradeToday  = true;
            return;
        }

        rangeFormed = true;
        Log("✅ Rango formado | High: " + DoubleToString(rangeHigh,_Digits) +
            " | Low: " + DoubleToString(rangeLow,_Digits) +
            " | Tamaño: " + DoubleToString(rangeSize/_Point,0) + " pts");
    }

    // ── 3. GESTIONAR POSICIÓN ABIERTA ──
    if(PositionOpen()) {
        // Cierre forzado al final de sesión
        if(CloseEOD && venTotal >= closeM) {
            Trade.PositionClose(ticket);
            Log("🕐 Cierre de sesión: posición cerrada por tiempo");
            tradeToday = true;
        }
        return;
    }

    // ── 4. BUSCAR BREAKOUT (después del rango, antes del cierre) ──
    if(!rangeFormed || tradeToday) return;
    if(venTotal < rangeEndM || venTotal >= closeM) return;

    // Solo en nueva vela M1
    datetime barTime = iTime(Symbol(), PERIOD_M1, 0);
    if(barTime == lastBar) return;
    lastBar = barTime;

    double ask      = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid      = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double atr      = GetATR();
    double spread   = ask - bid;
    double rangeSz  = rangeHigh - rangeLow;
    double vwap     = CalcVWAP();
    double ema50    = GetEMA50();

    // ── Breakout ALCISTA ──
    if(ask > rangeHigh + spread) {  // Precio cierra sobre el techo del rango
        bool vwapOK  = !UseVWAP_Filter  || ask > vwap;
        bool trendOK = !UseTrend_Filter  || ask > ema50;

        if(vwapOK && trendOK) {
            double sl = NormalizeDouble(rangeLow  - atr * SL_Buffer_ATR, _Digits);
            double tp = NormalizeDouble(ask + rangeSz * TP_RangeMultiple, _Digits);
            double lot = CalcLot(ask - sl);
            if(lot > 0 && Trade.Buy(lot, Symbol(), 0, sl, tp, "ORB_LONG")) {
                ticket     = Trade.ResultOrder();
                tradeToday = true;
                Log("▲ ORB LONG | Ask:" + DoubleToString(ask,_Digits) +
                    " | SL:" + DoubleToString(sl,_Digits) +
                    " | TP:" + DoubleToString(tp,_Digits) +
                    " | Lot:" + DoubleToString(lot,2) +
                    " | Range:" + DoubleToString(rangeSz/_Point,0) + "pts");
            }
        } else {
            Log("▲ Breakout alcista rechazado por filtro | VWAP:" +
                (vwapOK?"OK":"NO") + " | Trend:" + (trendOK?"OK":"NO"));
        }
    }

    // ── Breakout BAJISTA ──
    else if(bid < rangeLow - spread) {  // Precio cierra bajo el piso del rango
        bool vwapOK  = !UseVWAP_Filter  || bid < vwap;
        bool trendOK = !UseTrend_Filter  || bid < ema50;

        if(vwapOK && trendOK) {
            double sl = NormalizeDouble(rangeHigh + atr * SL_Buffer_ATR, _Digits);
            double tp = NormalizeDouble(bid - rangeSz * TP_RangeMultiple, _Digits);
            double lot = CalcLot(sl - bid);
            if(lot > 0 && Trade.Sell(lot, Symbol(), 0, sl, tp, "ORB_SHORT")) {
                ticket     = Trade.ResultOrder();
                tradeToday = true;
                Log("▼ ORB SHORT | Bid:" + DoubleToString(bid,_Digits) +
                    " | SL:" + DoubleToString(sl,_Digits) +
                    " | TP:" + DoubleToString(tp,_Digits) +
                    " | Lot:" + DoubleToString(lot,2) +
                    " | Range:" + DoubleToString(rangeSz/_Point,0) + "pts");
            }
        } else {
            Log("▼ Breakout bajista rechazado por filtro | VWAP:" +
                (vwapOK?"OK":"NO") + " | Trend:" + (trendOK?"OK":"NO"));
        }
    }
}

//============================================================
//  HELPERS
//============================================================
void VenTime(int &h, int &m) {
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    h = dt.hour - (4 + BrokerUTC);
    if(h < 0) h += 24; if(h >= 24) h -= 24;
    m = dt.min;
}

double GetATR() {
    double atr[]; ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_atr, 0, 0, 3, atr) < 0) return _Point * 100;
    return atr[1];
}

double GetEMA50() {
    double ema[]; ArraySetAsSeries(ema, true);
    if(CopyBuffer(h_ema, 0, 0, 2, ema) < 0) return SymbolInfoDouble(Symbol(),SYMBOL_BID);
    return ema[0];
}

double CalcVWAP() {
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    double cumVP = 0, cumVol = 0;
    for(int i = iBars(Symbol(), PERIOD_M1) - 1; i >= 0; i--) {
        if(iTime(Symbol(), PERIOD_M1, i) < dayStart) continue;
        double tp  = (iHigh(Symbol(),PERIOD_M1,i) +
                      iLow(Symbol(), PERIOD_M1,i) +
                      iClose(Symbol(),PERIOD_M1,i)) / 3.0;
        long   vol = MathMax(iVolume(Symbol(),PERIOD_M1,i), 1);
        cumVP  += tp * vol; cumVol += vol;
    }
    return (cumVol > 0) ? cumVP / cumVol : SymbolInfoDouble(Symbol(),SYMBOL_BID);
}

bool PositionOpen() {
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong t = PositionGetTicket(i);
        if(t > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            ticket = t; return true;
        }
    }
    return false;
}

double CalcLot(double slDist) {
    if(slDist <= 0) return 0;
    double risk    = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
    double tickVal = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    if(tickVal <= 0 || tickSz <= 0) return minLot;
    double lot = risk / (slDist / tickSz * tickVal);
    lot = MathMax(MathFloor(lot / lotStep) * lotStep, minLot);
    return MathMin(lot, maxLot);
}

void Log(string msg) {
    if(PrintLogs)
        Print("[ORB][", TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES), "] ", msg);
}
