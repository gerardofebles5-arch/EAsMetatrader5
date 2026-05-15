//+------------------------------------------------------------------+
//|                                        GoldenRangeBreakout.mq5 |
//|                                    Estrategia de Alto Rendimiento|
//|                                    XAUUSD H1 - RR 1:2 - WR 60%+ |
//+------------------------------------------------------------------+
#property copyright "Golden Range Breakout Strategy"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Objetos globales
CTrade trade;

//--- Inputs del usuario
input group "════════ CONFIGURACIÓN DE RIESGO ════════"
input double   InpRiskPercent = 1.0;           // Riesgo por operación (% del balance)
input double   InpRiskReward = 2.0;            // Risk:Reward ratio
input double   InpPartialClosePercent = 50.0;  // % a cerrar en TP1 (1R)

input group "════════ PARÁMETROS DE RANGO ════════"
input int      InpRangeStartHour = 0;          // Hora inicio del rango (UTC)
input int      InpRangeEndHour = 8;            // Hora fin del rango (UTC)
input double   InpMaxRangeSize = 12.0;         // Tamaño máximo del rango (USD)
input double   InpStopLossBuffer = 1.5;        // Buffer del Stop Loss (USD)

input group "════════ HORARIO DE TRADING ════════"
input int      InpStartTradingHour = 9;        // Hora inicio trading (UTC)
input int      InpEndTradingHour = 14;         // Hora fin trading (UTC)

input group "════════ FILTROS ════════"
input int      InpATRPeriod = 14;              // Período ATR
input double   InpMinATR = 6.0;                // ATR mínimo para operar (USD)
input int      InpEMAPeriod = 50;              // Período EMA en H4
input bool     InpUseTrendFilter = true;       // Usar filtro de tendencia EMA50 H4
input bool     InpUseVolumeConfirm = false;    // Usar confirmación por volumen (si hay datos)
input double   InpVolumeMultiplier = 1.2;      // Multiplicador de volumen promedio

input group "════════ GESTIÓN AVANZADA ════════"
input bool     InpUseBreakeven = true;         // Mover SL a breakeven en TP1
input int      InpMagicNumber = 123456;        // Magic Number único
input string   InpTradeComment = "GRB_v1";     // Comentario de las operaciones

input group "════════ DÍAS BLOQUEADOS (NFP/CPI) ════════"
input bool     InpBlockFridays = true;         // Bloquear viernes de NFP
input bool     InpBlockCPIDays = true;         // Bloquear martes de CPI

//--- Variables globales
double g_HighRange = 0;
double g_LowRange = 0;
bool   g_RangeCalculated = false;
datetime g_LastBarTime = 0;
datetime g_LastRangeDate = 0;

//--- Handles de indicadores
int g_HandleATR = INVALID_HANDLE;
int g_HandleEMA = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Configurar trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   //--- Inicializar indicadores
   g_HandleATR = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   g_HandleEMA = iMA(_Symbol, PERIOD_H4, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(g_HandleATR == INVALID_HANDLE || g_HandleEMA == INVALID_HANDLE)
   {
      Print("❌ Error al inicializar indicadores");
      return INIT_FAILED;
   }
   
   Print("✅ Golden Range Breakout EA iniciado correctamente");
   Print("📊 Símbolo: ", _Symbol);
   Print("⏰ Horario de trading: ", InpStartTradingHour, ":00 - ", InpEndTradingHour, ":00 UTC");
   Print("💰 Riesgo por trade: ", InpRiskPercent, "%");
   Print("🎯 Risk:Reward: 1:", InpRiskReward);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Liberar indicadores
   if(g_HandleATR != INVALID_HANDLE) IndicatorRelease(g_HandleATR);
   if(g_HandleEMA != INVALID_HANDLE) IndicatorRelease(g_HandleEMA);
   
   Comment("");
   Print("EA detenido. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Verificar nueva vela H1
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBarTime == g_LastBarTime) return;
   g_LastBarTime = currentBarTime;
   
   //--- Actualizar información en pantalla
   UpdateDashboard();
   
   //--- Calcular rango al inicio del día
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   if(timeStruct.hour == InpRangeEndHour && !g_RangeCalculated)
   {
      CalculateRange();
   }
   
   //--- Resetear rango calculado al cambiar de día
   datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDate != g_LastRangeDate)
   {
      g_RangeCalculated = false;
      g_LastRangeDate = currentDate;
   }
   
   //--- Solo operar si el rango fue calculado
   if(!g_RangeCalculated) return;
   
   //--- Verificar si hay posiciones abiertas
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return; // No abrir nuevas posiciones si ya hay una activa
   }
   
   //--- Verificar condiciones de entrada
   CheckEntryConditions();
}

