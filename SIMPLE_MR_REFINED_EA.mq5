//+------------------------------------------------------------------+
//|                                    SIMPLE_MR_REFINED_EA.mq5      |
//|              Simple Mean Reversion + SL Inteligente              |
//|              SOLO cambio: Perder menos cuando pierde             |
//+------------------------------------------------------------------+
#property copyright "Simple MR Refined"
#property version   "1.00"

#include <Trade\Trade.mqh>

// CONFIGURACIÓN REFINADA
input double InpRisk = 0.22;                 // Riesgo base (aumentado ligeramente)
input int    InpSL = 23;                     // SL optimizado
input int    InpTP = 52;                     // TP optimizado (RR 1:2.26)
input int    InpMagic = 555666;

// PROTECCIONES MEJORADAS
input int    InpMaxTrades = 3;               // Permitir 1 trade más
input double InpMaxDD = 12.0;                // DD más estricto
input double InpMaxDailyLoss = 0.8;          // Pérdida diaria máxima %

// INDICADORES REFINADOS
input int    InpRSIPeriod = 14;
input int    InpRSILow = 28;                 // Más extremo (mejor señal)
input int    InpRSIHigh = 72;                // Más extremo (mejor señal)

// PROTECCIÓN DE PÉRDIDAS
input bool   InpUseSmartSL = true;
input double InpMaxLossPercent = 0.45;       // Límite por trade

// FILTROS ADICIONALES
input bool   InpUseVolumeFilter = true;      // Confirmar con volumen
input double InpMinVolumeMultiplier = 1.15;  // Volumen mínimo vs promedio

CTrade trade;
datetime lastBar = 0;
int tradesToday = 0;
datetime lastDate = 0;
double peak = 0;

// Tracking de pérdidas
int consecutiveLosses = 0;
double currentDayLoss = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   peak = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("SIMPLE MR REFINED - SL Inteligente Activado");
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
      currentDayLoss = 0;
      consecutiveLosses = 0;
   }
   
   // Actualizar estadísticas
   UpdateStats();
   
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
   
   // No operar si ya perdimos mucho hoy
   if(currentDayLoss > balance * InpMaxDailyLoss / 100.0)
   {
      Print("⊗ Pérdida diaria alcanzada: ", DoubleToString(currentDayLoss, 2));
      return;
   }
   
   // NUEVO: Después de 2 pérdidas consecutivas, pausar
   if(consecutiveLosses >= 2)
   {
      Print("⊗ Pausado por pérdidas consecutivas");
      return;
   }
   
   // Filtro de sesión
   int hour = t.hour;
   if(hour < 8 || hour > 17) return;
   if(t.day_of_week == 5 && hour >= 15) return;
   
   // Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > 50) return;
   
   // SEÑAL (igual que SIMPLE)
   int signal = GetSignal();
   
   if(signal == 1)
      OpenBuy();
   else if(signal == -1)
      OpenSell();
}

