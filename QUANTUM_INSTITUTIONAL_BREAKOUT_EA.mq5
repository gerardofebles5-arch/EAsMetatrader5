//+------------------------------------------------------------------+
//|                    QUANTUM_INSTITUTIONAL_BREAKOUT_EA.mq5         |
//|              Sistema Híbrido: Mean Reversion + Breakout         |
//|              Asian Range + London/NY Breakout + 14 Mejoras      |
//+------------------------------------------------------------------+
#property copyright "Quantum Institutional Breakout EA"
#property version   "5.00"
#property description "Estrategia institucional de expansión de volatilidad"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN BASE
// ═══════════════════════════════════════════════════════════════════
input group "═══ CONFIGURACIÓN BASE ═══"
input double InpRiskPercent = 0.20;          // Riesgo por trade
input int    InpStopLossPips = 25;           // Stop Loss pips
input int    InpTakeProfitPips = 50;         // Take Profit pips
input int    InpMagicNumber = 505050;        // Magic number

input group "═══ PROTECCIONES ═══"
input int    InpMaxTradesPerDay = 3;         // Max trades/día
input int    InpMaxConsecutiveLosses = 3;    // Pausar después de N pérdidas
input double InpMaxDailyLossPercent = 2.0;   // Pérdida máxima diaria %
input double InpMaxDrawdownPercent = 15.0;   // Drawdown máximo %

// ═══════════════════════════════════════════════════════════════════
// ESTRATEGIA INSTITUCIONAL - ASIAN RANGE BREAKOUT
// ═══════════════════════════════════════════════════════════════════
input group "═══ ASIAN RANGE DETECTION ═══"
input bool   InpUseAsianRange = true;        // Activar detección rango asiático
input int    InpAsianStartHour = 0;          // Inicio sesión Asia (GMT)
input int    InpAsianEndHour = 7;            // Fin sesión Asia (GMT)
input bool   InpDrawAsianBox = true;         // Dibujar rectángulo en gráfico
input color  InpAsianBoxColor = clrDarkGray; // Color del rectángulo

input group "═══ LONDON BREAKOUT ═══"
input bool   InpUseLondonBreakout = true;    // Activar ruptura Londres
input int    InpLondonStartHour = 7;         // Inicio ventana Londres (GMT)
input int    InpLondonEndHour = 10;          // Fin ventana Londres (GMT)
input double InpMinMomentumPips = 15;        // Pips mínimos de momentum
input double InpMinVolumeRatio = 1.3;        // Volumen mínimo vs promedio

input group "═══ NEW YORK BREAKOUT ═══"
input bool   InpUseNYBreakout = true;        // Activar ruptura NY
input int    InpNYStartHour = 13;            // Inicio ventana NY (GMT)
input int    InpNYEndHour = 16;              // Fin ventana NY (GMT)
input bool   InpUseNYContinuation = true;    // Continuidad de Londres

input group "═══ PIVOT BIAS FILTER ═══"
input bool   InpUsePivotBias = true;         // Usar pivote como sesgo
input bool   InpStrictPivotBias = false;     // Solo operar en dirección del sesgo

input group "═══ VOLATILITY EXPANSION ═══"
input bool   InpUseVolatilityFilter = true;  // Filtro de expansión de volatilidad
input double InpMinATRExpansion = 1.2;       // ATR mínimo vs promedio
input int    InpConsolidationBars = 20;      // Barras para detectar consolidación

input group "═══ REJECTION SETUPS ═══"
input bool   InpUseRejectionFilter = true;   // Filtro anti-trampa
input double InpMaxWickRatio = 0.6;          // Ratio máximo mecha/cuerpo
input int    InpRejectionLookback = 3;       // Barras para detectar rechazo

// ═══════════════════════════════════════════════════════════════════
// MEJORAS DEL QUANTUM MASTER (Simplificadas)
// ═══════════════════════════════════════════════════════════════════
input group "═══ FILTROS INTELIGENTES ═══"
input bool   InpUseMarketRegimeFilter = true;  // Filtro de régimen
input bool   InpUseOrderFlowFilter = true;     // Filtro de order flow
input bool   InpUseConfluenceScoring = true;   // Scoring por confluencia
input int    InpMinConfluenceFactors = 5;      // Factores mínimos (de 12)

input group "═══ GESTIÓN AVANZADA ═══"
input bool   InpUseDynamicSL = true;           // Stop Loss dinámico
input bool   InpUsePartialProfits = true;      // Toma parcial de ganancias
input bool   InpUseSmartExit = true;           // Salidas inteligentes

input group "═══ VISUAL PANEL ═══"
input bool   InpShowPanel = true;              // Mostrar panel informativo
input int    InpPanelX = 20;                   // Posición X del panel
input int    InpPanelY = 50;                   // Posición Y del panel
input color  InpPanelColor = clrDarkSlateGray; // Color del panel

// ═══════════════════════════════════════════════════════════════════
// ESTRUCTURAS DE DATOS
// ═══════════════════════════════════════════════════════════════════

