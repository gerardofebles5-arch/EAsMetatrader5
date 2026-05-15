//+------------------------------------------------------------------+
//|                         XAUUSD_V15_0_PROP_FIRM_ELITE.mq5         |
//|                    ELITE PROP FIRM SYSTEM - OPTIMIZED            |
//|                                                                    |
//| ENFOQUE: Profitable y sostenible para fondeo                      |
//| FILOSOFÍA: Calidad extrema, DD mínimo, consistencia máxima        |
//|                                                                    |
//| MEJORAS V15.0:                                                    |
//| • Detección de estructura de mercado (HH/HL/LH/LL)                |
//| • Breakout solo con confirmación de estructura                    |
//| • Pullback a zona de valor (Fibonacci 50%-61.8%)                  |
//| • SL inteligente: último swing + buffer                           |
//| • TP escalonado: 1R (30%), 1.5R (30%), 2R+ (40% trailing)         |
//| • Filtro de momentum (RSI)                                        |
//| • Filtro de tendencia multi-TF (EMA 20/50/200)                    |
//| • Solo mejores sesiones (Londres + NY overlap)                    |
//| • Max 1 trade/día, pausa tras pérdida                             |
//| • DD ultra-conservador: 1.5% diario, 3% semanal                   |
//+------------------------------------------------------------------+
#property copyright "Elite Prop Firm System V15.0"
#property version   "15.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== RIESGO ULTRA-CONSERVADOR ==="
input double InpRiskPercent = 0.5;              // Riesgo por trade (%)
input double InpMaxDailyDD = 1.5;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 3.0;              // DD máximo semanal (%)

input group "=== SESIÓN ÓPTIMA ==="
input int InpLondonStart = 8;                   // Londres inicio (08:00 GMT)
input int InpLondonEnd = 12;                    // Londres fin (12:00 GMT)
input int InpNYStart = 13;                      // NY inicio (13:00 GMT)
input int InpNYEnd = 17;                        // NY fin (17:00 GMT)
input int InpGMTOffset = 0;                     // Offset GMT

input group "=== ESTRUCTURA DE MERCADO ==="
input int InpSwingBars = 15;                    // Barras para swing (estructura)
input double InpMinBreakoutPips = 20;           // Breakout mínimo (pips)
input double InpFiboPullbackMin = 0.50;         // Fibo pullback mín (50%)
input double InpFiboPullbackMax = 0.618;        // Fibo pullback máx (61.8%)

input group "=== FILTROS INSTITUCIONALES ==="
input int InpEMA20Period = 20;                  // EMA rápida
input int InpEMA50Period = 50;                  // EMA media
input int InpEMA200Period = 200;                // EMA lenta
input int InpRSIPeriod = 14;                    // RSI período
input int InpRSIOverbought = 70;                // RSI sobrecompra
input int InpRSIOversold = 30;                  // RSI sobreventa
input double InpMinATR = 15.0;                  // ATR mínimo (pips)

input group "=== GESTIÓN INTELIGENTE ==="
input double InpSLBufferPips = 5;               // Buffer SL (pips)
input double InpTP1_RR = 1.0;                   // TP1 (1R)
input double InpTP1_Percent = 30;               // % cerrar en TP1
input double InpTP2_RR = 1.5;                   // TP2 (1.5R)
input double InpTP2_Percent = 30;               // % cerrar en TP2
input double InpTrailingStart_RR = 1.8;         // Trailing desde (1.8R)
input double InpTrailingStep_Pips = 10;         // Trailing step (pips)
input double InpBreakeven_RR = 0.6;             // Breakeven (0.6R)

input group "=== CONTROL OPERATIVO ==="
input int InpMaxTradesPerDay = 1;               // Max trades/día
input bool InpPauseAfterLoss = true;            // Pausa tras pérdida
input int InpMaxConsecutiveLosses = 1;          // Max pérdidas consecutivas

input group "=== AVANZADO ==="
input int InpMagicNumber = 150001;              // Magic Number
input bool InpShowDebug = true;                 // Mostrar debug

