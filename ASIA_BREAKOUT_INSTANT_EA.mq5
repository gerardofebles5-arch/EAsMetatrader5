//+------------------------------------------------------------------+
//|                        ASIA_BREAKOUT_INSTANT_EA.mq5              |
//|                   OPERA INMEDIATAMENTE - Sin Esperas             |
//+------------------------------------------------------------------+
#property copyright "Asia Breakout Instant - Immediate Trading"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN
// ═══════════════════════════════════════════════════════════════════
input group "=== CONFIGURACION ==="
input double InpRiskPercent = 1.0;           // Riesgo por trade
input int    InpStopLossPips = 25;           // Stop Loss pips
input int    InpTakeProfitPips = 50;         // Take Profit pips
input int    InpMagicNumber = 111111;        // Magic number

input group "=== RANGO ASIATICO ==="
input int    InpAsiaStartHour = 0;           // Inicio rango (GMT)
input int    InpAsiaEndHour = 4;             // Fin rango (4 horas)
input int    InpBreakoutOffsetPips = 5;      // Offset FIJO en pips

input group "=== PROTECCIONES ==="
input int    InpMaxTradesPerDay = 30;        // Max trades/día
input bool   InpUseTrailing = true;          // Usar trailing
input int    InpTrailingStart = 20;          // Iniciar trailing
input int    InpTrailingDistance = 10;       // Distancia trailing

// ═══════════════════════════════════════════════════════════════════
// GLOBALES
// ═══════════════════════════════════════════════════════════════════
CTrade trade;

double asiaHigh = 0;
double asiaLow = 0;
double asiaRange = 0;
bool rangeCalculated = false;
double buyTrigger = 0;
double sellTrigger = 0;

datetime lastTradeDate = 0;
int tradesThisDay = 0;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT INSTANT v1.00                             ║");
   Print("║  Opera INMEDIATAMENTE al detectar breakout              ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Rango: ", InpAsiaStartHour, ":00-", InpAsiaEndHour, ":00 | Offset: ", InpBreakoutOffsetPips, " pips          ║");
   Print("║  SL: ", InpStopLossPips, " | TP: ", InpTakeProfitPips, " | Max: ", InpMaxTradesPerDay, "/día              ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar nueva barra
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   UpdateDailyControls();
   
   // Gestionar posiciones abiertas
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   // Verificar límite de trades
   if(tradesThisDay >= InpMaxTradesPerDay) return;
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;
   
   // CALCULAR RANGO durante sesión asiática
   if(currentHour >= InpAsiaStartHour && currentHour < InpAsiaEndHour)
   {
      CalculateAsiaRange();
      rangeCalculated = false; // Resetear hasta que termine la sesión
   }
   
   // FINALIZAR RANGO al terminar sesión asiática
   if(currentHour == InpAsiaEndHour && !rangeCalculated)
   {
      FinalizeAsiaRange();
   }
   
   // BUSCAR BREAKOUT después de la sesión asiática
   if(currentHour >= InpAsiaEndHour && rangeCalculated)
   {
      CheckBreakout();
   }
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
      rangeCalculated = false;
      asiaHigh = 0;
      asiaLow = 0;
      buyTrigger = 0;
      sellTrigger = 0;
      
      Print("═══ NUEVO DÍA ═══");
   }
}

//+------------------------------------------------------------------+
void CalculateAsiaRange()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   datetime asiaStart = StringToTime(StringFormat("%d.%d.%d %d:00", 
                                                   timeStruct.year, 
                                                   timeStruct.mon, 
                                                   timeStruct.day, 
                                                   InpAsiaStartHour));
   
   int bars = Bars(_Symbol, PERIOD_M5, asiaStart, TimeCurrent());
   if(bars <= 0) return;
   
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   if(CopyHigh(_Symbol, PERIOD_M5, 0, bars, highs) > 0 &&
      CopyLow(_Symbol, PERIOD_M5, 0, bars, lows) > 0)
   {
      asiaHigh = highs[ArrayMaximum(highs)];
      asiaLow = lows[ArrayMinimum(lows)];
      
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      asiaRange = (asiaHigh - asiaLow) / (10 * point);
   }
}

