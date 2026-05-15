//+------------------------------------------------------------------+
//|                        XAUUSD_V12_1_BREAKOUT_ENHANCED.mq5        |
//|                                    Estrategia Breakout + Pullback |
//|                                                                    |
//| V12.1 MEJORAS:                                                     |
//| + Filtro rango mínimo: Range(15) > 0.8 × ATR(14)                  |
//| + Filtro EMA20/EMA50 como condición adicional                     |
//| + Breakeven cambiado a 1.2R                                       |
//|                                                                    |
//| Timeframe: M15                                                     |
//| Filtro: EMA200 H1 + EMA20/50 M15                                  |
//| Lógica: Breakout de swing + pullback                               |
//| TP: 1.8 RR                                                         |
//| Riesgo: 0.5% por trade                                             |
//| Max trades: 2 diarios                                              |
//| DD Control: 4% diario, 8% semanal                                  |
//+------------------------------------------------------------------+
#property copyright "Breakout Pullback Enhanced System"
#property version   "12.10"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== CONFIGURACIÓN BÁSICA ==="
input double InpRiskPercent = 0.5;              // Riesgo por trade (%)
input double InpRiskReward = 1.8;               // Risk:Reward ratio
input int InpMaxTradesPerDay = 2;               // Máximo trades por día

input group "=== FILTRO TENDENCIA ==="
input int InpEMA200Period = 200;                // Período EMA200 (H1)
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;     // Timeframe EMA200
input int InpEMA20Period = 20;                  // Período EMA20 (M15)
input int InpEMA50Period = 50;                  // Período EMA50 (M15)

input group "=== BREAKOUT SETTINGS ==="
input int InpSwingBars = 10;                    // Barras para detectar swing high/low
input double InpPullbackPercent = 40;           // % de retroceso para entrada (0-100)
input int InpMinBreakoutPips = 5;               // Mínimo pips de breakout válido

input group "=== FILTRO VOLATILIDAD ==="
input int InpATRPeriod = 14;                    // ATR período
input int InpRangeBars = 15;                    // Barras para calcular rango
input double InpRangeMultiplier = 0.8;          // Multiplicador rango mínimo (Range > X * ATR)

input group "=== DRAWDOWN CONTROL ==="
input double InpMaxDailyDD = 4.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 8.0;              // DD máximo semanal (%)

input group "=== GESTIÓN AVANZADA ==="
input bool InpUseBreakeven = true;              // Activar breakeven
input double InpBreakevenRR = 1.2;              // RR para activar breakeven (CAMBIADO)
input int InpMagicNumber = 120101;              // Magic Number

//--- Global Variables
CTrade trade;
int emaHandle;
int ema20Handle;
int ema50Handle;
int atrHandle;

