//+------------------------------------------------------------------+
//|                              EURUSD_V1_0_NY_BREAKOUT.mq5         |
//|                        Breakout + Pullback NY Session             |
//|                                                                    |
//| Basado en V12.0 (que funciona) adaptado para EURUSD              |
//| Configuración RECOMENDADA con visualización avanzada              |
//+------------------------------------------------------------------+
#property copyright "NY Breakout System V1.0"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS - Todos configurables desde MT5                           |
//+------------------------------------------------------------------+

input group "=== CONFIGURACIÓN BÁSICA ==="
input double InpRiskPercent = 0.5;              // Riesgo por trade (%)
input double InpRiskReward = 2.0;               // Risk:Reward ratio
input int InpMaxTradesPerDay = 2;               // Máximo trades por día
input int InpMagicNumber = 130001;              // Magic Number

input group "=== FILTRO HORARIO (Nueva York) ==="
input bool InpUseTimeFilter = false;            // Activar filtro horario
input int InpStartHourGMT = 8;                  // Hora inicio GMT (8=08:00)
input int InpEndHourGMT = 20;                   // Hora fin GMT (20=20:00)

input group "=== FILTRO DE TENDENCIA ==="
input int InpEMA200Period = 200;                // Período EMA200
input ENUM_TIMEFRAMES InpEMATF = PERIOD_H1;     // Timeframe EMA

input group "=== DETECCIÓN DE SWINGS ==="
input int InpSwingLookback = 10;                // Barras para detectar swing
input int InpSwingConfirmation = 1;             // Velas confirmación pivote (1-3)

input group "=== BREAKOUT ==="
input bool InpUseATRForBreakout = false;        // Usar ATR para breakout
input int InpMinBreakoutPips = 7;               // Mínimo breakout en pips
input double InpMinBreakoutATR = 0.3;           // Múltiplo ATR si activado

input group "=== PULLBACK ==="
input double InpPullbackPercent = 40.0;         // % retroceso (40=40%)
input int InpMaxPullbackBars = 20;              // Timeout pullback (velas)

input group "=== GESTIÓN DE POSICIÓN ==="
input bool InpUseBreakeven = true;              // Activar breakeven
input double InpBreakevenTrigger = 0.9;         // RR para activar BE (0.9=90%)
input int InpBreakevenBufferPips = 5;           // Buffer BE en pips

input group "=== CONTROL DE DRAWDOWN ==="
input double InpMaxDailyDD = 3.0;               // DD máximo diario (%)
input double InpMaxWeeklyDD = 6.0;              // DD máximo semanal (%)

input group "=== FILTROS OPCIONALES ==="
input bool InpUseVolatilityFilter = false;      // Filtro volatilidad
input double InpMinATR = 30.0;                  // ATR mínimo en pips

input group "=== VISUALIZACIÓN ==="
input bool InpShowPanel = true;                 // Mostrar panel info
input bool InpShowSwings = true;                // Mostrar swings en gráfico
input bool InpShowBreakoutZones = true;         // Mostrar zonas breakout
input bool InpShowPullbackTarget = true;        // Mostrar target pullback
input color InpSwingHighColor = clrRed;         // Color swing high
input color InpSwingLowColor = clrBlue;         // Color swing low
input color InpBreakoutColor = clrOrange;       // Color zona breakout
input color InpPullbackColor = clrGreen;        // Color pullback target

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+

CTrade trade;
int emaHandle;
int atrHandle;
double emaBuffer[];
double atrBuffer[];

datetime lastBarTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;

double dailyStartEquity = 0;
double weeklyStartEquity = 0;
datetime lastDayCheck = 0;
datetime lastWeekCheck = 0;
bool dailyLimitReached = false;
bool weeklyLimitReached = false;

// Estado de breakout
bool breakoutDetected = false;
bool waitingForPullback = false;
double breakoutLevel = 0;
double breakoutRange = 0;
double pullbackTarget = 0;
datetime breakoutTime = 0;
int breakoutDirection = 0; // 1=long, -1=short

// Swings detectados
double lastSwingHigh = 0;
double lastSwingLow = 0;
datetime lastSwingHighTime = 0;
datetime lastSwingLowTime = 0;