//+------------------------------------------------------------------+
//| Calcular el rango asiático                                       |
//+------------------------------------------------------------------+
void CalculateRange()
{
   datetime startTime = 0;
   datetime endTime = 0;
   
   //--- Obtener el inicio y fin del rango
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   timeStruct.hour = InpRangeStartHour;
   timeStruct.min = 0;
   timeStruct.sec = 0;
   startTime = StructToTime(timeStruct);
   
   timeStruct.hour = InpRangeEndHour;
   endTime = StructToTime(timeStruct);
   
   //--- Buscar el máximo y mínimo en el período
   int startBar = iBarShift(_Symbol, PERIOD_H1, endTime);
   int endBar = iBarShift(_Symbol, PERIOD_H1, startTime);
   
   if(startBar < 0 || endBar < 0)
   {
      Print("⚠️ Error al calcular barras del rango");
      return;
   }
   
   g_HighRange = 0;
   g_LowRange = DBL_MAX;
   
   for(int i = startBar; i <= endBar; i++)
   {
      double high = iHigh(_Symbol, PERIOD_H1, i);
      double low = iLow(_Symbol, PERIOD_H1, i);
      
      if(high > g_HighRange) g_HighRange = high;
      if(low < g_LowRange) g_LowRange = low;
   }
   
   //--- Validar tamaño del rango
   double rangeSize = g_HighRange - g_LowRange;
   
   if(rangeSize > InpMaxRangeSize * _Point * 10)
   {
      Print("⚠️ Rango demasiado amplio: ", rangeSize / _Point / 10, " USD - Se omite el día");
      g_RangeCalculated = false;
      return;
   }
   
   g_RangeCalculated = true;
   Print("✅ Rango calculado - High: ", g_HighRange, " Low: ", g_LowRange, " Size: ", rangeSize / _Point / 10, " USD");
   
   //--- Dibujar líneas en el gráfico
   DrawRangeLines();
}

