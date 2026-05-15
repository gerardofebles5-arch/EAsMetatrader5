//+------------------------------------------------------------------+
//|                              InstitutionalFlow_Scalping_EA.mq5   |
//|                           SCALPING VERSION - Todas las Fases     |
//|                                      Optimizado para Scalping    |
//+------------------------------------------------------------------+
#property copyright "Institutional Flow Scalping Strategy"
#property link      ""
#property version   "5.40"
#property strict

//+------------------------------------------------------------------+
//| FASE 1: MEJORAS ESENCIALES ✅                                    |
//| 1. Timeframes M1/M5                                              |
//| 2. ATR dinámico para SL/TP                                       |
//| 3. Trailing stop agresivo                                        |
//| 4. Break Even rápido                                             |
//| 5. Filtro de spread dinámico                                     |
//|                                                                  |
//| FASE 2: MEJORAS AVANZADAS ✅                                     |
//| 1. Partial Close (cierre parcial)                                |
//| 2. Time-Based Exit                                               |
//| 3. Confirmación de volumen mejorada                              |
//| 4. MACD en M1                                                    |
//| 5. CCI (Commodity Channel Index)                                 |
//| 6. Williams %R                                                   |
//| 7. Detección de Fake Breakout                                    |
//| 8. Bollinger Squeeze                                             |
//|                                                                  |
//| FASE 3: MEJORAS EXPERTAS ✅                                      |
//| 1. Detección de Régimen de Mercado (ADX)                         |
//| 2. Volatility-Based Position Sizing                              |
//| 3. Scoring Adaptativo (ajuste dinámico)                          |
//| 4. Multi-Timeframe Momentum Confirmation                          |
//|                                                                  |
//| FASE 4: MEJORAS ULTRA-AVANZADAS ✅                               |
//| 1. News Filter (filtro de noticias)                              |
//| 2. Session-Based Strategy Adjustment                              |
//| 3. Smart Stop Loss Adjustment                                     |
//| 4. Profit Protection System                                       |
//+------------------------------------------------------------------+

// ============ INPUTS DE GESTIÓN DE RIESGO ============
input double RiskPercent = 1.5;              // Riesgo por trade (%)
input bool UseATRforSLTP = true;             // Usar ATR dinámico para SL/TP
input double ATRMultiplierSL = 2.0;          // Multiplicador ATR para SL (más amplio)
input double ATRMultiplierTP = 4.0;          // Multiplicador ATR para TP (RR 1:2)
input int ManualStopLossPips = 15;           // SL manual si no usa ATR
input int ManualTakeProfitPips = 30;         // TP manual si no usa ATR

// ============ INPUTS DE SCALPING ============
input int ScalpingTimeframe = 1;             // Timeframe principal (1=M1, 5=M5)
input int BreakEvenPips = 8;                 // Break Even a 8 pips (más conservador)
input bool UseAggressiveTrailing = true;     // Trailing stop agresivo
input int TrailingStartPips = 12;            // Iniciar trailing a 12 pips
input int TrailingStepPips = 3;              // Step del trailing
input int TrailingStopPips = 5;              // Distancia del trailing (más amplio)

// ============ FASE 2: INPUTS AVANZADOS ============
input bool UsePartialClose = true;           // Usar cierre parcial
input double PartialClosePercent = 50.0;     // % a cerrar en TP1
input int TP1_Pips = 10;                     // TP1 para cierre parcial
input bool UseTimeBasedExit = true;          // Salida por tiempo
input int MaxMinutesInTrade = 15;            // Máximo minutos en trade
input int MinPipsForTimeExit = 3;            // Mínimo profit para no cerrar por tiempo

// ============ FASE 3: INPUTS EXPERTOS ============
input bool UseMarketRegimeDetection = true;  // Detectar régimen de mercado
input int ADX_Period = 14;                   // Período ADX para régimen
input double ADX_TrendingLevel = 25.0;       // ADX >25 = tendencia
input double ADX_RangingLevel = 20.0;        // ADX <20 = rango
input bool UseVolatilityPositionSizing = true; // Ajustar lote por volatilidad
input double VolatilityMultiplierMax = 1.3;  // Multiplicador máximo en baja volatilidad
input double VolatilityMultiplierMin = 0.7;  // Multiplicador mínimo en alta volatilidad
input bool UseAdaptiveScoring = true;        // Scoring adaptativo
input int AdaptivePeriod = 20;               // Trades para calcular adaptación

// ============ FASE 4: INPUTS ULTRA-AVANZADOS ============
input bool UseNewsFilter = false;            // Filtro de noticias (DESACTIVADO por defecto)
input int NewsAvoidanceMinutes = 30;         // Minutos antes/después de noticias
input bool UseSessionAdjustment = true;      // Ajuste por sesión
input double LondonRiskMultiplier = 1.2;     // Multiplicador Londres
input double NYRiskMultiplier = 1.0;         // Multiplicador NY
input double AsiaRiskMultiplier = 0.7;       // Multiplicador Asia
input bool UseSmartStopLoss = true;          // SL inteligente por estructura
input int SwingLookback = 20;                // Velas para buscar swing
input bool UseProfitProtection = true;       // Protección de profits
input double ProfitProtectionLevel1 = 300.0; // $ para reducir riesgo
input double ProfitProtectionLevel2 = 600.0; // $ para stop trading

// ============ INPUTS DE TRADING ============
input int MagicNumber = 123457;              // Magic Number
input int MaxTradesPerHour = 10;             // Máximo trades por hora
input int MaxTradesPerDay = 50;              // Máximo trades por día
input int MaxConsecutiveLosses = 3;          // Stop después de X pérdidas
input double MaxDailyLossDollars = 200.0;    // Pérdida máxima diaria ($)
input int MinScoreToTrade = 4;               // Score mínimo (OPTIMIZADO para operar)

// ============ INPUTS DE HORARIO ============
input int LondonStartHour = 8;               // Inicio sesión Londres (UTC)
input int LondonEndHour = 12;                // Fin sesión Londres (UTC)
input int NYStartHour = 13;                  // Inicio sesión NY (UTC)
input int NYEndHour = 17;                    // Fin sesión NY (UTC)
input bool TradeAsianSession = false;        // Operar sesión asiática (DESACTIVADO - baja calidad)

// ============ INPUTS DE INDICADORES ============
input int EMA_Fast_M15 = 20;                 // EMA Rápida M15 (bias)
input int EMA_Slow_M15 = 50;                 // EMA Lenta M15 (bias)
input int RSI_Period = 14;                   // Período RSI
input int RSI_Level = 50;                    // Nivel RSI
input int ATR_Period = 14;                   // Período ATR
input int Stochastic_K = 5;                  // Stochastic %K
input int Stochastic_D = 3;                  // Stochastic %D
input int Stochastic_Slowing = 3;            // Stochastic Slowing

// ============ INPUTS DE FILTROS ============
input bool UseDynamicSpread = true;          // Spread dinámico por hora
input int MaxSpreadPips_London = 5;          // Spread máximo Londres (más permisivo)
input int MaxSpreadPips_NY = 5;              // Spread máximo NY (más permisivo)
input int MaxSpreadPips_Other = 8;           // Spread máximo otras horas (más permisivo)
input int MaxDailyRangePips = 500;           // Rango diario máximo (más permisivo)
input bool TradeMonday = true;               // Operar lunes (scalping sí)
input bool TradeFriday = true;               // Operar viernes (scalping sí)