// Rango Asiático
struct SAsianRange {
   double high;
   double low;
   double mid;
   datetime startTime;
   datetime endTime;
   bool isValid;
   bool highBroken;
   bool lowBroken;
};

// Estructura de Londres
struct SLondonSession {
   double high;
   double low;
   double open;
   double close;
   datetime startTime;
   datetime endTime;
   bool isBullish;
   bool isValid;
};

// Estadísticas de trading
struct STradeStats {
   int totalTrades;
   int wins;
   int losses;
   double winRate;
   double totalProfit;
   int tradesThisDay;
};

// ═══════════════════════════════════════════════════════════════════
// VARIABLES GLOBALES
// ═══════════════════════════════════════════════════════════════════
CTrade trade;
SAsianRange asianRange;
SLondonSession londonSession;
STradeStats stats;

datetime lastBarTime = 0;
datetime lastTradeDate = 0;
int consecutiveLosses = 0;
bool isPaused = false;
double dailyStartBalance = 0;
double peakBalance = 0;

// Pivotes
double dailyPivot = 0;
double R1 = 0, S1 = 0;

// VWAP
double currentVWAP = 0;

// Panel
string panelPrefix = "QIB_Panel_";

// Partial profits
bool tp1Taken = false;
bool tp2Taken = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   // Inicializar estructuras
   asianRange.isValid = false;
   londonSession.isValid = false;
   
   stats.totalTrades = 0;
   stats.wins = 0;
   stats.losses = 0;
   stats.winRate = 0;
   stats.totalProfit = 0;
   stats.tradesThisDay = 0;
   
   // Crear panel visual
   if(InpShowPanel)
      CreateVisualPanel();
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  QUANTUM INSTITUTIONAL BREAKOUT EA v5.0                   ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Estrategia: Asian Range + London/NY Breakout            ║");
   Print("║  Asian Range: ", InpUseAsianRange ? "ON" : "OFF", " | London: ", InpUseLondonBreakout ? "ON" : "OFF", " | NY: ", InpUseNYBreakout ? "ON" : "OFF", "        ║");
   Print("║  Pivot Bias: ", InpUsePivotBias ? "ON" : "OFF", " | Volatility: ", InpUseVolatilityFilter ? "ON" : "OFF", "              ║");
   Print("║  Confluence: ", InpUseConfluenceScoring ? "ON" : "OFF", " (Min: ", InpMinConfluenceFactors, "/12)                ║");
   Print("║  Visual Panel: ", InpShowPanel ? "ON" : "OFF", "                                      ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Eliminar objetos gráficos
   ObjectsDeleteAll(0, panelPrefix);
   ObjectsDeleteAll(0, "AsianBox_");
   
   Print("═══════════════════════════════════════════════════════════");
   Print("  ESTADÍSTICAS FINALES");
   Print("  Total Trades: ", stats.totalTrades);
   Print("  Win Rate: ", DoubleToString(stats.winRate, 1), "%");
   Print("  Profit: $", DoubleToString(stats.totalProfit, 2));
   Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   UpdateDailyControls();
   UpdatePerformanceStats();
   
   // Actualizar componentes
   UpdateDailyPivots();
   UpdateVWAP();
   DetectAsianRange();
   DetectLondonSession();
   
   // Actualizar panel visual
   if(InpShowPanel)
      UpdateVisualPanel();
   
   // Gestionar posiciones abiertas
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   // Filtros de protección
   if(!PassProtectionFilters()) return;
   
   // Filtros inteligentes
   if(InpUseMarketRegimeFilter && !PassMarketRegimeFilter()) return;
   
   // ═══════════════════════════════════════════════════════════════
   // ESTRATEGIA 1: LONDON BREAKOUT (Prioridad Alta)
   // ═══════════════════════════════════════════════════════════════
   if(InpUseLondonBreakout && InpUseAsianRange)
   {
      int londonSignal = AnalyzeLondonBreakout();
      if(londonSignal != 0)
      {
         if(PassAllFilters(londonSignal))
         {
            if(londonSignal == 1)
               ExecuteBuySignal("LONDON_BREAKOUT");
            else
               ExecuteSellSignal("LONDON_BREAKOUT");
            return;
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // ESTRATEGIA 2: NY CONTINUATION (Prioridad Media)
   // ═══════════════════════════════════════════════════════════════
   if(InpUseNYBreakout && InpUseNYContinuation)
   {
      int nySignal = AnalyzeNYContinuation();
      if(nySignal != 0)
      {
         if(PassAllFilters(nySignal))
         {
            if(nySignal == 1)
               ExecuteBuySignal("NY_CONTINUATION");
            else
               ExecuteSellSignal("NY_CONTINUATION");
            return;
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // ESTRATEGIA 3: MEAN REVERSION (Fallback)
   // ═══════════════════════════════════════════════════════════════
   int mrSignal = AnalyzeMeanReversion();
   if(mrSignal != 0)
   {
      if(PassAllFilters(mrSignal))
      {
         if(mrSignal == 1)
            ExecuteBuySignal("MEAN_REVERSION");
         else
            ExecuteSellSignal("MEAN_REVERSION");
      }
   }
}


//+------------------------------------------------------------------+
// FUNCIONES DE CONTROL DIARIO
//+------------------------------------------------------------------+
void UpdateDailyControls()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day));
   
   if(lastTradeDate != today)
   {
      stats.tradesThisDay = 0;
      lastTradeDate = today;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      // Resetear flags
      asianRange.isValid = false;
      asianRange.highBroken = false;
      asianRange.lowBroken = false;
      londonSession.isValid = false;
      
      if(isPaused)
      {
         isPaused = false;
         consecutiveLosses = 0;
         Print("► Nuevo día - Sistema reactivado");
      }
   }
}

//+------------------------------------------------------------------+
void UpdatePerformanceStats()
{
   static ulong lastProcessedTicket = 0;
   
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))
   {
      int totalDeals = HistoryDealsTotal();
      if(totalDeals > 0)
      {
         ulong ticket = HistoryDealGetTicket(totalDeals - 1);
         if(ticket != lastProcessedTicket && ticket > 0)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            
            if(profit > 0)
            {
               stats.wins++;
               consecutiveLosses = 0;
               if(isPaused) isPaused = false;
            }
            else if(profit < 0)
            {
               stats.losses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ PAUSADO - ", consecutiveLosses, " pérdidas consecutivas");
               }
            }
            
            stats.totalTrades = stats.wins + stats.losses;
            if(stats.totalTrades > 0)
               stats.winRate = (double)stats.wins / stats.totalTrades * 100.0;
            stats.totalProfit += profit;
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            if(balance > peakBalance) peakBalance = balance;
            
            lastProcessedTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool PassProtectionFilters()
{
   if(isPaused) return false;
   if(stats.tradesThisDay >= InpMaxTradesPerDay) return false;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   
   if(dailyLoss > InpMaxDailyLossPercent)
   {
      Print("⊗ Pérdida diaria: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdownPercent)
   {
      Print("⊗ Drawdown: ", DoubleToString(dd, 2), "%");
      return false;
   }
   
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > 50) return false;
   
   return true;
}

//+------------------------------------------------------------------+
// DETECCIÓN DE RANGO ASIÁTICO
//+------------------------------------------------------------------+
void DetectAsianRange()
{
   if(!InpUseAsianRange) return;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Durante sesión asiática: actualizar high/low
   if(hour >= InpAsianStartHour && hour < InpAsianEndHour)
   {
      if(!asianRange.isValid)
      {
         asianRange.startTime = TimeCurrent();
         asianRange.high = iHigh(_Symbol, PERIOD_M5, 1);
         asianRange.low = iLow(_Symbol, PERIOD_M5, 1);
         asianRange.isValid = true;
         asianRange.highBroken = false;
         asianRange.lowBroken = false;
      }
      else
      {
         double high = iHigh(_Symbol, PERIOD_M5, 1);
         double low = iLow(_Symbol, PERIOD_M5, 1);
         
         if(high > asianRange.high) asianRange.high = high;
         if(low < asianRange.low) asianRange.low = low;
      }
   }
   
   // Al finalizar sesión asiática: calcular mid y dibujar
   if(hour == InpAsianEndHour && dt.min < 5 && asianRange.isValid)
   {
      asianRange.endTime = TimeCurrent();
      asianRange.mid = (asianRange.high + asianRange.low) / 2;
      
      if(InpDrawAsianBox)
         DrawAsianRangeBox();
      
      Print("═══════════════════════════════════════════════════════════");
      Print("  RANGO ASIÁTICO DETECTADO");
      Print("  HIGH: ", asianRange.high);
      Print("  LOW: ", asianRange.low);
      Print("  MID: ", asianRange.mid);
      Print("  Rango: ", DoubleToString((asianRange.high - asianRange.low) / (10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT)), 1), " pips");
      Print("═══════════════════════════════════════════════════════════");
   }
}

//+------------------------------------------------------------------+
void DrawAsianRangeBox()
{
   string objName = "AsianBox_" + TimeToString(asianRange.startTime);
   
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                   asianRange.startTime, asianRange.high,
                   asianRange.endTime + 3600 * 12, asianRange.low);
      
      ObjectSetInteger(0, objName, OBJPROP_COLOR, InpAsianBoxColor);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   }
}

//+------------------------------------------------------------------+
void DetectLondonSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Inicio de Londres
   if(hour == InpLondonStartHour && dt.min < 5)
   {
      londonSession.startTime = TimeCurrent();
      londonSession.open = iClose(_Symbol, PERIOD_M5, 1);
      londonSession.high = londonSession.open;
      londonSession.low = londonSession.open;
      londonSession.isValid = true;
   }
   
   // Durante Londres: actualizar high/low
   if(hour >= InpLondonStartHour && hour < InpLondonEndHour && londonSession.isValid)
   {
      double high = iHigh(_Symbol, PERIOD_M5, 1);
      double low = iLow(_Symbol, PERIOD_M5, 1);
      
      if(high > londonSession.high) londonSession.high = high;
      if(low < londonSession.low) londonSession.low = low;
   }
   
   // Cierre de Londres
   if(hour == InpLondonEndHour && dt.min < 5 && londonSession.isValid)
   {
      londonSession.endTime = TimeCurrent();
      londonSession.close = iClose(_Symbol, PERIOD_M5, 1);
      londonSession.isBullish = (londonSession.close > londonSession.open);
      
      Print("► Londres cerró | ", londonSession.isBullish ? "Alcista" : "Bajista",
            " | Rango: ", DoubleToString((londonSession.high - londonSession.low) / (10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT)), 1), " pips");
   }
}