//+------------------------------------------------------------------+
void FinalizeAsiaRange()
{
   if(asiaRange <= 0) return;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double offset = InpBreakoutOffsetPips * 10 * point;
   
   buyTrigger = asiaHigh + offset;
   sellTrigger = asiaLow - offset;
   rangeCalculated = true;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print(StringFormat("║  RANGO ASIA CALCULADO: %.1f pips                        ║", asiaRange));
   Print(StringFormat("║  High: %s | Low: %s              ║", 
         DoubleToString(asiaHigh, _Digits), 
         DoubleToString(asiaLow, _Digits)));
   Print(StringFormat("║  BUY Trigger: %s                              ║", 
         DoubleToString(buyTrigger, _Digits)));
   Print(StringFormat("║  SELL Trigger: %s                             ║", 
         DoubleToString(sellTrigger, _Digits)));
   Print("╚═══════════════════════════════════════════════════════════╝");
}

//+------------------------------------------------------------------+
void CheckBreakout()
{
   if(buyTrigger == 0 || sellTrigger == 0) return;
   
   double currentPrice = iClose(_Symbol, PERIOD_M5, 0);
   double open0 = iOpen(_Symbol, PERIOD_M5, 0);
   double close0 = iClose(_Symbol, PERIOD_M5, 0);
   
   // BREAKOUT ALCISTA
   if(currentPrice > buyTrigger && close0 > open0)
   {
      Print(StringFormat("► BREAKOUT ALCISTA detectado | Precio: %s > Trigger: %s", 
            DoubleToString(currentPrice, _Digits), 
            DoubleToString(buyTrigger, _Digits)));
      ExecuteBuySignal();
      return;
   }
   
   // BREAKOUT BAJISTA
   if(currentPrice < sellTrigger && close0 < open0)
   {
      Print(StringFormat("▼ BREAKOUT BAJISTA detectado | Precio: %s < Trigger: %s", 
            DoubleToString(currentPrice, _Digits), 
            DoubleToString(sellTrigger, _Digits)));
      ExecuteSellSignal();
      return;
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
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⚠ Lote muy pequeño: ", lots);
      return;
   }
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ASIA_INSTANT_BUY"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓✓✓ COMPRA EJECUTADA ✓✓✓                               ║");
      Print(StringFormat("║  Entry: %s | SL: %s | TP: %s    ║", 
            DoubleToString(ask, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(tp, _Digits)));
      Print(StringFormat("║  Lote: %.2f | Trade %d/%d                            ║", 
            lots, tradesThisDay, InpMaxTradesPerDay));
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
   else
   {
      Print("✗ ERROR al abrir COMPRA: ", GetLastError());
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
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⚠ Lote muy pequeño: ", lots);
      return;
   }
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ASIA_INSTANT_SELL"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓✓✓ VENTA EJECUTADA ✓✓✓                                ║");
      Print(StringFormat("║  Entry: %s | SL: %s | TP: %s    ║", 
            DoubleToString(bid, _Digits),
            DoubleToString(sl, _Digits),
            DoubleToString(tp, _Digits)));
      Print(StringFormat("║  Lote: %.2f | Trade %d/%d                            ║", 
            lots, tradesThisDay, InpMaxTradesPerDay));
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
   else
   {
      Print("✗ ERROR al abrir VENTA: ", GetLastError());
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
   if(!InpUseTrailing) return;
   
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
               Print(StringFormat("► TRAILING | Profit: +%.1f pips", profitPips));
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print(StringFormat("▼ TRAILING | Profit: +%.1f pips", profitPips));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA BREAKOUT INSTANT - Detenido                        ║");
   Print(StringFormat("║  Trades hoy: %d                                          ║", tradesThisDay));
   Print("╚═══════════════════════════════════════════════════════════╝");
}
//+------------------------------------------------------------------+