// ============ VARIABLES GLOBALES ============
int consecutiveLosses = 0;
int tradesToday = 0;
int tradesThisHour = 0;
double dailyPnL = 0.0;
datetime lastTradeDate = 0;
datetime lastTradeHour = 0;
datetime lastBarTime = 0;
double maxProfitReached = 0.0;

// FASE 2: Variables adicionales
bool tp1_closed = false;                     // TP1 ya cerrado
datetime position_open_time = 0;             // Tiempo de apertura de posición
double initial_position_volume = 0.0;        // Volumen inicial de posición

// FASE 3: Variables adicionales
enum MARKET_REGIME { TRENDING, RANGING, VOLATILE };
MARKET_REGIME current_regime = RANGING;      // Régimen actual del mercado
int adaptive_min_score = 4;                  // Score mínimo adaptativo
double last_20_trades_wr = 0.0;              // Win rate últimos 20 trades
int trades_for_adaptation = 0;               // Contador para adaptación
int wins_in_period = 0;                      // Wins en período adaptativo

// FASE 4: Variables adicionales
enum TRADING_SESSION { LONDON, NEWYORK, ASIA, OVERLAP };
TRADING_SESSION current_session = ASIA;      // Sesión actual
double session_risk_multiplier = 1.0;        // Multiplicador de riesgo por sesión
int session_min_score_adjustment = 0;        // Ajuste de score por sesión
bool profit_protection_active = false;       // Protección de profits activa
bool trading_stopped_today = false;          // Trading detenido por profits

// ============ HANDLES DE INDICADORES ============
int handle_EMA_Fast_M15;
int handle_EMA_Slow_M15;
int handle_RSI_M5;
int handle_ATR_M5;
int handle_Stochastic_M1;
int handle_BB_M1;

// FASE 2: Handles adicionales
int handle_MACD_M1;
int handle_CCI_M1;
int handle_WPR_M1;

// FASE 3: Handles adicionales
int handle_ADX_M15;
int handle_ATR_M15;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Institutional Flow SCALPING EA Iniciado ===");
   Print("Versión: 5.40 - FINAL OPTIMIZADO (v5.20 + SL/TP mejorados)");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M", ScalpingTimeframe);
   Print("Riesgo: ", RiskPercent, "%");
   Print("Score mínimo: ", MinScoreToTrade, " (BAJO para operar)");
   Print("SL/TP: ATR x", ATRMultiplierSL, "/", ATRMultiplierTP, " (MEJORADO)");
   Print("Sin penalizaciones | Sin alineación obligatoria");
   Print("🎯 OBJETIVO: Opera como v5.20 + Mejor gestión de riesgo");
   
   // Crear handles de indicadores FASE 1
   ENUM_TIMEFRAMES tf_main = (ScalpingTimeframe == 1) ? PERIOD_M1 : PERIOD_M5;
   
   handle_EMA_Fast_M15 = iMA(_Symbol, PERIOD_M15, EMA_Fast_M15, 0, MODE_EMA, PRICE_CLOSE);
   handle_EMA_Slow_M15 = iMA(_Symbol, PERIOD_M15, EMA_Slow_M15, 0, MODE_EMA, PRICE_CLOSE);
   handle_RSI_M5 = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   handle_ATR_M5 = iATR(_Symbol, PERIOD_M5, ATR_Period);
   handle_Stochastic_M1 = iStochastic(_Symbol, PERIOD_M1, Stochastic_K, Stochastic_D, Stochastic_Slowing, MODE_SMA, STO_LOWHIGH);
   handle_BB_M1 = iBands(_Symbol, PERIOD_M1, 20, 0, 2, PRICE_CLOSE);
   
   // FASE 2: Crear handles adicionales
   handle_MACD_M1 = iMACD(_Symbol, PERIOD_M1, 12, 26, 9, PRICE_CLOSE);
   handle_CCI_M1 = iCCI(_Symbol, PERIOD_M1, 14, PRICE_TYPICAL);
   handle_WPR_M1 = iWPR(_Symbol, PERIOD_M1, 14);
   
   // FASE 3: Crear handles adicionales
   handle_ADX_M15 = iADX(_Symbol, PERIOD_M15, ADX_Period);
   handle_ATR_M15 = iATR(_Symbol, PERIOD_M15, ATR_Period);
   
   if(handle_EMA_Fast_M15 == INVALID_HANDLE || handle_EMA_Slow_M15 == INVALID_HANDLE || 
      handle_RSI_M5 == INVALID_HANDLE || handle_ATR_M5 == INVALID_HANDLE ||
      handle_Stochastic_M1 == INVALID_HANDLE || handle_BB_M1 == INVALID_HANDLE ||
      handle_MACD_M1 == INVALID_HANDLE || handle_CCI_M1 == INVALID_HANDLE || handle_WPR_M1 == INVALID_HANDLE ||
      handle_ADX_M15 == INVALID_HANDLE || handle_ATR_M15 == INVALID_HANDLE)
   {
      Print("Error al crear indicadores");
      return(INIT_FAILED);
   }
   
   Print("Indicadores inicializados correctamente");
   Print("=== 🚀 VERSIÓN FINAL 5.40 ACTIVADA 🚀 ===");
   Print("Lógica: v5.20 (opera) + SL/TP v5.30 (calidad)");
   Print("Score: ", MinScoreToTrade, " | Sin penalizaciones | Sin alineación obligatoria");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar handles de indicadores FASE 1
   if(handle_EMA_Fast_M15 != INVALID_HANDLE) IndicatorRelease(handle_EMA_Fast_M15);
   if(handle_EMA_Slow_M15 != INVALID_HANDLE) IndicatorRelease(handle_EMA_Slow_M15);
   if(handle_RSI_M5 != INVALID_HANDLE) IndicatorRelease(handle_RSI_M5);
   if(handle_ATR_M5 != INVALID_HANDLE) IndicatorRelease(handle_ATR_M5);
   if(handle_Stochastic_M1 != INVALID_HANDLE) IndicatorRelease(handle_Stochastic_M1);
   if(handle_BB_M1 != INVALID_HANDLE) IndicatorRelease(handle_BB_M1);
   
   // FASE 2: Liberar handles adicionales
   if(handle_MACD_M1 != INVALID_HANDLE) IndicatorRelease(handle_MACD_M1);
   if(handle_CCI_M1 != INVALID_HANDLE) IndicatorRelease(handle_CCI_M1);
   if(handle_WPR_M1 != INVALID_HANDLE) IndicatorRelease(handle_WPR_M1);
   
   // FASE 3: Liberar handles adicionales
   if(handle_ADX_M15 != INVALID_HANDLE) IndicatorRelease(handle_ADX_M15);
   if(handle_ATR_M15 != INVALID_HANDLE) IndicatorRelease(handle_ATR_M15);
   
   Print("=== Institutional Flow SCALPING EA Detenido ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ENUM_TIMEFRAMES tf_main = (ScalpingTimeframe == 1) ? PERIOD_M1 : PERIOD_M5;
   
   // Verificar nueva vela
   datetime currentBarTime = iTime(_Symbol, tf_main, 0);
   if(currentBarTime == lastBarTime) 
   {
      // Aunque no haya nueva vela, gestionar posición abierta
      if(PositionSelect(_Symbol))
      {
         ManageOpenPosition();
      }
      return;
   }
   lastBarTime = currentBarTime;
   
   Print("🔄 === NUEVA VELA ", TimeToString(currentBarTime), " ===");
   
   // Resetear contadores
   ResetDailyCounters();
   ResetHourlyCounters();
   
   // FASE 3: Detectar régimen de mercado
   if(UseMarketRegimeDetection)
   {
      DetectMarketRegime();
      AdjustStrategyByRegime();
      Print("📈 Régimen: ", current_regime==TRENDING?"TRENDING":(current_regime==RANGING?"RANGING":"VOLATILE"));
   }
   
   // FASE 4: Detectar sesión y ajustar
   if(UseSessionAdjustment)
   {
      DetectCurrentSession();
      AdjustBySession();
      string session_name = current_session==LONDON?"LONDON":(current_session==NEWYORK?"NY":(current_session==OVERLAP?"OVERLAP":"ASIA"));
      Print("🌍 Sesión: ", session_name, " | Risk mult: ", session_risk_multiplier);
   }
   
   // FASE 4: Verificar protección de profits
   if(UseProfitProtection)
   {
      CheckProfitProtection();
      if(trading_stopped_today)
      {
         Print("💰 Trading detenido por protección de profits");
         return;
      }
   }
   
   // Verificar si ya hay posición abierta
   if(PositionSelect(_Symbol))
   {
      Print("📊 Posición abierta - Gestionando...");
      ManageOpenPosition();
      return;
   }
   
   // FASE 4: Filtro de noticias
   if(UseNewsFilter && IsNewsTime())
   {
      Print("📰 Evitando trade por noticias");
      return;
   }
   
   // Verificar filtros globales
   Print("🔍 Verificando filtros globales...");
   if(!CheckGlobalFilters())
   {
      Print("❌ Filtros globales NO pasados");
      return;
   }
   
   // Buscar señal de entrada
   Print("🎯 Analizando mercado...");
   int signal = AnalyzeMarketScalping();
   
   if(signal == 1) // Señal LONG
   {
      Print("✅ EJECUTANDO LONG");
      OpenTrade(ORDER_TYPE_BUY);
   }
   else if(signal == -1) // Señal SHORT
   {
      Print("✅ EJECUTANDO SHORT");
      OpenTrade(ORDER_TYPE_SELL);
   }
   else
   {
      Print("⏸️ Sin señal válida en esta vela");
   }
}

