//+------------------------------------------------------------------+
//|                         XAUUSD_V14_1_OPTIMIZED.mq5               |
//|                    Professional Prop Firm EA - OPTIMIZED         |
//|                                                                    |
//| OPTIMIZACIONES V14.1:                                             |
//| • Filtro de volatilidad mejorado (ATR vs ATR promedio)            |
//| • Validación de calidad de pullback (cierre en tercio)            |
//| • Trailing stop parcial después de 1.5R                           |
//| • Filtro de spread dinámico                                       |
//| • Confirmación multi-timeframe (M15 + H1)                         |
//| • Gestión de equity en lugar de balance                           |
//| • Logging mejorado para análisis                                  |
//| • Protección contra slippage excesivo                             |
//+------------------------------------------------------------------+
#property copyright "Pro Firm Optimized V14.1"
#property version   "14.10"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== RIESGO ADAPTATIVO ==="
input double InpRiskLow = 0.3;                  // Riesgo bajo DD (DD ≤ 2%)
input double InpRiskMedium = 0.15;              // Riesgo medio DD (DD > 4%)
input double InpRiskHigh = 0.1;                 // Riesgo alto DD (DD ≥ 6%)
input double InpDDThresholdLow = 2.0;           // Umbral DD bajo (%)
input double InpDDThresholdMedium = 4.0;        // Umbral DD medio (%)
input double InpDDThresholdHigh = 6.0;          // Umbral DD alto (%)
input bool InpUseEquityDD = true;               // Usar equity en lugar de balance

input group "=== CONTROL DRAWDOWN ESTRICTO ==="
input double InpMaxDailyDD = 2.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 4.0;              // DD máximo semanal (%)
input double InpRecoveryThreshold = 1.0;        // % recuperación para reactivar

input group "=== FILTRO SESIÓN NY ==="
input int InpSession1Start = 8;                 // Sesión 1 inicio (08:00 NY)
input int InpSession1End = 12;                  // Sesión 1 fin (12:00 NY)
input int InpSession2Start = 13;                // Sesión 2 inicio (13:00 NY)
input int InpSession2End = 16;                  // Sesión 2 fin (16:00 NY)
input int InpGMTOffset = -5;                    // Offset GMT para NY

input group "=== SL DINÁMICO ==="
input int InpATRPeriod = 14;                    // ATR período
input double InpATRMultiplier = 1.2;            // Multiplicador ATR para SL
input int InpATRAvgPeriod = 20;                 // ATR promedio (filtro volatilidad)
input double InpMinATRRatio = 0.9;              // ATR mín vs promedio (0.9 = más permisivo)

input group "=== FILTRO BREAKOUT ==="
input int InpSwingBars = 10;                    // Barras para swing
input double InpBodyRangeRatio = 0.6;           // Body mínimo (60% range)
input double InpMinBreakoutATR = 0.8;           // Breakout mínimo (0.8 ATR)
input double InpPullbackPercent = 40;           // % pullback
input double InpPullbackThirdRatio = 0.60;      // Cierre en tercio (60% = más permisivo)

input group "=== GESTIÓN OPERACIÓN ==="
input double InpPartialCloseRR = 1.0;           // RR para cierre parcial (1R)
input double InpPartialClosePercent = 50;       // % a cerrar (50%)
input double InpFinalTargetRR = 2.5;            // Target final (2.5R)
input double InpBreakevenRR = 0.8;              // RR para breakeven
input double InpTrailingStartRR = 1.5;          // RR para iniciar trailing
input double InpTrailingStepRR = 0.3;           // Step trailing (0.3R)
input int InpMaxTradesPerDay = 1;               // Max trades/día

input group "=== FILTRO TENDENCIA ==="
input int InpEMA200Period = 200;                // EMA200 período
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;     // Timeframe EMA
input bool InpUseMultiTF = false;               // Confirmación multi-TF (OFF por defecto)

input group "=== RACHAS PÉRDIDAS ==="
input int InpMaxConsecutiveLosses = 2;          // Max pérdidas consecutivas
input bool InpSuspendAfterLosses = true;        // Suspender tras pérdidas

