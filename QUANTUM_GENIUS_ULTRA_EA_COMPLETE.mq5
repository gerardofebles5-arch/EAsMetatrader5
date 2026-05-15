//+------------------------------------------------------------------+
//|                                  QUANTUM_GENIUS_ULTRA_EA.mq5           |
//|           Sistema MASTER - MÃ¡xima Inteligencia y PrecisiÃ³n      |
//|           Confluence + Partials + News Filter + Trend Strength  |
//+------------------------------------------------------------------+
#property copyright "Quantum Master EA"
#property version   "5.00"

#include <Trade\Trade.mqh>

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// CONFIGURACIÃ“N BASE (QUANTUM Original - NO TOCAR si funciona)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
input group "â•â•â• CONFIGURACIÃ“N BASE QUANTUM â•â•â•"
input double InpRiskPercent = 0.20;          // Riesgo por trade
input int    InpStopLossPips = 25;           // Stop Loss pips
input int    InpTakeProfitPips = 50;         // Take Profit pips
input int    InpMagicNumber = 303030;        // Magic number

input group "â•â•â• PROTECCIONES BASE â•â•â•"
input int    InpMaxTradesPerDay = 2;         // Max trades/dÃ­a (CALIDAD > CANTIDAD)
input int    InpMaxConsecutiveLosses = 3;    // Pausar despuÃ©s de N pÃ©rdidas
input double InpMaxDailyLossPercent = 1.5;   // PÃ©rdida mÃ¡xima diaria %
input double InpMaxDrawdownPercent = 15.0;   // Drawdown mÃ¡ximo %

input group "â•â•â• INDICADORES BASE â•â•â•"
input int    InpBollingerPeriod = 20;        // Bollinger perÃ­odo
input double InpBollingerDeviation = 2.0;    // Bollinger desviaciÃ³n
input int    InpRSIPeriod = 14;              // RSI perÃ­odo
input int    InpRSIOversold = 30;            // RSI sobreventa
input int    InpRSIOverbought = 70;          // RSI sobrecompra

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// COMPONENTES INSTITUCIONALES (Activar/Desactivar)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
input group "â•â•â• MULTI-TIMEFRAME ANALYSIS â•â•â•"
input bool   InpUseMTF = true;               // Usar anÃ¡lisis MTF
input bool   InpRequireMTFAlignment = true;  // Requiere alineaciÃ³n D1/H4/H1

input group "â•â•â• NY BREAKOUT SYSTEM â•â•â•"
input bool   InpUseNYBreakout = true;        // Activar NY Breakout
input int    InpNYOpenHour = 13;             // Hora apertura NY (GMT)
input double InpBreakoutMinVolume = 1.5;     // Volumen mÃ­nimo vs promedio

input group "â•â•â• TRAILING STOP AKALI â•â•â•"
input bool   InpUseAkaliTrailing = true;     // Usar trailing Akali
input int    InpAkaliLevel1 = 15;            // Nivel 1: Breakeven
input int    InpAkaliLevel2 = 25;            // Nivel 2: Asegurar ganancia
input int    InpAkaliLevel3 = 35;            // Nivel 3: Trailing estructura

input group "â•â•â• INSTITUTIONAL ALGORITHMS â•â•â•"
input bool   InpUseVWAP = true;              // Usar VWAP
input bool   InpUseTWAP = false;             // Usar TWAP (opcional)
input double InpVWAPDeviation = 0.5;         // DesviaciÃ³n VWAP (% ATR)

input group "â•â•â• STRUCTURE ANALYSIS â•â•â•"
input bool   InpUseStructure = true;         // Detectar BOS/CHoCH
input int    InpSwingBars = 5;               // Barras para swing points
input bool   InpDetectFailure = true;        // Detectar falla de estructura

input group "â•â•â• GEOMETRIC PATTERNS â•â•â•"
input bool   InpUsePatterns = false;         // Detectar patrones (opcional)
input int    InpPatternBars = 20;            // Barras para patrones

input group "â•â•â• PIVOT SYSTEM â•â•â•"
input bool   InpUsePivots = true;            // Usar pivotes diarios
input bool   InpTradePivotBounce = true;     // Operar rebotes en pivotes
input bool   InpTradePivotBreakout = true;   // Operar breakouts de pivotes

input group "â•â•â• SESSION ANALYSIS â•â•â•"
input bool   InpUseLondonContinuity = true;  // Continuidad Londresâ†’NY
input double InpLondonStrengthMin = 1.2;     // Fuerza mÃ­nima Londres (ATR)

input group "â•â•â• SCALPING TRAILING â•â•â•"
input bool   InpUseScalpingTrail = false;    // Trailing scalping (opcional)
input int    InpScalpTrailDistance = 5;      // Distancia trailing scalping

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// PATRONES DE VELAS + IA
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
input group "â•â•â• PATRONES DE VELAS â•â•â•"
input bool   InpUseCandlePatterns = true;    // Activar patrones de velas
input int    InpMinPatternScore = 70;        // Score mÃ­nimo del patrÃ³n
input bool   InpRequirePatternConfirmation = true; // Requiere confirmaciÃ³n

input group "â•â•â• INTELIGENCIA ARTIFICIAL â•â•â•"
input bool   InpUseAdaptiveLearning = true;  // Aprendizaje adaptativo
input int    InpMinLearningTrades = 50;      // Trades mÃ­nimos para aprender
input double InpMinPatternWinRate = 50.0;    // Win rate mÃ­nimo del patrÃ³n
input bool   InpUseIntelligentScoring = true; // Scoring inteligente
input int    InpMinIntelligentScore = 85;    // Score inteligente mÃ­nimo (AUMENTADO)

input group "â•â•â• FILTROS INTELIGENTES â•â•â•"
input bool   InpUseMarketRegimeFilter = true;  // Filtro de rÃ©gimen de mercado
input bool   InpUseOrderFlowFilter = true;     // Filtro de order flow
input bool   InpUseAdaptiveRisk = true;        // Riesgo adaptativo
input bool   InpUseSmartExit = true;           // Salidas inteligentes
input int    InpMaxHoursInTrade = 2;           // MÃ¡x horas sin alcanzar 50% TP
input double InpMinADX = 15.0;                 // ADX mÃ­nimo para operar
input double InpMinVolatility = 0.7;           // Volatilidad mÃ­nima (ATR ratio)
input double InpMaxVolatility = 2.0;           // Volatilidad mÃ¡xima (ATR ratio)
input double InpMinOrderFlowBuy = 1.2;         // Imbalance mÃ­nimo para compra
input double InpMaxOrderFlowSell = 0.83;       // Imbalance mÃ¡ximo para venta

input group "â•â•â• MEJORAS AVANZADAS â•â•â•"
input bool   InpUseConfluenceScoring = true;   // Scoring por confluencia
input int    InpMinConfluenceFactors = 5;      // Factores mÃ­nimos (de 10)
input bool   InpUseDynamicSL = true;           // Stop Loss dinÃ¡mico
input double InpSLMultiplier = 2.0;            // Multiplicador SL (ATR)
input bool   InpUsePartialProfits = true;      // Toma parcial de ganancias
input bool   InpUseCorrelationFilter = true;   // Filtro de correlaciÃ³n
input int    InpMinMinutesBetweenTrades = 30;  // Minutos entre trades similares

