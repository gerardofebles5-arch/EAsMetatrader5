//+------------------------------------------------------------------+
//|                                           XAUUSD_BREAKOUT_v12.1  |
//|                                    Estrategia Breakout + Pullback |
//|                                              Versión Mejorada     |
//+------------------------------------------------------------------+
#property copyright "Breakout Pullback System"
#property version   "12.1"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== CONFIGURACIÓN BÁSICA ==="
input double InpRiskPercent = 0.3;              // Riesgo por trade (%) - Reducido para prop firms
input double InpRiskReward = 2.0;                // Risk:Reward ratio
input int InpMaxTradesPerDay = 2;                // Máximo trades por día

input group "=== FILTRO TENDENCIA ==="
input int InpEMA200Period = 200;                 // Período EMA200 (H1)
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;      // Timeframe EMA

input group "=== SWING DETECTION ==="
input int InpSwingBars = 15;                     // Barras máximas para buscar swing
input int InpSwingLeftBars = 2;                  // Barras a la izquierda para confirmar swing
input int InpSwingRightBars = 2;                  // Barras a la derecha para confirmar swing
input int InpMinBreakoutPips = 8;                 // Mínimo pips de breakout válido
input double InpPullbackPercent = 50.0;           // % de retroceso para entrada (0-100)

input group "=== DRAWDOWN CONTROL ==="
input double InpMaxDailyDD = 4.0;                 // DD máximo diario (%) sobre equity
input double InpMaxWeeklyDD = 8.0;                 // DD máximo semanal (%) sobre equity

input group "=== GESTIÓN AVANZADA ==="
input bool InpUseBreakeven = true;                 // Activar breakeven
input double InpBreakevenRR = 0.8;                 // RR para activar breakeven
input int InpBreakevenBufferPips = 20;             // Pips de buffer para breakeven
input int InpMagicNumber = 120001;                 // Magic Number

input group "=== FILTRO HORARIO ==="
input bool InpUseTimeFilter = true;                 // Usar filtro horario
input int InpStartHour = 8;                         // Hora inicio (hora servidor, 0-23)
input int InpEndHour = 17;                          // Hora fin

//--- Global Variables
CTrade trade;
int emaHandle;
double emaBuffer[];

datetime lastBarTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;

double dailyStartEquity = 0;
double weeklyStartEquity = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;

bool dailyLimitReached = false;
bool weeklyLimitReached = false;

struct SwingPoint {
   double price;
   datetime time;
   bool isHigh;  // true = swing high, false = swing low
};