//--- Global Variables
CTrade trade;
int emaHandle20, emaHandle50, emaHandle200;
int rsiHandle, atrHandle;
double ema20[], ema50[], ema200[];
double rsiBuffer[], atrBuffer[];

datetime lastBarTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;

// Balance tracking
double dailyStartBalance = 0;
double weeklyStartBalance = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;
bool dailyLimitReached = false;
bool weeklyLimitReached = false;

// Pérdidas
int consecutiveLosses = 0;
bool pausedAfterLoss = false;

// Estructura de mercado
enum MarketStructure {
   STRUCTURE_NONE,
   STRUCTURE_BULLISH,    // HH + HL
   STRUCTURE_BEARISH     // LH + LL
};

struct SwingPoint {
   double price;
   datetime time;
   int barIndex;
};

SwingPoint lastHigh, lastLow;
SwingPoint prevHigh, prevLow;
MarketStructure currentStructure = STRUCTURE_NONE;

// Breakout state
bool breakoutDetected = false;
bool waitingForPullback = false;
double breakoutLevel = 0;
double swingLevel = 0;
double fiboPullbackMin = 0;
double fiboPullbackMax = 0;
bool isBullishBreakout = false;

// Parcialización
int tp1Closed = 0;  // 0=no, 1=cerrado
int tp2Closed = 0;
double originalLotSize = 0;

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
   emaHandle20 = iMA(_Symbol, PERIOD_M15, InpEMA20Period, 0, MODE_EMA, PRICE_CLOSE);
   emaHandle50 = iMA(_Symbol, PERIOD_M15, InpEMA50Period, 0, MODE_EMA, PRICE_CLOSE);
   emaHandle200 = iMA(_Symbol, PERIOD_H1, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_M15, 14);
   
   if(emaHandle20 == INVALID_HANDLE || emaHandle50 == INVALID_HANDLE || 
      emaHandle200 == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || 
      atrHandle == INVALID_HANDLE) {
      Print("❌ Error creando indicadores");
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(ema20, true);
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   // Inicializar balance
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   Print("═══════════════════════════════════════════════════════");
   Print("  EA V15.0 PROP FIRM ELITE");
   Print("  PROFITABLE & SUSTAINABLE FOR FUNDING");
   Print("═══════════════════════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Riesgo: ", InpRiskPercent, "%");
   Print("DD Control: ", InpMaxDailyDD, "% / ", InpMaxWeeklyDD, "%");
   Print("TP Escalonado: ", InpTP1_Percent, "%@", InpTP1_RR, "R + ",
         InpTP2_Percent, "%@", InpTP2_RR, "R + Trailing");
   Print("Max trades/día: ", InpMaxTradesPerDay);
   Print("═══════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle20 != INVALID_HANDLE) IndicatorRelease(emaHandle20);
   if(emaHandle50 != INVALID_HANDLE) IndicatorRelease(emaHandle50);
   if(emaHandle200 != INVALID_HANDLE) IndicatorRelease(emaHandle200);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   
   Print("EA V15.0 detenido. Razón: ", reason);
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
      Comment("⛔ DD LÍMITE ALCANZADO");
      return;
   }
   
   // Reset contadores
   ResetDailyCounters();
   
   // Verificar pausa tras pérdida
   if(pausedAfterLoss) {
      Comment("⏸ PAUSADO - Esperando nuevo día");
      return;
   }
   
   // Límite de trades
   if(tradesToday >= InpMaxTradesPerDay) {
      Comment("⏸ Límite diario alcanzado");
      return;
   }
   
   // Verificar sesión
   if(!IsTradingSession()) {
      Comment("⏰ Fuera de sesión óptima");
      return;
   }
   
   // Gestionar posiciones
   ManageOpenPositions();
   
   // Solo buscar señales si no hay posiciones
   if(PositionsTotal() > 0)
      return;
   
   // Actualizar indicadores
   if(!UpdateIndicators())
      return;
   
   // Verificar filtros básicos
   if(!CheckBasicFilters())
      return;
   
   // Lógica principal
   ProcessMarketStructure();
   
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Actualizar indicadores                                            |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(emaHandle20, 0, 0, 3, ema20) < 3) return false;
   if(CopyBuffer(emaHandle50, 0, 0, 3, ema50) < 3) return false;
   if(CopyBuffer(emaHandle200, 0, 0, 3, ema200) < 3) return false;
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3) return false;
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) < 1) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Verificar sesión óptima                                           |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour + InpGMTOffset;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   // Londres: 08:00-12:00 o NY: 13:00-17:00
   bool london = (currentHour >= InpLondonStart && currentHour < InpLondonEnd);
   bool ny = (currentHour >= InpNYStart && currentHour < InpNYEnd);
   
   return (london || ny);
}

