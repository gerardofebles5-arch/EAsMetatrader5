//+------------------------------------------------------------------+
//|                        XAUUSD_V13_INSTITUTIONAL_BREAKOUT.mq5     |
//|                                      Sistema para Cuentas Fondeo |
//|                                                                    |
//| FILOSOFÍA: Estabilidad > Rentabilidad                             |
//| Objetivo: Aprobar challenges con DD controlado                    |
//|                                                                    |
//| LÓGICA:                                                            |
//| - Breakout de High/Low del día anterior                           |
//| - Pullback 30-50% + confirmación                                  |
//| - Filtro EMA200 H1 + ATR expansión                                |
//| - Solo sesión Londres/NY                                          |
//| - TP 1.8RR, SL = 1 ATR                                            |
//| - Control estricto DD: 4% diario, 8% semanal                      |
//+------------------------------------------------------------------+
#property copyright "Institutional Breakout System"
#property version   "13.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== CONFIGURACIÓN BÁSICA ==="
input double InpRiskPercent = 0.5;              // Riesgo por trade (%)
input double InpRiskReward = 1.8;               // Risk:Reward (1.6-2.0)
input int InpMaxTradesPerDay = 2;               // Máximo trades por día
input bool InpStopAfter2Losses = true;          // Parar tras 2 pérdidas diarias

input group "=== FILTRO TENDENCIA ==="
input int InpEMA200Period = 200;                // Período EMA200 (H1)

input group "=== BREAKOUT INSTITUCIONAL ==="
input double InpPullbackMin = 30;               // Pullback mínimo (%)
input double InpPullbackMax = 50;               // Pullback máximo (%)

input group "=== FILTRO VOLATILIDAD ==="
input int InpATRPeriod = 14;                    // ATR período
input int InpATRAvgPeriod = 20;                 // ATR promedio período
input double InpATRMultiplier = 1.0;            // Multiplicador ATR para SL

input group "=== HORARIO TRADING ==="
input int InpStartHour = 8;                     // Hora inicio (servidor)
input int InpEndHour = 17;                      // Hora fin (servidor)

input group "=== DRAWDOWN CONTROL ==="
input double InpMaxDailyDD = 4.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 8.0;              // DD máximo semanal (%)

input group "=== GESTIÓN AVANZADA ==="
input double InpBreakevenRR = 1.0;              // RR para activar breakeven
input int InpMagicNumber = 130001;              // Magic Number

//--- Global Variables
CTrade trade;
int emaHandle;
int atrHandle;
int atrAvgHandle;

double emaBuffer[];
double atrBuffer[];
double atrAvgBuffer[];

datetime lastBarTime = 0;
int tradesToday = 0;
int lossesToday = 0;
datetime lastTradeDate = 0;

double dailyStartBalance = 0;
double weeklyStartBalance = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;

bool dailyLimitReached = false;
bool weeklyLimitReached = false;
bool twoLossesReached = false;

// Niveles institucionales
double previousDayHigh = 0;
double previousDayLow = 0;
datetime previousDayDate = 0;

