//+------------------------------------------------------------------+
//|                                  QUANTUM_INSTITUTIONAL_EA.mq5    |
//|           Mean Reversion + Institutional Concepts + MTF          |
//|           Sistema Modular - Activar/Desactivar Componentes       |
//+------------------------------------------------------------------+
#property copyright "Quantum Institutional"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN BASE (QUANTUM Original - NO TOCAR si funciona)
// ═══════════════════════════════════════════════════════════════════
input group "═══ CONFIGURACIÓN BASE QUANTUM ═══"
input double InpRiskPercent = 0.20;          // Riesgo por trade
input int    InpStopLossPips = 25;           // Stop Loss pips
input int    InpTakeProfitPips = 50;         // Take Profit pips
input int    InpMagicNumber = 303030;        // Magic number

input group "═══ PROTECCIONES BASE ═══"
input int    InpMaxTradesPerDay = 3;         // Max trades/día (2 MR + 1 Breakout)
input int    InpMaxConsecutiveLosses = 3;    // Pausar después de N pérdidas
input double InpMaxDailyLossPercent = 1.5;   // Pérdida máxima diaria %
input double InpMaxDrawdownPercent = 15.0;   // Drawdown máximo %

input group "═══ INDICADORES BASE ═══"
input int    InpBollingerPeriod = 20;        // Bollinger período
input double InpBollingerDeviation = 2.0;    // Bollinger desviación
input int    InpRSIPeriod = 14;              // RSI período
input int    InpRSIOversold = 30;            // RSI sobreventa
input int    InpRSIOverbought = 70;          // RSI sobrecompra

// ═══════════════════════════════════════════════════════════════════
// COMPONENTES INSTITUCIONALES (Activar/Desactivar)
// ═══════════════════════════════════════════════════════════════════
input group "═══ MULTI-TIMEFRAME ANALYSIS ═══"
input bool   InpUseMTF = true;               // Usar análisis MTF
input bool   InpRequireMTFAlignment = true;  // Requiere alineación D1/H4/H1

input group "═══ NY BREAKOUT SYSTEM ═══"
input bool   InpUseNYBreakout = true;        // Activar NY Breakout
input int    InpNYOpenHour = 13;             // Hora apertura NY (GMT)
input double InpBreakoutMinVolume = 1.5;     // Volumen mínimo vs promedio

input group "═══ TRAILING STOP AKALI ═══"
input bool   InpUseAkaliTrailing = true;     // Usar trailing Akali
input int    InpAkaliLevel1 = 15;            // Nivel 1: Breakeven
input int    InpAkaliLevel2 = 25;            // Nivel 2: Asegurar ganancia
input int    InpAkaliLevel3 = 35;            // Nivel 3: Trailing estructura

input group "═══ INSTITUTIONAL ALGORITHMS ═══"
input bool   InpUseVWAP = true;              // Usar VWAP
input bool   InpUseTWAP = false;             // Usar TWAP (opcional)
input double InpVWAPDeviation = 0.5;         // Desviación VWAP (% ATR)

input group "═══ STRUCTURE ANALYSIS ═══"
input bool   InpUseStructure = true;         // Detectar BOS/CHoCH
input int    InpSwingBars = 5;               // Barras para swing points
input bool   InpDetectFailure = true;        // Detectar falla de estructura

input group "═══ GEOMETRIC PATTERNS ═══"
input bool   InpUsePatterns = false;         // Detectar patrones (opcional)
input int    InpPatternBars = 20;            // Barras para patrones

input group "═══ PIVOT SYSTEM ═══"
input bool   InpUsePivots = true;            // Usar pivotes diarios
input bool   InpTradePivotBounce = true;     // Operar rebotes en pivotes
input bool   InpTradePivotBreakout = true;   // Operar breakouts de pivotes

input group "═══ SESSION ANALYSIS ═══"
input bool   InpUseLondonContinuity = true;  // Continuidad Londres→NY
input double InpLondonStrengthMin = 1.2;     // Fuerza mínima Londres (ATR)

input group "═══ SCALPING TRAILING ═══"
input bool   InpUseScalpingTrail = false;    // Trailing scalping (opcional)
input int    InpScalpTrailDistance = 5;      // Distancia trailing scalping