//+------------------------------------------------------------------+
//| Verificar filtros básicos                                         |
//+------------------------------------------------------------------+
bool CheckBasicFilters()
{
   // ATR mínimo
   double atr = atrBuffer[0];
   double atrPips = atr / (_Point * 10);
   
   if(atrPips < InpMinATR) {
      if(InpShowDebug)
         Print("⚠ ATR bajo: ", DoubleToString(atrPips, 1), " pips");
      return false;
   }
   
   return true;
}


//+------------------------------------------------------------------+
//| Procesar estructura de mercado                                    |
//+------------------------------------------------------------------+
void ProcessMarketStructure()
{
   // Paso 1: Identificar estructura (HH/HL o LH/LL)
   if(currentStructure == STRUCTURE_NONE) {
      IdentifyMarketStructure();
   }
   
   // Paso 2: Detectar breakout con confirmación
   if(currentStructure != STRUCTURE_NONE && !breakoutDetected) {
      DetectStructureBreakout();
   }
   
   // Paso 3: Esperar pullback a zona Fibonacci
   if(breakoutDetected && waitingForPullback) {
      CheckFiboPullback();
   }
}

//+------------------------------------------------------------------+
//| Identificar estructura de mercado                                 |
//+------------------------------------------------------------------+
void IdentifyMarketStructure()
{
   // Encontrar últimos swings
   FindSwingPoints();
   
   // Verificar si tenemos swings válidos
   if(lastHigh.price == 0 || lastLow.price == 0 || 
      prevHigh.price == 0 || prevLow.price == 0)
      return;
   
   // Estructura alcista: HH + HL
   bool higherHigh = (lastHigh.price > prevHigh.price);
   bool higherLow = (lastLow.price > prevLow.price);
   
   // Estructura bajista: LH + LL
   bool lowerHigh = (lastHigh.price < prevHigh.price);
   bool lowerLow = (lastLow.price < prevLow.price);
   
   if(higherHigh && higherLow) {
      currentStructure = STRUCTURE_BULLISH;
      if(InpShowDebug)
         Print("📈 Estructura ALCISTA detectada (HH + HL)");
   }
   else if(lowerHigh && lowerLow) {
      currentStructure = STRUCTURE_BEARISH;
      if(InpShowDebug)
         Print("📉 Estructura BAJISTA detectada (LH + LL)");
   }
}

//+------------------------------------------------------------------+
//| Encontrar swing points                                            |
//+------------------------------------------------------------------+
void FindSwingPoints()
{
   double highestHigh = 0;
   double lowestLow = DBL_MAX;
   int highBar = 0, lowBar = 0;
   
   // Buscar último swing high
   for(int i = 2; i <= InpSwingBars + 2; i++) {
      double high = iHigh(_Symbol, PERIOD_M15, i);
      if(high > highestHigh) {
         highestHigh = high;
         highBar = i;
      }
   }
   
   // Buscar último swing low
   for(int i = 2; i <= InpSwingBars + 2; i++) {
      double low = iLow(_Symbol, PERIOD_M15, i);
      if(low < lowestLow) {
         lowestLow = low;
         lowBar = i;
      }
   }
   
   // Actualizar swings
   if(lastHigh.price != highestHigh) {
      prevHigh = lastHigh;
      lastHigh.price = highestHigh;
      lastHigh.time = iTime(_Symbol, PERIOD_M15, highBar);
      lastHigh.barIndex = highBar;
   }
   
   if(lastLow.price != lowestLow) {
      prevLow = lastLow;
      lastLow.price = lowestLow;
      lastLow.time = iTime(_Symbol, PERIOD_M15, lowBar);
      lastLow.barIndex = lowBar;
   }
}

