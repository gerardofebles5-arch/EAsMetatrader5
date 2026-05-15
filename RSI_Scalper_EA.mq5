//+------------------------------------------------------------------+
//|                                          RSI_Scalper_EA.mq5      |
//|                         RSI PURO - OPERA AUTOMÁTICAMENTE         |
//+------------------------------------------------------------------+
#property copyright "RSI Scalper"
#property version   "8.00"
#property strict

//+------------------------------------------------------------------+
//| ESTRATEGIA RSI PURA:                                             |
//| RSI < 30 (sobreventa) = LONG                                     |
//| RSI > 70 (sobrecompra) = SHORT                                   |
//| OPERA AUTOMÁTICAMENTE cuando se cumplen condiciones              |
//+------------------------------------------------------------------+

// ============ INPUTS ============
input double RiskPercent = 1.5;              // Riesgo por trade (%)
input int StopLossPips = 25;                 // Stop Loss (pips)
input int TakeProfitPips = 50;               // Take Profit (pips)
input int MagicNumber = 888888;              // Magic Number

// RSI
input int RSI_Period = 14;                   // Período RSI
input int RSI_Oversold = 30;                 // Nivel sobreventa
input int RSI_Overbought = 70;               // Nivel sobrecompra

// ============ VARIABLES GLOBALES ============
int handle_RSI;
datetime lastBarTime = 0;
int tradesCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("=== RSI SCALPER EA v8.0 INICIADO ===");
   Print("========================================");
   Print("Estrategia: RSI ", RSI_Period);
   Print("RSI < ", RSI_Oversold, " = LONG");
   Print("RSI > ", RSI_Overbought, " = SHORT");
   Print("SL: ", StopLossPips, "p | TP: ", TakeProfitPips, "p");
   Print("Riesgo: ", RiskPercent, "%");
   Print("========================================");
   
   // Crear RSI
   handle_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   
   if(handle_RSI == INVALID_HANDLE)
   {
      Print("❌ ERROR: No se pudo crear RSI");
      return(INIT_FAILED);
   }
   
   Print("✅ RSI creado correctamente");
   Print("========================================");
   Print("🚀 EA LISTO - OPERARÁ AUTOMÁTICAMENTE");
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_RSI != INVALID_HANDLE) IndicatorRelease(handle_RSI);
   Print("========================================");
   Print("=== RSI SCALPER EA DETENIDO ===");
   Print("Total trades ejecutados: ", tradesCount);
   Print("========================================");
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
   
   Print("----------------------------------------");
   Print("🔄 NUEVA VELA M5: ", TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES));
   
   // Si ya hay posición, no abrir otra
   if(PositionSelect(_Symbol))
   {
      double profit = PositionGetDouble(POSITION_PROFIT);
      Print("📊 Posición abierta | Profit: $", NormalizeDouble(profit, 2));
      Print("----------------------------------------");
      return;
   }
   
   // Obtener RSI
   double rsi[];
   ArraySetAsSeries(rsi, true);
   
   if(CopyBuffer(handle_RSI, 0, 0, 2, rsi) <= 0)
   {
      Print("❌ ERROR: No se pudo obtener RSI");
      Print("----------------------------------------");
      return;
   }
   
   double rsi_current = rsi[0];
   double rsi_prev = rsi[1];
   
   Print("📊 RSI Actual: ", NormalizeDouble(rsi_current, 2));
   Print("📊 RSI Anterior: ", NormalizeDouble(rsi_prev, 2));
   
   // SEÑAL LONG: RSI sale de sobreventa
   if(rsi_prev < RSI_Oversold && rsi_current >= RSI_Oversold)
   {
      Print("🟢🟢🟢 SEÑAL LONG DETECTADA 🟢🟢🟢");
      Print("RSI salió de sobreventa: ", NormalizeDouble(rsi_prev, 2), " → ", NormalizeDouble(rsi_current, 2));
      OpenTrade(ORDER_TYPE_BUY);
      Print("----------------------------------------");
      return;
   }
   
   // SEÑAL SHORT: RSI sale de sobrecompra
   if(rsi_prev > RSI_Overbought && rsi_current <= RSI_Overbought)
   {
      Print("🔴🔴🔴 SEÑAL SHORT DETECTADA 🔴🔴🔴");
      Print("RSI salió de sobrecompra: ", NormalizeDouble(rsi_prev, 2), " → ", NormalizeDouble(rsi_current, 2));
      OpenTrade(ORDER_TYPE_SELL);
      Print("----------------------------------------");
      return;
   }
   
   // Alternativa: RSI en zona extrema (más agresivo)
   if(rsi_current < RSI_Oversold)
   {
      Print("🟢 RSI en sobreventa: ", NormalizeDouble(rsi_current, 2));
      Print("🟢 ABRIENDO LONG");
      OpenTrade(ORDER_TYPE_BUY);
      Print("----------------------------------------");
      return;
   }
   
   if(rsi_current > RSI_Overbought)
   {
      Print("🔴 RSI en sobrecompra: ", NormalizeDouble(rsi_current, 2));
      Print("🔴 ABRIENDO SHORT");
      OpenTrade(ORDER_TYPE_SELL);
      Print("----------------------------------------");
      return;
   }
   
   Print("⏸️ Sin señal | RSI en zona neutral: ", NormalizeDouble(rsi_current, 2));
   Print("----------------------------------------");
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
   
   Print("💼 Preparando orden...");
   Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
   Print("Precio: ", price);
   Print("SL: ", sl, " (", StopLossPips, "p)");
   Print("TP: ", tp, " (", TakeProfitPips, "p)");
   Print("Lote: ", lotSize);
   
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
   request.comment = "RSI_Scalper";
   request.type_filling = ORDER_FILLING_IOC;
   
   // Enviar orden
   Print("📤 Enviando orden...");
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         tradesCount++;
         Print("========================================");
         Print("✅✅✅ TRADE ABIERTO EXITOSAMENTE ✅✅✅");
         Print("========================================");
         Print("Ticket: ", result.order);
         Print("Tipo: ", (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL");
         Print("Precio: ", result.price);
         Print("Volumen: ", result.volume);
         Print("Trade #", tradesCount);
         Print("========================================");
      }
      else
      {
         Print("❌ ERROR al abrir trade");
         Print("Código: ", result.retcode);
         Print("Mensaje: ", result.comment);
      }
   }
   else
   {
      Print("❌ ERROR en OrderSend");
      Print("Código error: ", GetLastError());
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
