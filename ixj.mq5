//+------------------------------------------------------------------+
//|                                           HealthBreakout_PropEA  |
//|                                    Estrategia para Prop Firms    |
//|                                              Versión 1.0 - 2025  |
//+------------------------------------------------------------------+
#property copyright "Prop Firm EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters (configurables desde MT5)
input group "=== CONFIGURACIÓN GENERAL ==="
input long InpMagicNumber = 20250220;           // Magic Number
input string InpTradeComment = "HealthBreakout"; // Comentario de órdenes

input group "=== HORARIO DE OPERACIÓN (NY Session) ==="
input bool   InpUseTimeFilter = true;           // Activar filtro horario
input int    InpStartHour = 14;                  // Hora inicio (GMT, 14 = 9am NY)
input int    InpEndHour = 21;                     // Hora fin (GMT, 21 = 4pm NY)

input group "=== INDICADORES ==="
input int    InpEMAShort = 50;                    // EMA corta (períodos)
input int    InpEMALong = 200;                     // EMA larga (períodos)
input int    InpRSIPeriod = 14;                     // Período RSI
input double InpRSIOverbought = 70;                  // Nivel sobrecompra
input double InpRSIOversold = 30;                    // Nivel sobreventa
input int    InpATRPeriod = 14;                      // Período ATR

input group "=== DETECCIÓN DE SWINGS ==="
input int    InpSwingLookback = 30;                  // Barras máximas para buscar swing
input int    InpSwingLeft = 3;                        // Barras izquierda para confirmar
input int    InpSwingRight = 3;                       // Barras derecha para confirmar

input group "=== BREAKOUT ==="
input double InpBreakoutATRMult = 0.5;                // Multiplicador ATR para margen breakout
input bool   InpUseVolumeFilter = true;                // Usar filtro de volumen
input double InpMinVolumeRatio = 1.5;                  // Volumen mínimo sobre media

input group "=== PULLBACK ==="
input double InpPullbackFib = 0.382;                   // Nivel Fibonacci para pullback
input int    InpMaxPullbackBars = 15;                   // Máx velas esperando pullback

input group "=== GESTIÓN DE RIESGO ==="
input double InpRiskPerTrade = 0.5;                     // % riesgo por operación
input double InpMinRiskReward = 2.0;                     // RR mínimo
input int    InpMaxTradesPerDay = 1;                      // Máx operaciones por día
input int    InpMaxConsecutiveLosses = 3;                 // Pérdidas consecutivas para pausa
input int    InpPauseHoursAfterLosses = 24;               // Horas de pausa

input group "=== REGLAS PROP FIRM ==="
input double InpMaxDailyLoss = 2.0;                       // % pérdida máxima diaria (equity)
input double InpMaxTotalLoss = 4.0;                        // % pérdida máxima total (desde inicio)

input group "=== GESTIÓN DE POSICIÓN ==="
input bool   InpUsePartialClose = true;                   // Cierres parciales
input double InpPartial1Level = 1.0;                       // Nivel 1R para primer cierre
input double InpPartial1Percent = 30;                      // % a cerrar en nivel 1
input double InpPartial2Level = 1.5;                       // Nivel 1.5R para segundo cierre
input double InpPartial2Percent = 30;                      // % a cerrar en nivel 2
input bool   InpUseBreakeven = true;                       // Activar breakeven
input double InpBreakevenLevel = 1.5;                       // Nivel para activar breakeven
input int    InpBreakevenBufferPips = 5;                    // Buffer en pips
input bool   InpUseTrailing = true;                         // Activar trailing stop
input double InpTrailingStart = 2.0;                        // Nivel para iniciar trailing
input double InpTrailingDistanceATR = 1.0;                   // Distancia trailing en ATR

input group "=== AVANZADO ==="
input bool   InpUseSpreadFilter = true;                     // Evitar spreads altos
input double InpMaxSpreadPips = 2.5;                         // Máx spread permitido

//--- Global Variables
CTrade trade;
int emaShortHandle, emaLongHandle, rsiHandle, atrHandle;
double emaShort[], emaLong[], rsi[], atr[];
datetime lastBarTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;
double dailyStartEquity = 0;
double totalStartEquity = 0;
datetime lastDayCheck = 0;
bool tradingPaused = false;
datetime pauseUntil = 0;
int consecutiveLosses = 0;

