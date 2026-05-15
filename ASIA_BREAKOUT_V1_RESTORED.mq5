//+------------------------------------------------------------------+
//|                                    ASIA_BREAKOUT_PURE_EA.mq5     |
//|                        Price Action Pura - Geometría del Mercado |
//|                        Estrategia: Rango Asiático + Breakout     |
//+------------------------------------------------------------------+
#property copyright "Asia Breakout Pure - Price Action Strategy"
#property version   "1.00"
#property description "Estrategia basada en acción del precio pura"
#property description "Sin indicadores - Solo geometría y dinámica de sesiones"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// PARÁMETROS DE ENTRADA
// ═══════════════════════════════════════════════════════════════════

input group "═══ CONFIGURACIÓN BÁSICA ═══"
input double InpRiskPercent = 1.0;           // Riesgo por trade (%)
input int    InpMagicNumber = 888888;        // Magic number

input group "═══ RANGO ASIÁTICO ═══"
input int    InpAsiaStartHour = 0;           // Hora inicio Asia (GMT)
input int    InpAsiaEndHour = 8;             // Hora fin Asia (GMT)
input int    InpBreakoutOffset = 5;          // Offset para trigger (pips)

input group "═══ GESTIÓN DE RIESGO ═══"
input double InpRiskRewardRatio = 2.0;       // Ratio Riesgo:Beneficio mínimo
input bool   InpUseBreakevenAt1to1 = false;  // NO usar BE en 1:1 (muy tarde)
input bool   InpUseEarlyBreakeven = true;    // BE ULTRA TEMPRANO
input int    InpEarlyBreakevenPips = 5;      // BE en solo +5 pips
input bool   InpUseTrailingStop = true;      // Usar trailing stop ganancia
input int    InpTrailingStart = 8;           // Iniciar trailing en X pips - MÁS TEMPRANO
input int    InpTrailingDistance = 5;        // Distancia trailing (pips) - MÁS AGRESIVO
input bool   InpUseLossTrailing = true;      // Trailing stop para pérdidas
input int    InpLossTrailingTrigger = -5;    // Activar en -X pips - MÁS TEMPRANO
input int    InpLossTrailingDistance = 3;    // Reducir pérdida a X pips - MÁS AGRESIVO

input group "═══ CONSOLIDACIONES GEOMÉTRICAS ═══"
input bool   InpUseFractalValidation = false; // NO validar fractales (más trades)
input int    InpFractalPeriod = 5;           // Período fractal
input int    InpMinRangeSize = 20;           // Rango mínimo Asia (pips) - PERMISIVO
input int    InpMaxRangeSize = 150;          // Rango máximo Asia (pips) - PERMISIVO
input double InpMinImpulseStrength = 0.50;   // Impulso mínimo (50% body) - PERMISIVO
input int    InpMinCandleSize = 5;           // Tamaño mínimo vela (pips) - PERMISIVO

input group "═══ PROTECCIONES MÍNIMAS ═══"
input int    InpMaxTradesPerDay = 15;        // Max trades por día - PERMISIVO
input double InpMaxDailyLoss = 3.0;          // Pérdida máxima diaria (%)
input int    InpMaxSpread = 50;              // Spread máximo (pips)
input int    InpMaxConsecutiveLosses = 5;    // Pausar después de X pérdidas
input int    InpMinMinutesBetweenTrades = 10; // Minutos entre trades - PERMISIVO

// ═══════════════════════════════════════════════════════════════════
// VARIABLES GLOBALES
// ═══════════════════════════════════════════════════════════════════

CTrade trade;

// Rango Asiático
struct SAsiaRange {
   datetime startTime;
   datetime endTime;
   double high;
   double low;
   double range;
   bool isValid;
   bool buyTriggerHit;
   bool sellTriggerHit;
   double buyTrigger;
   double sellTrigger;
};
SAsiaRange asiaRange;

// Control diario
datetime lastTradeDate = 0;
int tradesThisDay = 0;
double dailyStartBalance = 0;
double dailyProfit = 0;
int consecutiveLosses = 0;
datetime lastTradeTime = 0;