//+------------------------------------------------------------------+
//| Resetear contadores diarios                                      |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
   
   if(currentDate != lastTradeDate)
   {
      tradesToday = 0;
      tradesThisHour = 0;
      dailyPnL = 0.0;
      consecutiveLosses = 0; // Reset diario de pérdidas
      lastTradeDate = currentDate;
      
      // FASE 4: Reset protección de profits
      profit_protection_active = false;
      trading_stopped_today = false;
      
      Print("=== NUEVO DÍA DE SCALPING - Contadores reseteados ===");
   }
}

//+------------------------------------------------------------------+
//| Resetear contadores por hora                                     |
//+------------------------------------------------------------------+
void ResetHourlyCounters()
{
   datetime currentHour = iTime(_Symbol, PERIOD_H1, 0);
   
   if(currentHour != lastTradeHour)
   {
      tradesThisHour = 0;
      lastTradeHour = currentHour;
   }
}


//+------------------------------------------------------------------+
//| FASE 1: Filtro de Spread Dinámico                                |
//+------------------------------------------------------------------+
int GetMaxSpreadForCurrentHour()
{
   if(!UseDynamicSpread)
      return MaxSpreadPips_Other;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // Londres: spread más bajo
   if(hour >= LondonStartHour && hour < LondonEndHour)
      return MaxSpreadPips_London;
   
   // NY: spread bajo
   if(hour >= NYStartHour && hour < NYEndHour)
      return MaxSpreadPips_NY;
   
   // Otras horas: spread más alto permitido
   return MaxSpreadPips_Other;
}

//+------------------------------------------------------------------+
//| Verificar filtros globales - VERSIÓN SIMPLIFICADA                |
//+------------------------------------------------------------------+
bool CheckGlobalFilters()
{
   // Verificar día de la semana
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dayOfWeek = dt.day_of_week;
   
   if(dayOfWeek == 1 && !TradeMonday)
   {
      Print("❌ Lunes - No operar");
      return false;
   }
   
   if(dayOfWeek == 5 && !TradeFriday && dt.hour >= 14)
   {
      Print("❌ Viernes tarde - No operar");
      return false;
   }
   
   // Verificar horario - MÁS PERMISIVO
   int currentHour = dt.hour;
   bool inLondonSession = (currentHour >= LondonStartHour && currentHour < LondonEndHour);
   bool inNYSession = (currentHour >= NYStartHour && currentHour < NYEndHour);
   bool inAsianSession = (currentHour >= 0 && currentHour < 7);
   
   // Permitir operar en cualquier sesión si TradeAsianSession está activo
   if(!inLondonSession && !inNYSession && !inAsianSession)
   {
      // Permitir operar fuera de sesiones principales
      if(!TradeAsianSession)
      {
         Print("❌ Fuera de horario de trading");
         return false;
      }
   }
   
   // FASE 1: Spread dinámico - MÁS PERMISIVO
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point / 10;
   int maxSpread = GetMaxSpreadForCurrentHour();
   if(spread > maxSpread)
   {
      Print("❌ Spread alto: ", (int)spread, " pips (máx: ", maxSpread, ")");
      return false;
   }
   
   // Verificar rango diario - MÁS PERMISIVO
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dailyLow = iLow(_Symbol, PERIOD_D1, 0);
   double dailyRange = (dailyHigh - dailyLow) / _Point / 10;
   
   if(dailyRange > MaxDailyRangePips)
   {
      Print("❌ Rango diario excesivo: ", (int)dailyRange, " pips");
      return false;
   }
   
   // Verificar límites de trading
   if(tradesToday >= MaxTradesPerDay)
   {
      Print("❌ Límite diario alcanzado: ", tradesToday, " trades");
      return false;
   }
   
   if(tradesThisHour >= MaxTradesPerHour)
   {
      Print("❌ Límite por hora alcanzado: ", tradesThisHour, " trades");
      return false;
   }
   
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      Print("❌ Límite de pérdidas consecutivas: ", consecutiveLosses);
      return false;
   }
   
   if(dailyPnL <= -MaxDailyLossDollars)
   {
      Print("❌ Límite de pérdida diaria: $", (int)dailyPnL);
      return false;
   }
   
   Print("✅ Filtros globales OK | Spread:", (int)spread, "p | Rango:", (int)dailyRange, "p | Trades:", tradesToday);
   return true;
}

