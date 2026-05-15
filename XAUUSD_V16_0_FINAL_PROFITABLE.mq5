//+------------------------------------------------------------------+
//|                      XAUUSD_V16_0_FINAL_PROFITABLE.mq5           |
//|                    SISTEMA FINAL RENTABLE PARA FONDEO            |
//|                                                                    |
//| ENFOQUE: Simple, Rentable, Sostenible                             |
//| FILOSOFÍA: Lo que funciona en real, no en teoría                  |
//|                                                                    |
//| ESTRATEGIA CORE:                                                  |
//| • Breakout de rango consolidado (mínimo 8 velas)                  |
//| • Confirmación con vela fuerte (body > 50%)                       |
//| • Entrada inmediata (NO pullback - reduce oportunidades)          |
//| • SL: Opuesto del rango + 10 pips                                 |
//| • TP: 1.5R fijo (balance profit/frecuencia)                       |
//| • Breakeven: 0.8R                                                 |
//| • Filtro EMA200 H1 (tendencia mayor)                              |
//| • Sesión Londres/NY (08:00-17:00)                                 |
//| • Max 2 trades/día                                                |
//| • DD: 3% diario, 6% semanal                                       |
//| • Riesgo: 1% por trade                                            |
//+------------------------------------------------------------------+
#property copyright "Final Profitable System V16.0"
#property version   "16.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== RIESGO Y DD ==="
input double InpRiskPercent = 1.0;              // Riesgo por trade (%)
input double InpMaxDailyDD = 3.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 6.0;              // DD máximo semanal (%)

input group "=== SESIÓN ==="
input int InpSessionStart = 8;                  // Inicio sesión (08:00 GMT)
input int InpSessionEnd = 17;                   // Fin sesión (17:00 GMT)
input int InpGMTOffset = 0;                     // Offset GMT

input group "=== BREAKOUT RANGO ==="
input int InpMinRangeBars = 8;                  // Mínimo velas en rango
input int InpMaxRangeBars = 30;                 // Máximo velas en rango
input double InpMinRangePips = 30;              // Rango mínimo (pips)
input double InpMaxRangePips = 150;             // Rango máximo (pips)
input double InpBodyPercent = 0.50;             // Body mínimo breakout (50%)

input group "=== GESTIÓN ==="
input double InpRiskReward = 1.5;               // Risk:Reward
input double InpBreakevenRR = 0.8;              // Breakeven (0.8R)
input double InpSLBufferPips = 10;              // Buffer SL (pips)
input int InpMaxTradesPerDay = 2;               // Max trades/día

input group "=== FILTROS ==="
input int InpEMA200Period = 200;                // EMA200 período
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;     // EMA timeframe
input double InpMinATRPips = 20;                // ATR mínimo (pips)

input group "=== AVANZADO ==="
input int InpMagicNumber = 160001;              // Magic Number

//--- Global Variables
CTrade trade;
int emaHandle, atrHandle;
double emaBuffer[], atrBuffer[];

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

// Rango
struct RangeInfo {
   double high;
   double low;
   int bars;
   datetime startTime;
   bool valid;
};

