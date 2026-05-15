//+------------------------------------------------------------------+
//|                                        InstitutionalFlow_EA.mq5 |
//|                                  Estrategia Dual Sesiones XAUUSD |
//|                                      Optimizada para Prop Firms |
//+------------------------------------------------------------------+
#property copyright "Institutional Flow Strategy"
#property link      ""
#property version   "1.00"
#property strict

// Inputs de Gestión de Riesgo
input double RiskPercent = 1.5;              // Riesgo por trade (%)
input int StopLossPips = 60;                 // Stop Loss en pips
input int TakeProfitPips = 120;              // Take Profit en pips (RR 1:2)
input int BreakEvenPips = 40;                // Break Even a X pips

// Inputs de Trading
input int MagicNumber = 123456;              // Magic Number
input int MaxTradesPerDay = 2;               // Máximo trades por día
input int MaxConsecutiveLosses = 2;          // Stop después de X pérdidas
input double MaxDailyLossDollars = 150.0;    // Pérdida máxima diaria ($)
input int MinScoreToTrade = 14;              // Score mínimo para operar

// Inputs de Horario
input int LondonStartHour = 8;               // Inicio sesión Londres (UTC)
input int LondonEndHour = 12;                // Fin sesión Londres (UTC)
input int NYStartHour = 13;                  // Inicio sesión NY (UTC)
input int NYEndHour = 17;                    // Fin sesión NY (UTC)

// Inputs de Indicadores
input int EMA_Fast = 50;                     // EMA Rápida
input int EMA_Slow = 200;                    // EMA Lenta
input int RSI_Period = 14;                   // Período RSI
input int RSI_Level = 50;                    // Nivel RSI

// Inputs de Filtros
input int MaxSpreadPips = 6;                 // Spread máximo
input int MaxDailyRangePips = 280;           // Rango diario máximo
input bool TradeMonday = false;              // Operar lunes
input bool TradeFriday = false;              // Operar viernes

// Variables globales
int consecutiveLosses = 0;
int tradesToday = 0;
double dailyPnL = 0.0;
datetime lastTradeDate = 0;
datetime lastBarTime = 0;