// ═══════════════════════════════════════════════════════════════════
// GLOBALES
// ═══════════════════════════════════════════════════════════════════
CTrade trade;
datetime lastBarTime = 0;
datetime lastTradeDate = 0;
int tradesThisDay = 0;
int consecutiveLosses = 0;
bool isPaused = false;
double dailyStartBalance = 0;
double peakBalance = 0;
int totalWins = 0;
int totalLosses = 0;

// Estructura de mercado
struct SSwingPoint {
   double price;
   datetime time;
   bool isHigh;
   bool broken;
};
SSwingPoint lastSwingHigh, lastSwingLow;

// Sesión Londres
struct SLondonSession {
   double open;
   double close;
   double high;
   double low;
   bool isBullish;
   double strength;
   datetime startTime;
   datetime endTime;
};
SLondonSession londonSession;

// Pivotes diarios
double dailyPivot, R1, R2, R3, S1, S2, S3;

// VWAP
double currentVWAP = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   // Inicializar estructura
   lastSwingHigh.broken = true;
   lastSwingLow.broken = true;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║      QUANTUM INSTITUTIONAL - Sistema Modular              ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Base: QUANTUM Mean Reversion                             ║");
   Print("║  MTF: ", InpUseMTF ? "ON" : "OFF", " | NY Breakout: ", InpUseNYBreakout ? "ON" : "OFF", "                      ║");
   Print("║  Akali Trail: ", InpUseAkaliTrailing ? "ON" : "OFF", " | VWAP: ", InpUseVWAP ? "ON" : "OFF", "                  ║");
   Print("║  Structure: ", InpUseStructure ? "ON" : "OFF", " | Pivots: ", InpUsePivots ? "ON" : "OFF", "                  ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   UpdateDailyControls();
   UpdatePerformanceStats();
   
   // Actualizar componentes institucionales
   if(InpUsePivots) UpdateDailyPivots();
   if(InpUseVWAP) UpdateVWAP();
   if(InpUseStructure) UpdateStructure();
   if(InpUseLondonContinuity) UpdateLondonSession();
   
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   if(!PassProtectionFilters()) return;
   
   // ANÁLISIS MULTI-TIMEFRAME
   if(InpUseMTF && InpRequireMTFAlignment)
   {
      if(!CheckMTFAlignment())
      {
         return; // No operar si MTF no alineado
      }
   }
   
   // PRIORIDAD 1: NY BREAKOUT (13:00-14:00 GMT)
   if(InpUseNYBreakout)
   {
      int breakoutSignal = AnalyzeNYBreakout();
      if(breakoutSignal != 0)
      {
         if(breakoutSignal == 1)
            ExecuteBuySignal("NY_BREAKOUT");
         else
            ExecuteSellSignal("NY_BREAKOUT");
         return;
      }
   }
   
   // PRIORIDAD 2: PIVOT BOUNCE/BREAKOUT
   if(InpUsePivots)
   {
      int pivotSignal = AnalyzePivotSignals();
      if(pivotSignal != 0)
      {
         if(pivotSignal == 1)
            ExecuteBuySignal("PIVOT");
         else
            ExecuteSellSignal("PIVOT");
         return;
      }
   }
   
   // PRIORIDAD 3: MEAN REVERSION (QUANTUM Original)
   int mrSignal = AnalyzeMeanReversion();
   if(mrSignal == 1)
      ExecuteBuySignal("MEAN_REVERSION");
   else if(mrSignal == -1)
      ExecuteSellSignal("MEAN_REVERSION");
}

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
      tradesThisDay = 0;
      lastTradeDate = today;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      
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
               totalWins++;
               consecutiveLosses = 0;
               if(isPaused) isPaused = false;
               
               Print("✓ WIN | ", totalWins, "W-", totalLosses, "L | WR: ", 
                     DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%");
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ PAUSADO - ", consecutiveLosses, " pérdidas consecutivas");
               }
               
               Print("✗ LOSS | ", totalWins, "W-", totalLosses, "L | Consecutive: ", consecutiveLosses);
            }
            
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
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
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
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hourGMT = timeStruct.hour;
   
   bool isLondon = (hourGMT >= 8 && hourGMT < 12);
   bool isNY = (hourGMT >= 13 && hourGMT < 17);
   
   if(!isLondon && !isNY) return false;
   if(timeStruct.day_of_week == 5 && hourGMT >= 15) return false;
   
   return true;
}