//--- Estado de la estrategia
struct SwingPoint {
   double price;
   datetime time;
   bool isHigh; // true = swing high, false = swing low
};
SwingPoint lastSwing;
bool breakoutDetected = false;
bool waitingForPullback = false;
double breakoutLevel = 0;
double pullbackTarget = 0;
datetime breakoutTime = 0;
int pullbackBarsCount = 0;
int breakoutDirection = 0; // 1 = long, -1 = short

//--- Para seguimiento de trades
struct TradeRecord {
   ulong ticket;
   double openPrice;
   double sl;
   double tp;
   double riskAmount;
   double partial1Closed;
   double partial2Closed;
};
TradeRecord currentTrade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configurar trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_RETURN);
   trade.SetAsyncMode(false);
   
   // Crear handles de indicadores
   emaShortHandle = iMA(_Symbol, PERIOD_H1, InpEMAShort, 0, MODE_EMA, PRICE_CLOSE);
   emaLongHandle  = iMA(_Symbol, PERIOD_H1, InpEMALong, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle      = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   atrHandle      = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   
   if(emaShortHandle == INVALID_HANDLE || emaLongHandle == INVALID_HANDLE ||
      rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE) {
      Print("Error creando handles de indicadores");
      return INIT_FAILED;
   }
   
   // Configurar buffers como series
   ArraySetAsSeries(emaShort, true);
   ArraySetAsSeries(emaLong, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   
   // Inicializar equity de inicio
   totalStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyStartEquity = totalStartEquity;
   lastDayCheck = TimeCurrent();
   
   Print("=== HealthBreakout Prop EA iniciado ===");
   Print("Símbolo: ", _Symbol);
   Print("Riesgo por trade: ", InpRiskPerTrade, "%");
   Print("Drawdown máximo diario: ", InpMaxDailyLoss, "%");
   Print("Drawdown máximo total: ", InpMaxTotalLoss, "%");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaShortHandle != INVALID_HANDLE) IndicatorRelease(emaShortHandle);
   if(emaLongHandle != INVALID_HANDLE)  IndicatorRelease(emaLongHandle);
   if(rsiHandle != INVALID_HANDLE)      IndicatorRelease(rsiHandle);
   if(atrHandle != INVALID_HANDLE)      IndicatorRelease(atrHandle);
   
   Print("EA detenido. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Verificar nueva barra en H1 ---
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // --- Filtro horario ---
   if(InpUseTimeFilter && !IsTradingTime()) {
      Comment("Fuera de horario de trading");
      return;
   }
   
   // --- Control de pausa por pérdidas consecutivas ---
   if(tradingPaused) {
      if(TimeCurrent() >= pauseUntil) {
         tradingPaused = false;
         consecutiveLosses = 0;
         Print("Pausa finalizada, reanudando trading");
      } else {
         Comment("Trading pausado por ", (pauseUntil - TimeCurrent())/3600, " horas más");
         return;
      }
   }
   
   // --- Control de drawdown según reglas prop firm ---
   CheckDrawdownLimits();
   if(AccountInfoDouble(ACCOUNT_EQUITY) <= 0) return; // Protección
   
   // --- Actualizar indicadores ---
   if(!UpdateIndicators()) return;
   
   // --- Gestionar posiciones abiertas ---
   if(PositionsTotal() > 0) {
      ManageOpenPosition();
      return; // No buscar nuevas señales si ya hay posición
   }
   
   // --- Resetear contador diario de trades ---
   ResetDailyTradeCount();
   if(tradesToday >= InpMaxTradesPerDay) {
      Comment("Límite diario de trades alcanzado");
      return;
   }
   
   // --- Lógica principal de señales ---
   if(breakoutDetected && waitingForPullback) {
      CheckPullback();
   } else {
      DetectBreakout();
   }
   
   // --- Actualizar comentario en pantalla ---
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Verificar si está en horario de trading (NY Session)            |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   if(InpStartHour <= InpEndHour)
      return (hour >= InpStartHour && hour < InpEndHour);
   else
      return (hour >= InpStartHour || hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Actualizar valores de indicadores                                |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   if(CopyBuffer(emaShortHandle, 0, 1, 3, emaShort) < 3) return false;
   if(CopyBuffer(emaLongHandle, 0, 1, 3, emaLong) < 3) return false;
   if(CopyBuffer(rsiHandle, 0, 1, 3, rsi) < 3) return false;
   if(CopyBuffer(atrHandle, 0, 1, 3, atr) < 3) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Detectar breakout de swing                                      |
//+------------------------------------------------------------------+
void DetectBreakout()
{
   double high1 = iHigh(_Symbol, PERIOD_H1, 1);
   double low1 = iLow(_Symbol, PERIOD_H1, 1);
   double close1 = iClose(_Symbol, PERIOD_H1, 1);
   double volume1 = (double)iVolume(_Symbol, PERIOD_H1, 1);
   
   // Calcular media de volumen (últimas 20 velas)
   double avgVolume = 0;
   if(InpUseVolumeFilter) {
      for(int i = 1; i <= 20; i++) {
         avgVolume += (double)iVolume(_Symbol, PERIOD_H1, i);
      }
      avgVolume /= 20.0;
   }
   
   // Encontrar últimos swings
   double swingHigh, swingLow;
   datetime swingTime;
   bool foundHigh = FindSwingHigh(swingHigh, swingTime);
   bool foundLow = FindSwingLow(swingLow, swingTime);
   
   // Margen de breakout basado en ATR
   double atrValue = atr[1]; // ATR de la vela anterior
   double minBreakout = InpBreakoutATRMult * atrValue;
   
   // --- Breakout alcista ---
   if(foundHigh && close1 > swingHigh + minBreakout && high1 > swingHigh + minBreakout) {
      // Filtro de tendencia: precio por encima de EMA50 y EMA200
      if(close1 > emaShort[1] && close1 > emaLong[1]) {
         // Filtro de volumen (opcional)
         if(!InpUseVolumeFilter || volume1 >= avgVolume * InpMinVolumeRatio) {
            // Filtro de RSI (no sobrecomprado)
            if(rsi[1] < InpRSIOverbought) {
               // Breakout confirmado
               breakoutDetected = true;
               waitingForPullback = true;
               breakoutDirection = 1;
               breakoutLevel = swingHigh;
               breakoutTime = iTime(_Symbol, PERIOD_H1, 1);
               pullbackBarsCount = 0;
               
               // Calcular rango de breakout y pullback target (Fibonacci)
               double breakoutRange = high1 - swingHigh;
               pullbackTarget = swingHigh + breakoutRange * InpPullbackFib;
               
               lastSwing.price = swingHigh;
               lastSwing.time = swingTime;
               lastSwing.isHigh = false; // breakout alcista, esperamos pullback hacia abajo
               
               Print("BREAKOUT ALCISTA detectado en ", swingHigh, " | Target pullback: ", pullbackTarget);
            }
         }
      }
   }
   
   // --- Breakout bajista ---
   if(foundLow && close1 < swingLow - minBreakout && low1 < swingLow - minBreakout) {
      if(close1 < emaShort[1] && close1 < emaLong[1]) {
         if(!InpUseVolumeFilter || volume1 >= avgVolume * InpMinVolumeRatio) {
            if(rsi[1] > InpRSIOversold) {
               breakoutDetected = true;
               waitingForPullback = true;
               breakoutDirection = -1;
               breakoutLevel = swingLow;
               breakoutTime = iTime(_Symbol, PERIOD_H1, 1);
               pullbackBarsCount = 0;
               
               double breakoutRange = swingLow - low1;
               pullbackTarget = swingLow - breakoutRange * InpPullbackFib;
               
               lastSwing.price = swingLow;
               lastSwing.time = swingTime;
               lastSwing.isHigh = true; // breakout bajista, esperamos pullback hacia arriba
               
               Print("BREAKOUT BAJISTA detectado en ", swingLow, " | Target pullback: ", pullbackTarget);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar pullback y entrada                                    |
//+------------------------------------------------------------------+
void CheckPullback()
{
   // Timeout
   pullbackBarsCount++;
   if(pullbackBarsCount > InpMaxPullbackBars) {
      ResetBreakoutState();
      Print("Timeout: pullback no ocurrió en ", InpMaxPullbackBars, " velas");
      return;
   }
   
   double low1 = iLow(_Symbol, PERIOD_H1, 1);
   double high1 = iHigh(_Symbol, PERIOD_H1, 1);
   double close1 = iClose(_Symbol, PERIOD_H1, 1);
   double rsi1 = rsi[1];
   
   // Entrada LONG (breakout alcista)
   if(breakoutDirection == 1) {
      // Condición: precio toca pullback target y cierra por encima
      if(low1 <= pullbackTarget && close1 > pullbackTarget) {
         // Verificar RSI no sobrecomprado
         if(rsi1 < InpRSIOverbought) {
            // Verificar que sigue por encima de EMA
            if(close1 > emaShort[1] && close1 > emaLong[1]) {
               OpenTrade(ORDER_TYPE_BUY);
               ResetBreakoutState();
            }
         }
      }
   }
   
   // Entrada SHORT (breakout bajista)
   if(breakoutDirection == -1) {
      if(high1 >= pullbackTarget && close1 < pullbackTarget) {
         if(rsi1 > InpRSIOversold) {
            if(close1 < emaShort[1] && close1 < emaLong[1]) {
               OpenTrade(ORDER_TYPE_SELL);
               ResetBreakoutState();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Abrir operación                                                  |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = (ask - bid) / point;
   
   // Filtro de spread máximo
   if(InpUseSpreadFilter && spread > InpMaxSpreadPips) {
      Print("Spread demasiado alto: ", spread, " pips. No se abre operación.");
      return;
   }
   
   double entryPrice, sl, tp;
   double slDistance;
   
   if(orderType == ORDER_TYPE_BUY) {
      entryPrice = ask;
      slDistance = MathAbs(entryPrice - breakoutLevel);
      // SL mínimo de 20 pips para evitar SL demasiado ajustado
      if(slDistance < 20 * point) slDistance = 20 * point;
      sl = NormalizeDouble(entryPrice - slDistance, _Digits);
      tp = NormalizeDouble(entryPrice + slDistance * InpMinRiskReward, _Digits);
   } else {
      entryPrice = bid;
      slDistance = MathAbs(breakoutLevel - entryPrice);
      if(slDistance < 20 * point) slDistance = 20 * point;
      sl = NormalizeDouble(entryPrice + slDistance, _Digits);
      tp = NormalizeDouble(entryPrice - slDistance * InpMinRiskReward, _Digits);
   }
   
   // Calcular lote según riesgo
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPerTrade / 100.0;
   double slPoints = slDistance / point;
   double lotSize = CalculateLotSize(riskAmount, slPoints);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      Print("Lote calculado demasiado pequeño: ", lotSize);
      return;
   }
   
   // Ejecutar orden
   bool success = false;
   if(orderType == ORDER_TYPE_BUY) {
      success = trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, InpTradeComment);
   } else {
      success = trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, InpTradeComment);
   }
   
   if(success) {
      Print("✓ Operación abierta: ", (orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT"),
            " Lote=", lotSize, " Entry=", entryPrice, " SL=", sl, " TP=", tp);
      tradesToday++;
      lastTradeDate = TimeCurrent();
      
      // Registrar trade actual
      currentTrade.ticket = trade.ResultOrder();
      currentTrade.openPrice = entryPrice;
      currentTrade.sl = sl;
      currentTrade.tp = tp;
      currentTrade.riskAmount = riskAmount;
      currentTrade.partial1Closed = 0;
      currentTrade.partial2Closed = 0;
   } else {
      Print("✗ Error abriendo operación: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote                                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slPoints)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Valor de 1 pip en la divisa de la cuenta para 1 lote
   double pipValue = tickValue * (point / tickSize);
   double lotSize = riskAmount / (slPoints * pipValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Gestionar posición abierta (cierres parciales, breakeven, trail)|
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   // Seleccionar la posición (solo una)
   if(PositionsTotal() == 0) return;
   ulong ticket = PositionGetTicket(0);
   if(!PositionSelectByTicket(ticket)) return;
   
   double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   double posSL = PositionGetDouble(POSITION_SL);
   double posTP = PositionGetDouble(POSITION_TP);
   double posVolume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double profitPoints = (posType == POSITION_TYPE_BUY) ? (currentPrice - posOpen) / point : (posOpen - currentPrice) / point;
   double riskPoints = MathAbs(posOpen - posSL) / point;
   double rrAchieved = profitPoints / riskPoints;
   
   // --- Cierres parciales ---
   if(InpUsePartialClose) {
      // Primer nivel parcial (1R)
      if(currentTrade.partial1Closed == 0 && rrAchieved >= InpPartial1Level) {
         double closePercent = InpPartial1Percent / 100.0;
         double closeVolume = posVolume * closePercent;
         if(trade.PositionClosePartial(ticket, closeVolume)) {
            currentTrade.partial1Closed = closeVolume;
            Print("Primer cierre parcial en ", InpPartial1Level, "R: cerrado ", closePercent*100, "%");
         }
      }
      // Segundo nivel parcial (1.5R)
      if(currentTrade.partial2Closed == 0 && rrAchieved >= InpPartial2Level) {
         double closePercent = InpPartial2Percent / 100.0;
         double remainingVolume = posVolume - currentTrade.partial1Closed;
         double closeVolume = remainingVolume * closePercent;
         if(trade.PositionClosePartial(ticket, closeVolume)) {
            currentTrade.partial2Closed = closeVolume;
            Print("Segundo cierre parcial en ", InpPartial2Level, "R: cerrado ", closePercent*100, "%");
         }
      }
   }
   
   // --- Breakeven ---
   if(InpUseBreakeven && rrAchieved >= InpBreakevenLevel) {
      // Verificar si ya está en breakeven (SL cerca de entrada)
      if(MathAbs(posSL - posOpen) > InpBreakevenBufferPips * point) {
         double newSL;
         if(posType == POSITION_TYPE_BUY) {
            newSL = NormalizeDouble(posOpen + InpBreakevenBufferPips * point, _Digits);
         } else {
            newSL = NormalizeDouble(posOpen - InpBreakevenBufferPips * point, _Digits);
         }
         if(trade.PositionModify(ticket, newSL, posTP)) {
            Print("Breakeven activado en ", InpBreakevenLevel, "R. Nuevo SL: ", newSL);
         }
      }
   }
   
   // --- Trailing Stop ---
   if(InpUseTrailing && rrAchieved >= InpTrailingStart) {
      double atrCurrent = atr[1]; // ATR actual
      double trailDistance = InpTrailingDistanceATR * atrCurrent;
      double newSL;
      if(posType == POSITION_TYPE_BUY) {
         newSL = NormalizeDouble(currentPrice - trailDistance, _Digits);
         if(newSL > posSL) {
            if(trade.PositionModify(ticket, newSL, posTP)) {
               Print("Trailing actualizado: nuevo SL ", newSL);
            }
         }
      } else {
         newSL = NormalizeDouble(currentPrice + trailDistance, _Digits);
         if(newSL < posSL || posSL == 0) {
            if(trade.PositionModify(ticket, newSL, posTP)) {
               Print("Trailing actualizado: nuevo SL ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Resetear estado de breakout                                      |
//+------------------------------------------------------------------+
void ResetBreakoutState()
{
   breakoutDetected = false;
   waitingForPullback = false;
   breakoutLevel = 0;
   pullbackTarget = 0;
   breakoutDirection = 0;
}

//+------------------------------------------------------------------+
//| Encontrar swing high verdadero                                   |
//+------------------------------------------------------------------+
bool FindSwingHigh(double &highPrice, datetime &highTime)
{
   int startBar = 2; // Empezar desde la vela 2 (la 1 es la anterior)
   int maxBars = InpSwingLookback;
   for(int i = startBar; i <= startBar + maxBars; i++) {
      double currentHigh = iHigh(_Symbol, PERIOD_H1, i);
      bool isHigh = true;
      
      // Verificar izquierda (barras más nuevas)
      for(int j = 1; j <= InpSwingLeft; j++) {
         if(i - j < 0) continue;
         if(currentHigh <= iHigh(_Symbol, PERIOD_H1, i - j)) {
            isHigh = false;
            break;
         }
      }
      if(isHigh) {
         // Verificar derecha (barras más viejas)
         for(int j = 1; j <= InpSwingRight; j++) {
            if(i + j >= Bars(_Symbol, PERIOD_H1)) break;
            if(currentHigh <= iHigh(_Symbol, PERIOD_H1, i + j)) {
               isHigh = false;
               break;
            }
         }
      }
      if(isHigh) {
         highPrice = currentHigh;
         highTime = iTime(_Symbol, PERIOD_H1, i);
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
   int maxBars = InpSwingLookback;
   for(int i = startBar; i <= startBar + maxBars; i++) {
      double currentLow = iLow(_Symbol, PERIOD_H1, i);
      bool isLow = true;
      
      for(int j = 1; j <= InpSwingLeft; j++) {
         if(i - j < 0) continue;
         if(currentLow >= iLow(_Symbol, PERIOD_H1, i - j)) {
            isLow = false;
            break;
         }
      }
      if(isLow) {
         for(int j = 1; j <= InpSwingRight; j++) {
            if(i + j >= Bars(_Symbol, PERIOD_H1)) break;
            if(currentLow >= iLow(_Symbol, PERIOD_H1, i + j)) {
               isLow = false;
               break;
            }
         }
      }
      if(isLow) {
         lowPrice = currentLow;
         lowTime = iTime(_Symbol, PERIOD_H1, i);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Control de drawdown según reglas prop firm                       |
//+------------------------------------------------------------------+
void CheckDrawdownLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Reinicio diario
   MqlDateTime dtNow, dtLast;
   TimeToStruct(TimeCurrent(), dtNow);
   TimeToStruct(lastDayCheck, dtLast);
   if(dtNow.day != dtLast.day) {
      dailyStartEquity = currentEquity;
      lastDayCheck = TimeCurrent();
   }
   
   // Drawdown diario
   double dailyDD = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   if(dailyDD >= InpMaxDailyLoss) {
      Print("❌ DRAWdown DIARIO MÁXIMO ALCANZADO: ", DoubleToString(dailyDD, 2), "%");
      // Cerrar todas las posiciones y detener trading
      CloseAllPositions();
      tradingPaused = true;
      pauseUntil = TimeCurrent() + 86400; // Pausa 24h
      return;
   }
   
   // Drawdown total desde inicio de la fase
   double totalDD = (totalStartEquity - currentEquity) / totalStartEquity * 100.0;
   if(totalDD >= InpMaxTotalLoss) {
      Print("❌ DRAWdown TOTAL MÁXIMO ALCANZADO: ", DoubleToString(totalDD, 2), "% - CHALLENGE FALLADO");
      CloseAllPositions();
      ExpertRemove(); // Terminar el EA (opcional)
   }
}

//+------------------------------------------------------------------+
//| Cerrar todas las posiciones                                      |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Resetear contador de trades diarios                              |
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
//| Actualizar comentario en pantalla                                |
//+------------------------------------------------------------------+
void UpdateComment()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyDD = (dailyStartEquity - currentEquity) / dailyStartEquity * 100.0;
   double totalDD = (totalStartEquity - currentEquity) / totalStartEquity * 100.0;
   
   string status = "ACTIVO";
   if(tradingPaused) status = "PAUSADO";
   if(dailyDD >= InpMaxDailyLoss) status = "DD DIARIO ALCANZADO";
   if(totalDD >= InpMaxTotalLoss) status = "CHALLENGE FALLIDO";
   
   string comment = StringFormat(
      "═══════════════════════════════════════\n" +
      "  HealthBreakout Prop EA\n" +
      "═══════════════════════════════════════\n" +
      "Estado: %s\n" +
      "Trades hoy: %d/%d\n" +
      "Pérdidas consecutivas: %d\n" +
      "DD Diario: %.2f%% / %.1f%%\n" +
      "DD Total: %.2f%% / %.1f%%\n" +
      "───────────────────────────────────────\n" +
      "Balance: %.2f | Equity: %.2f\n" +
      "───────────────────────────────────────\n" +
      "Breakout: %s\n" +
      "Pullback target: %.5f\n" +
      "═══════════════════════════════════════",
      status,
      tradesToday, InpMaxTradesPerDay,
      consecutiveLosses,
      dailyDD, InpMaxDailyLoss,
      totalDD, InpMaxTotalLoss,
      AccountInfoDouble(ACCOUNT_BALANCE),
      currentEquity,
      (breakoutDetected ? "Sí" : "No"),
      pullbackTarget
   );
   
   Comment(comment);
}

//+------------------------------------------------------------------+
//| Registrar resultado de una operación cerrada (llamar desde OnTrade) |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Esta función se llama automáticamente cuando ocurre un evento de trade
   // Podemos usarla para actualizar consecutiveLosses
   // Por simplicidad, se podría hacer en ManageOpenPosition cuando se cierra la posición,
   // pero aquí implementamos una verificación simple.
   
   // No implementado en detalle para no complicar, pero se puede añadir.
   // Lo dejamos como placeholder.
}

//+------------------------------------------------------------------+
//| Expert tick function (alternativa si se necesita procesamiento rápido)|
//+------------------------------------------------------------------+
// Nota: OnTick ya está definido arriba.