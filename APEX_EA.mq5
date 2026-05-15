//+------------------------------------------------------------------+
//|                                                      APEX_EA.mq5 |
//|                         APEX — Simple Trend EA v1.0              |
//|                                                                   |
//|  LÓGICA:  EMA 9/21 Cross · Filtro EMA 50 · VWAP Bias · ATR SL  |
//|  RR:      1:2  |  RIESGO: 1% por trade  |  MAX: 2 trades/día   |
//|  MERCADOS: NAS100 (NQ) · USOIL (WTI)                            |
//+------------------------------------------------------------------+
#property copyright "APEX EA v1.0"
#property version   "1.00"
#property description "EA simple y automático: EMA Cross + VWAP + ATR"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//============================================================
//  INPUTS
//============================================================
input group "═══ RIESGO ═══"
input double RiskPercent   = 1.0;   // Riesgo por operación (% del balance)
input double RR_Ratio      = 2.0;   // Ratio Riesgo:Beneficio (TP = RR × SL)
input int    MaxDailyTrades= 2;     // Máximo de trades por día

input group "═══ EMAs ═══"
input int    EMA_Fast      = 9;     // EMA rápida (señal)
input int    EMA_Slow      = 21;    // EMA lenta (señal)
input int    EMA_Trend     = 50;    // EMA de tendencia (filtro)

input group "═══ ATR (Stop Loss) ═══"
input int    ATR_Period    = 14;    // Período ATR
input double ATR_Mult      = 1.5;   // Multiplicador ATR para el SL

input group "═══ HORARIO (Venezuela UTC-4) ═══"
input int    StartHour     = 9;     // Hora inicio
input int    StartMin      = 44;    // Minuto inicio
input int    EndHour       = 12;    // Hora fin
input int    BrokerUTC     = 0;     // Offset UTC de tu broker (0=UTC, 2=UTC+2, 3=UTC+3)

input group "═══ CONTROL ═══"
input bool   TradeEnabled  = true;  // Master switch
input bool   UseBreakEven  = true;  // Activar Break Even en +1R
input bool   UseTrailing   = true;  // Trailing stop con ATR
input int    MagicNumber   = 202502;
input bool   PrintLogs     = true;

//============================================================
//  VARIABLES GLOBALES
//============================================================
CTrade         Trade;
CPositionInfo  Pos;

int  h_fast, h_slow, h_trend, h_atr;

// Control diario
int      dailyTrades   = 0;
datetime lastTradeDay  = 0;
datetime lastBar       = 0;

// Estado del trailing / BE
bool     beActivated   = false;
ulong    currentTicket = 0;

