//+------------------------------------------------------------------+
//|                                            QUANTUM_V2_EA.mq5     |
//|                Mean Reversion Refinado - Versión Mejorada        |
//+------------------------------------------------------------------+
#property copyright "Quantum V2"
#property version   "2.00"

#include <Trade\Trade.mqh>

// CONFIGURACIÓN (refinada pero conservadora)
input double InpRiskPercent = 0.22;          // Riesgo 0.22% (ligeramente más)
input int    InpStopLossPips = 23;           // SL 23 pips (ajustado)
input int    InpTakeProfitPips = 52;         // TP 52 pips (RR 1:2.26)
input int    InpMagicNumber = 212223;

// PROTECCIONES (más estrictas)
input int    InpMaxTradesPerDay = 2;
input int    InpMaxConsecutiveLosses = 2;    // Más estricto: 2 vs 3
input double InpMaxDailyLossPercent = 1.2;   // Más estricto: 1.2% vs 1.5%
input double InpMaxDrawdownPercent = 12.0;   // Más estricto: 12% vs 15%

// MEAN REVERSION (refinado)
input int    InpBollingerPeriod = 20;
input double InpBollingerDeviation = 2.1;    // 2.1 vs 2.0 (más selectivo)
input int    InpRSIPeriod = 14;
input int    InpRSIOversold = 28;            // 28 vs 30 (más extremo)
input int    InpRSIOverbought = 72;          // 72 vs 70 (más extremo)

// GLOBALES
CTrade trade;
datetime lastBarTime = 0;
datetime lastTradeDate = 0;
int tradesThisDay = 0;
int consecutiveLosses = 0;
bool isPaused = false;
double dailyStartBalance = 0;
double peakBalance = 0;
int totalWins = 0;
int totalLosses = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║         QUANTUM V2 - Mean Reversion Refinado              ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Riesgo: ", InpRiskPercent, "% | SL: ", InpStopLossPips, " | TP: ", InpTakeProfitPips, "         ║");
   Print("║  RR: 1:", DoubleToString((double)InpTakeProfitPips/InpStopLossPips, 2), " | Max Trades: ", InpMaxTradesPerDay, "/día              ║");
   Print("║  Bollinger: ", InpBollingerDeviation, "σ | RSI: ", InpRSIOversold, "/", InpRSIOverbought, "                ║");
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
   UpdatePerformanceStats();
   
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   if(!PassProtectionFilters()) return;
   
   int signal = AnalyzeMeanReversion();
   
   if(signal == 1)
      ExecuteBuySignal();
   else if(signal == -1)
      ExecuteSellSignal();
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
      
      if(isPaused)
      {
         isPaused = false;
         consecutiveLosses = 0;
         Print("► Nuevo día - Sistema reactivado");
      }
   }
}

