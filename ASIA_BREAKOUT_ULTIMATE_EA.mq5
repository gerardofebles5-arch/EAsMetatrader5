//+------------------------------------------------------------------+
//|                              ASIA_BREAKOUT_ULTIMATE_EA.mq5       |
//|                   v4.00 ULTIMATE - Protección Contra Drawdowns   |
//+------------------------------------------------------------------+
#property copyright "Asia Breakout v4.00 Ultimate"
#property version   "4.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// PARÁMETROS
// ═══════════════════════════════════════════════════════════════════

input group "=== CONFIGURACION BASE ==="
input double InpRiskPercent = 1.0;
input int    InpMagicNumber = 999999;

input group "=== RANGO ASIATICO ==="
input int    InpAsiaStartHour = 0;
input int    InpAsiaEndHour = 8;
input int    InpBreakoutOffset = 5;
input double InpMinRangePips = 20.0;
input double InpMaxRangePips = 150.0;

input group "=== GESTION BASICA ==="
input double InpRiskRewardRatio = 1.5;
input int    InpMaxTradesPerDay = 20;
input double InpMaxDailyLoss = 5.0;

input group "=== CIERRES INTELIGENTES ==="
input bool   InpUseSmartExit = true;
input int    InpMinPipsForSmartExit = 3;
input bool   InpCloseOnOppositeCandle = true;
input double InpOppositeCandleStrength = 0.70;
input bool   InpCloseOnWeakMomentum = true;
input int    InpWeakMomentumBars = 3;

input group "=== BREAKEVEN Y TRAILING ==="
input bool   InpUseQuickBreakeven = true;
input int    InpQuickBreakevenPips = 10;
input bool   InpUseSmartTrailing = true;
input int    InpSmartTrailingStart = 15;
input int    InpSmartTrailingStep = 5;

input group "=== PROTECCION CONTRA DRAWDOWNS ==="
input bool   InpUseDrawdownProtection = true;
input int    InpMaxConsecutiveLosses = 3;
input int    InpPauseAfterLossesMinutes = 60;
input bool   InpReduceLotAfterDrawdown = true;
input double InpDrawdownThreshold = 3.0;
input double InpLotReductionFactor = 0.5;
input bool   InpUseVolatilityFilter = true;
input double InpMaxVolatilityMultiplier = 2.5;

input group "=== VALIDACION DE TENDENCIA ==="
input bool   InpUseTrendValidation = true;
input int    InpTrendPeriod = 20;
input double InpMinTrendStrength = 0.6;

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

// Protección contra drawdowns
int consecutiveLosses = 0;
datetime pauseUntil = 0;
double currentDrawdown = 0;
double lotMultiplier = 1.0;
double peakBalance = 0;

// Tracking de posiciones
struct SPositionTracking {
   ulong ticket;
   datetime openTime;
   double openPrice;
   double highestProfit;
   int barsWithoutProgress;
   double lastPrice;
};
SPositionTracking posTracking[];

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   asiaRange.isValid = false;
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   peakBalance = dailyStartBalance;
   ArrayResize(posTracking, 0);
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT ULTIMATE v4.00                            ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  ✅ Cierres Inteligentes                                 ║");
   Print("║  ✅ Protección Contra Drawdowns                          ║");
   Print("║  ✅ Pausa Automática Después de Pérdidas                 ║");
   Print("║  ✅ Reducción de Lote en Drawdown                        ║");
   Print("║  ✅ Filtro de Volatilidad Extrema                        ║");
   Print("║  ✅ Validación de Tendencia                              ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyControls();
   UpdateDrawdownProtection();
   
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   if(!PassBasicProtections()) return;
   if(!PassDrawdownProtections()) return;
   
   UpdateAsiaRange();
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
      ArrayResize(posTracking, 0);
   }
}

//+------------------------------------------------------------------+
void UpdateDrawdownProtection()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Actualizar peak balance
   if(currentBalance > peakBalance)
      peakBalance = currentBalance;
   
   // Calcular drawdown actual
   currentDrawdown = ((peakBalance - currentBalance) / peakBalance) * 100.0;
   
   // Ajustar multiplicador de lote según drawdown
   if(InpReduceLotAfterDrawdown && currentDrawdown > InpDrawdownThreshold)
   {
      lotMultiplier = InpLotReductionFactor;
      Print(StringFormat("⚠ DRAWDOWN DETECTADO: %.2f%% | Lote reducido a %.0f%%", 
                        currentDrawdown, lotMultiplier * 100));
   }
   else
   {
      lotMultiplier = 1.0;
   }
}

//+------------------------------------------------------------------+
bool PassBasicProtections()
{
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
   double dailyProfit = AccountInfoDouble(ACCOUNT_BALANCE) - dailyStartBalance;
   double dailyLossPercent = (dailyProfit / dailyStartBalance) * 100.0;
   if(dailyLossPercent < -InpMaxDailyLoss) return false;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread = (ask - bid) / point;
   if(spread > 50) return false;
   
   return true;
}

