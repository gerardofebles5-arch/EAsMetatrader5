//+------------------------------------------------------------------+
//|                              ASIA_BREAKOUT_SMART_EXIT_EA.mq5     |
//|                   v1.00 + CIERRES INTELIGENTES (Price Action)    |
//+------------------------------------------------------------------+
#property copyright "Asia Breakout v1.00 + Smart Exits"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// PARÁMETROS (VERSIÓN 1 ORIGINAL - SIN FILTROS)
// ═══════════════════════════════════════════════════════════════════

input group "═══ CONFIGURACIÓN BASE ═══"
input double InpRiskPercent = 1.0;
input int    InpMagicNumber = 999999;

input group "═══ RANGO ASIÁTICO ═══"
input int    InpAsiaStartHour = 0;
input int    InpAsiaEndHour = 8;
input int    InpBreakoutOffset = 5;

input group "═══ GESTIÓN BÁSICA ═══"
input double InpRiskRewardRatio = 1.5;
input int    InpMaxTradesPerDay = 20;
input double InpMaxDailyLoss = 5.0;

input group "═══ CIERRES INTELIGENTES (Price Action) ═══"
input bool   InpUseSmartExit = true;          // Activar cierres inteligentes
input int    InpMinPipsForSmartExit = 3;      // Mínimo +3 pips para analizar cierre
input bool   InpCloseOnOppositeCandle = true; // Cerrar si vela opuesta fuerte
input double InpOppositeCandleStrength = 0.70; // Vela opuesta >70% body
input bool   InpCloseOnWeakMomentum = true;   // Cerrar si momentum se debilita
input int    InpWeakMomentumBars = 3;         // 3 velas sin progreso
input bool   InpUseQuickBreakeven = true;     // BE rápido en +10 pips
input int    InpQuickBreakevenPips = 10;      // BE en +10 pips
input bool   InpUseSmartTrailing = true;      // Trailing inteligente
input int    InpSmartTrailingStart = 15;      // Iniciar en +15 pips
input int    InpSmartTrailingStep = 5;        // Mover cada 5 pips

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

// Tracking de posiciones para smart exit
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
   ArrayResize(posTracking, 0);
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT + SMART EXITS v1.00                       ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  ✅ SIN FILTROS - Solo Price Action                      ║");
   Print("║  ✅ Cierres Inteligentes Activados                       ║");
   Print("║  ✅ Detecta velas opuestas fuertes                       ║");
   Print("║  ✅ Detecta pérdida de momentum                          ║");
   Print("║  ✅ BE rápido en +10 pips                                ║");
   Print("║  ✅ Trailing inteligente cada 5 pips                     ║");
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
   
   if(!PassBasicProtections()) return;
   
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
      if(asiaRange.range >= 15 && asiaRange.range <= 200)
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
      ExecuteBuySignal();
      asiaRange.buyTriggerHit = true;
   }
   
   if(!asiaRange.sellTriggerHit && currentPrice < asiaRange.sellTrigger)
   {
      ExecuteSellSignal();
      asiaRange.sellTriggerHit = true;
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
      Print(StringFormat("✓ COMPRA | Entry: %s | SL: %s | TP: %s", 
                        DoubleToString(ask, _Digits), 
                        DoubleToString(sl, _Digits), 
                        DoubleToString(tp, _Digits)));
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
      Print(StringFormat("✓ VENTA | Entry: %s | SL: %s | TP: %s", 
                        DoubleToString(bid, _Digits), 
                        DoubleToString(sl, _Digits), 
                        DoubleToString(tp, _Digits)));
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
      
      // ═══════════════════════════════════════════════════════════════
      // CIERRES INTELIGENTES (Price Action Pura)
      // ═══════════════════════════════════════════════════════════════
      
      if(InpUseSmartExit && profitPips >= InpMinPipsForSmartExit)
      {
         // 1. VELA OPUESTA FUERTE
         if(InpCloseOnOppositeCandle)
         {
            if(DetectOppositeCandle(isBuy))
            {
               trade.PositionClose(ticket);
               Print(StringFormat("⚠ CIERRE INTELIGENTE: Vela opuesta fuerte | Profit: %.1f pips", profitPips));
               RemovePositionTracking(trackIdx);
               continue;
            }
         }
         
         // 2. PÉRDIDA DE MOMENTUM
         if(InpCloseOnWeakMomentum && trackIdx >= 0)
         {
            if(posTracking[trackIdx].barsWithoutProgress >= InpWeakMomentumBars &&
               posTracking[trackIdx].highestProfit > InpMinPipsForSmartExit)
            {
               trade.PositionClose(ticket);
               Print(StringFormat("⚠ CIERRE INTELIGENTE: Momentum débil | Profit: %.1f pips", profitPips));
               RemovePositionTracking(trackIdx);
               continue;
            }
         }
      }
      
      // ═══════════════════════════════════════════════════════════════
      // BREAKEVEN RÁPIDO
      // ═══════════════════════════════════════════════════════════════
      
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
      
      // ═══════════════════════════════════════════════════════════════
      // TRAILING INTELIGENTE
      // ═══════════════════════════════════════════════════════════════
      
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
   
   // Si estamos en LONG, detectar vela BAJISTA fuerte
   if(isLongPosition)
   {
      if(close1 < open1 && bodyPercent > InpOppositeCandleStrength)
      {
         Print(StringFormat("⚠ Vela BAJISTA fuerte detectada: %.1f%%", bodyPercent * 100));
         return true;
      }
   }
   // Si estamos en SHORT, detectar vela ALCISTA fuerte
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
