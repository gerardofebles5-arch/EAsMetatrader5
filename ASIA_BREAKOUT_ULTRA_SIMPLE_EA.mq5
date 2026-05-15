//+------------------------------------------------------------------+
//|                       ASIA_BREAKOUT_ULTRA_SIMPLE_EA.mq5          |
//|                   SIN FILTROS - Solo Breakout Puro               |
//+------------------------------------------------------------------+
#property copyright "Asia Breakout Ultra Simple - No Filters"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN MÍNIMA
// ═══════════════════════════════════════════════════════════════════
input group "=== CONFIGURACION BASE ==="
input double InpRiskPercent = 1.0;           // Riesgo por trade
input int    InpStopLossPips = 25;           // Stop Loss pips
input int    InpTakeProfitPips = 50;         // Take Profit pips
input int    InpMagicNumber = 999999;        // Magic number

input group "=== RANGO ASIATICO ==="
input int    InpAsiaStartHour = 0;           // Inicio rango (GMT)
input int    InpAsiaEndHour = 4;             // Fin rango (4 horas)
input double InpBreakoutOffsetPercent = 0.08;// Offset (8% del rango)

input group "=== TRAILING SIMPLE ==="
input bool   InpUseTrailing = true;          // Usar trailing
input int    InpTrailingStart = 20;          // Iniciar trailing en pips
input int    InpTrailingDistance = 10;       // Distancia trailing

input group "=== PROTECCIONES MINIMAS ==="
input int    InpMaxTradesPerDay = 20;        // Max trades/día
input double InpMaxDailyLoss = 5.0;          // Pérdida máxima diaria %

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

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   asiaRange.isValid = false;
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT ULTRA SIMPLE v1.00                        ║");
   Print("║  SIN FILTROS - Breakout Puro                             ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Rango: ", InpAsiaStartHour, ":00-", InpAsiaEndHour, ":00 (", InpAsiaEndHour-InpAsiaStartHour, "h)                        ║");
   Print("║  Offset: ", DoubleToString(InpBreakoutOffsetPercent*100,0), "% | Max: ", InpMaxTradesPerDay, "/día                      ║");
   Print("║  SL: ", InpStopLossPips, " | TP: ", InpTakeProfitPips, " | Trailing: ", InpTrailingStart, " pips           ║");
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
   }
}

//+------------------------------------------------------------------+
bool PassBasicProtections()
{
   // Solo 2 protecciones básicas
   
   // 1. Max trades
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
   // 2. Pérdida diaria
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   if(dailyLoss > InpMaxDailyLoss) return false;
   
   return true;
}

//+------------------------------------------------------------------+
void UpdateAsiaRange()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;
   
   // Durante sesión asiática: actualizar rango
   if(currentHour >= InpAsiaStartHour && currentHour < InpAsiaEndHour)
   {
      datetime asiaStart = StringToTime(StringFormat("%d.%d.%d %d:00", 
                                                      timeStruct.year, 
                                                      timeStruct.mon, 
                                                      timeStruct.day, 
                                                      InpAsiaStartHour));
      
      int bars = Bars(_Symbol, PERIOD_M5, asiaStart, TimeCurrent());
      
      if(bars > 0)
      {
         double highs[], lows[];
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
   
   // Al finalizar sesión: validar y calcular triggers
   if(currentHour == InpAsiaEndHour && timeStruct.min < 5 && !asiaRange.isValid)
   {
      // SIN FILTROS DE RANGO - Acepta cualquier rango
      if(asiaRange.range > 0)
      {
         asiaRange.isValid = true;
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         
         // Offset proporcional
         double offset = asiaRange.range * InpBreakoutOffsetPercent * 10 * point;
         
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
   
   // Validar vela ACTUAL (índice 0)
   double currentPrice = iClose(_Symbol, PERIOD_M5, 0);
   double open0 = iOpen(_Symbol, PERIOD_M5, 0);
   double close0 = iClose(_Symbol, PERIOD_M5, 0);
   
   // COMPRA: Precio rompe trigger alcista
   if(!asiaRange.buyTriggerHit && currentPrice > asiaRange.buyTrigger)
   {
      // SIN FILTROS - Solo verifica que vela sea alcista
      if(close0 > open0)
      {
         ExecuteBuySignal();
         asiaRange.buyTriggerHit = true;
      }
   }
   
   // VENTA: Precio rompe trigger bajista
   if(!asiaRange.sellTriggerHit && currentPrice < asiaRange.sellTrigger)
   {
      // SIN FILTROS - Solo verifica que vela sea bajista
      if(close0 < open0)
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
   
   double sl = ask - InpStopLossPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(InpStopLossPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ASIA_SIMPLE_BUY"))
   {
      tradesThisDay++;
      Print(StringFormat("✓ COMPRA | Entry: %s | SL: %d | TP: %d | Lote: %.2f | Trade %d/%d", 
            DoubleToString(ask, _Digits), InpStopLossPips, InpTakeProfitPips, lots, tradesThisDay, InpMaxTradesPerDay));
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + InpStopLossPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(InpStopLossPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ASIA_SIMPLE_SELL"))
   {
      tradesThisDay++;
      Print(StringFormat("✓ VENTA | Entry: %s | SL: %d | TP: %d | Lote: %.2f | Trade %d/%d", 
            DoubleToString(bid, _Digits), InpStopLossPips, InpTakeProfitPips, lots, tradesThisDay, InpMaxTradesPerDay));
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      if(!InpUseTrailing) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      // TRAILING SIMPLE
      if(profitPips >= InpTrailingStart)
      {
         double trailDistance = InpTrailingDistance * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print(StringFormat("► TRAILING | Profit: %.1f pips | New SL: %s", 
                     profitPips, DoubleToString(newSL, _Digits)));
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print(StringFormat("▼ TRAILING | Profit: %.1f pips | New SL: %s", 
                     profitPips, DoubleToString(newSL, _Digits)));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT ULTRA SIMPLE - Detenido                   ║");
   Print(StringFormat("║  Trades hoy: %d                                          ║", tradesThisDay));
   Print("╚═══════════════════════════════════════════════════════════╝");
}
//+------------------------------------------------------------------+