//+------------------------------------------------------------------+
void UpdatePerformanceStats()
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
               totalWins++;
               consecutiveLosses = 0;
               
               if(isPaused)
               {
                  isPaused = false;
                  Print("✓ WIN - Sistema reactivado");
               }
               
               Print("✓ WIN | ", totalWins, "W-", totalLosses, "L | WR: ", 
                     DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%");
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ PAUSADO - ", consecutiveLosses, " pérdidas consecutivas");
               }
               
               Print("✗ LOSS | ", totalWins, "W-", totalLosses, "L | Consecutive: ", consecutiveLosses);
            }
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            if(balance > peakBalance) peakBalance = balance;
            
            lastProcessedTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool PassProtectionFilters()
{
   if(isPaused) return false;
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   
   if(dailyLoss > InpMaxDailyLossPercent)
   {
      Print("⊗ Pérdida diaria: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdownPercent)
   {
      Print("⊗ Drawdown: ", DoubleToString(dd, 2), "%");
      return false;
   }
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(spread > 45) return false;
   
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hourGMT = timeStruct.hour;
   
   bool isLondon = (hourGMT >= 8 && hourGMT < 12);
   bool isNY = (hourGMT >= 13 && hourGMT < 17);
   
   if(!isLondon && !isNY) return false;
   if(timeStruct.day_of_week == 5 && hourGMT >= 15) return false;
   
   return true;
}

//+------------------------------------------------------------------+
int AnalyzeMeanReversion()
{
   double sma = CalculateSMA(InpBollingerPeriod);
   double stdDev = CalculateStdDev(InpBollingerPeriod, sma);
   double upperBand = sma + (InpBollingerDeviation * stdDev);
   double lowerBand = sma - (InpBollingerDeviation * stdDev);
   
   double rsi = CalculateRSI(InpRSIPeriod);
   
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   
   // REFINAMIENTO: Confirmación de volumen
   long vol1 = iVolume(_Symbol, PERIOD_CURRENT, 1);
   long avgVol = 0;
   for(int i = 2; i <= 11; i++)
      avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
   avgVol /= 10;
   
   bool volumeOK = (vol1 > avgVol * 1.1);
   
   // SEÑAL DE COMPRA
   if(rsi < InpRSIOversold)
   {
      bool touchedLowerBand = (low1 <= lowerBand * 1.0008);
      bool bullishCandle = (close1 > open1);
      bool strongBounce = (close1 > low1 + (high1 - low1) * 0.55);
      
      // REFINAMIENTO: Confirmación de momentum
      bool momentumOK = (close1 > close2 * 0.9998);
      
      if(touchedLowerBand && bullishCandle && strongBounce && volumeOK && momentumOK)
      {
         Print("► COMPRA | RSI:", DoubleToString(rsi, 1), " | Vol:", vol1, "/", avgVol);
         return 1;
      }
   }
   
   // Señal extrema
   if(rsi < 24 && close1 < lowerBand && close1 > open1 && volumeOK)
   {
      Print("► COMPRA EXTREMA | RSI:", DoubleToString(rsi, 1));
      return 1;
   }
   
   // SEÑAL DE VENTA
   if(rsi > InpRSIOverbought)
   {
      bool touchedUpperBand = (high1 >= upperBand * 0.9992);
      bool bearishCandle = (close1 < open1);
      bool strongDrop = (close1 < high1 - (high1 - low1) * 0.55);
      
      bool momentumOK = (close1 < close2 * 1.0002);
      
      if(touchedUpperBand && bearishCandle && strongDrop && volumeOK && momentumOK)
      {
         Print("▼ VENTA | RSI:", DoubleToString(rsi, 1), " | Vol:", vol1, "/", avgVol);
         return -1;
      }
   }
   
   if(rsi > 76 && close1 > upperBand && close1 < open1 && volumeOK)
   {
      Print("▼ VENTA EXTREMA | RSI:", DoubleToString(rsi, 1));
      return -1;
   }
   
   return 0;
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
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "QV2_BUY"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA | Lote:", lots, " | Trade ", tradesThisDay, "/", InpMaxTradesPerDay, "              ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
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
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "QV2_SELL"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA | Lote:", lots, " | Trade ", tradesThisDay, "/", InpMaxTradesPerDay, "              ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
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
      
      // REFINAMIENTO: Breakeven más temprano (18 pips vs 20)
      if(profitPips > 18)
      {
         double breakeven = openPrice + (isBuy ? 4 : -4) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("► Breakeven +4 pips");
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("▼ Breakeven +4 pips");
         }
      }
      
      // REFINAMIENTO: Trailing más temprano (32 pips vs 35)
      if(profitPips > 32)
      {
         double trailDistance = 13 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("► Trailing -13 pips | Profit:", DoubleToString(profitPips, 1));
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Trailing +13 pips | Profit:", DoubleToString(profitPips, 1));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
double CalculateSMA(int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += iClose(_Symbol, PERIOD_CURRENT, i);
   return sum / period;
}

//+------------------------------------------------------------------+
double CalculateStdDev(int period, double sma)
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
double CalculateRSI(int period)
{
   double gains = 0;
   double losses = 0;
   
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
   double rsi = 100 - (100 / (1 + rs));
   
   return rsi;
}
//+------------------------------------------------------------------+