// Fractales
struct SFractal {
   datetime time;
   double price;
   bool isHigh;
};
SFractal lastFractalHigh, lastFractalLow;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Inicializar
   asiaRange.isValid = false;
   asiaRange.buyTriggerHit = false;
   asiaRange.sellTriggerHit = false;
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT PURE EA v3.00 - ULTRA AGGRESSIVE          ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  🎯 ESTRATEGIA: MUCHOS TRADES + GESTIÓN ULTRA AGRESIVA  ║");
   Print("║  📊 Rango Asia: ", InpAsiaStartHour, ":00 - ", InpAsiaEndHour, ":00 GMT                    ║");
   Print("║  ⚡ Offset: ", InpBreakoutOffset, " pips | R:R: 1:", DoubleToString(InpRiskRewardRatio, 1), "              ║");
   Print("║  🛡️ Riesgo: ", DoubleToString(InpRiskPercent, 1), "% | Max trades: ", InpMaxTradesPerDay, "/día            ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  ⚡ BREAKEVEN EN +5 PIPS (Ultra temprano)                ║");
   Print("║  ⚡ TRAILING PÉRDIDAS EN -5 PIPS (Corta rápido)         ║");
   Print("║  ⚡ TRAILING GANANCIA EN +8 PIPS (Protege rápido)       ║");
   Print("║  ⚡ FILTROS PERMISIVOS (Muchas operaciones)             ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("═══════════════════════════════════════════════════════════");
   Print("EA detenido. Trades hoy: ", tradesThisDay);
   Print("Profit diario: ", DoubleToString(dailyProfit, 2));
   Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Actualizar control diario
   UpdateDailyControls();
   
   // Gestionar posiciones abiertas
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   // Verificar protecciones mínimas
   if(!PassMinimalProtections()) return;
   
   // Actualizar rango asiático
   UpdateAsiaRange();
   
   // Actualizar fractales si está activado
   if(InpUseFractalValidation)
      UpdateFractals();
   
   // Buscar señales de breakout
   CheckBreakoutSignals();
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
      dailyProfit = 0;
      consecutiveLosses = 0;
      
      // Reset rango asiático
      asiaRange.isValid = false;
      asiaRange.buyTriggerHit = false;
      asiaRange.sellTriggerHit = false;
      
      Print("► Nuevo día - Controles reseteados");
   }
   
   // Calcular profit diario
   dailyProfit = AccountInfoDouble(ACCOUNT_BALANCE) - dailyStartBalance;
}

