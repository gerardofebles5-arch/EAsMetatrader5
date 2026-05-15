//+------------------------------------------------------------------+
//|                                            ELITE_MR_EA.mq5       |
//|                  Elite Mean Reversion - Diagonal Growth          |
//|                  Objetivo: Pendiente positiva constante          |
//+------------------------------------------------------------------+
#property copyright "Elite MR"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN ELITE - Optimizada para crecimiento diagonal
// ═══════════════════════════════════════════════════════════════════
input double InpBaseRisk = 0.25;             // Riesgo base %
input int    InpBaseSL = 20;                 // SL base (más ajustado)
input int    InpBaseTP = 55;                 // TP base (RR 1:2.75)
input int    InpMagic = 777888;

// PROTECCIONES ULTRA ESTRICTAS
input int    InpMaxTradesPerDay = 3;
input double InpMaxDailyLoss = 0.6;          // Solo 0.6% pérdida diaria
input double InpMaxDrawdown = 8.0;           // DD máximo 8%
input int    InpMaxConsecutiveLosses = 2;

// SEÑALES ULTRA SELECTIVAS
input int    InpRSIPeriod = 14;
input int    InpRSIOversold = 25;            // Extremo
input int    InpRSIOverbought = 75;          // Extremo
input double InpMinVolumeRatio = 1.2;        // Volumen mínimo
input bool   InpRequireBollinger = true;     // Confirmar con Bollinger

// COMPOUNDING INTELIGENTE
input bool   InpUseCompounding = true;       // Aumentar lote con ganancias
input double InpCompoundingRate = 0.03;      // 3% por win
input double InpMaxRiskMultiplier = 1.5;     // Máximo 1.5x riesgo

CTrade trade;
datetime lastBarTime = 0;
datetime lastTradeDate = 0;
int tradesThisDay = 0;
int consecutiveLosses = 0;
int consecutiveWins = 0;
double dailyStartBalance = 0;
double peakBalance = 0;
double currentDayLoss = 0;

// Compounding
double riskMultiplier = 1.0;
int totalWins = 0;
int totalLosses = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║            ELITE MR - Diagonal Growth System              ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Objetivo: Pendiente positiva constante                   ║");
   Print("║  Risk: ", InpBaseRisk, "% | SL:", InpBaseSL, " | TP:", InpBaseTP, " | RR:1:", DoubleToString((double)InpBaseTP/InpBaseSL,2), "  ║");
   Print("║  Max DD: ", InpMaxDrawdown, "% | Max Daily Loss: ", InpMaxDailyLoss, "%            ║");
   Print("║  Compounding: ", InpUseCompounding ? "ON" : "OFF", " | Ultra Selective Signals       ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   UpdateDailyControls();
   UpdatePerformanceTracking();
   
   if(PositionsTotal() > 0)
   {
      ManagePositionAggressively();
      return;
   }
   
   if(!PassUltraStrictFilters()) return;
   
   int signal = GetUltraSelectiveSignal();
   
   if(signal == 1)
      ExecuteBuy();
   else if(signal == -1)
      ExecuteSell();
}

//+------------------------------------------------------------------+
void UpdateDailyControls()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   datetime today = StringToTime(IntegerToString(t.year)+"."+IntegerToString(t.mon)+"."+IntegerToString(t.day));
   
   if(lastTradeDate != today)
   {
      tradesThisDay = 0;
      lastTradeDate = today;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      currentDayLoss = 0;
      
      // Reset solo si ganamos ayer
      if(consecutiveWins > 0)
         consecutiveLosses = 0;
      
      Print("► Nuevo día | Balance:", dailyStartBalance, " | Risk:", DoubleToString(riskMultiplier,2), "x");
   }
}

