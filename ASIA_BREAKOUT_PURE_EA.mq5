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
input double InpRiskRewardRatio = 1.5;       // Ratio Riesgo:Beneficio mínimo
input bool   InpUseBreakevenAt1to1 = true;   // Mover a BE en 1:1
input bool   InpUseTrailingStop = true;      // Usar trailing stop
input int    InpTrailingStart = 15;          // Iniciar trailing en X pips
input int    InpTrailingDistance = 10;       // Distancia trailing (pips)

input group "═══ CONSOLIDACIONES GEOMÉTRICAS ═══"
input bool   InpUseFractalValidation = true; // Validar con fractales
input int    InpFractalPeriod = 5;           // Período fractal
input int    InpMinRangeSize = 20;           // Rango mínimo Asia (pips)
input int    InpMaxRangeSize = 150;          // Rango máximo Asia (pips)

input group "═══ PROTECCIONES MÍNIMAS ═══"
input int    InpMaxTradesPerDay = 10;        // Max trades por día
input double InpMaxDailyLoss = 3.0;          // Pérdida máxima diaria (%)
input int    InpMaxSpread = 50;              // Spread máximo (pips)

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
   Print("║  ASIA BREAKOUT PURE EA v1.00                             ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  🎯 ESTRATEGIA: PRICE ACTION PURA                        ║");
   Print("║  📊 Rango Asia: ", InpAsiaStartHour, ":00 - ", InpAsiaEndHour, ":00 GMT                    ║");
   Print("║  ⚡ Offset: ", InpBreakoutOffset, " pips | R:R: 1:", DoubleToString(InpRiskRewardRatio, 1), "              ║");
   Print("║  🛡️ Riesgo: ", DoubleToString(InpRiskPercent, 1), "% | Max trades: ", InpMaxTradesPerDay, "/día            ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  SIN INDICADORES - SOLO GEOMETRÍA DEL MERCADO            ║");
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
   
   // Protección 2: Pérdida diaria máxima
   double dailyLossPercent = (dailyProfit / dailyStartBalance) * 100.0;
   if(dailyLossPercent < -InpMaxDailyLoss)
   {
      Print("⊗ Pérdida diaria alcanzada: ", DoubleToString(dailyLossPercent, 2), "%");
      return false;
   }
   
   // Protección 3: Spread máximo
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 
                    SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > InpMaxSpread)
   {
      return false;
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
         
         // Vela alcista con cuerpo >60% del rango
         if(close1 > open1 && range > 0 && body > range * 0.6)
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
         
         // Vela bajista con cuerpo >60% del rango
         if(close1 < open1 && range > 0 && body > range * 0.6)
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
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA EJECUTADA - BREAKOUT ALCISTA                  ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Entry: ", DoubleToString(ask, _Digits), "                                      ║");
      Print("║  SL:    ", DoubleToString(sl, _Digits), " (-", DoubleToString(slPips, 1), " pips)                  ║");
      Print("║  TP:    ", DoubleToString(tp, _Digits), " (+", DoubleToString(tpPips, 1), " pips)                  ║");
      Print("║  Lote:  ", DoubleToString(lots, 2), "                                          ║");
      Print("║  R:R:   1:", DoubleToString(InpRiskRewardRatio, 1), "                                        ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                          ║");
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
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA EJECUTADA - BREAKOUT BAJISTA                   ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Entry: ", DoubleToString(bid, _Digits), "                                      ║");
      Print("║  SL:    ", DoubleToString(sl, _Digits), " (+", DoubleToString(slPips, 1), " pips)                  ║");
      Print("║  TP:    ", DoubleToString(tp, _Digits), " (-", DoubleToString(tpPips, 1), " pips)                  ║");
      Print("║  Lote:  ", DoubleToString(lots, 2), "                                          ║");
      Print("║  R:R:   1:", DoubleToString(InpRiskRewardRatio, 1), "                                        ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                          ║");
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
void ManageOpenPositions()
{
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
      
      // BREAKEVEN EN 1:1
      if(InpUseBreakevenAt1to1)
      {
         double slDistance = isBuy ? (openPrice - currentSL) : (currentSL - openPrice);
         
         if(profit >= slDistance) // 1:1 alcanzado
         {
            double breakeven = openPrice + (isBuy ? 2 : -2) * 10 * point; // +2 pips
            
            if(isBuy && breakeven > currentSL)
            {
               trade.PositionModify(ticket, breakeven, currentTP);
               Print("► Breakeven activado en 1:1 | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
            else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
            {
               trade.PositionModify(ticket, breakeven, currentTP);
               Print("▼ Breakeven activado en 1:1 | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
         }
      }
      
      // TRAILING STOP DE ALTA PRECISIÓN
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
               Print("► Trailing Stop | SL: ", DoubleToString(newSL, _Digits), 
                     " | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Trailing Stop | SL: ", DoubleToString(newSL, _Digits),
                     " | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