//+------------------------------------------------------------------+
void UpdateStats()
{
   static ulong lastTicket = 0;
   
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      if(total > 0)
      {
         ulong ticket = HistoryDealGetTicket(total - 1);
         if(ticket != lastTicket && ticket > 0)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            
            if(profit > 0)
            {
               consecutiveLosses = 0;
               Print("✓ WIN | Consecutive losses reset");
            }
            else if(profit < 0)
            {
               consecutiveLosses++;
               currentDayLoss += MathAbs(profit);
               Print("✗ LOSS | Consecutive: ", consecutiveLosses, " | Day loss: ", DoubleToString(currentDayLoss, 2));
            }
            
            lastTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
int GetSignal()
{
   double rsi = CalcRSI(InpRSIPeriod);
   
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   // Filtro de volumen
   bool volumeOK = true;
   if(InpUseVolumeFilter)
   {
      long vol = iVolume(_Symbol, PERIOD_CURRENT, 1);
      long avgVol = 0;
      for(int i = 2; i <= 11; i++)
         avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
      avgVol /= 10;
      
      volumeOK = (vol > avgVol * InpMinVolumeMultiplier);
   }
   
   if(!volumeOK) return 0;
   
   // COMPRA: RSI bajo + vela alcista + rebote fuerte
   if(rsi < InpRSILow && close > open)
   {
      // Confirmar rebote fuerte (cierre en 60% superior del rango)
      double range = high - low;
      if(range > 0 && (close - low) > range * 0.6)
      {
         Print("► BUY | RSI:", DoubleToString(rsi, 1), " | Vol: OK");
         return 1;
      }
   }
   
   // Señal extrema de compra
   if(rsi < 25 && close > open && volumeOK)
   {
      Print("► BUY EXTREMO | RSI:", DoubleToString(rsi, 1));
      return 1;
   }
   
   // VENTA: RSI alto + vela bajista + caída fuerte
   if(rsi > InpRSIHigh && close < open)
   {
      // Confirmar caída fuerte (cierre en 60% inferior del rango)
      double range = high - low;
      if(range > 0 && (high - close) > range * 0.6)
      {
         Print("▼ SELL | RSI:", DoubleToString(rsi, 1), " | Vol: OK");
         return -1;
      }
   }
   
   // Señal extrema de venta
   if(rsi > 75 && close < open && volumeOK)
   {
      Print("▼ SELL EXTREMO | RSI:", DoubleToString(rsi, 1));
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL/TP base
   int slPips = InpSL;
   int tpPips = InpTP;
   
   // SL inteligente - reducir si hay pérdidas consecutivas
   if(InpUseSmartSL && consecutiveLosses > 0)
   {
      slPips = (int)(InpSL * 0.82); // 18% menos SL (más agresivo)
      Print("► SL reducido a ", slPips, " pips (pérdidas: ", consecutiveLosses, ")");
   }
   
   double sl = ask - slPips * 10 * point;
   double tp = ask + tpPips * 10 * point;
   
   // Calcular lote con límite de pérdida máxima
   double lots = CalcLotsWithMaxLoss(slPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "SMR_BUY"))
   {
      tradesToday++;
      Print("✓ BUY | Lots:", lots, " | SL:", slPips, " pips");
   }
}

//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   int slPips = InpSL;
   int tpPips = InpTP;
   
   // SL inteligente
   if(InpUseSmartSL && consecutiveLosses > 0)
   {
      slPips = (int)(InpSL * 0.82); // 18% menos SL (más agresivo)
      Print("▼ SL reducido a ", slPips, " pips (pérdidas: ", consecutiveLosses, ")");
   }
   
   double sl = bid + slPips * 10 * point;
   double tp = bid - tpPips * 10 * point;
   
   double lots = CalcLotsWithMaxLoss(slPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "SMR_SELL"))
   {
      tradesToday++;
      Print("✓ SELL | Lots:", lots, " | SL:", slPips, " pips");
   }
}

//+------------------------------------------------------------------+
double CalcLotsWithMaxLoss(double slDist)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Calcular riesgo normal
   double normalRisk = balance * InpRisk / 100.0;
   
   // NUEVO: Limitar pérdida máxima por trade
   double maxLoss = balance * InpMaxLossPercent / 100.0;
   double actualRisk = MathMin(normalRisk, maxLoss);
   
   // Si hay pérdidas consecutivas, reducir riesgo adicional
   if(consecutiveLosses > 0)
   {
      actualRisk *= 0.80; // 20% menos riesgo (más conservador)
   }
   
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   double lots = actualRisk / (slDist * tickVal / tickSize);
   
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
      
      // Breakeven más temprano a +18 pips
      if(pips > 18)
      {
         double be = openPrice + (isBuy ? 4 : -4) * 10 * point;
         double currentSL = PositionGetDouble(POSITION_SL);
         
         if(isBuy && be > currentSL)
         {
            trade.PositionModify(ticket, be, PositionGetDouble(POSITION_TP));
            Print("► Breakeven +4 pips");
         }
         else if(!isBuy && (currentSL == 0 || be < currentSL))
         {
            trade.PositionModify(ticket, be, PositionGetDouble(POSITION_TP));
            Print("▼ Breakeven +4 pips");
         }
      }
      
      // Trailing más agresivo a +28 pips
      if(pips > 28)
      {
         double trail = 11 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trail;
            if(newSL > PositionGetDouble(POSITION_SL))
            {
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
               Print("► Trailing -11 pips | Profit:", DoubleToString(pips, 1));
            }
         }
         else
         {
            newSL = currentPrice + trail;
            double currentSL = PositionGetDouble(POSITION_SL);
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
               Print("▼ Trailing +11 pips | Profit:", DoubleToString(pips, 1));
            }
         }
      }
      
      // Asegurar ganancia a +40 pips
      if(pips > 40)
      {
         double secureSL;
         if(isBuy)
         {
            secureSL = currentPrice - 8 * 10 * point;
            if(secureSL > PositionGetDouble(POSITION_SL))
               trade.PositionModify(ticket, secureSL, PositionGetDouble(POSITION_TP));
         }
         else
         {
            secureSL = currentPrice + 8 * 10 * point;
            double currentSL = PositionGetDouble(POSITION_SL);
            if(currentSL == 0 || secureSL < currentSL)
               trade.PositionModify(ticket, secureSL, PositionGetDouble(POSITION_TP));
         }
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