//+------------------------------------------------------------------+
// MULTI-TIMEFRAME ANALYSIS
//+------------------------------------------------------------------+
bool CheckMTFAlignment()
{
   // Analizar D1, H4, H1 para alineación
   int trendD1 = GetTrend(PERIOD_D1);
   int trendH4 = GetTrend(PERIOD_H4);
   int trendH1 = GetTrend(PERIOD_H1);
   
   // Alineación alcista: todos > 0
   if(trendD1 > 0 && trendH4 > 0 && trendH1 > 0)
   {
      Print("► MTF Alineado ALCISTA (D1/H4/H1)");
      return true;
   }
   
   // Alineación bajista: todos < 0
   if(trendD1 < 0 && trendH4 < 0 && trendH1 < 0)
   {
      Print("▼ MTF Alineado BAJISTA (D1/H4/H1)");
      return true;
   }
   
   return false; // No alineado
}

int GetTrend(ENUM_TIMEFRAMES tf)
{
   double ema20 = CalculateEMA(20, tf);
   double ema50 = CalculateEMA(50, tf);
   double ema100 = CalculateEMA(100, tf);
   
   if(ema20 > ema50 && ema50 > ema100) return 1;  // Alcista
   if(ema20 < ema50 && ema50 < ema100) return -1; // Bajista
   return 0; // Rango
}

//+------------------------------------------------------------------+
// NY BREAKOUT SYSTEM
//+------------------------------------------------------------------+
int AnalyzeNYBreakout()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hourGMT = timeStruct.hour;
   
   // Solo en apertura NY (13:00-14:00 GMT)
   if(hourGMT != InpNYOpenHour) return 0;
   
   // Verificar que Londres ya cerró
   if(!londonSession.startTime) return 0;
   
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   
   // Verificar volumen
   long vol1 = iVolume(_Symbol, PERIOD_M5, 1);
   long avgVol = 0;
   for(int i = 2; i <= 11; i++)
      avgVol += iVolume(_Symbol, PERIOD_M5, i);
   avgVol /= 10;
   
   bool volumeOK = (vol1 > avgVol * InpBreakoutMinVolume);
   if(!volumeOK) return 0;
   
   // BREAKOUT ALCISTA: Rompe máximo de Londres
   if(high1 > londonSession.high)
   {
      // Confirmación: vela alcista fuerte
      double range = high1 - low1;
      if(range > 0 && (close1 - low1) > range * 0.7)
      {
         // Continuidad de Londres
         if(InpUseLondonContinuity && londonSession.isBullish && londonSession.strength > InpLondonStrengthMin)
         {
            Print("► NY BREAKOUT ALCISTA | Londres continuidad | Vol:", vol1);
            return 1;
         }
         else if(!InpUseLondonContinuity)
         {
            Print("► NY BREAKOUT ALCISTA | Vol:", vol1);
            return 1;
         }
      }
   }
   
   // BREAKOUT BAJISTA: Rompe mínimo de Londres
   if(low1 < londonSession.low)
   {
      double range = high1 - low1;
      if(range > 0 && (high1 - close1) > range * 0.7)
      {
         if(InpUseLondonContinuity && !londonSession.isBullish && londonSession.strength > InpLondonStrengthMin)
         {
            Print("▼ NY BREAKOUT BAJISTA | Londres continuidad | Vol:", vol1);
            return -1;
         }
         else if(!InpUseLondonContinuity)
         {
            Print("▼ NY BREAKOUT BAJISTA | Vol:", vol1);
            return -1;
         }
      }
   }
   
   return 0;
}

void UpdateLondonSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hourGMT = timeStruct.hour;
   
   // Inicio de Londres (8:00 GMT)
   if(hourGMT == 8 && timeStruct.min < 5)
   {
      londonSession.startTime = TimeCurrent();
      londonSession.open = iClose(_Symbol, PERIOD_M5, 1);
      londonSession.high = londonSession.open;
      londonSession.low = londonSession.open;
   }
   
   // Durante Londres: actualizar high/low
   if(hourGMT >= 8 && hourGMT < 12)
   {
      double high = iHigh(_Symbol, PERIOD_M5, 1);
      double low = iLow(_Symbol, PERIOD_M5, 1);
      
      if(high > londonSession.high) londonSession.high = high;
      if(low < londonSession.low) londonSession.low = low;
   }
   
   // Cierre de Londres (12:00 GMT)
   if(hourGMT == 12 && timeStruct.min < 5)
   {
      londonSession.endTime = TimeCurrent();
      londonSession.close = iClose(_Symbol, PERIOD_M5, 1);
      londonSession.isBullish = (londonSession.close > londonSession.open);
      
      double atr = CalculateATR(14, PERIOD_M5);
      double range = londonSession.high - londonSession.low;
      londonSession.strength = range / atr;
      
      Print("Londres cerró | ", londonSession.isBullish ? "Alcista" : "Bajista", 
            " | Fuerza: ", DoubleToString(londonSession.strength, 2));
   }
}

//+------------------------------------------------------------------+
// VWAP CALCULATION
//+------------------------------------------------------------------+
void UpdateVWAP()
{
   double sumPV = 0;
   double sumV = 0;
   
   // Calcular VWAP desde inicio del día
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime todayStart = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                       IntegerToString(timeStruct.mon) + "." + 
                                       IntegerToString(timeStruct.day));
   
   int bars = Bars(_Symbol, PERIOD_M5, todayStart, TimeCurrent());
   
   for(int i = 1; i <= MathMin(bars, 288); i++) // Max 288 velas M5 en un día
   {
      double typical = (iHigh(_Symbol, PERIOD_M5, i) + iLow(_Symbol, PERIOD_M5, i) + iClose(_Symbol, PERIOD_M5, i)) / 3;
      long volume = iVolume(_Symbol, PERIOD_M5, i);
      
      sumPV += typical * volume;
      sumV += volume;
   }
   
   if(sumV > 0)
      currentVWAP = sumPV / sumV;
}

