//+------------------------------------------------------------------+
//|                              InstitutionalFlow_Scalping_EA.mq5   |
//|                           SCALPING VERSION - Todas las Fases     |
//|                                      Optimizado para Scalping    |
//+------------------------------------------------------------------+
#property copyright "Institutional Flow Scalping Strategy"
#property link      ""
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| FASE 1: MEJORAS ESENCIALES                                       |
//| 1. Timeframes M1/M5                                              |
//| 2. ATR dinámico para SL/TP                                       |
//| 3. Trailing stop agresivo                                        |
//| 4. Break Even rápido                                             |
//| 5. Filtro de spread dinámico                                     |
//+------------------------------------------------------------------+

// ============ INPUTS DE GESTIÓN DE RIESGO ============
input double RiskPercent = 1.5;              // Riesgo por trade (%)
input bool UseATRforSLTP = true;             // Usar ATR dinámico para SL/TP
input double ATRMultiplierSL = 1.5;          // Multiplicador ATR para SL
input double ATRMultiplierTP = 3.0;          // Multiplicador ATR para TP (RR 1:2)
input int ManualStopLossPips = 15;           // SL manual si no usa ATR
input int ManualTakeProfitPips = 30;         // TP manual si no usa ATR

// ============ INPUTS DE SCALPING ============
input int ScalpingTimeframe = 1;             // Timeframe principal (1=M1, 5=M5)
input int BreakEvenPips = 5;                 // Break Even rápido (5 pips)
input bool UseAggressiveTrailing = true;     // Trailing stop agresivo
input int TrailingStartPips = 8;             // Iniciar trailing a X pips
input int TrailingStepPips = 3;              // Step del trailing
input int TrailingStopPips = 3;              // Distancia del trailing

// ============ INPUTS DE TRADING ============
input int MagicNumber = 123457;              // Magic Number
input int MaxTradesPerHour = 10;             // Máximo trades por hora
input int MaxTradesPerDay = 50;              // Máximo trades por día
input int MaxConsecutiveLosses = 3;          // Stop después de X pérdidas
input double MaxDailyLossDollars = 200.0;    // Pérdida máxima diaria ($)
input int MinScoreToTrade = 12;              // Score mínimo (más bajo para scalping)

// ============ INPUTS DE HORARIO ============
input int LondonStartHour = 8;               // Inicio sesión Londres (UTC)
input int LondonEndHour = 12;                // Fin sesión Londres (UTC)
input int NYStartHour = 13;                  // Inicio sesión NY (UTC)
input int NYEndHour = 17;                    // Fin sesión NY (UTC)
input bool TradeAsianSession = false;        // Operar sesión asiática

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
input int MaxSpreadPips_London = 3;          // Spread máximo Londres
input int MaxSpreadPips_NY = 3;              // Spread máximo NY
input int MaxSpreadPips_Other = 5;           // Spread máximo otras horas
input int MaxDailyRangePips = 300;           // Rango diario máximo
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