//+------------------------------------------------------------------+
void UpdatePerformanceTracking()
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
               totalWins++;
               consecutiveWins++;
               consecutiveLosses = 0;
               
               // COMPOUNDING: Aumentar riesgo gradualmente
               if(InpUseCompounding)
               {
                  riskMultiplier = MathMin(InpMaxRiskMultiplier, riskMultiplier * (1 + InpCompoundingRate));
               }
               
               double wr = (double)totalWins/(totalWins+totalLosses)*100;
               Print("✓ WIN | WR:", DoubleToString(wr,1), "% | CW:", consecutiveWins, " | Risk:", DoubleToString(riskMultiplier,2), "x");
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               consecutiveWins = 0;
               currentDayLoss += MathAbs(profit);
               
               // PROTECCIÓN: Reducir riesgo agresivamente
               riskMultiplier = MathMax(0.6, riskMultiplier * 0.75);
               
               double wr = (double)totalWins/(totalWins+totalLosses)*100;
               Print("✗ LOSS | WR:", DoubleToString(wr,1), "% | CL:", consecutiveLosses, " | Risk:", DoubleToString(riskMultiplier,2), "x");
            }
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            if(balance > peakBalance) peakBalance = balance;
            
            lastTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool PassUltraStrictFilters()
{
   // 1. Pérdidas consecutivas
   if(consecutiveLosses >= InpMaxConsecutiveLosses)
   {
      Print("⊗ Pausado por pérdidas consecutivas:", consecutiveLosses);
      return false;
   }
   
   // 2. Trades diarios
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
   // 3. Pérdida diaria
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(currentDayLoss > balance * InpMaxDailyLoss / 100.0)
   {
      Print("⊗ Pérdida diaria alcanzada:", DoubleToString(currentDayLoss,2));
      return false;
   }
   
   // 4. Drawdown
   double dd = (peakBalance - balance) / peakBalance * 100;
   if(dd > InpMaxDrawdown)
   {
      Print("⊗ Drawdown:", DoubleToString(dd,2), "%");
      return false;
   }
   
   // 5. Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > 40) return false;
   
   // 6. Sesión
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int hour = t.hour;
   
   bool isLondon = (hour >= 8 && hour < 12);
   bool isNY = (hour >= 13 && hour < 17);
   
   if(!isLondon && !isNY) return false;
   if(t.day_of_week == 5 && hour >= 15) return false;
   
   return true;
}

