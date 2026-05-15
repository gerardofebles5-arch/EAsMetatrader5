//+------------------------------------------------------------------+
//|                        XAUUSD_V12_2_INSTITUTIONAL.mq5            |
//|                                    Estrategia Breakout + Pullback |
//|                                                                    |
//| V12.2 INSTITUCIONAL - MEJORAS:                                    |
//| 1. SL normalizado con ATR (0.8-1.8 ATR)                           |
//| 2. Filtro fuerza breakout (body >= 60% range)                     |
//| 3. Pullback mejorado (cierre en tercio superior/inferior)         |
//| 4. Breakeven a 1.0R                                               |
//| 5. MinBreakout corregido                                          |
//|                                                                    |
//| Timeframe: M15                                                     |
//| Filtro: EMA200 H1                                                  |
//| Lógica: Breakout de swing + pullback                               |
//| SL: Normalizado con ATR                                            |
//| TP: 1.8 RR                                                         |
//| Riesgo: 0.5% por trade                                             |
//| Max trades: 2 diarios                                              |
//| DD Control: 4% diario, 8% semanal                                  |
//+------------------------------------------------------------------+
#property copyright "Institutional Breakout System V12.2"
#property version   "12.20"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== CONFIGURACIÓN BÁSICA ==="
input double InpRiskPercent = 0.5;              // Riesgo por trade (%)
input double InpRiskReward = 1.8;               // Risk:Reward ratio
input int InpMaxTradesPerDay = 2;               // Máximo trades por día

input group "=== FILTRO TENDENCIA ==="
input int InpEMA200Period = 200;                // Período EMA200 (H1)
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;     // Timeframe EMA

input group "=== BREAKOUT SETTINGS ==="
input int InpSwingBars = 10;                    // Barras para detectar swing high/low
input double InpPullbackPercent = 40;           // % de retroceso para entrada (0-100)
input int InpMinBreakoutPips = 5;               // Mínimo pips de breakout válido
input double InpBodyRangeRatio = 0.6;           // Body mínimo vs range (60%)

input group "=== SL NORMALIZADO CON ATR ==="
input int InpATRPeriod = 14;                    // ATR período
input double InpATRMinMultiplier = 0.8;         // ATR mínimo multiplicador
input double InpATRMaxMultiplier = 1.8;         // ATR máximo multiplicador

input group "=== PULLBACK MEJORADO ==="
input double InpCandleThirdRatio = 0.66;        // Ratio tercio vela (66%)

input group "=== DRAWDOWN CONTROL ==="
input double InpMaxDailyDD = 4.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 8.0;              // DD máximo semanal (%)

input group "=== GESTIÓN AVANZADA ==="
input bool InpUseBreakeven = true;              // Activar breakeven
input double InpBreakevenRR = 1.0;              // RR para activar breakeven
input int InpMagicNumber = 122001;              // Magic Number

//--- Global Variables
CTrade trade;
int emaHandle;
int atrHandle;
double emaBuffer[];
double atrBuffer[];

datetime lastBarTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;

double dailyStartBalance = 0;
double weeklyStartBalance = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;

bool dailyLimitReached = false;
bool weeklyLimitReached = false;

struct SwingPoint {
   double price;
   datetime time;
   bool isHigh;
};

