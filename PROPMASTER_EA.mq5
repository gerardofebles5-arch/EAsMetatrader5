//+------------------------------------------------------------------+
//|                                              PROPMASTER_EA.mq5   |
//|                    PROPMASTER — Challenge Express v1.0           |
//|                                                                   |
//|  OBJETIVO: Aprobar challenges de fondeo (FTMO, MFF, Funded Next) |
//|  MODO:     Automático con guardianes de riesgo de prop firm      |
//|  MERCADOS: NAS100 (NQ) · USOIL (WTI)                            |
//|                                                                   |
//|  ★ REGLAS PROP FIRM INTEGRADAS:                                  |
//|    · Guardián de DD diario (para antes del límite)              |
//|    · Guardián de DD total (para antes del límite)               |
//|    · Target diario automatico (avance progresivo)               |
//|    · Cierre automático fin de semana                            |
//|    · Modo consistencia (cap de ganancia diaria)                 |
//|    · Escala de lotes por fase del challenge                     |
//+------------------------------------------------------------------+
#property copyright "PROPMASTER EA v1.0"
#property version   "1.00"
#property description "EA especializado en aprobar challenges de fondeo propietario"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//============================================================
//  CONFIGURACIÓN DEL CHALLENGE
//============================================================
input group "═══ 🏆 CONFIGURACIÓN DEL CHALLENGE ═══"
input double AccountSize        = 100000; // Tamaño de la cuenta challenge ($)
input double ProfitTarget_Pct   = 8.0;   // Objetivo de beneficio (%, ej: FTMO=8%)
input double MaxDailyDD_Pct     = 5.0;   // DD diario máximo permitido por la prop (%)
input double MaxTotalDD_Pct     = 10.0;  // DD total máximo permitido por la prop (%)
input double SafetyBuffer_Pct   = 0.8;   // Margen de seguridad (el EA para ANTES del límite)
                                          // Ej: 0.8 → EA para al 80% del límite
input double DailyTarget_Pct    = 0.6;   // Objetivo de ganancia por día (%)
input bool   ConsistencyMode    = true;  // Cap diario: no superar 40% del objetivo en un día

input group "═══ 🛡️ RIESGO POR OPERACIÓN ═══"
input double RiskPhase1_Pct     = 0.5;   // Riesgo por trade en fase inicial (%)
input double RiskPhase2_Pct     = 0.75;  // Riesgo por trade a mitad del challenge (%)
input double RiskPhase3_Pct     = 1.0;   // Riesgo por trade en fase final (%)
input double RR_Ratio           = 2.0;   // Ratio R:R
input int    MaxTradesPerDay     = 3;     // Máximo de trades por día

input group "═══ 📈 ESTRATEGIA ═══"
input int    EMA_Fast           = 9;     // EMA rápida
input int    EMA_Slow           = 21;    // EMA lenta
input int    EMA_Trend          = 50;    // EMA de tendencia
input int    RSI_Period         = 14;    // Período RSI
input double RSI_Bull           = 55.0;  // RSI mínimo para largo
input double RSI_Bear           = 45.0;  // RSI máximo para corto
input int    ATR_Period         = 14;    // ATR para el SL
input double ATR_Mult           = 1.3;   // Multiplicador ATR

input group "═══ ⏰ HORARIO ═══"
input int    StartHour          = 9;     // Hora inicio (Venezuela UTC-4)
input int    StartMin           = 44;    // Minuto inicio
input int    EndHour            = 12;    // Hora fin operativa
input int    BrokerUTC          = 0;     // Offset UTC broker
input bool   CloseOnFriday      = true;  // Cerrar todo el viernes a las 11:30 AM VEN
input int    FridayCloseHour    = 11;    // Hora cierre viernes (Venezuela)
input int    FridayCloseMin     = 30;    // Minuto cierre viernes

input group "═══ ⚙️ CONTROL ═══"
input bool   TradeEnabled       = true;
input int    MagicNumber        = 202503;
input bool   PrintLogs          = true;
input bool   ShowDashboard      = true;  // Panel visual en el gráfico

