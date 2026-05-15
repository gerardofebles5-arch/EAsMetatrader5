//+------------------------------------------------------------------+
//|                              ASIA_BREAKOUT_PERFECT_EA.mq5        |
//|                   VERSIÓN PERFECTA - Todos los Problemas Corregidos |
//+------------------------------------------------------------------+
#property copyright "Asia Breakout Perfect - All Issues Fixed"
#property version   "5.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// PARÁMETROS CORREGIDOS
// ═══════════════════════════════════════════════════════════════════

input group "=== CONFIGURACION BASE ==="
input double InpRiskPercent = 1.0;
input int    InpMagicNumber = 777777;

input group "=== RANGO ASIATICO (CORREGIDO) ==="
input int    InpAsiaStartHour = 0;
input int    InpAsiaEndHour = 4;              // Solo 4 horas (no 8)
input double InpBreakoutOffsetPercent = 0.08; // 8% del rango (no fijo)

input group "=== FILTROS ESTRICTOS ==="
input int    InpMinRangeSize = 30;            // 30 pips (no 20)
input int    InpMaxRangeSize = 100;           // 100 pips (no 150)
input double InpMinImpulseStrength = 0.65;    // 65% (no 50%)
input int    InpMinCandleSize = 10;           // 10 pips (no 5)
input bool   InpUseFractalValidation = true;  // Activado (no false)

input group "=== GESTION CORRECTA ==="
input double InpRiskRewardRatio = 1.5;
input bool   InpUseBreakeven = false;         // Desactivado (era +5 pips)
input int    InpBreakevenPips = 20;           // Si se usa, en +20 pips
input bool   InpUseTrailing = true;
input int    InpTrailingStart = 25;           // +25 pips (no +8)
input int    InpTrailingDistance = 8;         // 8 pips distancia

input group "=== PROTECCIONES ==="
input int    InpMaxTradesPerDay = 15;
input double InpMaxDailyLoss = 3.0;
input int    InpMaxConsecutiveLosses = 3;     // Pausa después de 3
input int    InpPauseMinutes = 60;            // Pausa 60 minutos
input bool   InpUseVolatilityFilter = true;   // Filtro volatilidad
input double InpMaxVolatilityMultiplier = 2.5;
input bool   InpUseTrendValidation = true;    // Validación tendencia
input double InpMinTrendStrength = 0.65;      // 65% fuerza

// ═══════════════════════════════════════════════════════════════════
// GLOBALES
// ═══════════════════════════════════════════════════════════════════

CTrade trade;

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

datetime lastTradeDate = 0;
int tradesThisDay = 0;
double dailyStartBalance = 0;
int consecutiveLosses = 0;
datetime pauseUntil = 0;

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
   asiaRange.isValid = false;
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT PERFECT v5.00                             ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  ✅ Valida vela ACTUAL (no anterior)                     ║");
   Print("║  ✅ Offset proporcional (8% del rango)                   ║");
   Print("║  ✅ Rango solo 4 horas (no 8)                            ║");
   Print("║  ✅ Filtros estrictos (30-100 pips, 65% impulso)         ║");
   Print("║  ✅ SIN BE temprano (o BE en +20 pips)                   ║");
   Print("║  ✅ Trailing en +25 pips (no +8)                         ║");
   Print("║  ✅ Filtro volatilidad extrema                           ║");
   Print("║  ✅ Validación de tendencia                              ║");
   Print("║  ✅ Pausa después de 3 pérdidas                          ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyControls();
   
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   if(!PassAllProtections()) return;
   
   UpdateAsiaRange();
   
   if(InpUseFractalValidation)
      UpdateFractals();
   
   CheckBreakoutSignals();
}

//+------------------------------------------------------------------+
void UpdateDailyControls()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime today = StringToTime(StringFormat("%d.%d.%d", timeStruct.year, timeStruct.mon, timeStruct.day));
   
   if(lastTradeDate != today)
   {
      tradesThisDay = 0;
      lastTradeDate = today;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      asiaRange.isValid = false;
      asiaRange.buyTriggerHit = false;
      asiaRange.sellTriggerHit = false;
   }
}

