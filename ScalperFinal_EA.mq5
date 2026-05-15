//+------------------------------------------------------------------+
//|                                        ScalperFinal_EA.mq5       |
//|                    BASADO EN v5.20 QUE SÍ OPERÓ                  |
//|                    SOLO MEJORAMOS SL/TP                          |
//+------------------------------------------------------------------+
#property copyright "Scalper Final"
#property version   "9.00"
#property strict

// ============ INPUTS ============
input double RiskPercent = 1.5;
input int StopLossPips = 20;                 // SL más amplio que v5.20
input int TakeProfitPips = 40;               // TP más amplio (RR 1:2)
input int MagicNumber = 999999;

// Indicadores (igual que v5.20)
input int EMA_Fast = 9;
input int EMA_Slow = 21;
input int RSI_Period = 14;

// Horario
input int StartHour = 8;
input int EndHour = 17;
input int MaxTradesPerDay = 30;

// ============ VARIABLES ============
int handle_EMA_Fast, handle_EMA_Slow, handle_RSI;
int tradesToday = 0;
datetime lastTradeDate = 0;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SCALPER FINAL v9.0 (Basado en v5.20) ===");
   Print("SL: ", StopLossPips, "p | TP: ", TakeProfitPips, "p");
   
   handle_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handle_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   
   if(handle_EMA_Fast == INVALID_HANDLE || handle_EMA_Slow == INVALID_HANDLE || handle_RSI == INVALID_HANDLE)
   {
      Print("Error creando indicadores");
      return(INIT_FAILED);
   }
   
   Print("=== LISTO PARA OPERAR ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_EMA_Fast != INVALID_HANDLE) IndicatorRelease(handle_EMA_Fast);
   if(handle_EMA_Slow != INVALID_HANDLE) IndicatorRelease(handle_EMA_Slow);
   if(handle_RSI != INVALID_HANDLE) IndicatorRelease(handle_RSI);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // Reset diario
   datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDate != lastTradeDate)
   {
      tradesToday = 0;
      lastTradeDate = currentDate;
      Print("=== NUEVO DÍA ===");
   }
   
   // Si hay posición, salir
   if(PositionSelect(_Symbol)) return;
   
   // Verificar horario
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < StartHour || dt.hour >= EndHour) return;
   
   // Verificar límite
   if(tradesToday >= MaxTradesPerDay) return;
   
   // Analizar (IGUAL QUE v5.20)
   int signal = AnalyzeSignal();
   
   if(signal == 1)
   {
      Print("🟢 LONG");
      OpenTrade(ORDER_TYPE_BUY);
   }
   else if(signal == -1)
   {
      Print("🔴 SHORT");
      OpenTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
int AnalyzeSignal()
{
   double ema_fast[], ema_slow[], rsi[];
   ArraySetAsSeries(ema_fast, true);
   ArraySetAsSeries(ema_slow, true);
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(handle_EMA_Fast, 0, 0, 3, ema_fast) <= 0) return 0;
   if(CopyBuffer(handle_EMA_Slow, 0, 0, 3, ema_slow) <= 0) return 0;
   if(CopyBuffer(handle_RSI, 0, 0, 2, rsi) <= 0) return 0;
   
   double ema_fast_curr = ema_fast[0];
   double ema_fast_prev = ema_fast[1];
   double ema_slow_curr = ema_slow[0];
   double ema_slow_prev = ema_slow[1];
   double rsi_curr = rsi[0];
   
   // LONG: EMA cruza arriba + RSI > 50
   if(ema_fast_prev < ema_slow_prev && ema_fast_curr > ema_slow_curr && rsi_curr > 50)
   {
      Print("✅ Cruce alcista | RSI:", rsi_curr);
      return 1;
   }
   
   // SHORT: EMA cruza abajo + RSI < 50
   if(ema_fast_prev > ema_slow_prev && ema_fast_curr < ema_slow_curr && rsi_curr < 50)
   {
      Print("✅ Cruce bajista | RSI:", rsi_curr);
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
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
   
   double lotSize = CalculateLotSize(StopLossPips);
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   lotSize = NormalizeDouble(lotSize, 2);
   
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
   request.comment = "ScalperFinal";
   request.type_filling = ORDER_FILLING_IOC;
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("=== TRADE ABIERTO ===");
         Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("SL: ", StopLossPips, "p | TP: ", TakeProfitPips, "p");
         Print("Lote: ", lotSize);
         tradesToday++;
      }
      else
      {
         Print("Error: ", result.retcode);
      }
   }
}

//+------------------------------------------------------------------+
double CalculateLotSize(int slPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / tickSize * _Point;
   
   double lotSize = riskAmount / (slPips * 10 * pointValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   return lotSize;
}
//+------------------------------------------------------------------+