//============================================================
//  ESTRUCTURAS Y ENUMS
//============================================================
enum CHALLENGE_PHASE {
    PHASE_INITIAL  = 0,  // 0–33% del objetivo
    PHASE_MID      = 1,  // 33–66% del objetivo
    PHASE_FINAL    = 2   // 66–100% del objetivo
};

enum CHALLENGE_STATUS {
    STATUS_ACTIVE  = 0,
    STATUS_PASSED  = 1,
    STATUS_FAILED  = 2,
    STATUS_PAUSED  = 3   // Límite diario alcanzado
};

//============================================================
//  VARIABLES GLOBALES
//============================================================
CTrade        Trade;
CPositionInfo Pos;

// Handles
int h_fast, h_slow, h_trend, h_rsi, h_atr;

// Challenge tracking
double startBalance      = 0;
double highWaterMark     = 0;  // Equity máximo alcanzado
double dayStartBalance   = 0;
double dayStartEquity    = 0;
datetime lastTradeDay    = 0;
datetime lastBar         = 0;

// Contadores diarios
int      dailyTrades     = 0;
double   dailyPnL        = 0;
double   dailyDD         = 0;

// Estado
CHALLENGE_PHASE   currentPhase  = PHASE_INITIAL;
CHALLENGE_STATUS  status        = STATUS_ACTIVE;
ulong             currentTicket = 0;
bool              beActivated   = false;

// Límites calculados
double safeMaxDailyDD   = 0;
double safeMaxTotalDD   = 0;
double profitTargetAbs  = 0;
double dailyTargetAbs   = 0;
double consistencyCap   = 0;