bool CheckVWAPAlignment(int direction)
{
   if(!InpUseVWAP) return true; // Si no usa VWAP, siempre OK
   
   double price = iClose(_Symbol, PERIOD_M5, 1);
   double atr = CalculateATR(14, PERIOD_M5);
   double deviation = InpVWAPDeviation * atr;
   
   // Compra: precio debe estar cerca o por encima de VWAP
   if(direction > 0)
   {
      if(price < currentVWAP - deviation)
      {
         Print("⊗ VWAP: Precio muy por debajo (", price, " vs ", currentVWAP, ")");
         return false;
      }
   }
   
   // Venta: precio debe estar cerca o por debajo de VWAP
   if(direction < 0)
   {
      if(price > currentVWAP + deviation)
      {
         Print("⊗ VWAP: Precio muy por encima (", price, " vs ", currentVWAP, ")");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
// STRUCTURE ANALYSIS
//+------------------------------------------------------------------+
void UpdateStructure()
{
   // Buscar swing points
   FindSwingPoints();
   
   // Detectar BOS (Break of Structure)
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   
   // BOS Alcista: rompe último swing high
   if(!lastSwingHigh.broken && close1 > lastSwingHigh.price)
   {
      lastSwingHigh.broken = true;
      Print("► BOS ALCISTA | Precio: ", close1, " > Swing High: ", lastSwingHigh.price);
   }
   
   // BOS Bajista: rompe último swing low
   if(!lastSwingLow.broken && close1 < lastSwingLow.price)
   {
      lastSwingLow.broken = true;
      Print("▼ BOS BAJISTA | Precio: ", close1, " < Swing Low: ", lastSwingLow.price);
   }
}

void FindSwingPoints()
{
   // Buscar swing high
   for(int i = InpSwingBars; i < InpSwingBars + 10; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      bool isSwing = true;
      
      for(int j = i - InpSwingBars; j <= i + InpSwingBars; j++)
      {
         if(j == i || j < 1) continue;
         if(iHigh(_Symbol, PERIOD_M5, j) > high)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && (lastSwingHigh.broken || high > lastSwingHigh.price))
      {
         lastSwingHigh.price = high;
         lastSwingHigh.time = iTime(_Symbol, PERIOD_M5, i);
         lastSwingHigh.isHigh = true;
         lastSwingHigh.broken = false;
         break;
      }
   }
   
   // Buscar swing low
   for(int i = InpSwingBars; i < InpSwingBars + 10; i++)
   {
      double low = iLow(_Symbol, PERIOD_M5, i);
      bool isSwing = true;
      
      for(int j = i - InpSwingBars; j <= i + InpSwingBars; j++)
      {
         if(j == i || j < 1) continue;
         if(iLow(_Symbol, PERIOD_M5, j) < low)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && (lastSwingLow.broken || low < lastSwingLow.price))
      {
         lastSwingLow.price = low;
         lastSwingLow.time = iTime(_Symbol, PERIOD_M5, i);
         lastSwingLow.isHigh = false;
         lastSwingLow.broken = false;
         break;
      }
   }
}

bool DetectStructureFailure(int direction)
{
   if(!InpDetectFailure) return false;
   
   // Falla alcista: rompió swing high pero retrocedió y rompió swing low
   if(direction > 0 && lastSwingHigh.broken && !lastSwingLow.broken)
   {
      double close1 = iClose(_Symbol, PERIOD_M5, 1);
      if(close1 < lastSwingLow.price)
      {
         Print("⚠ FALLA ESTRUCTURA ALCISTA - Reversión bajista probable");
         return true;
      }
   }
   
   // Falla bajista: rompió swing low pero retrocedió y rompió swing high
   if(direction < 0 && lastSwingLow.broken && !lastSwingHigh.broken)
   {
      double close1 = iClose(_Symbol, PERIOD_M5, 1);
      if(close1 > lastSwingHigh.price)
      {
         Print("⚠ FALLA ESTRUCTURA BAJISTA - Reversión alcista probable");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
// PIVOT SYSTEM
//+------------------------------------------------------------------+
void UpdateDailyPivots()
{
   // Calcular pivotes del día anterior
   double highD1 = iHigh(_Symbol, PERIOD_D1, 1);
   double lowD1 = iLow(_Symbol, PERIOD_D1, 1);
   double closeD1 = iClose(_Symbol, PERIOD_D1, 1);
   
   dailyPivot = (highD1 + lowD1 + closeD1) / 3;
   
   R1 = (2 * dailyPivot) - lowD1;
   R2 = dailyPivot + (highD1 - lowD1);
   R3 = highD1 + 2 * (dailyPivot - lowD1);
   
   S1 = (2 * dailyPivot) - highD1;
   S2 = dailyPivot - (highD1 - lowD1);
   S3 = lowD1 - 2 * (highD1 - dailyPivot);
}

int AnalyzePivotSignals()
{
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   double atr = CalculateATR(14, PERIOD_M5);
   double tolerance = atr * 0.2;
   
   // REBOTE EN SOPORTE (S1, S2, S3)
   if(InpTradePivotBounce)
   {
      // S1
      if(low1 <= S1 + tolerance && close1 > open1 && close1 > S1)
      {
         Print("► PIVOT BOUNCE S1 | Precio: ", close1);
         return 1;
      }
      // S2
      if(low1 <= S2 + tolerance && close1 > open1 && close1 > S2)
      {
         Print("► PIVOT BOUNCE S2 | Precio: ", close1);
         return 1;
      }
   }
   
   // REBOTE EN RESISTENCIA (R1, R2, R3)
   if(InpTradePivotBounce)
   {
      // R1
      if(high1 >= R1 - tolerance && close1 < open1 && close1 < R1)
      {
         Print("▼ PIVOT BOUNCE R1 | Precio: ", close1);
         return -1;
      }
      // R2
      if(high1 >= R2 - tolerance && close1 < open1 && close1 < R2)
      {
         Print("▼ PIVOT BOUNCE R2 | Precio: ", close1);
         return -1;
      }
   }
   
   // BREAKOUT DE PIVOTES
   if(InpTradePivotBreakout)
   {
      double close2 = iClose(_Symbol, PERIOD_M5, 2);
      
      // Breakout alcista de R1
      if(close2 <= R1 && close1 > R1 && close1 > open1)
      {
         Print("► PIVOT BREAKOUT R1 | Precio: ", close1);
         return 1;
      }
      
      // Breakout bajista de S1
      if(close2 >= S1 && close1 < S1 && close1 < open1)
      {
         Print("▼ PIVOT BREAKOUT S1 | Precio: ", close1);
         return -1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
// MEAN REVERSION (QUANTUM Original)
//+------------------------------------------------------------------+
int AnalyzeMeanReversion()
{
   double sma = CalculateSMA(InpBollingerPeriod, PERIOD_M5);
   double stdDev = CalculateStdDev(InpBollingerPeriod, sma, PERIOD_M5);
   double upperBand = sma + (InpBollingerDeviation * stdDev);
   double lowerBand = sma - (InpBollingerDeviation * stdDev);
   
   double rsi = CalculateRSI(InpRSIPeriod, PERIOD_M5);
   
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   
   // COMPRA
   if(rsi < InpRSIOversold)
   {
      bool touchedLowerBand = (low1 <= lowerBand * 1.001);
      bool bullishCandle = (close1 > open1);
      bool bouncing = (close1 > low1 + (high1 - low1) * 0.5);
      
      if(touchedLowerBand && bullishCandle && bouncing)
      {
         if(CheckVWAPAlignment(1))
         {
            Print("► MEAN REVERSION COMPRA | RSI: ", DoubleToString(rsi, 1));
            return 1;
         }
      }
   }
   
   // Señal extrema compra
   if(rsi < 25 && close1 < lowerBand && close1 > open1)
   {
      if(CheckVWAPAlignment(1))
      {
         Print("► MR COMPRA EXTREMA | RSI: ", DoubleToString(rsi, 1));
         return 1;
      }
   }
   
   // VENTA
   if(rsi > InpRSIOverbought)
   {
      bool touchedUpperBand = (high1 >= upperBand * 0.999);
      bool bearishCandle = (close1 < open1);
      bool falling = (close1 < high1 - (high1 - low1) * 0.5);
      
      if(touchedUpperBand && bearishCandle && falling)
      {
         if(CheckVWAPAlignment(-1))
         {
            Print("▼ MEAN REVERSION VENTA | RSI: ", DoubleToString(rsi, 1));
            return -1;
         }
      }
   }
   
   // Señal extrema venta
   if(rsi > 75 && close1 > upperBand && close1 < open1)
   {
      if(CheckVWAPAlignment(-1))
      {
         Print("▼ MR VENTA EXTREMA | RSI: ", DoubleToString(rsi, 1));
         return -1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
// EJECUCIÓN DE OPERACIONES
//+------------------------------------------------------------------+
void ExecuteBuySignal(string signalType)
{
   // Verificar falla de estructura
   if(DetectStructureFailure(1)) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = ask - InpStopLossPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(InpStopLossPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "QI_" + signalType))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA | ", signalType, "                              ║");
      Print("║  Lote: ", lots, " | SL: ", InpStopLossPips, " | TP: ", InpTakeProfitPips, "          ║");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

void ExecuteSellSignal(string signalType)
{
   if(DetectStructureFailure(-1)) return;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + InpStopLossPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(InpStopLossPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "QI_" + signalType))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA | ", signalType, "                               ║");
      Print("║  Lote: ", lots, " | SL: ", InpStopLossPips, " | TP: ", InpTakeProfitPips, "          ║");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

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
// GESTIÓN DE POSICIONES CON TRAILING AKALI
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      if(InpUseAkaliTrailing)
      {
         AkaliTrailingStop(ticket, isBuy, openPrice, currentPrice, currentSL, currentTP, profitPips, point);
      }
      else if(InpUseScalpingTrail)
      {
         ScalpingTrailingStop(ticket, isBuy, currentPrice, currentSL, currentTP, profitPips, point);
      }
      else
      {
         // Trailing original QUANTUM
         if(profitPips > 20)
         {
            double breakeven = openPrice + (isBuy ? 5 : -5) * 10 * point;
            
            if(isBuy && breakeven > currentSL)
               trade.PositionModify(ticket, breakeven, currentTP);
            else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
               trade.PositionModify(ticket, breakeven, currentTP);
         }
         
         if(profitPips > 35)
         {
            double trailDistance = 15 * 10 * point;
            double newSL;
            
            if(isBuy)
            {
               newSL = currentPrice - trailDistance;
               if(newSL > currentSL)
                  trade.PositionModify(ticket, newSL, currentTP);
            }
            else
            {
               newSL = currentPrice + trailDistance;
               if(currentSL == 0 || newSL < currentSL)
                  trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void AkaliTrailingStop(ulong ticket, bool isBuy, double openPrice, double currentPrice, 
                       double currentSL, double currentTP, double profitPips, double point)
{
   // NIVEL 1: Breakeven
   if(profitPips > InpAkaliLevel1)
   {
      double breakeven = openPrice + (isBuy ? 5 : -5) * 10 * point;
      
      if(isBuy && breakeven > currentSL)
      {
         trade.PositionModify(ticket, breakeven, currentTP);
         Print("► Akali L1: Breakeven +5 pips");
         return;
      }
      else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
      {
         trade.PositionModify(ticket, breakeven, currentTP);
         Print("▼ Akali L1: Breakeven +5 pips");
         return;
      }
   }
   
   // NIVEL 2: Asegurar ganancia
   if(profitPips > InpAkaliLevel2)
   {
      double secureSL = openPrice + (isBuy ? 10 : -10) * 10 * point;
      
      if(isBuy && secureSL > currentSL)
      {
         trade.PositionModify(ticket, secureSL, currentTP);
         Print("► Akali L2: SL asegurado +10 pips");
         return;
      }
      else if(!isBuy && (currentSL == 0 || secureSL < currentSL))
      {
         trade.PositionModify(ticket, secureSL, currentTP);
         Print("▼ Akali L2: SL asegurado +10 pips");
         return;
      }
   }
   
   // NIVEL 3: Trailing basado en estructura
   if(profitPips > InpAkaliLevel3)
   {
      double structureSL;
      
      if(isBuy)
      {
         // Usar último swing low como SL
         structureSL = lastSwingLow.price + 2 * 10 * point;
         if(structureSL > currentSL && structureSL < currentPrice)
         {
            trade.PositionModify(ticket, structureSL, currentTP);
            Print("► Akali L3: Trailing estructura | SL: ", structureSL);
         }
      }
      else
      {
         // Usar último swing high como SL
         structureSL = lastSwingHigh.price - 2 * 10 * point;
         if((currentSL == 0 || structureSL < currentSL) && structureSL > currentPrice)
         {
            trade.PositionModify(ticket, structureSL, currentTP);
            Print("▼ Akali L3: Trailing estructura | SL: ", structureSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
void ScalpingTrailingStop(ulong ticket, bool isBuy, double currentPrice, 
                          double currentSL, double currentTP, double profitPips, double point)
{
   // Trailing agresivo para scalping
   if(profitPips > 10)
   {
      double trailDistance = InpScalpTrailDistance * 10 * point;
      double newSL;
      
      if(isBuy)
      {
         newSL = currentPrice - trailDistance;
         if(newSL > currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print("► Scalp Trail: -", InpScalpTrailDistance, " pips | Profit: ", DoubleToString(profitPips, 1));
         }
      }
      else
      {
         newSL = currentPrice + trailDistance;
         if(currentSL == 0 || newSL < currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print("▼ Scalp Trail: +", InpScalpTrailDistance, " pips | Profit: ", DoubleToString(profitPips, 1));
         }
      }
   }
}

//+------------------------------------------------------------------+
// FUNCIONES AUXILIARES
//+------------------------------------------------------------------+
double CalculateSMA(int period, ENUM_TIMEFRAMES tf)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, tf, i);
   return sum / period;
}

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

double CalculateEMA(int period, ENUM_TIMEFRAMES tf)
{
   double multiplier = 2.0 / (period + 1);
   double ema = iClose(_Symbol, tf, period);
   
   for(int i = period - 1; i >= 1; i--)
   {
      double close = iClose(_Symbol, tf, i);
      ema = (close - ema) * multiplier + ema;
   }
   
   return ema;
}
//+------------------------------------------------------------------+