//============================================================
//  INIT
//============================================================
int OnInit() {
    Trade.SetExpertMagicNumber(MagicNumber);
    Trade.SetDeviationInPoints(30);
    Trade.SetTypeFilling(ORDER_FILLING_IOC);

    h_fast  = iMA(Symbol(), PERIOD_CURRENT, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
    h_slow  = iMA(Symbol(), PERIOD_CURRENT, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
    h_trend = iMA(Symbol(), PERIOD_CURRENT, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
    h_atr   = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);

    if(h_fast==INVALID_HANDLE || h_slow==INVALID_HANDLE ||
       h_trend==INVALID_HANDLE || h_atr==INVALID_HANDLE) {
        Alert("APEX EA: Error en handles de indicadores");
        return INIT_FAILED;
    }

    Log("APEX EA iniciado | " + Symbol() +
        " | Riesgo:" + DoubleToString(RiskPercent,1) + "%" +
        " | RR 1:" + DoubleToString(RR_Ratio,1));
    return INIT_SUCCEEDED;
}

//============================================================
//  DEINIT
//============================================================
void OnDeinit(const int reason) {
    IndicatorRelease(h_fast);
    IndicatorRelease(h_slow);
    IndicatorRelease(h_trend);
    IndicatorRelease(h_atr);
}

//============================================================
//  TICK
//============================================================
void OnTick() {
    if(!TradeEnabled) return;

    // ── Reset contador diario ──
    datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if(today != lastTradeDay) {
        dailyTrades  = 0;
        lastTradeDay = today;
        beActivated  = false;
        currentTicket= 0;
        Log("Nuevo día. Contador reseteado.");
    }

    // ── Gestión activa de posición abierta ──
    if(PositionOpen()) {
        if(UseBreakEven) ManageBreakEven();
        if(UseTrailing)  ManageTrailing();
        return; // Una posición a la vez
    } else {
        currentTicket = 0;
        beActivated   = false;
    }

    // ── Guards ──
    if(!InWindow())               return;
    if(dailyTrades >= MaxDailyTrades) return;

    // ── Solo procesar al cierre de cada vela ──
    datetime barTime = iTime(Symbol(), PERIOD_CURRENT, 0);
    if(barTime == lastBar) return;
    lastBar = barTime;

    // ── Leer indicadores (vela cerrada, índice 1) ──
    double fast[3], slow[3], trend[3], atr[3];
    if(!CopyBuffers(fast, slow, trend, atr)) return;

    // ── Calcular VWAP ──
    double vwap = CalcVWAP();

    // ── Condiciones de entrada ──
    double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    // LONG: EMA9 cruza sobre EMA21 + precio sobre EMA50 + precio sobre VWAP
    bool crossUp   = fast[1] > slow[1] && fast[2] <= slow[2];
    bool trendUp   = price > trend[0];
    bool aboveVWAP = price > vwap;
    bool longCond  = crossUp && trendUp && aboveVWAP;

    // SHORT: EMA9 cruza bajo EMA21 + precio bajo EMA50 + precio bajo VWAP
    bool crossDown  = fast[1] < slow[1] && fast[2] >= slow[2];
    bool trendDown  = price < trend[0];
    bool belowVWAP  = price < vwap;
    bool shortCond  = crossDown && trendDown && belowVWAP;

    if(longCond)       OpenTrade(ORDER_TYPE_BUY,  atr[1]);
    else if(shortCond) OpenTrade(ORDER_TYPE_SELL, atr[1]);
}

//============================================================
//  ABRIR OPERACIÓN
//============================================================
void OpenTrade(ENUM_ORDER_TYPE type, double atr) {
    int    digits   = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double ask      = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid      = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double slDist   = atr * ATR_Mult;
    double entry, sl, tp;

    if(type == ORDER_TYPE_BUY) {
        entry = ask;
        sl    = NormalizeDouble(entry - slDist, digits);
        tp    = NormalizeDouble(entry + slDist * RR_Ratio, digits);
    } else {
        entry = bid;
        sl    = NormalizeDouble(entry + slDist, digits);
        tp    = NormalizeDouble(entry - slDist * RR_Ratio, digits);
    }

    double lot = CalcLot(slDist);
    if(lot <= 0) { Log("Lote inválido. Cancelando."); return; }

    bool ok = (type == ORDER_TYPE_BUY) ?
              Trade.Buy(lot, Symbol(), 0, sl, tp, "APEX") :
              Trade.Sell(lot, Symbol(), 0, sl, tp, "APEX");

    if(ok && Trade.ResultOrder() > 0) {
        currentTicket = Trade.ResultOrder();
        dailyTrades++;
        Log((type==ORDER_TYPE_BUY ? "▲ BUY" : "▼ SELL") +
            " | Lot:" + DoubleToString(lot,2) +
            " | SL:" + DoubleToString(sl,digits) +
            " | TP:" + DoubleToString(tp,digits) +
            " | ATR:" + DoubleToString(atr,digits));
    } else {
        Log("Error al abrir: " + Trade.ResultRetcodeDescription());
    }
}

//============================================================
//  BREAK EVEN en +1R
//============================================================
void ManageBreakEven() {
    if(beActivated || currentTicket == 0) return;
    if(!Pos.SelectByTicket(currentTicket)) return;

    double entry   = Pos.PriceOpen();
    double sl      = Pos.StopLoss();
    double current = (Pos.PositionType() == POSITION_TYPE_BUY) ?
                      SymbolInfoDouble(Symbol(), SYMBOL_BID) :
                      SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double oneR    = MathAbs(entry - sl);
    int    digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

    bool hitOneR = (Pos.PositionType()==POSITION_TYPE_BUY  && current >= entry + oneR) ||
                   (Pos.PositionType()==POSITION_TYPE_SELL && current <= entry - oneR);

    if(hitOneR) {
        double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) -
                        SymbolInfoDouble(Symbol(), SYMBOL_BID);
        double newSL  = (Pos.PositionType()==POSITION_TYPE_BUY) ?
                         NormalizeDouble(entry + spread, digits) :
                         NormalizeDouble(entry - spread, digits);
        if(Trade.PositionModify(currentTicket, newSL, Pos.TakeProfit())) {
            beActivated = true;
            Log("🔐 Break Even activado | SL → " + DoubleToString(newSL, digits));
        }
    }
}

//============================================================
//  TRAILING STOP con ATR
//============================================================
void ManageTrailing() {
    if(currentTicket == 0) return;
    if(!Pos.SelectByTicket(currentTicket)) return;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_atr, 0, 0, 2, atr) < 0) return;

    int    digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double currSL  = Pos.StopLoss();
    double currTP  = Pos.TakeProfit();
    double newSL;

    if(Pos.PositionType() == POSITION_TYPE_BUY) {
        newSL = NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_BID) - atr[0]*ATR_Mult, digits);
        if(newSL > currSL + _Point * 5 && newSL > Pos.PriceOpen())
            Trade.PositionModify(currentTicket, newSL, currTP);
    } else {
        newSL = NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_ASK) + atr[0]*ATR_Mult, digits);
        if(newSL < currSL - _Point * 5 && newSL < Pos.PriceOpen())
            Trade.PositionModify(currentTicket, newSL, currTP);
    }
}