//+------------------------------------------------------------------+
//| FASE 1: Calcular SL/TP con ATR Dinámico                          |
//+------------------------------------------------------------------+
void CalculateDynamicSLTP(int &sl_pips, int &tp_pips)
{
   if(UseATRforSLTP)
   {
      double atr_array[];
      ArraySetAsSeries(atr_array, true);
      
      if(CopyBuffer(handle_ATR_M5, 0, 0, 1, atr_array) > 0)
      {
         double atr = atr_array[0] / _Point / 10; // ATR en pips
         
         sl_pips = (int)(atr * ATRMultiplierSL);
         tp_pips = (int)(atr * ATRMultiplierTP);
         
         // Límites para scalping de calidad
         if(sl_pips < 12) sl_pips = 12;  // SL mínimo más amplio
         if(sl_pips > 30) sl_pips = 30;  // SL máximo
         if(tp_pips < 24) tp_pips = 24;  // TP mínimo (RR 1:2)
         if(tp_pips > 60) tp_pips = 60;  // TP máximo
      }
      else
      {
         // Fallback a valores manuales
         sl_pips = ManualStopLossPips;
         tp_pips = ManualTakeProfitPips;
      }
   }
   else
   {
      sl_pips = ManualStopLossPips;
      tp_pips = ManualTakeProfitPips;
   }
}

//+------------------------------------------------------------------+
//| Analizar mercado para SCALPING - VERSIÓN 5.40 FINAL              |
//+------------------------------------------------------------------+
int AnalyzeMarketScalping()
{
   int score = 0;
   bool biasLong = false;
   bool biasShort = false;
   
   // PASO 1: Verificar Bias M15
   CheckBiasM15(biasLong, biasShort, score);
   
   // Si no hay bias claro, usar método alternativo
   if(!biasLong && !biasShort)
   {
      double close_array[], ema_fast_array[];
      ArraySetAsSeries(close_array, true);
      ArraySetAsSeries(ema_fast_array, true);
      
      if(CopyClose(_Symbol, PERIOD_M15, 0, 1, close_array) > 0 &&
         CopyBuffer(handle_EMA_Fast_M15, 0, 0, 1, ema_fast_array) > 0)
      {
         if(close_array[0] > ema_fast_array[0])
         {
            biasLong = true;
            score += 2;
         }
         else
         {
            biasShort = true;
            score += 2;
         }
      }
   }
   
   // Si aún no hay bias, usar vela M5
   if(!biasLong && !biasShort)
   {
      double open_m5 = iOpen(_Symbol, PERIOD_M5, 0);
      double close_m5 = iClose(_Symbol, PERIOD_M5, 0);
      
      if(close_m5 > open_m5)
      {
         biasLong = true;
         score += 2;
      }
      else
      {
         biasShort = true;
         score += 2;
      }
   }
   
   // PASO 2: Confirmación M5 (BONUS)
   bool m5Confirmed = false;
   bool m5Bullish = false;
   CheckM5Confirmation(m5Confirmed, m5Bullish, score);
   
   // PASO 3: Timing M1 (BONUS)
   bool m1Confirmed = false;
   bool m1Bullish = false;
   CheckM1TimingWithStochastic(m1Confirmed, m1Bullish, score);
   
   // PASO 4: Bollinger Bands (BONUS)
   CheckBollingerBands(score);
   
   // FASE 2: Indicadores adicionales (BONUS)
   if(CheckMACDConfirmation(biasLong))
      score += 2;
   
   bool cci_oversold = false, cci_overbought = false;
   if(CheckCCIExtreme(cci_oversold, cci_overbought))
   {
      if((biasLong && cci_oversold) || (biasShort && cci_overbought))
         score += 2;
   }
   
   bool wpr_buy = false, wpr_sell = false;
   if(CheckWilliamsR(wpr_buy, wpr_sell))
   {
      if((biasLong && wpr_buy) || (biasShort && wpr_sell))
         score += 2;
   }
   
   if(IsVolumeIncreasing())
      score += 1;
   
   // Verificar fake breakout y squeeze (SOLO INFO, NO PENALIZA)
   bool is_fake = IsFakeBreakout();
   bool is_squeeze = IsBollingerSqueeze();
   
   // Verificar score mínimo
   int min_score_required = MinScoreToTrade;
   
   // Ajustar por scoring adaptativo
   if(UseAdaptiveScoring)
      min_score_required = adaptive_min_score;
   
   // Ajustar por sesión
   if(UseSessionAdjustment)
   {
      min_score_required += session_min_score_adjustment;
      if(min_score_required < 2) min_score_required = 2; // Mínimo absoluto bajo
   }
   
   // Log detallado
   Print("📊 ANÁLISIS: Score=", score, " Min=", min_score_required, 
         " | Bias:", biasLong?"LONG":(biasShort?"SHORT":"NONE"),
         " | M5:", m5Confirmed?"✓":"✗", m5Bullish?"BULL":"BEAR",
         " | M1:", m1Confirmed?"✓":"✗", m1Bullish?"BULL":"BEAR",
         " | Fake:", is_fake?"⚠":"✓",
         " | Squeeze:", is_squeeze?"⚠":"✓");
   
   if(score < min_score_required)
   {
      Print("⚠️ Score insuficiente: ", score, " < ", min_score_required);
      return 0;
   }
   
   // Generar señal basada en bias
   if(biasLong)
   {
      Print("🟢 === SEÑAL LONG === Score: ", score);
      return 1;
   }
   else if(biasShort)
   {
      Print("🔴 === SEÑAL SHORT === Score: ", score);
      return -1;
   }
   
   Print("⚠️ Sin bias determinado");
   return 0;
}


//+------------------------------------------------------------------+
//| Verificar Bias en M15 (más rápido que D1)                        |
//+------------------------------------------------------------------+
bool CheckBiasM15(bool &biasLong, bool &biasShort, int &score)
{
   double ema_fast_array[], ema_slow_array[], close_array[];
   ArraySetAsSeries(ema_fast_array, true);
   ArraySetAsSeries(ema_slow_array, true);
   ArraySetAsSeries(close_array, true);
   
   if(CopyBuffer(handle_EMA_Fast_M15, 0, 0, 1, ema_fast_array) <= 0) return false;
   if(CopyBuffer(handle_EMA_Slow_M15, 0, 0, 1, ema_slow_array) <= 0) return false;
   if(CopyClose(_Symbol, PERIOD_M15, 0, 1, close_array) <= 0) return false;
   
   double ema_fast = ema_fast_array[0];
   double ema_slow = ema_slow_array[0];
   double close_m15 = close_array[0];
   
   // Bias alcista
   if(close_m15 > ema_fast && ema_fast > ema_slow)
   {
      biasLong = true;
      score += 3;
      return true;
   }
   
   // Bias bajista
   if(close_m15 < ema_fast && ema_fast < ema_slow)
   {
      biasShort = true;
      score += 3;
      return true;
   }
   
   // Bias débil alcista
   if(close_m15 > ema_fast)
   {
      biasLong = true;
      score += 1;
      return true;
   }
   
   // Bias débil bajista
   if(close_m15 < ema_fast)
   {
      biasShort = true;
      score += 1;
      return true;
   }
   
   return true; // Siempre continuar
}