RangeInfo currentRange;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_M15, 14);
   
   if(emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) {
      Print("❌ Error creando indicadores");
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   currentRange.valid = false;
   
   Print("═══════════════════════════════════════════════════════");
   Print("  EA V16.0 FINAL PROFITABLE");
   Print("  SIMPLE • RENTABLE • SOSTENIBLE");
   Print("═══════════════════════════════════════════════════════");
   Print("Estrategia: Breakout de rango consolidado");
   Print("Riesgo: ", InpRiskPercent, "% | RR: 1:", InpRiskReward);
   Print("DD Control: ", InpMaxDailyDD, "% / ", InpMaxWeeklyDD, "%");
   Print("Max trades/día: ", InpMaxTradesPerDay);
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
   
   Print("EA V16.0 detenido");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   CheckDrawdownLimits();
   if(dailyLimitReached || weeklyLimitReached) {
      Comment("⛔ DD LÍMITE");
      return;
   }
   
   ResetDailyCounters();
   
   if(tradesToday >= InpMaxTradesPerDay) {
      Comment("⏸ Límite diario");
      return;
   }
   
   if(!IsTradingSession()) {
      Comment("⏰ Fuera de sesión");
      return;
   }
   
   ManageOpenPositions();
   
   if(PositionsTotal() > 0)
      return;
   
   if(!UpdateIndicators())
      return;
   
   if(!CheckBasicFilters())
      return;
   
   // Lógica principal: Detectar rango y breakout
   ProcessRangeBreakout();
   
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Actualizar indicadores                                            |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(emaHandle, 0, 0, 2, emaBuffer) < 2) return false;
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) < 1) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Verificar sesión                                                  |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour + InpGMTOffset;
   if(currentHour < 0) currentHour += 24;
   if(currentHour >= 24) currentHour -= 24;
   
   return (currentHour >= InpSessionStart && currentHour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| Verificar filtros básicos                                         |
//+------------------------------------------------------------------+
bool CheckBasicFilters()
{
   double atr = atrBuffer[0];
   double atrPips = atr / (_Point * 10);
   
   if(atrPips < InpMinATRPips) {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Procesar detección de rango y breakout                            |
//+------------------------------------------------------------------+
void ProcessRangeBreakout()
{
   // Paso 1: Identificar rango consolidado
   if(!currentRange.valid) {
      IdentifyRange();
   }
   
   // Paso 2: Detectar breakout del rango
   if(currentRange.valid) {
      DetectBreakout();
   }
}

//+------------------------------------------------------------------+
//| Identificar rango consolidado                                     |
//+------------------------------------------------------------------+
void IdentifyRange()
{
   // Buscar últimas X velas para rango
   int lookback = InpMaxRangeBars;
   
   double highest = iHigh(_Symbol, PERIOD_M15, 1);
   double lowest = iLow(_Symbol, PERIOD_M15, 1);
   
   // Encontrar high/low de las últimas velas
   for(int i = 2; i <= lookback; i++) {
      double high = iHigh(_Symbol, PERIOD_M15, i);
      double low = iLow(_Symbol, PERIOD_M15, i);
      
      if(high > highest) highest = high;
      if(low < lowest) lowest = low;
   }
   
   double rangePips = (highest - lowest) / (_Point * 10);
   
   // Verificar que el rango es válido
   if(rangePips >= InpMinRangePips && rangePips <= InpMaxRangePips) {
      // Contar cuántas velas están dentro del rango
      int barsInRange = 0;
      
      for(int i = 1; i <= lookback; i++) {
         double high = iHigh(_Symbol, PERIOD_M15, i);
         double low = iLow(_Symbol, PERIOD_M15, i);
         
         // Si la vela está completamente dentro del rango
         if(high <= highest && low >= lowest) {
            barsInRange++;
         }
         else {
            break; // Rango roto
         }
      }
      
      // Validar que hay suficientes velas en rango
      if(barsInRange >= InpMinRangeBars) {
         currentRange.high = highest;
         currentRange.low = lowest;
         currentRange.bars = barsInRange;
         currentRange.startTime = iTime(_Symbol, PERIOD_M15, barsInRange);
         currentRange.valid = true;
         
         Print("📊 RANGO detectado: ", lowest, " - ", highest, " (", rangePips, " pips, ", barsInRange, " velas)");
      }
   }
}

//+------------------------------------------------------------------+
//| Detectar breakout del rango                                       |
//+------------------------------------------------------------------+
void DetectBreakout()
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double open1 = iOpen(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   double body = MathAbs(close1 - open1);
   double range = high1 - low1;
   
   if(range == 0) return;
   
   double bodyPercent = body / range;
   
   // Verificar que la vela tiene cuerpo fuerte
   if(bodyPercent < InpBodyPercent) return;
   
   // Breakout ALCISTA
   if(close1 > currentRange.high && high1 > currentRange.high) {
      // Verificar filtro EMA
      if(close1 > emaBuffer[0]) {
         Print("✅ BREAKOUT ALCISTA del rango");
         OpenTrade(ORDER_TYPE_BUY);
         currentRange.valid = false;
      }
   }
   
   // Breakout BAJISTA
   if(close1 < currentRange.low && low1 < currentRange.low) {
      // Verificar filtro EMA
      if(close1 < emaBuffer[0]) {
         Print("✅ BREAKOUT BAJISTA del rango");
         OpenTrade(ORDER_TYPE_SELL);
         currentRange.valid = false;
      }
   }
}


//+------------------------------------------------------------------+
//| Abrir trade                                                        |
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
      // SL: Bajo del rango - buffer
      sl = NormalizeDouble(currentRange.low - slBuffer, _Digits);
      // TP: 1.5R
      double slDistance = entryPrice - sl;
      tp = NormalizeDouble(entryPrice + (slDistance * InpRiskReward), _Digits);
   }
   else {
      entryPrice = bid;
      // SL: Alto del rango + buffer
      sl = NormalizeDouble(currentRange.high + slBuffer, _Digits);
      // TP: 1.5R
      double slDistance = sl - entryPrice;
      tp = NormalizeDouble(entryPrice - (slDistance * InpRiskReward), _Digits);
   }
   
   // Calcular lote
   double slDistance = MathAbs(entryPrice - sl);
   double slPips = slDistance / point;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("❌ Lote muy pequeño");
      return;
   }
   
   string comment = StringFormat("V16_RB_%.1fR", InpRiskReward);
   
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
      Print("   TP: ", tp, " (", InpRiskReward, "R)");
      Print("   Lote: ", lotSize);
      Print("   Rango: ", currentRange.low, " - ", currentRange.high);
      
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
//| Gestionar posiciones abiertas                                     |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
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
         Print("🔒 Breakeven en ", InpBreakevenRR, "R");
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
   }
   
   // Reset semanal
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartBalance = currentBalance;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
   }
   
   // Calcular DD
   double currentDailyDD = 0;
   double currentWeeklyDD = 0;
   
   if(dailyStartBalance > 0)
      currentDailyDD = ((dailyStartBalance - currentBalance) / dailyStartBalance) * 100.0;
   
   if(weeklyStartBalance > 0)
      currentWeeklyDD = ((weeklyStartBalance - currentBalance) / weeklyStartBalance) * 100.0;
   
   if(currentDailyDD >= InpMaxDailyDD && !dailyLimitReached) {
      dailyLimitReached = true;
      Print("⛔ DD DIARIO: ", DoubleToString(currentDailyDD, 2), "%");
   }
   
   if(currentWeeklyDD >= InpMaxWeeklyDD && !weeklyLimitReached) {
      weeklyLimitReached = true;
      Print("⛔ DD SEMANAL: ", DoubleToString(currentWeeklyDD, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Reset contadores                                                  |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   MqlDateTime currentTime, lastTradeTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastTradeDate, lastTradeTime);
   
   if(currentTime.day != lastTradeTime.day) {
      tradesToday = 0;
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
   else if(tradesToday >= InpMaxTradesPerDay) status = "🟡 LÍMITE";
   else if(!IsTradingSession()) status = "🟡 FUERA SESIÓN";
   
   string rangeStatus = "Buscando rango...";
   if(currentRange.valid) {
      double rangePips = (currentRange.high - currentRange.low) / (_Point * 10);
      rangeStatus = StringFormat("RANGO: %.2f - %.2f (%.0f pips, %d velas)", 
                                 currentRange.low, currentRange.high, rangePips, currentRange.bars);
   }
   
   double atr = (ArraySize(atrBuffer) > 0) ? atrBuffer[0] / (_Point * 10) : 0;
   
   string comment = StringFormat(
      "╔═══════════════════════════════════════════════╗\n" +
      "║   EA V16.0 FINAL PROFITABLE                   ║\n" +
      "║   BREAKOUT DE RANGO CONSOLIDADO               ║\n" +
      "╚═══════════════════════════════════════════════╝\n\n" +
      "Estado: %s\n" +
      "Trades: %d/%d\n" +
      "DD Diario: %.2f%% / %.1f%%\n\n" +
      "┌─ ESTRATEGIA ───────────────────────────┐\n" +
      "│ Riesgo: %.1f%% | RR: 1:%.1f\n" +
      "│ Breakeven: %.1fR\n" +
      "│ Rango: %d-%d velas\n" +
      "│ Body mínimo: %.0f%%\n" +
      "└────────────────────────────────────────┘\n\n" +
      "┌─ MERCADO ──────────────────────────────┐\n" +
      "│ EMA200: %.2f\n" +
      "│ ATR: %.1f pips\n" +
      "│ Precio: %.2f\n" +
      "└────────────────────────────────────────┘\n\n" +
      "%s\n\n" +
      "Posiciones: %d\n" +
      "Balance: $%.2f | Equity: $%.2f\n" +
      "═══════════════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay,
      currentDailyDD, InpMaxDailyDD,
      InpRiskPercent, InpRiskReward,
      InpBreakevenRR,
      InpMinRangeBars, InpMaxRangeBars,
      InpBodyPercent * 100,
      emaBuffer[0],
      atr,
      SymbolInfoDouble(_Symbol, SYMBOL_BID),
      rangeStatus,
      PositionsTotal(),
      currentBalance,
      equity
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+