input group "â•â•â• MEJORAS Ã‰LITE (MASTER) â•â•â•"
input bool   InpUseTrendStrengthFilter = true; // Filtro de fuerza de tendencia
input double InpMinTrendStrength = 0.6;        // Fuerza mÃ­nima (0-1)
input bool   InpUseNewsFilter = true;          // Evitar operar cerca de noticias
input int    InpNewsAvoidMinutes = 30;         // Minutos antes/despuÃ©s de noticias
input bool   InpUseSessionFilter = true;       // Filtro de sesiÃ³n Ã³ptima
input bool   InpTradeOnlyBestHours = true;     // Solo mejores horas (8-12, 13-17 GMT)
input bool   InpUseDrawdownProtection = true;  // ProtecciÃ³n adicional de drawdown
input double InpMaxDrawdownForDay = 2.0;       // Drawdown mÃ¡ximo diario %

input group "═══ MEJORAS ULTRA (GENIUS) ═══"
input bool   InpUseVolumeProfile = true;       // Análisis de Volume Profile
input bool   InpUseLiquiditySweep = true;      // Detectar barridos de liquidez
input bool   InpUseDayOfWeekFilter = true;     // Filtro por día de semana
input bool   InpUseMultiPatternConfluence = true; // Confluencia multi-patrón
input int    InpVolumeProfileBars = 100;       // Barras para Volume Profile
input double InpMinLiquiditySweepPips = 15;    // Pips mínimos para sweep

input group "â•â•â• ESTADÃSTICAS â•â•â•"
input bool   InpSaveStatistics = true;       // Guardar estadÃ­sticas
input bool   InpPrintLearningStats = true;   // Imprimir estadÃ­sticas

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// ESTRUCTURAS DE DATOS ADICIONALES (IA)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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

// EstadÃ­sticas por patrÃ³n
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

// EstadÃ­sticas por hora
struct SHourStats {
   int hour;
   int totalTrades;
   int wins;
   double winRate;
   double totalProfit;
};

// Estadísticas por día de semana
struct SDayStats {
   int dayOfWeek;
   int totalTrades;
   int wins;
   double winRate;
   double totalProfit;
};

// Volume Profile
struct SVolumeNode {
   double priceLevel;
   long volume;
};

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// GLOBALES
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

// SesiÃ³n Londres
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

// Memoria y estadÃ­sticas IA
STradeMemory tradeHistory[];
int historyCount = 0;
SPatternStats patternStats[30];
int patternCount = 0;
SHourStats hourStats[24];

SDayStats dayStats[7];

// Volume Profile
SVolumeNode volumeProfile[];
int volumeProfileSize = 0;
double pocPrice = 0; // Point of Control