// Handles de indicadores
int handle_EMA50_D1;
int handle_EMA200_D1;
int handle_RSI_H1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Institutional Flow EA Iniciado ===");
   Print("Símbolo: ", _Symbol);
   Print("Riesgo: ", RiskPercent, "%");
   Print("SL: ", StopLossPips, " pips | TP: ", TakeProfitPips, " pips");
   Print("Score mínimo: ", MinScoreToTrade);
   
   // Crear handles de indicadores
   handle_EMA50_D1 = iMA(_Symbol, PERIOD_D1, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handle_EMA200_D1 = iMA(_Symbol, PERIOD_D1, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handle_RSI_H1 = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
   
   if(handle_EMA50_D1 == INVALID_HANDLE || handle_EMA200_D1 == INVALID_HANDLE || handle_RSI_H1 == INVALID_HANDLE)
   {
      Print("Error al crear indicadores");
      return(INIT_FAILED);
   }
   
   Print("Indicadores inicializados correctamente");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar handles de indicadores
   if(handle_EMA50_D1 != INVALID_HANDLE) IndicatorRelease(handle_EMA50_D1);
   if(handle_EMA200_D1 != INVALID_HANDLE) IndicatorRelease(handle_EMA200_D1);
   if(handle_RSI_H1 != INVALID_HANDLE) IndicatorRelease(handle_RSI_H1);
   
   Print("=== Institutional Flow EA Detenido ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar nueva vela en M15
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // Resetear contadores diarios
   ResetDailyCounters();
   
   // Verificar si ya hay posición abierta
   if(PositionSelect(_Symbol))
   {
      ManageOpenPosition();
      return;
   }
   
   // Verificar filtros globales
   if(!CheckGlobalFilters()) return;
   
   // Buscar señal de entrada
   int signal = AnalyzeMarket();
   
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
      dailyPnL = 0.0;
      lastTradeDate = currentDate;
      Print("Nuevo día de trading - Contadores reseteados");
   }
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
   {
      return false;
   }
   
   if(dayOfWeek == 5 && !TradeFriday && dt.hour >= 14)
   {
      return false;
   }
   
   // Verificar horario
   int currentHour = dt.hour;
   bool inLondonSession = (currentHour >= LondonStartHour && currentHour < LondonEndHour);
   bool inNYSession = (currentHour >= NYStartHour && currentHour < NYEndHour);
   
   if(!inLondonSession && !inNYSession)
   {
      return false;
   }
   
   // Verificar spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point / 10;
   if(spread > MaxSpreadPips)
   {
      return false;
   }
   
   // Verificar rango diario
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dailyLow = iLow(_Symbol, PERIOD_D1, 0);
   double dailyRange = (dailyHigh - dailyLow) / _Point / 10;
   
   if(dailyRange > MaxDailyRangePips)
   {
      return false;
   }
   
   // Verificar límites de trading
   if(tradesToday >= MaxTradesPerDay)
   {
      return false;
   }
   
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      return false;
   }
   
   if(dailyPnL <= -MaxDailyLossDollars)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Analizar mercado y generar señal                                 |
//+------------------------------------------------------------------+
int AnalyzeMarket()
{
   int score = 0;
   bool biasLong = false;
   bool biasShort = false;
   
   // PASO 1: Verificar Bias D1
   if(!CheckBiasD1(biasLong, biasShort, score))
   {
      return 0;
   }
   
   // PASO 2: Buscar zona institucional H4
   bool orderBlockFound = false;
   bool isOrderBlockBullish = false;
   
   if(!FindInstitutionalZone(orderBlockFound, isOrderBlockBullish, score))
   {
      return 0;
   }
   
   // PASO 3: Verificar confirmación H1
   bool h1Confirmed = false;
   bool h1Bullish = false;
   
   if(!CheckH1Confirmation(h1Confirmed, h1Bullish, score))
   {
      return 0;
   }
   
   // PASO 4: Verificar timing M15
   bool m15Confirmed = false;
   bool m15Bullish = false;
   
   if(!CheckM15Timing(m15Confirmed, m15Bullish, score))
   {
      return 0;
   }
   
   // Verificar score mínimo
   if(score < MinScoreToTrade)
   {
      Print("Score insuficiente: ", score, " (mínimo: ", MinScoreToTrade, ")");
      return 0;
   }
   
   // Determinar señal
   if(biasLong && isOrderBlockBullish && h1Bullish && m15Bullish)
   {
      Print("=== SEÑAL LONG === Score: ", score);
      return 1;
   }
   else if(biasShort && !isOrderBlockBullish && !h1Bullish && !m15Bullish)
   {
      Print("=== SEÑAL SHORT === Score: ", score);
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Verificar Bias en D1                                             |
//+------------------------------------------------------------------+
bool CheckBiasD1(bool &biasLong, bool &biasShort, int &score)
{
   double ema50_array[], ema200_array[], close_array[];
   ArraySetAsSeries(ema50_array, true);
   ArraySetAsSeries(ema200_array, true);
   ArraySetAsSeries(close_array, true);
   
   if(CopyBuffer(handle_EMA50_D1, 0, 0, 1, ema50_array) <= 0) return false;
   if(CopyBuffer(handle_EMA200_D1, 0, 0, 1, ema200_array) <= 0) return false;
   if(CopyClose(_Symbol, PERIOD_D1, 0, 1, close_array) <= 0) return false;
   
   double ema50_d1 = ema50_array[0];
   double ema200_d1 = ema200_array[0];
   double close_d1 = close_array[0];
   
   // Bias alcista
   if(close_d1 > ema50_d1 && ema50_d1 > ema200_d1)
   {
      double distance = (close_d1 - ema50_d1) / _Point / 10;
      if(distance < 200)
      {
         biasLong = true;
         score += 2;
         return true;
      }
   }
   
   // Bias bajista
   if(close_d1 < ema50_d1 && ema50_d1 < ema200_d1)
   {
      double distance = (ema50_d1 - close_d1) / _Point / 10;
      if(distance < 200)
      {
         biasShort = true;
         score += 2;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Buscar zona institucional en H4                                  |
//+------------------------------------------------------------------+
bool FindInstitutionalZone(bool &found, bool &isBullish, int &score)
{
   double open_array[], close_array[], high_array[], low_array[];
   ArraySetAsSeries(open_array, true);
   ArraySetAsSeries(close_array, true);
   ArraySetAsSeries(high_array, true);
   ArraySetAsSeries(low_array, true);
   
   if(CopyOpen(_Symbol, PERIOD_H4, 0, 21, open_array) <= 0) return false;
   if(CopyClose(_Symbol, PERIOD_H4, 0, 21, close_array) <= 0) return false;
   if(CopyHigh(_Symbol, PERIOD_H4, 0, 21, high_array) <= 0) return false;
   if(CopyLow(_Symbol, PERIOD_H4, 0, 21, low_array) <= 0) return false;
   
   // Buscar Order Block en últimas 20 velas H4
   for(int i = 1; i <= 20; i++)
   {
      double open_h4 = open_array[i];
      double close_h4 = close_array[i];
      double high_h4 = high_array[i];
      double low_h4 = low_array[i];
      
      double candleBody = MathAbs(close_h4 - open_h4) / _Point / 10;
      
      // Order Block alcista (vela bajista antes de impulso alcista)
      if(close_h4 < open_h4 && candleBody > 20)
      {
         // Verificar impulso alcista después
         double impulseHigh = high_array[i-1];
         double impulseLow = low_array[i-1];
         double impulseSize = (impulseHigh - impulseLow) / _Point / 10;
         
         if(impulseSize > 80 && close_array[i-1] > open_array[i-1])
         {
            // Verificar si precio actual está cerca del OB
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double distanceToOB = MathAbs(currentPrice - low_h4) / _Point / 10;
            
            if(distanceToOB < 20)
            {
               found = true;
               isBullish = true;
               score += 3;
               return true;
            }
         }
      }
      
      // Order Block bajista (vela alcista antes de impulso bajista)
      if(close_h4 > open_h4 && candleBody > 20)
      {
         // Verificar impulso bajista después
         double impulseHigh = high_array[i-1];
         double impulseLow = low_array[i-1];
         double impulseSize = (impulseHigh - impulseLow) / _Point / 10;
         
         if(impulseSize > 80 && close_array[i-1] < open_array[i-1])
         {
            // Verificar si precio actual está cerca del OB
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double distanceToOB = MathAbs(currentPrice - high_h4) / _Point / 10;
            
            if(distanceToOB < 20)
            {
               found = true;
               isBullish = false;
               score += 3;
               return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Verificar confirmación en H1                                     |
//+------------------------------------------------------------------+
bool CheckH1Confirmation(bool &confirmed, bool &isBullish, int &score)
{
   double open_array[], close_array[], high_array[], low_array[];
   long volume_array[];
   double rsi_array[];
   
   ArraySetAsSeries(open_array, true);
   ArraySetAsSeries(close_array, true);
   ArraySetAsSeries(high_array, true);
   ArraySetAsSeries(low_array, true);
   ArraySetAsSeries(volume_array, true);
   ArraySetAsSeries(rsi_array, true);
   
   if(CopyOpen(_Symbol, PERIOD_H1, 0, 12, open_array) <= 0) return false;
   if(CopyClose(_Symbol, PERIOD_H1, 0, 12, close_array) <= 0) return false;
   if(CopyHigh(_Symbol, PERIOD_H1, 0, 12, high_array) <= 0) return false;
   if(CopyLow(_Symbol, PERIOD_H1, 0, 12, low_array) <= 0) return false;
   if(CopyTickVolume(_Symbol, PERIOD_H1, 0, 12, volume_array) <= 0) return false;
   if(CopyBuffer(handle_RSI_H1, 0, 0, 2, rsi_array) <= 0) return false;
   
   double open_h1 = open_array[1];
   double close_h1 = close_array[1];
   double high_h1 = high_array[1];
   double low_h1 = low_array[1];
   
   double body = MathAbs(close_h1 - open_h1);
   double upperWick = high_h1 - MathMax(open_h1, close_h1);
   double lowerWick = MathMin(open_h1, close_h1) - low_h1;
   double totalSize = high_h1 - low_h1;
   
   // Pin bar alcista
   if(lowerWick > totalSize * 0.6 && close_h1 > open_h1)
   {
      double rsi = rsi_array[1];
      if(rsi > RSI_Level)
      {
         // Verificar volumen
         long volume = volume_array[1];
         long avgVolume = 0;
         for(int i = 2; i <= 11; i++)
         {
            avgVolume += volume_array[i];
         }
         avgVolume = avgVolume / 10;
         
         if(volume > avgVolume * 1.5)
         {
            confirmed = true;
            isBullish = true;
            score += 3; // Pin bar
            score += 2; // RSI
            score += 2; // Volumen
            return true;
         }
      }
   }
   
   // Pin bar bajista
   if(upperWick > totalSize * 0.6 && close_h1 < open_h1)
   {
      double rsi = rsi_array[1];
      if(rsi < RSI_Level)
      {
         long volume = volume_array[1];
         long avgVolume = 0;
         for(int i = 2; i <= 11; i++)
         {
            avgVolume += volume_array[i];
         }
         avgVolume = avgVolume / 10;
         
         if(volume > avgVolume * 1.5)
         {
            confirmed = true;
            isBullish = false;
            score += 3;
            score += 2;
            score += 2;
            return true;
         }
      }
   }
   
   // Engulfing alcista
   double open_h1_prev = open_array[2];
   double close_h1_prev = close_array[2];
   
   if(close_h1_prev < open_h1_prev && close_h1 > open_h1 && 
      close_h1 > open_h1_prev && open_h1 < close_h1_prev)
   {
      double rsi = rsi_array[1];
      if(rsi > RSI_Level)
      {
         confirmed = true;
         isBullish = true;
         score += 2; // Engulfing
         score += 2; // RSI
         return true;
      }
   }
   
   // Engulfing bajista
   if(close_h1_prev > open_h1_prev && close_h1 < open_h1 && 
      close_h1 < open_h1_prev && open_h1 > close_h1_prev)
   {
      double rsi = rsi_array[1];
      if(rsi < RSI_Level)
      {
         confirmed = true;
         isBullish = false;
         score += 2;
         score += 2;
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Verificar timing en M15                                          |
//+------------------------------------------------------------------+
bool CheckM15Timing(bool &confirmed, bool &isBullish, int &score)
{
   double open_array[], close_array[], high_array[], low_array[];
   ArraySetAsSeries(open_array, true);
   ArraySetAsSeries(close_array, true);
   ArraySetAsSeries(high_array, true);
   ArraySetAsSeries(low_array, true);
   
   if(CopyOpen(_Symbol, PERIOD_M15, 0, 3, open_array) <= 0) return false;
   if(CopyClose(_Symbol, PERIOD_M15, 0, 3, close_array) <= 0) return false;
   if(CopyHigh(_Symbol, PERIOD_M15, 0, 3, high_array) <= 0) return false;
   if(CopyLow(_Symbol, PERIOD_M15, 0, 3, low_array) <= 0) return false;
   
   // Buscar Higher Low (alcista) o Lower High (bajista)
   double high_m15_1 = high_array[1];
   double low_m15_1 = low_array[1];
   double close_m15_1 = close_array[1];
   double open_m15_1 = open_array[1];
   
   double high_m15_2 = high_array[2];
   double low_m15_2 = low_array[2];
   
   // Higher Low (alcista)
   if(low_m15_1 > low_m15_2 && close_m15_1 > open_m15_1)
   {
      confirmed = true;
      isBullish = true;
      score += 2;
      return true;
   }
   
   // Lower High (bajista)
   if(high_m15_1 < high_m15_2 && close_m15_1 < open_m15_1)
   {
      confirmed = true;
      isBullish = false;
      score += 2;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Abrir trade                                                       |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calcular SL y TP
   double sl, tp;
   if(orderType == ORDER_TYPE_BUY)
   {
      sl = price - StopLossPips * _Point * 10;
      tp = price + TakeProfitPips * _Point * 10;
   }
   else
   {
      sl = price + StopLossPips * _Point * 10;
      tp = price - TakeProfitPips * _Point * 10;
   }
   
   // Calcular lote
   double lotSize = CalculateLotSize(StopLossPips);
   
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
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "Institutional Flow";
   
   // Enviar orden
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("=== TRADE ABIERTO ===");
         Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("Precio: ", price);
         Print("SL: ", sl, " (", StopLossPips, " pips)");
         Print("TP: ", tp, " (", TakeProfitPips, " pips)");
         Print("Lote: ", lotSize);
         
         tradesToday++;
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
//| Gestionar posición abierta                                       |
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
   
   // Mover a Break Even
   if(profitPips >= BreakEvenPips && positionSL != positionOpenPrice)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;
      request.sl = NormalizeDouble(positionOpenPrice + _Point * 10, _Digits); // +1 pip
      request.tp = PositionGetDouble(POSITION_TP);
      
      if(OrderSend(request, result))
      {
         Print("Break Even activado a +", BreakEvenPips, " pips");
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
               Print("Pérdida registrada. Consecutivas: ", consecutiveLosses);
            }
            else
            {
               consecutiveLosses = 0;
               Print("Ganancia registrada. Consecutivas reseteadas.");
            }
            
            Print("P/L del día: $", dailyPnL);
         }
      }
   }
}
//+------------------------------------------------------------------+