//+------------------------------------------------------------------+
int GetUltraSelectiveSignal()
{
   // RSI
   double rsi = CalcRSI(InpRSIPeriod);
   
   // Velas
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   // Volumen
   long vol1 = iVolume(_Symbol, PERIOD_CURRENT, 1);
   long avgVol = 0;
   for(int i = 2; i <= 11; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= 10;
   
   bool volumeOK = (vol1 > avgVol * InpMinVolumeRatio);
   if(!volumeOK) return 0;
   
   // Bollinger (opcional pero recomendado)
   bool bollingerOK = true;
   if(InpRequireBollinger)
   {
      double sma = CalcSMA(20);
      double stdDev = CalcStdDev(20, sma);
      double upperBand = sma + 2.0 * stdDev;
      double lowerBand = sma - 2.0 * stdDev;
      
      // Para compra: debe tocar banda inferior
      // Para venta: debe tocar banda superior
      bollingerOK = (low1 <= lowerBand * 1.002) || (high1 >= upperBand * 0.998);
   }
   
   if(!bollingerOK) return 0;
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL DE COMPRA ULTRA SELECTIVA
   // ═══════════════════════════════════════════════════════════════
   if(rsi < InpRSIOversold)
   {
      // 1. Vela alcista fuerte
      bool strongBullish = (close1 > open1) && ((close1 - open1) > (high1 - low1) * 0.6);
      
      // 2. Rebote confirmado
      bool bouncing = (close1 > close2 * 0.9995);
      
      // 3. Mecha inferior larga (rechazo)
      double lowerWick = MathMin(close1, open1) - low1;
      double body = MathAbs(close1 - open1);
      bool rejection = (lowerWick > body * 0.8);
      
      // 4. Toca banda inferior de Bollinger
      double sma = CalcSMA(20);
      double stdDev = CalcStdDev(20, sma);
      double lowerBand = sma - 2.0 * stdDev;
      bool touchedBand = (low1 <= lowerBand * 1.002);
      
      // SEÑAL: Necesita al menos 3 de 4 confirmaciones
      int confirmations = 0;
      if(strongBullish) confirmations++;
      if(bouncing) confirmations++;
      if(rejection) confirmations++;
      if(touchedBand) confirmations++;
      
      if(confirmations >= 3)
      {
         Print("► COMPRA ELITE | RSI:", DoubleToString(rsi,1), " | Conf:", confirmations, "/4");
         return 1;
      }
   }
   
   // Señal extrema (RSI < 22)
   if(rsi < 22 && close1 > open1 && volumeOK)
   {
      Print("► COMPRA EXTREMA | RSI:", DoubleToString(rsi,1));
      return 1;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL DE VENTA ULTRA SELECTIVA
   // ═══════════════════════════════════════════════════════════════
   if(rsi > InpRSIOverbought)
   {
      bool strongBearish = (close1 < open1) && ((open1 - close1) > (high1 - low1) * 0.6);
      bool falling = (close1 < close2 * 1.0005);
      
      double upperWick = high1 - MathMax(close1, open1);
      double body = MathAbs(close1 - open1);
      bool rejection = (upperWick > body * 0.8);
      
      double sma = CalcSMA(20);
      double stdDev = CalcStdDev(20, sma);
      double upperBand = sma + 2.0 * stdDev;
      bool touchedBand = (high1 >= upperBand * 0.998);
      
      int confirmations = 0;
      if(strongBearish) confirmations++;
      if(falling) confirmations++;
      if(rejection) confirmations++;
      if(touchedBand) confirmations++;
      
      if(confirmations >= 3)
      {
         Print("▼ VENTA ELITE | RSI:", DoubleToString(rsi,1), " | Conf:", confirmations, "/4");
         return -1;
      }
   }
   
   if(rsi > 78 && close1 < open1 && volumeOK)
   {
      Print("▼ VENTA EXTREMA | RSI:", DoubleToString(rsi,1));
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
void ExecuteBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL/TP dinámicos basados en pérdidas
   int slPips = InpBaseSL;
   int tpPips = InpBaseTP;
   
   if(consecutiveLosses > 0)
   {
      slPips = (int)(InpBaseSL * 0.80); // 20% menos SL
      Print("► SL reducido:", slPips, " pips");
   }
   
   double sl = ask - slPips * 10 * point;
   double tp = ask + tpPips * 10 * point;
   
   double lots = CalcLots(slPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ELITE_BUY"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA | Lote:", lots, " | SL:", slPips, " | TP:", tpPips, "        ║");
      Print("║  Risk:", DoubleToString(InpBaseRisk*riskMultiplier,2), "% | Trade:", tradesThisDay, "/", InpMaxTradesPerDay, "                  ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
void ExecuteSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   int slPips = InpBaseSL;
   int tpPips = InpBaseTP;
   
   if(consecutiveLosses > 0)
   {
      slPips = (int)(InpBaseSL * 0.80);
      Print("▼ SL reducido:", slPips, " pips");
   }
   
   double sl = bid + slPips * 10 * point;
   double tp = bid - tpPips * 10 * point;
   
   double lots = CalcLots(slPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ELITE_SELL"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA | Lote:", lots, " | SL:", slPips, " | TP:", tpPips, "        ║");
      Print("║  Risk:", DoubleToString(InpBaseRisk*riskMultiplier,2), "% | Trade:", tradesThisDay, "/", InpMaxTradesPerDay, "                  ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = balance * InpBaseRisk * riskMultiplier / 100.0;
   
   // Límite absoluto
   double maxRisk = balance * 0.4 / 100.0;
   risk = MathMin(risk, maxRisk);
   
   // Reducir si hay pérdidas
   if(consecutiveLosses > 0)
      risk *= 0.75;
   
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
void ManagePositionAggressively()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double pips = profit / (10 * point);
      
      // NIVEL 1: Breakeven ultra temprano a +15 pips
      if(pips > 15)
      {
         double be = openPrice + (isBuy ? 3 : -3) * 10 * point;
         
         if(isBuy && be > currentSL)
         {
            trade.PositionModify(ticket, be, currentTP);
            Print("► BE +3 pips | Profit:", DoubleToString(pips,1));
         }
         else if(!isBuy && (currentSL == 0 || be < currentSL))
         {
            trade.PositionModify(ticket, be, currentTP);
            Print("▼ BE +3 pips | Profit:", DoubleToString(pips,1));
         }
      }
      
      // NIVEL 2: Trailing agresivo a +25 pips
      if(pips > 25)
      {
         double trail = 10 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trail;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("► Trail -10 | Profit:", DoubleToString(pips,1));
            }
         }
         else
         {
            newSL = currentPrice + trail;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Trail +10 | Profit:", DoubleToString(pips,1));
            }
         }
      }
      
      // NIVEL 3: Asegurar ganancia a +35 pips
      if(pips > 35)
      {
         double secure = 7 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - secure;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("► Secure -7 | Profit:", DoubleToString(pips,1));
            }
         }
         else
         {
            newSL = currentPrice + secure;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Secure +7 | Profit:", DoubleToString(pips,1));
            }
         }
      }
      
      // NIVEL 4: Cierre parcial a +45 pips (asegurar 80% de ganancia)
      if(pips > 45)
      {
         double lockProfit = 5 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - lockProfit;
            if(newSL > currentSL)
               trade.PositionModify(ticket, newSL, currentTP);
         }
         else
         {
            newSL = currentPrice + lockProfit;
            if(currentSL == 0 || newSL < currentSL)
               trade.PositionModify(ticket, newSL, currentTP);
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
double CalcSMA(int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, PERIOD_CURRENT, i);
   return sum / period;
}

//+------------------------------------------------------------------+
double CalcStdDev(int period, double sma)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
   {
      double diff = iClose(_Symbol, PERIOD_CURRENT, i) - sma;
      sum += diff * diff;
   }
   return MathSqrt(sum / period);
}
//+------------------------------------------------------------------+