//+------------------------------------------------------------------+
//| Verificar confirmación en M5 con RSI                             |
//+------------------------------------------------------------------+
bool CheckM5Confirmation(bool &confirmed, bool &isBullish, int &score)
{
   double open_array[], close_array[], high_array[], low_array[];
   double rsi_array[];
   
   ArraySetAsSeries(open_array, true);
   ArraySetAsSeries(close_array, true);
   ArraySetAsSeries(high_array, true);
   ArraySetAsSeries(low_array, true);
   ArraySetAsSeries(rsi_array, true);
   
   if(CopyOpen(_Symbol, PERIOD_M5, 0, 3, open_array) <= 0) return true; // Continuar si falla
   if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close_array) <= 0) return true;
   if(CopyHigh(_Symbol, PERIOD_M5, 0, 3, high_array) <= 0) return true;
   if(CopyLow(_Symbol, PERIOD_M5, 0, 3, low_array) <= 0) return true;
   if(CopyBuffer(handle_RSI_M5, 0, 0, 2, rsi_array) <= 0) return true;
   
   double open_m5 = open_array[1];
   double close_m5 = close_array[1];
   double high_m5 = high_array[1];
   double low_m5 = low_array[1];
   double rsi = rsi_array[1];
   
   double body = MathAbs(close_m5 - open_m5);
   double upperWick = high_m5 - MathMax(open_m5, close_m5);
   double lowerWick = MathMin(open_m5, close_m5) - low_m5;
   double totalSize = high_m5 - low_m5;
   
   if(totalSize == 0) return true; // Evitar división por cero
   
   // Pin bar alcista
   if(lowerWick > totalSize * 0.5 && close_m5 > open_m5 && rsi > RSI_Level)
   {
      confirmed = true;
      isBullish = true;
      score += 3;
      return true;
   }
   
   // Pin bar bajista
   if(upperWick > totalSize * 0.5 && close_m5 < open_m5 && rsi < RSI_Level)
   {
      confirmed = true;
      isBullish = false;
      score += 3;
      return true;
   }
   
   // Vela alcista fuerte con RSI
   if(close_m5 > open_m5 && body > totalSize * 0.6 && rsi > RSI_Level)
   {
      confirmed = true;
      isBullish = true;
      score += 2;
      return true;
   }
   
   // Vela bajista fuerte con RSI
   if(close_m5 < open_m5 && body > totalSize * 0.6 && rsi < RSI_Level)
   {
      confirmed = true;
      isBullish = false;
      score += 2;
      return true;
   }
   
   // Vela alcista simple (sin requisitos estrictos)
   if(close_m5 > open_m5 && rsi > 45)
   {
      confirmed = true;
      isBullish = true;
      score += 1;
      return true;
   }
   
   // Vela bajista simple
   if(close_m5 < open_m5 && rsi < 55)
   {
      confirmed = true;
      isBullish = false;
      score += 1;
      return true;
   }
   
   return true; // Siempre continuar
}

//+------------------------------------------------------------------+
//| Verificar timing M1 con Stochastic                               |
//+------------------------------------------------------------------+
bool CheckM1TimingWithStochastic(bool &confirmed, bool &isBullish, int &score)
{
   double stoch_main[], stoch_signal[];
   ArraySetAsSeries(stoch_main, true);
   ArraySetAsSeries(stoch_signal, true);
   
   if(CopyBuffer(handle_Stochastic_M1, 0, 0, 2, stoch_main) <= 0) return true; // Continuar si falla
   if(CopyBuffer(handle_Stochastic_M1, 1, 0, 2, stoch_signal) <= 0) return true;
   
   double stoch_k_current = stoch_main[0];
   double stoch_d_current = stoch_signal[0];
   double stoch_k_prev = stoch_main[1];
   double stoch_d_prev = stoch_signal[1];
   
   // Saliendo de sobreventa (señal alcista)
   if(stoch_k_prev < 20 && stoch_k_current > 20 && stoch_k_current > stoch_d_current)
   {
      confirmed = true;
      isBullish = true;
      score += 3;
      return true;
   }
   
   // Saliendo de sobrecompra (señal bajista)
   if(stoch_k_prev > 80 && stoch_k_current < 80 && stoch_k_current < stoch_d_current)
   {
      confirmed = true;
      isBullish = false;
      score += 3;
      return true;
   }
   
   // Cruce alcista en zona media
   if(stoch_k_prev < stoch_d_prev && stoch_k_current > stoch_d_current && stoch_k_current > 50)
   {
      confirmed = true;
      isBullish = true;
      score += 2;
      return true;
   }
   
   // Cruce bajista en zona media
   if(stoch_k_prev > stoch_d_prev && stoch_k_current < stoch_d_current && stoch_k_current < 50)
   {
      confirmed = true;
      isBullish = false;
      score += 2;
      return true;
   }
   
   // Stochastic alcista (sin cruce)
   if(stoch_k_current > stoch_d_current && stoch_k_current < 80)
   {
      confirmed = true;
      isBullish = true;
      score += 1;
      return true;
   }
   
   // Stochastic bajista (sin cruce)
   if(stoch_k_current < stoch_d_current && stoch_k_current > 20)
   {
      confirmed = true;
      isBullish = false;
      score += 1;
      return true;
   }
   
   return true; // Siempre continuar
}

//+------------------------------------------------------------------+
//| Verificar Bollinger Bands                                        |
//+------------------------------------------------------------------+
void CheckBollingerBands(int &score)
{
   double bb_upper[], bb_lower[], bb_middle[];
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_middle, true);
   
   if(CopyBuffer(handle_BB_M1, 1, 0, 1, bb_upper) <= 0) return;
   if(CopyBuffer(handle_BB_M1, 2, 0, 1, bb_lower) <= 0) return;
   if(CopyBuffer(handle_BB_M1, 0, 0, 1, bb_middle) <= 0) return;
   
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double upper = bb_upper[0];
   double lower = bb_lower[0];
   double middle = bb_middle[0];
   
   // Precio cerca de banda inferior (posible rebote alcista)
   double distance_to_lower = MathAbs(current_price - lower) / _Point / 10;
   if(distance_to_lower < 3)
   {
      score += 2;
      return;
   }
   
   // Precio cerca de banda superior (posible rebote bajista)
   double distance_to_upper = MathAbs(current_price - upper) / _Point / 10;
   if(distance_to_upper < 3)
   {
      score += 2;
      return;
   }
}


