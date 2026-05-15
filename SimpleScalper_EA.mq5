//+------------------------------------------------------------------+
//|                                            SimpleScalper_EA.mq5  |
//|                                  Estrategia Algorítmica Simple   |
//+------------------------------------------------------------------+
#property copyright "Simple Scalper"
#property version   "6.00"
#property strict

//+------------------------------------------------------------------+
//| ESTRATEGIA SIMPLE: EMA Crossover + RSI                           |
//| - EMA 9 cruza EMA 21 = Señal                                     |
//| - RSI confirma (>50 para long, <50 para short)                   |
//| - SL/TP fijos                                                    |
//+------------------------------------------------------------------+

// ============ INPUTS ============
input double RiskPercent = 1.5;              // Riesgo por trade (%)
input int StopLossPips = 20;                 // Stop Loss (pips)
input int TakeProfitPips = 40;               // Take Profit (pips) - RR 1:2
input int MagicNumber = 999999;              // Magic Number

// Indicadores
input int EMA_Fast = 9;                      // EMA Rápida
input int EMA_Slow = 21;                     // EMA Lenta
input int RSI_Period = 14;                   // Período RSI

// Horario
input int StartHour = 8;                     // Hora inicio (UTC)
input int EndHour = 17;                      // Hora fin (UTC)

// Límites
input int MaxTradesPerDay = 20;              // Máximo trades por día

// ============ VARIABLES GLOBALES ============
int handle_EMA_Fast;
int handle_EMA_Slow;
int handle_RSI;

int tradesToday = 0;
datetime lastTradeDate = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Simple Scalper EA v6.0 Iniciado ===");
   Print("Estrategia: EMA ", EMA_Fast, "/", EMA_Slow, " + RSI");
   Print("SL: ", StopLossPips, "p | TP: ", TakeProfitPips, "p | RR: 1:2");
   Print("Riesgo: ", RiskPercent, "%");
   
   // Crear indicadores
   handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handle_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   
   if(handle_EMA_Fast == INVALID_HANDLE || handle_EMA_Slow == INVALID_HANDLE || handle_RSI == INVALID_HANDLE)
   {
      Print("Error al crear indicadores");
      return(INIT_FAILED);
   }
   
   Print("=== EA LISTO PARA OPERAR ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handle_EMA_Fast);
   if(handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(handle_EMA_Slow);
   if(handle_RSI != INVALID_HANDLE) IndicatorRelease(handle_RSI);
   
   Print("=== Simple Scalper EA Detenido ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Solo operar en nueva vela M5
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   
   if(currentBarTime == lastBarTime)
      return;
   
   lastBarTime = currentBarTime;
   
   // Resetear contador diario
   datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDate != lastTradeDate)
   {
      tradesToday = 0;
      lastTradeDate = currentDate;
      Print("=== NUEVO DÍA - Contador reseteado ===");
   }
   
   // Verificar si ya hay posición
   if(PositionSelect(_Symbol))
      return;
   
   // Verificar filtros básicos
   if(!CheckBasicFilters())
      return;
   
   // Analizar señal
   int signal = AnalyzeSignal();
   
   if(signal == 1)
   {
      Print("🟢 SEÑAL LONG");
      OpenTrade(ORDER_TYPE_BUY);
   }
   else if(signal == -1)
   {
      Print("🔴 SEÑAL SHORT");
      OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Verificar filtros básicos                                        |
//+------------------------------------------------------------------+
bool CheckBasicFilters()
{
   // Verificar horario
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.hour < StartHour || dt.hour >= EndHour)
   {
      //Print("Fuera de horario");
      return false;
   }
   
   // Verificar límite diario
   if(tradesToday >= MaxTradesPerDay)
   {
      Print("Límite diario alcanzado: ", tradesToday);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Analizar señal - ESTRATEGIA SIMPLE                               |
//+------------------------------------------------------------------+
int AnalyzeSignal()
{
   // Obtener valores de indicadores
   double ema_fast[], ema_slow[], rsi[];
   ArraySetAsSeries(ema_fast, true);
   ArraySetAsSeries(ema_slow, true);
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(handle_EMA_Fast, 0, 0, 3, ema_fast) <= 0) return 0;
   if(CopyBuffer(handle_EMA_Slow, 0, 0, 3, ema_slow) <= 0) return 0;
   if(CopyBuffer(handle_RSI, 0, 0, 2, rsi) <= 0) return 0;
   
   // Valores actuales y anteriores
   double ema_fast_current = ema_fast[0];
   double ema_fast_prev = ema_fast[1];
   double ema_slow_current = ema_slow[0];
   double ema_slow_prev = ema_slow[1];
   double rsi_current = rsi[0];
   
   // SEÑAL LONG: EMA rápida cruza hacia arriba + RSI > 50
   if(ema_fast_prev < ema_slow_prev && ema_fast_current > ema_slow_current && rsi_current > 50)
   {
      Print("✅ Cruce alcista detectado | EMA Fast:", ema_fast_current, " > EMA Slow:", ema_slow_current, " | RSI:", rsi_current);
      return 1;
   }
   
   // SEÑAL SHORT: EMA rápida cruza hacia abajo + RSI < 50
   if(ema_fast_prev > ema_slow_prev && ema_fast_current < ema_slow_current && rsi_current < 50)
   {
      Print("✅ Cruce bajista detectado | EMA Fast:", ema_fast_current, " < EMA Slow:", ema_slow_current, " | RSI:", rsi_current);
      return -1;
   }
   
   return 0;
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
   
   // Normalizar
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Preparar orden
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
   request.comment = "SimpleScalper";
   request.type_filling = ORDER_FILLING_IOC;
   
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
         Print("Error al abrir trade: ", result.retcode);
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