// Objetos gráficos
string objPrefix = "NYBO_";

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configurar trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
   // Crear indicadores
   emaHandle = iMA(_Symbol, InpEMATF, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) {
      Print("❌ Error creando EMA200: ", GetLastError());
      return INIT_FAILED;
   }
   
   atrHandle = iATR(_Symbol, PERIOD_M15, 14);
   if(atrHandle == INVALID_HANDLE) {
      Print("❌ Error creando ATR: ", GetLastError());
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   // Inicializar drawdown tracking
   dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   weeklyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastDayCheck = TimeCurrent();
   lastWeekCheck = TimeCurrent();
   
   // Limpiar objetos previos
   DeleteAllObjects();
   
   Print("═══════════════════════════════════════");
   Print("  EA EURUSD NY BREAKOUT V1.0 INICIADO");
   Print("═══════════════════════════════════════");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M15");
   Print("Riesgo: ", InpRiskPercent, "%");
   Print("Risk:Reward: 1:", InpRiskReward);
   Print("Filtro horario: ", InpUseTimeFilter ? "SÍ" : "NO");
   if(InpUseTimeFilter)
      Print("Ventana: ", InpStartHourGMT, ":00 - ", InpEndHourGMT, ":00 GMT");
   Print("═══════════════════════════════════════");
   
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
   
   DeleteAllObjects();
   Comment("");
   
   Print("EA detenido. Razón: ", reason);
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
   
   // Actualizar indicadores
   if(!UpdateIndicators())
      return;
   
   // Control de drawdown
   CheckDrawdownLimits();
   if(dailyLimitReached || weeklyLimitReached) {
      UpdateVisuals();
      return;
   }
   
   // Reset contador diario
   ResetDailyTradeCount();
   
   // Filtro horario
   if(InpUseTimeFilter && !IsTradingTime()) {
      UpdateVisuals();
      return;
   }
   
   // Filtro volatilidad
   if(InpUseVolatilityFilter && !CheckVolatility()) {
      UpdateVisuals();
      return;
   }
   
   // Gestionar posiciones abiertas
   if(PositionsTotal() > 0) {
      ManagePositions();
      UpdateVisuals();
      return;
   }
   
   // Verificar límite de trades
   if(tradesToday >= InpMaxTradesPerDay) {
      UpdateVisuals();
      return;
   }
   
   // Lógica principal
   if(!breakoutDetected) {
      DetectBreakout();
   }
   else if(waitingForPullback) {
      CheckPullback();
   }
   
   // Actualizar visualización
   UpdateVisuals();
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
   
   if(CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 3) {
      Print("Error copiando ATR: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Verificar horario de trading                                      |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   int currentHour = timeStruct.hour;
   
   // Manejar caso donde ventana cruza medianoche
   if(InpStartHourGMT < InpEndHourGMT) {
      return (currentHour >= InpStartHourGMT && currentHour < InpEndHourGMT);
   }
   else {
      return (currentHour >= InpStartHourGMT || currentHour < InpEndHourGMT);
   }
}

//+------------------------------------------------------------------+
//| Verificar volatilidad mínima                                      |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
   double atrPips = atrBuffer[0] / _Point;
   return (atrPips >= InpMinATR);
}

//+------------------------------------------------------------------+
//| Detectar breakout de swing                                        |
//+------------------------------------------------------------------+
void DetectBreakout()
{
   // Encontrar swings
   FindSwings();
   
   if(lastSwingHigh == 0 || lastSwingLow == 0)
      return;
   
   // Datos de vela anterior
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   
   // Calcular mínimo breakout
   double minBreakout;
   if(InpUseATRForBreakout) {
      double atrPips = atrBuffer[0] / _Point;
      minBreakout = InpMinBreakoutATR * atrPips * _Point;
   }
   else {
      minBreakout = InpMinBreakoutPips * _Point * 10;
   }
   
   // Verificar breakout alcista
   if(high1 > lastSwingHigh + minBreakout && close1 > lastSwingHigh) {
      if(close1 > emaBuffer[0]) {
         RegisterBreakout(1, lastSwingHigh, high1);
         Print("🔼 BREAKOUT ALCISTA detectado en ", lastSwingHigh);
      }
   }
   
   // Verificar breakout bajista
   if(low1 < lastSwingLow - minBreakout && close1 < lastSwingLow) {
      if(close1 < emaBuffer[0]) {
         RegisterBreakout(-1, lastSwingLow, low1);
         Print("🔽 BREAKOUT BAJISTA detectado en ", lastSwingLow);
      }
   }
}

//+------------------------------------------------------------------+
//| Registrar breakout detectado                                      |
//+------------------------------------------------------------------+
void RegisterBreakout(int direction, double level, double extremePrice)
{
   breakoutDetected = true;
   waitingForPullback = true;
   breakoutDirection = direction;
   breakoutLevel = level;
   breakoutTime = iTime(_Symbol, PERIOD_M15, 1);
   
   if(direction == 1) {
      breakoutRange = extremePrice - level;
      pullbackTarget = level + (breakoutRange * (1.0 - InpPullbackPercent/100.0));
   }
   else {
      breakoutRange = level - extremePrice;
      pullbackTarget = level - (breakoutRange * (1.0 - InpPullbackPercent/100.0));
   }
   
   Print("Target pullback: ", pullbackTarget, " | Timeout: ", InpMaxPullbackBars, " velas");
}

//+------------------------------------------------------------------+
//| Encontrar swings high y low                                       |
//+------------------------------------------------------------------+
void FindSwings()
{
   // Buscar swing high
   for(int i = InpSwingConfirmation + 1; i <= InpSwingLookback + InpSwingConfirmation; i++) {
      double high_i = iHigh(_Symbol, PERIOD_M15, i);
      bool isSwingHigh = true;
      
      // Verificar velas a la izquierda
      for(int left = 1; left <= InpSwingConfirmation; left++) {
         if(iHigh(_Symbol, PERIOD_M15, i + left) >= high_i) {
            isSwingHigh = false;
            break;
         }
      }
      
      // Verificar velas a la derecha
      if(isSwingHigh) {
         for(int right = 1; right <= InpSwingConfirmation; right++) {
            if(iHigh(_Symbol, PERIOD_M15, i - right) >= high_i) {
               isSwingHigh = false;
               break;
            }
         }
      }
      
      if(isSwingHigh) {
         lastSwingHigh = high_i;
         lastSwingHighTime = iTime(_Symbol, PERIOD_M15, i);
         break;
      }
   }
   
   // Buscar swing low
   for(int i = InpSwingConfirmation + 1; i <= InpSwingLookback + InpSwingConfirmation; i++) {
      double low_i = iLow(_Symbol, PERIOD_M15, i);
      bool isSwingLow = true;
      
      // Verificar velas a la izquierda
      for(int left = 1; left <= InpSwingConfirmation; left++) {
         if(iLow(_Symbol, PERIOD_M15, i + left) <= low_i) {
            isSwingLow = false;
            break;
         }
      }
      
      // Verificar velas a la derecha
      if(isSwingLow) {
         for(int right = 1; right <= InpSwingConfirmation; right++) {
            if(iLow(_Symbol, PERIOD_M15, i - right) <= low_i) {
               isSwingLow = false;
               break;
            }
         }
      }
      
      if(isSwingLow) {
         lastSwingLow = low_i;
         lastSwingLowTime = iTime(_Symbol, PERIOD_M15, i);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar pullback y entrada                                      |
//+------------------------------------------------------------------+
void CheckPullback()
{
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   
   // Verificar timeout
   int barsSinceBreakout = (int)((TimeCurrent() - breakoutTime) / PeriodSeconds(PERIOD_M15));
   if(barsSinceBreakout > InpMaxPullbackBars) {
      Print("⏱ Timeout: pullback no ocurrió en ", InpMaxPullbackBars, " velas");
      ResetBreakout();
      return;
   }
   
   // Verificar pullback LONG
   if(breakoutDirection == 1) {
      if(low1 <= pullbackTarget && close1 > pullbackTarget) {
         if(close1 > emaBuffer[0]) {
            Print("✅ Pullback alcista completado - Abriendo LONG");
            OpenTrade(ORDER_TYPE_BUY);
            ResetBreakout();
         }
      }
   }
   
   // Verificar pullback SHORT
   if(breakoutDirection == -1) {
      if(high1 >= pullbackTarget && close1 < pullbackTarget) {
         if(close1 < emaBuffer[0]) {
            Print("✅ Pullback bajista completado - Abriendo SHORT");
            OpenTrade(ORDER_TYPE_SELL);
            ResetBreakout();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Abrir trade                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double entryPrice, sl, tp, slDistance;
   
   if(type == ORDER_TYPE_BUY) {
      entryPrice = ask;
      sl = breakoutLevel;
      slDistance = entryPrice - sl;
      
      // Mínimo 10 pips
      if(slDistance < 100 * _Point)
         slDistance = 100 * _Point;
      
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + (slDistance * InpRiskReward), _Digits);
   }
   else {
      entryPrice = bid;
      sl = breakoutLevel;
      slDistance = sl - entryPrice;
      
      if(slDistance < 100 * _Point)
         slDistance = 100 * _Point;
      
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - (slDistance * InpRiskReward), _Digits);
   }
   
   // Calcular lote
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double slPips = slDistance / _Point;
   double lotSize = CalculateLotSize(riskAmount, slPips);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("❌ Lote muy pequeño: ", lotSize);
      return;
   }
   
   // Ejecutar orden
   string comment = StringFormat("NYBO_RR%.1f", InpRiskReward);
   bool result = false;
   
   if(type == ORDER_TYPE_BUY) {
      result = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   else {
      result = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment);
   }
   
   if(result) {
      Print("✅ Trade abierto: ", EnumToString(type), " | Lote: ", lotSize, " | SL: ", sl, " | TP: ", tp);
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
void ManagePositions()
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
   double breakevenTrigger = slDistance * InpBreakevenTrigger;
   
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
      double buffer = InpBreakevenBufferPips * _Point * 10;
      double newSL = NormalizeDouble(posOpenPrice + (buffer * ((posType == POSITION_TYPE_BUY) ? 1 : -1)), _Digits);
      
      if(trade.PositionModify(ticket, newSL, posTP)) {
         Print("✅ Breakeven activado | Ticket: ", ticket, " | Nuevo SL: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Control de drawdown                                               |
//+------------------------------------------------------------------+
void CheckDrawdownLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   // Reset diario
   MqlDateTime lastDayStruct;
   TimeToStruct(lastDayCheck, lastDayStruct);
   
   if(timeStruct.day != lastDayStruct.day) {
      dailyStartEquity = currentEquity;
      lastDayCheck = TimeCurrent();
      dailyLimitReached = false;
      Print("📅 Nuevo día - Equity inicial: ", dailyStartEquity);
   }
   
   // Reset semanal (lunes)
   MqlDateTime lastWeekStruct;
   TimeToStruct(lastWeekCheck, lastWeekStruct);
   
   if(timeStruct.day_of_week == 1 && lastWeekStruct.day_of_week != 1) {
      weeklyStartEquity = currentEquity;
      lastWeekCheck = TimeCurrent();
      weeklyLimitReached = false;
      Print("📅 Nueva semana - Equity inicial: ", weeklyStartEquity);
   }
   
   // Calcular DD
   double dailyDD = ((dailyStartEquity - currentEquity) / dailyStartEquity) * 100.0;
   double weeklyDD = ((weeklyStartEquity - currentEquity) / weeklyStartEquity) * 100.0;
   
   if(dailyDD >= InpMaxDailyDD) {
      dailyLimitReached = true;
      Print("⚠️ LÍMITE DD DIARIO ALCANZADO: ", DoubleToString(dailyDD, 2), "%");
   }
   
   if(weeklyDD >= InpMaxWeeklyDD) {
      weeklyLimitReached = true;
      Print("⚠️ LÍMITE DD SEMANAL ALCANZADO: ", DoubleToString(weeklyDD, 2), "%");
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
//| Reset estado de breakout                                          |
//+------------------------------------------------------------------+
void ResetBreakout()
{
   breakoutDetected = false;
   waitingForPullback = false;
   breakoutLevel = 0;
   breakoutRange = 0;
   pullbackTarget = 0;
   breakoutTime = 0;
   breakoutDirection = 0;
}

//+------------------------------------------------------------------+
//| Actualizar visualización                                          |
//+------------------------------------------------------------------+
void UpdateVisuals()
{
   if(InpShowPanel)
      DrawInfoPanel();
   
   if(InpShowSwings)
      DrawSwings();
   
   if(InpShowBreakoutZones && breakoutDetected)
      DrawBreakoutZone();
   
   if(InpShowPullbackTarget && waitingForPullback)
      DrawPullbackTarget();
}

//+------------------------------------------------------------------+
//| Dibujar panel de información                                      |
//+------------------------------------------------------------------+
void DrawInfoPanel()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyDD = ((dailyStartEquity - currentEquity) / dailyStartEquity) * 100.0;
   double weeklyDD = ((weeklyStartEquity - currentEquity) / weeklyStartEquity) * 100.0;
   
   string status = "🟢 ACTIVO";
   color statusColor = clrLime;
   
   if(dailyLimitReached) {
      status = "🔴 DD DIARIO";
      statusColor = clrRed;
   }
   else if(weeklyLimitReached) {
      status = "🔴 DD SEMANAL";
      statusColor = clrRed;
   }
   else if(tradesToday >= InpMaxTradesPerDay) {
      status = "🟡 LÍMITE TRADES";
      statusColor = clrYellow;
   }
   else if(InpUseTimeFilter && !IsTradingTime()) {
      status = "⏸ FUERA HORARIO";
      statusColor = clrGray;
   }
   
   string breakoutStatus = "🔍 Buscando breakout...";
   if(breakoutDetected && waitingForPullback) {
      breakoutStatus = StringFormat("⏳ Esperando pullback %.5f", pullbackTarget);
   }
   
   double atrPips = atrBuffer[0] / _Point;
   
   string info = StringFormat(
      "╔═══════════════════════════════════════╗\n" +
      "║   EURUSD NY BREAKOUT V1.0            ║\n" +
      "╠═══════════════════════════════════════╣\n" +
      "║ Estado: %-28s ║\n" +
      "║ Trades hoy: %d/%d                      ║\n" +
      "║ DD Diario: %.2f%% / %.1f%%              ║\n" +
      "║ DD Semanal: %.2f%% / %.1f%%             ║\n" +
      "╠═══════════════════════════════════════╣\n" +
      "║ EMA200 H1: %.5f                    ║\n" +
      "║ ATR: %.1f pips                        ║\n" +
      "║ Precio: %.5f                       ║\n" +
      "╠═══════════════════════════════════════╣\n" +
      "║ Swing High: %.5f                   ║\n" +
      "║ Swing Low: %.5f                    ║\n" +
      "║ %s ║\n" +
      "╠═══════════════════════════════════════╣\n" +
      "║ Posiciones: %d                        ║\n" +
      "║ Balance: $%.2f                      ║\n" +
      "║ Equity: $%.2f                       ║\n" +
      "╚═══════════════════════════════════════╝",
      status,
      tradesToday, InpMaxTradesPerDay,
      dailyDD, InpMaxDailyDD,
      weeklyDD, InpMaxWeeklyDD,
      emaBuffer[0],
      atrPips,
      SymbolInfoDouble(_Symbol, SYMBOL_BID),
      lastSwingHigh,
      lastSwingLow,
      breakoutStatus,
      PositionsTotal(),
      AccountInfoDouble(ACCOUNT_BALANCE),
      currentEquity
   );
   
   Comment(info);
}

//+------------------------------------------------------------------+
//| Dibujar swings en gráfico                                         |
//+------------------------------------------------------------------+
void DrawSwings()
{
   // Swing High
   if(lastSwingHigh > 0) {
      string objName = objPrefix + "SwingHigh";
      
      if(ObjectFind(0, objName) < 0) {
         ObjectCreate(0, objName, OBJ_TREND, 0, lastSwingHighTime, lastSwingHigh, 
                      TimeCurrent() + PeriodSeconds(PERIOD_M15) * 50, lastSwingHigh);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, InpSwingHighColor);
         ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, objName, OBJPROP_BACK, true);
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      }
      else {
         ObjectMove(0, objName, 0, lastSwingHighTime, lastSwingHigh);
         ObjectMove(0, objName, 1, TimeCurrent() + PeriodSeconds(PERIOD_M15) * 50, lastSwingHigh);
      }
      
      // Etiqueta
      string labelName = objPrefix + "SwingHighLabel";
      if(ObjectFind(0, labelName) < 0) {
         ObjectCreate(0, labelName, OBJ_TEXT, 0, lastSwingHighTime, lastSwingHigh);
         ObjectSetString(0, labelName, OBJPROP_TEXT, " ▼ Swing High");
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpSwingHighColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
      }
      else {
         ObjectMove(0, labelName, 0, lastSwingHighTime, lastSwingHigh);
      }
   }
   
   // Swing Low
   if(lastSwingLow > 0) {
      string objName = objPrefix + "SwingLow";
      
      if(ObjectFind(0, objName) < 0) {
         ObjectCreate(0, objName, OBJ_TREND, 0, lastSwingLowTime, lastSwingLow, 
                      TimeCurrent() + PeriodSeconds(PERIOD_M15) * 50, lastSwingLow);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, InpSwingLowColor);
         ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, objName, OBJPROP_BACK, true);
         ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      }
      else {
         ObjectMove(0, objName, 0, lastSwingLowTime, lastSwingLow);
         ObjectMove(0, objName, 1, TimeCurrent() + PeriodSeconds(PERIOD_M15) * 50, lastSwingLow);
      }
      
      // Etiqueta
      string labelName = objPrefix + "SwingLowLabel";
      if(ObjectFind(0, labelName) < 0) {
         ObjectCreate(0, labelName, OBJ_TEXT, 0, lastSwingLowTime, lastSwingLow);
         ObjectSetString(0, labelName, OBJPROP_TEXT, " ▲ Swing Low");
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpSwingLowColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
      }
      else {
         ObjectMove(0, labelName, 0, lastSwingLowTime, lastSwingLow);
      }
   }
}

//+------------------------------------------------------------------+
//| Dibujar zona de breakout                                          |
//+------------------------------------------------------------------+
void DrawBreakoutZone()
{
   string objName = objPrefix + "BreakoutZone";
   
   datetime time1 = breakoutTime;
   datetime time2 = TimeCurrent() + PeriodSeconds(PERIOD_M15) * 30;
   
   if(ObjectFind(0, objName) < 0) {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, time1, breakoutLevel - 5*_Point, 
                   time2, breakoutLevel + 5*_Point);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, InpBreakoutColor);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_FILL, true);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   }
   else {
      ObjectMove(0, objName, 0, time1, breakoutLevel - 5*_Point);
      ObjectMove(0, objName, 1, time2, breakoutLevel + 5*_Point);
   }
   
   // Etiqueta
   string labelName = objPrefix + "BreakoutLabel";
   string text = (breakoutDirection == 1) ? "🔼 BREAKOUT ALCISTA" : "🔽 BREAKOUT BAJISTA";
   
   if(ObjectFind(0, labelName) < 0) {
      ObjectCreate(0, labelName, OBJ_TEXT, 0, breakoutTime, breakoutLevel);
      ObjectSetString(0, labelName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpBreakoutColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
      ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   }
   else {
      ObjectMove(0, labelName, 0, breakoutTime, breakoutLevel);
      ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   }
}

//+------------------------------------------------------------------+
//| Dibujar target de pullback                                        |
//+------------------------------------------------------------------+
void DrawPullbackTarget()
{
   string objName = objPrefix + "PullbackTarget";
   
   datetime time1 = breakoutTime;
   datetime time2 = TimeCurrent() + PeriodSeconds(PERIOD_M15) * 30;
   
   if(ObjectFind(0, objName) < 0) {
      ObjectCreate(0, objName, OBJ_TREND, 0, time1, pullbackTarget, time2, pullbackTarget);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, InpPullbackColor);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   }
   else {
      ObjectMove(0, objName, 0, time1, pullbackTarget);
      ObjectMove(0, objName, 1, time2, pullbackTarget);
   }
   
   // Etiqueta
   string labelName = objPrefix + "PullbackLabel";
   string text = StringFormat("🎯 Target Pullback %.5f", pullbackTarget);
   
   if(ObjectFind(0, labelName) < 0) {
      ObjectCreate(0, labelName, OBJ_TEXT, 0, breakoutTime, pullbackTarget);
      ObjectSetString(0, labelName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, InpPullbackColor);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
      ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   }
   else {
      ObjectMove(0, labelName, 0, breakoutTime, pullbackTarget);
      ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   }
   
   // Dibujar zona de entrada
   string zoneName = objPrefix + "EntryZone";
   double zoneTop = pullbackTarget + (10 * _Point);
   double zoneBottom = pullbackTarget - (10 * _Point);
   
   if(ObjectFind(0, zoneName) < 0) {
      ObjectCreate(0, zoneName, OBJ_RECTANGLE, 0, time1, zoneTop, time2, zoneBottom);
      ObjectSetInteger(0, zoneName, OBJPROP_COLOR, InpPullbackColor);
      ObjectSetInteger(0, zoneName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, zoneName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, zoneName, OBJPROP_FILL, true);
      ObjectSetInteger(0, zoneName, OBJPROP_BACK, true);
      ObjectSetInteger(0, zoneName, OBJPROP_SELECTABLE, false);
   }
   else {
      ObjectMove(0, zoneName, 0, time1, zoneTop);
      ObjectMove(0, zoneName, 1, time2, zoneBottom);
   }
}

//+------------------------------------------------------------------+
//| Eliminar todos los objetos del EA                                 |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--) {
      string objName = ObjectName(0, i, 0, -1);
      if(StringFind(objName, objPrefix) == 0) {
         ObjectDelete(0, objName);
      }
   }
}
//+------------------------------------------------------------------+
