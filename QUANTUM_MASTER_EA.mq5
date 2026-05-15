//+------------------------------------------------------------------+
//|                                  QUANTUM_MASTER_EA.mq5           |
//|           Sistema MASTER - DAILY TRADER Edition                  |
//|           AGRESIVO v4.30 - Máximo Rendimiento                    |
//+------------------------------------------------------------------+
#property copyright "Quantum Master EA - Daily Trader Aggressive"
#property version   "4.30"

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
input int    InpMaxTradesPerDay = 6;         // Max trades/día (AUMENTADO más)
input int    InpMaxConsecutiveLosses = 5;    // Pausar después de N pérdidas (MÁS TOLERANTE)
input double InpMaxDailyLossPercent = 4.0;   // Pérdida máxima diaria % (AUMENTADO)
input double InpMaxDrawdownPercent = 20.0;   // Drawdown máximo % (AUMENTADO)

input group "═══ INDICADORES BASE ═══"
input int    InpBollingerPeriod = 20;        // Bollinger período
input double InpBollingerDeviation = 1.8;    // Bollinger desviación (REDUCIDO para más señales)
input int    InpRSIPeriod = 14;              // RSI período
input int    InpRSIOversold = 35;            // RSI sobreventa (MÁS ALTO para más señales)
input int    InpRSIOverbought = 65;          // RSI sobrecompra (MÁS BAJO para más señales)

// ═══════════════════════════════════════════════════════════════════
// COMPONENTES INSTITUCIONALES (Activar/Desactivar)
// ═══════════════════════════════════════════════════════════════════
input group "═══ MULTI-TIMEFRAME ANALYSIS ═══"
input bool   InpUseMTF = true;               // Usar análisis MTF
input bool   InpRequireMTFAlignment = false; // NO requiere alineación (MENOS RESTRICTIVO)

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
// PATRONES DE VELAS + IA
// ═══════════════════════════════════════════════════════════════════
input group "═══ PATRONES DE VELAS ═══"
input bool   InpUseCandlePatterns = true;    // Activar patrones de velas
input int    InpMinPatternScore = 55;        // Score mínimo del patrón (MUY REDUCIDO)
input bool   InpRequirePatternConfirmation = false; // NO requiere confirmación (MENOS RESTRICTIVO)

input group "═══ INTELIGENCIA ARTIFICIAL ═══"
input bool   InpUseAdaptiveLearning = true;  // Aprendizaje adaptativo
input int    InpMinLearningTrades = 50;      // Trades mínimos para aprender
input double InpMinPatternWinRate = 35.0;    // Win rate mínimo del patrón (MUY REDUCIDO)
input bool   InpUseIntelligentScoring = true; // Scoring inteligente
input int    InpMinIntelligentScore = 60;    // Score inteligente mínimo (MUY REDUCIDO)

input group "═══ FILTROS INTELIGENTES ═══"
input bool   InpUseMarketRegimeFilter = true;  // Filtro de régimen de mercado
input bool   InpUseOrderFlowFilter = true;     // Filtro de order flow
input bool   InpUseAdaptiveRisk = true;        // Riesgo adaptativo
input bool   InpUseSmartExit = true;           // Salidas inteligentes
input int    InpMaxHoursInTrade = 5;           // Máx horas sin alcanzar 50% TP (MÁS PACIENCIA)
input double InpMinADX = 8.0;                  // ADX mínimo para operar (MUY REDUCIDO)
input double InpMinVolatility = 0.4;           // Volatilidad mínima (MUY REDUCIDO)
input double InpMaxVolatility = 3.5;           // Volatilidad máxima (MUY AUMENTADO)
input double InpMinOrderFlowBuy = 1.0;         // Imbalance mínimo para compra (CASI NEUTRAL)
input double InpMaxOrderFlowSell = 1.0;        // Imbalance máximo para venta (CASI NEUTRAL)

input group "═══ MEJORAS AVANZADAS ═══"
input bool   InpUseConfluenceScoring = true;   // Scoring por confluencia
input int    InpMinConfluenceFactors = 2;      // Factores mínimos (de 10) (MUY REDUCIDO)
input bool   InpUseDynamicSL = true;           // Stop Loss dinámico
input double InpSLMultiplier = 1.6;            // Multiplicador SL (ATR) (MÁS AJUSTADO)
input bool   InpUsePartialProfits = true;      // Toma parcial de ganancias
input bool   InpUseCorrelationFilter = false;  // Filtro de correlación (DESACTIVADO)
input int    InpMinMinutesBetweenTrades = 10;  // Minutos entre trades similares (MUY REDUCIDO)

input group "═══ MEJORAS ÉLITE (MASTER) ═══"
input bool   InpUseTrendStrengthFilter = false; // Filtro de fuerza de tendencia (DESACTIVADO)
input double InpMinTrendStrength = 0.5;        // Fuerza mínima (REDUCIDO)
input bool   InpUseNewsFilter = false;         // Evitar operar cerca de noticias (DESACTIVADO)
input int    InpNewsAvoidMinutes = 30;         // Minutos antes/después de noticias
input bool   InpUseSessionFilter = false;      // Filtro de sesión óptima (DESACTIVADO)
input bool   InpTradeOnlyBestHours = false;    // Operar TODO el día (DESACTIVADO)
input bool   InpUseDrawdownProtection = true;  // Protección adicional de drawdown
input double InpMaxDrawdownForDay = 3.0;       // Drawdown máximo diario % (AUMENTADO)

input group "═══ ESTADÍSTICAS ═══"
input bool   InpSaveStatistics = true;       // Guardar estadísticas
input bool   InpPrintLearningStats = true;   // Imprimir estadísticas

// ═══════════════════════════════════════════════════════════════════
// ESTRUCTURAS DE DATOS ADICIONALES (IA)
// ═══════════════════════════════════════════════════════════════════

// Memoria de trades para aprendizaje
struct STradeMemory {
   datetime time;
   string signalType;
   string candlePattern;
   double entryPrice;
   double exitPrice;
   double profit;
   bool isWin;
   int hourGMT;
   int dayOfWeek;
   double rsi;
   double atr;
   int mtfAlignment;
   double vwapDistance;
   double spread;
   int intelligentScore;
};

// Estadísticas por patrón
struct SPatternStats {
   string name;
   int totalTrades;
   int wins;
   int losses;
   double winRate;
   double totalProfit;
   double avgProfit;
   double profitFactor;
   int bestHour;
   double bestRSI;
};

// Estadísticas por hora
struct SHourStats {
   int hour;
   int totalTrades;
   int wins;
   double winRate;
   double totalProfit;
};

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

// Memoria y estadísticas IA
STradeMemory tradeHistory[];
int historyCount = 0;
SPatternStats patternStats[30];
int patternCount = 0;
SHourStats hourStats[24];