//+------------------------------------------------------------------+
bool PassDrawdownProtections()
{
   if(!InpUseDrawdownProtection) return true;
   
   // Verificar pausa después de pérdidas consecutivas
   if(TimeCurrent() < pauseUntil)
   {
      return false;
   }
   
   // Verificar volatilidad extrema
   if(InpUseVolatilityFilter)
   {
      if(!PassVolatilityFilter())
      {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassVolatilityFilter()
{
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_H1, 0, 24, highs) < 24) return false;
   if(CopyLow(_Symbol, PERIOD_H1, 0, 24, lows) < 24) return false;
   
   // Calcular volatilidad promedio de las últimas 24 horas
   double avgRange = 0;
   for(int i = 0; i < 24; i++)
   {
      avgRange += (highs[i] - lows[i]);
   }
   avgRange /= 24.0;
   
   // Calcular volatilidad actual (última hora)
   double currentRange = highs[0] - lows[0];
   
   // Si volatilidad actual es más de X veces el promedio, no operar
   double volatilityRatio = currentRange / avgRange;
   if(volatilityRatio > InpMaxVolatilityMultiplier)
   {
      Print(StringFormat("⚠ VOLATILIDAD EXTREMA: %.2fx promedio | No operar", volatilityRatio));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool ValidateTrend(bool isBuySignal)
{
   if(!InpUseTrendValidation) return true;
   
   double closes[];
   ArraySetAsSeries(closes, true);
   
   if(CopyClose(_Symbol, PERIOD_M15, 0, InpTrendPeriod, closes) < InpTrendPeriod)
      return false;
   
   // Calcular tendencia simple
   int bullishBars = 0;
   int bearishBars = 0;
   
   for(int i = 1; i < InpTrendPeriod; i++)
   {
      if(closes[i-1] > closes[i]) bullishBars++;
      else if(closes[i-1] < closes[i]) bearishBars++;
   }
   
   double trendStrength = (double)MathMax(bullishBars, bearishBars) / (InpTrendPeriod - 1);
   bool isBullish = (bullishBars > bearishBars);
   
   // Validar que la señal esté alineada con la tendencia
   if(isBuySignal && !isBullish && trendStrength > InpMinTrendStrength)
   {
      Print(StringFormat("⚠ SEÑAL COMPRA rechazada: Tendencia bajista (%.0f%%)", trendStrength * 100));
      return false;
   }
   
   if(!isBuySignal && isBullish && trendStrength > InpMinTrendStrength)
   {
      Print(StringFormat("⚠ SEÑAL VENTA rechazada: Tendencia alcista (%.0f%%)", trendStrength * 100));
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
   
   if(currentHour == InpAsiaEndHour && timeStruct.min < 5 && !asiaRange.isValid)
   {
      if(asiaRange.range >= InpMinRangePips && asiaRange.range <= InpMaxRangePips)
      {
         asiaRange.isValid = true;
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double offset = InpBreakoutOffset * 10 * point;
         
         asiaRange.buyTrigger = asiaRange.high + offset;
         asiaRange.sellTrigger = asiaRange.low - offset;
         asiaRange.buyTriggerHit = false;
         asiaRange.sellTriggerHit = false;
         
         Print(StringFormat("✓ RANGO ASIA: %.1f pips | Buy: %s | Sell: %s", 
                           asiaRange.range, 
                           DoubleToString(asiaRange.buyTrigger, _Digits), 
                           DoubleToString(asiaRange.sellTrigger, _Digits)));
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
      if(ValidateTrend(true))
      {
         ExecuteBuySignal();
         asiaRange.buyTriggerHit = true;
      }
   }
   
   if(!asiaRange.sellTriggerHit && currentPrice < asiaRange.sellTrigger)
   {
      if(ValidateTrend(false))
      {
         ExecuteSellSignal();
         asiaRange.sellTriggerHit = true;
      }
   }
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
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ASIA_BUY"))
   {
      tradesThisDay++;
      AddPositionTracking(trade.ResultOrder(), ask);
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
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ASIA_SELL"))
   {
      tradesThisDay++;
      AddPositionTracking(trade.ResultOrder(), bid);
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
   
   // Aplicar multiplicador de lote (reducción en drawdown)
   riskAmount *= lotMultiplier;
   
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
void AddPositionTracking(ulong ticket, double openPrice)
{
   int size = ArraySize(posTracking);
   ArrayResize(posTracking, size + 1);
   posTracking[size].ticket = ticket;
   posTracking[size].openTime = TimeCurrent();
   posTracking[size].openPrice = openPrice;
   posTracking[size].highestProfit = 0;
   posTracking[size].barsWithoutProgress = 0;
   posTracking[size].lastPrice = openPrice;
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
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      // Encontrar tracking
      int trackIdx = FindPositionTracking(ticket);
      if(trackIdx >= 0)
      {
         if(profitPips > posTracking[trackIdx].highestProfit)
         {
            posTracking[trackIdx].highestProfit = profitPips;
            posTracking[trackIdx].barsWithoutProgress = 0;
         }
         else
         {
            posTracking[trackIdx].barsWithoutProgress++;
         }
         posTracking[trackIdx].lastPrice = currentPrice;
      }
      
      // CIERRES INTELIGENTES
      if(InpUseSmartExit && profitPips >= InpMinPipsForSmartExit)
      {
         if(InpCloseOnOppositeCandle)
         {
            if(DetectOppositeCandle(isBuy))
            {
               trade.PositionClose(ticket);
               Print(StringFormat("⚠ CIERRE INTELIGENTE: Vela opuesta fuerte | Profit: %.1f pips", profitPips));
               OnTradeClose(true);
               RemovePositionTracking(trackIdx);
               continue;
            }
         }
         
         if(InpCloseOnWeakMomentum && trackIdx >= 0)
         {
            if(posTracking[trackIdx].barsWithoutProgress >= InpWeakMomentumBars &&
               posTracking[trackIdx].highestProfit > InpMinPipsForSmartExit)
            {
               trade.PositionClose(ticket);
               Print(StringFormat("⚠ CIERRE INTELIGENTE: Momentum débil | Profit: %.1f pips", profitPips));
               OnTradeClose(true);
               RemovePositionTracking(trackIdx);
               continue;
            }
         }
      }
      
      // BREAKEVEN RÁPIDO
      if(InpUseQuickBreakeven && profitPips >= InpQuickBreakevenPips)
      {
         double breakeven = openPrice + (isBuy ? 2 : -2) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print(StringFormat("✓ BE RÁPIDO | +%.1f pips", profitPips));
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print(StringFormat("✓ BE RÁPIDO | +%.1f pips", profitPips));
         }
      }
      
      // TRAILING INTELIGENTE
      if(InpUseSmartTrailing && profitPips > InpSmartTrailingStart)
      {
         double trailDistance = InpSmartTrailingStep * 10 * point;
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
void OnTradeClose(bool isWin)
{
   if(!InpUseDrawdownProtection) return;
   
   if(isWin)
   {
      consecutiveLosses = 0;
   }
   else
   {
      consecutiveLosses++;
      
      if(consecutiveLosses >= InpMaxConsecutiveLosses)
      {
         pauseUntil = TimeCurrent() + InpPauseAfterLossesMinutes * 60;
         Print(StringFormat("⚠ PAUSA ACTIVADA: %d pérdidas consecutivas | Pausa hasta: %s", 
                           consecutiveLosses, 
                           TimeToString(pauseUntil)));
         consecutiveLosses = 0;
      }
   }
}

//+------------------------------------------------------------------+
bool DetectOppositeCandle(bool isLongPosition)
{
   double open1 = iOpen(_Symbol, PERIOD_M5, 1);
   double close1 = iClose(_Symbol, PERIOD_M5, 1);
   double high1 = iHigh(_Symbol, PERIOD_M5, 1);
   double low1 = iLow(_Symbol, PERIOD_M5, 1);
   
   double body = MathAbs(close1 - open1);
   double range = high1 - low1;
   
   if(range == 0) return false;
   
   double bodyPercent = body / range;
   
   if(isLongPosition)
   {
      if(close1 < open1 && bodyPercent > InpOppositeCandleStrength)
      {
         Print(StringFormat("⚠ Vela BAJISTA fuerte detectada: %.1f%%", bodyPercent * 100));
         return true;
      }
   }
   else
   {
      if(close1 > open1 && bodyPercent > InpOppositeCandleStrength)
      {
         Print(StringFormat("⚠ Vela ALCISTA fuerte detectada: %.1f%%", bodyPercent * 100));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
int FindPositionTracking(ulong ticket)
{
   for(int i = 0; i < ArraySize(posTracking); i++)
   {
      if(posTracking[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void RemovePositionTracking(int index)
{
   if(index < 0 || index >= ArraySize(posTracking)) return;
   
   int size = ArraySize(posTracking);
   for(int i = index; i < size - 1; i++)
   {
      posTracking[i] = posTracking[i + 1];
   }
   ArrayResize(posTracking, size - 1);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT ULTIMATE v4.00 - Detenido                ║");
   Print(StringFormat("║  Drawdown máximo: %.2f%%                                  ║", currentDrawdown));
   Print(StringFormat("║  Pérdidas consecutivas: %d                                ║", consecutiveLosses));
   Print("╚═══════════════════════════════════════════════════════════╝");
}

//+------------------------------------------------------------------+