//+------------------------------------------------------------------+
//| Detectar breakout de estructura                                   |
//+------------------------------------------------------------------+
void DetectStructureBreakout()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   // Breakout alcista (rompe último high)
   if(currentStructure == STRUCTURE_BULLISH && high1 > lastHigh.price) {
      double breakoutSize = (high1 - lastHigh.price) / (_Point * 10);
      
      if(breakoutSize >= InpMinBreakoutPips) {
         // Verificar filtros
         if(!CheckTrendFilters(true)) return;
         if(!CheckMomentumFilter(true)) return;
         
         breakoutDetected = true;
         waitingForPullback = true;
         isBullishBreakout = true;
         breakoutLevel = lastHigh.price;
         swingLevel = lastLow.price;
         
         // Calcular zona Fibonacci
         double range = breakoutLevel - swingLevel;
         fiboPullbackMin = breakoutLevel - (range * InpFiboPullbackMin);
         fiboPullbackMax = breakoutLevel - (range * InpFiboPullbackMax);
         
         Print("✅ BREAKOUT ALCISTA: ", breakoutLevel);
         Print("   Zona pullback: ", fiboPullbackMax, " - ", fiboPullbackMin);
      }
   }
   
   // Breakout bajista (rompe último low)
   if(currentStructure == STRUCTURE_BEARISH && low1 < lastLow.price) {
      double breakoutSize = (lastLow.price - low1) / (_Point * 10);
      
      if(breakoutSize >= InpMinBreakoutPips) {
         // Verificar filtros
         if(!CheckTrendFilters(false)) return;
         if(!CheckMomentumFilter(false)) return;
         
         breakoutDetected = true;
         waitingForPullback = true;
         isBullishBreakout = false;
         breakoutLevel = lastLow.price;
         swingLevel = lastHigh.price;
         
         // Calcular zona Fibonacci
         double range = swingLevel - breakoutLevel;
         fiboPullbackMin = breakoutLevel + (range * InpFiboPullbackMin);
         fiboPullbackMax = breakoutLevel + (range * InpFiboPullbackMax);
         
         Print("✅ BREAKOUT BAJISTA: ", breakoutLevel);
         Print("   Zona pullback: ", fiboPullbackMin, " - ", fiboPullbackMax);
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar filtros de tendencia                                    |
//+------------------------------------------------------------------+
bool CheckTrendFilters(bool isBullish)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(isBullish) {
      // Para LONG: precio > EMA20 > EMA50 > EMA200
      if(price < ema20[0]) return false;
      if(ema20[0] < ema50[0]) return false;
      if(ema50[0] < ema200[0]) return false;
   }
   else {
      // Para SHORT: precio < EMA20 < EMA50 < EMA200
      if(price > ema20[0]) return false;
      if(ema20[0] > ema50[0]) return false;
      if(ema50[0] > ema200[0]) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Verificar filtro de momentum                                      |
//+------------------------------------------------------------------+
bool CheckMomentumFilter(bool isBullish)
{
   double rsi = rsiBuffer[0];
   
   if(isBullish) {
      // Para LONG: RSI no sobrecomprado
      if(rsi >= InpRSIOverbought) {
         if(InpShowDebug)
            Print("⚠ RSI sobrecomprado: ", DoubleToString(rsi, 1));
         return false;
      }
   }
   else {
      // Para SHORT: RSI no sobrevendido
      if(rsi <= InpRSIOversold) {
         if(InpShowDebug)
            Print("⚠ RSI sobrevendido: ", DoubleToString(rsi, 1));
         return false;
      }
   }
   
   return true;
}


//+------------------------------------------------------------------+
//| Verificar pullback a zona Fibonacci                               |
//+------------------------------------------------------------------+
void CheckFiboPullback()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   
   // Timeout: 30 velas
   if(iTime(_Symbol, PERIOD_M15, 1) - lastHigh.time > 30 * PeriodSeconds(PERIOD_M15)) {
      ResetBreakoutState();
      if(InpShowDebug)
         Print("⏱ Timeout: pullback no ocurrió");
      return;
   }
   
   // Entrada LONG
   if(isBullishBreakout) {
      // Precio debe tocar zona Fibo y rebotar
      if(low1 <= fiboPullbackMax && close1 >= fiboPullbackMin) {
         // Confirmar que sigue en tendencia
         if(CheckTrendFilters(true)) {
            OpenTrade(ORDER_TYPE_BUY);
            ResetBreakoutState();
         }
      }
   }
   
   // Entrada SHORT
   if(!isBullishBreakout) {
      // Precio debe tocar zona Fibo y rebotar
      if(high1 >= fiboPullbackMin && close1 <= fiboPullbackMax) {
         // Confirmar que sigue en tendencia
         if(CheckTrendFilters(false)) {
            OpenTrade(ORDER_TYPE_SELL);
            ResetBreakoutState();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset estado breakout                                             |
//+------------------------------------------------------------------+
void ResetBreakoutState()
{
   breakoutDetected = false;
   waitingForPullback = false;
   breakoutLevel = 0;
   swingLevel = 0;
   fiboPullbackMin = 0;
   fiboPullbackMax = 0;
   currentStructure = STRUCTURE_NONE;
}

//+------------------------------------------------------------------+
//| Abrir trade con gestión inteligente                               |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double entryPrice, sl, tp;
   double slBuffer = InpSLBufferPips * point * 10;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      // SL: último swing low - buffer
      sl = NormalizeDouble(swingLevel - slBuffer, _Digits);
      // TP: calculado con RR final (usaremos parcialización)
      double slDistance = entryPrice - sl;
      tp = NormalizeDouble(entryPrice + (slDistance * 2.5), _Digits);
   }
   else {
      entryPrice = bid;
      // SL: último swing high + buffer
      sl = NormalizeDouble(swingLevel + slBuffer, _Digits);
      // TP: calculado con RR final
      double slDistance = sl - entryPrice;
      tp = NormalizeDouble(entryPrice - (slDistance * 2.5), _Digits);
   }
   
   // Calcular lote
   double slDistance = MathAbs(entryPrice - sl);
   double slPips = slDistance / point;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("❌ Lote muy pequeño: ", lotSize);
      return;
   }
   
   // Guardar para parcialización
   originalLotSize = lotSize;
   tp1Closed = 0;
   tp2Closed = 0;
   
   string comment = StringFormat("V15_Elite_%.1fR", InpTP1_RR);
   
   bool success = false;
   if(orderType == ORDER_TYPE_BUY) {
      success = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   else {
      success = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   
   if(success) {
      string dir = (orderType == ORDER_TYPE_BUY) ? "LONG" : "SHORT";
      Print("✅ ", dir, " ABIERTO");
      Print("   Entry: ", entryPrice);
      Print("   SL: ", sl, " (", DoubleToString(slPips, 1), " pips)");
      Print("   TP: ", tp);
      Print("   Lote: ", lotSize);
      Print("   Estructura: ", (currentStructure == STRUCTURE_BULLISH) ? "ALCISTA" : "BAJISTA");
      
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
//| Gestionar posiciones abiertas con TP escalonado                   |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      // Breakeven
      MoveToBreakeven(ticket);
      
      // TP1: 30% en 1R
      if(tp1Closed == 0) {
         CheckPartialClose(ticket, InpTP1_RR, InpTP1_Percent, 1);
      }
      
      // TP2: 30% en 1.5R
      if(tp1Closed == 1 && tp2Closed == 0) {
         CheckPartialClose(ticket, InpTP2_RR, InpTP2_Percent, 2);
      }
      
      // Trailing: 40% restante desde 1.8R
      if(tp1Closed == 1 && tp2Closed == 1) {
         ApplyTrailingStop(ticket);
      }
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
   double breakevenTrigger = slDistance * InpBreakeven_RR;
   
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
         Print("🔒 Breakeven activado en ", InpBreakeven_RR, "R");
      }
   }
}

//+------------------------------------------------------------------+
//| Cierre parcial escalonado                                         |
//+------------------------------------------------------------------+
void CheckPartialClose(ulong ticket, double targetRR, double percentClose, int tpLevel)
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
   double targetDistance = slDistance * targetRR;
   
   bool shouldClose = false;
   
   if(posType == POSITION_TYPE_BUY) {
      if(currentPrice >= posOpenPrice + targetDistance)
         shouldClose = true;
   }
   else {
      if(currentPrice <= posOpenPrice - targetDistance)
         shouldClose = true;
   }
   
   if(shouldClose) {
      // Calcular volumen a cerrar
      double closeVolume = NormalizeDouble(originalLotSize * percentClose / 100.0, 2);
      
      // Asegurar que no cerramos todo
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(posLot - closeVolume < minLot) {
         closeVolume = posLot - minLot;
      }
      
      if(closeVolume >= minLot) {
         if(trade.PositionClosePartial(ticket, closeVolume)) {
            if(tpLevel == 1) tp1Closed = 1;
            if(tpLevel == 2) tp2Closed = 1;
            
            Print("✅ TP", tpLevel, " alcanzado: ", percentClose, "% cerrado en ", targetRR, "R");
            Print("   Quedan ", (posLot - closeVolume), " lotes");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing stop para posición restante                              |
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
   
   // Activar trailing solo después de 1.8R
   if(currentProfit < InpTrailingStart_RR) return;
   
   double trailingDistance = InpTrailingStep_Pips * _Point * 10;
   double newSL = 0;
   
   if(posType == POSITION_TYPE_BUY) {
      newSL = currentPrice - trailingDistance;
      if(newSL > posSL) {
         newSL = NormalizeDouble(newSL, _Digits);
         if(trade.PositionModify(ticket, newSL, posTP)) {
            Print("📈 Trailing: SL movido a ", newSL, " (", DoubleToString(currentProfit, 2), "R)");
         }
      }
   }
   else {
      newSL = currentPrice + trailingDistance;
      if(newSL < posSL) {
         newSL = NormalizeDouble(newSL, _Digits);
         if(trade.PositionModify(ticket, newSL, posTP)) {
            Print("📉 Trailing: SL movido a ", newSL, " (", DoubleToString(currentProfit, 2), "R)");
         }
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
      Print("📅 Nuevo día - Balance: $", DoubleToString(dailyStartBalance, 2));
   }
   
   // Reset semanal (lunes)
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartBalance = currentBalance;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
      Print("📅 Nueva semana - Balance: $", DoubleToString(weeklyStartBalance, 2));
   }
   
   // Calcular DD
   double currentDailyDD = 0;
   double currentWeeklyDD = 0;
   
   if(dailyStartBalance > 0)
      currentDailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   if(weeklyStartBalance > 0)
      currentWeeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   // Verificar límites
   if(currentDailyDD >= InpMaxDailyDD && !dailyLimitReached) {
      dailyLimitReached = true;
      Print("⛔ DD DIARIO ALCANZADO: ", DoubleToString(currentDailyDD, 2), "%");
   }
   
   if(currentWeeklyDD >= InpMaxWeeklyDD && !weeklyLimitReached) {
      weeklyLimitReached = true;
      Print("⛔ DD SEMANAL ALCANZADO: ", DoubleToString(currentWeeklyDD, 2), "%");
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
      pausedAfterLoss = false;
      consecutiveLosses = 0;
   }
}

//+------------------------------------------------------------------+
//| Callback de transacciones                                         |
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
                  consecutiveLosses++;
                  Print("📉 Pérdida #", consecutiveLosses, " | $", DoubleToString(profit, 2));
                  
                  if(InpPauseAfterLoss && consecutiveLosses >= InpMaxConsecutiveLosses) {
                     pausedAfterLoss = true;
                     Print("⏸ PAUSADO hasta mañana");
                  }
               }
               else if(profit > 0) {
                  consecutiveLosses = 0;
                  Print("📈 Ganancia: $", DoubleToString(profit, 2));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Actualizar comentario                                             |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   double currentDailyDD = 0;
   if(dailyStartBalance > 0)
      currentDailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   string status = "🟢 ACTIVO";
   if(dailyLimitReached) status = "🔴 DD DIARIO";
   else if(weeklyLimitReached) status = "🔴 DD SEMANAL";
   else if(pausedAfterLoss) status = "🟡 PAUSADO";
   else if(tradesToday >= InpMaxTradesPerDay) status = "🟡 LÍMITE";
   else if(!IsTradingSession()) status = "🟡 FUERA SESIÓN";
   
   string structureStr = "Analizando...";
   if(currentStructure == STRUCTURE_BULLISH) structureStr = "📈 ALCISTA (HH+HL)";
   else if(currentStructure == STRUCTURE_BEARISH) structureStr = "📉 BAJISTA (LH+LL)";
   
   string signalStr = "Esperando estructura";
   if(breakoutDetected && waitingForPullback) {
      signalStr = StringFormat("Pullback: %.2f - %.2f", fiboPullbackMin, fiboPullbackMax);
   }
   
   double atr = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] / (_Point * 10) : 0;
   double rsi = (ArraySize(rsiBuffer) > 0) ? rsiBuffer[0] : 0;
   
   string comment = StringFormat(
      "╔═══════════════════════════════════════════════╗\n" +
      "║   EA V15.0 PROP FIRM ELITE                    ║\n" +
      "║   PROFITABLE & SUSTAINABLE                    ║\n" +
      "╚═══════════════════════════════════════════════╝\n\n" +
      "Estado: %s\n" +
      "Trades: %d/%d | Pérdidas: %d\n" +
      "DD Diario: %.2f%% / %.1f%%\n\n" +
      "┌─ ESTRUCTURA DE MERCADO ────────────────┐\n" +
      "│ %s\n" +
      "│ Último High: %.2f\n" +
      "│ Último Low:  %.2f\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ FILTROS INSTITUCIONALES ──────────────┐\n" +
      "│ EMA20:  %.2f\n" +
      "│ EMA50:  %.2f\n" +
      "│ EMA200: %.2f (H1)\n" +
      "│ RSI:    %.1f\n" +
      "│ ATR:    %.1f pips\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ GESTIÓN ESCALONADA ───────────────────┐\n" +
      "│ TP1: %.0f%% @ %.1fR\n" +
      "│ TP2: %.0f%% @ %.1fR\n" +
      "│ Trailing: %.1fR+ (%.0f pips step)\n" +
      "└────────────────────────────────────────┘\n\n" +
      "%s\n\n" +
      "Posiciones: %d\n" +
      "Balance: $%.2f | Equity: $%.2f\n" +
      "═══════════════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay, consecutiveLosses,
      currentDailyDD, InpMaxDailyDD,
      structureStr,
      lastHigh.price,
      lastLow.price,
      ema20[0],
      ema50[0],
      ema200[0],
      rsi,
      atr,
      InpTP1_Percent, InpTP1_RR,
      InpTP2_Percent, InpTP2_RR,
      InpTrailingStart_RR, InpTrailingStep_Pips,
      signalStr,
      PositionsTotal(),
      currentBalance,
      equity
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+