//+------------------------------------------------------------------+
bool PassMinimalProtections()
{
   // Protección 1: Max trades por día
   if(tradesThisDay >= InpMaxTradesPerDay)
   {
      return false;
   }
   
   // Protección 2: Pérdidas consecutivas
   if(consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      Print("⊗ Pausado por ", consecutiveLosses, " pérdidas consecutivas");
      return false;
   }
   
   // Protección 3: Pérdida diaria máxima
   double dailyLossPercent = (dailyProfit / dailyStartBalance) * 100.0;
   if(dailyLossPercent < -InpMaxDailyLoss)
   {
      Print("⊗ Pérdida diaria alcanzada: ", DoubleToString(dailyLossPercent, 2), "%");
      return false;
   }
   
   // Protección 4: Spread máximo
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 
                    SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > InpMaxSpread)
   {
      return false;
   }
   
   // Protección 5: Tiempo mínimo entre trades
   if(lastTradeTime > 0)
   {
      int minutesSinceLastTrade = (int)((TimeCurrent() - lastTradeTime) / 60);
      if(minutesSinceLastTrade < InpMinMinutesBetweenTrades)
      {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
void UpdateAsiaRange()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;
   
   // Durante sesión asiática: actualizar high/low
   if(currentHour >= InpAsiaStartHour && currentHour < InpAsiaEndHour)
   {
      // Usar CopyHigh y CopyLow para datos crudos (más eficiente)
      double highs[], lows[];
      
      // Calcular inicio de sesión asiática hoy
      datetime asiaStart = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                        IntegerToString(timeStruct.mon) + "." + 
                                        IntegerToString(timeStruct.day) + " " +
                                        IntegerToString(InpAsiaStartHour) + ":00");
      
      int bars = Bars(_Symbol, PERIOD_M5, asiaStart, TimeCurrent());
      
      if(bars > 0)
      {
         ArraySetAsSeries(highs, true);
         ArraySetAsSeries(lows, true);
         
         if(CopyHigh(_Symbol, PERIOD_M5, asiaStart, bars, highs) > 0 &&
            CopyLow(_Symbol, PERIOD_M5, asiaStart, bars, lows) > 0)
         {
            // Encontrar high y low del rango
            double rangeHigh = highs[ArrayMaximum(highs)];
            double rangeLow = lows[ArrayMinimum(lows)];
            
            asiaRange.high = rangeHigh;
            asiaRange.low = rangeLow;
            asiaRange.range = (rangeHigh - rangeLow) / (10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
            asiaRange.startTime = asiaStart;
            asiaRange.endTime = TimeCurrent();
            asiaRange.isValid = false; // Todavía no es válido hasta que termine la sesión
         }
      }
   }
   
   // Al finalizar sesión asiática: validar rango
   if(currentHour == InpAsiaEndHour && timeStruct.min < 5 && !asiaRange.isValid)
   {
      // Validar tamaño del rango
      if(asiaRange.range >= InpMinRangeSize && asiaRange.range <= InpMaxRangeSize)
      {
         asiaRange.isValid = true;
         
         // Calcular triggers
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double offset = InpBreakoutOffset * 10 * point;
         
         asiaRange.buyTrigger = asiaRange.high + offset;
         asiaRange.sellTrigger = asiaRange.low - offset;
         
         asiaRange.buyTriggerHit = false;
         asiaRange.sellTriggerHit = false;
         
         Print("╔═══════════════════════════════════════════════════════════╗");
         Print("║  ✓ RANGO ASIÁTICO VÁLIDO                                 ║");
         Print("╠═══════════════════════════════════════════════════════════╣");
         Print("║  High: ", DoubleToString(asiaRange.high, _Digits), "                                    ║");
         Print("║  Low:  ", DoubleToString(asiaRange.low, _Digits), "                                    ║");
         Print("║  Rango: ", DoubleToString(asiaRange.range, 1), " pips                                ║");
         Print("╠═══════════════════════════════════════════════════════════╣");
         Print("║  🎯 TRIGGERS:                                            ║");
         Print("║  Compra:  ", DoubleToString(asiaRange.buyTrigger, _Digits), "                              ║");
         Print("║  Venta:   ", DoubleToString(asiaRange.sellTrigger, _Digits), "                              ║");
         Print("╚═══════════════════════════════════════════════════════════╝");
      }
      else
      {
         Print("⊗ Rango asiático inválido: ", DoubleToString(asiaRange.range, 1), 
               " pips (min: ", InpMinRangeSize, ", max: ", InpMaxRangeSize, ")");
      }
   }
}

//+------------------------------------------------------------------+
void UpdateFractals()
{
   // Buscar fractal high
   int highBar = -1;
   for(int i = InpFractalPeriod; i < InpFractalPeriod + 20; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      bool isFractal = true;
      
      for(int j = i - InpFractalPeriod; j <= i + InpFractalPeriod; j++)
      {
         if(j == i || j < 0) continue;
         if(iHigh(_Symbol, PERIOD_M5, j) > high)
         {
            isFractal = false;
            break;
         }
      }
      
      if(isFractal)
      {
         highBar = i;
         break;
      }
   }
   
   if(highBar > 0)
   {
      lastFractalHigh.price = iHigh(_Symbol, PERIOD_M5, highBar);
      lastFractalHigh.time = iTime(_Symbol, PERIOD_M5, highBar);
      lastFractalHigh.isHigh = true;
   }
   
   // Buscar fractal low
   int lowBar = -1;
   for(int i = InpFractalPeriod; i < InpFractalPeriod + 20; i++)
   {
      double low = iLow(_Symbol, PERIOD_M5, i);
      bool isFractal = true;
      
      for(int j = i - InpFractalPeriod; j <= i + InpFractalPeriod; j++)
      {
         if(j == i || j < 0) continue;
         if(iLow(_Symbol, PERIOD_M5, j) < low)
         {
            isFractal = false;
            break;
         }
      }
      
      if(isFractal)
      {
         lowBar = i;
         break;
      }
   }
   
   if(lowBar > 0)
   {
      lastFractalLow.price = iLow(_Symbol, PERIOD_M5, lowBar);
      lastFractalLow.time = iTime(_Symbol, PERIOD_M5, lowBar);
      lastFractalLow.isHigh = false;
   }
}

//+------------------------------------------------------------------+
void CheckBreakoutSignals()
{
   if(!asiaRange.isValid) return;
   
   double currentPrice = iClose(_Symbol, PERIOD_M5, 0);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SEÑAL DE COMPRA: Precio rompe trigger alcista
   if(!asiaRange.buyTriggerHit && currentPrice > asiaRange.buyTrigger)
   {
      // Validar con fractales si está activado
      bool fractalValid = true;
      if(InpUseFractalValidation)
      {
         // Validar que el último fractal low esté dentro o debajo del rango asiático
         fractalValid = (lastFractalLow.price <= asiaRange.high);
      }
      
      if(fractalValid)
      {
         // Validar impulso puro (vela alcista fuerte)
         double open1 = iOpen(_Symbol, PERIOD_M5, 1);
         double close1 = iClose(_Symbol, PERIOD_M5, 1);
         double high1 = iHigh(_Symbol, PERIOD_M5, 1);
         double low1 = iLow(_Symbol, PERIOD_M5, 1);
         double body = close1 - open1;
         double range = high1 - low1;
         
         // Validar impulso más estricto
         double candleSizePips = range / (10 * point);
         
         if(close1 > open1 && range > 0 && 
            body > range * InpMinImpulseStrength &&
            candleSizePips >= InpMinCandleSize)
         {
            ExecuteBuySignal();
            asiaRange.buyTriggerHit = true;
         }
      }
   }
   
   // SEÑAL DE VENTA: Precio rompe trigger bajista
   if(!asiaRange.sellTriggerHit && currentPrice < asiaRange.sellTrigger)
   {
      // Validar con fractales si está activado
      bool fractalValid = true;
      if(InpUseFractalValidation)
      {
         // Validar que el último fractal high esté dentro o arriba del rango asiático
         fractalValid = (lastFractalHigh.price >= asiaRange.low);
      }
      
      if(fractalValid)
      {
         // Validar impulso puro (vela bajista fuerte)
         double open1 = iOpen(_Symbol, PERIOD_M5, 1);
         double close1 = iClose(_Symbol, PERIOD_M5, 1);
         double high1 = iHigh(_Symbol, PERIOD_M5, 1);
         double low1 = iLow(_Symbol, PERIOD_M5, 1);
         double body = open1 - close1;
         double range = high1 - low1;
         
         // Validar impulso más estricto
         double candleSizePips = range / (10 * point);
         
         if(close1 < open1 && range > 0 && 
            body > range * InpMinImpulseStrength &&
            candleSizePips >= InpMinCandleSize)
         {
            ExecuteSellSignal();
            asiaRange.sellTriggerHit = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
void ExecuteBuySignal()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL: Debajo del low de Asia
   double sl = asiaRange.low - (5 * 10 * point); // 5 pips buffer
   double slDistance = ask - sl;
   double slPips = slDistance / (10 * point);
   
   // TP: Basado en R:R ratio
   double tpDistance = slDistance * InpRiskRewardRatio;
   double tp = ask + tpDistance;
   double tpPips = tpDistance / (10 * point);
   
   // Calcular lote (1% dinámico)
   double lots = CalculatePositionSize(slDistance);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño: ", lots);
      return;
   }
   
   string comment = "ASIA_BUY_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, comment))
   {
      tradesThisDay++;
      lastTradeTime = TimeCurrent();
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA EJECUTADA - BREAKOUT ALCISTA                  ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Entry: ", DoubleToString(ask, _Digits), "                                      ║");
      Print("║  SL:    ", DoubleToString(sl, _Digits), " (-", DoubleToString(slPips, 1), " pips)                  ║");
      Print("║  TP:    ", DoubleToString(tp, _Digits), " (+", DoubleToString(tpPips, 1), " pips)                  ║");
      Print("║  Lote:  ", DoubleToString(lots, 2), "                                          ║");
      Print("║  R:R:   1:", DoubleToString(InpRiskRewardRatio, 1), "                                        ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " | Pérdidas consecutivas: ", consecutiveLosses, "  ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL: Arriba del high de Asia
   double sl = asiaRange.high + (5 * 10 * point); // 5 pips buffer
   double slDistance = sl - bid;
   double slPips = slDistance / (10 * point);
   
   // TP: Basado en R:R ratio
   double tpDistance = slDistance * InpRiskRewardRatio;
   double tp = bid - tpDistance;
   double tpPips = tpDistance / (10 * point);
   
   // Calcular lote (1% dinámico)
   double lots = CalculatePositionSize(slDistance);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño: ", lots);
      return;
   }
   
   string comment = "ASIA_SELL_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, comment))
   {
      tradesThisDay++;
      lastTradeTime = TimeCurrent();
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA EJECUTADA - BREAKOUT BAJISTA                   ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Entry: ", DoubleToString(bid, _Digits), "                                      ║");
      Print("║  SL:    ", DoubleToString(sl, _Digits), " (+", DoubleToString(slPips, 1), " pips)                  ║");
      Print("║  TP:    ", DoubleToString(tp, _Digits), " (-", DoubleToString(tpPips, 1), " pips)                  ║");
      Print("║  Lote:  ", DoubleToString(lots, 2), "                                          ║");
      Print("║  R:R:   1:", DoubleToString(InpRiskRewardRatio, 1), "                                        ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " | Pérdidas consecutivas: ", consecutiveLosses, "  ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   // Cálculo dinámico del 1%
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = riskAmount / (slDistance * tickValue / tickSize);
   
   // Normalizar lote
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   return lots;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   // Actualizar estadísticas de trades cerrados
   UpdateTradeStatistics();
   
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
      
      // ═══════════════════════════════════════════════════════════════
      // BREAKEVEN ULTRA TEMPRANO (En +5 pips)
      // ═══════════════════════════════════════════════════════════════
      if(InpUseEarlyBreakeven && profitPips >= InpEarlyBreakevenPips)
      {
         double breakeven = openPrice + (isBuy ? 1 : -1) * 10 * point; // BE+1 pip
         
         if(isBuy && breakeven > currentSL)
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("⚡ BE TEMPRANO | +", DoubleToString(profitPips, 1), " pips → SL a BE+1");
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("⚡ BE TEMPRANO | +", DoubleToString(profitPips, 1), " pips → SL a BE+1");
         }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // TRAILING STOP PARA PÉRDIDAS (Corta pérdidas ULTRA rápido)
      // ═══════════════════════════════════════════════════════════════
      if(InpUseLossTrailing && profitPips < InpLossTrailingTrigger)
      {
         double lossTrailDistance = InpLossTrailingDistance * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - lossTrailDistance;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("⚠ CORTA PÉRDIDA | ", DoubleToString(profitPips, 1), " pips → SL a -", 
                     DoubleToString(InpLossTrailingDistance, 0), " pips");
            }
         }
         else
         {
            newSL = currentPrice + lossTrailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("⚠ CORTA PÉRDIDA | ", DoubleToString(profitPips, 1), " pips → SL a -",
                     DoubleToString(InpLossTrailingDistance, 0), " pips");
            }
         }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // TRAILING STOP PARA GANANCIAS (ULTRA AGRESIVO)
      // ═══════════════════════════════════════════════════════════════
      if(InpUseTrailingStop && profitPips > InpTrailingStart)
      {
         double trailDistance = InpTrailingDistance * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("⚡ TRAILING GANANCIA | +", DoubleToString(profitPips, 1), 
                     " pips | SL a -", DoubleToString(InpTrailingDistance, 0), " pips del precio");
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("⚡ TRAILING GANANCIA | +", DoubleToString(profitPips, 1),
                     " pips | SL a +", DoubleToString(InpTrailingDistance, 0), " pips del precio");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void UpdateTradeStatistics()
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
               consecutiveLosses = 0;
               Print("✓ WIN | Pérdidas consecutivas: 0");
            }
            else if(profit < 0)
            {
               consecutiveLosses++;
               Print("✗ LOSS | Pérdidas consecutivas: ", consecutiveLosses);
            }
            
            lastProcessedTicket = ticket;
         }
      }
   }
}