//+------------------------------------------------------------------+
//| Abrir trade con SL/TP dinámico y FASE 4: Smart SL                |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   bool is_long = (orderType == ORDER_TYPE_BUY);
   
   // FASE 4: Calcular Smart SL (o normal si está desactivado)
   double sl = CalculateSmartSL(is_long, price);
   
   // Calcular SL pips para el lote
   double sl_pips_distance = MathAbs(price - sl) / _Point / 10;
   int sl_pips = (int)sl_pips_distance;
   
   // Calcular TP con ratio 1:2
   int tp_pips = sl_pips * 2;
   double tp;
   if(is_long)
   {
      tp = price + tp_pips * _Point * 10;
   }
   else
   {
      tp = price - tp_pips * _Point * 10;
   }
   
   // Calcular lote (incluye ajustes de FASE 3 y FASE 4)
   double lotSize = CalculateLotSize(sl_pips);
   
   // Normalizar valores
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Preparar request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 5;  // Slippage control para scalping
   request.magic = MagicNumber;
   request.comment = "Scalping";
   request.type_filling = ORDER_FILLING_IOC; // Immediate or Cancel
   
   // Enviar orden
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("=== SCALPING TRADE ABIERTO ===");
         Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("Precio: ", price);
         Print("SL: ", sl, " (", sl_pips, " pips) ", UseSmartStopLoss ? "[SMART]" : "[NORMAL]");
         Print("TP: ", tp, " (", tp_pips, " pips)");
         Print("Lote: ", lotSize);
         if(profit_protection_active) Print("💰 Protección activa: Riesgo reducido");
         
         tradesToday++;
         tradesThisHour++;
         maxProfitReached = 0.0;
         
         // FASE 2: Inicializar variables de posición
         tp1_closed = false;
         position_open_time = TimeCurrent();
         initial_position_volume = lotSize;
      }
      else
      {
         Print("Error al abrir trade: ", result.retcode, " - ", result.comment);
      }
   }
   else
   {
      Print("Error en OrderSend: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calcular tamaño de lote con FASE 3 y FASE 4                      |
//+------------------------------------------------------------------+
double CalculateLotSize(int slPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   
   // FASE 4: Ajustar riesgo por sesión
   if(UseSessionAdjustment)
   {
      riskAmount = riskAmount * session_risk_multiplier;
   }
   
   // FASE 4: Ajustar riesgo por protección de profits
   if(profit_protection_active)
   {
      riskAmount = riskAmount * 0.5;  // Reducir 50%
   }
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / tickSize * _Point;
   
   double lotSize = riskAmount / (slPips * 10 * pointValue);
   
   // FASE 3: Ajustar por volatilidad
   if(UseVolatilityPositionSizing)
   {
      double volatility_multiplier = CalculateVolatilityMultiplier();
      lotSize = lotSize * volatility_multiplier;
   }
   
   // Verificar límites
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| FASE 1: Gestionar posición con BE rápido y Trailing agresivo     |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!PositionSelect(_Symbol)) return;
   
   double positionProfit = PositionGetDouble(POSITION_PROFIT);
   double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double positionSL = PositionGetDouble(POSITION_SL);
   long positionType = PositionGetInteger(POSITION_TYPE);
   
   double currentPrice = (positionType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double profitPips = 0;
   if(positionType == POSITION_TYPE_BUY)
   {
      profitPips = (currentPrice - positionOpenPrice) / _Point / 10;
   }
   else
   {
      profitPips = (positionOpenPrice - currentPrice) / _Point / 10;
   }
   
   // Actualizar máximo profit alcanzado
   if(profitPips > maxProfitReached)
      maxProfitReached = profitPips;
   
   // FASE 2: Partial Close (cierre parcial)
   if(UsePartialClose && !tp1_closed && profitPips >= TP1_Pips)
   {
      PartialClosePosition();
   }
   
   // FASE 2: Time-Based Exit
   if(UseTimeBasedExit)
   {
      CheckTimeBasedExit(profitPips);
   }
   
   // FASE 1: Break Even RÁPIDO (5 pips)
   if(profitPips >= BreakEvenPips)
   {
      double current_sl_pips = MathAbs(positionOpenPrice - positionSL) / _Point / 10;
      
      // Solo mover a BE si aún no está en BE
      if(current_sl_pips > 2)
      {
         double new_sl = NormalizeDouble(positionOpenPrice + _Point * 10, _Digits); // +1 pip
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.symbol = _Symbol;
         request.sl = new_sl;
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(OrderSend(request, result))
         {
            Print("✓ Break Even activado a +", BreakEvenPips, " pips");
         }
      }
   }
   
   // FASE 1: Trailing Stop AGRESIVO
   if(UseAggressiveTrailing && profitPips >= TrailingStartPips)
   {
      double new_sl = 0;
      
      if(positionType == POSITION_TYPE_BUY)
      {
         new_sl = currentPrice - TrailingStopPips * _Point * 10;
      }
      else
      {
         new_sl = currentPrice + TrailingStopPips * _Point * 10;
      }
      
      new_sl = NormalizeDouble(new_sl, _Digits);
      
      // Solo mover SL si es mejor que el actual
      bool should_move = false;
      if(positionType == POSITION_TYPE_BUY && new_sl > positionSL)
         should_move = true;
      if(positionType == POSITION_TYPE_SELL && new_sl < positionSL)
         should_move = true;
      
      if(should_move)
      {
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.symbol = _Symbol;
         request.sl = new_sl;
         request.tp = PositionGetDouble(POSITION_TP);
         
         if(OrderSend(request, result))
         {
            Print("✓ Trailing Stop movido: Profit=", (int)profitPips, " pips, Nuevo SL a ", TrailingStopPips, " pips del precio");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| FASE 2: Partial Close (Cierre Parcial)                           |
//+------------------------------------------------------------------+
void PartialClosePosition()
{
   if(!PositionSelect(_Symbol)) return;
   
   double currentVolume = PositionGetDouble(POSITION_VOLUME);
   double closeVolume = NormalizeDouble(initial_position_volume * (PartialClosePercent / 100.0), 2);
   
   // Verificar que el volumen a cerrar sea válido
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(closeVolume < minLot)
   {
      Print("⚠️ Volumen parcial muy pequeño, no se cierra");
      tp1_closed = true; // Marcar como cerrado para no intentar de nuevo
      return;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = closeVolume;
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation = 5;
   request.magic = MagicNumber;
   request.comment = "Partial Close TP1";
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         tp1_closed = true;
         Print("✓ TP1 alcanzado: ", (int)PartialClosePercent, "% cerrado a +", TP1_Pips, " pips");
         
         // Mover SL a Break Even después de TP1
         double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double new_sl = NormalizeDouble(positionOpenPrice + _Point * 10, _Digits);
         
         MqlTradeRequest req_sl = {};
         MqlTradeResult res_sl = {};
         
         req_sl.action = TRADE_ACTION_SLTP;
         req_sl.symbol = _Symbol;
         req_sl.sl = new_sl;
         req_sl.tp = PositionGetDouble(POSITION_TP);
         
         if(!OrderSend(req_sl, res_sl))
         {
            Print("Error ajustando SL inteligente: ", res_sl.retcode);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| FASE 2: Time-Based Exit                                          |
//+------------------------------------------------------------------+
void CheckTimeBasedExit(double profitPips)
{
   int minutes_open = (int)((TimeCurrent() - position_open_time) / 60);
   
   if(minutes_open >= MaxMinutesInTrade && profitPips < MinPipsForTimeExit)
   {
      // Cerrar posición por tiempo
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      request.deviation = 5;
      request.magic = MagicNumber;
      request.comment = "Time Exit";
      
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("⏱️ Time-based exit: ", minutes_open, " min sin movimiento significativo");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| FASE 2: MACD Confirmation                                         |
//+------------------------------------------------------------------+
bool CheckMACDConfirmation(bool is_long)
{
   double macd_main[], macd_signal[];
   ArraySetAsSeries(macd_main, true);
   ArraySetAsSeries(macd_signal, true);
   
   if(CopyBuffer(handle_MACD_M1, 0, 0, 2, macd_main) <= 0) return false;
   if(CopyBuffer(handle_MACD_M1, 1, 0, 2, macd_signal) <= 0) return false;
   
   // Cruce alcista
   if(is_long)
      return (macd_main[0] > macd_signal[0] && macd_main[1] <= macd_signal[1]);
   
   // Cruce bajista
   return (macd_main[0] < macd_signal[0] && macd_main[1] >= macd_signal[1]);
}

//+------------------------------------------------------------------+
//| FASE 2: CCI Extreme Detection                                    |
//+------------------------------------------------------------------+
bool CheckCCIExtreme(bool &is_oversold, bool &is_overbought)
{
   double cci[];
   ArraySetAsSeries(cci, true);
   
   if(CopyBuffer(handle_CCI_M1, 0, 0, 2, cci) <= 0) return false;
   
   // Saliendo de sobreventa (señal alcista)
   is_oversold = (cci[1] < -100 && cci[0] > -100);
   
   // Saliendo de sobrecompra (señal bajista)
   is_overbought = (cci[1] > 100 && cci[0] < 100);
   
   return (is_oversold || is_overbought);
}

//+------------------------------------------------------------------+
//| FASE 2: Williams %R Signal                                       |
//+------------------------------------------------------------------+
bool CheckWilliamsR(bool &is_buy, bool &is_sell)
{
   double wpr[];
   ArraySetAsSeries(wpr, true);
   
   if(CopyBuffer(handle_WPR_M1, 0, 0, 2, wpr) <= 0) return false;
   
   // Saliendo de sobreventa (señal alcista)
   is_buy = (wpr[1] < -80 && wpr[0] > -80);
   
   // Saliendo de sobrecompra (señal bajista)
   is_sell = (wpr[1] > -20 && wpr[0] < -20);
   
   return (is_buy || is_sell);
}

//+------------------------------------------------------------------+
//| FASE 2: Volume Confirmation                                      |
//+------------------------------------------------------------------+
bool IsVolumeIncreasing()
{
   long vol_m1_current = iVolume(_Symbol, PERIOD_M1, 0);
   long vol_m1_prev = iVolume(_Symbol, PERIOD_M1, 1);
   
   // Calcular volumen promedio de últimas 20 velas M1
   long total_volume = 0;
   for(int i = 1; i <= 20; i++)
   {
      total_volume += iVolume(_Symbol, PERIOD_M1, i);
   }
   long avg_vol_m1 = total_volume / 20;
   
   // Volumen actual debe ser >130% del anterior Y >150% del promedio
   return (vol_m1_current > vol_m1_prev * 1.3) && (vol_m1_current > avg_vol_m1 * 1.5);
}

//+------------------------------------------------------------------+
//| FASE 2: Fake Breakout Detection                                  |
//+------------------------------------------------------------------+
bool IsFakeBreakout()
{
   double atr_array[];
   ArraySetAsSeries(atr_array, true);
   
   if(CopyBuffer(handle_ATR_M5, 0, 0, 1, atr_array) <= 0) return false;
   
   double atr = atr_array[0];
   
   // Obtener tamaño de la última vela M1
   double open_m1 = iOpen(_Symbol, PERIOD_M1, 1);
   double close_m1 = iClose(_Symbol, PERIOD_M1, 1);
   double high_m1 = iHigh(_Symbol, PERIOD_M1, 1);
   double low_m1 = iLow(_Symbol, PERIOD_M1, 1);
   
   double candle_size = high_m1 - low_m1;
   
   // Si la vela es <30% del ATR, puede ser un fake breakout
   return (candle_size < atr * 0.3);
}

//+------------------------------------------------------------------+
//| FASE 2: Bollinger Squeeze Detection                              |
//+------------------------------------------------------------------+
bool IsBollingerSqueeze()
{
   double bb_upper[], bb_lower[], bb_middle[];
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(bb_middle, true);
   
   if(CopyBuffer(handle_BB_M1, 1, 0, 20, bb_upper) <= 0) return false;
   if(CopyBuffer(handle_BB_M1, 2, 0, 20, bb_lower) <= 0) return false;
   if(CopyBuffer(handle_BB_M1, 0, 0, 20, bb_middle) <= 0) return false;
   
   // Calcular ancho actual de las bandas
   double current_width = (bb_upper[0] - bb_lower[0]) / bb_middle[0];
   
   // Calcular ancho promedio de últimas 20 velas
   double total_width = 0;
   for(int i = 0; i < 20; i++)
   {
      total_width += (bb_upper[i] - bb_lower[i]) / bb_middle[i];
   }
   double avg_width = total_width / 20;
   
   // Squeeze si ancho actual es <70% del promedio
   return (current_width < avg_width * 0.7);
}

//+------------------------------------------------------------------+
//| FASE 3: Detectar Régimen de Mercado                              |
//+------------------------------------------------------------------+
void DetectMarketRegime()
{
   double adx_array[], atr_array[];
   ArraySetAsSeries(adx_array, true);
   ArraySetAsSeries(atr_array, true);
   
   if(CopyBuffer(handle_ADX_M15, 0, 0, 1, adx_array) <= 0) return;
   if(CopyBuffer(handle_ATR_M15, 0, 0, 20, atr_array) <= 0) return;
   
   double adx = adx_array[0];
   double current_atr = atr_array[0];
   
   // Calcular ATR promedio
   double total_atr = 0;
   for(int i = 0; i < 20; i++)
   {
      total_atr += atr_array[i];
   }
   double avg_atr = total_atr / 20;
   
   // Determinar régimen
   if(adx > ADX_TrendingLevel)
   {
      current_regime = TRENDING;
   }
   else if(adx < ADX_RangingLevel)
   {
      current_regime = RANGING;
   }
   else if(current_atr > avg_atr * 1.5)
   {
      current_regime = VOLATILE;
   }
   else
   {
      current_regime = RANGING;
   }
}

//+------------------------------------------------------------------+
//| FASE 3: Ajustar Estrategia por Régimen                           |
//+------------------------------------------------------------------+
void AdjustStrategyByRegime()
{
   if(!UseAdaptiveScoring) return;
   
   switch(current_regime)
   {
      case TRENDING:
         adaptive_min_score = MinScoreToTrade - 1; // Más agresivo
         if(adaptive_min_score < 3) adaptive_min_score = 3;
         break;
         
      case RANGING:
         adaptive_min_score = MinScoreToTrade; // Normal
         break;
         
      case VOLATILE:
         adaptive_min_score = MinScoreToTrade + 1; // Ligeramente conservador
         if(adaptive_min_score > 8) adaptive_min_score = 8;
         break;
   }
}

//+------------------------------------------------------------------+
//| FASE 3: Calcular Multiplicador de Volatilidad                    |
//+------------------------------------------------------------------+
double CalculateVolatilityMultiplier()
{
   double atr_array[];
   ArraySetAsSeries(atr_array, true);
   
   if(CopyBuffer(handle_ATR_M15, 0, 0, 20, atr_array) <= 0) return 1.0;
   
   double current_atr = atr_array[0];
   
   // Calcular ATR promedio
   double total_atr = 0;
   for(int i = 0; i < 20; i++)
   {
      total_atr += atr_array[i];
   }
   double avg_atr = total_atr / 20;
   
   double volatility_ratio = current_atr / avg_atr;
   
   // Ajustar multiplicador
   if(volatility_ratio > 1.5)
   {
      // Alta volatilidad → Reducir lote
      return VolatilityMultiplierMin;
   }
   else if(volatility_ratio < 0.7)
   {
      // Baja volatilidad → Aumentar lote
      return VolatilityMultiplierMax;
   }
   else
   {
      // Volatilidad normal
      return 1.0;
   }
}

//+------------------------------------------------------------------+
//| FASE 3: Actualizar Estadísticas Adaptativas                      |
//+------------------------------------------------------------------+
void UpdateAdaptiveStats(bool is_win)
{
   if(!UseAdaptiveScoring) return;
   
   trades_for_adaptation++;
   if(is_win) wins_in_period++;
   
   // Calcular cada 20 trades
   if(trades_for_adaptation >= AdaptivePeriod)
   {
      last_20_trades_wr = (double)wins_in_period / (double)trades_for_adaptation;
      
      // Ajustar score mínimo basado en performance
      if(last_20_trades_wr > 0.70)
      {
         // Win rate alto → Ser más agresivo
         adaptive_min_score = MinScoreToTrade - 2;
         if(adaptive_min_score < 10) adaptive_min_score = 10;
         Print("📊 Adaptive: WR=", (int)(last_20_trades_wr*100), "% → Score mínimo: ", adaptive_min_score, " (AGRESIVO)");
      }
      else if(last_20_trades_wr < 0.55)
      {
         // Win rate bajo → Ser más conservador
         adaptive_min_score = MinScoreToTrade + 3;
         if(adaptive_min_score > 18) adaptive_min_score = 18;
         Print("📊 Adaptive: WR=", (int)(last_20_trades_wr*100), "% → Score mínimo: ", adaptive_min_score, " (CONSERVADOR)");
      }
      else
      {
         // Win rate normal → Mantener
         adaptive_min_score = MinScoreToTrade;
         Print("📊 Adaptive: WR=", (int)(last_20_trades_wr*100), "% → Score mínimo: ", adaptive_min_score, " (NORMAL)");
      }
      
      // Reset contadores
      trades_for_adaptation = 0;
      wins_in_period = 0;
   }
}

//+------------------------------------------------------------------+
//| FASE 4: Detectar Sesión Actual                                   |
//+------------------------------------------------------------------+
void DetectCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   if(hour >= 8 && hour < 12)
   {
      current_session = LONDON;
   }
   else if(hour >= 12 && hour < 13)
   {
      current_session = OVERLAP;  // Londres-NY overlap
   }
   else if(hour >= 13 && hour < 17)
   {
      current_session = NEWYORK;
   }
   else
   {
      current_session = ASIA;
   }
}

//+------------------------------------------------------------------+
//| FASE 4: Ajustar Estrategia por Sesión                            |
//+------------------------------------------------------------------+
void AdjustBySession()
{
   switch(current_session)
   {
      case LONDON:
         session_risk_multiplier = LondonRiskMultiplier;
         session_min_score_adjustment = -1;  // Más agresivo
         break;
         
      case OVERLAP:
         session_risk_multiplier = 1.1;  // Muy buena sesión
         session_min_score_adjustment = -1;  // Más agresivo
         break;
         
      case NEWYORK:
         session_risk_multiplier = NYRiskMultiplier;
         session_min_score_adjustment = 0;
         break;
         
      case ASIA:
         session_risk_multiplier = AsiaRiskMultiplier;
         session_min_score_adjustment = +1;  // Solo un poco más conservador
         break;
   }
}

//+------------------------------------------------------------------+
//| FASE 4: Verificar si es Hora de Noticias                         |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   // Implementación simplificada: evitar primeros 30 min de cada hora
   // En producción, usar calendario económico real
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Evitar primeros 30 min de horas clave (8:30, 9:30, 13:30, 14:30, 15:30)
   if(dt.min < NewsAvoidanceMinutes)
   {
      if(dt.hour == 8 || dt.hour == 9 || dt.hour == 13 || dt.hour == 14 || dt.hour == 15)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| FASE 4: Verificar Protección de Profits                          |
//+------------------------------------------------------------------+
void CheckProfitProtection()
{
   if(dailyPnL >= ProfitProtectionLevel2)
   {
      trading_stopped_today = true;
      if(!profit_protection_active)
      {
         Print("💰💰 PROFIT PROTECTION LEVEL 2: Trading detenido por hoy. Profit: $", (int)dailyPnL);
      }
      profit_protection_active = true;
      return;
   }
   
   if(dailyPnL >= ProfitProtectionLevel1)
   {
      if(!profit_protection_active)
      {
         Print("💰 PROFIT PROTECTION LEVEL 1: Riesgo reducido 50%. Profit: $", (int)dailyPnL);
      }
      profit_protection_active = true;
      return;
   }
   
   profit_protection_active = false;
}

//+------------------------------------------------------------------+
//| FASE 4: Calcular Smart Stop Loss                                 |
//+------------------------------------------------------------------+
double CalculateSmartSL(bool is_long, double entry_price)
{
   if(!UseSmartStopLoss)
   {
      // Usar SL normal
      int sl_pips, tp_pips;
      CalculateDynamicSLTP(sl_pips, tp_pips);
      
      if(is_long)
         return entry_price - sl_pips * _Point * 10;
      else
         return entry_price + sl_pips * _Point * 10;
   }
   
   // Buscar último swing high/low
   double swing_level = FindNearestSwingLevel(is_long);
   
   if(swing_level == 0)
   {
      // No se encontró swing, usar SL normal
      int sl_pips, tp_pips;
      CalculateDynamicSLTP(sl_pips, tp_pips);
      
      if(is_long)
         return entry_price - sl_pips * _Point * 10;
      else
         return entry_price + sl_pips * _Point * 10;
   }
   
   // Colocar SL 5 pips detrás del swing
   if(is_long)
      return swing_level - 5 * _Point * 10;
   else
      return swing_level + 5 * _Point * 10;
}

//+------------------------------------------------------------------+
//| FASE 4: Encontrar Nivel de Swing Más Cercano                     |
//+------------------------------------------------------------------+
double FindNearestSwingLevel(bool is_long)
{
   double high_array[], low_array[];
   ArraySetAsSeries(high_array, true);
   ArraySetAsSeries(low_array, true);
   
   ENUM_TIMEFRAMES tf = PERIOD_M5;
   
   if(CopyHigh(_Symbol, tf, 0, SwingLookback, high_array) <= 0) return 0;
   if(CopyLow(_Symbol, tf, 0, SwingLookback, low_array) <= 0) return 0;
   
   if(is_long)
   {
      // Buscar swing low más cercano
      double min_low = low_array[0];
      for(int i = 1; i < SwingLookback; i++)
      {
         if(low_array[i] < min_low)
            min_low = low_array[i];
      }
      return min_low;
   }
   else
   {
      // Buscar swing high más cercano
      double max_high = high_array[0];
      for(int i = 1; i < SwingLookback; i++)
      {
         if(high_array[i] > max_high)
            max_high = high_array[i];
      }
      return max_high;
   }
}

//+------------------------------------------------------------------+
//| Trade transaction event                                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      long dealEntry = 0;
      if(HistoryDealSelect(trans.deal))
      {
         dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         
         if(dealEntry == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            dailyPnL += profit;
            
            bool is_win = (profit > 0);
            
            if(profit < 0)
            {
               consecutiveLosses++;
               Print("❌ Pérdida: $", (int)profit, " | Consecutivas: ", consecutiveLosses);
            }
            else
            {
               consecutiveLosses = 0;
               Print("✓ Ganancia: $", (int)profit, " | Consecutivas reseteadas");
            }
            
            // FASE 3: Actualizar estadísticas adaptativas
            UpdateAdaptiveStats(is_win);
            
            Print("P/L del día: $", (int)dailyPnL, " | Trades hoy: ", tradesToday);
         }
      }
   }
}
//+------------------------------------------------------------------+
