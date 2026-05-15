//+------------------------------------------------------------------+
//|                           XAUUSD_V12_1_BREAKOUT_PULLBACK.mq5     |
//|                                    Estrategia Breakout + Pullback |
//|                                              VERSIÓN CORREGIDA    |
//|                                                                    |
//| Timeframe: M15                                                     |
//| Filtro: EMA200 H1                                                  |
//| Lógica: Breakout de swing + pullback                               |
//| TP: 1.8 RR                                                         |
//| Riesgo: 0.5% por trade                                             |
//| Max trades: 2 diarios                                              |
//| DD Control: 4% diario, 8% semanal                                  |
//+------------------------------------------------------------------+
#property copyright "Breakout Pullback System - Fixed"
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
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;     // Timeframe EMA

input group "=== BREAKOUT SETTINGS ==="
input int InpSwingBars = 10;                    // Barras para detectar swing high/low
input double InpPullbackPercent = 40;           // % de retroceso para entrada (0-100)
input int InpMinBreakoutPips = 5;               // Mínimo pips de breakout válido
input int InpMinSLPips = 20;                    // SL mínimo en pips (XAUUSD)

input group "=== DRAWDOWN CONTROL ==="
input double InpMaxDailyDD = 4.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 8.0;              // DD máximo semanal (%)
input bool InpCloseOnDDLimit = true;            // Cerrar posiciones al alcanzar DD

input group "=== GESTIÓN AVANZADA ==="
input bool InpUseBreakeven = true;              // Activar breakeven
input double InpBreakevenRR = 0.8;              // RR para activar breakeven
input int InpBreakevenOffset = 20;              // Offset en points para BE

input group "=== FILTROS ADICIONALES ==="
input bool InpUseSpreadFilter = true;           // Activar filtro de spread
input int InpMaxSpreadPips = 30;                // Spread máximo permitido (pips)
input bool InpUseTradingHours = true;           // Filtro horario
input int InpStartHour = 7;                     // Hora inicio (GMT)
input int InpEndHour = 21;                      // Hora fin (GMT)

input group "=== NOTIFICACIONES ==="
input bool InpSendNotifications = false;        // Enviar notificaciones móviles
input bool InpEnableLogging = true;             // Guardar log en archivo

input group "=== SISTEMA ==="
input int InpMagicNumber = 120001;              // Magic Number

//--- Global Variables
CTrade trade;
int emaHandle;
double emaBuffer[];

// Estado de trading
struct TradingState {
   datetime lastBarTime;
   int tradesToday;
   datetime lastTradeDate;
   
   double dailyStartBalance;
   double weeklyStartBalance;
   datetime lastDayCheck;
   datetime lastWeekCheck;
   
   bool dailyLimitReached;
   bool weeklyLimitReached;
   
   // Estado de breakout
   bool breakoutDetected;
   bool isLongSetup;  // true = esperando LONG, false = esperando SHORT
   double breakoutLevel;
   double pullbackTarget;
   datetime breakoutTime;
};