//============================================================
//  INIT
//============================================================
int OnInit() {
    Trade.SetExpertMagicNumber(MagicNumber);
    Trade.SetDeviationInPoints(30);
    Trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Handles
    h_fast  = iMA(Symbol(), PERIOD_CURRENT, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
    h_slow  = iMA(Symbol(), PERIOD_CURRENT, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
    h_trend = iMA(Symbol(), PERIOD_CURRENT, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
    h_rsi   = iRSI(Symbol(), PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    h_atr   = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);

    if(h_fast==INVALID_HANDLE || h_slow==INVALID_HANDLE ||
       h_trend==INVALID_HANDLE || h_rsi==INVALID_HANDLE || h_atr==INVALID_HANDLE) {
        Alert("PROPMASTER: Error en handles");
        return INIT_FAILED;
    }

    // Calcular límites del challenge
    startBalance     = AccountInfoDouble(ACCOUNT_BALANCE);
    highWaterMark    = AccountInfoDouble(ACCOUNT_EQUITY);
    dayStartBalance  = startBalance;
    dayStartEquity   = highWaterMark;

    safeMaxDailyDD  = AccountSize * (MaxDailyDD_Pct * SafetyBuffer_Pct / 100.0);
    safeMaxTotalDD  = AccountSize * (MaxTotalDD_Pct * SafetyBuffer_Pct / 100.0);
    profitTargetAbs = AccountSize * (ProfitTarget_Pct / 100.0);
    dailyTargetAbs  = AccountSize * (DailyTarget_Pct / 100.0);
    consistencyCap  = profitTargetAbs * 0.40; // No más del 40% del objetivo en un día

    Log("═══ PROPMASTER EA INICIADO ═══");
    Log("Challenge: $" + DoubleToString(AccountSize,0) +
        " | Target: " + DoubleToString(ProfitTarget_Pct,1) + "%" +
        " ($" + DoubleToString(profitTargetAbs,0) + ")");
    Log("DD Diario límite EA: $" + DoubleToString(safeMaxDailyDD,0) +
        " | DD Total límite EA: $" + DoubleToString(safeMaxTotalDD,0));
    Log("Target diario: $" + DoubleToString(dailyTargetAbs,0) +
        " | Cap consistencia: $" + DoubleToString(consistencyCap,0));

    return INIT_SUCCEEDED;
}

//============================================================
//  DEINIT
//============================================================
void OnDeinit(const int reason) {
    ObjectsDeleteAll(0, "PM_", 0, -1);
    IndicatorRelease(h_fast);
    IndicatorRelease(h_slow);
    IndicatorRelease(h_trend);
    IndicatorRelease(h_rsi);
    IndicatorRelease(h_atr);
}

//============================================================
//  TICK PRINCIPAL
//============================================================
void OnTick() {
    if(!TradeEnabled) return;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

    // Actualizar high water mark
    if(equity > highWaterMark) highWaterMark = equity;

    // Reset diario
    CheckDailyReset(balance, equity);

    // Calcular métricas en tiempo real
    double totalDD     = startBalance - MathMin(equity, balance);
    double todayDD     = dayStartEquity - MathMin(equity, dayStartEquity);
    double totalProfit = balance - startBalance;
    dailyPnL           = balance - dayStartBalance;

    // ════ GUARDIANES DE PROP FIRM ════
    // 1. DD Total — parar si se acerca al límite
    if(totalDD >= safeMaxTotalDD) {
        if(status != STATUS_FAILED) {
            status = STATUS_FAILED;
            CloseAllPositions();
            Log("🚨 GUARDIÁN TOTAL DD: $" + DoubleToString(totalDD,0) +
                " >= límite $" + DoubleToString(safeMaxTotalDD,0) + " | EA DETENIDO");
        }
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // 2. DD Diario — parar si se acerca al límite diario
    if(todayDD >= safeMaxDailyDD) {
        if(status == STATUS_ACTIVE) {
            status = STATUS_PAUSED;
            CloseAllPositions();
            Log("⛔ GUARDIÁN DD DIARIO: $" + DoubleToString(todayDD,0) +
                " | Operaciones suspendidas por hoy");
        }
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // 3. Target total alcanzado
    if(totalProfit >= profitTargetAbs) {
        if(status != STATUS_PASSED) {
            status = STATUS_PASSED;
            CloseAllPositions();
            Log("🏆 CHALLENGE APROBADO! Beneficio: $" + DoubleToString(totalProfit,0) +
                " (+" + DoubleToString(totalProfit/AccountSize*100,2) + "%)");
        }
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // 4. Cap de consistencia diaria
    if(ConsistencyMode && dailyPnL >= consistencyCap) {
        if(status == STATUS_ACTIVE) {
            status = STATUS_PAUSED;
            CloseAllPositions();
            Log("📊 CONSISTENCIA: Objetivo diario cap alcanzado ($" +
                DoubleToString(dailyPnL,0) + "). Stops por hoy.");
        }
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // 5. Objetivo diario alcanzado (sin cap de consistencia)
    if(dailyPnL >= dailyTargetAbs && status == STATUS_ACTIVE) {
        CloseAllPositions();
        Log("✅ Objetivo diario alcanzado: $" + DoubleToString(dailyPnL,0) +
            " | Cerrando operaciones por hoy");
        status = STATUS_PAUSED;
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // Reactivar si el día fue reseteado
    if(status == STATUS_PAUSED) {
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // 6. Cierre de fin de semana (viernes)
    if(CloseOnFriday && IsWeekendClose()) {
        CloseAllPositions();
        Log("📅 Cierre de fin de semana activado");
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    }

    // ════ GESTIÓN DE POSICIÓN ACTIVA ════
    if(PositionOpen()) {
        ManageBreakEven();
        ManageTrailing();
        if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
        return;
    } else {
        currentTicket = 0;
        beActivated   = false;
    }

    // ════ BÚSQUEDA DE NUEVA ENTRADA ════
    if(!InWindow())                    return;
    if(dailyTrades >= MaxTradesPerDay) return;

    // Solo en nueva vela
    datetime barTime = iTime(Symbol(), PERIOD_CURRENT, 0);
    if(barTime == lastBar) return;
    lastBar = barTime;

    // Determinar fase del challenge y riesgo correspondiente
    double progress   = totalProfit / profitTargetAbs;
    currentPhase = progress < 0.33 ? PHASE_INITIAL :
                   progress < 0.66 ? PHASE_MID     : PHASE_FINAL;
    double riskPct = currentPhase == PHASE_INITIAL ? RiskPhase1_Pct :
                     currentPhase == PHASE_MID     ? RiskPhase2_Pct : RiskPhase3_Pct;

    // Reducir riesgo si el DD diario está elevado (modo defensivo)
    if(todayDD >= safeMaxDailyDD * 0.5) riskPct *= 0.5;

    // Leer indicadores (vela cerrada, índice 1)
    double fast[3], slow[3], trend[3], rsi[3], atr[3];
    if(!ReadIndicators(fast, slow, trend, rsi, atr)) return;

    double vwap  = CalcVWAP();
    double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    // ════ CONDICIONES DE ENTRADA (5 filtros) ════
    // LONG
    bool crossUp    = fast[1] > slow[1] && fast[2] <= slow[2];  // Cruce alcista
    bool trendBull  = price > trend[0] && trend[0] > trend[1];  // EMA50 subiendo
    bool aboveVWAP  = price > vwap;                              // Sobre VWAP
    bool rsiBull    = rsi[1] > RSI_Bull && rsi[1] < 75;         // RSI momentum, no sobrecompra
    bool bullMom    = fast[1] > fast[2];                         // EMA9 acelerando
    bool longSig    = crossUp && trendBull && aboveVWAP && rsiBull && bullMom;

    // SHORT
    bool crossDown  = fast[1] < slow[1] && fast[2] >= slow[2];  // Cruce bajista
    bool trendBear  = price < trend[0] && trend[0] < trend[1];  // EMA50 bajando
    bool belowVWAP  = price < vwap;                              // Bajo VWAP
    bool rsiBear    = rsi[1] < RSI_Bear && rsi[1] > 25;         // RSI momentum, no sobrevendido
    bool bearMom    = fast[1] < fast[2];                         // EMA9 acelerando bajada
    bool shortSig   = crossDown && trendBear && belowVWAP && rsiBear && bearMom;

    if(longSig)       OpenTrade(ORDER_TYPE_BUY,  atr[1], riskPct);
    else if(shortSig) OpenTrade(ORDER_TYPE_SELL, atr[1], riskPct);

    if(ShowDashboard) DrawDashboard(totalProfit, dailyPnL, todayDD, totalDD);
}

//============================================================
//  ABRIR OPERACIÓN
//============================================================
void OpenTrade(ENUM_ORDER_TYPE type, double atr, double riskPct) {
    int    digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double ask    = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid    = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double slDist = atr * ATR_Mult;
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

    // Verificar que el TP no excede el objetivo total restante
    double remaining = profitTargetAbs - (AccountInfoDouble(ACCOUNT_BALANCE) - startBalance);
    double lot = CalcLot(slDist, riskPct);
    if(lot <= 0) return;

    string phaseStr = currentPhase==PHASE_INITIAL ? "P1" :
                      currentPhase==PHASE_MID     ? "P2" : "P3";
    string comment  = "PROPMASTER_" + phaseStr;

    bool ok = (type==ORDER_TYPE_BUY) ?
              Trade.Buy(lot, Symbol(), 0, sl, tp, comment) :
              Trade.Sell(lot, Symbol(), 0, sl, tp, comment);

    if(ok && Trade.ResultOrder() > 0) {
        currentTicket = Trade.ResultOrder();
        dailyTrades++;
        Log((type==ORDER_TYPE_BUY ? "▲ BUY" : "▼ SELL") +
            " [" + phaseStr + "]" +
            " | Lot:" + DoubleToString(lot,2) +
            " | Riesgo:" + DoubleToString(riskPct,2) + "%" +
            " | SL:" + DoubleToString(sl,digits) +
            " | TP:" + DoubleToString(tp,digits));
    } else {
        Log("❌ Error al abrir: " + Trade.ResultRetcodeDescription());
    }
}

//============================================================
//  BREAK EVEN en +1R
//============================================================
void ManageBreakEven() {
    if(beActivated || currentTicket==0) return;
    if(!Pos.SelectByTicket(currentTicket)) return;

    double entry   = Pos.PriceOpen();
    double sl      = Pos.StopLoss();
    double oneR    = MathAbs(entry - sl);
    int    digits  = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    bool   isBuy   = Pos.PositionType() == POSITION_TYPE_BUY;
    double current = isBuy ? SymbolInfoDouble(Symbol(),SYMBOL_BID) :
                              SymbolInfoDouble(Symbol(),SYMBOL_ASK);

    bool hit1R = (isBuy  && current >= entry + oneR) ||
                 (!isBuy && current <= entry - oneR);
    if(!hit1R) return;

    double spread = SymbolInfoDouble(Symbol(),SYMBOL_ASK) - SymbolInfoDouble(Symbol(),SYMBOL_BID);
    double newSL  = isBuy ? NormalizeDouble(entry + spread, digits) :
                             NormalizeDouble(entry - spread, digits);
    if(Trade.PositionModify(currentTicket, newSL, Pos.TakeProfit())) {
        beActivated = true;
        Log("🔐 Break Even | Ticket:" + IntegerToString(currentTicket));
    }
}

//============================================================
//  TRAILING STOP
//============================================================
void ManageTrailing() {
    if(currentTicket==0 || !beActivated) return;
    if(!Pos.SelectByTicket(currentTicket)) return;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_atr,0,0,2,atr)<0) return;

    int    digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    bool   isBuy  = Pos.PositionType()==POSITION_TYPE_BUY;
    double currSL = Pos.StopLoss();
    double newSL;

    if(isBuy) {
        newSL = NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_BID) - atr[0]*ATR_Mult, digits);
        if(newSL > currSL + _Point*5 && newSL > Pos.PriceOpen())
            Trade.PositionModify(currentTicket, newSL, Pos.TakeProfit());
    } else {
        newSL = NormalizeDouble(SymbolInfoDouble(Symbol(),SYMBOL_ASK) + atr[0]*ATR_Mult, digits);
        if(newSL < currSL - _Point*5 && newSL < Pos.PriceOpen())
            Trade.PositionModify(currentTicket, newSL, Pos.TakeProfit());
    }
}

//============================================================
//  DASHBOARD VISUAL
//============================================================
void DrawDashboard(double totalPnL, double dayPnL, double dayDD, double totalDD) {
    double progress     = MathMax(0, totalPnL) / profitTargetAbs * 100.0;
    double ddDayPct     = dayDD / AccountSize * 100.0;
    double ddTotalPct   = totalDD / AccountSize * 100.0;
    double dayPct       = dayPnL  / AccountSize * 100.0;
    double totalPct     = totalPnL / AccountSize * 100.0;
    double safeDD_D_Pct = MaxDailyDD_Pct * SafetyBuffer_Pct;
    double safeDD_T_Pct = MaxTotalDD_Pct * SafetyBuffer_Pct;

    string phase = currentPhase==PHASE_INITIAL ? "FASE 1 — Conservador" :
                   currentPhase==PHASE_MID     ? "FASE 2 — Moderado"   :
                                                  "FASE 3 — Agresivo";
    string stat  = status==STATUS_ACTIVE  ? "🟢 ACTIVO"    :
                   status==STATUS_PASSED  ? "🏆 APROBADO"  :
                   status==STATUS_FAILED  ? "🚨 DETENIDO"  : "⛔ PAUSADO HOY";
    string phasRisk = currentPhase==PHASE_INITIAL ? DoubleToString(RiskPhase1_Pct,1) :
                      currentPhase==PHASE_MID     ? DoubleToString(RiskPhase2_Pct,1) :
                                                     DoubleToString(RiskPhase3_Pct,1);

    // Barra de progreso ASCII
    int    barLen     = 20;
    int    filled     = (int)(progress / 100.0 * barLen);
    filled = MathMin(filled, barLen);
    string bar = "[";
    for(int i=0;i<barLen;i++) bar += (i < filled ? "█" : "░");
    bar += "]";

    // Panel
    string p = "PM_";
    int x=15, y=35, step=17;
    int row=0;

    Label(p+"BG");  // Fondo
    Rect(p+"RECT", x-8, y-8, 300, step*16+16);

    Label(p+"T0", x, y+step*row++, "▶ PROPMASTER v1.0 — CHALLENGE EXPRESS", clrYellow, 8, true);
    Label(p+"T1", x, y+step*row++, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 7);

    // Status + Fase
    Label(p+"ST", x, y+step*row++, "Estado:  " + stat +
          "  |  " + phase, status==STATUS_ACTIVE  ? clrLimeGreen :
                             status==STATUS_PASSED ? clrYellow    :
                             status==STATUS_FAILED ? clrRed       : clrGray, 7);

    // Progreso hacia el objetivo
    Label(p+"PR", x, y+step*row++, "Progreso:  " + bar + "  " +
          DoubleToString(progress,1) + "%", clrCyan, 7);

    // P&L Total
    color pnlCol = totalPnL >= 0 ? clrLimeGreen : clrTomato;
    Label(p+"TP", x, y+step*row++,
          "P&L Total:  $" + (totalPnL>=0?"+":"") + DoubleToString(totalPnL,0) +
          "  (" + (totalPct>=0?"+":"") + DoubleToString(totalPct,2) + "%)" +
          "  →  Falta: $" + DoubleToString(MathMax(0,profitTargetAbs-totalPnL),0),
          pnlCol, 7);

    // P&L Hoy
    color dayCol = dayPnL >= 0 ? clrLimeGreen : clrOrange;
    Label(p+"DP", x, y+step*row++,
          "P&L Hoy:   $" + (dayPnL>=0?"+":"") + DoubleToString(dayPnL,0) +
          "  (" + (dayPct>=0?"+":"") + DoubleToString(dayPct,2) + "%)" +
          "  →  Target: $" + DoubleToString(dailyTargetAbs,0),
          dayCol, 7);

    // DD Diario
    double ddDayRatio = ddDayPct / safeDD_D_Pct;
    color  ddDCol     = ddDayRatio < 0.5 ? clrLimeGreen :
                        ddDayRatio < 0.8 ? clrOrange : clrRed;
    Label(p+"DD", x, y+step*row++,
          "DD Hoy:    " + DoubleToString(ddDayPct,2) + "%" +
          "  /  Límite EA: " + DoubleToString(safeDD_D_Pct,1) + "%" +
          "  /  Prop: " + DoubleToString(MaxDailyDD_Pct,1) + "%",
          ddDCol, 7);

    // DD Total
    double ddTotRatio = ddTotalPct / safeDD_T_Pct;
    color  ddTCol     = ddTotRatio < 0.4 ? clrLimeGreen :
                        ddTotRatio < 0.7 ? clrOrange : clrRed;
    Label(p+"DT", x, y+step*row++,
          "DD Total:  " + DoubleToString(ddTotalPct,2) + "%" +
          "  /  Límite EA: " + DoubleToString(safeDD_T_Pct,1) + "%" +
          "  /  Prop: " + DoubleToString(MaxTotalDD_Pct,1) + "%",
          ddTCol, 7);

    // Separador
    Label(p+"S1", x, y+step*row++, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 7);

    // Riesgo actual
    Label(p+"RS", x, y+step*row++,
          "Riesgo/trade:  " + phasRisk + "%" +
          "  |  Trades hoy: " + IntegerToString(dailyTrades) +
          " / " + IntegerToString(MaxTradesPerDay),
          clrAqua, 7);

    // Cuenta y High Water Mark
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    Label(p+"EQ", x, y+step*row++,
          "Equity:   $" + DoubleToString(equity,0) +
          "  |  HWM: $" + DoubleToString(highWaterMark,0),
          clrDimGray, 7);

    // Separador
    Label(p+"S2", x, y+step*row++, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", clrDimGray, 7);

    // Próxima acción
    string action = status==STATUS_PASSED ? "🏆 ¡Enviar a la prop para evaluación!" :
                    status==STATUS_FAILED ? "🚨 Revisar drawdown. EA en modo seguro." :
                    status==STATUS_PAUSED ? "⏸  Objetivo del día alcanzado. Mañana sigo." :
                    dailyTrades>=MaxTradesPerDay ? "✅ Máx trades del día. Esperando mañana." :
                    !InWindow()           ? "⏰ Fuera de ventana. Próxima: 9:44 AM VEN." :
                                           "🔍 Buscando setup en ventana activa...";
    color actCol = status==STATUS_PASSED ? clrYellow :
                   status==STATUS_FAILED ? clrRed    : clrLimeGreen;
    Label(p+"AC", x, y+step*row++, action, actCol, 7);

    ChartRedraw(0);
}

//============================================================
//  HELPERS
//============================================================

bool ReadIndicators(double &fast[], double &slow[],
                    double &trend[], double &rsi[], double &atr[]) {
    ArraySetAsSeries(fast, true); ArraySetAsSeries(slow,  true);
    ArraySetAsSeries(trend,true); ArraySetAsSeries(rsi,   true);
    ArraySetAsSeries(atr,  true);
    return CopyBuffer(h_fast, 0,0,3,fast)  >= 0 &&
           CopyBuffer(h_slow, 0,0,3,slow)  >= 0 &&
           CopyBuffer(h_trend,0,0,3,trend) >= 0 &&
           CopyBuffer(h_rsi,  0,0,3,rsi)   >= 0 &&
           CopyBuffer(h_atr,  0,0,3,atr)   >= 0;
}

double CalcVWAP() {
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    double cumVP=0, cumVol=0;
    for(int i=iBars(Symbol(),PERIOD_CURRENT)-1; i>=0; i--) {
        if(iTime(Symbol(),PERIOD_CURRENT,i) < dayStart) continue;
        double tp  = (iHigh(Symbol(),PERIOD_CURRENT,i)+
                      iLow(Symbol(), PERIOD_CURRENT,i)+
                      iClose(Symbol(),PERIOD_CURRENT,i)) / 3.0;
        long   vol = MathMax(iVolume(Symbol(),PERIOD_CURRENT,i), 1);
        cumVP  += tp*vol;
        cumVol += vol;
    }
    return (cumVol>0) ? cumVP/cumVol : iClose(Symbol(),PERIOD_CURRENT,0);
}

bool InWindow() {
    MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
    int venH = dt.hour-(4+BrokerUTC);
    if(venH<0) venH+=24; if(venH>=24) venH-=24;
    int tot = venH*60+dt.min;
    return tot>=StartHour*60+StartMin && tot<EndHour*60;
}

bool IsWeekendClose() {
    MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
    if(dt.day_of_week != 5) return false;
    int venH = dt.hour-(4+BrokerUTC);
    if(venH<0) venH+=24; if(venH>=24) venH-=24;
    return (venH*60+dt.min) >= FridayCloseHour*60+FridayCloseMin;
}

void CheckDailyReset(double balance, double equity) {
    datetime today = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
    if(today != lastTradeDay) {
        dailyTrades    = 0;
        dayStartBalance= balance;
        dayStartEquity = equity;
        lastTradeDay   = today;
        beActivated    = false;
        currentTicket  = 0;
        if(status == STATUS_PAUSED) status = STATUS_ACTIVE;
        Log("📅 Nuevo día. Balance: $" + DoubleToString(balance,0));
    }
}

bool PositionOpen() {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong t = PositionGetTicket(i);
        if(t>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber) {
            if(currentTicket==0) currentTicket=t;
            return true;
        }
    }
    return false;
}

void CloseAllPositions() {
    for(int i=PositionsTotal()-1; i>=0; i--) {
        ulong t = PositionGetTicket(i);
        if(t>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
            Trade.PositionClose(t);
    }
}

double CalcLot(double slDist, double riskPct) {
    if(slDist<=0) return 0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk    = balance * riskPct / 100.0;
    double tickVal = SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
    if(tickVal<=0||tickSz<=0) return minLot;
    double lot = risk / (slDist/tickSz*tickVal);
    lot = MathMax(MathFloor(lot/lotStep)*lotStep, minLot);
    return MathMin(lot, maxLot);
}

// ── Objetos del panel ──
void Label(string name, int x=0, int y=0, string txt="",
           color col=clrGray, int sz=7, bool bold=false) {
    if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
    ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
    ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
    ObjectSetString(0,name,OBJPROP_TEXT,txt);
    ObjectSetInteger(0,name,OBJPROP_COLOR,col);
    ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
    ObjectSetString(0,name,OBJPROP_FONT,bold?"Courier New Bold":"Courier New");
    ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
    ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}

void Rect(string name, int x, int y, int w, int h) {
    if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
    ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
    ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
    ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
    ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
    ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'5,10,18');
    ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
    ObjectSetInteger(0,name,OBJPROP_COLOR,C'30,55,80');
    ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
    ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
    ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
    ObjectSetInteger(0,name,OBJPROP_BACK,false);
}

void Log(string msg) {
    if(PrintLogs)
        Print("[PROPMASTER][",TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),"] ",msg);
}