// ============ HANDLES DE INDICADORES ============
int handle_EMA_Fast_M15;
int handle_EMA_Slow_M15;
int handle_RSI_M5;
int handle_ATR_M5;
int handle_Stochastic_M1;
int handle_BB_M1;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Institutional Flow SCALPING EA Iniciado ===");
   Print("Versión: 2.00 - SCALPING (Todas las Fases)");
   Print("Símbolo: ", _Symbol);
   Print("Timeframe: M", ScalpingTimeframe);
   Print("Riesgo: ", RiskPercent, "%");
   Print("ATR Dinámico: ", UseATRforSLTP ? "SÍ" : "NO");
   Print("Break Even: ", BreakEvenPips, " pips");
   Print("Trailing: ", UseAggressiveTrailing ? "AGRESIVO" : "OFF");
   Print("Score mínimo: ", MinScoreToTrade);
   
   // Crear handles de indicadores
   ENUM_TIMEFRAMES tf_main = (ScalpingTimeframe == 1) ? PERIOD_M1 : PERIOD_M5;
   
   handle_EMA_Fast_M15 = iMA(_Symbol, PERIOD_M15, EMA_Fast_M15, 0, MODE_EMA, PRICE_CLOSE);
   handle_EMA_Slow_M15 = iMA(_Symbol, PERIOD_M15, EMA_Slow_M15, 0, MODE_EMA, PRICE_CLOSE);
   handle_RSI_M5 = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   handle_ATR_M5 = iATR(_Symbol, PERIOD_M5, ATR_Period);
   handle_Stochastic_M1 = iStochastic(_Symbol, PERIOD_M1, Stochastic_K, Stochastic_D, Stochastic_Slowing, MODE_SMA, STO_LOWHIGH);
   handle_BB_M1 = iBands(_Symbol, PERIOD_M1, 20, 0, 2, PRICE_CLOSE);
   
   if(handle_EMA_Fast_M15 == INVALID_HANDLE || handle_EMA_Slow_M15 == INVALID_HANDLE || 
      handle_RSI_M5 == INVALID_HANDLE || handle_ATR_M5 == INVALID_HANDLE ||
      handle_Stochastic_M1 == INVALID_HANDLE || handle_BB_M1 == INVALID_HANDLE)
   {
      Print("Error al crear indicadores");
      return(INIT_FAILED);
   }
   
   Print("Indicadores inicializados correctamente");
   Print("=== MODO SCALPING ACTIVADO ===");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar handles de indicadores
   if(handle_EMA_Fast_M15 != INVALID_HANDLE) IndicatorRelease(handle_EMA_Fast_M15);
   if(handle_EMA_Slow_M15 != INVALID_HANDLE) IndicatorRelease(handle_EMA_Slow_M15);
   if(handle_RSI_M5 != INVALID_HANDLE) IndicatorRelease(handle_RSI_M5);
   if(handle_ATR_M5 != INVALID_HANDLE) IndicatorRelease(handle_ATR_M5);
   if(handle_Stochastic_M1 != INVALID_HANDLE) IndicatorRelease(handle_Stochastic_M1);
   if(handle_BB_M1 != INVALID_HANDLE) IndicatorRelease(handle_BB_M1);
   
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
   
   // Resetear contadores
   ResetDailyCounters();
   ResetHourlyCounters();
   
   // Verificar si ya hay posición abierta
   if(PositionSelect(_Symbol))
   {
      ManageOpenPosition();
      return;
   }
   
   // Verificar filtros globales
   if(!CheckGlobalFilters()) return;
   
   // Buscar señal de entrada
   int signal = AnalyzeMarketScalping();
   
   if(signal == 1) // Señal LONG
   {
      OpenTrade(ORDER_TYPE_BUY);
   }
   else if(signal == -1) // Señal SHORT
   {
      OpenTrade(ORDER_TYPE_SELL);
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
//| Verificar filtros globales                                       |
//+------------------------------------------------------------------+
bool CheckGlobalFilters()
{
   // Verificar día de la semana
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dayOfWeek = dt.day_of_week;
   
   if(dayOfWeek == 1 && !TradeMonday)
      return false;
   
   if(dayOfWeek == 5 && !TradeFriday && dt.hour >= 14)
      return false;
   
   // Verificar horario
   int currentHour = dt.hour;
   bool inLondonSession = (currentHour >= LondonStartHour && currentHour < LondonEndHour);
   bool inNYSession = (currentHour >= NYStartHour && currentHour < NYEndHour);
   bool inAsianSession = (currentHour >= 0 && currentHour < 7);
   
   if(!inLondonSession && !inNYSession && (!TradeAsianSession || !inAsianSession))
      return false;
   
   // FASE 1: Spread dinámico
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point / 10;
   int maxSpread = GetMaxSpreadForCurrentHour();
   if(spread > maxSpread)
   {
      //Print("Spread muy alto: ", spread, " pips (máx: ", maxSpread, ")");
      return false;
   }
   
   // Verificar rango diario
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dailyLow = iLow(_Symbol, PERIOD_D1, 0);
   double dailyRange = (dailyHigh - dailyLow) / _Point / 10;
   
   if(dailyRange > MaxDailyRangePips)
      return false;
   
   // Verificar límites de trading
   if(tradesToday >= MaxTradesPerDay)
      return false;
   
   if(tradesThisHour >= MaxTradesPerHour)
      return false;
   
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      Print("Límite de pérdidas consecutivas alcanzado: ", consecutiveLosses);
      return false;
   }
   
   if(dailyPnL <= -MaxDailyLossDollars)
   {
      Print("Límite de pérdida diaria alcanzado: $", dailyPnL);
      return false;
   }
   
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
         
         // Límites mínimos y máximos para scalping
         if(sl_pips < 8) sl_pips = 8;
         if(sl_pips > 25) sl_pips = 25;
         if(tp_pips < 15) tp_pips = 15;
         if(tp_pips > 50) tp_pips = 50;
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
//| Analizar mercado para SCALPING                                   |
//+------------------------------------------------------------------+
int AnalyzeMarketScalping()
{
   int score = 0;
   bool biasLong = false;
   bool biasShort = false;
   
   // PASO 1: Verificar Bias M15 (más rápido que D1)
   if(!CheckBiasM15(biasLong, biasShort, score))
      return 0;
   
   // PASO 2: Verificar confirmación M5
   bool m5Confirmed = false;
   bool m5Bullish = false;
   
   if(!CheckM5Confirmation(m5Confirmed, m5Bullish, score))
      return 0;
   
   // PASO 3: Verificar timing M1 con Stochastic
   bool m1Confirmed = false;
   bool m1Bullish = false;
   
   if(!CheckM1TimingWithStochastic(m1Confirmed, m1Bullish, score))
      return 0;
   
   // PASO 4: Verificar Bollinger Bands
   CheckBollingerBands(score);
   
   // Verificar score mínimo
   if(score < MinScoreToTrade)
   {
      //Print("Score insuficiente: ", score, " (mínimo: ", MinScoreToTrade, ")");
      return 0;
   }
   
   // Determinar señal
   if(biasLong && m5Bullish && m1Bullish)
   {
      Print("=== SEÑAL SCALPING LONG === Score: ", score);
      return 1;
   }
   else if(biasShort && !m5Bullish && !m1Bullish)
   {
      Print("=== SEÑAL SCALPING SHORT === Score: ", score);
      return -1;
   }
   
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
      score += 2;
      return true;
   }
   
   // Bias bajista
   if(close_m15 < ema_fast && ema_fast < ema_slow)
   {
      biasShort = true;
      score += 2;
      return true;
   }
   
   return false;
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
   
   if(CopyOpen(_Symbol, PERIOD_M5, 0, 3, open_array) <= 0) return false;
   if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close_array) <= 0) return false;
   if(CopyHigh(_Symbol, PERIOD_M5, 0, 3, high_array) <= 0) return false;
   if(CopyLow(_Symbol, PERIOD_M5, 0, 3, low_array) <= 0) return false;
   if(CopyBuffer(handle_RSI_M5, 0, 0, 2, rsi_array) <= 0) return false;
   
   double open_m5 = open_array[1];
   double close_m5 = close_array[1];
   double high_m5 = high_array[1];
   double low_m5 = low_array[1];
   double rsi = rsi_array[1];
   
   double body = MathAbs(close_m5 - open_m5);
   double upperWick = high_m5 - MathMax(open_m5, close_m5);
   double lowerWick = MathMin(open_m5, close_m5) - low_m5;
   double totalSize = high_m5 - low_m5;
   
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
   
   return false;
}