bool breakoutDetected = false;
bool waitingForPullback = false;
int breakoutType = 0; // 1=bullish, -1=bearish
double breakoutLevel = 0;
double pullbackMin = 0;
double pullbackMax = 0;
datetime breakoutTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configurar trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Crear indicadores
   emaHandle = iMA(_Symbol, PERIOD_H1, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   atrHandle = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) {
      Print("Error creando ATR: ", GetLastError());
      return INIT_FAILED;
   }
   
   atrAvgHandle = iATR(_Symbol, PERIOD_M15, InpATRAvgPeriod);
   if(atrAvgHandle == INVALID_HANDLE) {
      Print("Error creando ATR Average: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(atrAvgBuffer, true);
   
   // Inicializar balance tracking
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   // Calcular niveles del día anterior
   CalculatePreviousDayLevels();
   
   Print("═══════════════════════════════════════════════════════");
   Print("  EA V13.0 INSTITUTIONAL BREAKOUT - PROP FIRM READY");
   Print("═══════════════════════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M15");
   Print("Riesgo: ", InpRiskPercent, "% | RR: 1:", InpRiskReward);
   Print("Horario: ", InpStartHour, ":00 - ", InpEndHour, ":00");
   Print("DD Control: ", InpMaxDailyDD, "% diario / ", InpMaxWeeklyDD, "% semanal");
   Print("Previous Day High: ", previousDayHigh);
   Print("Previous Day Low: ", previousDayLow);
   Print("═══════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(atrAvgHandle != INVALID_HANDLE) IndicatorRelease(atrAvgHandle);
   
   Print("EA V13.0 detenido. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar nueva barra
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   // Actualizar niveles del día anterior si cambió el día
   UpdateDailyLevels();
   
   // Control de drawdown
   CheckDrawdownLimits();
   if(dailyLimitReached || weeklyLimitReached) {
      Comment("⛔ TRADING DETENIDO - Límite DD alcanzado");
      return;
   }
   
   // Reset contadores diarios
   ResetDailyCounters();
   
   // Verificar límite de trades
   if(tradesToday >= InpMaxTradesPerDay) {
      Comment("⏸ Límite diario alcanzado: ", tradesToday, "/", InpMaxTradesPerDay);
      return;
   }
   
   // Verificar regla de 2 pérdidas
   if(InpStopAfter2Losses && twoLossesReached) {
      Comment("⏸ 2 pérdidas consecutivas - Trading pausado hasta mañana");
      return;
   }
   
   // Verificar horario de trading
   if(!IsTradingHours()) {
      Comment("⏰ Fuera de horario de trading");
      return;
   }
   
   // Gestionar posiciones abiertas
   ManageOpenPositions();
   
   // Solo buscar nuevas señales si no hay posiciones
   if(PositionsTotal() > 0)
      return;
   
   // Actualizar indicadores
   if(!UpdateIndicators())
      return;
   
   // Lógica principal
   ProcessInstitutionalBreakout();
   
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Calcular niveles del día anterior                                 |
//+------------------------------------------------------------------+
void CalculatePreviousDayLevels()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   datetime yesterday = iTime(_Symbol, PERIOD_D1, 1);
   
   if(yesterday == 0) {
      Print("⚠ No se pudo obtener día anterior");
      return;
   }
   
   previousDayHigh = iHigh(_Symbol, PERIOD_D1, 1);
   previousDayLow = iLow(_Symbol, PERIOD_D1, 1);
   previousDayDate = yesterday;
   
   Print("Niveles actualizados - High: ", previousDayHigh, " | Low: ", previousDayLow);
}

//+------------------------------------------------------------------+
//| Actualizar niveles diarios                                        |
//+------------------------------------------------------------------+
void UpdateDailyLevels()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   
   if(today != previousDayDate + PeriodSeconds(PERIOD_D1)) {
      CalculatePreviousDayLevels();
      
      // Reset estado de breakout al cambiar de día
      ResetBreakoutState();
   }
}

//+------------------------------------------------------------------+
//| Verificar horario de trading                                      |
//+------------------------------------------------------------------+
bool IsTradingHours()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour;
   
   return (currentHour >= InpStartHour && currentHour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Actualizar indicadores                                            |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3) {
      Print("Error copiando EMA buffer: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 3) {
      Print("Error copiando ATR buffer: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(atrAvgHandle, 0, 0, 3, atrAvgBuffer) < 3) {
      Print("Error copiando ATR Average buffer: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Procesar lógica de breakout institucional                         |
//+------------------------------------------------------------------+
void ProcessInstitutionalBreakout()
{
   // Verificar que tengamos niveles válidos
   if(previousDayHigh == 0 || previousDayLow == 0)
      return;
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double close2 = iClose(_Symbol, PERIOD_M15, 2);
   
   // Estado 1: Detectar breakout
   if(!breakoutDetected) {
      DetectInstitutionalBreakout();
   }
   
   // Estado 2: Esperar pullback y entrar
   if(breakoutDetected && waitingForPullback) {
      CheckPullbackEntry();
   }
}

//+------------------------------------------------------------------+
//| Detectar breakout institucional                                   |
//+------------------------------------------------------------------+
void DetectInstitutionalBreakout()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double close2 = iClose(_Symbol, PERIOD_M15, 2);
   
   // Filtro de volatilidad: ATR actual > ATR promedio
   if(atrBuffer[0] <= atrAvgBuffer[0]) {
      return; // No hay expansión de volatilidad
   }
   
   // BREAKOUT ALCISTA del High del día anterior
   if(high1 > previousDayHigh && close1 > previousDayHigh) {
      // Filtro EMA: precio debe estar por encima
      if(close1 > emaBuffer[0]) {
         // No entrar en la vela de ruptura
         if(close2 <= previousDayHigh) {
            breakoutDetected = true;
            waitingForPullback = true;
            breakoutType = 1; // Bullish
            breakoutLevel = previousDayHigh;
            breakoutTime = iTime(_Symbol, PERIOD_M15, 1);
            
            // Calcular zona de pullback
            double breakoutRange = high1 - previousDayHigh;
            pullbackMin = previousDayHigh + (breakoutRange * (1.0 - InpPullbackMax/100.0));
            pullbackMax = previousDayHigh + (breakoutRange * (1.0 - InpPullbackMin/100.0));
            
            Print("🔼 BREAKOUT ALCISTA detectado");
            Print("   Nivel: ", previousDayHigh);
            Print("   Zona pullback: ", pullbackMin, " - ", pullbackMax);
         }
      }
   }
   
   // BREAKOUT BAJISTA del Low del día anterior
   if(low1 < previousDayLow && close1 < previousDayLow) {
      // Filtro EMA: precio debe estar por debajo
      if(close1 < emaBuffer[0]) {
         // No entrar en la vela de ruptura
         if(close2 >= previousDayLow) {
            breakoutDetected = true;
            waitingForPullback = true;
            breakoutType = -1; // Bearish
            breakoutLevel = previousDayLow;
            breakoutTime = iTime(_Symbol, PERIOD_M15, 1);
            
            // Calcular zona de pullback
            double breakoutRange = previousDayLow - low1;
            pullbackMin = previousDayLow - (breakoutRange * (1.0 - InpPullbackMax/100.0));
            pullbackMax = previousDayLow - (breakoutRange * (1.0 - InpPullbackMin/100.0));
            
            Print("🔽 BREAKOUT BAJISTA detectado");
            Print("   Nivel: ", previousDayLow);
            Print("   Zona pullback: ", pullbackMax, " - ", pullbackMin);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar entrada en pullback                                     |
//+------------------------------------------------------------------+
void CheckPullbackEntry()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double open1 = iOpen(_Symbol, PERIOD_M15, 1);
   
   // Timeout: 4 horas (16 velas M15)
   if(TimeCurrent() - breakoutTime > 4 * 3600) {
      ResetBreakoutState();
      Print("⏱ Timeout: pullback no ocurrió en 4 horas");
      return;
   }
   
   // ENTRADA LONG
   if(breakoutType == 1) {
      // Precio retrocedió a zona de pullback
      if(low1 <= pullbackMax && low1 >= pullbackMin) {
         // Confirmación: cierre de vela alcista
         if(close1 > open1 && close1 > pullbackMin) {
            // Verificar que sigue por encima de EMA
            if(close1 > emaBuffer[0]) {
               OpenTrade(ORDER_TYPE_BUY);
               ResetBreakoutState();
            }
         }
      }
   }
   
   // ENTRADA SHORT
   if(breakoutType == -1) {
      // Precio retrocedió a zona de pullback
      if(high1 >= pullbackMin && high1 <= pullbackMax) {
         // Confirmación: cierre de vela bajista
         if(close1 < open1 && close1 < pullbackMax) {
            // Verificar que sigue por debajo de EMA
            if(close1 < emaBuffer[0]) {
               OpenTrade(ORDER_TYPE_SELL);
               ResetBreakoutState();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset estado de breakout                                          |
//+------------------------------------------------------------------+
void ResetBreakoutState()
{
   breakoutDetected = false;
   waitingForPullback = false;
   breakoutType = 0;
   breakoutLevel = 0;
   pullbackMin = 0;
   pullbackMax = 0;
   breakoutTime = 0;
}

//+------------------------------------------------------------------+
//| Callback cuando se cierra una posición                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0) {
         if(HistoryDealSelect(dealTicket)) {
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(dealMagic == InpMagicNumber) {
               double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
               
               if(profit < 0) {
                  lossesToday++;
                  Print("📉 Pérdida registrada | Total pérdidas hoy: ", lossesToday);
                  
                  if(InpStopAfter2Losses && lossesToday >= 2) {
                     twoLossesReached = true;
                     Print("⏸ 2 pérdidas alcanzadas - Trading pausado hasta mañana");
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Actualizar comentario en gráfico                                  |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double dailyDD = 0;
   double weeklyDD = 0;
   
   if(dailyStartBalance > 0)
      dailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   if(weeklyStartBalance > 0)
      weeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   string status = "🟢 ACTIVO";
   if(dailyLimitReached) status = "🔴 DD DIARIO ALCANZADO";
   else if(weeklyLimitReached) status = "🔴 DD SEMANAL ALCANZADO";
   else if(twoLossesReached) status = "🟡 2 PÉRDIDAS - PAUSADO";
   else if(tradesToday >= InpMaxTradesPerDay) status = "🟡 LÍMITE TRADES";
   else if(!IsTradingHours()) status = "🟡 FUERA DE HORARIO";
   
   string breakoutStatus = "Esperando breakout...";
   if(breakoutDetected && waitingForPullback) {
      string direction = (breakoutType == 1) ? "ALCISTA" : "BAJISTA";
      breakoutStatus = StringFormat("Breakout %s detectado\nEsperando pullback: %.2f - %.2f", 
                                    direction, pullbackMin, pullbackMax);
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   string comment = StringFormat(
      "╔═══════════════════════════════════════════════╗\n" +
      "║   EA V13.0 INSTITUTIONAL BREAKOUT             ║\n" +
      "║   PROP FIRM READY                             ║\n" +
      "╚═══════════════════════════════════════════════╝\n\n" +
      "Estado: %s\n" +
      "Trades hoy: %d/%d | Pérdidas: %d\n\n" +
      "┌─ DRAWDOWN CONTROL ─────────────────────┐\n" +
      "│ DD Diario:  %.2f%% / %.1f%%\n" +
      "│ DD Semanal: %.2f%% / %.1f%%\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ NIVELES INSTITUCIONALES ──────────────┐\n" +
      "│ Previous Day High: %.2f\n" +
      "│ Previous Day Low:  %.2f\n" +
      "│ Precio actual:     %.2f\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ FILTROS ──────────────────────────────┐\n" +
      "│ EMA200 H1: %.2f\n" +
      "│ ATR(14):   %.2f\n" +
      "│ ATR Avg:   %.2f %s\n" +
      "└────────────────────────────────────────┘\n\n" +
      "%s\n\n" +
      "Posiciones: %d\n" +
      "Balance: $%.2f | Equity: $%.2f\n" +
      "═══════════════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay, lossesToday,
      dailyDD, InpMaxDailyDD,
      weeklyDD, InpMaxWeeklyDD,
      previousDayHigh,
      previousDayLow,
      currentPrice,
      emaBuffer[0],
      atrBuffer[0],
      atrAvgBuffer[0],
      (atrBuffer[0] > atrAvgBuffer[0]) ? "✓" : "✗",
      breakoutStatus,
      PositionsTotal(),
      currentBalance,
      equity
   );
   
   Comment(comment);
}

//+------------------------------------------------------------------+
//| Abrir trade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL = 1 ATR (no distancia al breakout)
   double slDistance = atrBuffer[0] * InpATRMultiplier;
   
   // Mínimo 10 pips de SL
   if(slDistance < 100 * point)
      slDistance = 100 * point;
   
   double entryPrice, sl, tp;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + (slDistance * InpRiskReward), _Digits);
   }
   else {
      entryPrice = bid;
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - (slDistance * InpRiskReward), _Digits);
   }
   
   // Calcular lote basado en riesgo
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slPips = slDistance / point;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("⚠ Lote calculado muy pequeño: ", lotSize);
      return;
   }
   
   // Ejecutar orden
   string comment = StringFormat("V13_RR%.1f", InpRiskReward);
   
   bool success = false;
   if(orderType == ORDER_TYPE_BUY) {
      success = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   else {
      success = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   
   if(success) {
      string direction = (orderType == ORDER_TYPE_BUY) ? "LONG" : "SHORT";
      Print("✅ ", direction, " abierto");
      Print("   Lote: ", lotSize);
      Print("   Entry: ", entryPrice);
      Print("   SL: ", sl, " (", DoubleToString(slDistance/point, 1), " pips)");
      Print("   TP: ", tp, " (", DoubleToString((slDistance * InpRiskReward)/point, 1), " pips)");
      Print("   Riesgo: $", DoubleToString(riskAmount, 2));
      
      tradesToday++;
      lastTradeDate = TimeCurrent();
   }
   else {
      Print("❌ Error abriendo trade: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote                                           |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slPips)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slInTicks = slPips * point / tickSize;
   double lotSize = riskAmount / (slInTicks * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Gestionar posiciones abiertas                                     |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      // Breakeven al +1RR
      MoveToBreakeven(ticket);
   }
}

//+------------------------------------------------------------------+
//| Mover a breakeven                                                 |
//+------------------------------------------------------------------+
void MoveToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double slDistance = MathAbs(posOpenPrice - posSL);
   double breakevenTrigger = slDistance * InpBreakevenRR;
   
   // Si ya está en breakeven, salir
   if(MathAbs(posSL - posOpenPrice) < 10 * _Point)
      return;
   
   // Verificar si alcanzó +1RR
   bool shouldMoveBE = false;
   
   if(posType == POSITION_TYPE_BUY) {
      if(currentPrice >= posOpenPrice + breakevenTrigger)
         shouldMoveBE = true;
   }
   else {
      if(currentPrice <= posOpenPrice - breakevenTrigger)
         shouldMoveBE = true;
   }
   
   if(shouldMoveBE) {
      double newSL = NormalizeDouble(posOpenPrice + (1 * _Point * ((posType == POSITION_TYPE_BUY) ? 1 : -1)), _Digits);
      
      if(trade.PositionModify(ticket, newSL, posTP)) {
         Print("🔒 Breakeven activado | Ticket: ", ticket, " | Nuevo SL: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Control de drawdown                                               |
//+------------------------------------------------------------------+
void CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Reset diario
   MqlDateTime lastDayStruct;
   TimeToStruct(lastDayCheck, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      dailyStartBalance = currentBalance;
      lastDayCheck = TimeCurrent();
      dailyLimitReached = false;
      Print("📅 Nuevo día - Balance inicial: $", DoubleToString(dailyStartBalance, 2));
   }
   
   // Reset semanal (lunes)
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartBalance = currentBalance;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
      Print("📅 Nueva semana - Balance inicial: $", DoubleToString(weeklyStartBalance, 2));
   }
   
   // Calcular DD
   double dailyDD = 0;
   double weeklyDD = 0;
   
   if(dailyStartBalance > 0)
      dailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   if(weeklyStartBalance > 0)
      weeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   // Verificar límites
   if(dailyDD >= InpMaxDailyDD && !dailyLimitReached) {
      dailyLimitReached = true;
      Print("⛔ LÍMITE DD DIARIO ALCANZADO: ", DoubleToString(dailyDD, 2), "%");
      Print("   Balance inicio: $", dailyStartBalance);
      Print("   Balance actual: $", currentBalance);
   }
   
   if(weeklyDD >= InpMaxWeeklyDD && !weeklyLimitReached) {
      weeklyLimitReached = true;
      Print("⛔ LÍMITE DD SEMANAL ALCANZADO: ", DoubleToString(weeklyDD, 2), "%");
      Print("   Balance inicio: $", weeklyStartBalance);
      Print("   Balance actual: $", currentBalance);
   }
}

//+------------------------------------------------------------------+
//| Reset contadores diarios                                          |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   MqlDateTime currentTime, lastTradeTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastTradeDate, lastTradeTime);
   
   if(currentTime.day != lastTradeTime.day) {
      tradesToday = 0;
      lossesToday = 0;
      twoLossesReached = false;
   }
}
//+------------------------------------------------------------------+