//+------------------------------------------------------------------+
// ANÁLISIS DE LONDON BREAKOUT
//+------------------------------------------------------------------+
int AnalyzeLondonBreakout()
{
   if(!asianRange.isValid) return 0;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Solo durante ventana de Londres
   if(hour < InpLondonStartHour || hour >= InpLondonEndHour) return 0;
   
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minMomentum = InpMinMomentumPips * 10 * point;
   
   // RUPTURA ALCISTA del HIGH asiático
   if(!asianRange.highBroken && high1 > asianRange.high)
   {
      // Verificar momentum
      double bodySize = MathAbs(close1 - open1);
      if(bodySize < minMomentum) return 0;
      
      // Verificar vela alcista
      if(close1 <= open1) return 0;
      
      // Verificar volumen
      if(!CheckVolumeExpansion()) return 0;
      
      // Verificar no hay rechazo
      if(InpUseRejectionFilter && DetectRejection(1)) return 0;
      
      asianRange.highBroken = true;
      Print("🔥 LONDON BREAKOUT ALCISTA | Rompió HIGH Asia: ", asianRange.high);
      return 1;
   }
   
   // RUPTURA BAJISTA del LOW asiático
   if(!asianRange.lowBroken && low1 < asianRange.low)
   {
      double bodySize = MathAbs(close1 - open1);
      if(bodySize < minMomentum) return 0;
      
      if(close1 >= open1) return 0;
      
      if(!CheckVolumeExpansion()) return 0;
      
      if(InpUseRejectionFilter && DetectRejection(-1)) return 0;
      
      asianRange.lowBroken = true;
      Print("🔥 LONDON BREAKOUT BAJISTA | Rompió LOW Asia: ", asianRange.low);
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
// ANÁLISIS DE NY CONTINUATION
//+------------------------------------------------------------------+
int AnalyzeNYContinuation()
{
   if(!londonSession.isValid) return 0;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Solo durante ventana de NY
   if(hour < InpNYStartHour || hour >= InpNYEndHour) return 0;
   
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   
   // CONTINUACIÓN ALCISTA: Rompe HIGH de Londres
   if(high1 > londonSession.high && londonSession.isBullish)
   {
      if(!CheckVolumeExpansion()) return 0;
      if(InpUseRejectionFilter && DetectRejection(1)) return 0;
      
      Print("🚀 NY CONTINUATION ALCISTA | Rompió HIGH Londres: ", londonSession.high);
      return 1;
   }
   
   // CONTINUACIÓN BAJISTA: Rompe LOW de Londres
   if(low1 < londonSession.low && !londonSession.isBullish)
   {
      if(!CheckVolumeExpansion()) return 0;
      if(InpUseRejectionFilter && DetectRejection(-1)) return 0;
      
      Print("🚀 NY CONTINUATION BAJISTA | Rompió LOW Londres: ", londonSession.low);
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
// MEAN REVERSION (Fallback)
//+------------------------------------------------------------------+
int AnalyzeMeanReversion()
{
   double sma = CalculateSMA(20, PERIOD_M5);
   double stdDev = CalculateStdDev(20, sma, PERIOD_M5);
   double upperBand = sma + (2.0 * stdDev);
   double lowerBand = sma - (2.0 * stdDev);
   
   double rsi = CalculateRSI(14, PERIOD_M5);
   
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   
   // COMPRA
   if(rsi < 30 && low1 <= lowerBand * 1.001 && close1 > open1)
   {
      return 1;
   }
   
   // VENTA
   if(rsi > 70 && high1 >= upperBand * 0.999 && close1 < open1)
   {
      return -1;
   }
   
   return 0;
}


//+------------------------------------------------------------------+
// FILTROS AVANZADOS
//+------------------------------------------------------------------+
bool PassAllFilters(int direction)
{
   // Filtro de sesgo de pivote
   if(InpUsePivotBias && !PassPivotBiasFilter(direction)) return false;
   
   // Filtro de expansión de volatilidad
   if(InpUseVolatilityFilter && !PassVolatilityExpansionFilter()) return false;
   
   // Filtro de order flow
   if(InpUseOrderFlowFilter && !PassOrderFlowFilter(direction)) return false;
   
   // Filtro de confluencia
   if(InpUseConfluenceScoring && !PassConfluenceFilter(direction)) return false;
   
   return true;
}

//+------------------------------------------------------------------+
bool PassPivotBiasFilter(int direction)
{
   if(!InpUsePivotBias) return true;
   
   double price = iClose(_Symbol, PERIOD_M5, 1);
   
   // Sesgo alcista: precio > pivote
   bool bullishBias = (price > dailyPivot);
   
   if(InpStrictPivotBias)
   {
      if(direction == 1 && !bullishBias)
      {
         Print("⊗ PIVOT BIAS: Rechazado compra (precio < pivote)");
         return false;
      }
      if(direction == -1 && bullishBias)
      {
         Print("⊗ PIVOT BIAS: Rechazado venta (precio > pivote)");
         return false;
      }
   }
   
   Print("✓ PIVOT BIAS: ", bullishBias ? "Alcista" : "Bajista", " | Pivote: ", dailyPivot);
   return true;
}

//+------------------------------------------------------------------+
bool PassVolatilityExpansionFilter()
{
   if(!InpUseVolatilityFilter) return true;
   
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   
   if(avgATR == 0) return false;
   
   double expansion = atr / avgATR;
   
   if(expansion < InpMinATRExpansion)
   {
      Print("⊗ VOLATILITY: Expansión insuficiente (", DoubleToString(expansion, 2), "x)");
      return false;
   }
   
   // Verificar consolidación previa
   if(!WasConsolidating())
   {
      Print("⊗ VOLATILITY: No hubo consolidación previa");
      return false;
   }
   
   Print("✓ VOLATILITY: Expansión OK (", DoubleToString(expansion, 2), "x)");
   return true;
}

//+------------------------------------------------------------------+
bool WasConsolidating()
{
   double highestHigh = iHigh(_Symbol, PERIOD_M5, 1);
   double lowestLow = iLow(_Symbol, PERIOD_M5, 1);
   
   for(int i = 2; i <= InpConsolidationBars; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(h > highestHigh) highestHigh = h;
      if(l < lowestLow) lowestLow = l;
   }
   
   double range = highestHigh - lowestLow;
   double atr = CalculateATR(14, PERIOD_M5);
   
   // Consolidación si el rango es menor a 1.5x ATR
   return (range < atr * 1.5);
}

//+------------------------------------------------------------------+
bool CheckVolumeExpansion()
{
   long vol1 = iVolume(_Symbol, PERIOD_M5, 1);
   long avgVol = 0;
   
   for(int i = 2; i <= 11; i++)
      avgVol += iVolume(_Symbol, PERIOD_M5, i);
   avgVol /= 10;
   
   if(avgVol == 0) return false;
   
   double volRatio = (double)vol1 / avgVol;
   
   if(volRatio < InpMinVolumeRatio)
   {
      Print("⊗ VOLUME: Insuficiente (", DoubleToString(volRatio, 2), "x)");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool DetectRejection(int direction)
{
   if(!InpUseRejectionFilter) return false;
   
   for(int i = 1; i <= InpRejectionLookback; i++)
   {
      double open = iOpen(_Symbol, PERIOD_M5, i);
      double close = iClose(_Symbol, PERIOD_M5, i);
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      
      double body = MathAbs(close - open);
      double range = high - low;
      
      if(range == 0) continue;
      
      // Rechazo alcista: mecha inferior larga
      if(direction == 1)
      {
         double lowerWick = MathMin(open, close) - low;
         if(body > 0 && lowerWick / body > InpMaxWickRatio)
         {
            Print("⊗ REJECTION: Detectado rechazo alcista en barra ", i);
            return true;
         }
      }
      
      // Rechazo bajista: mecha superior larga
      if(direction == -1)
      {
         double upperWick = high - MathMax(open, close);
         if(body > 0 && upperWick / body > InpMaxWickRatio)
         {
            Print("⊗ REJECTION: Detectado rechazo bajista en barra ", i);
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
bool PassMarketRegimeFilter()
{
   double adx = CalculateADX(14);
   
   if(adx < 15.0)
   {
      Print("⊗ REGIME: ADX bajo (", DoubleToString(adx, 1), ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassOrderFlowFilter(int direction)
{
   if(!InpUseOrderFlowFilter) return true;
   
   double imbalance = CalculateOrderFlowImbalance(10);
   
   if(direction == 1 && imbalance < 1.2)
   {
      Print("⊗ ORDER FLOW: Compra rechazada (", DoubleToString(imbalance, 2), ")");
      return false;
   }
   
   if(direction == -1 && imbalance > 0.83)
   {
      Print("⊗ ORDER FLOW: Venta rechazada (", DoubleToString(imbalance, 2), ")");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
double CalculateOrderFlowImbalance(int bars)
{
   double buyPressure = 0, sellPressure = 0;
   
   for(int i = 1; i <= bars; i++)
   {
      double open = iOpen(_Symbol, PERIOD_M5, i);
      double close = iClose(_Symbol, PERIOD_M5, i);
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      long volume = iVolume(_Symbol, PERIOD_M5, i);
      
      double range = high - low;
      if(range == 0) continue;
      
      double closePosition = (close - low) / range;
      
      if(close > open)
      {
         buyPressure += volume * closePosition;
         sellPressure += volume * (1 - closePosition);
      }
      else
      {
         sellPressure += volume * (1 - closePosition);
         buyPressure += volume * closePosition;
      }
   }
   
   if(sellPressure == 0) return 999.0;
   return buyPressure / sellPressure;
}

//+------------------------------------------------------------------+
bool PassConfluenceFilter(int direction)
{
   if(!InpUseConfluenceScoring) return true;
   
   int confluence = 0;
   
   // Factor 1: Rango asiático válido
   if(asianRange.isValid) confluence++;
   
   // Factor 2: Sesión activa (Londres o NY)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if((dt.hour >= 7 && dt.hour < 10) || (dt.hour >= 13 && dt.hour < 16))
      confluence++;
   
   // Factor 3: Expansión de volatilidad
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   if(avgATR > 0 && atr / avgATR > 1.2) confluence++;
   
   // Factor 4: Sesgo de pivote
   double price = iClose(_Symbol, PERIOD_M5, 1);
   if((direction == 1 && price > dailyPivot) || (direction == -1 && price < dailyPivot))
      confluence++;
   
   // Factor 5: VWAP alignment
   if(currentVWAP > 0)
   {
      double distance = MathAbs(price - currentVWAP) / currentVWAP;
      if(distance < 0.002) confluence++;
   }
   
   // Factor 6: Order flow
   double imbalance = CalculateOrderFlowImbalance(10);
   if((direction == 1 && imbalance > 1.3) || (direction == -1 && imbalance < 0.77))
      confluence++;
   
   // Factor 7: RSI extremo
   double rsi = CalculateRSI(14, PERIOD_M5);
   if((direction == 1 && rsi < 35) || (direction == -1 && rsi > 65))
      confluence++;
   
   // Factor 8: Volumen alto
   if(CheckVolumeExpansion()) confluence++;
   
   // Factor 9: No hay rechazo
   if(!DetectRejection(direction)) confluence++;
   
   // Factor 10: ADX fuerte
   double adx = CalculateADX(14);
   if(adx > 20) confluence++;
   
   // Factor 11: Londres alcista/bajista
   if(londonSession.isValid)
   {
      if((direction == 1 && londonSession.isBullish) || 
         (direction == -1 && !londonSession.isBullish))
         confluence++;
   }
   
   // Factor 12: Consolidación previa
   if(WasConsolidating()) confluence++;
   
   if(confluence < InpMinConfluenceFactors)
   {
      Print("⊗ CONFLUENCIA: Insuficiente (", confluence, "/12)");
      return false;
   }
   
   Print("✅ CONFLUENCIA: ", confluence, "/12 factores ⭐");
   return true;
}

//+------------------------------------------------------------------+
// EJECUCIÓN DE TRADES
//+------------------------------------------------------------------+
void ExecuteBuySignal(string signalType)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slPips = InpUseDynamicSL ? CalculateDynamicSL() : InpStopLossPips;
   double sl = ask - slPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   string comment = "QIB_" + signalType;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, comment))
   {
      stats.tradesThisDay++;
      tp1Taken = false;
      tp2Taken = false;
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA | ", signalType, "                              ║");
      Print("║  Lote: ", lots, " | SL: ", DoubleToString(slPips, 1), " | TP: ", InpTakeProfitPips, "          ║");
      Print("║  Trade ", stats.tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal(string signalType)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slPips = InpUseDynamicSL ? CalculateDynamicSL() : InpStopLossPips;
   double sl = bid + slPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   string comment = "QIB_" + signalType;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, comment))
   {
      stats.tradesThisDay++;
      tp1Taken = false;
      tp2Taken = false;
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA | ", signalType, "                               ║");
      Print("║  Lote: ", lots, " | SL: ", DoubleToString(slPips, 1), " | TP: ", InpTakeProfitPips, "          ║");
      Print("║  Trade ", stats.tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = riskAmount / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
double CalculateDynamicSL()
{
   double atr = CalculateATR(14, PERIOD_M5);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slPips = (atr * 2.0) / (10 * point);
   
   if(slPips < 15) slPips = 15;
   if(slPips > 45) slPips = 45;
   
   return slPips;
}


//+------------------------------------------------------------------+
// GESTIÓN DE POSICIONES
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      // Toma parcial de ganancias
      if(InpUsePartialProfits)
         ManagePartialProfits(ticket, isBuy, openPrice, currentPrice, profitPips);
      
      // Salidas inteligentes
      if(InpUseSmartExit)
         ApplySmartExit(ticket, isBuy, openTime, profitPips);
      
      // Trailing stop básico
      if(profitPips > 20)
      {
         double breakeven = openPrice + (isBuy ? 5 : -5) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
            trade.PositionModify(ticket, breakeven, currentTP);
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
            trade.PositionModify(ticket, breakeven, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
void ManagePartialProfits(ulong ticket, bool isBuy, double openPrice, 
                          double currentPrice, double profitPips)
{
   double lots = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lots < minLot * 2) return;
   
   // TP1: 50% en 50% del TP
   if(profitPips >= InpTakeProfitPips * 0.5 && !tp1Taken)
   {
      double closeVolume = MathFloor((lots * 0.5) / lotStep) * lotStep;
      if(closeVolume >= minLot)
      {
         if(trade.PositionClosePartial(ticket, closeVolume))
         {
            tp1Taken = true;
            Print("💰 TP1: Cerrado 50% en ", DoubleToString(profitPips, 1), " pips");
         }
      }
   }
   
   // TP2: 30% en 100% del TP
   if(profitPips >= InpTakeProfitPips && !tp2Taken)
   {
      double remainingLots = PositionGetDouble(POSITION_VOLUME);
      double closeVolume = MathFloor((remainingLots * 0.6) / lotStep) * lotStep;
      if(closeVolume >= minLot)
      {
         if(trade.PositionClosePartial(ticket, closeVolume))
         {
            tp2Taken = true;
            Print("💰 TP2: Cerrado 30% en ", DoubleToString(profitPips, 1), " pips");
         }
      }
   }
}

//+------------------------------------------------------------------+
void ApplySmartExit(ulong ticket, bool isBuy, datetime openTime, double profitPips)
{
   // Salida 1: Viernes 15:00 GMT
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= 15)
   {
      Print("📅 SMART EXIT: Viernes 15:00 GMT - Cerrando");
      trade.PositionClose(ticket);
      return;
   }
   
   // Salida 2: Tiempo sin alcanzar 50% TP
   int hoursOpen = (int)((TimeCurrent() - openTime) / 3600);
   if(hoursOpen >= 2 && profitPips < InpTakeProfitPips * 0.5)
   {
      Print("⏰ SMART EXIT: 2 horas sin alcanzar 50% TP");
      trade.PositionClose(ticket);
      return;
   }
}

//+------------------------------------------------------------------+
// FUNCIONES AUXILIARES
//+------------------------------------------------------------------+
void UpdateDailyPivots()
{
   double highD1 = iHigh(_Symbol, PERIOD_D1, 1);
   double lowD1 = iLow(_Symbol, PERIOD_D1, 1);
   double closeD1 = iClose(_Symbol, PERIOD_D1, 1);
   
   dailyPivot = (highD1 + lowD1 + closeD1) / 3;
   R1 = (2 * dailyPivot) - lowD1;
   S1 = (2 * dailyPivot) - highD1;
}

//+------------------------------------------------------------------+
void UpdateVWAP()
{
   double sumPV = 0;
   double sumV = 0;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime todayStart = StringToTime(IntegerToString(dt.year) + "." + 
                                       IntegerToString(dt.mon) + "." + 
                                       IntegerToString(dt.day));
   
   int bars = Bars(_Symbol, PERIOD_M5, todayStart, TimeCurrent());
   
   for(int i = 1; i <= MathMin(bars, 288); i++)
   {
      double typical = (iHigh(_Symbol, PERIOD_M5, i) + iLow(_Symbol, PERIOD_M5, i) + iClose(_Symbol, PERIOD_M5, i)) / 3;
      long volume = iVolume(_Symbol, PERIOD_M5, i);
      
      sumPV += typical * volume;
      sumV += volume;
   }
   
   if(sumV > 0)
      currentVWAP = sumPV / sumV;
}

//+------------------------------------------------------------------+
double CalculateSMA(int period, ENUM_TIMEFRAMES tf)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, tf, i);
   return sum / period;
}

//+------------------------------------------------------------------+
double CalculateStdDev(int period, double sma, ENUM_TIMEFRAMES tf)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
   {
      double diff = iClose(_Symbol, tf, i) - sma;
      sum += diff * diff;
   }
   return MathSqrt(sum / period);
}

//+------------------------------------------------------------------+
double CalculateRSI(int period, ENUM_TIMEFRAMES tf)
{
   double gains = 0;
   double losses = 0;
   
   for(int i = 1; i <= period; i++)
   {
      double change = iClose(_Symbol, tf, i) - iClose(_Symbol, tf, i + 1);
      if(change > 0)
         gains += change;
      else
         losses += MathAbs(change);
   }
   
   double avgGain = gains / period;
   double avgLoss = losses / period;
   
   if(avgLoss == 0) return 100;
   
   double rs = avgGain / avgLoss;
   return 100 - (100 / (1 + rs));
}

//+------------------------------------------------------------------+
double CalculateATR(int period, ENUM_TIMEFRAMES tf)
{
   double atr = 0;
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(_Symbol, tf, i);
      double low = iLow(_Symbol, tf, i);
      double prevClose = iClose(_Symbol, tf, i + 1);
      double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      atr += tr;
   }
   return atr / period;
}

//+------------------------------------------------------------------+
double CalculateADX(int period)
{
   double plusDM = 0, minusDM = 0, tr = 0;
   
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      double prevHigh = iHigh(_Symbol, PERIOD_M5, i + 1);
      double prevLow = iLow(_Symbol, PERIOD_M5, i + 1);
      double prevClose = iClose(_Symbol, PERIOD_M5, i + 1);
      
      double highDiff = high - prevHigh;
      double lowDiff = prevLow - low;
      
      if(highDiff > lowDiff && highDiff > 0) plusDM += highDiff;
      else if(lowDiff > highDiff && lowDiff > 0) minusDM += lowDiff;
      
      double trueRange = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      tr += trueRange;
   }
   
   if(tr == 0) return 0;
   double plusDI = (plusDM / tr) * 100;
   double minusDI = (minusDM / tr) * 100;
   if(plusDI + minusDI == 0) return 0;
   return MathAbs(plusDI - minusDI) / (plusDI + minusDI) * 100;
}

//+------------------------------------------------------------------+
// PANEL VISUAL
//+------------------------------------------------------------------+
void CreateVisualPanel()
{
   int x = InpPanelX;
   int y = InpPanelY;
   int width = 350;
   int lineHeight = 20;
   
   // Fondo del panel
   string bgName = panelPrefix + "BG";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 200);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpPanelColor);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, true);
   
   // Título
   CreateLabel("Title", "QUANTUM INSTITUTIONAL BREAKOUT v5.0", x + 10, y + 5, clrWhite, 10, true);
   
   // Labels
   CreateLabel("Session", "", x + 10, y + 30, clrLightGray, 9);
   CreateLabel("AsianRange", "", x + 10, y + 50, clrLightGray, 9);
   CreateLabel("Pivot", "", x + 10, y + 70, clrLightGray, 9);
   CreateLabel("Bias", "", x + 10, y + 90, clrLightGray, 9);
   CreateLabel("ATR", "", x + 10, y + 110, clrLightGray, 9);
   CreateLabel("Trades", "", x + 10, y + 130, clrLightGray, 9);
   CreateLabel("WinRate", "", x + 10, y + 150, clrLightGray, 9);
   CreateLabel("Status", "", x + 10, y + 170, clrYellow, 9, true);
}

//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size, bool bold = false)
{
   string objName = panelPrefix + name;
   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   if(bold)
      ObjectSetString(0, objName, OBJPROP_FONT, "Arial Bold");
}

//+------------------------------------------------------------------+
void UpdateVisualPanel()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Sesión actual
   string session = "ASIA";
   if(hour >= 7 && hour < 10) session = "LONDRES";
   else if(hour >= 13 && hour < 16) session = "NUEVA YORK";
   ObjectSetString(0, panelPrefix + "Session", OBJPROP_TEXT, "Sesión: " + session);
   
   // Rango asiático
   if(asianRange.isValid)
   {
      string rangeText = StringFormat("Rango Asia: %.2f - %.2f", asianRange.low, asianRange.high);
      ObjectSetString(0, panelPrefix + "AsianRange", OBJPROP_TEXT, rangeText);
   }
   else
   {
      ObjectSetString(0, panelPrefix + "AsianRange", OBJPROP_TEXT, "Rango Asia: Esperando...");
   }
   
   // Pivote
   ObjectSetString(0, panelPrefix + "Pivot", OBJPROP_TEXT, 
                   StringFormat("Pivote Diario: %.2f", dailyPivot));
   
   // Sesgo
   double price = iClose(_Symbol, PERIOD_M5, 1);
   string bias = (price > dailyPivot) ? "ALCISTA" : "BAJISTA";
   color biasColor = (price > dailyPivot) ? clrLime : clrRed;
   ObjectSetString(0, panelPrefix + "Bias", OBJPROP_TEXT, "Sesgo: " + bias);
   ObjectSetInteger(0, panelPrefix + "Bias", OBJPROP_COLOR, biasColor);
   
   // ATR Expansion
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   double expansion = avgATR > 0 ? atr / avgATR : 0;
   string atrText = StringFormat("ATR Expansion: %.2fx %s", expansion, 
                                 expansion > 1.2 ? "(ACTIVO)" : "");
   ObjectSetString(0, panelPrefix + "ATR", OBJPROP_TEXT, atrText);
   
   // Trades
   ObjectSetString(0, panelPrefix + "Trades", OBJPROP_TEXT, 
                   StringFormat("Trades Hoy: %d/%d", stats.tradesThisDay, InpMaxTradesPerDay));
   
   // Win Rate
   ObjectSetString(0, panelPrefix + "WinRate", OBJPROP_TEXT, 
                   StringFormat("Win Rate: %.1f%%", stats.winRate));
   
   // Status
   string status = "Esperando señal...";
   if(PositionsTotal() > 0)
      status = "EN TRADE";
   else if(isPaused)
      status = "PAUSADO";
   else if(asianRange.isValid && (hour >= 7 && hour < 10))
      status = "Esperando ruptura Londres";
   else if(londonSession.isValid && (hour >= 13 && hour < 16))
      status = "Esperando continuación NY";
   
   ObjectSetString(0, panelPrefix + "Status", OBJPROP_TEXT, "Estado: " + status);
}

//+------------------------------------------------------------------+