//+------------------------------------------------------------------+
bool PassAllProtections()
{
   // Protección 1: Max trades
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
   // Protección 2: Pérdida diaria
   double dailyProfit = AccountInfoDouble(ACCOUNT_BALANCE) - dailyStartBalance;
   double dailyLossPercent = (dailyProfit / dailyStartBalance) * 100.0;
   if(dailyLossPercent < -InpMaxDailyLoss) return false;
   
   // Protección 3: Spread
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = (ask - bid) / point;
   if(spread > 50) return false;
   
   // Protección 4: Pausa después de pérdidas
   if(TimeCurrent() < pauseUntil)
   {
      return false;
   }
   
   // Protección 5: Filtro de volatilidad
   if(InpUseVolatilityFilter && !PassVolatilityFilter())
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassVolatilityFilter()
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_H1, 0, 24, highs) < 24) return true;
   if(CopyLow(_Symbol, PERIOD_H1, 0, 24, lows) < 24) return true;
   
   double avgRange = 0;
   for(int i = 0; i < 24; i++)
   {
      avgRange += (highs[i] - lows[i]);
   }
   avgRange /= 24.0;
   
   double currentRange = highs[0] - lows[0];
   double volatilityRatio = currentRange / avgRange;
   
   if(volatilityRatio > InpMaxVolatilityMultiplier)
   {
      Print(StringFormat("⚠ VOLATILIDAD EXTREMA: %.2fx | No operar", volatilityRatio));
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
   
   // CORREGIDO: Solo primeras 4 horas (no 8)
   if(currentHour >= InpAsiaStartHour && currentHour < InpAsiaEndHour)
   {
      double highs[], lows[];
      datetime asiaStart = StringToTime(StringFormat("%d.%d.%d %d:00", 
                                                      timeStruct.year, 
                                                      timeStruct.mon, 
                                                      timeStruct.day, 
                                                      InpAsiaStartHour));
      
      int bars = Bars(_Symbol, PERIOD_M5, asiaStart, TimeCurrent());
      
      if(bars > 0)
      {
         ArraySetAsSeries(highs, true);
         ArraySetAsSeries(lows, true);
         
         if(CopyHigh(_Symbol, PERIOD_M5, asiaStart, bars, highs) > 0 &&
            CopyLow(_Symbol, PERIOD_M5, asiaStart, bars, lows) > 0)
         {
            asiaRange.high = highs[ArrayMaximum(highs)];
            asiaRange.low = lows[ArrayMinimum(lows)];
            asiaRange.range = (asiaRange.high - asiaRange.low) / (10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
            asiaRange.startTime = asiaStart;
            asiaRange.endTime = TimeCurrent();
         }
      }
   }
   
   // Validar rango al finalizar sesión
   if(currentHour == InpAsiaEndHour && timeStruct.min < 5 && !asiaRange.isValid)
   {
      if(asiaRange.range >= InpMinRangeSize && asiaRange.range <= InpMaxRangeSize)
      {
         asiaRange.isValid = true;
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         
         // CORREGIDO: Offset proporcional (no fijo)
         double offset = asiaRange.range * InpBreakoutOffsetPercent * 10 * point;
         
         asiaRange.buyTrigger = asiaRange.high + offset;
         asiaRange.sellTrigger = asiaRange.low - offset;
         asiaRange.buyTriggerHit = false;
         asiaRange.sellTriggerHit = false;
         
         Print(StringFormat("✓ RANGO ASIA: %.1f pips | Offset: %.1f pips (%.0f%%)", 
                           asiaRange.range, 
                           offset / (10 * point),
                           InpBreakoutOffsetPercent * 100));
         Print(StringFormat("  Buy: %s | Sell: %s", 
                           DoubleToString(asiaRange.buyTrigger, _Digits), 
                           DoubleToString(asiaRange.sellTrigger, _Digits)));
      }
   }
}

//+------------------------------------------------------------------+
void UpdateFractals()
{
   int fractalPeriod = 5;
   
   // Buscar fractal high
   for(int i = fractalPeriod; i < fractalPeriod + 20; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      bool isFractal = true;
      
      for(int j = i - fractalPeriod; j <= i + fractalPeriod; j++)
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
         lastFractalHigh.price = high;
         lastFractalHigh.time = iTime(_Symbol, PERIOD_M5, i);
         lastFractalHigh.isHigh = true;
         break;
      }
   }
   
   // Buscar fractal low
   for(int i = fractalPeriod; i < fractalPeriod + 20; i++)
   {
      double low = iLow(_Symbol, PERIOD_M5, i);
      bool isFractal = true;
      
      for(int j = i - fractalPeriod; j <= i + fractalPeriod; j++)
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
         lastFractalLow.price = low;
         lastFractalLow.time = iTime(_Symbol, PERIOD_M5, i);
         lastFractalLow.isHigh = false;
         break;
      }
   }
}

//+------------------------------------------------------------------+
void CheckBreakoutSignals()
{
   if(!asiaRange.isValid) return;
   
   double currentPrice = iClose(_Symbol, PERIOD_M5, 0);
   
   if(!asiaRange.buyTriggerHit && currentPrice > asiaRange.buyTrigger)
   {
      if(ValidateEntry(true))
      {
         ExecuteBuySignal();
         asiaRange.buyTriggerHit = true;
      }
   }
   
   if(!asiaRange.sellTriggerHit && currentPrice < asiaRange.sellTrigger)
   {
      if(ValidateEntry(false))
      {
         ExecuteSellSignal();
         asiaRange.sellTriggerHit = true;
      }
   }
}