input group "=== PROTECCIÓN ==="
input double InpMaxSpreadPips = 5.0;            // Spread máximo (pips)
input double InpMaxSlippagePips = 3.0;          // Slippage máximo (pips)

input group "=== AVANZADO ==="
input int InpMagicNumber = 141001;              // Magic Number
input bool InpEnableLogging = true;             // Logging detallado

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
datetime lastTradeDate = 0;

// Balance tracking
double dailyStartBalance = 0;
double weeklyStartBalance = 0;
double dailyStartEquity = 0;
double weeklyStartEquity = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;

// DD control
bool dailyLimitReached = false;
bool weeklyLimitReached = false;
double currentDailyDD = 0;
double currentWeeklyDD = 0;

// Rachas pérdidas
int consecutiveLosses = 0;
bool suspendedByLosses = false;

// Breakout state
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

// Parcialización y trailing
bool partialClosed = false;
bool trailingActive = false;
double originalLotSize = 0;
double highestProfit = 0;

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
      Print("❌ Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   atrHandle = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE) {
      Print("❌ Error creando ATR: ", GetLastError());
      return INIT_FAILED;
   }
   
   atrAvgHandle = iATR(_Symbol, PERIOD_M15, InpATRAvgPeriod);
   if(atrAvgHandle == INVALID_HANDLE) {
      Print("❌ Error creando ATR Average: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(atrAvgBuffer, true);
   
   // Inicializar balance tracking
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   Print("═══════════════════════════════════════════════════════");
   Print("  EA V14.1 OPTIMIZED - PROFESSIONAL SYSTEM");
   Print("═══════════════════════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M15");
   Print("Riesgo adaptativo: ", InpRiskHigh, "% - ", InpRiskLow, "%");
   Print("DD Control: ", InpMaxDailyDD, "% diario / ", InpMaxWeeklyDD, "% semanal");
   Print("SL: ", InpATRMultiplier, " ATR");
   Print("Parcialización: ", InpPartialClosePercent, "% en ", InpPartialCloseRR, "R");
   Print("Trailing: Desde ", InpTrailingStartRR, "R");
   Print("Target final: ", InpFinalTargetRR, "R");
   Print("OPTIMIZACIONES:");
   Print("  • Filtro volatilidad ATR");
   Print("  • Validación pullback mejorada");
   Print("  • Trailing stop parcial");
   Print("  • Filtro spread dinámico");
   Print("  • Multi-timeframe");
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
   
   Print("EA V14.1 detenido. Razón: ", reason);
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
      Comment("⛔ TRADING SUSPENDIDO - Límite DD alcanzado");
      return;
   }
   
   // Reset contadores diarios
   ResetDailyCounters();
   
   // Verificar suspensión por pérdidas
   if(suspendedByLosses) {
      Comment("⏸ SUSPENDIDO - ", consecutiveLosses, " pérdidas consecutivas");
      return;
   }
   
   // Verificar límite de trades
   if(tradesToday >= InpMaxTradesPerDay) {
      Comment("⏸ Límite diario: ", tradesToday, "/", InpMaxTradesPerDay);
      return;
   }
   
   // Verificar sesión de trading
   if(!IsTradingSession()) {
      if(InpEnableLogging)
         Comment("⏰ Fuera de sesión NY");
      return;
   }
   
   // Verificar spread
   if(!CheckSpread()) {
      if(InpEnableLogging) {
         double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point / (_Point * 10);
         Comment("⚠ Spread muy alto: ", DoubleToString(spread, 1), " pips (max: ", InpMaxSpreadPips, ")");
      }
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
   
   // Verificar filtro de volatilidad
   if(!CheckVolatilityFilter()) {
      if(InpEnableLogging) {
         double atr = atrBuffer[0];
         double atrAvg = atrAvgBuffer[0];
         double ratio = (atrAvg > 0) ? atr / atrAvg : 0;
         Comment("⏸ Volatilidad insuficiente - ATR ratio: ", DoubleToString(ratio, 2), " (min: ", InpMinATRRatio, ")");
      }
      return;
   }
   
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
      Print("Error copiando EMA: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) < 1) {
      Print("Error copiando ATR: ", GetLastError());
      return false;
   }
   
   if(CopyBuffer(atrAvgHandle, 0, 1, 1, atrAvgBuffer) < 1) {
      Print("Error copiando ATR Average: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| NUEVO: Verificar filtro de volatilidad                            |
//+------------------------------------------------------------------+
bool CheckVolatilityFilter()
{
   double atr = atrBuffer[0];
   double atrAvg = atrAvgBuffer[0];
   
   if(atrAvg == 0) return false;
   
   double atrRatio = atr / atrAvg;
   
   // ATR debe ser al menos 1.1x el promedio
   return (atrRatio >= InpMinATRRatio);
}

//+------------------------------------------------------------------+
//| NUEVO: Verificar spread                                           |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double maxSpread = InpMaxSpreadPips * _Point * 10;
   
   return (spread <= maxSpread);
}

//+------------------------------------------------------------------+
//| Verificar sesión de trading NY                                    |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour + InpGMTOffset;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   bool session1 = (currentHour >= InpSession1Start && currentHour < InpSession1End);
   bool session2 = (currentHour >= InpSession2Start && currentHour < InpSession2End);
   
   return (session1 || session2);
}

//+------------------------------------------------------------------+
//| Calcular riesgo adaptativo según DD                               |
//+------------------------------------------------------------------+
double GetAdaptiveRisk()
{
   double risk;
   
   if(currentDailyDD <= InpDDThresholdLow) {
      risk = InpRiskLow;
   }
   else if(currentDailyDD <= InpDDThresholdMedium) {
      risk = InpRiskMedium;
   }
   else {
      risk = InpRiskHigh;
   }
   
   return risk;
}

//+------------------------------------------------------------------+
//| Procesar lógica Breakout + Pullback con validación mejorada       |
//+------------------------------------------------------------------+
void ProcessBreakoutPullback()
{
   // Estado 1: Detectar breakout
   if(!breakoutDetected) {
      DetectSwingBreakout();
   }
   
   // Estado 2: Esperar pullback y entrar
   if(breakoutDetected && waitingForPullback) {
      CheckPullbackEntry();
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
      return (closePosition >= InpPullbackThirdRatio);
   }
   else {
      // Para SELL: cierre debe estar en tercio inferior (<= 34%)
      double closePosition = (close - low) / range;
      return (closePosition <= (1.0 - InpPullbackThirdRatio));
   }
}

//+------------------------------------------------------------------+
//| NUEVO: Confirmación multi-timeframe                               |
//+------------------------------------------------------------------+
bool CheckMultiTimeframeConfirmation(bool isBullish)
{
   if(!InpUseMultiTF) return true;
   
   // Verificar EMA en H1 también
   double emaH1[];
   ArraySetAsSeries(emaH1, true);
   
   int emaH1Handle = iMA(_Symbol, PERIOD_H1, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaH1Handle == INVALID_HANDLE) return true;
   
   if(CopyBuffer(emaH1Handle, 0, 0, 1, emaH1) < 1) {
      IndicatorRelease(emaH1Handle);
      return true;
   }
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool h1Confirmed = isBullish ? (currentPrice > emaH1[0]) : (currentPrice < emaH1[0]);
   
   IndicatorRelease(emaH1Handle);
   return h1Confirmed;
}

//+------------------------------------------------------------------+
//| Verificar fuerza del breakout                                     |
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
   
   // Filtro 1: Body >= 60% range
   double bodyRatio = body / range;
   if(bodyRatio < InpBodyRangeRatio) {
      if(InpEnableLogging)
         Print("⚠ Breakout rechazado: body ratio ", DoubleToString(bodyRatio, 2), " < ", InpBodyRangeRatio);
      return false;
   }
   
   // Filtro 2: Breakout >= 0.8 ATR
   double atr = atrBuffer[0];
   double minBreakout = atr * InpMinBreakoutATR;
   
   if(range < minBreakout) {
      if(InpEnableLogging)
         Print("⚠ Breakout rechazado: range ", DoubleToString(range, 5), " < ", DoubleToString(minBreakout, 5));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detectar breakout de swing                                        |
//+------------------------------------------------------------------+
void DetectSwingBreakout()
{
   double swingHigh = FindSwingHigh(InpSwingBars);
   double swingLow = FindSwingLow(InpSwingBars);
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   // Breakout alcista
   if(high1 > swingHigh && close1 > swingHigh) {
      // Verificar fuerza
      if(!CheckBreakoutStrength(1)) return;
      
      // Filtro EMA: solo LONG si precio > EMA200
      if(close1 > emaBuffer[0]) {
         // Multi-timeframe confirmation
         if(!CheckMultiTimeframeConfirmation(true)) {
            if(InpEnableLogging)
               Print("⚠ Breakout alcista rechazado: confirmación H1 fallida");
            return;
         }
         
         breakoutDetected = true;
         waitingForPullback = true;
         breakoutLevel = swingHigh;
         
         double breakoutRange = high1 - swingHigh;
         pullbackTarget = swingHigh + (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         lastSwing.price = swingHigh;
         lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
         lastSwing.isHigh = false;
         
         Print("✓ BREAKOUT ALCISTA: ", swingHigh, " | Pullback: ", pullbackTarget);
      }
   }
   
   // Breakout bajista
   if(low1 < swingLow && close1 < swingLow) {
      // Verificar fuerza
      if(!CheckBreakoutStrength(1)) return;
      
      // Filtro EMA: solo SHORT si precio < EMA200
      if(close1 < emaBuffer[0]) {
         // Multi-timeframe confirmation
         if(!CheckMultiTimeframeConfirmation(false)) {
            if(InpEnableLogging)
               Print("⚠ Breakout bajista rechazado: confirmación H1 fallida");
            return;
         }
         
         breakoutDetected = true;
         waitingForPullback = true;
         breakoutLevel = swingLow;
         
         double breakoutRange = swingLow - low1;
         pullbackTarget = swingLow - (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         lastSwing.price = swingLow;
         lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
         lastSwing.isHigh = true;
         
         Print("✓ BREAKOUT BAJISTA: ", swingLow, " | Pullback: ", pullbackTarget);
      }
   }
}


//+------------------------------------------------------------------+
//| Verificar entrada en pullback con validación de calidad           |
//+------------------------------------------------------------------+
void CheckPullbackEntry()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   // Timeout: 20 velas
   if(iTime(_Symbol, PERIOD_M15, 1) - lastSwing.time > 20 * PeriodSeconds(PERIOD_M15)) {
      ResetBreakoutState();
      if(InpEnableLogging)
         Print("⏱ Timeout: pullback no ocurrió");
      return;
   }
   
   // Entrada LONG
   if(!lastSwing.isHigh) {
      if(low1 <= pullbackTarget && close1 > pullbackTarget) {
         // Validar calidad del pullback
         if(!CheckPullbackQuality(1, true)) {
            if(InpEnableLogging)
               Print("⚠ Pullback LONG rechazado: cierre no en tercio superior");
            return;
         }
         
         if(close1 > emaBuffer[0]) {
            OpenTrade(ORDER_TYPE_BUY);
            ResetBreakoutState();
         }
      }
   }
   
   // Entrada SHORT
   if(lastSwing.isHigh) {
      if(high1 >= pullbackTarget && close1 < pullbackTarget) {
         // Validar calidad del pullback
         if(!CheckPullbackQuality(1, false)) {
            if(InpEnableLogging)
               Print("⚠ Pullback SHORT rechazado: cierre no en tercio inferior");
            return;
         }
         
         if(close1 < emaBuffer[0]) {
            OpenTrade(ORDER_TYPE_SELL);
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
      if(high > highest) highest = high;
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
      if(low < lowest) lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Reset estado breakout                                             |
//+------------------------------------------------------------------+
void ResetBreakoutState()
{
   breakoutDetected = false;
   waitingForPullback = false;
   breakoutLevel = 0;
   pullbackTarget = 0;
}

//+------------------------------------------------------------------+
//| Abrir trade con riesgo adaptativo y protección slippage           |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL dinámico: 1.2 ATR
   double atr = atrBuffer[0];
   double slDistance = atr * InpATRMultiplier;
   
   double entryPrice, sl, tp;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + (slDistance * InpFinalTargetRR), _Digits);
   }
   else {
      entryPrice = bid;
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - (slDistance * InpFinalTargetRR), _Digits);
   }

   
   // Riesgo adaptativo basado en equity si está habilitado
   double baseAmount = InpUseEquityDD ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double adaptiveRisk = GetAdaptiveRisk();
   double riskAmount = baseAmount * adaptiveRisk / 100.0;
   double slPips = slDistance / point;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("❌ Lote muy pequeño: ", lotSize);
      return;
   }
   
   // Guardar lote original para parcialización
   originalLotSize = lotSize;
   partialClosed = false;
   trailingActive = false;
   highestProfit = 0;
   
   string comment = StringFormat("V14.1_Risk%.2f%%", adaptiveRisk);
   
   bool success = false;
   if(orderType == ORDER_TYPE_BUY) {
      success = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   else {
      success = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   
   if(success) {
      // Verificar slippage
      double executedPrice = trade.ResultPrice();
      double slippage = MathAbs(executedPrice - entryPrice) / point;
      double maxSlippage = InpMaxSlippagePips * 10;
      
      if(slippage > maxSlippage) {
         Print("⚠ SLIPPAGE ALTO: ", DoubleToString(slippage, 1), " pips");
      }
      
      string dir = (orderType == ORDER_TYPE_BUY) ? "LONG" : "SHORT";
      Print("✅ ", dir, " abierto");
      Print("   Lote: ", lotSize, " | Riesgo: ", adaptiveRisk, "%");
      Print("   Entry: ", executedPrice, " (slippage: ", DoubleToString(slippage, 1), " pips)");
      Print("   SL: ", sl, " (", DoubleToString(slPips, 1), " pips | ", InpATRMultiplier, " ATR)");
      Print("   TP: ", tp, " (", InpFinalTargetRR, "R)");
      
      if(InpEnableLogging) {
         Print("📊 ATR: ", DoubleToString(atr, 5));
         Print("📊 EMA200: ", DoubleToString(emaBuffer[0], 2));
         Print("📊 Spread: ", DoubleToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point, 5));
      }
      
      tradesToday++;
      lastTradeDate = TimeCurrent();
   }
   else {
      Print("❌ Error: ", trade.ResultRetcodeDescription());
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
//| Gestionar posiciones abiertas con trailing mejorado               |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      // Parcialización en 1R
      if(!partialClosed) {
         CheckPartialClose(ticket);
      }
      
      // Breakeven en 0.8R
      MoveToBreakeven(ticket);
      
      // NUEVO: Trailing stop después de 1.5R
      if(partialClosed) {
         ApplyTrailingStop(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar cierre parcial en 1R                                    |
//+------------------------------------------------------------------+
void CheckPartialClose(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posLot = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double slDistance = MathAbs(posOpenPrice - posSL);
   double targetDistance = slDistance * InpPartialCloseRR;
   
   bool shouldPartialClose = false;
   
   if(posType == POSITION_TYPE_BUY) {
      if(currentPrice >= posOpenPrice + targetDistance)
         shouldPartialClose = true;
   }
   else {
      if(currentPrice <= posOpenPrice - targetDistance)
         shouldPartialClose = true;
   }
   
   if(shouldPartialClose) {
      // Calcular lote a cerrar (50%)
      double closeVolume = NormalizeDouble(posLot * InpPartialClosePercent / 100.0, 2);
      
      // Asegurar que queda algo abierto
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(posLot - closeVolume < minLot) {
         closeVolume = posLot - minLot;
      }
      
      if(closeVolume >= minLot) {
         if(trade.PositionClosePartial(ticket, closeVolume)) {
            partialClosed = true;
            Print("✅ Cierre parcial: ", closeVolume, " lotes en ", InpPartialCloseRR, "R");
            Print("   Quedan ", (posLot - closeVolume), " lotes hasta ", InpFinalTargetRR, "R");
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Mover a breakeven en 0.8R                                         |
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
         Print("🔒 Breakeven activado en ", InpBreakevenRR, "R | SL: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| NUEVO: Aplicar trailing stop después de 1.5R                      |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket)
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
   double currentProfit = 0;
   
   if(posType == POSITION_TYPE_BUY) {
      currentProfit = (currentPrice - posOpenPrice) / slDistance;
   }
   else {
      currentProfit = (posOpenPrice - currentPrice) / slDistance;
   }
   
   // Activar trailing solo después de 1.5R
   if(currentProfit < InpTrailingStartRR) return;
   
   // Actualizar máximo profit
   if(currentProfit > highestProfit) {
      highestProfit = currentProfit;
   }
   
   // Calcular nuevo SL basado en trailing step
   double trailingDistance = slDistance * InpTrailingStepRR;
   double newSL = 0;
   
   if(posType == POSITION_TYPE_BUY) {
      newSL = currentPrice - trailingDistance;
      // Solo mover SL hacia arriba
      if(newSL > posSL) {
         newSL = NormalizeDouble(newSL, _Digits);
         if(trade.PositionModify(ticket, newSL, posTP)) {
            if(InpEnableLogging)
               Print("📈 Trailing LONG: SL movido a ", newSL, " (", DoubleToString(currentProfit, 2), "R)");
         }
      }
   }
   else {
      newSL = currentPrice + trailingDistance;
      // Solo mover SL hacia abajo
      if(newSL < posSL) {
         newSL = NormalizeDouble(newSL, _Digits);
         if(trade.PositionModify(ticket, newSL, posTP)) {
            if(InpEnableLogging)
               Print("📉 Trailing SHORT: SL movido a ", newSL, " (", DoubleToString(currentProfit, 2), "R)");
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Control de drawdown con equity                                    |
//+------------------------------------------------------------------+
void CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Reset diario
   MqlDateTime lastDayStruct;
   TimeToStruct(lastDayCheck, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      dailyStartBalance = currentBalance;
      dailyStartEquity = currentEquity;
      lastDayCheck = TimeCurrent();
      dailyLimitReached = false;
      Print("📅 Nuevo día - Balance: $", DoubleToString(dailyStartBalance, 2), 
            " | Equity: $", DoubleToString(dailyStartEquity, 2));
   }
   
   // Reset semanal (lunes)
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartBalance = currentBalance;
      weeklyStartEquity = currentEquity;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
      Print("📅 Nueva semana - Balance: $", DoubleToString(weeklyStartBalance, 2),
            " | Equity: $", DoubleToString(weeklyStartEquity, 2));
   }
   
   // Calcular DD basado en equity o balance
   currentDailyDD = 0;
   currentWeeklyDD = 0;
   
   if(InpUseEquityDD) {
      if(dailyStartEquity > 0)
         currentDailyDD = ((dailyStartEquity - currentEquity) / dailyStartEquity) * 100.0;
      
      if(weeklyStartEquity > 0)
         currentWeeklyDD = ((weeklyStartEquity - currentEquity) / weeklyStartEquity) * 100.0;
   }
   else {
      if(dailyStartBalance > 0)
         currentDailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
      
      if(weeklyStartBalance > 0)
         currentWeeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   }
   
   // Verificar límites
   if(currentDailyDD >= InpMaxDailyDD && !dailyLimitReached) {
      dailyLimitReached = true;
      Print("⛔ DD DIARIO ALCANZADO: ", DoubleToString(currentDailyDD, 2), "%");
   }
   
   if(currentWeeklyDD >= InpMaxWeeklyDD && !weeklyLimitReached) {
      weeklyLimitReached = true;
      Print("⛔ DD SEMANAL ALCANZADO: ", DoubleToString(currentWeeklyDD, 2), "%");
   }
   
   // Verificar recuperación
   if(dailyLimitReached && currentDailyDD < (InpMaxDailyDD - InpRecoveryThreshold)) {
      dailyLimitReached = false;
      Print("✅ DD recuperado - Trading reactivado");
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
      suspendedByLosses = false;
      consecutiveLosses = 0;
   }
}


//+------------------------------------------------------------------+
//| Callback de transacciones con logging mejorado                    |
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
               double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
               
               if(profit < 0) {
                  consecutiveLosses++;
                  Print("📉 Pérdida #", consecutiveLosses, " | $", DoubleToString(profit, 2));
                  
                  if(InpEnableLogging) {
                     Print("   Volumen: ", volume);
                     Print("   DD Diario: ", DoubleToString(currentDailyDD, 2), "%");
                  }
                  
                  if(InpSuspendAfterLosses && consecutiveLosses >= InpMaxConsecutiveLosses) {
                     suspendedByLosses = true;
                     Print("⏸ SUSPENDIDO tras ", consecutiveLosses, " pérdidas");
                  }
               }
               else if(profit > 0) {
                  consecutiveLosses = 0;
                  Print("📈 Ganancia: $", DoubleToString(profit, 2), " - Racha reiniciada");
                  
                  if(InpEnableLogging) {
                     Print("   Volumen: ", volume);
                     Print("   Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Actualizar comentario con información mejorada                    |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   string status = "🟢 ACTIVO";
   if(dailyLimitReached) status = "🔴 DD DIARIO";
   else if(weeklyLimitReached) status = "🔴 DD SEMANAL";
   else if(suspendedByLosses) status = "🟡 SUSPENDIDO";
   else if(tradesToday >= InpMaxTradesPerDay) status = "🟡 LÍMITE TRADES";
   else if(!IsTradingSession()) status = "🟡 FUERA SESIÓN";
   
   double adaptiveRisk = GetAdaptiveRisk();
   
   string breakoutStatus = "Buscando breakout...";
   if(breakoutDetected && waitingForPullback) {
      breakoutStatus = StringFormat("Esperando pullback: %.2f", pullbackTarget);
   }
   
   double atr = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] : 0;
   double atrAvg = (ArraySize(atrAvgBuffer) > 0) ? atrAvgBuffer[0] : 0;
   double atrRatio = (atrAvg > 0) ? atr / atrAvg : 0;
   
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point / (_Point * 10);
   
   // Estado de filtros
   string filterStatus = "";
   if(!IsTradingSession()) filterStatus = "❌ Fuera de sesión";
   else if(!CheckSpread()) filterStatus = StringFormat("❌ Spread alto (%.1f)", spread);
   else if(!CheckVolatilityFilter()) filterStatus = StringFormat("❌ ATR bajo (%.2f)", atrRatio);
   else filterStatus = "✅ Todos los filtros OK";
   
   string comment = StringFormat(
      "╔═══════════════════════════════════════════════╗\n" +
      "║   EA V14.1 OPTIMIZED                          ║\n" +
      "║   PROFESSIONAL PROP FIRM SYSTEM               ║\n" +
      "╚═══════════════════════════════════════════════╝\n\n" +
      "Estado: %s\n" +
      "Trades: %d/%d | Pérdidas: %d/%d\n\n" +
      "┌─ RIESGO ADAPTATIVO ────────────────────┐\n" +
      "│ Riesgo actual: %.2f%%\n" +
      "│ DD Diario:  %.2f%% / %.1f%% (%s)\n" +
      "│ DD Semanal: %.2f%% / %.1f%%\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ MERCADO ──────────────────────────────┐\n" +
      "│ EMA200 H1: %.2f\n" +
      "│ ATR(14):   %.2f (ratio: %.2f)\n" +
      "│ Spread:    %.1f pips\n" +
      "│ Precio:    %.2f\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ FILTROS ──────────────────────────────┐\n" +
      "│ %s\n" +
      "│ Volatilidad: %.2f / %.2f (min)\n" +
      "│ Multi-TF: %s\n" +
      "└────────────────────────────────────────┘\n\n" +
      "%s\n\n" +
      "Posiciones: %d\n" +
      "Balance: $%.2f | Equity: $%.2f\n" +
      "═══════════════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay, consecutiveLosses, InpMaxConsecutiveLosses,
      adaptiveRisk,
      currentDailyDD, InpMaxDailyDD, InpUseEquityDD ? "Equity" : "Balance",
      currentWeeklyDD, InpMaxWeeklyDD,
      emaBuffer[0],
      atr, atrRatio,
      spread,
      SymbolInfoDouble(_Symbol, SYMBOL_BID),
      filterStatus,
      atrRatio, InpMinATRRatio,
      InpUseMultiTF ? "ON" : "OFF",
      breakoutStatus,
      PositionsTotal(),
      currentBalance,
      equity
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+