SwingPoint lastSwing;
bool breakoutDetected = false;
bool waitingForPullback = false;
double breakoutLevel = 0;
double pullbackTarget = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_RETURN);  // Más compatible
   
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   
   // Inicializar tracking de drawdown
   dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   Print("=== EA V12.1 MEJORADO INICIADO ===");
   Print("Símbolo: ", _Symbol);
   Print("Riesgo: ", InpRiskPercent, "%");
   Print("RR: 1:", InpRiskReward);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
   Print("EA V12.1 detenido. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Filtro horario
   if(InpUseTimeFilter && !IsTradingTime())
      return;
   
   // Verificar nueva barra en M15
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
   
   // Actualizar EMA
   if(!UpdateEMA())
      return;
   
   // Lógica principal
   ProcessBreakoutPullback();
   
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Actualizar EMA                                                   |
//+------------------------------------------------------------------+
bool UpdateEMA()
{
   if(CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3) {
      Print("Error copiando EMA buffer: ", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Procesar lógica Breakout + Pullback                              |
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
//| Detectar breakout de swing high/low                              |
//+------------------------------------------------------------------+
void DetectSwingBreakout()
{
   double swingHigh, swingLow;
   datetime dummy;
   bool foundHigh = FindSwingHigh(swingHigh, dummy);
   bool foundLow = FindSwingLow(swingLow, dummy);
   
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   
   double minBreakout = InpMinBreakoutPips * _Point;  // Sin multiplicar por 10
   
   // Breakout alcista
   if(foundHigh && high1 > swingHigh + minBreakout && close1 > swingHigh) {
      if(close1 > emaBuffer[0]) {  // Filtro EMA
         breakoutDetected = true;
         waitingForPullback = true;
         breakoutLevel = swingHigh;
         
         double breakoutRange = high1 - swingHigh;
         pullbackTarget = swingHigh + (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         lastSwing.price = swingHigh;
         lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
         lastSwing.isHigh = false;  // breakout alcista, esperamos pullback hacia abajo
         
         Print("BREAKOUT ALCISTA detectado en ", swingHigh, " | Pullback target: ", pullbackTarget);
      }
   }
   
   // Breakout bajista
   if(foundLow && low1 < swingLow - minBreakout && close1 < swingLow) {
      if(close1 < emaBuffer[0]) {
         breakoutDetected = true;
         waitingForPullback = true;
         breakoutLevel = swingLow;
         
         double breakoutRange = swingLow - low1;
         pullbackTarget = swingLow - (breakoutRange * (1.0 - InpPullbackPercent/100.0));
         
         lastSwing.price = swingLow;
         lastSwing.time = iTime(_Symbol, PERIOD_M15, 1);
         lastSwing.isHigh = true;  // breakout bajista, esperamos pullback hacia arriba
         
         Print("BREAKOUT BAJISTA detectado en ", swingLow, " | Pullback target: ", pullbackTarget);
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar entrada en pullback                                    |
//+------------------------------------------------------------------+
void CheckPullbackEntry()
{
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   
   // Timeout
   if(iTime(_Symbol, PERIOD_M15, 1) - lastSwing.time > 20 * PeriodSeconds(PERIOD_M15)) {
      ResetBreakoutState();
      Print("Timeout: pullback no ocurrió en 20 velas");
      return;
   }
   
   // Entrada LONG (breakout alcista)
   if(!lastSwing.isHigh) {
      // Precio retrocedió al nivel de pullback y cierra por encima
      if(low1 <= pullbackTarget && close1 > pullbackTarget) {
         if(close1 > emaBuffer[0]) {
            OpenTrade(ORDER_TYPE_BUY, pullbackTarget);
            ResetBreakoutState();
         }
      }
   }
   
   // Entrada SHORT (breakout bajista)
   if(lastSwing.isHigh) {
      if(high1 >= pullbackTarget && close1 < pullbackTarget) {
         if(close1 < emaBuffer[0]) {
            OpenTrade(ORDER_TYPE_SELL, pullbackTarget);
            ResetBreakoutState();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Encontrar swing high verdadero                                   |
//+------------------------------------------------------------------+
bool FindSwingHigh(double &highPrice, datetime &highTime)
{
   int startBar = 2;  // Empezar desde la vela 2 (la vela 1 es la anterior)
   int maxBars = InpSwingBars + InpSwingLeftBars + InpSwingRightBars + 2;
   for(int i = startBar; i <= startBar + maxBars; i++)
   {
      double currentHigh = iHigh(_Symbol, PERIOD_M15, i);
      bool isHigh = true;
      
      // Verificar barras a la izquierda (más nuevas)
      for(int j = 1; j <= InpSwingLeftBars; j++)
      {
         if(i - j < 0) continue;
         if(currentHigh <= iHigh(_Symbol, PERIOD_M15, i - j))
         {
            isHigh = false;
            break;
         }
      }
      if(isHigh)
      {
         // Verificar barras a la derecha (más viejas)
         for(int j = 1; j <= InpSwingRightBars; j++)
         {
            if(i + j >= Bars(_Symbol, PERIOD_M15)) break;
            if(currentHigh <= iHigh(_Symbol, PERIOD_M15, i + j))
            {
               isHigh = false;
               break;
            }
         }
      }
      if(isHigh)
      {
         highPrice = currentHigh;
         highTime = iTime(_Symbol, PERIOD_M15, i);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Encontrar swing low verdadero                                    |
//+------------------------------------------------------------------+
bool FindSwingLow(double &lowPrice, datetime &lowTime)
{
   int startBar = 2;
   int maxBars = InpSwingBars + InpSwingLeftBars + InpSwingRightBars + 2;
   for(int i = startBar; i <= startBar + maxBars; i++)
   {
      double currentLow = iLow(_Symbol, PERIOD_M15, i);
      bool isLow = true;
      
      for(int j = 1; j <= InpSwingLeftBars; j++)
      {
         if(i - j < 0) continue;
         if(currentLow >= iLow(_Symbol, PERIOD_M15, i - j))
         {
            isLow = false;
            break;
         }
      }
      if(isLow)
      {
         for(int j = 1; j <= InpSwingRightBars; j++)
         {
            if(i + j >= Bars(_Symbol, PERIOD_M15)) break;
            if(currentLow >= iLow(_Symbol, PERIOD_M15, i + j))
            {
               isLow = false;
               break;
            }
         }
      }
      if(isLow)
      {
         lowPrice = currentLow;
         lowTime = iTime(_Symbol, PERIOD_M15, i);
         return true;
      }
   }
   return false;
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
//| Abrir trade                                                      |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType, double entryReference)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double entryPrice, sl, tp;
   double slDistance;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      slDistance = MathAbs(entryPrice - breakoutLevel);
      if(slDistance < 100 * point)  // Mínimo 100 pips
         slDistance = 100 * point;
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + slDistance * InpRiskReward, _Digits);
   } else {
      entryPrice = bid;
      slDistance = MathAbs(breakoutLevel - entryPrice);
      if(slDistance < 100 * point)
         slDistance = 100 * point;
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - slDistance * InpRiskReward, _Digits);
   }
   
   // Calcular lote correctamente
   double slPips = slDistance / point;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("Lote calculado demasiado pequeño: ", lotSize);
      return;
   }
   
   string comment = StringFormat("BP_V12_RR%.1f", InpRiskReward);
   
   if(orderType == ORDER_TYPE_BUY) {
      if(trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
         Print("✓ LONG abierto: Lote=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
         tradesToday++;
         lastTradeDate = TimeCurrent();
      } else {
         Print("✗ Error abriendo LONG: ", trade.ResultRetcodeDescription());
      }
   } else {
      if(trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
         Print("✓ SHORT abierto: Lote=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
         tradesToday++;
         lastTradeDate = TimeCurrent();
      } else {
         Print("✗ Error abriendo SHORT: ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote (corregido)                              |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slPips)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Valor de 1 pip en la divisa de la cuenta para 1 lote
   double pipValue = tickValue * (point / tickSize);
   
   double lotSize = riskAmount / (slPips * pipValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Gestionar posiciones abiertas                                    |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      if(InpUseBreakeven) {
         MoveToBreakeven(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Mover a breakeven (con buffer configurable)                      |
//+------------------------------------------------------------------+
void MoveToBreakeven(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   
   double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
   
   double slDistance = MathAbs(posOpen - posSL);
   double trigger = slDistance * InpBreakevenRR;
   
   bool reached = false;
   if(posType == POSITION_TYPE_BUY && currentPrice >= posOpen + trigger) reached = true;
   if(posType == POSITION_TYPE_SELL && currentPrice <= posOpen - trigger) reached = true;
   
   if(reached) {
      // Si ya está en breakeven (cerca), no hacer nada
      if(MathAbs(posSL - posOpen) < InpBreakevenBufferPips * _Point * 2) return;
      
      double newSL = posOpen + (posType == POSITION_TYPE_BUY ? InpBreakevenBufferPips * _Point : -InpBreakevenBufferPips * _Point);
      newSL = NormalizeDouble(newSL, _Digits);
      
      if(trade.PositionModify(ticket, newSL, posTP)) {
         Print("✓ Breakeven activado para ticket ", ticket, " | Nuevo SL: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Control de drawdown basado en equity                             |
//+------------------------------------------------------------------+
void CheckDrawdownLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   MqlDateTime dtNow, dtLastDay, dtLastWeek;
   TimeToStruct(TimeCurrent(), dtNow);
   TimeToStruct(lastDayCheck, dtLastDay);
   TimeToStruct(lastWeekCheck, dtLastWeek);
   
   // Reset diario
   if(dtNow.day != dtLastDay.day) {
      dailyStartEquity = currentEquity;
      lastDayCheck = TimeCurrent();
      dailyLimitReached = false;
      Print("Nuevo día - Equity inicial: ", dailyStartEquity);
   }
   
   // Reset semanal (lunes)
   if(dtNow.day_of_week == 1 && dtLastWeek.day_of_week != 1) {
      weeklyStartEquity = currentEquity;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
      Print("Nueva semana - Equity inicial: ", weeklyStartEquity);
   }
   
   // Calcular DD
   double dailyDD = 0, weeklyDD = 0;
   if(dailyStartEquity != 0)
      dailyDD = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   if(weeklyStartEquity != 0)
      weeklyDD = (weeklyStartEquity - currentEquity) / weeklyStartEquity * 100.0;
   
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
//| Reset contador de trades diarios                                 |
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
//| Filtro horario                                                   |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!InpUseTimeFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   if(InpStartHour <= InpEndHour)
      return (hour >= InpStartHour && hour < InpEndHour);
   else
      return (hour >= InpStartHour || hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Actualizar comentario en gráfico                                 |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyDD = 0, weeklyDD = 0;
   if(dailyStartEquity != 0)
      dailyDD = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   if(weeklyStartEquity != 0)
      weeklyDD = (weeklyStartEquity - currentEquity) / weeklyStartEquity * 100.0;
   
   string status = "ACTIVO";
   if(dailyLimitReached) status = "DD DIARIO ALCANZADO";
   if(weeklyLimitReached) status = "DD SEMANAL ALCANZADO";
   if(tradesToday >= InpMaxTradesPerDay) status = "LÍMITE TRADES DIARIO";
   
   string breakoutStatus = "Buscando breakout...";
   if(breakoutDetected && waitingForPullback) {
      breakoutStatus = StringFormat("Esperando pullback a %.2f", pullbackTarget);
   }
   
   string comment = StringFormat(
      "═══════════════════════════════════════\n" +
      "  EA V12.1 BREAKOUT + PULLBACK\n" +
      "═══════════════════════════════════════\n" +
      "Estado: %s\n" +
      "Trades hoy: %d/%d\n" +
      "DD Diario (eq): %.2f%% / %.1f%%\n" +
      "DD Semanal (eq): %.2f%% / %.1f%%\n" +
      "───────────────────────────────────────\n" +
      "EMA200 H1: %.2f\n" +
      "Precio: %.2f\n" +
      "%s\n" +
      "───────────────────────────────────────\n" +
      "Posiciones: %d\n" +
      "Balance: %.2f | Equity: %.2f\n" +
      "═══════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay,
      dailyDD, InpMaxDailyDD,
      weeklyDD, InpMaxWeeklyDD,
      emaBuffer[0],
      SymbolInfoDouble(_Symbol, SYMBOL_BID),
      breakoutStatus,
      PositionsTotal(),
      AccountInfoDouble(ACCOUNT_BALANCE),
      currentEquity
   );
   
   Comment(comment);
}
//+------------------------------------------------------------------+