// Variables para mejoras avanzadas
datetime lastTradeTime = 0;
string lastSignalType = "";
int lastDirection = 0;
bool tp1Taken = false;
bool tp2Taken = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   // Inicializar estructura
   lastSwingHigh.broken = true;
   lastSwingLow.broken = true;
   
   // Inicializar estadísticas por hora
   for(int i = 0; i < 24; i++)
   {
      hourStats[i].hour = i;
      hourStats[i].totalTrades = 0;
      hourStats[i].wins = 0;
      hourStats[i].winRate = 50.0;
      hourStats[i].totalProfit = 0;
   }
   
   // Cargar historial si existe
   if(InpUseAdaptiveLearning)
      LoadTradeHistory();
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  QUANTUM MASTER EA - AGGRESSIVE TRADER v4.30             ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  🔥 CONFIGURACIÓN AGRESIVA PARA MÁXIMO RENDIMIENTO       ║");
   Print("║  Base: Mean Reversion + 17 Patrones + IA                 ║");
   Print("║  Confluence: ", InpMinConfluenceFactors, "/10 | Score: ≥", InpMinIntelligentScore, " | ADX: ≥", DoubleToString(InpMinADX, 1), "        ║");
   Print("║  RSI: ", InpRSIOversold, "-", InpRSIOverbought, " | BB Dev: ", DoubleToString(InpBollingerDeviation, 1), " | Max: ", InpMaxTradesPerDay, "/día      ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  ⚡ FILTROS MUY PERMISIVOS:                               ║");
   Print("║  Order Flow: ", DoubleToString(InpMinOrderFlowBuy, 2), "-", DoubleToString(InpMaxOrderFlowSell, 2), " | Vol: ", DoubleToString(InpMinVolatility, 1), "-", DoubleToString(InpMaxVolatility, 1), "          ║");
   Print("║  Pattern: ≥", InpMinPatternScore, " | SL: ", DoubleToString(InpSLMultiplier, 1), "x | Entre trades: ", InpMinMinutesBetweenTrades, "min  ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  🚀 CONFIGURACIÓN AGRESIVA:                               ║");
   Print("║  Max Consecutive Losses: ", InpMaxConsecutiveLosses, " | Max DD: ", DoubleToString(InpMaxDrawdownPercent, 0), "%      ║");
   Print("║  Max Daily Loss: ", DoubleToString(InpMaxDailyLossPercent, 1), "% | Max Hours: ", InpMaxHoursInTrade, "h              ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Trades en memoria: ", historyCount, "                                ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Guardar historial
   if(InpSaveStatistics && InpUseAdaptiveLearning)
      SaveTradeHistory();
   
   // Imprimir estadísticas finales
   if(InpPrintLearningStats && InpUseAdaptiveLearning)
      PrintFinalStatistics();
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
   
   // ═══════════════════════════════════════════════════════════════
   // MEJORA 1: FILTRO DE RÉGIMEN DE MERCADO
   // ═══════════════════════════════════════════════════════════════
   if(!PassMarketRegimeFilter()) return;
   
   // ═══════════════════════════════════════════════════════════════
   // MEJORAS ÉLITE: FILTROS ADICIONALES
   // ═══════════════════════════════════════════════════════════════
   
   // Filtro de fuerza de tendencia
   if(!PassTrendStrengthFilter()) return;
   
   // Filtro de noticias
   if(IsNearNewsTime())
   {
      Print("⊗ FILTRO NOTICIAS: Evitando operar cerca de noticias");
      return;
   }
   
   // Filtro de sesión
   if(!PassSessionFilter()) return;
   
   // Protección de drawdown avanzada
   if(!PassDrawdownProtection()) return;
   
   // ═══════════════════════════════════════════════════════════════
   // ANÁLISIS MULTI-TIMEFRAME
   // ═══════════════════════════════════════════════════════════════
   int mtfAlignment = 0;
   if(InpUseMTF && InpRequireMTFAlignment)
   {
      if(!CheckMTFAlignment(mtfAlignment))
         return;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // DETECCIÓN DE PATRONES DE VELAS
   // ═══════════════════════════════════════════════════════════════
   string candlePattern = "NONE";
   int patternScore = 0;
   int patternSignal = 0;
   
   if(InpUseCandlePatterns)
   {
      patternSignal = DetectCandlePattern(candlePattern, patternScore);
      
      // Filtro por score mínimo
      if(patternScore > 0 && patternScore < InpMinPatternScore)
      {
         Print("⊗ Patrón ", candlePattern, " score bajo: ", patternScore);
         patternSignal = 0;
      }
      
      // Filtro por aprendizaje
      if(InpUseAdaptiveLearning && historyCount >= InpMinLearningTrades && patternSignal != 0)
      {
         if(!IsPatternProfitable(candlePattern))
         {
            Print("⊗ Patrón ", candlePattern, " no rentable (WR: ", 
                  DoubleToString(GetPatternWinRate(candlePattern), 1), "%)");
            patternSignal = 0;
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // SCORING INTELIGENTE
   // ═══════════════════════════════════════════════════════════════
   int intelligentScore = 50;
   if(InpUseIntelligentScoring && patternSignal != 0)
   {
      intelligentScore = CalculateIntelligentScore(candlePattern, patternScore, mtfAlignment);
      
      if(intelligentScore < InpMinIntelligentScore)
      {
         Print("⊗ Score inteligente bajo: ", intelligentScore, " (min: ", InpMinIntelligentScore, ")");
         return;
      }
      
      // Destacar señales premium
      if(intelligentScore >= 95)
      {
         Print("★★★ SEÑAL PREMIUM: Score ", intelligentScore, " ★★★");
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // MEJORA AVANZADA: CONFLUENCE SCORING
   // ═══════════════════════════════════════════════════════════════
   int confluenceScore = 0;
   if(InpUseConfluenceScoring && patternSignal != 0)
   {
      int pivotSignal = InpUsePivots ? AnalyzePivotSignals() : 0;
      double orderFlowImbalance = CalculateOrderFlowImbalance(10);
      
      confluenceScore = CalculateConfluenceScore(candlePattern, patternScore, mtfAlignment,
                                                  orderFlowImbalance, pivotSignal, patternSignal);
      
      // MEJORA ÉLITE: Aumentar requisito después de pérdidas
      int minRequired = InpMinConfluenceFactors;
      if(consecutiveLosses >= 2)
      {
         minRequired = InpMinConfluenceFactors + 1; // Requiere 1 factor más
         Print("⚠ Modo conservador: Requiere ", minRequired, " factores (pérdidas consecutivas: ", consecutiveLosses, ")");
      }
      
      if(confluenceScore < minRequired)
      {
         Print("⊗ CONFLUENCIA INSUFICIENTE: ", confluenceScore, "/10 factores (mín: ", 
               minRequired, ")");
         return;
      }
      
      Print("✅ CONFLUENCIA EXCELENTE: ", confluenceScore, "/10 factores ⭐⭐⭐");
   }
   
   // ═══════════════════════════════════════════════════════════════
   // PRIORIDAD 1: NY BREAKOUT
   // ═══════════════════════════════════════════════════════════════
   if(InpUseNYBreakout)
   {
      int breakoutSignal = AnalyzeNYBreakout();
      if(breakoutSignal != 0)
      {
         // MEJORA 2: Filtro de Order Flow
         if(!PassOrderFlowFilter(breakoutSignal))
            return;
         
         // Confirmar con patrón si está disponible
         if(InpRequirePatternConfirmation && InpUseCandlePatterns)
         {
            if(patternSignal == 0 || patternSignal != breakoutSignal)
            {
               Print("⊗ NY Breakout sin confirmación de patrón");
               return;
            }
         }
         
         if(breakoutSignal == 1)
            ExecuteBuySignal("NY_BREAKOUT", candlePattern, intelligentScore);
         else
            ExecuteSellSignal("NY_BREAKOUT", candlePattern, intelligentScore);
         return;
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // PRIORIDAD 2: PIVOT SIGNALS
   // ═══════════════════════════════════════════════════════════════
   if(InpUsePivots)
   {
      int pivotSignal = AnalyzePivotSignals();
      if(pivotSignal != 0)
      {
         // MEJORA 2: Filtro de Order Flow
         if(!PassOrderFlowFilter(pivotSignal))
            return;
         
         if(InpRequirePatternConfirmation && InpUseCandlePatterns)
         {
            if(patternSignal == 0 || patternSignal != pivotSignal)
               return;
         }
         
         if(pivotSignal == 1)
            ExecuteBuySignal("PIVOT", candlePattern, intelligentScore);
         else
            ExecuteSellSignal("PIVOT", candlePattern, intelligentScore);
         return;
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // PRIORIDAD 3: MEAN REVERSION + PATRONES
   // ═══════════════════════════════════════════════════════════════
   int mrSignal = AnalyzeMeanReversion();
   
   // Si hay patrón, debe coincidir con MR
   if(InpUseCandlePatterns && patternSignal != 0)
   {
      if(mrSignal == patternSignal)
      {
         // MEJORA 2: Filtro de Order Flow
         if(!PassOrderFlowFilter(mrSignal))
            return;
         
         if(patternSignal == 1)
            ExecuteBuySignal("MR_PATTERN", candlePattern, intelligentScore);
         else
            ExecuteSellSignal("MR_PATTERN", candlePattern, intelligentScore);
      }
   }
   else if(mrSignal != 0)
   {
      // MR sin patrón
      // MEJORA 2: Filtro de Order Flow
      if(!PassOrderFlowFilter(mrSignal))
         return;
      
      if(mrSignal == 1)
         ExecuteBuySignal("MEAN_REVERSION", "NONE", intelligentScore);
      else
         ExecuteSellSignal("MEAN_REVERSION", "NONE", intelligentScore);
   }
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
            string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
            
            // Extraer información del trade para actualizar memoria
            if(InpUseAdaptiveLearning && StringFind(comment, "QI_") >= 0)
            {
               string signalType = "UNKNOWN";
               string pattern = "NONE";
               int score = 50;
               
               string parts[];
               StringSplit(comment, '_', parts);
               if(ArraySize(parts) >= 2)
                  signalType = parts[1];
               if(ArraySize(parts) >= 3)
                  pattern = parts[2];
               if(ArraySize(parts) >= 4)
               {
                  string scoreStr = parts[3];
                  StringReplace(scoreStr, "S", "");
                  score = StringToInteger(scoreStr);
               }
               
               // Actualizar el último trade en memoria con el resultado
               if(historyCount > 0)
               {
                  tradeHistory[historyCount - 1].profit = profit;
                  tradeHistory[historyCount - 1].isWin = (profit > 0);
                  tradeHistory[historyCount - 1].exitPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
                  
                  UpdatePatternStats(pattern, profit > 0, profit);
                  
                  MqlDateTime dt;
                  TimeToStruct(tradeHistory[historyCount - 1].time, dt);
                  UpdateHourStats(dt.hour, profit > 0, profit);
               }
            }
            
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
bool CheckMTFAlignment(int &alignment)
{
   // Analizar D1, H4, H1 para alineación
   int trendD1 = GetTrend(PERIOD_D1);
   int trendH4 = GetTrend(PERIOD_H4);
   int trendH1 = GetTrend(PERIOD_H1);
   
   alignment = 0;
   if(trendD1 > 0) alignment++;
   if(trendH4 > 0) alignment++;
   if(trendH1 > 0) alignment++;
   
   // Alineación alcista: todos > 0
   if(trendD1 > 0 && trendH4 > 0 && trendH1 > 0)
   {
      Print("► MTF Alineado ALCISTA (D1/H4/H1)");
      return true;
   }
   
   // Alineación bajista: todos < 0
   if(trendD1 < 0 && trendH4 < 0 && trendH1 < 0)
   {
      alignment = -3;
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
void ExecuteBuySignal(string signalType, string pattern = "NONE", int score = 50)
{
   // Verificar falla de estructura
   if(DetectStructureFailure(1)) return;
   
   // MEJORA AVANZADA: Filtro de correlación
   if(!PassCorrelationFilter(signalType, 1)) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // MEJORA AVANZADA: SL Dinámico
   double slPips = CalculateDynamicSL();
   double sl = ask - slPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   string comment = "QI_" + signalType;
   if(pattern != "NONE")
      comment += "_" + pattern + "_S" + IntegerToString(score);
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, comment))
   {
      // Guardar en memoria para aprendizaje
      if(InpUseAdaptiveLearning)
         SaveTradeToMemory(signalType, pattern, ask, 0, 0, score);
      
      // MEJORA AVANZADA: Actualizar tracking de correlación
      UpdateCorrelationTracking(signalType, 1);
      
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA | ", signalType, "                              ║");
      Print("║  Lote: ", lots, " | SL: ", DoubleToString(slPips, 1), " | TP: ", InpTakeProfitPips, "          ║");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

void ExecuteSellSignal(string signalType, string pattern = "NONE", int score = 50)
{
   if(DetectStructureFailure(-1)) return;
   
   // MEJORA AVANZADA: Filtro de correlación
   if(!PassCorrelationFilter(signalType, -1)) return;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // MEJORA AVANZADA: SL Dinámico
   double slPips = CalculateDynamicSL();
   double sl = bid + slPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   string comment = "QI_" + signalType;
   if(pattern != "NONE")
      comment += "_" + pattern + "_S" + IntegerToString(score);
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, comment))
   {
      // Guardar en memoria para aprendizaje
      if(InpUseAdaptiveLearning)
         SaveTradeToMemory(signalType, pattern, bid, 0, 0, score);
      
      // MEJORA AVANZADA: Actualizar tracking de correlación
      UpdateCorrelationTracking(signalType, -1);
      
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA | ", signalType, "                               ║");
      Print("║  Lote: ", lots, " | SL: ", DoubleToString(slPips, 1), " | TP: ", InpTakeProfitPips, "          ║");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

double CalculatePositionSize(double slDistance)
{
   // Calcular multiplicador adaptativo
   double riskMultiplier = CalculateAdaptiveRiskMultiplier();
   
   // Aplicar multiplicador al riesgo base
   double adjustedRisk = InpRiskPercent * riskMultiplier;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * adjustedRisk / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = riskAmount / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   
   double finalLots = MathMax(minLot, MathMin(maxLot, lots));
   
   Print("💰 Lote calculado: ", finalLots, " | Riesgo ajustado: ", DoubleToString(adjustedRisk, 3), "%");
   
   return finalLots;
}

//+------------------------------------------------------------------+
// GESTIÓN DE POSICIONES CON TRAILING AKALI + SMART EXIT
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
      
      // MEJORA AVANZADA: Toma parcial de ganancias
      ManagePartialProfits(ticket, isBuy, openPrice, currentPrice, profitPips);
      
      // APLICAR SALIDAS INTELIGENTES PRIMERO
      ApplySmartExitLogic(ticket, isBuy, openPrice, openTime, currentPrice, profitPips);
      
      // Si la posición fue cerrada, continuar con la siguiente
      if(PositionSelectByTicket(ticket) == false) continue;
      
      // TRAILING STOPS
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

// ═══════════════════════════════════════════════════════════════════
// DETECCIÓN DE PATRONES DE VELAS (17 PATRONES)
// ═══════════════════════════════════════════════════════════════════
int DetectCandlePattern(string &patternName, int &score)
{
   double o1 = iOpen(_Symbol, PERIOD_M5, 1);
   double h1 = iHigh(_Symbol, PERIOD_M5, 1);
   double l1 = iLow(_Symbol, PERIOD_M5, 1);
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   
   double o2 = iOpen(_Symbol, PERIOD_M5, 2);
   double h2 = iHigh(_Symbol, PERIOD_M5, 2);
   double l2 = iLow(_Symbol, PERIOD_M5, 2);
   double c2 = iClose(_Symbol, PERIOD_M5, 2);
   
   double o3 = iOpen(_Symbol, PERIOD_M5, 3);
   double c3 = iClose(_Symbol, PERIOD_M5, 3);
   
   double body1 = MathAbs(c1 - o1);
   double range1 = h1 - l1;
   double body2 = MathAbs(c2 - o2);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minBody = 10 * 10 * point; // Mínimo 10 pips
   
   // ═══════════════════════════════════════════════════════════════
   // PATRONES ALCISTAS
   // ═══════════════════════════════════════════════════════════════
   
   // 1. HAMMER
   if(c1 > o1 && body1 > minBody && body1 < range1 * 0.35)
   {
      double lowerShadow = o1 - l1;
      double upperShadow = h1 - c1;
      
      if(lowerShadow > body1 * 2.0 && upperShadow < body1 * 0.5)
      {
         patternName = "HAMMER";
         score = 85;
         return 1;
      }
   }
   
   // 2. BULLISH ENGULFING
   if(c2 < o2 && c1 > o1 && body1 > minBody && body2 > minBody)
   {
      if(c1 > o2 && o1 < c2)
      {
         patternName = "BULLISH_ENGULFING";
         score = 90;
         return 1;
      }
   }
   
   // 3. MORNING STAR
   if(c3 < o3 && body1 > minBody && c1 > o1)
   {
      double body3 = MathAbs(c3 - o3);
      if(body2 < body3 * 0.3 && c1 > (o3 + c3) / 2)
      {
         patternName = "MORNING_STAR";
         score = 95;
         return 1;
      }
   }
   
   // 4. PIERCING LINE
   if(c2 < o2 && c1 > o1 && body1 > minBody && body2 > minBody)
   {
      double midpoint = (o2 + c2) / 2;
      if(o1 < c2 && c1 > midpoint && c1 < o2)
      {
         patternName = "PIERCING_LINE";
         score = 80;
         return 1;
      }
   }
   
   // 5. THREE WHITE SOLDIERS
   double o4 = iOpen(_Symbol, PERIOD_M5, 4);
   double c4 = iClose(_Symbol, PERIOD_M5, 4);
   
   if(c1 > o1 && c2 > o2 && c3 > o3 && c1 > c2 && c2 > c3)
   {
      if(body1 > minBody && body2 > minBody)
      {
         patternName = "THREE_WHITE_SOLDIERS";
         score = 88;
         return 1;
      }
   }
   
   // 6. BULLISH HARAMI
   if(c2 < o2 && c1 > o1 && body2 > minBody)
   {
      if(o1 > c2 && c1 < o2 && body1 < body2 * 0.5)
      {
         patternName = "BULLISH_HARAMI";
         score = 75;
         return 1;
      }
   }
   
   // 7. TWEEZER BOTTOM
   if(c2 < o2 && c1 > o1 && MathAbs(l1 - l2) < range1 * 0.1)
   {
      patternName = "TWEEZER_BOTTOM";
      score = 78;
      return 1;
   }
   
   // 8. DRAGONFLY DOJI
   if(body1 < range1 * 0.1 && range1 > minBody)
   {
      double lowerShadow = MathMin(o1, c1) - l1;
      double upperShadow = h1 - MathMax(o1, c1);
      
      if(lowerShadow > range1 * 0.7 && upperShadow < range1 * 0.1)
      {
         patternName = "DRAGONFLY_DOJI";
         score = 82;
         return 1;
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // PATRONES BAJISTAS
   // ═══════════════════════════════════════════════════════════════
   
   // 9. SHOOTING STAR
   if(c1 < o1 && body1 > minBody && body1 < range1 * 0.35)
   {
      double upperShadow = h1 - o1;
      double lowerShadow = c1 - l1;
      
      if(upperShadow > body1 * 2.0 && lowerShadow < body1 * 0.5)
      {
         patternName = "SHOOTING_STAR";
         score = 85;
         return -1;
      }
   }
   
   // 10. BEARISH ENGULFING
   if(c2 > o2 && c1 < o1 && body1 > minBody && body2 > minBody)
   {
      if(c1 < o2 && o1 > c2)
      {
         patternName = "BEARISH_ENGULFING";
         score = 90;
         return -1;
      }
   }
   
   // 11. EVENING STAR
   if(c3 > o3 && body1 > minBody && c1 < o1)
   {
      double body3 = MathAbs(c3 - o3);
      if(body2 < body3 * 0.3 && c1 < (o3 + c3) / 2)
      {
         patternName = "EVENING_STAR";
         score = 95;
         return -1;
      }
   }
   
   // 12. DARK CLOUD COVER
   if(c2 > o2 && c1 < o1 && body1 > minBody && body2 > minBody)
   {
      double midpoint = (o2 + c2) / 2;
      if(o1 > c2 && c1 < midpoint && c1 > o2)
      {
         patternName = "DARK_CLOUD_COVER";
         score = 80;
         return -1;
      }
   }
   
   // 13. THREE BLACK CROWS
   if(c1 < o1 && c2 < o2 && c3 < o3 && c1 < c2 && c2 < c3)
   {
      if(body1 > minBody && body2 > minBody)
      {
         patternName = "THREE_BLACK_CROWS";
         score = 88;
         return -1;
      }
   }
   
   // 14. BEARISH HARAMI
   if(c2 > o2 && c1 < o1 && body2 > minBody)
   {
      if(o1 < c2 && c1 > o2 && body1 < body2 * 0.5)
      {
         patternName = "BEARISH_HARAMI";
         score = 75;
         return -1;
      }
   }
   
   // 15. TWEEZER TOP
   if(c2 > o2 && c1 < o1 && MathAbs(h1 - h2) < range1 * 0.1)
   {
      patternName = "TWEEZER_TOP";
      score = 78;
      return -1;
   }
   
   // 16. GRAVESTONE DOJI
   if(body1 < range1 * 0.1 && range1 > minBody)
   {
      double upperShadow = h1 - MathMax(o1, c1);
      double lowerShadow = MathMin(o1, c1) - l1;
      
      if(upperShadow > range1 * 0.7 && lowerShadow < range1 * 0.1)
      {
         patternName = "GRAVESTONE_DOJI";
         score = 82;
         return -1;
      }
   }
   
   // 17. HANGING MAN
   if(c1 < o1 && body1 > minBody && body1 < range1 * 0.35)
   {
      double lowerShadow = c1 - l1;
      double upperShadow = h1 - o1;
      
      if(lowerShadow > body1 * 2.0 && upperShadow < body1 * 0.5)
      {
         // Solo en zona alta (precio > SMA)
         double sma = CalculateSMA(20, PERIOD_M5);
         if(c1 > sma)
         {
            patternName = "HANGING_MAN";
            score = 83;
            return -1;
         }
      }
   }
   
   patternName = "NONE";
   score = 0;
   return 0;
}

// ═══════════════════════════════════════════════════════════════════
// SISTEMA DE APRENDIZAJE E INTELIGENCIA
// ═══════════════════════════════════════════════════════════════════

double GetPatternWinRate(string patternName)
{
   int wins = 0;
   int total = 0;
   
   for(int i = 0; i < historyCount; i++)
   {
      if(tradeHistory[i].candlePattern == patternName)
      {
         total++;
         if(tradeHistory[i].isWin) wins++;
      }
   }
   
   if(total < 5) return 50.0;
   return (double)wins / total * 100.0;
}

bool IsPatternProfitable(string patternName)
{
   double wr = GetPatternWinRate(patternName);
   return (wr >= InpMinPatternWinRate);
}

double GetHourWinRate(int hour)
{
   if(hourStats[hour].totalTrades < 5) return 50.0;
   return hourStats[hour].winRate;
}

int CalculateIntelligentScore(string pattern, int patternScore, int mtfAlignment)
{
   int score = 50;
   
   // Factor 1: Score del patrón base
   score += (patternScore - 75) / 2;
   
   // Factor 2: Win rate histórico del patrón
   if(historyCount >= InpMinLearningTrades)
   {
      double wr = GetPatternWinRate(pattern);
      score += (int)((wr - 50) * 0.4);
   }
   
   // Factor 3: Hora del día
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   if(hour >= 8 && hour < 12) score += 10;   // Londres
   if(hour >= 13 && hour < 17) score += 15;  // NY
   if(hour >= 0 && hour < 3) score -= 20;    // Asia
   
   double hourWR = GetHourWinRate(hour);
   if(hourWR > 55) score += 10;
   if(hourWR < 40) score -= 15;
   
   // Factor 4: RSI
   double rsi = CalculateRSI(InpRSIPeriod, PERIOD_M5);
   if(rsi < 25 || rsi > 75) score += 15;
   if(rsi > 45 && rsi < 55) score -= 10;
   
   // Factor 5: Volatilidad
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   if(atr > avgATR * 1.5) score += 10;
   if(atr < avgATR * 0.5) score -= 15;
   
   // Factor 6: MTF Alignment
   if(mtfAlignment == 3) score += 15;
   if(mtfAlignment == 0) score -= 10;
   
   // Factor 7: VWAP
   if(InpUseVWAP && currentVWAP > 0)
   {
      double price = iClose(_Symbol, PERIOD_M5, 1);
      double distance = MathAbs(price - currentVWAP) / currentVWAP * 100;
      if(distance < 0.1) score += 10;
      if(distance > 0.5) score -= 10;
   }
   
   // Factor 8: Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread < 20) score += 5;
   if(spread > 40) score -= 10;
   
   return score;
}

void SaveTradeToMemory(string signalType, string pattern, double entry, double exit, double profit, int score)
{
   ArrayResize(tradeHistory, historyCount + 1);
   
   tradeHistory[historyCount].time = TimeCurrent();
   tradeHistory[historyCount].signalType = signalType;
   tradeHistory[historyCount].candlePattern = pattern;
   tradeHistory[historyCount].entryPrice = entry;
   tradeHistory[historyCount].exitPrice = exit;
   tradeHistory[historyCount].profit = profit;
   tradeHistory[historyCount].isWin = (profit > 0);
   tradeHistory[historyCount].intelligentScore = score;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   tradeHistory[historyCount].hourGMT = dt.hour;
   tradeHistory[historyCount].dayOfWeek = dt.day_of_week;
   tradeHistory[historyCount].rsi = CalculateRSI(14, PERIOD_M5);
   tradeHistory[historyCount].atr = CalculateATR(14, PERIOD_M5);
   tradeHistory[historyCount].vwapDistance = currentVWAP > 0 ? MathAbs(entry - currentVWAP) : 0;
   tradeHistory[historyCount].spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   historyCount++;
   
   UpdatePatternStats(pattern, profit > 0, profit);
   UpdateHourStats(dt.hour, profit > 0, profit);
}

void UpdatePatternStats(string pattern, bool isWin, double profit)
{
   if(pattern == "NONE") return;
   
   int index = -1;
   for(int i = 0; i < patternCount; i++)
   {
      if(patternStats[i].name == pattern)
      {
         index = i;
         break;
      }
   }
   
   if(index == -1)
   {
      index = patternCount;
      patternStats[index].name = pattern;
      patternStats[index].totalTrades = 0;
      patternStats[index].wins = 0;
      patternStats[index].losses = 0;
      patternStats[index].totalProfit = 0;
      patternCount++;
   }
   
   patternStats[index].totalTrades++;
   if(isWin)
      patternStats[index].wins++;
   else
      patternStats[index].losses++;
   
   patternStats[index].totalProfit += profit;
   patternStats[index].winRate = (double)patternStats[index].wins / patternStats[index].totalTrades * 100.0;
   patternStats[index].avgProfit = patternStats[index].totalProfit / patternStats[index].totalTrades;
   
   if(patternStats[index].losses > 0)
   {
      double grossProfit = 0;
      double grossLoss = 0;
      for(int i = 0; i < historyCount; i++)
      {
         if(tradeHistory[i].candlePattern == pattern)
         {
            if(tradeHistory[i].profit > 0)
               grossProfit += tradeHistory[i].profit;
            else
               grossLoss += MathAbs(tradeHistory[i].profit);
         }
      }
      patternStats[index].profitFactor = grossLoss > 0 ? grossProfit / grossLoss : 0;
   }
   
   if(InpPrintLearningStats)
   {
      Print("📊 ", pattern, " | Trades: ", patternStats[index].totalTrades,
            " | WR: ", DoubleToString(patternStats[index].winRate, 1), "%",
            " | PF: ", DoubleToString(patternStats[index].profitFactor, 2));
   }
}

void UpdateHourStats(int hour, bool isWin, double profit)
{
   hourStats[hour].totalTrades++;
   if(isWin) hourStats[hour].wins++;
   hourStats[hour].totalProfit += profit;
   hourStats[hour].winRate = (double)hourStats[hour].wins / hourStats[hour].totalTrades * 100.0;
}

void LoadTradeHistory()
{
   string filename = "QUANTUM_AI_History_" + _Symbol + ".csv";
   int handle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_COMMON);
   
   if(handle == INVALID_HANDLE) return;
   
   historyCount = 0;
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(line == "" || StringFind(line, "time") >= 0) continue;
      
      ArrayResize(tradeHistory, historyCount + 1);
      
      string parts[];
      StringSplit(line, ',', parts);
      if(ArraySize(parts) >= 10)
      {
         tradeHistory[historyCount].time = StringToTime(parts[0]);
         tradeHistory[historyCount].signalType = parts[1];
         tradeHistory[historyCount].candlePattern = parts[2];
         tradeHistory[historyCount].profit = StringToDouble(parts[3]);
         tradeHistory[historyCount].isWin = (StringToInteger(parts[4]) == 1);
         tradeHistory[historyCount].hourGMT = StringToInteger(parts[5]);
         tradeHistory[historyCount].rsi = StringToDouble(parts[6]);
         tradeHistory[historyCount].atr = StringToDouble(parts[7]);
         tradeHistory[historyCount].intelligentScore = StringToInteger(parts[8]);
         
         historyCount++;
      }
   }
   
   FileClose(handle);
   Print("✓ Historial cargado: ", historyCount, " trades");
}

void SaveTradeHistory()
{
   string filename = "QUANTUM_AI_History_" + _Symbol + ".csv";
   int handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_COMMON);
   
   if(handle == INVALID_HANDLE) return;
   
   FileWrite(handle, "time,signal,pattern,profit,isWin,hour,rsi,atr,score,vwapDist");
   
   for(int i = 0; i < historyCount; i++)
   {
      FileWrite(handle,
         TimeToString(tradeHistory[i].time),
         tradeHistory[i].signalType,
         tradeHistory[i].candlePattern,
         tradeHistory[i].profit,
         tradeHistory[i].isWin ? 1 : 0,
         tradeHistory[i].hourGMT,
         tradeHistory[i].rsi,
         tradeHistory[i].atr,
         tradeHistory[i].intelligentScore,
         tradeHistory[i].vwapDistance
      );
   }
   
   FileClose(handle);
   Print("✓ Historial guardado: ", historyCount, " trades");
}

void PrintFinalStatistics()
{
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║           ESTADÍSTICAS FINALES - QUANTUM AI               ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Total Trades: ", historyCount, "                                      ║");
   Print("║  Win Rate Global: ", DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%                          ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  PATRONES MÁS RENTABLES:                                  ║");
   
   for(int i = 0; i < patternCount; i++)
   {
      if(patternStats[i].totalTrades >= 5)
      {
         Print("║  ", patternStats[i].name, " | ", patternStats[i].totalTrades, " trades | WR: ",
               DoubleToString(patternStats[i].winRate, 1), "% | PF: ",
               DoubleToString(patternStats[i].profitFactor, 2), "  ║");
      }
   }
   
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  MEJORES HORAS:                                           ║");
   
   for(int h = 0; h < 24; h++)
   {
      if(hourStats[h].totalTrades >= 5)
      {
         Print("║  ", h, ":00 GMT | ", hourStats[h].totalTrades, " trades | WR: ",
               DoubleToString(hourStats[h].winRate, 1), "%  ║");
      }
   }
   
   Print("╚═══════════════════════════════════════════════════════════╝");
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 1: MARKET REGIME DETECTION (ADX + VOLATILITY)
// ═══════════════════════════════════════════════════════════════════

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

bool PassMarketRegimeFilter()
{
   if(!InpUseMarketRegimeFilter) return true;
   
   // Calcular ADX
   double adx = CalculateADX(14);
   
   // Calcular volatilidad
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   double volRatio = avgATR > 0 ? atr / avgATR : 1.0;
   
   // Filtro 1: ADX muy bajo = mercado sin dirección
   if(adx < InpMinADX)
   {
      Print("⊗ FILTRO RÉGIMEN: ADX bajo (", DoubleToString(adx, 1), ") - Mercado sin dirección");
      return false;
   }
   
   // Filtro 2: Volatilidad muy baja = movimientos falsos
   if(volRatio < InpMinVolatility)
   {
      Print("⊗ FILTRO RÉGIMEN: Volatilidad baja (", DoubleToString(volRatio, 2), "x) - Evitar operar");
      return false;
   }
   
   // Filtro 3: Volatilidad extrema = riesgo alto
   if(volRatio > InpMaxVolatility)
   {
      Print("⊗ FILTRO RÉGIMEN: Volatilidad extrema (", DoubleToString(volRatio, 2), "x) - Demasiado riesgo");
      return false;
   }
   
   Print("✓ FILTRO RÉGIMEN: OK | ADX: ", DoubleToString(adx, 1), " | Vol: ", DoubleToString(volRatio, 2), "x");
   return true;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 2: ORDER FLOW ANALYSIS
// ═══════════════════════════════════════════════════════════════════

double CalculateOrderFlowImbalance(int bars = 10)
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

bool PassOrderFlowFilter(int signalDirection)
{
   if(!InpUseOrderFlowFilter) return true;
   
   double imbalance = CalculateOrderFlowImbalance(10);
   
   // Señal de compra
   if(signalDirection == 1)
   {
      if(imbalance < InpMinOrderFlowBuy)
      {
         Print("⊗ FILTRO ORDER FLOW: Compra rechazada | Imbalance: ", DoubleToString(imbalance, 2), 
               " (mín: ", DoubleToString(InpMinOrderFlowBuy, 2), ")");
         return false;
      }
      Print("✓ FILTRO ORDER FLOW: Compra OK | Presión compradora: ", DoubleToString(imbalance, 2));
   }
   
   // Señal de venta
   if(signalDirection == -1)
   {
      if(imbalance > InpMaxOrderFlowSell)
      {
         Print("⊗ FILTRO ORDER FLOW: Venta rechazada | Imbalance: ", DoubleToString(imbalance, 2),
               " (máx: ", DoubleToString(InpMaxOrderFlowSell, 2), ")");
         return false;
      }
      Print("✓ FILTRO ORDER FLOW: Venta OK | Presión vendedora: ", DoubleToString(imbalance, 2));
   }
   
   return true;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 3: ADAPTIVE RISK MANAGEMENT
// ═══════════════════════════════════════════════════════════════════

double GetRecentWinRate(int lastNTrades = 10)
{
   if(historyCount < lastNTrades) return 50.0;
   
   int wins = 0;
   int startIndex = historyCount - lastNTrades;
   
   for(int i = startIndex; i < historyCount; i++)
   {
      if(tradeHistory[i].isWin) wins++;
   }
   
   return (double)wins / lastNTrades * 100.0;
}

double CalculateAdaptiveRiskMultiplier()
{
   if(!InpUseAdaptiveRisk) return 1.0;
   
   double multiplier = 1.0;
   
   // Factor 1: Win Rate reciente
   double recentWR = GetRecentWinRate(10);
   
   if(recentWR > 60) multiplier *= 1.3;      // Racha ganadora
   else if(recentWR > 55) multiplier *= 1.1;
   else if(recentWR < 40) multiplier *= 0.5; // Racha perdedora
   else if(recentWR < 45) multiplier *= 0.7;
   
   // Factor 2: Pérdidas consecutivas
   if(consecutiveLosses >= 2) multiplier *= 0.6;
   else if(consecutiveLosses >= 1) multiplier *= 0.8;
   
   // Factor 3: Volatilidad
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   if(avgATR > 0 && atr > avgATR * 1.5) multiplier *= 0.7;
   
   // Limitar multiplicador
   if(multiplier < 0.5) multiplier = 0.5;
   if(multiplier > 1.5) multiplier = 1.5;
   
   Print("🎯 Multiplicador de Riesgo: ", DoubleToString(multiplier, 2), 
         " | WR reciente: ", DoubleToString(recentWR, 1), "%",
         " | Pérdidas consecutivas: ", consecutiveLosses);
   
   return multiplier;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 4: SMART EXIT MANAGEMENT
// ═══════════════════════════════════════════════════════════════════

void ApplySmartExitLogic(ulong ticket, bool isBuy, double openPrice, datetime openTime, 
                         double currentPrice, double profitPips)
{
   if(!InpUseSmartExit) return;
   
   // Salida 1: Tiempo sin alcanzar 50% TP
   int hoursOpen = (int)((TimeCurrent() - openTime) / 3600);
   double halfTP = InpTakeProfitPips / 2.0;
   
   if(hoursOpen >= InpMaxHoursInTrade && profitPips < halfTP)
   {
      Print("⏰ SALIDA INTELIGENTE: ", hoursOpen, " horas sin alcanzar 50% TP (", 
            DoubleToString(profitPips, 1), " pips)");
      trade.PositionClose(ticket);
      return;
   }
   
   // Salida 2: Viernes 15:00 GMT
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= 15)
   {
      Print("📅 SALIDA INTELIGENTE: Viernes 15:00 GMT - Cerrando posición");
      trade.PositionClose(ticket);
      return;
   }
   
   // Salida 3: Patrón opuesto fuerte
   string oppositePattern = "";
   int oppositeScore = 0;
   int oppositeSignal = DetectCandlePattern(oppositePattern, oppositeScore);
   
   if(isBuy && oppositeSignal == -1 && oppositeScore >= 85)
   {
      Print("🔄 SALIDA INTELIGENTE: Patrón bajista fuerte (", oppositePattern, 
            " score: ", oppositeScore, ") - Cerrando compra");
      trade.PositionClose(ticket);
      return;
   }
   
   if(!isBuy && oppositeSignal == 1 && oppositeScore >= 85)
   {
      Print("🔄 SALIDA INTELIGENTE: Patrón alcista fuerte (", oppositePattern,
            " score: ", oppositeScore, ") - Cerrando venta");
      trade.PositionClose(ticket);
      return;
   }
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA AVANZADA 1: CONFLUENCE SCORING
// ═══════════════════════════════════════════════════════════════════

int CalculateConfluenceScore(string pattern, int patternScore, int mtfAlign, 
                             double orderFlowImbalance, int pivotSignal, int direction)
{
   if(!InpUseConfluenceScoring) return 10; // Si no usa confluencia, retornar alto
   
   int confluence = 0;
   
   // Factor 1: Patrón fuerte (score ≥85)
   if(patternScore >= 85)
   {
      confluence++;
      Print("  ✓ Factor 1: Patrón fuerte (", pattern, " score: ", patternScore, ")");
   }
   
   // Factor 2: MTF Alignment (3 timeframes alineados)
   if(MathAbs(mtfAlign) == 3)
   {
      confluence++;
      Print("  ✓ Factor 2: MTF alineado (", mtfAlign, " timeframes)");
   }
   
   // Factor 3: VWAP Alignment
   if(InpUseVWAP && currentVWAP > 0)
   {
      double price = iClose(_Symbol, PERIOD_M5, 1);
      double distance = MathAbs(price - currentVWAP) / currentVWAP * 100;
      if(distance < 0.15)
      {
         confluence++;
         Print("  ✓ Factor 3: Cerca de VWAP (", DoubleToString(distance, 3), "%)");
      }
   }
   
   // Factor 4: Pivot Signal
   if(pivotSignal != 0)
   {
      confluence++;
      Print("  ✓ Factor 4: Señal de Pivot");
   }
   
   // Factor 5: Order Flow fuerte
   if((direction == 1 && orderFlowImbalance > 1.5) || 
      (direction == -1 && orderFlowImbalance < 0.67))
   {
      confluence++;
      Print("  ✓ Factor 5: Order Flow fuerte (", DoubleToString(orderFlowImbalance, 2), ")");
   }
   
   // Factor 6: Market Regime favorable
   double adx = CalculateADX(14);
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   double volRatio = avgATR > 0 ? atr / avgATR : 1.0;
   
   if(adx > 20 && volRatio > 0.9 && volRatio < 1.8)
   {
      confluence++;
      Print("  ✓ Factor 6: Régimen favorable (ADX: ", DoubleToString(adx, 1), ")");
   }
   
   // Factor 7: RSI extremo
   double rsi = CalculateRSI(14, PERIOD_M5);
   if((direction == 1 && rsi < 35) || (direction == -1 && rsi > 65))
   {
      confluence++;
      Print("  ✓ Factor 7: RSI extremo (", DoubleToString(rsi, 1), ")");
   }
   
   // Factor 8: Estructura rota
   if(InpUseStructure)
   {
      if((direction == 1 && lastSwingHigh.broken) || 
         (direction == -1 && lastSwingLow.broken))
      {
         confluence++;
         Print("  ✓ Factor 8: Estructura rota (BOS)");
      }
   }
   
   // Factor 9: Hora premium (Londres o NY)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if((dt.hour >= 8 && dt.hour < 12) || (dt.hour >= 13 && dt.hour < 17))
   {
      confluence++;
      Print("  ✓ Factor 9: Hora premium (", dt.hour, ":00 GMT)");
   }
   
   // Factor 10: Win Rate reciente alto
   double recentWR = GetRecentWinRate(10);
   if(recentWR > 55)
   {
      confluence++;
      Print("  ✓ Factor 10: Win Rate reciente alto (", DoubleToString(recentWR, 1), "%)");
   }
   
   Print("📊 CONFLUENCIA TOTAL: ", confluence, "/10 factores alineados");
   
   return confluence;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA AVANZADA 2: DYNAMIC STOP LOSS
// ═══════════════════════════════════════════════════════════════════

double CalculateDynamicSL()
{
   if(!InpUseDynamicSL) return InpStopLossPips;
   
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   double volRatio = avgATR > 0 ? atr / avgATR : 1.0;
   
   double multiplier = InpSLMultiplier;
   
   // Ajustar multiplicador según volatilidad
   if(volRatio < 0.8)
      multiplier = InpSLMultiplier * 0.75;  // Baja vol: SL más ajustado
   else if(volRatio > 1.5)
      multiplier = InpSLMultiplier * 1.25;  // Alta vol: SL más amplio
   
   double slDistance = atr * multiplier;
   
   // Convertir a pips
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPips = slDistance / (10 * point);
   
   // Limitar entre 15 y 45 pips
   if(slPips < 15) slPips = 15;
   if(slPips > 45) slPips = 45;
   
   Print("📏 SL Dinámico: ", DoubleToString(slPips, 1), " pips | ATR: ", 
         DoubleToString(atr, 2), " | Vol Ratio: ", DoubleToString(volRatio, 2));
   
   return slPips;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA AVANZADA 3: PARTIAL PROFIT TAKING
// ═══════════════════════════════════════════════════════════════════

void ManagePartialProfits(ulong ticket, bool isBuy, double openPrice, 
                          double currentPrice, double profitPips)
{
   if(!InpUsePartialProfits) return;
   
   double lots = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Verificar que hay suficiente volumen para cerrar parcialmente
   if(lots < minLot * 2) return;
   
   // TP1: 50% en 50% del TP (25 pips si TP=50)
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
   
   // TP2: 30% en 100% del TP (50 pips)
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
            
            // Mover SL a breakeven + 10 pips para el 20% restante
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double newSL = openPrice + (isBuy ? 10 : -10) * 10 * point;
            trade.PositionModify(ticket, newSL, 0);
            Print("🔒 SL movido a breakeven +10 pips para el 20% restante");
         }
      }
   }
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA AVANZADA 4: CORRELATION FILTER
// ═══════════════════════════════════════════════════════════════════

bool PassCorrelationFilter(string signalType, int direction)
{
   if(!InpUseCorrelationFilter) return true;
   
   // Filtro 1: Ya hay trade abierto en misma dirección
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         int posType = (int)PositionGetInteger(POSITION_TYPE);
         int posDirection = (posType == POSITION_TYPE_BUY) ? 1 : -1;
         
         if(posDirection == direction)
         {
            Print("⊗ FILTRO CORRELACIÓN: Ya hay trade abierto en misma dirección");
            return false;
         }
      }
   }
   
   // Filtro 2: Señal similar muy reciente
   if(signalType == lastSignalType && direction == lastDirection)
   {
      int minutesSince = (int)((TimeCurrent() - lastTradeTime) / 60);
      if(minutesSince < InpMinMinutesBetweenTrades)
      {
         Print("⊗ FILTRO CORRELACIÓN: Señal similar hace ", minutesSince, " minutos (mín: ", 
               InpMinMinutesBetweenTrades, ")");
         return false;
      }
   }
   
   // Filtro 3: Máximo 1 trade por tipo por día
   int tradesOfTypeToday = 0;
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   
   for(int i = 0; i < historyCount; i++)
   {
      if(tradeHistory[i].signalType == signalType)
      {
         MqlDateTime dtTrade;
         TimeToStruct(tradeHistory[i].time, dtTrade);
         
         if(dtTrade.year == dtNow.year && dtTrade.mon == dtNow.mon && dtTrade.day == dtNow.day)
            tradesOfTypeToday++;
      }
   }
   
   if(tradesOfTypeToday >= 1)
   {
      Print("⊗ FILTRO CORRELACIÓN: Ya hay ", tradesOfTypeToday, " trade(s) tipo ", signalType, " hoy");
      return false;
   }
   
   Print("✓ FILTRO CORRELACIÓN: OK");
   return true;
}

void UpdateCorrelationTracking(string signalType, int direction)
{
   lastTradeTime = TimeCurrent();
   lastSignalType = signalType;
   lastDirection = direction;
   tp1Taken = false;
   tp2Taken = false;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA ÉLITE 1: TREND STRENGTH FILTER
// ═══════════════════════════════════════════════════════════════════

double CalculateTrendStrength()
{
   // Calcular fuerza de tendencia usando múltiples EMAs
   double ema20 = CalculateEMA(20, PERIOD_M5);
   double ema50 = CalculateEMA(50, PERIOD_M5);
   double ema100 = CalculateEMA(100, PERIOD_M5);
   double ema200 = CalculateEMA(200, PERIOD_M5);
   
   double price = iClose(_Symbol, PERIOD_M5, 1);
   
   // Calcular separación entre EMAs (normalizado)
   double range = iHigh(_Symbol, PERIOD_M5, 1) - iLow(_Symbol, PERIOD_M5, 1);
   if(range == 0) return 0;
   
   double separation = 0;
   separation += MathAbs(ema20 - ema50) / range;
   separation += MathAbs(ema50 - ema100) / range;
   separation += MathAbs(ema100 - ema200) / range;
   
   // Normalizar a 0-1
   double strength = separation / 3.0;
   if(strength > 1.0) strength = 1.0;
   
   // Verificar alineación
   bool bullishAlignment = (ema20 > ema50 && ema50 > ema100 && ema100 > ema200);
   bool bearishAlignment = (ema20 < ema50 && ema50 < ema100 && ema100 < ema200);
   
   if(!bullishAlignment && !bearishAlignment)
      strength *= 0.5; // Penalizar si no hay alineación clara
   
   return strength;
}

bool PassTrendStrengthFilter()
{
   if(!InpUseTrendStrengthFilter) return true;
   
   double trendStrength = CalculateTrendStrength();
   
   if(trendStrength < InpMinTrendStrength)
   {
      Print("⊗ FILTRO TENDENCIA: Fuerza insuficiente (", DoubleToString(trendStrength, 2), 
            " < ", DoubleToString(InpMinTrendStrength, 2), ")");
      return false;
   }
   
   Print("✓ FILTRO TENDENCIA: Fuerza OK (", DoubleToString(trendStrength, 2), ")");
   return true;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA ÉLITE 2: NEWS FILTER
// ═══════════════════════════════════════════════════════════════════

bool IsNearNewsTime()
{
   if(!InpUseNewsFilter) return false;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Horas típicas de noticias importantes (GMT)
   // 8:30 - Noticias UK
   // 12:30-14:30 - Noticias US (NFP, FOMC, etc)
   // 18:00 - Cierre de sesión
   
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Definir ventanas de noticias (en minutos desde medianoche)
   int newsWindows[][2] = {
      {8*60 + 15, 8*60 + 45},      // 8:15-8:45 GMT (UK news)
      {12*60 + 15, 12*60 + 45},    // 12:15-12:45 GMT (Early US)
      {13*60 + 15, 13*60 + 45},    // 13:15-13:45 GMT (US open)
      {14*60 + 15, 14*60 + 45},    // 14:15-14:45 GMT (US data)
      {17*60 + 45, 18*60 + 15}     // 17:45-18:15 GMT (Close)
   };
   
   for(int i = 0; i < ArrayRange(newsWindows, 0); i++)
   {
      if(currentMinutes >= newsWindows[i][0] && currentMinutes <= newsWindows[i][1])
      {
         Print("⊗ FILTRO NOTICIAS: Cerca de ventana de noticias (", dt.hour, ":", dt.min, " GMT)");
         return true;
      }
   }
   
   return false;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA ÉLITE 3: SESSION FILTER (Mejores Horas)
// ═══════════════════════════════════════════════════════════════════

bool PassSessionFilter()
{
   if(!InpUseSessionFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   if(!InpTradeOnlyBestHours)
      return true;
   
   // Solo operar en las mejores horas
   bool isLondon = (hour >= 8 && hour < 12);   // Londres: 8:00-12:00 GMT
   bool isNY = (hour >= 13 && hour < 17);      // NY: 13:00-17:00 GMT
   
   if(!isLondon && !isNY)
   {
      Print("⊗ FILTRO SESIÓN: Fuera de horas óptimas (", hour, ":00 GMT)");
      return false;
   }
   
   // Verificar win rate por hora
   double hourWR = GetHourWinRate(hour);
   if(hourWR < 45.0 && historyCount >= InpMinLearningTrades)
   {
      Print("⊗ FILTRO SESIÓN: Hora con bajo WR (", hour, ":00 = ", 
            DoubleToString(hourWR, 1), "%)");
      return false;
   }
   
   Print("✓ FILTRO SESIÓN: Hora óptima (", hour, ":00 GMT, WR: ", 
         DoubleToString(hourWR, 1), "%)");
   return true;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA ÉLITE 4: DRAWDOWN PROTECTION AVANZADA
// ═══════════════════════════════════════════════════════════════════

bool PassDrawdownProtection()
{
   if(!InpUseDrawdownProtection) return true;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyDD = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   
   if(dailyDD > InpMaxDrawdownForDay)
   {
      Print("⊗ PROTECCIÓN DD: Drawdown diario excedido (", DoubleToString(dailyDD, 2), 
            "% > ", DoubleToString(InpMaxDrawdownForDay, 2), "%)");
      return false;
   }
   
   // Protección adicional: Si hay 2+ pérdidas consecutivas, reducir agresividad
   if(consecutiveLosses >= 2)
   {
      // Solo operar con confluence score muy alto
      Print("⚠ PROTECCIÓN DD: 2+ pérdidas consecutivas - Modo ultra-conservador");
      // Esta verificación se hará en el confluence scoring
   }
   
   return true;
}