//+------------------------------------------------------------------+
bool ValidateEntry(bool isBuySignal)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // CORREGIDO: Validar vela ACTUAL (índice 0, no 1)
   double open0 = iOpen(_Symbol, PERIOD_M5, 0);
   double close0 = iClose(_Symbol, PERIOD_M5, 0);
   double high0 = iHigh(_Symbol, PERIOD_M5, 0);
   double low0 = iLow(_Symbol, PERIOD_M5, 0);
   
   double body = MathAbs(close0 - open0);
   double range = high0 - low0;
   double candleSizePips = range / (10 * point);
   
   // Validar impulso
   if(range == 0) return false;
   double bodyPercent = body / range;
   
   if(isBuySignal)
   {
      if(close0 <= open0) return false;  // Debe ser alcista
      if(bodyPercent < InpMinImpulseStrength) return false;
      if(candleSizePips < InpMinCandleSize) return false;
   }
   else
   {
      if(close0 >= open0) return false;  // Debe ser bajista
      if(bodyPercent < InpMinImpulseStrength) return false;
      if(candleSizePips < InpMinCandleSize) return false;
   }
   
   // Validar fractales
   if(InpUseFractalValidation)
   {
      if(isBuySignal && lastFractalLow.price > asiaRange.high)
         return false;
      if(!isBuySignal && lastFractalHigh.price < asiaRange.low)
         return false;
   }
   
   // Validar tendencia
   if(InpUseTrendValidation && !ValidateTrend(isBuySignal))
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
bool ValidateTrend(bool isBuySignal)
{
   double closes[];
   ArraySetAsSeries(closes, true);
   
   int period = 20;
   if(CopyClose(_Symbol, PERIOD_M15, 0, period, closes) < period)
      return true;
   
   int bullishBars = 0;
   int bearishBars = 0;
   
   for(int i = 1; i < period; i++)
   {
      if(closes[i-1] > closes[i]) bullishBars++;
      else if(closes[i-1] < closes[i]) bearishBars++;
   }
   
   double trendStrength = (double)MathMax(bullishBars, bearishBars) / (period - 1);
   bool isBullish = (bullishBars > bearishBars);
   
   if(isBuySignal && !isBullish && trendStrength > InpMinTrendStrength)
   {
      Print(StringFormat("⚠ COMPRA rechazada: Tendencia bajista %.0f%%", trendStrength * 100));
      return false;
   }
   
   if(!isBuySignal && isBullish && trendStrength > InpMinTrendStrength)
   {
      Print(StringFormat("⚠ VENTA rechazada: Tendencia alcista %.0f%%", trendStrength * 100));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
void ExecuteBuySignal()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = asiaRange.low - (5 * 10 * point);
   double slDistance = ask - sl;
   double tp = ask + (slDistance * InpRiskRewardRatio);
   
   double lots = CalculatePositionSize(slDistance);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ASIA_BUY_PERFECT"))
   {
      tradesThisDay++;
      Print(StringFormat("✓ COMPRA | Entry: %s | SL: %s | TP: %s | Lote: %.2f", 
                        DoubleToString(ask, _Digits), 
                        DoubleToString(sl, _Digits), 
                        DoubleToString(tp, _Digits),
                        lots));
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = asiaRange.high + (5 * 10 * point);
   double slDistance = sl - bid;
   double tp = bid - (slDistance * InpRiskRewardRatio);
   
   double lots = CalculatePositionSize(slDistance);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ASIA_SELL_PERFECT"))
   {
      tradesThisDay++;
      Print(StringFormat("✓ VENTA | Entry: %s | SL: %s | TP: %s | Lote: %.2f", 
                        DoubleToString(bid, _Digits), 
                        DoubleToString(sl, _Digits), 
                        DoubleToString(tp, _Digits),
                        lots));
   }
}

//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lots = riskAmount / (slDistance * tickValue / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
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
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      // BREAKEVEN (solo si está activado y en +20 pips)
      if(InpUseBreakeven && profitPips >= InpBreakevenPips)
      {
         double breakeven = openPrice + (isBuy ? 2 : -2) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print(StringFormat("✓ BE | +%.1f pips", profitPips));
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print(StringFormat("✓ BE | +%.1f pips", profitPips));
         }
      }
      
      // TRAILING (solo si está activado y en +25 pips)
      if(InpUseTrailing && profitPips > InpTrailingStart)
      {
         double trailDistance = InpTrailingDistance * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print(StringFormat("► TRAILING | +%.1f pips", profitPips));
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print(StringFormat("▼ TRAILING | +%.1f pips", profitPips));
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
            }
            else if(profit < 0)
            {
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  pauseUntil = TimeCurrent() + InpPauseMinutes * 60;
                  Print(StringFormat("⚠ PAUSA: %d pérdidas | Hasta: %s", 
                                    consecutiveLosses, 
                                    TimeToString(pauseUntil)));
                  consecutiveLosses = 0;
               }
            }
            
            lastProcessedTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT PERFECT v5.00 - Detenido                 ║");
   Print(StringFormat("║  Trades hoy: %d                                           ║", tradesThisDay));
   Print("╚═══════════════════════════════════════════════════════════╝");
}

//+------------------------------------------------------------------+