// Liquidity Sweep
double lastHighSweep = 0;
double lastLowSweep = 0;
datetime lastSweepTime = 0;

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
   
   // Inicializar estadÃ­sticas por hora
   for(int i = 0; i < 24; i++)
   {
      hourStats[i].hour = i;
      hourStats[i].totalTrades = 0;
      hourStats[i].wins = 0;
      hourStats[i].winRate = 50.0;
      hourStats[i].totalProfit = 0;
   }
      // Inicializar estadísticas por día
   for(int i = 0; i < 7; i++)
   {
      dayStats[i].dayOfWeek = i;
      dayStats[i].totalTrades = 0;
      dayStats[i].wins = 0;
      dayStats[i].winRate = 50.0;
      dayStats[i].totalProfit = 0;
   }

   // Cargar historial si existe
   if(InpUseAdaptiveLearning)
      LoadTradeHistory();
   
   Print("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—");
   Print("â•‘      QUANTUM MASTER EA - MÃ¡xima Inteligencia v4.0        â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  Base: QUANTUM Mean Reversion                             â•‘");
   Print("â•‘  MTF: ", InpUseMTF ? "ON" : "OFF", " | NY Breakout: ", InpUseNYBreakout ? "ON" : "OFF", "                      â•‘");
   Print("â•‘  Akali: ", InpUseAkaliTrailing ? "ON" : "OFF", " | VWAP: ", InpUseVWAP ? "ON" : "OFF", "                    â•‘");
   Print("â•‘  Structure: ", InpUseStructure ? "ON" : "OFF", " | Pivots: ", InpUsePivots ? "ON" : "OFF", "                  â•‘");
   Print("â•‘  Patterns: ", InpUseCandlePatterns ? "ON" : "OFF", " | AI Learning: ", InpUseAdaptiveLearning ? "ON" : "OFF", "          â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  â˜… FILTROS INTELIGENTES:                                  â•‘");
   Print("â•‘  Market Regime: ", InpUseMarketRegimeFilter ? "ON" : "OFF", " | Order Flow: ", InpUseOrderFlowFilter ? "ON" : "OFF", "            â•‘");
   Print("â•‘  Adaptive Risk: ", InpUseAdaptiveRisk ? "ON" : "OFF", " | Smart Exit: ", InpUseSmartExit ? "ON" : "OFF", "              â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  â­ MEJORAS AVANZADAS:                                    â•‘");
   Print("â•‘  Confluence: ", InpUseConfluenceScoring ? "ON" : "OFF", " (Min: ", InpMinConfluenceFactors, "/10)                  â•‘");
   Print("â•‘  Dynamic SL: ", InpUseDynamicSL ? "ON" : "OFF", " | Partial Profits: ", InpUsePartialProfits ? "ON" : "OFF", "          â•‘");
   Print("â•‘  Correlation Filter: ", InpUseCorrelationFilter ? "ON" : "OFF", "                            â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  ðŸ† MEJORAS Ã‰LITE (MASTER):                               â•‘");
   Print("â•‘  Trend Strength: ", InpUseTrendStrengthFilter ? "ON" : "OFF", " (Min: ", DoubleToString(InpMinTrendStrength, 1), ")              â•‘");
   Print("â•‘  News Filter: ", InpUseNewsFilter ? "ON" : "OFF", " | Session Filter: ", InpUseSessionFilter ? "ON" : "OFF", "            â•‘");
   Print("â•‘  DD Protection: ", InpUseDrawdownProtection ? "ON" : "OFF", " (Max: ", DoubleToString(InpMaxDrawdownForDay, 1), "%)            â•‘");
   Print("â•‘  Best Hours Only: ", InpTradeOnlyBestHours ? "YES" : "NO", "                                â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  🚀 MEJORAS ULTRA (GENIUS):                               ║");
   Print("║  Volume Profile: ", InpUseVolumeProfile ? "ON" : "OFF", " | Liquidity Sweep: ", InpUseLiquiditySweep ? "ON" : "OFF", "        ║");
   Print("║  Day Filter: ", InpUseDayOfWeekFilter ? "ON" : "OFF", " | Multi-Pattern: ", InpUseMultiPatternConfluence ? "ON" : "OFF", "            ║");
   Print("â•‘  Trades en memoria: ", historyCount, "                                â•‘");
   Print("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Guardar historial
   if(InpSaveStatistics && InpUseAdaptiveLearning)
      SaveTradeHistory();
   
   // Imprimir estadÃ­sticas finales
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
      // MEJORA 15: Actualizar Volume Profile
   if(InpUseVolumeProfile) UpdateVolumeProfile();
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   if(!PassProtectionFilters()) return;
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // MEJORA 1: FILTRO DE RÃ‰GIMEN DE MERCADO
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   if(!PassMarketRegimeFilter()) return;
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // MEJORAS Ã‰LITE: FILTROS ADICIONALES
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   
   // Filtro de fuerza de tendencia
   if(!PassTrendStrengthFilter()) return;
   
   // Filtro de noticias
   if(IsNearNewsTime())
   {
      Print("âŠ— FILTRO NOTICIAS: Evitando operar cerca de noticias");
      return;
   }
   
   // Filtro de sesiÃ³n
   if(!PassSessionFilter()) return;
      // MEJORA 17: Filtro por día de semana
   if(!PassDayOfWeekFilter()) return;

   // ProtecciÃ³n de drawdown avanzada
   if(!PassDrawdownProtection()) return;
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // ANÃLISIS MULTI-TIMEFRAME
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   int mtfAlignment = 0;
   if(InpUseMTF && InpRequireMTFAlignment)
   {
      if(!CheckMTFAlignment(mtfAlignment))
         return;
   }
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // DETECCIÃ“N DE PATRONES DE VELAS
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   string candlePattern = "NONE";
   int patternScore = 0;
   int patternSignal = 0;
   
   if(InpUseCandlePatterns)
   {
      patternSignal = DetectCandlePattern(candlePattern, patternScore);
      
      // Filtro por score mÃ­nimo
      if(patternScore > 0 && patternScore < InpMinPatternScore)
      {
         Print("âŠ— PatrÃ³n ", candlePattern, " score bajo: ", patternScore);
         patternSignal = 0;
      }
      
      // Filtro por aprendizaje
      if(InpUseAdaptiveLearning && historyCount >= InpMinLearningTrades && patternSignal != 0)
      {
         if(!IsPatternProfitable(candlePattern))
         {
            Print("âŠ— PatrÃ³n ", candlePattern, " no rentable (WR: ", 
                  DoubleToString(GetPatternWinRate(candlePattern), 1), "%)");
            patternSignal = 0;
         }
      }
   }
   
      // MEJORA 18: Multi-Pattern Confluence
   if(InpUseMultiPatternConfluence && patternSignal != 0)
   {
      if(!CheckMultiPatternConfluence(patternSignal))
      {
         Print("⊗ MULTI-PATTERN: Sin confluencia de múltiples patrones");
         return;
      }
   }

   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // SCORING INTELIGENTE
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   int intelligentScore = 50;
   if(InpUseIntelligentScoring && patternSignal != 0)
   {
      intelligentScore = CalculateIntelligentScore(candlePattern, patternScore, mtfAlignment);
      
      if(intelligentScore < InpMinIntelligentScore)
      {
         Print("âŠ— Score inteligente bajo: ", intelligentScore, " (min: ", InpMinIntelligentScore, ")");
         return;
      }
      
      // Destacar seÃ±ales premium
      if(intelligentScore >= 95)
      {
         Print("â˜…â˜…â˜… SEÃ‘AL PREMIUM: Score ", intelligentScore, " â˜…â˜…â˜…");
      }
   }
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // MEJORA AVANZADA: CONFLUENCE SCORING
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   int confluenceScore = 0;
   if(InpUseConfluenceScoring && patternSignal != 0)
   {
      int pivotSignal = InpUsePivots ? AnalyzePivotSignals() : 0;
      double orderFlowImbalance = CalculateOrderFlowImbalance(10);
      
      confluenceScore = CalculateConfluenceScore(candlePattern, patternScore, mtfAlignment,
                                                  orderFlowImbalance, pivotSignal, patternSignal);
      
      // MEJORA Ã‰LITE: Aumentar requisito despuÃ©s de pÃ©rdidas
      int minRequired = InpMinConfluenceFactors;
      if(consecutiveLosses >= 2)
      {
         minRequired = InpMinConfluenceFactors + 1; // Requiere 1 factor mÃ¡s
         Print("âš  Modo conservador: Requiere ", minRequired, " factores (pÃ©rdidas consecutivas: ", consecutiveLosses, ")");
      }
      
      if(confluenceScore < minRequired)
      {
         Print("âŠ— CONFLUENCIA INSUFICIENTE: ", confluenceScore, "/10 factores (mÃ­n: ", 
               minRequired, ")");
         return;
      }
      
      Print("âœ… CONFLUENCIA EXCELENTE: ", confluenceScore, "/10 factores â­â­â­");
   }
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // PRIORIDAD 1: NY BREAKOUT
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   if(InpUseNYBreakout)
   {
      int breakoutSignal = AnalyzeNYBreakout();
      if(breakoutSignal != 0)
      {
         // MEJORA 2: Filtro de Order Flow
         if(!PassOrderFlowFilter(breakoutSignal))
            return;
         
         // Confirmar con patrÃ³n si estÃ¡ disponible
         if(InpRequirePatternConfirmation && InpUseCandlePatterns)
         {
            if(patternSignal == 0 || patternSignal != breakoutSignal)
            {
               Print("âŠ— NY Breakout sin confirmaciÃ³n de patrÃ³n");
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
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // PRIORIDAD 2: PIVOT SIGNALS
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // PRIORIDAD 3: MEAN REVERSION + PATRONES
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   int mrSignal = AnalyzeMeanReversion();
   
   // Si hay patrÃ³n, debe coincidir con MR
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
      // MR sin patrÃ³n
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
         Print("â–º Nuevo dÃ­a - Sistema reactivado");
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
            
            // Extraer informaciÃ³n del trade para actualizar memoria
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
               
               // Actualizar el Ãºltimo trade en memoria con el resultado
               if(historyCount > 0)
               {
                  tradeHistory[historyCount - 1].profit = profit;
                  tradeHistory[historyCount - 1].isWin = (profit > 0);
                  tradeHistory[historyCount - 1].exitPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
                  
                  UpdatePatternStats(pattern, profit > 0, profit);
                  
                  MqlDateTime dt;
                  TimeToStruct(tradeHistory[historyCount - 1].time, dt);
                  UpdateHourStats(dt.hour, profit > 0, profit);
                  UpdateDayStats(dt.day_of_week, profit > 0, profit);

               }
            }
            
            if(profit > 0)
            {
               totalWins++;
               consecutiveLosses = 0;
               if(isPaused) isPaused = false;
               
               Print("âœ“ WIN | ", totalWins, "W-", totalLosses, "L | WR: ", 
                     DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%");
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("âš  PAUSADO - ", consecutiveLosses, " pÃ©rdidas consecutivas");
               }
               
               Print("âœ— LOSS | ", totalWins, "W-", totalLosses, "L | Consecutive: ", consecutiveLosses);
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
      Print("âŠ— PÃ©rdida diaria: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdownPercent)
   {
      Print("âŠ— Drawdown: ", DoubleToString(dd, 2), "%");
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
   // Analizar D1, H4, H1 para alineaciÃ³n
   int trendD1 = GetTrend(PERIOD_D1);
   int trendH4 = GetTrend(PERIOD_H4);
   int trendH1 = GetTrend(PERIOD_H1);
   
   alignment = 0;
   if(trendD1 > 0) alignment++;
   if(trendH4 > 0) alignment++;
   if(trendH1 > 0) alignment++;
   
   // AlineaciÃ³n alcista: todos > 0
   if(trendD1 > 0 && trendH4 > 0 && trendH1 > 0)
   {
      Print("â–º MTF Alineado ALCISTA (D1/H4/H1)");
      return true;
   }
   
   // AlineaciÃ³n bajista: todos < 0
   if(trendD1 < 0 && trendH4 < 0 && trendH1 < 0)
   {
      alignment = -3;
      Print("â–¼ MTF Alineado BAJISTA (D1/H4/H1)");
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
   
   // Verificar que Londres ya cerrÃ³
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
   
   // BREAKOUT ALCISTA: Rompe mÃ¡ximo de Londres
   if(high1 > londonSession.high)
   {
      // ConfirmaciÃ³n: vela alcista fuerte
      double range = high1 - low1;
      if(range > 0 && (close1 - low1) > range * 0.7)
      {
         // Continuidad de Londres
         if(InpUseLondonContinuity && londonSession.isBullish && londonSession.strength > InpLondonStrengthMin)
         {
            Print("â–º NY BREAKOUT ALCISTA | Londres continuidad | Vol:", vol1);
            return 1;
         }
         else if(!InpUseLondonContinuity)
         {
            Print("â–º NY BREAKOUT ALCISTA | Vol:", vol1);
            return 1;
         }
      }
   }
   
   // BREAKOUT BAJISTA: Rompe mÃ­nimo de Londres
   if(low1 < londonSession.low)
   {
      double range = high1 - low1;
      if(range > 0 && (high1 - close1) > range * 0.7)
      {
         if(InpUseLondonContinuity && !londonSession.isBullish && londonSession.strength > InpLondonStrengthMin)
         {
            Print("â–¼ NY BREAKOUT BAJISTA | Londres continuidad | Vol:", vol1);
            return -1;
         }
         else if(!InpUseLondonContinuity)
         {
            Print("â–¼ NY BREAKOUT BAJISTA | Vol:", vol1);
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
      
      Print("Londres cerrÃ³ | ", londonSession.isBullish ? "Alcista" : "Bajista", 
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
   
   // Calcular VWAP desde inicio del dÃ­a
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime todayStart = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                       IntegerToString(timeStruct.mon) + "." + 
                                       IntegerToString(timeStruct.day));
   
   int bars = Bars(_Symbol, PERIOD_M5, todayStart, TimeCurrent());
   
   for(int i = 1; i <= MathMin(bars, 288); i++) // Max 288 velas M5 en un dÃ­a
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
         Print("âŠ— VWAP: Precio muy por debajo (", price, " vs ", currentVWAP, ")");
         return false;
      }
   }
   
   // Venta: precio debe estar cerca o por debajo de VWAP
   if(direction < 0)
   {
      if(price > currentVWAP + deviation)
      {
         Print("âŠ— VWAP: Precio muy por encima (", price, " vs ", currentVWAP, ")");
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
   
   // BOS Alcista: rompe Ãºltimo swing high
   if(!lastSwingHigh.broken && close1 > lastSwingHigh.price)
   {
      lastSwingHigh.broken = true;
      Print("â–º BOS ALCISTA | Precio: ", close1, " > Swing High: ", lastSwingHigh.price);
   }
   
   // BOS Bajista: rompe Ãºltimo swing low
   if(!lastSwingLow.broken && close1 < lastSwingLow.price)
   {
      lastSwingLow.broken = true;
      Print("â–¼ BOS BAJISTA | Precio: ", close1, " < Swing Low: ", lastSwingLow.price);
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
   
   // Falla alcista: rompiÃ³ swing high pero retrocediÃ³ y rompiÃ³ swing low
   if(direction > 0 && lastSwingHigh.broken && !lastSwingLow.broken)
   {
      double close1 = iClose(_Symbol, PERIOD_M5, 1);
      if(close1 < lastSwingLow.price)
      {
         Print("âš  FALLA ESTRUCTURA ALCISTA - ReversiÃ³n bajista probable");
         return true;
      }
   }
   
   // Falla bajista: rompiÃ³ swing low pero retrocediÃ³ y rompiÃ³ swing high
   if(direction < 0 && lastSwingLow.broken && !lastSwingHigh.broken)
   {
      double close1 = iClose(_Symbol, PERIOD_M5, 1);
      if(close1 > lastSwingHigh.price)
      {
         Print("âš  FALLA ESTRUCTURA BAJISTA - ReversiÃ³n alcista probable");
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
   // Calcular pivotes del dÃ­a anterior
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
         Print("â–º PIVOT BOUNCE S1 | Precio: ", close1);
         return 1;
      }
      // S2
      if(low1 <= S2 + tolerance && close1 > open1 && close1 > S2)
      {
         Print("â–º PIVOT BOUNCE S2 | Precio: ", close1);
         return 1;
      }
   }
   
   // REBOTE EN RESISTENCIA (R1, R2, R3)
   if(InpTradePivotBounce)
   {
      // R1
      if(high1 >= R1 - tolerance && close1 < open1 && close1 < R1)
      {
         Print("â–¼ PIVOT BOUNCE R1 | Precio: ", close1);
         return -1;
      }
      // R2
      if(high1 >= R2 - tolerance && close1 < open1 && close1 < R2)
      {
         Print("â–¼ PIVOT BOUNCE R2 | Precio: ", close1);
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
         Print("â–º PIVOT BREAKOUT R1 | Precio: ", close1);
         return 1;
      }
      
      // Breakout bajista de S1
      if(close2 >= S1 && close1 < S1 && close1 < open1)
      {
         Print("â–¼ PIVOT BREAKOUT S1 | Precio: ", close1);
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
            Print("â–º MEAN REVERSION COMPRA | RSI: ", DoubleToString(rsi, 1));
            return 1;
         }
      }
   }
   
   // SeÃ±al extrema compra
   if(rsi < 25 && close1 < lowerBand && close1 > open1)
   {
      if(CheckVWAPAlignment(1))
      {
         Print("â–º MR COMPRA EXTREMA | RSI: ", DoubleToString(rsi, 1));
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
            Print("â–¼ MEAN REVERSION VENTA | RSI: ", DoubleToString(rsi, 1));
            return -1;
         }
      }
   }
   
   // SeÃ±al extrema venta
   if(rsi > 75 && close1 > upperBand && close1 < open1)
   {
      if(CheckVWAPAlignment(-1))
      {
         Print("â–¼ MR VENTA EXTREMA | RSI: ", DoubleToString(rsi, 1));
         return -1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
// EJECUCIÃ“N DE OPERACIONES
//+------------------------------------------------------------------+
void ExecuteBuySignal(string signalType, string pattern = "NONE", int score = 50)
{
   // Verificar falla de estructura
   if(DetectStructureFailure(1)) return;
   
   // MEJORA AVANZADA: Filtro de correlaciÃ³n
   if(!PassCorrelationFilter(signalType, 1)) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // MEJORA AVANZADA: SL DinÃ¡mico
   double slPips = CalculateDynamicSL();
   double sl = ask - slPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("âŠ— Lote muy pequeÃ±o");
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
      
      // MEJORA AVANZADA: Actualizar tracking de correlaciÃ³n
      UpdateCorrelationTracking(signalType, 1);
      
      tradesThisDay++;
      Print("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—");
      Print("â•‘  âœ“ COMPRA | ", signalType, "                              â•‘");
      Print("â•‘  Lote: ", lots, " | SL: ", DoubleToString(slPips, 1), " | TP: ", InpTakeProfitPips, "          â•‘");
      Print("â•‘  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      â•‘");
      Print("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
   }
}

void ExecuteSellSignal(string signalType, string pattern = "NONE", int score = 50)
{
   if(DetectStructureFailure(-1)) return;
   
   // MEJORA AVANZADA: Filtro de correlaciÃ³n
   if(!PassCorrelationFilter(signalType, -1)) return;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // MEJORA AVANZADA: SL DinÃ¡mico
   double slPips = CalculateDynamicSL();
   double sl = bid + slPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("âŠ— Lote muy pequeÃ±o");
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
      
      // MEJORA AVANZADA: Actualizar tracking de correlaciÃ³n
      UpdateCorrelationTracking(signalType, -1);
      
      tradesThisDay++;
      Print("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—");
      Print("â•‘  âœ“ VENTA | ", signalType, "                               â•‘");
      Print("â•‘  Lote: ", lots, " | SL: ", DoubleToString(slPips, 1), " | TP: ", InpTakeProfitPips, "          â•‘");
      Print("â•‘  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      â•‘");
      Print("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
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
   
   Print("ðŸ’° Lote calculado: ", finalLots, " | Riesgo ajustado: ", DoubleToString(adjustedRisk, 3), "%");
   
   return finalLots;
}

//+------------------------------------------------------------------+
// GESTIÃ“N DE POSICIONES CON TRAILING AKALI + SMART EXIT
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
      
      // Si la posiciÃ³n fue cerrada, continuar con la siguiente
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
         Print("â–º Akali L1: Breakeven +5 pips");
         return;
      }
      else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
      {
         trade.PositionModify(ticket, breakeven, currentTP);
         Print("â–¼ Akali L1: Breakeven +5 pips");
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
         Print("â–º Akali L2: SL asegurado +10 pips");
         return;
      }
      else if(!isBuy && (currentSL == 0 || secureSL < currentSL))
      {
         trade.PositionModify(ticket, secureSL, currentTP);
         Print("â–¼ Akali L2: SL asegurado +10 pips");
         return;
      }
   }
   
   // NIVEL 3: Trailing basado en estructura
   if(profitPips > InpAkaliLevel3)
   {
      double structureSL;
      
      if(isBuy)
      {
         // Usar Ãºltimo swing low como SL
         structureSL = lastSwingLow.price + 2 * 10 * point;
         if(structureSL > currentSL && structureSL < currentPrice)
         {
            trade.PositionModify(ticket, structureSL, currentTP);
            Print("â–º Akali L3: Trailing estructura | SL: ", structureSL);
         }
      }
      else
      {
         // Usar Ãºltimo swing high como SL
         structureSL = lastSwingHigh.price - 2 * 10 * point;
         if((currentSL == 0 || structureSL < currentSL) && structureSL > currentPrice)
         {
            trade.PositionModify(ticket, structureSL, currentTP);
            Print("â–¼ Akali L3: Trailing estructura | SL: ", structureSL);
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
            Print("â–º Scalp Trail: -", InpScalpTrailDistance, " pips | Profit: ", DoubleToString(profitPips, 1));
         }
      }
      else
      {
         newSL = currentPrice + trailDistance;
         if(currentSL == 0 || newSL < currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print("â–¼ Scalp Trail: +", InpScalpTrailDistance, " pips | Profit: ", DoubleToString(profitPips, 1));
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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DETECCIÃ“N DE PATRONES DE VELAS (17 PATRONES)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
   double minBody = 10 * 10 * point; // MÃ­nimo 10 pips
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // PATRONES ALCISTAS
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   
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
   
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   // PATRONES BAJISTAS
   // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
   
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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SISTEMA DE APRENDIZAJE E INTELIGENCIA
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
   
   // Factor 1: Score del patrÃ³n base
   score += (patternScore - 75) / 2;
   
   // Factor 2: Win rate histÃ³rico del patrÃ³n
   if(historyCount >= InpMinLearningTrades)
   {
      double wr = GetPatternWinRate(pattern);
      score += (int)((wr - 50) * 0.4);
   }
   
   // Factor 3: Hora del dÃ­a
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
void UpdateDayStats(int dayOfWeek, bool isWin, double profit)
{
   dayStats[dayOfWeek].totalTrades++;
   if(isWin) dayStats[dayOfWeek].wins++;
   dayStats[dayOfWeek].totalProfit += profit;
   dayStats[dayOfWeek].winRate = (double)dayStats[dayOfWeek].wins / dayStats[dayOfWeek].totalTrades * 100.0;
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
      Print("ðŸ“Š ", pattern, " | Trades: ", patternStats[index].totalTrades,
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
   Print("âœ“ Historial cargado: ", historyCount, " trades");
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
   Print("âœ“ Historial guardado: ", historyCount, " trades");
}

void PrintFinalStatistics()
{
   Print("â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—");
   Print("â•‘           ESTADÃSTICAS FINALES - QUANTUM AI               â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  Total Trades: ", historyCount, "                                      â•‘");
   Print("â•‘  Win Rate Global: ", DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%                          â•‘");
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  PATRONES MÃS RENTABLES:                                  â•‘");
   
   for(int i = 0; i < patternCount; i++)
   {
      if(patternStats[i].totalTrades >= 5)
      {
         Print("â•‘  ", patternStats[i].name, " | ", patternStats[i].totalTrades, " trades | WR: ",
               DoubleToString(patternStats[i].winRate, 1), "% | PF: ",
               DoubleToString(patternStats[i].profitFactor, 2), "  â•‘");
      }
   }
   
   Print("â• â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•£");
   Print("â•‘  MEJORES HORAS:                                           â•‘");
   
   for(int h = 0; h < 24; h++)
   {
      if(hourStats[h].totalTrades >= 5)
      {
         Print("â•‘  ", h, ":00 GMT | ", hourStats[h].totalTrades, " trades | WR: ",
               DoubleToString(hourStats[h].winRate, 1), "%  â•‘");
      }
   }
   
   Print("â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA 1: MARKET REGIME DETECTION (ADX + VOLATILITY)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
   
   // Filtro 1: ADX muy bajo = mercado sin direcciÃ³n
   if(adx < InpMinADX)
   {
      Print("âŠ— FILTRO RÃ‰GIMEN: ADX bajo (", DoubleToString(adx, 1), ") - Mercado sin direcciÃ³n");
      return false;
   }
   
   // Filtro 2: Volatilidad muy baja = movimientos falsos
   if(volRatio < InpMinVolatility)
   {
      Print("âŠ— FILTRO RÃ‰GIMEN: Volatilidad baja (", DoubleToString(volRatio, 2), "x) - Evitar operar");
      return false;
   }
   
   // Filtro 3: Volatilidad extrema = riesgo alto
   if(volRatio > InpMaxVolatility)
   {
      Print("âŠ— FILTRO RÃ‰GIMEN: Volatilidad extrema (", DoubleToString(volRatio, 2), "x) - Demasiado riesgo");
      return false;
   }
   
   Print("âœ“ FILTRO RÃ‰GIMEN: OK | ADX: ", DoubleToString(adx, 1), " | Vol: ", DoubleToString(volRatio, 2), "x");
   return true;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA 2: ORDER FLOW ANALYSIS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
   
   // SeÃ±al de compra
   if(signalDirection == 1)
   {
      if(imbalance < InpMinOrderFlowBuy)
      {
         Print("âŠ— FILTRO ORDER FLOW: Compra rechazada | Imbalance: ", DoubleToString(imbalance, 2), 
               " (mÃ­n: ", DoubleToString(InpMinOrderFlowBuy, 2), ")");
         return false;
      }
      Print("âœ“ FILTRO ORDER FLOW: Compra OK | PresiÃ³n compradora: ", DoubleToString(imbalance, 2));
   }
   
   // SeÃ±al de venta
   if(signalDirection == -1)
   {
      if(imbalance > InpMaxOrderFlowSell)
      {
         Print("âŠ— FILTRO ORDER FLOW: Venta rechazada | Imbalance: ", DoubleToString(imbalance, 2),
               " (mÃ¡x: ", DoubleToString(InpMaxOrderFlowSell, 2), ")");
         return false;
      }
      Print("âœ“ FILTRO ORDER FLOW: Venta OK | PresiÃ³n vendedora: ", DoubleToString(imbalance, 2));
   }
   
   return true;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA 3: ADAPTIVE RISK MANAGEMENT
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
   
   // Factor 2: PÃ©rdidas consecutivas
   if(consecutiveLosses >= 2) multiplier *= 0.6;
   else if(consecutiveLosses >= 1) multiplier *= 0.8;
   
   // Factor 3: Volatilidad
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   if(avgATR > 0 && atr > avgATR * 1.5) multiplier *= 0.7;
   
   // Limitar multiplicador
   if(multiplier < 0.5) multiplier = 0.5;
   if(multiplier > 1.5) multiplier = 1.5;
   
   Print("ðŸŽ¯ Multiplicador de Riesgo: ", DoubleToString(multiplier, 2), 
         " | WR reciente: ", DoubleToString(recentWR, 1), "%",
         " | PÃ©rdidas consecutivas: ", consecutiveLosses);
   
   return multiplier;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA 4: SMART EXIT MANAGEMENT
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

void ApplySmartExitLogic(ulong ticket, bool isBuy, double openPrice, datetime openTime, 
                         double currentPrice, double profitPips)
{
   if(!InpUseSmartExit) return;
   
   // Salida 1: Tiempo sin alcanzar 50% TP
   int hoursOpen = (int)((TimeCurrent() - openTime) / 3600);
   double halfTP = InpTakeProfitPips / 2.0;
   
   if(hoursOpen >= InpMaxHoursInTrade && profitPips < halfTP)
   {
      Print("â° SALIDA INTELIGENTE: ", hoursOpen, " horas sin alcanzar 50% TP (", 
            DoubleToString(profitPips, 1), " pips)");
      trade.PositionClose(ticket);
      return;
   }
   
   // Salida 2: Viernes 15:00 GMT
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 5 && dt.hour >= 15)
   {
      Print("ðŸ“… SALIDA INTELIGENTE: Viernes 15:00 GMT - Cerrando posiciÃ³n");
      trade.PositionClose(ticket);
      return;
   }
   
   // Salida 3: PatrÃ³n opuesto fuerte
   string oppositePattern = "";
   int oppositeScore = 0;
   int oppositeSignal = DetectCandlePattern(oppositePattern, oppositeScore);
   
   if(isBuy && oppositeSignal == -1 && oppositeScore >= 85)
   {
      Print("ðŸ”„ SALIDA INTELIGENTE: PatrÃ³n bajista fuerte (", oppositePattern, 
            " score: ", oppositeScore, ") - Cerrando compra");
      trade.PositionClose(ticket);
      return;
   }
   
   if(!isBuy && oppositeSignal == 1 && oppositeScore >= 85)
   {
      Print("ðŸ”„ SALIDA INTELIGENTE: PatrÃ³n alcista fuerte (", oppositePattern,
            " score: ", oppositeScore, ") - Cerrando venta");
      trade.PositionClose(ticket);
      return;
   }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA AVANZADA 1: CONFLUENCE SCORING
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

int CalculateConfluenceScore(string pattern, int patternScore, int mtfAlign, 
                             double orderFlowImbalance, int pivotSignal, int direction)
{
   if(!InpUseConfluenceScoring) return 10; // Si no usa confluencia, retornar alto
   
   int confluence = 0;
   
   // Factor 1: PatrÃ³n fuerte (score â‰¥85)
   if(patternScore >= 85)
   {
      confluence++;
      Print("  âœ“ Factor 1: PatrÃ³n fuerte (", pattern, " score: ", patternScore, ")");
   }
   
   // Factor 2: MTF Alignment (3 timeframes alineados)
   if(MathAbs(mtfAlign) == 3)
   {
      confluence++;
      Print("  âœ“ Factor 2: MTF alineado (", mtfAlign, " timeframes)");
   }
   
   // Factor 3: VWAP Alignment
   if(InpUseVWAP && currentVWAP > 0)
   {
      double price = iClose(_Symbol, PERIOD_M5, 1);
      double distance = MathAbs(price - currentVWAP) / currentVWAP * 100;
      if(distance < 0.15)
      {
         confluence++;
         Print("  âœ“ Factor 3: Cerca de VWAP (", DoubleToString(distance, 3), "%)");
      }
   }
   
   // Factor 4: Pivot Signal
   if(pivotSignal != 0)
   {
      confluence++;
      Print("  âœ“ Factor 4: SeÃ±al de Pivot");
   }
   
   // Factor 5: Order Flow fuerte
   if((direction == 1 && orderFlowImbalance > 1.5) || 
      (direction == -1 && orderFlowImbalance < 0.67))
   {
      confluence++;
      Print("  âœ“ Factor 5: Order Flow fuerte (", DoubleToString(orderFlowImbalance, 2), ")");
   }
   
   // Factor 6: Market Regime favorable
   double adx = CalculateADX(14);
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   double volRatio = avgATR > 0 ? atr / avgATR : 1.0;
   
   if(adx > 20 && volRatio > 0.9 && volRatio < 1.8)
   {
      confluence++;
      Print("  âœ“ Factor 6: RÃ©gimen favorable (ADX: ", DoubleToString(adx, 1), ")");
   }
   
   // Factor 7: RSI extremo
   double rsi = CalculateRSI(14, PERIOD_M5);
   if((direction == 1 && rsi < 35) || (direction == -1 && rsi > 65))
   {
      confluence++;
      Print("  âœ“ Factor 7: RSI extremo (", DoubleToString(rsi, 1), ")");
   }
   
   // Factor 8: Estructura rota
   if(InpUseStructure)
   {
      if((direction == 1 && lastSwingHigh.broken) || 
         (direction == -1 && lastSwingLow.broken))
      {
         confluence++;
         Print("  âœ“ Factor 8: Estructura rota (BOS)");
      }
   }
   
   // Factor 9: Hora premium (Londres o NY)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if((dt.hour >= 8 && dt.hour < 12) || (dt.hour >= 13 && dt.hour < 17))
   {
      confluence++;
      Print("  âœ“ Factor 9: Hora premium (", dt.hour, ":00 GMT)");
   }
   
   // Factor 10: Win Rate reciente alto
   double recentWR = GetRecentWinRate(10);
   if(recentWR > 55)
   {
      confluence++;
      Print("  âœ“ Factor 10: Win Rate reciente alto (", DoubleToString(recentWR, 1), "%)");
   }
   
   // Factor 11: Cerca del POC (Volume Profile)
   if(InpUseVolumeProfile)
   {
      double price = iClose(_Symbol, PERIOD_M5, 1);
      if(IsNearPOC(price, 0.0015))
      {
         confluence++;
         Print("  ✓ Factor 11: Cerca del POC");
      }
   }
   
   // Factor 12: Liquidity Sweep
   int sweepSignal = DetectLiquiditySweep();
   if(sweepSignal == direction)
   {
      confluence++;
      Print("  ✓ Factor 12: Liquidity Sweep detectado");
   }

   Print("📊 CONFLUENCIA TOTAL: ", confluence, "/12 factores alineados");
   return confluence;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA AVANZADA 2: DYNAMIC STOP LOSS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

double CalculateDynamicSL()
{
   if(!InpUseDynamicSL) return InpStopLossPips;
   
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateATR(50, PERIOD_M5);
   double volRatio = avgATR > 0 ? atr / avgATR : 1.0;
   
   double multiplier = InpSLMultiplier;
   
   // Ajustar multiplicador segÃºn volatilidad
   if(volRatio < 0.8)
      multiplier = InpSLMultiplier * 0.75;  // Baja vol: SL mÃ¡s ajustado
   else if(volRatio > 1.5)
      multiplier = InpSLMultiplier * 1.25;  // Alta vol: SL mÃ¡s amplio
   
   double slDistance = atr * multiplier;
   
   // Convertir a pips
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPips = slDistance / (10 * point);
   
   // Limitar entre 15 y 45 pips
   if(slPips < 15) slPips = 15;
   if(slPips > 45) slPips = 45;
   
   Print("ðŸ“ SL DinÃ¡mico: ", DoubleToString(slPips, 1), " pips | ATR: ", 
         DoubleToString(atr, 2), " | Vol Ratio: ", DoubleToString(volRatio, 2));
   
   return slPips;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA AVANZADA 3: PARTIAL PROFIT TAKING
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
            Print("ðŸ’° TP1: Cerrado 50% en ", DoubleToString(profitPips, 1), " pips");
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
            Print("ðŸ’° TP2: Cerrado 30% en ", DoubleToString(profitPips, 1), " pips");
            
            // Mover SL a breakeven + 10 pips para el 20% restante
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double newSL = openPrice + (isBuy ? 10 : -10) * 10 * point;
            trade.PositionModify(ticket, newSL, 0);
            Print("ðŸ”’ SL movido a breakeven +10 pips para el 20% restante");
         }
      }
   }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA AVANZADA 4: CORRELATION FILTER
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

bool PassCorrelationFilter(string signalType, int direction)
{
   if(!InpUseCorrelationFilter) return true;
   
   // Filtro 1: Ya hay trade abierto en misma direcciÃ³n
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         int posType = (int)PositionGetInteger(POSITION_TYPE);
         int posDirection = (posType == POSITION_TYPE_BUY) ? 1 : -1;
         
         if(posDirection == direction)
         {
            Print("âŠ— FILTRO CORRELACIÃ“N: Ya hay trade abierto en misma direcciÃ³n");
            return false;
         }
      }
   }
   
   // Filtro 2: SeÃ±al similar muy reciente
   if(signalType == lastSignalType && direction == lastDirection)
   {
      int minutesSince = (int)((TimeCurrent() - lastTradeTime) / 60);
      if(minutesSince < InpMinMinutesBetweenTrades)
      {
         Print("âŠ— FILTRO CORRELACIÃ“N: SeÃ±al similar hace ", minutesSince, " minutos (mÃ­n: ", 
               InpMinMinutesBetweenTrades, ")");
         return false;
      }
   }
   
   // Filtro 3: MÃ¡ximo 1 trade por tipo por dÃ­a
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
      Print("âŠ— FILTRO CORRELACIÃ“N: Ya hay ", tradesOfTypeToday, " trade(s) tipo ", signalType, " hoy");
      return false;
   }
   
   Print("âœ“ FILTRO CORRELACIÃ“N: OK");
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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA Ã‰LITE 1: TREND STRENGTH FILTER
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

double CalculateTrendStrength()
{
   // Calcular fuerza de tendencia usando mÃºltiples EMAs
   double ema20 = CalculateEMA(20, PERIOD_M5);
   double ema50 = CalculateEMA(50, PERIOD_M5);
   double ema100 = CalculateEMA(100, PERIOD_M5);
   double ema200 = CalculateEMA(200, PERIOD_M5);
   
   double price = iClose(_Symbol, PERIOD_M5, 1);
   
   // Calcular separaciÃ³n entre EMAs (normalizado)
   double range = iHigh(_Symbol, PERIOD_M5, 1) - iLow(_Symbol, PERIOD_M5, 1);
   if(range == 0) return 0;
   
   double separation = 0;
   separation += MathAbs(ema20 - ema50) / range;
   separation += MathAbs(ema50 - ema100) / range;
   separation += MathAbs(ema100 - ema200) / range;
   
   // Normalizar a 0-1
   double strength = separation / 3.0;
   if(strength > 1.0) strength = 1.0;
   
   // Verificar alineaciÃ³n
   bool bullishAlignment = (ema20 > ema50 && ema50 > ema100 && ema100 > ema200);
   bool bearishAlignment = (ema20 < ema50 && ema50 < ema100 && ema100 < ema200);
   
   if(!bullishAlignment && !bearishAlignment)
      strength *= 0.5; // Penalizar si no hay alineaciÃ³n clara
   
   return strength;
}

bool PassTrendStrengthFilter()
{
   if(!InpUseTrendStrengthFilter) return true;
   
   double trendStrength = CalculateTrendStrength();
   
   if(trendStrength < InpMinTrendStrength)
   {
      Print("âŠ— FILTRO TENDENCIA: Fuerza insuficiente (", DoubleToString(trendStrength, 2), 
            " < ", DoubleToString(InpMinTrendStrength, 2), ")");
      return false;
   }
   
   Print("âœ“ FILTRO TENDENCIA: Fuerza OK (", DoubleToString(trendStrength, 2), ")");
   return true;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA Ã‰LITE 2: NEWS FILTER
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

bool IsNearNewsTime()
{
   if(!InpUseNewsFilter) return false;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Horas tÃ­picas de noticias importantes (GMT)
   // 8:30 - Noticias UK
   // 12:30-14:30 - Noticias US (NFP, FOMC, etc)
   // 18:00 - Cierre de sesiÃ³n
   
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
         Print("âŠ— FILTRO NOTICIAS: Cerca de ventana de noticias (", dt.hour, ":", dt.min, " GMT)");
         return true;
      }
   }
   
   return false;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA Ã‰LITE 3: SESSION FILTER (Mejores Horas)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
      Print("âŠ— FILTRO SESIÃ“N: Fuera de horas Ã³ptimas (", hour, ":00 GMT)");
      return false;
   }
   
   // Verificar win rate por hora
   double hourWR = GetHourWinRate(hour);
   if(hourWR < 45.0 && historyCount >= InpMinLearningTrades)
   {
      Print("âŠ— FILTRO SESIÃ“N: Hora con bajo WR (", hour, ":00 = ", 
            DoubleToString(hourWR, 1), "%)");
      return false;
   }
   
   Print("âœ“ FILTRO SESIÃ“N: Hora Ã³ptima (", hour, ":00 GMT, WR: ", 
         DoubleToString(hourWR, 1), "%)");
   return true;
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MEJORA Ã‰LITE 4: DRAWDOWN PROTECTION AVANZADA
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

bool PassDrawdownProtection()
{
   if(!InpUseDrawdownProtection) return true;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyDD = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   
   if(dailyDD > InpMaxDrawdownForDay)
   {
      Print("âŠ— PROTECCIÃ“N DD: Drawdown diario excedido (", DoubleToString(dailyDD, 2), 
            "% > ", DoubleToString(InpMaxDrawdownForDay, 2), "%)");
      return false;
   }
   
   // ProtecciÃ³n adicional: Si hay 2+ pÃ©rdidas consecutivas, reducir agresividad
   if(consecutiveLosses >= 2)
   {
      // Solo operar con confluence score muy alto
      Print("âš  PROTECCIÃ“N DD: 2+ pÃ©rdidas consecutivas - Modo ultra-conservador");
      // Esta verificaciÃ³n se harÃ¡ en el confluence scoring
   }
   
   return true;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 15: VOLUME PROFILE ANALYSIS
// ═══════════════════════════════════════════════════════════════════

void UpdateVolumeProfile()
{
   if(!InpUseVolumeProfile) return;
   
   ArrayResize(volumeProfile, 0);
   volumeProfileSize = 0;
   
   double minPrice = DBL_MAX;
   double maxPrice = -DBL_MAX;
   
   // Encontrar rango de precios
   for(int i = 1; i <= InpVolumeProfileBars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      if(high > maxPrice) maxPrice = high;
      if(low < minPrice) minPrice = low;
   }
   
   if(maxPrice <= minPrice) return;
   
   // Dividir en 50 niveles
   int levels = 50;
   double priceStep = (maxPrice - minPrice) / levels;
   
   ArrayResize(volumeProfile, levels);
   
   // Acumular volumen por nivel
   for(int i = 1; i <= InpVolumeProfileBars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      long volume = iVolume(_Symbol, PERIOD_M5, i);
      
      // Distribuir volumen en niveles tocados
      for(int l = 0; l < levels; l++)
      {
         double levelPrice = minPrice + (l * priceStep);
         if(levelPrice >= low && levelPrice <= high)
         {
            volumeProfile[l].priceLevel = levelPrice;
            double range = high - low;
            if(range > 0)
               volumeProfile[l].volume += (long)(volume / (range / priceStep));
         }
      }
   }
   
   // Encontrar POC (Point of Control)
   long maxVol = 0;
   for(int l = 0; l < levels; l++)
   {
      if(volumeProfile[l].volume > maxVol)
      {
         maxVol = volumeProfile[l].volume;
         pocPrice = volumeProfile[l].priceLevel;
      }
   }
   
   volumeProfileSize = levels;
}

bool IsNearPOC(double price, double tolerance = 0.0015)
{
   if(pocPrice == 0) return false;
   double distance = MathAbs(price - pocPrice) / pocPrice;
   return (distance < tolerance);
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 16: LIQUIDITY SWEEP DETECTION
// ═══════════════════════════════════════════════════════════════════

int DetectLiquiditySweep()
{
   if(!InpUseLiquiditySweep) return 0;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minSweepDistance = InpMinLiquiditySweepPips * 10 * point;
   
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   
   // Buscar máximo reciente (últimas 20 barras)
   double recentHigh = high1;
   for(int i = 2; i <= 20; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      if(h > recentHigh) recentHigh = h;
   }
   
   // Buscar mínimo reciente
   double recentLow = low1;
   for(int i = 2; i <= 20; i++)
   {
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(l < recentLow) recentLow = l;
   }
   
   // SWEEP ALCISTA: Rompe mínimo y cierra por encima
   if(low1 < recentLow - minSweepDistance && close1 > open1 && close1 > recentLow)
   {
      if(MathAbs(low1 - lastLowSweep) > minSweepDistance || 
         (TimeCurrent() - lastSweepTime) > 3600)
      {
         lastLowSweep = low1;
         lastSweepTime = TimeCurrent();
         Print("💧 LIQUIDITY SWEEP ALCISTA | Barrió: ", recentLow, " | Cerró: ", close1);
         return 1;
      }
   }
   
   // SWEEP BAJISTA: Rompe máximo y cierra por debajo
   if(high1 > recentHigh + minSweepDistance && close1 < open1 && close1 < recentHigh)
   {
      if(MathAbs(high1 - lastHighSweep) > minSweepDistance || 
         (TimeCurrent() - lastSweepTime) > 3600)
      {
         lastHighSweep = high1;
         lastSweepTime = TimeCurrent();
         Print("💧 LIQUIDITY SWEEP BAJISTA | Barrió: ", recentHigh, " | Cerró: ", close1);
         return -1;
      }
   }
   
   return 0;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 17: DAY OF WEEK FILTER
// ═══════════════════════════════════════════════════════════════════

double GetDayWinRate(int dayOfWeek)
{
   if(dayStats[dayOfWeek].totalTrades < 5) return 50.0;
   return dayStats[dayOfWeek].winRate;
}

bool PassDayOfWeekFilter()
{
   if(!InpUseDayOfWeekFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dayOfWeek = dt.day_of_week;
   
   // Evitar lunes si tiene bajo WR
   if(dayOfWeek == 1 && historyCount >= InpMinLearningTrades)
   {
      double mondayWR = GetDayWinRate(1);
      if(mondayWR < 45.0)
      {
         Print("⊗ FILTRO DÍA: Lunes con bajo WR (", DoubleToString(mondayWR, 1), "%)");
         return false;
      }
   }
   
   // Evitar viernes después de las 12:00 GMT
   if(dayOfWeek == 5 && dt.hour >= 12)
   {
      Print("⊗ FILTRO DÍA: Viernes tarde - Evitar operar");
      return false;
   }
   
   // Verificar win rate del día actual
   double dayWR = GetDayWinRate(dayOfWeek);
   if(dayWR < 40.0 && historyCount >= InpMinLearningTrades)
   {
      string dayName[] = {"Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"};
      Print("⊗ FILTRO DÍA: ", dayName[dayOfWeek], " con bajo WR (", 
            DoubleToString(dayWR, 1), "%)");
      return false;
   }
   
   Print("✓ FILTRO DÍA: OK (día ", dayOfWeek, ", WR: ", DoubleToString(dayWR, 1), "%)");
   return true;
}

// ═══════════════════════════════════════════════════════════════════
// MEJORA 18: MULTI-PATTERN CONFLUENCE
// ═══════════════════════════════════════════════════════════════════

int DetectCandlePatternAtBar(int bar, string &patternName, int &score)
{
   double o = iOpen(_Symbol, PERIOD_M5, bar);
   double h = iHigh(_Symbol, PERIOD_M5, bar);
   double l = iLow(_Symbol, PERIOD_M5, bar);
   double c = iClose(_Symbol, PERIOD_M5, bar);
   
   double body = MathAbs(c - o);
   double range = h - l;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minBody = 10 * 10 * point;
   
   if(range == 0) return 0;
   
   // HAMMER
   if(c > o && body > minBody && body < range * 0.35)
   {
      double lowerShadow = o - l;
      double upperShadow = h - c;
      if(lowerShadow > body * 2.0 && upperShadow < body * 0.5)
      {
         patternName = "HAMMER";
         score = 85;
         return 1;
      }
   }
   
   // SHOOTING STAR
   if(c < o && body > minBody && body < range * 0.35)
   {
      double upperShadow = h - o;
      double lowerShadow = c - l;
      if(upperShadow > body * 2.0 && lowerShadow < body * 0.5)
      {
         patternName = "SHOOTING_STAR";
         score = 85;
         return -1;
      }
   }
   
   // BULLISH ENGULFING
   if(bar < Bars(_Symbol, PERIOD_M5) - 1)
   {
      double o2 = iOpen(_Symbol, PERIOD_M5, bar + 1);
      double c2 = iClose(_Symbol, PERIOD_M5, bar + 1);
      double body2 = MathAbs(c2 - o2);
      
      if(c2 < o2 && c > o && body > minBody && body2 > minBody)
      {
         if(c > o2 && o < c2)
         {
            patternName = "BULLISH_ENGULFING";
            score = 90;
            return 1;
         }
      }
      
      // BEARISH ENGULFING
      if(c2 > o2 && c < o && body > minBody && body2 > minBody)
      {
         if(c < o2 && o > c2)
         {
            patternName = "BEARISH_ENGULFING";
            score = 90;
            return -1;
         }
      }
   }
   
   patternName = "NONE";
   score = 0;
   return 0;
}

bool CheckMultiPatternConfluence(int direction)
{
   if(!InpUseMultiPatternConfluence) return true;
   
   int bullishPatterns = 0;
   int bearishPatterns = 0;
   
   // Analizar últimas 3 barras
   for(int bar = 1; bar <= 3; bar++)
   {
      string pattern = "";
      int score = 0;
      int signal = DetectCandlePatternAtBar(bar, pattern, score);
      
      if(signal == 1 && score >= 70) bullishPatterns++;
      if(signal == -1 && score >= 70) bearishPatterns++;
   }
   
   // Para compra: al menos 2 patrones alcistas
   if(direction == 1)
   {
      if(bullishPatterns >= 2 && bearishPatterns == 0)
      {
         Print("✓ MULTI-PATTERN: ", bullishPatterns, " patrones alcistas confirmados");
         return true;
      }
      else
      {
         Print("⊗ MULTI-PATTERN: Insuficiente confluencia alcista (", 
               bullishPatterns, " alcistas, ", bearishPatterns, " bajistas)");
         return false;
      }
   }
   
   // Para venta: al menos 2 patrones bajistas
   if(direction == -1)
   {
      if(bearishPatterns >= 2 && bullishPatterns == 0)
      {
         Print("✓ MULTI-PATTERN: ", bearishPatterns, " patrones bajistas confirmados");
         return true;
      }
      else
      {
         Print("⊗ MULTI-PATTERN: Insuficiente confluencia bajista (", 
               bearishPatterns, " bajistas, ", bullishPatterns, " alcistas)");
         return false;
      }
   }
   
   return false;
}