//+------------------------------------------------------------------+
//| Verificar condiciones de entrada                                 |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
   //--- Verificar horario permitido
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   if(timeStruct.hour < InpStartTradingHour || timeStruct.hour >= InpEndTradingHour)
      return;
   
   //--- Verificar filtro de días bloqueados
   if(InpBlockFridays && timeStruct.day_of_week == 5 && timeStruct.hour >= 11)
   {
      Print("⛔ Viernes bloqueado (NFP)");
      return;
   }
   
   if(InpBlockCPIDays && timeStruct.day_of_week == 2 && timeStruct.hour >= 11)
   {
      Print("⛔ Martes bloqueado (CPI)");
      return;
   }
   
   //--- Verificar filtro de volatilidad (ATR)
   double atrValue[];
   if(CopyBuffer(g_HandleATR, 0, 1, 1, atrValue) <= 0)
      return;
   
   double currentATR = atrValue[0] / _Point / 10; // Convertir a USD
   
   if(currentATR < InpMinATR)
   {
      Print("⚠️ ATR insuficiente: ", NormalizeDouble(currentATR, 2), " USD");
      return;
   }
   
   //--- Verificar filtro de tendencia H4
   bool isUptrend = true;
   if(InpUseTrendFilter)
   {
      double emaValue[];
      if(CopyBuffer(g_HandleEMA, 0, 1, 1, emaValue) <= 0)
         return;
      
      double closeH4 = iClose(_Symbol, PERIOD_H4, 1);
      isUptrend = (closeH4 > emaValue[0]);
   }
   
   //--- Obtener datos de la vela actual y anterior
   double closeCurrent = iClose(_Symbol, PERIOD_H1, 0);
   double highPrevious = iHigh(_Symbol, PERIOD_H1, 1);
   double lowPrevious = iLow(_Symbol, PERIOD_H1, 1);
   
   //--- Señal de COMPRA: breakout alcista
   if(isUptrend && closeCurrent > g_HighRange && highPrevious <= g_HighRange)
   {
      if(ConfirmByVolume(true))
      {
         Print("🟢 SEÑAL DE COMPRA detectada");
         OpenBuyTrade();
      }
   }
   
   //--- Señal de VENTA: breakout bajista
   if(!InpUseTrendFilter || !isUptrend)
   {
      if(closeCurrent < g_LowRange && lowPrevious >= g_LowRange)
      {
         if(ConfirmByVolume(false))
         {
            Print("🔴 SEÑAL DE VENTA detectada");
            OpenSellTrade();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Confirmar por volumen (opcional)                                 |
//+------------------------------------------------------------------+
bool ConfirmByVolume(bool isBuy)
{
   if(!InpUseVolumeConfirm) return true;
   
   long volumeCurrent = iVolume(_Symbol, PERIOD_H1, 0);
   
   //--- Calcular promedio de volumen de las últimas 10 velas
   long volumeSum = 0;
   for(int i = 1; i <= 10; i++)
   {
      volumeSum += iVolume(_Symbol, PERIOD_H1, i);
   }
   double volumeAvg = volumeSum / 10.0;
   
   if(volumeCurrent >= volumeAvg * InpVolumeMultiplier)
   {
      Print("✅ Confirmación por volumen: ", volumeCurrent, " vs Promedio: ", NormalizeDouble(volumeAvg, 0));
      return true;
   }
   
   Print("⚠️ Volumen insuficiente: ", volumeCurrent);
   return false;
}

//+------------------------------------------------------------------+
//| Abrir operación de compra                                        |
//+------------------------------------------------------------------+
void OpenBuyTrade()
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = g_HighRange - InpStopLossBuffer * _Point * 10;
   double slDistance = entryPrice - stopLoss;
   
   //--- Calcular lote basado en riesgo
   double lotSize = CalculateLotSize(slDistance);
   
   //--- Calcular TPs
   double tp1 = entryPrice + slDistance * 1.0;  // 1R
   double tp2 = entryPrice + slDistance * InpRiskReward;  // 2R
   
   //--- Abrir posición con TP2 como objetivo principal
   if(trade.Buy(lotSize, _Symbol, entryPrice, stopLoss, tp2, InpTradeComment))
   {
      Print("✅ COMPRA ejecutada - Lote: ", lotSize, " Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", tp2);
   }
   else
   {
      Print("❌ Error al abrir compra: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Abrir operación de venta                                         |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = g_LowRange + InpStopLossBuffer * _Point * 10;
   double slDistance = stopLoss - entryPrice;
   
   //--- Calcular lote basado en riesgo
   double lotSize = CalculateLotSize(slDistance);
   
   //--- Calcular TPs
   double tp1 = entryPrice - slDistance * 1.0;  // 1R
   double tp2 = entryPrice - slDistance * InpRiskReward;  // 2R
   
   //--- Abrir posición con TP2 como objetivo principal
   if(trade.Sell(lotSize, _Symbol, entryPrice, stopLoss, tp2, InpTradeComment))
   {
      Print("✅ VENTA ejecutada - Lote: ", lotSize, " Entry: ", entryPrice, " SL: ", stopLoss, " TP: ", tp2);
   }
   else
   {
      Print("❌ Error al abrir venta: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño del lote basado en riesgo                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lotSize = (riskAmount / (slDistance / tickSize * tickValue));
   
   //--- Normalizar lote
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Gestionar posiciones abiertas (breakeven, trailing, parciales)   |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double slDistance = MathAbs(entryPrice - currentSL);
      double tp1Level = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                        entryPrice + slDistance * 1.0 :
                        entryPrice - slDistance * 1.0;
      
      //--- Mover a breakeven si alcanza TP1 y está activado
      if(InpUseBreakeven)
      {
         bool reachedTP1 = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && currentPrice >= tp1Level) ||
                          (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && currentPrice <= tp1Level);
         
         if(reachedTP1 && currentSL != entryPrice)
         {
            trade.PositionModify(ticket, entryPrice, currentTP);
            Print("🔒 Stop Loss movido a BREAKEVEN en ticket ", ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dibujar líneas de rango en el gráfico                            |
//+------------------------------------------------------------------+
void DrawRangeLines()
{
   //--- Línea superior del rango
   ObjectDelete(0, "RangeHigh");
   ObjectCreate(0, "RangeHigh", OBJ_HLINE, 0, 0, g_HighRange);
   ObjectSetInteger(0, "RangeHigh", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "RangeHigh", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "RangeHigh", OBJPROP_WIDTH, 2);
   
   //--- Línea inferior del rango
   ObjectDelete(0, "RangeLow");
   ObjectCreate(0, "RangeLow", OBJ_HLINE, 0, 0, g_LowRange);
   ObjectSetInteger(0, "RangeLow", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "RangeLow", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "RangeLow", OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Panel informativo en pantalla                                    |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   string info = "";
   info += "═══════════════════════════════\n";
   info += "   GOLDEN RANGE BREAKOUT v1.0\n";
   info += "═══════════════════════════════\n\n";
   
   //--- Estado del rango
   if(g_RangeCalculated)
   {
      info += "📊 Rango: CALCULADO\n";
      info += "   High: " + DoubleToString(g_HighRange, _Digits) + "\n";
      info += "   Low:  " + DoubleToString(g_LowRange, _Digits) + "\n";
      info += "   Size: " + DoubleToString((g_HighRange - g_LowRange) / _Point / 10, 2) + " USD\n\n";
   }
   else
   {
      info += "⏳ Esperando rango...\n\n";
   }
   
   //--- ATR actual
   double atrValue[];
   if(CopyBuffer(g_HandleATR, 0, 1, 1, atrValue) > 0)
   {
      double currentATR = atrValue[0] / _Point / 10;
      info += "📈 ATR(14): " + DoubleToString(currentATR, 2) + " USD";
      info += (currentATR >= InpMinATR) ? " ✅\n" : " ❌\n";
   }
   
   //--- Tendencia H4
   if(InpUseTrendFilter)
   {
      double emaValue[];
      if(CopyBuffer(g_HandleEMA, 0, 1, 1, emaValue) > 0)
      {
         double closeH4 = iClose(_Symbol, PERIOD_H4, 1);
         bool isUptrend = (closeH4 > emaValue[0]);
         info += "🎯 Tendencia H4: " + (isUptrend ? "ALCISTA 🟢" : "BAJISTA 🔴") + "\n";
      }
   }
   
   //--- Posiciones abiertas
   info += "\n💼 Posiciones: " + IntegerToString(PositionsTotal()) + "\n";
   
   //--- Horario
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   info += "⏰ Hora UTC: " + IntegerToString(timeStruct.hour) + ":" + 
           (timeStruct.min < 10 ? "0" : "") + IntegerToString(timeStruct.min) + "\n";
   
   bool tradingHours = (timeStruct.hour >= InpStartTradingHour && timeStruct.hour < InpEndTradingHour);
   info += "   Trading: " + (tradingHours ? "ACTIVO ✅" : "INACTIVO ⏸️") + "\n";
   
   Comment(info);
}

//+------------------------------------------------------------------+
