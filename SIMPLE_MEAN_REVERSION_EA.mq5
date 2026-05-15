//+------------------------------------------------------------------+
//|                                  SIMPLE_MEAN_REVERSION_EA.mq5    |
//|                    Lo Más Simple Posible - Sin Complejidad       |
//+------------------------------------------------------------------+
#property copyright "Simple MR"
#property version   "1.00"

#include <Trade\Trade.mqh>

// CONFIGURACIÓN MINIMALISTA
input double InpRisk = 0.20;                 // Riesgo %
input int    InpSL = 25;                     // Stop Loss pips
input int    InpTP = 50;                     // Take Profit pips
input int    InpMagic = 333444;

// PROTECCIONES BÁSICAS
input int    InpMaxTrades = 2;               // Max trades/día
input double InpMaxDD = 15.0;                // Max drawdown %

// INDICADORES SIMPLES
input int    InpRSIPeriod = 14;
input int    InpRSILow = 30;
input int    InpRSIHigh = 70;

CTrade trade;
datetime lastBar = 0;
int tradesToday = 0;
datetime lastDate = 0;
double peak = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   peak = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("SIMPLE MEAN REVERSION - Activado");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar == lastBar) return;
   lastBar = bar;
   
   // Reset diario
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   datetime today = StringToTime(IntegerToString(t.year)+"."+IntegerToString(t.mon)+"."+IntegerToString(t.day));
   if(lastDate != today)
   {
      tradesToday = 0;
      lastDate = today;
   }
   
   // Si hay posición, gestionar
   if(PositionsTotal() > 0)
   {
      ManagePosition();
      return;
   }
   
   // Protecciones básicas
   if(tradesToday >= InpMaxTrades) return;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > peak) peak = balance;
   double dd = (peak - balance) / peak * 100;
   if(dd > InpMaxDD) return;
   
   // Filtro de sesión simple
   int hour = t.hour;
   if(hour < 8 || hour > 17) return;
   if(t.day_of_week == 5 && hour >= 15) return;
   
   // Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > 50) return;
   
   // SEÑAL SIMPLE
   int signal = GetSignal();
   
   if(signal == 1)
      OpenBuy();
   else if(signal == -1)
      OpenSell();
}

//+------------------------------------------------------------------+
int GetSignal()
{
   // RSI simple
   double rsi = CalcRSI(InpRSIPeriod);
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   
   // COMPRA: RSI bajo + vela alcista
   if(rsi < InpRSILow && close > open)
   {
      Print("► BUY | RSI:", DoubleToString(rsi, 1));
      return 1;
   }
   
   // VENTA: RSI alto + vela bajista
   if(rsi > InpRSIHigh && close < open)
   {
      Print("▼ SELL | RSI:", DoubleToString(rsi, 1));
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = ask - InpSL * 10 * point;
   double tp = ask + InpTP * 10 * point;
   
   double lots = CalcLots(InpSL * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "SMR_BUY"))
   {
      tradesToday++;
      Print("✓ BUY | Lots:", lots);
   }
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double sl = bid + InpSL * 10 * point;
   double tp = bid - InpTP * 10 * point;
   
   double lots = CalcLots(InpSL * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "SMR_SELL"))
   {
      tradesToday++;
      Print("✓ SELL | Lots:", lots);
   }
}

//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * InpRisk / 100.0;
   
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = risk / (slDist * tickVal / tickSize);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / step) * step;
   return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
void ManagePosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double pips = profit / (10 * point);
      
      // Breakeven simple a +20 pips
      if(pips > 20)
      {
         double be = openPrice + (isBuy ? 5 : -5) * 10 * point;
         double currentSL = PositionGetDouble(POSITION_SL);
         
         if(isBuy && be > currentSL)
            trade.PositionModify(ticket, be, PositionGetDouble(POSITION_TP));
         else if(!isBuy && (currentSL == 0 || be < currentSL))
            trade.PositionModify(ticket, be, PositionGetDouble(POSITION_TP));
      }
   }
}

//+------------------------------------------------------------------+
double CalcRSI(int period)
{
   double gains = 0, losses = 0;
   
   for(int i = 1; i <= period; i++)
   {
      double change = iClose(_Symbol, PERIOD_CURRENT, i) - iClose(_Symbol, PERIOD_CURRENT, i + 1);
      if(change > 0)
         gains += change;
      else
         losses += MathAbs(change);
   }
   
   double avgGain = gains / period;
   double avgLoss = losses / period;
   
   if(avgLoss == 0) return 100;
   
   double rs = avgGain / avgLoss;
   return 100 - (100 / (1 + rs));
}
//+------------------------------------------------------------------+