TradingState state;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validar símbolo
   if(_Symbol != "XAUUSD" && _Symbol != "XAUUSDm" && _Symbol != "GOLD") {
      Print("⚠ ADVERTENCIA: EA diseñado para XAUUSD, ejecutando en ", _Symbol);
      Print("  Algunos parámetros pueden no ser óptimos");
   }
   
   // Configurar trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Crear indicador EMA200 en H1
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("❌ Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   
   // Inicializar estado
   ZeroMemory(state);
   state.dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   state.weeklyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   state.lastDayCheck = TimeCurrent();
   state.lastWeekCheck = TimeCurrent();
   state.lastTradeDate = TimeCurrent();
   
   // Log de inicio
   string initLog = StringFormat(
      "\n╔════════════════════════════════════════════════╗\n"
      "║  EA V12.1 BREAKOUT + PULLBACK INICIADO        ║\n"
      "╚════════════════════════════════════════════════╝\n"
      "Símbolo: %s | TF: M15\n"
      "Riesgo: %.2f%% | RR: 1:%.1f\n"
      "Max trades/día: %d\n"
      "DD Límites: %.1f%% diario / %.1f%% semanal\n"
      "Filtros: Spread=%s | Horario=%s\n"
      "════════════════════════════════════════════════",
      _Symbol, InpRiskPercent, InpRiskReward,
      InpMaxTradesPerDay,
      InpMaxDailyDD, InpMaxWeeklyDD,
      InpUseSpreadFilter ? "SI" : "NO",
      InpUseTradingHours ? "SI" : "NO"
   );
   
   Print(initLog);
   LogToFile(initLog);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
   
   string reasonText;
   switch(reason) {
      case REASON_PROGRAM: reasonText = "Cambio de programa"; break;
      case REASON_REMOVE: reasonText = "EA removido del gráfico"; break;
      case REASON_RECOMPILE: reasonText = "Recompilación"; break;
      case REASON_CHARTCHANGE: reasonText = "Cambio de período/símbolo"; break;
      case REASON_CHARTCLOSE: reasonText = "Gráfico cerrado"; break;
      case REASON_PARAMETERS: reasonText = "Cambio de parámetros"; break;
      case REASON_ACCOUNT: reasonText = "Cambio de cuenta"; break;
      default: reasonText = "Razón desconocida"; break;
   }
   
   string deinitLog = StringFormat("EA V12.1 detenido. Razón: %s (%d)", reasonText, reason);
   Print(deinitLog);
   LogToFile(deinitLog);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar nueva barra
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == state.lastBarTime)
      return;
   state.lastBarTime = currentBarTime;
   
   // Control de drawdown
   CheckDrawdownLimits();
   if(state.dailyLimitReached || state.weeklyLimitReached) {
      Comment("⚠ TRADING DETENIDO - Límite DD alcanzado");
      return;
   }
   
   // Reset contador diario
   ResetDailyTradeCount();
   
   // Verificar límite de trades
   if(state.tradesToday >= InpMaxTradesPerDay) {
      Comment(StringFormat("⏸ Límite diario alcanzado: %d/%d", 
              state.tradesToday, InpMaxTradesPerDay));
      return;
   }
   
   // Filtro de horario
   if(InpUseTradingHours && !IsTradingTime()) {
      Comment("⏰ Fuera de horario de trading");
      return;
   }
   
   // Filtro de spread
   if(InpUseSpreadFilter && !IsSpreadAcceptable()) {
      Comment(StringFormat("📊 Spread muy alto: %.1f pips", GetCurrentSpread()));
      return;
   }
   
   // Gestionar posiciones abiertas
   ManageOpenPositions();
   
   // Solo buscar nuevas señales si no hay posiciones
   if(PositionsTotal() > 0)
      return;
   
   // Actualizar EMA
   if(!UpdateEMA())
      return;
   
   // Lógica principal
   ProcessBreakoutPullback();
   
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Actualizar EMA                                                     |
//+------------------------------------------------------------------+
bool UpdateEMA()
{
   if(CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3) {
      Print("❌ Error copiando EMA buffer: ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Procesar lógica Breakout + Pullback                               |
//+------------------------------------------------------------------+
void ProcessBreakoutPullback()
{
   // Estado 1: Detectar breakout de swing
   if(!state.breakoutDetected) {
      DetectSwingBreakout();
   }
   
   // Estado 2: Esperar pullback y entrar
   if(state.breakoutDetected) {
      CheckPullbackEntry();
   }
}

//+------------------------------------------------------------------+
//| Detectar breakout de swing high/low                               |
//+------------------------------------------------------------------+
void DetectSwingBreakout()
{
   // Encontrar último swing high y low
   double swingHigh = FindSwingHigh(InpSwingBars);
   double swingLow = FindSwingLow(InpSwingBars);
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   double minBreakout = InpMinBreakoutPips * _Point * 10;
   
   // Breakout alcista
   if(high1 > swingHigh + minBreakout && close1 > swingHigh) {
      // Verificar filtro EMA (precio por encima)
      if(close1 > emaBuffer[0]) {
         state.breakoutDetected = true;
         state.isLongSetup = true;
         state.breakoutLevel = swingHigh;
         state.breakoutTime = iTime(_Symbol, PERIOD_M15, 1);
         
         // Calcular nivel de pullback (retroceso del X%)
         double breakoutRange = high1 - swingHigh;
         state.pullbackTarget = swingHigh + (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         string msg = StringFormat("🔼 BREAKOUT ALCISTA detectado en %.2f | Pullback target: %.2f", 
                                   swingHigh, state.pullbackTarget);
         Print(msg);
         LogToFile(msg);
         
         if(InpSendNotifications)
            SendNotification(msg);
      }
   }
   
   // Breakout bajista
   if(low1 < swingLow - minBreakout && close1 < swingLow) {
      // Verificar filtro EMA (precio por debajo)
      if(close1 < emaBuffer[0]) {
         state.breakoutDetected = true;
         state.isLongSetup = false;
         state.breakoutLevel = swingLow;
         state.breakoutTime = iTime(_Symbol, PERIOD_M15, 1);
         
         // Calcular nivel de pullback (corrección: usar MathAbs)
         double breakoutRange = MathAbs(swingLow - low1);
         state.pullbackTarget = swingLow + (breakoutRange * (InpPullbackPercent/100.0));
         
         string msg = StringFormat("🔽 BREAKOUT BAJISTA detectado en %.2f | Pullback target: %.2f", 
                                   swingLow, state.pullbackTarget);
         Print(msg);
         LogToFile(msg);
         
         if(InpSendNotifications)
            SendNotification(msg);
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
   int barsSinceBreakout = (int)((iTime(_Symbol, PERIOD_M15, 0) - state.breakoutTime) / PeriodSeconds(PERIOD_M15));
   if(barsSinceBreakout > 20) {
      ResetBreakoutState();
      LogToFile("⏱ Timeout: pullback no ocurrió en 20 velas");
      return;
   }
   
   // Entrada LONG (después de breakout alcista)
   if(state.isLongSetup) {
      // Precio retrocedió al nivel de pullback y rebota
      if(low1 <= state.pullbackTarget && close1 > state.pullbackTarget) {
         OpenTrade(ORDER_TYPE_BUY);
         ResetBreakoutState();
      }
   }
   
   // Entrada SHORT (después de breakout bajista)
   if(!state.isLongSetup) {
      // Precio retrocedió al nivel de pullback y rebota
      if(high1 >= state.pullbackTarget && close1 < state.pullbackTarget) {
         OpenTrade(ORDER_TYPE_SELL);
         ResetBreakoutState();
      }
   }
}

//+------------------------------------------------------------------+
//| Encontrar swing high                                              |
//+------------------------------------------------------------------+
double FindSwingHigh(int bars)
{
   double highest = iHigh(_Symbol, PERIOD_M15, 2);
   for(int i = 3; i <= bars + 2; i++) {
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
   double lowest = iLow(_Symbol, PERIOD_M15, 2);
   for(int i = 3; i <= bars + 2; i++) {
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
   state.breakoutDetected = false;
   state.isLongSetup = false;
   state.breakoutLevel = 0;
   state.pullbackTarget = 0;
   state.breakoutTime = 0;
}

//+------------------------------------------------------------------+
//| Abrir trade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Calcular SL basado en la distancia al breakout level
   double slDistance;
   double entryPrice;
   double sl, tp;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      slDistance = MathAbs(entryPrice - state.breakoutLevel);
      
      // Aplicar SL mínimo (corregido para XAUUSD)
      double minSL = InpMinSLPips * point * 10;
      if(slDistance < minSL)
         slDistance = minSL;
      
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + (slDistance * InpRiskReward), _Digits);
   }
   else {
      entryPrice = bid;
      slDistance = MathAbs(state.breakoutLevel - entryPrice);
      
      double minSL = InpMinSLPips * point * 10;
      if(slDistance < minSL)
         slDistance = minSL;
      
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - (slDistance * InpRiskReward), _Digits);
   }
   
   // Calcular lote basado en riesgo (CORREGIDO)
   double slPips = slDistance / point;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("❌ Lote calculado muy pequeño: ", lotSize);
      LogToFile(StringFormat("Trade rechazado: lote muy pequeño (%.2f)", lotSize));
      return;
   }
   
   // Ejecutar orden
   string comment = StringFormat("BP_V12.1_RR%.1f", InpRiskReward);
   bool success = false;
   
   if(orderType == ORDER_TYPE_BUY) {
      success = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   else {
      success = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   
   // Log del resultado
   if(success) {
      string msg = StringFormat(
         "✅ %s abierto | Ticket: %I64u\n"
         "   Entry: %.2f | SL: %.2f (%.1f pips) | TP: %.2f\n"
         "   Lote: %.2f | Riesgo: $%.2f",
         (orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT"),
         trade.ResultOrder(),
         entryPrice, sl, slPips, tp,
         lotSize, riskAmount
      );
      
      Print(msg);
      LogToFile(msg);
      
      if(InpSendNotifications)
         SendNotification(StringFormat("Trade abierto: %s %.2f lotes", 
                         (orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT"), lotSize));
      
      state.tradesToday++;
      state.lastTradeDate = TimeCurrent();
   }
   else {
      string errorMsg = StringFormat("❌ Error abriendo %s: %s (código: %d)", 
                                     (orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT"),
                                     trade.ResultRetcodeDescription(),
                                     trade.ResultRetcode());
      Print(errorMsg);
      LogToFile(errorMsg);
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote (CORREGIDO)                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slPips)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Convertir SL en points a ticks (CORRECCIÓN CRÍTICA)
   double slInTicks = slPips * (point / tickSize);
   
   // Calcular lote
   double lotSize = riskAmount / (slInTicks * tickValue);
   
   // Ajustar a los límites del símbolo
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
//| Mover a breakeven (CORREGIDO)                                     |
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
   double beThreshold = InpBreakevenOffset * _Point;
   if(MathAbs(posSL - posOpenPrice) <= beThreshold * 1.5)
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
      // Mover SL a entry + offset (CORREGIDO)
      double offset = InpBreakevenOffset * _Point;
      double newSL = NormalizeDouble(posOpenPrice + (offset * ((posType == POSITION_TYPE_BUY) ? 1 : -1)), _Digits);
      
      if(trade.PositionModify(ticket, newSL, posTP)) {
         string msg = StringFormat("🔒 Breakeven activado | Ticket: %I64u | Nuevo SL: %.2f", ticket, newSL);
         Print(msg);
         LogToFile(msg);
         
         if(InpSendNotifications)
            SendNotification("Breakeven activado");
      }
   }
}

//+------------------------------------------------------------------+
//| Control de drawdown (MEJORADO)                                    |
//+------------------------------------------------------------------+
void CheckDrawdownLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Reset diario
   MqlDateTime lastDayStruct;
   TimeToStruct(state.lastDayCheck, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      state.dailyStartBalance = currentBalance;
      state.lastDayCheck = TimeCurrent();
      state.dailyLimitReached = false;
      
      string msg = StringFormat("📅 Nuevo día | Balance inicial: $%.2f", state.dailyStartBalance);
      Print(msg);
      LogToFile(msg);
   }
   
   // Reset semanal (corregido para lunes)
   MqlDateTime lastWeekStruct;
   TimeToStruct(state.lastWeekCheck, lastWeekStruct);
   
   // Resetear si es lunes Y el último check no fue lunes
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      state.weeklyStartBalance = currentBalance;
      state.lastWeekCheck = TimeCurrent();
      state.weeklyLimitReached = false;
      
      string msg = StringFormat("📆 Nueva semana | Balance inicial: $%.2f", state.weeklyStartBalance);
      Print(msg);
      LogToFile(msg);
   }
   
   // Calcular DD
   double dailyDD = ((state.dailyStartBalance - currentBalance) / state.dailyStartBalance) * 100.0;
   double weeklyDD = ((state.weeklyStartBalance - currentBalance) / state.weeklyStartBalance) * 100.0;
   
   // Verificar límites
   if(dailyDD >= InpMaxDailyDD && !state.dailyLimitReached) {
      state.dailyLimitReached = true;
      
      string msg = StringFormat("⚠️ LÍMITE DD DIARIO ALCANZADO: %.2f%%", dailyDD);
      Print(msg);
      LogToFile(msg);
      
      if(InpSendNotifications)
         SendNotification(msg);
      
      // Cerrar posiciones si está habilitado
      if(InpCloseOnDDLimit)
         CloseAllPositions("DD diario alcanzado");
   }
   
   if(weeklyDD >= InpMaxWeeklyDD && !state.weeklyLimitReached) {
      state.weeklyLimitReached = true;
      
      string msg = StringFormat("⚠️ LÍMITE DD SEMANAL ALCANZADO: %.2f%%", weeklyDD);
      Print(msg);
      LogToFile(msg);
      
      if(InpSendNotifications)
         SendNotification(msg);
      
      // Cerrar posiciones si está habilitado
      if(InpCloseOnDDLimit)
         CloseAllPositions("DD semanal alcanzado");
   }
}

//+------------------------------------------------------------------+
//| Cerrar todas las posiciones                                       |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   int closed = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      if(trade.PositionClose(ticket)) {
         closed++;
         Print("✓ Posición cerrada: ", ticket, " | Razón: ", reason);
      }
   }
   
   if(closed > 0) {
      string msg = StringFormat("Cerradas %d posiciones: %s", closed, reason);
      LogToFile(msg);
   }
}

//+------------------------------------------------------------------+
//| Reset contador de trades diarios                                  |
//+------------------------------------------------------------------+
void ResetDailyTradeCount()
{
   MqlDateTime currentTime, lastTradeTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(state.lastTradeDate, lastTradeTime);
   
   if(currentTime.day != lastTradeTime.day) {
      state.tradesToday = 0;
   }
}

//+------------------------------------------------------------------+
//| Verificar si está en horario de trading                           |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   
   return (tm.hour >= InpStartHour && tm.hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Verificar si el spread es aceptable                               |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   double spread = GetCurrentSpread();
   return (spread <= InpMaxSpreadPips);
}

//+------------------------------------------------------------------+
//| Obtener spread actual en pips                                     |
//+------------------------------------------------------------------+
double GetCurrentSpread()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   return (ask - bid) / (point * 10);
}

//+------------------------------------------------------------------+
//| Guardar en archivo de log                                         |
//+------------------------------------------------------------------+
void LogToFile(string message)
{
   if(!InpEnableLogging) return;
   
   string filename = StringFormat("EA_V12.1_%s_%d.log", _Symbol, InpMagicNumber);
   int handle = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE);
   
   if(handle != INVALID_HANDLE) {
      FileSeek(handle, 0, SEEK_END);
      string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
      FileWriteString(handle, timestamp + " | " + message + "\n");
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Actualizar comentario en gráfico                                  |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyDD = 0;
   double weeklyDD = 0;
   
   if(state.dailyStartBalance > 0)
      dailyDD = ((state.dailyStartBalance - currentBalance) / state.dailyStartBalance) * 100.0;
   
   if(state.weeklyStartBalance > 0)
      weeklyDD = ((state.weeklyStartBalance - currentBalance) / state.weeklyStartBalance) * 100.0;
   
   string status = "✅ ACTIVO";
   if(state.dailyLimitReached) status = "🛑 DD DIARIO ALCANZADO";
   else if(state.weeklyLimitReached) status = "🛑 DD SEMANAL ALCANZADO";
   else if(state.tradesToday >= InpMaxTradesPerDay) status = "⏸ LÍMITE TRADES DIARIO";
   else if(InpUseTradingHours && !IsTradingTime()) status = "⏰ FUERA DE HORARIO";
   else if(InpUseSpreadFilter && !IsSpreadAcceptable()) status = "📊 SPREAD ALTO";
   
   string breakoutStatus = "🔍 Buscando breakout...";
   if(state.breakoutDetected) {
      breakoutStatus = StringFormat("⏳ Esperando pullback a %.2f (%s)", 
                                   state.pullbackTarget,
                                   state.isLongSetup ? "LONG" : "SHORT");
   }
   
   double spread = GetCurrentSpread();
   
   string comment = StringFormat(
      "╔═══════════════════════════════════════════════╗\n"
      "║       EA V12.1 BREAKOUT + PULLBACK           ║\n"
      "╚═══════════════════════════════════════════════╝\n"
      "Estado: %s\n"
      "Trades hoy: %d/%d\n"
      "DD Diario: %.2f%% / %.1f%% 📉\n"
      "DD Semanal: %.2f%% / %.1f%% 📊\n"
      "───────────────────────────────────────────────\n"
      "EMA200 H1: %.2f\n"
      "Precio: %.2f | Spread: %.1f pips\n"
      "%s\n"
      "───────────────────────────────────────────────\n"
      "Posiciones: %d | Balance: $%.2f\n"
      "╚═══════════════════════════════════════════════╝",
      status,
      state.tradesToday, InpMaxTradesPerDay,
      dailyDD, InpMaxDailyDD,
      weeklyDD, InpMaxWeeklyDD,
      emaBuffer[0],
      SymbolInfoDouble(_Symbol, SYMBOL_BID), spread,
      breakoutStatus,
      PositionsTotal(),
      currentBalance
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+