//============================================================
//  HELPERS
//============================================================

// Copiar los 3 buffers de EMA + ATR (velas 0,1,2)
bool CopyBuffers(double &fast[], double &slow[], double &trend[], double &atr[]) {
    ArraySetAsSeries(fast,  true);
    ArraySetAsSeries(slow,  true);
    ArraySetAsSeries(trend, true);
    ArraySetAsSeries(atr,   true);
    return CopyBuffer(h_fast,  0,0,3,fast)  >= 0 &&
           CopyBuffer(h_slow,  0,0,3,slow)  >= 0 &&
           CopyBuffer(h_trend, 0,0,3,trend) >= 0 &&
           CopyBuffer(h_atr,   0,0,3,atr)   >= 0;
}

// VWAP diario
double CalcVWAP() {
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    double   cumVP = 0, cumVol = 0;
    int      bars  = iBars(Symbol(), PERIOD_CURRENT);

    for(int i = bars - 1; i >= 0; i--) {
        if(iTime(Symbol(), PERIOD_CURRENT, i) < dayStart) continue;
        double tp  = (iHigh(Symbol(),PERIOD_CURRENT,i) +
                      iLow(Symbol(), PERIOD_CURRENT,i) +
                      iClose(Symbol(),PERIOD_CURRENT,i)) / 3.0;
        long   vol = iVolume(Symbol(), PERIOD_CURRENT, i);
        if(vol < 1) vol = 1;
        cumVP  += tp * vol;
        cumVol += vol;
    }
    return (cumVol > 0) ? cumVP / cumVol : iClose(Symbol(), PERIOD_CURRENT, 0);
}

// Verificar ventana horaria Venezuela (UTC-4)
bool InWindow() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int venH = dt.hour - (4 + BrokerUTC);
    if(venH < 0)   venH += 24;
    if(venH >= 24) venH -= 24;
    int tot = venH * 60 + dt.min;
    return tot >= StartHour * 60 + StartMin && tot < EndHour * 60;
}

// Verificar si hay posición abierta del EA
bool PositionOpen() {
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        ulong t = PositionGetTicket(i);
        if(t > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
            if(currentTicket == 0) currentTicket = t;
            return true;
        }
    }
    return false;
}

// Calcular lote por % de riesgo
double CalcLot(double slDist) {
    if(slDist <= 0) return 0;
    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk     = balance * RiskPercent / 100.0;
    double tickVal  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSz   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lotStep  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double minLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot   = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    if(tickVal<=0 || tickSz<=0) return minLot;
    double lot = risk / (slDist / tickSz * tickVal);
    lot = MathMax(MathFloor(lot/lotStep)*lotStep, minLot);
    return MathMin(lot, maxLot);
}

void Log(string msg) {
    if(PrintLogs)
        Print("[APEX][", TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES), "] ", msg);
}
