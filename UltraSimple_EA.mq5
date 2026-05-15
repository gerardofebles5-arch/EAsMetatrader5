//+------------------------------------------------------------------+
//|                                           UltraSimple_EA.mq5     |
//|                              GARANTIZADO QUE OPERA               |
//+------------------------------------------------------------------+
#property copyright "Ultra Simple"
#property version   "7.00"
#property strict

//+------------------------------------------------------------------+
//| ESTRATEGIA MÁS SIMPLE POSIBLE:                                   |
//| - Precio > SMA 50 = LONG                                         |
//| - Precio < SMA 50 = SHORT                                        |
//| - Opera en CADA vela si no hay posición                          |
//+------------------------------------------------------------------+

// ============ INPUTS ============
input double RiskPercent = 1.5;              // Riesgo por trade (%)
input int StopLossPips = 20;                 // Stop Loss (pips)
input int TakeProfitPips = 40;               // Take Profit (pips)
input int MagicNumber = 777777;              // Magic Number
input int SMA_Period = 50;                   // Período SMA

// ============ VARIABLES GLOBALES ============
int handle_SMA;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== ULTRA SIMPLE EA v7.0 ===");
   Print("Estrategia: Precio vs SMA ", SMA_Period);
   Print("Precio > SMA = LONG | Precio < SMA = SHORT");
   Print("SL: ", StopLossPips, "p | TP: ", TakeProfitPips, "p");
   
   // Crear SMA
   handle_SMA = iMA(_Symbol, PERIOD_M5, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
   
   if(handle_SMA == INVALID_HANDLE)
   {
      Print("Error al crear SMA");
      return(INIT_FAILED);
   }
   
   Print("=== LISTO - OPERARÁ EN CADA VELA ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_SMA != INVALID_HANDLE) IndicatorRelease(handle_SMA);
   Print("=== EA Detenido ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Operar en cada nueva vela M5
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   
   if(currentBarTime == lastBarTime)
      return;
   
   lastBarTime = currentBarTime;
   
   Print("🔄 Nueva vela M5: ", TimeToString(currentBarTime));
   
   // Si ya hay posición, no abrir otra
   if(PositionSelect(_Symbol))
   {
      Print("📊 Ya hay posición abierta");
      return;
   }
   
   // Obtener precio y SMA
   double close_price = iClose(_Symbol, PERIOD_M5, 0);
   
   double sma[];
   ArraySetAsSeries(sma, true);
   
   if(CopyBuffer(handle_SMA, 0, 0, 1, sma) <= 0)
   {
      Print("❌ Error al obtener SMA");
      return;
   }
   
   double sma_value = sma[0];
   
   Print("💹 Precio: ", close_price, " | SMA: ", sma_value);
   
   // SEÑAL LONG: Precio > SMA
   if(close_price > sma_value)
   {
      Print("🟢 LONG: Precio (", close_price, ") > SMA (", sma_value, ")");
      OpenTrade(ORDER_TYPE_BUY);
   }
   // SEÑAL SHORT: Precio < SMA
   else if(close_price < sma_value)
   {
      Print("🔴 SHORT: Precio (", close_price, ") < SMA (", sma_value, ")");
      OpenTrade(ORDER_TYPE_SELL);
   }
   else
   {
      Print("⚠️ Precio = SMA (raro)");
   }
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
   request.comment = "UltraSimple";
   request.type_filling = ORDER_FILLING_IOC;
   
   // Enviar orden
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("✅ === TRADE ABIERTO ===");
         Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("Precio: ", price);
         Print("SL: ", sl, " (", StopLossPips, "p)");
         Print("TP: ", tp, " (", TakeProfitPips, "p)");
         Print("Lote: ", lotSize);
      }
      else
      {
         Print("❌ Error: ", result.retcode, " - ", result.comment);
      }
   }
   else
   {
      Print("❌ OrderSend falló: ", GetLastError());
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