SwingPoint lastSwing;
bool breakoutDetected = false;
bool waitingForPullback = false;
double breakoutLevel = 0;
double pullbackTarget = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configurar trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Crear indicador EMA200 en H1
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   // Crear indicador ATR en M15
   atrHandle = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) {
      Print("Error creando ATR: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   // Inicializar balance tracking
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   Print("═══════════════════════════════════════════════");
   Print("  EA V12.2 INSTITUTIONAL BREAKOUT");
   Print("═══════════════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M15");
   Print("Riesgo: ", InpRiskPercent, "%");
   Print("Risk:Reward: 1:", InpRiskReward);
   Print("SL: Normalizado ATR (", InpATRMinMultiplier, "-", InpATRMaxMultiplier, ")");
   Print("Breakeven: ", InpBreakevenRR, "R");
   Print("Max trades/día: ", InpMaxTradesPerDay);
   Print("═══════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
      
   Print("EA V12.2 detenido. Razón: ", reason);
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
   
   // Control de drawdown
   CheckDrawdownLimits();
   if(dailyLimitReached || weeklyLimitReached) {
      Comment("TRADING DETENIDO - Límite DD alcanzado");
      return;
   }
   
   // Reset contador diario
   ResetDailyTradeCount();
   
   // Verificar límite de trades
   if(tradesToday >= InpMaxTradesPerDay) {
      Comment("Límite diario alcanzado: ", tradesToday, "/", InpMaxTradesPerDay);
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
   ProcessBreakoutPullback();
   
   UpdateComment();
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
   
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) < 1) {
      Print("Error copiando ATR buffer: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Procesar lógica Breakout + Pullback                               |
//+------------------------------------------------------------------+
void ProcessBreakoutPullback()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   // Estado 1: Detectar breakout de swing
   if(!breakoutDetected) {
      DetectSwingBreakout();
   }
   
   // Estado 2: Esperar pullback y entrar
   if(breakoutDetected && waitingForPullback) {
      CheckPullbackEntry();
   }
}

//+------------------------------------------------------------------+
//| NUEVO: Verificar fuerza del breakout (body >= 60% range)          |
//+------------------------------------------------------------------+
bool CheckBreakoutStrength(int barIndex)
{
   double open = iOpen(_Symbol, PERIOD_M15, barIndex);
   double close = iClose(_Symbol, PERIOD_M15, barIndex);
   double high = iHigh(_Symbol, PERIOD_M15, barIndex);
   double low = iLow(_Symbol, PERIOD_M15, barIndex);
   
   double body = MathAbs(close - open);
   double range = high - low;
   
   if(range == 0) return false;
   
   double bodyRatio = body / range;
   
   return (bodyRatio >= InpBodyRangeRatio);
}

//+------------------------------------------------------------------+
//| Detectar breakout de swing high/low                               |
//+------------------------------------------------------------------+
void DetectSwingBreakout()
{
   // Encontrar último swing high
   double swingHigh = FindSwingHigh(InpSwingBars);
   // Encontrar último swing low
   double swingLow = FindSwingLow(InpSwingBars);
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   // CORREGIDO: MinBreakout sin * 10
   double minBreakout = InpMinBreakoutPips * _Point;
   
   // Breakout alcista
   if(high1 > swingHigh + minBreakout && close1 > swingHigh) {
      // NUEVO: Verificar fuerza del breakout
      if(!CheckBreakoutStrength(1)) {
         return; // Body muy pequeño, no es breakout fuerte
      }
      
      // Verificar filtro EMA (precio por encima)
      if(close1 > emaBuffer[0]) {
         breakoutDetected = true;
         waitingForPullback = true;
         breakoutLevel = swingHigh;
         
         // Calcular nivel de pullback (retroceso del X%)
         double breakoutRange = high1 - swingHigh;
         pullbackTarget = swingHigh + (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         lastSwing.price = swingHigh;
         lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
         lastSwing.isHigh = false; // Es un breakout alcista, esperamos pullback
         
         Print("✓ BREAKOUT ALCISTA detectado en ", swingHigh, " | Pullback target: ", pullbackTarget);
      }
   }
   
   // Breakout bajista
   if(low1 < swingLow - minBreakout && close1 < swingLow) {
      // NUEVO: Verificar fuerza del breakout
      if(!CheckBreakoutStrength(1)) {
         return; // Body muy pequeño, no es breakout fuerte
      }
      
      // Verificar filtro EMA (precio por debajo)
      if(close1 < emaBuffer[0]) {
         breakoutDetected = true;
         waitingForPullback = true;
         breakoutLevel = swingLow;
         
         // Calcular nivel de pullback
         double breakoutRange = swingLow - low1;
         pullbackTarget = swingLow - (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         lastSwing.price = swingLow;
         lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
         lastSwing.isHigh = true; // Es un breakout bajista, esperamos pullback
         
         Print("✓ BREAKOUT BAJISTA detectado en ", swingLow, " | Pullback target: ", pullbackTarget);
      }
   }
}

//+------------------------------------------------------------------+
//| NUEVO: Verificar calidad del pullback (cierre en tercio)          |
//+------------------------------------------------------------------+
bool CheckPullbackQuality(int barIndex, bool isBullish)
{
   double open = iOpen(_Symbol, PERIOD_M15, barIndex);
   double close = iClose(_Symbol, PERIOD_M15, barIndex);
   double high = iHigh(_Symbol, PERIOD_M15, barIndex);
   double low = iLow(_Symbol, PERIOD_M15, barIndex);
   
   double range = high - low;
   if(range == 0) return false;
   
   if(isBullish) {
      // Para BUY: cierre debe estar en tercio superior (>= 66%)
      double closePosition = (close - low) / range;
      return (closePosition >= InpCandleThirdRatio);
   }
   else {
      // Para SELL: cierre debe estar en tercio inferior (<= 34%)
      double closePosition = (close - low) / range;
      return (closePosition <= (1.0 - InpCandleThirdRatio));
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
   
   // Timeout: si pasan más de 20 velas sin pullback, cancelar
   if(iTime(_Symbol, PERIOD_M15, 1) - lastSwing.time > 20 * PeriodSeconds(PERIOD_M15)) {
      ResetBreakoutState();
      Print("Timeout: pullback no ocurrió en 20 velas");
      return;
   }
   
   // Entrada LONG (después de breakout alcista)
   if(!lastSwing.isHigh) {
      // Precio retrocedió al nivel de pullback y rebota
      if(low1 <= pullbackTarget && close1 > pullbackTarget) {
         // NUEVO: Verificar calidad del pullback
         if(!CheckPullbackQuality(1, true)) {
            return; // Vela no cierra en tercio superior
         }
         
         // Confirmar que sigue por encima de EMA
         if(close1 > emaBuffer[0]) {
            OpenTrade(ORDER_TYPE_BUY, pullbackTarget);
            ResetBreakoutState();
         }
      }
   }
   
   // Entrada SHORT (después de breakout bajista)
   if(lastSwing.isHigh) {
      // Precio retrocedió al nivel de pullback y rebota
      if(high1 >= pullbackTarget && close1 < pullbackTarget) {
         // NUEVO: Verificar calidad del pullback
         if(!CheckPullbackQuality(1, false)) {
            return; // Vela no cierra en tercio inferior
         }
         
         // Confirmar que sigue por debajo de EMA
         if(close1 < emaBuffer[0]) {
            OpenTrade(ORDER_TYPE_SELL, pullbackTarget);
            ResetBreakoutState();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Encontrar swing high                                              |
//+------------------------------------------------------------------+
double FindSwingHigh(int bars)
{
   double highest = 0;
   for(int i = 2; i <= bars + 2; i++) {
      double high = iHigh(_Symbol, PERIOD_M15, i);
      if(high > highest)
         highest = high;
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Encontrar swing low                                               |
//+------------------------------------------------------------------+
double FindSwingLow(int bars)
{
   double lowest = DBL_MAX;
   for(int i = 2; i <= bars + 2; i++) {
      double low = iLow(_Symbol, PERIOD_M15, i);
      if(low < lowest)
         lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Reset estado de breakout                                          |
//+------------------------------------------------------------------+
void ResetBreakoutState()
{
   breakoutDetected = false;
   waitingForPullback = false;
   breakoutLevel = 0;
   pullbackTarget = 0;
}

//+------------------------------------------------------------------+
//| NUEVO: Normalizar SL con ATR                                      |
//+------------------------------------------------------------------+
double NormalizeSL(double slStructure, double atr)
{
   double minSL = atr * InpATRMinMultiplier;
   double maxSL = atr * InpATRMaxMultiplier;
   
   double finalSL;
   
   if(slStructure < minSL) {
      finalSL = minSL;
      Print("  SL ajustado: estructura=", slStructure, " < minSL=", minSL, " → usando minSL");
   }
   else if(slStructure > maxSL) {
      finalSL = maxSL;
      Print("  SL ajustado: estructura=", slStructure, " > maxSL=", maxSL, " → usando maxSL");
   }
   else {
      finalSL = slStructure;
      Print("  SL estructura válido: ", slStructure, " (dentro de rango ATR)");
   }
   
   return finalSL;
}

//+------------------------------------------------------------------+
//| Abrir trade (MODIFICADO: SL normalizado con ATR)                  |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType, double entryReference)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Obtener ATR
   double atr = atrBuffer[0];
   if(atr <= 0) {
      Print("ATR inválido: ", atr);
      return;
   }
   
   // Calcular SL estructura (distancia al swing real)
   double entryPrice;
   double slStructure;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      slStructure = MathAbs(entryPrice - breakoutLevel);
   }
   else {
      entryPrice = bid;
      slStructure = MathAbs(breakoutLevel - entryPrice);
   }
   
   // NUEVO: Normalizar SL con ATR
   double slDistance = NormalizeSL(slStructure, atr);
   
   // Calcular SL y TP
   double sl, tp;
   
   if(orderType == ORDER_TYPE_BUY) {
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + (slDistance * InpRiskReward), _Digits);
   }
   else {
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - (slDistance * InpRiskReward), _Digits);
   }
   
   // Calcular lote basado en riesgo (usando distancia final normalizada)
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slPips = slDistance / point;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("Lote calculado muy pequeño: ", lotSize);
      return;
   }
   
   // Ejecutar orden
   string comment = StringFormat("V12.2_Inst_RR%.1f", InpRiskReward);
   
   if(orderType == ORDER_TYPE_BUY) {
      if(trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
         Print("✓ LONG abierto: Lote=", lotSize, " Entry=", entryPrice);
         Print("  SL=", sl, " (", DoubleToString(slPips, 1), " pips | ATR=", DoubleToString(atr, 2), ")");
         Print("  TP=", tp, " (", DoubleToString(slPips * InpRiskReward, 1), " pips)");
         tradesToday++;
         lastTradeDate = TimeCurrent();
      }
      else {
         Print("✗ Error abriendo LONG: ", trade.ResultRetcodeDescription());
      }
   }
   else {
      if(trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
         Print("✓ SHORT abierto: Lote=", lotSize, " Entry=", entryPrice);
         Print("  SL=", sl, " (", DoubleToString(slPips, 1), " pips | ATR=", DoubleToString(atr, 2), ")");
         Print("  TP=", tp, " (", DoubleToString(slPips * InpRiskReward, 1), " pips)");
         tradesToday++;
         lastTradeDate = TimeCurrent();
      }
      else {
         Print("✗ Error abriendo SHORT: ", trade.ResultRetcodeDescription());
      }
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
      
      // Breakeven
      if(InpUseBreakeven) {
         MoveToBreakeven(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Mover a breakeven (MODIFICADO: 1.0R)                              |
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
   
   // Verificar si alcanzó el nivel para breakeven
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
      double newSL = NormalizeDouble(posOpenPrice + (10 * _Point * ((posType == POSITION_TYPE_BUY) ? 1 : -1)), _Digits);
      
      if(trade.PositionModify(ticket, newSL, posTP)) {
         Print("✓ Breakeven activado (1.0R) para ticket ", ticket, " | Nuevo SL: ", newSL);
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
      Print("Nuevo día - Balance inicial: ", dailyStartBalance);
   }
   
   // Reset semanal (lunes)
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartBalance = currentBalance;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
      Print("Nueva semana - Balance inicial: ", weeklyStartBalance);
   }
   
   // Calcular DD
   double dailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   double weeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   // Verificar límites
   if(dailyDD >= InpMaxDailyDD) {
      dailyLimitReached = true;
      Print("⚠ LÍMITE DD DIARIO ALCANZADO: ", DoubleToString(dailyDD, 2), "%");
   }
   
   if(weeklyDD >= InpMaxWeeklyDD) {
      weeklyLimitReached = true;
      Print("⚠ LÍMITE DD SEMANAL ALCANZADO: ", DoubleToString(weeklyDD, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Reset contador de trades diarios                                  |
//+------------------------------------------------------------------+
void ResetDailyTradeCount()
{
   MqlDateTime currentTime, lastTradeTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastTradeDate, lastTradeTime);
   
   if(currentTime.day != lastTradeTime.day) {
      tradesToday = 0;
   }
}

//+------------------------------------------------------------------+
//| Actualizar comentario en gráfico                                  |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   double weeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   string status = "ACTIVO";
   if(dailyLimitReached) status = "DD DIARIO ALCANZADO";
   if(weeklyLimitReached) status = "DD SEMANAL ALCANZADO";
   if(tradesToday >= InpMaxTradesPerDay) status = "LÍMITE TRADES DIARIO";
   
   string breakoutStatus = "Buscando breakout...";
   if(breakoutDetected && waitingForPullback) {
      breakoutStatus = StringFormat("Esperando pullback a %.2f", pullbackTarget);
   }
   
   double atr = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] : 0;
   
   string comment = StringFormat(
      "═══════════════════════════════════════\n" +
      "  EA V12.2 INSTITUTIONAL\n" +
      "═══════════════════════════════════════\n" +
      "Estado: %s\n" +
      "Trades hoy: %d/%d\n" +
      "DD Diario: %.2f%% / %.1f%%\n" +
      "DD Semanal: %.2f%% / %.1f%%\n" +
      "───────────────────────────────────────\n" +
      "EMA200 H1: %.2f\n" +
      "ATR(14): %.2f (%.1f-%.1f)\n" +
      "Precio: %.2f\n" +
      "%s\n" +
      "───────────────────────────────────────\n" +
      "MEJORAS V12.2:\n" +
      "• SL normalizado ATR\n" +
      "• Filtro fuerza breakout\n" +
      "• Pullback mejorado\n" +
      "• Breakeven 1.0R\n" +
      "───────────────────────────────────────\n" +
      "Posiciones: %d\n" +
      "Balance: %.2f\n" +
      "═══════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay,
      dailyDD, InpMaxDailyDD,
      weeklyDD, InpMaxWeeklyDD,
      emaBuffer[0],
      atr, atr * InpATRMinMultiplier, atr * InpATRMaxMultiplier,
      SymbolInfoDouble(_Symbol, SYMBOL_BID),
      breakoutStatus,
      PositionsTotal(),
      currentBalance
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+