//+------------------------------------------------------------------+
//| Verificar timing M1 con Stochastic                               |
//+------------------------------------------------------------------+
bool CheckM1TimingWithStochastic(bool &confirmed, bool &isBullish, int &score)
{
   double stoch_main[], stoch_signal[];
   ArraySetAsSeries(stoch_main, true);
   ArraySetAsSeries(stoch_signal, true);
   
   if(CopyBuffer(handle_Stochastic_M1, 0, 0, 2, stoch_main) <= 0) return false;
   if(CopyBuffer(handle_Stochastic_M1, 1, 0, 2, stoch_signal) <= 0) return false;
   
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
   
   return false;
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
//| Abrir trade con SL/TP dinámico                                   |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // FASE 1: Calcular SL/TP con ATR dinámico
   int sl_pips, tp_pips;
   CalculateDynamicSLTP(sl_pips, tp_pips);
   
   // Calcular SL y TP
   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = price - sl_pips * _Point * 10;
      tp = price + tp_pips * _Point * 10;
   }
   else
   {
      sl = price + sl_pips * _Point * 10;
      tp = price - tp_pips * _Point * 10;
   }
   
   // Calcular lote
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
         Print("SL: ", sl, " (", sl_pips, " pips)");
         Print("TP: ", tp, " (", tp_pips, " pips)");
         Print("Lote: ", lotSize);
         Print("ATR Dinámico: ", UseATRforSLTP ? "SÍ" : "NO");
         
         tradesToday++;
         tradesThisHour++;
         maxProfitReached = 0.0; // Reset para nuevo trade
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
//| Calcular tamaño de lote                                          |
//+------------------------------------------------------------------+
double CalculateLotSize(int slPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / tickSize * _Point;
   
   double lotSize = riskAmount / (slPips * 10 * pointValue);
   
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
            
            Print("P/L del día: $", (int)dailyPnL, " | Trades hoy: ", tradesToday);
         }
      }
   }
}
//+------------------------------------------------------------------+