double emaBuffer[];
double ema20Buffer[];
double ema50Buffer[];
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
   
   // Crear indicadores
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   ema20Handle = iMA(_Symbol, PERIOD_M15, InpEMA20Period, 0, MODE_EMA, PRICE_CLOSE);
   if(ema20Handle == INVALID_HANDLE) {
      Print("Error creando EMA20: ", GetLastError());
      return INIT_FAILED;
   }
   
   ema50Handle = iMA(_Symbol, PERIOD_M15, InpEMA50Period, 0, MODE_EMA, PRICE_CLOSE);
   if(ema50Handle == INVALID_HANDLE) {
      Print("Error creando EMA50: ", GetLastError());
      return INIT_FAILED;
   }
   
   atrHandle = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) {
      Print("Error creando ATR: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(ema20Buffer, true);
   ArraySetAsSeries(ema50Buffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   // Inicializar balance tracking
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   Print("═══════════════════════════════════════════════");
   Print("  EA V12.1 BREAKOUT + PULLBACK ENHANCED");
   Print("═══════════════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M15");
   Print("Riesgo: ", InpRiskPercent, "%");
   Print("Risk:Reward: 1:", InpRiskReward);
   Print("Breakeven: ", InpBreakevenRR, "R");
   Print("Max trades/día: ", InpMaxTradesPerDay);
   Print("NUEVOS FILTROS:");
   Print("  - Rango mínimo: ", InpRangeMultiplier, " × ATR");
   Print("  - EMA20/50 M15");
   Print("═══════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(ema20Handle != INVALID_HANDLE) IndicatorRelease(ema20Handle);
   if(ema50Handle != INVALID_HANDLE) IndicatorRelease(ema50Handle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   
   Print("EA V12.1 detenido. Razón: ", reason);
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
      Print("Error copiando EMA200 buffer: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(ema20Handle, 0, 0, 3, ema20Buffer) < 3) {
      Print("Error copiando EMA20 buffer: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(ema50Handle, 0, 0, 3, ema50Buffer) < 3) {
      Print("Error copiando EMA50 buffer: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 3) {
      Print("Error copiando ATR buffer: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| NUEVO: Calcular rango de últimas N velas                          |
//+------------------------------------------------------------------+
double CalculateRange(int bars)
{
   double highest = 0;
   double lowest = DBL_MAX;
   
   for(int i = 1; i <= bars; i++) {
      double high = iHigh(_Symbol, PERIOD_M15, i);
      double low = iLow(_Symbol, PERIOD_M15, i);
      
      if(high > highest) highest = high;
      if(low < lowest) lowest = low;
   }
   
   return (highest - lowest);
}

//+------------------------------------------------------------------+
//| NUEVO: Verificar filtro de rango mínimo                           |
//+------------------------------------------------------------------+
bool CheckRangeFilter()
{
   double range = CalculateRange(InpRangeBars);
   double atr = atrBuffer[0];
   double minRange = atr * InpRangeMultiplier;
   
   bool passed = (range > minRange);
   
   if(!passed) {
      // Print("Filtro rango: Range=", range, " < MinRange=", minRange, " (", InpRangeMultiplier, " × ATR)");
   }
   
   return passed;
}

//+------------------------------------------------------------------+
//| NUEVO: Verificar filtro EMA20/EMA50                               |
//+------------------------------------------------------------------+
bool CheckEMAFilter(bool isBullish)
{
   double ema20 = ema20Buffer[0];
   double ema50 = ema50Buffer[0];
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   
   if(isBullish) {
      // Para LONG: EMA20 > EMA50 y precio > EMA20
      bool emaAligned = (ema20 > ema50);
      bool priceAbove = (close1 > ema20);
      return (emaAligned && priceAbove);
   }
   else {
      // Para SHORT: EMA20 < EMA50 y precio < EMA20
      bool emaAligned = (ema20 < ema50);
      bool priceBelow = (close1 < ema20);
      return (emaAligned && priceBelow);
   }
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
//| Detectar breakout de swing high/low                               |
//+------------------------------------------------------------------+
void DetectSwingBreakout()
{
   // NUEVO: Verificar filtro de rango primero
   if(!CheckRangeFilter()) {
      return; // No hay suficiente rango/volatilidad
   }
   
   // Encontrar último swing high
   double swingHigh = FindSwingHigh(InpSwingBars);
   // Encontrar último swing low
   double swingLow = FindSwingLow(InpSwingBars);
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   double minBreakout = InpMinBreakoutPips * _Point * 10;
   
   // Breakout alcista
   if(high1 > swingHigh + minBreakout && close1 > swingHigh) {
      // Verificar filtro EMA200 H1 (precio por encima)
      if(close1 > emaBuffer[0]) {
         // NUEVO: Verificar filtro EMA20/50
         if(CheckEMAFilter(true)) {
            breakoutDetected = true;
            waitingForPullback = true;
            breakoutLevel = swingHigh;
            
            // Calcular nivel de pullback (retroceso del X%)
            double breakoutRange = high1 - swingHigh;
            pullbackTarget = swingHigh + (breakoutRange * (1.0 - InpPullbackPercent/100.0));
            
            lastSwing.price = swingHigh;
            lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
            lastSwing.isHigh = false; // Es un breakout alcista, esperamos pullback
            
            Print("✓ BREAKOUT ALCISTA detectado en ", swingHigh);
            Print("  Pullback target: ", pullbackTarget);
            Print("  Filtros: Range ✓ | EMA20>50 ✓ | EMA200 ✓");
         }
      }
   }
   
   // Breakout bajista
   if(low1 < swingLow - minBreakout && close1 < swingLow) {
      // Verificar filtro EMA200 H1 (precio por debajo)
      if(close1 < emaBuffer[0]) {
         // NUEVO: Verificar filtro EMA20/50
         if(CheckEMAFilter(false)) {
            breakoutDetected = true;
            waitingForPullback = true;
            breakoutLevel = swingLow;
            
            // Calcular nivel de pullback
            double breakoutRange = swingLow - low1;
            pullbackTarget = swingLow - (breakoutRange * (1.0 - InpPullbackPercent/100.0));
            
            lastSwing.price = swingLow;
            lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
            lastSwing.isHigh = true; // Es un breakout bajista, esperamos pullback
            
            Print("✓ BREAKOUT BAJISTA detectado en ", swingLow);
            Print("  Pullback target: ", pullbackTarget);
            Print("  Filtros: Range ✓ | EMA20<50 ✓ | EMA200 ✓");
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
         // Confirmar que sigue por encima de EMA200
         if(close1 > emaBuffer[0]) {
            // NUEVO: Re-verificar filtro EMA20/50 antes de entrar
            if(CheckEMAFilter(true)) {
               OpenTrade(ORDER_TYPE_BUY, pullbackTarget);
               ResetBreakoutState();
            }
         }
      }
   }
   
   // Entrada SHORT (después de breakout bajista)
   if(lastSwing.isHigh) {
      // Precio retrocedió al nivel de pullback y rebota
      if(high1 >= pullbackTarget && close1 < pullbackTarget) {
         // Confirmar que sigue por debajo de EMA200
         if(close1 < emaBuffer[0]) {
            // NUEVO: Re-verificar filtro EMA20/50 antes de entrar
            if(CheckEMAFilter(false)) {
               OpenTrade(ORDER_TYPE_SELL, pullbackTarget);
               ResetBreakoutState();
            }
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
//| Abrir trade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType, double entryReference)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Calcular SL basado en la distancia al breakout level
   double slDistance;
   double entryPrice;
   double sl, tp;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      slDistance = MathAbs(entryPrice - breakoutLevel);
      
      // Mínimo 10 pips de SL
      if(slDistance < 100 * point)
         slDistance = 100 * point;
      
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + (slDistance * InpRiskReward), _Digits);
   }
   else {
      entryPrice = bid;
      slDistance = MathAbs(breakoutLevel - entryPrice);
      
      if(slDistance < 100 * point)
         slDistance = 100 * point;
      
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - (slDistance * InpRiskReward), _Digits);
   }
   
   // Calcular lote basado en riesgo
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slPips = slDistance / point;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("Lote calculado muy pequeño: ", lotSize);
      return;
   }
   
   // Ejecutar orden
   string comment = StringFormat("BP_V12.1_RR%.1f", InpRiskReward);
   
   if(orderType == ORDER_TYPE_BUY) {
      if(trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
         Print("✓ LONG abierto: Lote=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
         tradesToday++;
         lastTradeDate = TimeCurrent();
      }
      else {
         Print("✗ Error abriendo LONG: ", trade.ResultRetcodeDescription());
      }
   }
   else {
      if(trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
         Print("✓ SHORT abierto: Lote=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
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
//| Mover a breakeven (MODIFICADO: ahora 1.2R)                        |
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
   double breakevenTrigger = slDistance * InpBreakevenRR; // Ahora 1.2R
   
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
         Print("✓ Breakeven activado (1.2R) para ticket ", ticket, " | Nuevo SL: ", newSL);
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
   
   // Calcular rango actual
   double currentRange = CalculateRange(InpRangeBars);
   double minRange = atrBuffer[0] * InpRangeMultiplier;
   string rangeStatus = (currentRange > minRange) ? "✓" : "✗";
   
   // Estado EMA20/50
   string emaStatus = (ema20Buffer[0] > ema50Buffer[0]) ? "EMA20>50 ↑" : "EMA20<50 ↓";
   
   string comment = StringFormat(
      "═══════════════════════════════════════\n" +
      "  EA V12.1 BREAKOUT ENHANCED\n" +
      "═══════════════════════════════════════\n" +
      "Estado: %s\n" +
      "Trades hoy: %d/%d\n" +
      "DD Diario: %.2f%% / %.1f%%\n" +
      "DD Semanal: %.2f%% / %.1f%%\n" +
      "───────────────────────────────────────\n" +
      "FILTROS:\n" +
      "EMA200 H1: %.2f\n" +
      "%s\n" +
      "Rango(%d): %.2f %s (min: %.2f)\n" +
      "ATR(14): %.2f\n" +
      "───────────────────────────────────────\n" +
      "Precio: %.2f\n" +
      "%s\n" +
      "───────────────────────────────────────\n" +
      "Posiciones: %d\n" +
      "Balance: %.2f\n" +
      "Breakeven: %.1fR\n" +
      "═══════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay,
      dailyDD, InpMaxDailyDD,
      weeklyDD, InpMaxWeeklyDD,
      emaBuffer[0],
      emaStatus,
      InpRangeBars, currentRange, rangeStatus, minRange,
      atrBuffer[0],
      SymbolInfoDouble(_Symbol, SYMBOL_BID),
      breakoutStatus,
      PositionsTotal(),
      currentBalance,
      InpBreakevenRR
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+
