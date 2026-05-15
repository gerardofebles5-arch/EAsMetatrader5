//+------------------------------------------------------------------+
//|                                      MAHORAGA_QUANTUM_EA.mq5     |
//|          Mean Reversion + Adaptación Inteligente (Mahoraga)      |
//|          "Se adapta a cualquier fenómeno una vez lo experimenta" |
//+------------------------------------------------------------------+
#property copyright "Mahoraga Quantum"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN BASE (Mean Reversion que funciona)
// ═══════════════════════════════════════════════════════════════════
input double InpBaseRisk = 0.20;             // Riesgo base %
input int    InpBaseSL = 25;                 // SL base en pips
input int    InpBaseTP = 50;                 // TP base en pips
input int    InpMagicNumber = 444555;

// PARÁMETROS DE ADAPTACIÓN (Mahoraga)
input bool   InpUseAdaptation = true;        // Activar adaptación
input int    InpAdaptationSpeed = 5;         // Velocidad de adaptación (1-10)
input double InpMinRisk = 0.10;              // Riesgo mínimo %
input double InpMaxRisk = 0.30;              // Riesgo máximo %

// PROTECCIONES INTELIGENTES
input int    InpMaxTradesPerDay = 3;
input int    InpMaxConsecutiveLosses = 2;
input double InpMaxDailyLoss = 1.0;          // 1% pérdida diaria máxima
input double InpMaxDrawdown = 12.0;

// INDICADORES
input int    InpRSIPeriod = 14;
input int    InpRSIOversold = 30;
input int    InpRSIOverbought = 70;
input int    InpBollingerPeriod = 20;
input double InpBollingerDev = 2.0;

// ═══════════════════════════════════════════════════════════════════
// GLOBALES
// ═══════════════════════════════════════════════════════════════════
CTrade trade;
datetime lastBarTime = 0;
datetime lastTradeDate = 0;
int tradesThisDay = 0;
int consecutiveLosses = 0;
bool isPaused = false;
double dailyStartBalance = 0;
double peakBalance = 0;

// Estadísticas para adaptación
int totalWins = 0;
int totalLosses = 0;
double totalProfitAmount = 0;
double totalLossAmount = 0;

// ADAPTACIÓN MAHORAGA
double adaptiveRiskMultiplier = 1.0;
double adaptiveSLMultiplier = 1.0;
double adaptiveTPMultiplier = 1.0;

// Memoria de condiciones de mercado
struct MarketCondition {
   double volatility;
   double rsiLevel;
   bool wasWin;
   datetime time;
};
MarketCondition marketMemory[50];
int memoryCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║       MAHORAGA QUANTUM - Adaptive Mean Reversion          ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Base: MR que funciona + Adaptación Mahoraga              ║");
   Print("║  Riesgo: ", InpBaseRisk, "% (adaptativo ", InpMinRisk, "-", InpMaxRisk, "%)        ║");
   Print("║  SL/TP: ", InpBaseSL, "/", InpBaseTP, " pips (adaptativos)                  ║");
   Print("║  Adaptación: ", InpUseAdaptation ? "ACTIVADA" : "DESACTIVADA", "                                ║");
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
   UpdatePerformanceAndAdapt();
   
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   if(!PassProtectionFilters()) return;
   
   // Analizar condiciones de mercado
   double volatility = CalculateVolatility();
   double rsi = CalculateRSI(InpRSIPeriod);
   
   // Consultar memoria: ¿estas condiciones han sido buenas antes?
   double conditionQuality = AnalyzeMarketMemory(volatility, rsi);
   
   // Si las condiciones son malas históricamente, ser más cauteloso
   if(conditionQuality < 0.3)
   {
      Print("⊗ Condiciones de mercado desfavorables (calidad: ", DoubleToString(conditionQuality, 2), ")");
      return;
   }
   
   int signal = GetMeanReversionSignal();
   
   if(signal == 1)
      ExecuteBuySignal(volatility, rsi, conditionQuality);
   else if(signal == -1)
      ExecuteSellSignal(volatility, rsi, conditionQuality);
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
void UpdatePerformanceAndAdapt()
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
            
            // Guardar condiciones de mercado en memoria
            if(memoryCount < 50)
            {
               marketMemory[memoryCount].volatility = CalculateVolatility();
               marketMemory[memoryCount].rsiLevel = CalculateRSI(InpRSIPeriod);
               marketMemory[memoryCount].wasWin = (profit > 0);
               marketMemory[memoryCount].time = TimeCurrent();
               memoryCount++;
            }
            
            if(profit > 0)
            {
               totalWins++;
               totalProfitAmount += profit;
               consecutiveLosses = 0;
               
               // ADAPTACIÓN: Aumentar confianza gradualmente
               if(InpUseAdaptation)
               {
                  adaptiveRiskMultiplier = MathMin(InpMaxRisk/InpBaseRisk, adaptiveRiskMultiplier * 1.05);
                  adaptiveTPMultiplier = MathMin(1.3, adaptiveTPMultiplier * 1.02);
               }
               
               if(isPaused)
               {
                  isPaused = false;
                  Print("✓ WIN - Sistema reactivado");
               }
               
               double winRate = (double)totalWins/(totalWins+totalLosses)*100;
               double profitFactor = (totalLossAmount > 0) ? totalProfitAmount/totalLossAmount : 0;
               
               Print("✓ WIN | WR:", DoubleToString(winRate, 1), "% PF:", DoubleToString(profitFactor, 2), 
                     " | Risk:", DoubleToString(adaptiveRiskMultiplier, 2), "x");
            }
            else if(profit < 0)
            {
               totalLosses++;
               totalLossAmount += MathAbs(profit);
               consecutiveLosses++;
               
               // ADAPTACIÓN: Reducir riesgo y ajustar SL/TP
               if(InpUseAdaptation)
               {
                  adaptiveRiskMultiplier = MathMax(InpMinRisk/InpBaseRisk, adaptiveRiskMultiplier * 0.80);
                  adaptiveSLMultiplier = MathMax(0.7, adaptiveSLMultiplier * 0.95);
                  adaptiveTPMultiplier = MathMax(0.8, adaptiveTPMultiplier * 0.98);
               }
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ PAUSADO - ", consecutiveLosses, " pérdidas | Risk reducido a ", 
                        DoubleToString(adaptiveRiskMultiplier, 2), "x");
               }
               
               double winRate = (double)totalWins/(totalWins+totalLosses)*100;
               Print("✗ LOSS | WR:", DoubleToString(winRate, 1), "% | Consecutive:", consecutiveLosses, 
                     " | Risk:", DoubleToString(adaptiveRiskMultiplier, 2), "x SL:", DoubleToString(adaptiveSLMultiplier, 2), "x");
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
   
   if(dailyLoss > InpMaxDailyLoss)
   {
      Print("⊗ Pérdida diaria: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdown)
   {
      Print("⊗ Drawdown: ", DoubleToString(dd, 2), "%");
      return false;
   }
   
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
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
double AnalyzeMarketMemory(double currentVol, double currentRSI)
{
   if(memoryCount < 5) return 0.5; // Sin suficiente memoria, neutral
   
   int similarWins = 0;
   int similarLosses = 0;
   
   // Buscar condiciones similares en memoria
   for(int i = 0; i < memoryCount; i++)
   {
      double volDiff = MathAbs(marketMemory[i].volatility - currentVol) / currentVol;
      double rsiDiff = MathAbs(marketMemory[i].rsiLevel - currentRSI);
      
      // Si las condiciones son similares (volatilidad ±20%, RSI ±10)
      if(volDiff < 0.20 && rsiDiff < 10)
      {
         if(marketMemory[i].wasWin)
            similarWins++;
         else
            similarLosses++;
      }
   }
   
   int totalSimilar = similarWins + similarLosses;
   if(totalSimilar == 0) return 0.5;
   
   return (double)similarWins / totalSimilar;
}

//+------------------------------------------------------------------+
int GetMeanReversionSignal()
{
   double rsi = CalculateRSI(InpRSIPeriod);
   
   // Bollinger Bands
   double sma = CalculateSMA(InpBollingerPeriod);
   double stdDev = CalculateStdDev(InpBollingerPeriod, sma);
   double upperBand = sma + (InpBollingerDev * stdDev);
   double lowerBand = sma - (InpBollingerDev * stdDev);
   
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   
   // COMPRA: RSI bajo + toca banda inferior + vela alcista
   if(rsi < InpRSIOversold)
   {
      bool touchedLower = (low1 <= lowerBand * 1.001);
      bool bullish = (close1 > open1);
      bool bouncing = (close1 > low1 + (high1 - low1) * 0.5);
      
      if(touchedLower && bullish && bouncing)
      {
         Print("► SEÑAL COMPRA | RSI:", DoubleToString(rsi, 1));
         return 1;
      }
   }
   
   // Señal extrema
   if(rsi < 25 && close1 < lowerBand && close1 > open1)
   {
      Print("► COMPRA EXTREMA | RSI:", DoubleToString(rsi, 1));
      return 1;
   }
   
   // VENTA: RSI alto + toca banda superior + vela bajista
   if(rsi > InpRSIOverbought)
   {
      bool touchedUpper = (high1 >= upperBand * 0.999);
      bool bearish = (close1 < open1);
      bool falling = (close1 < high1 - (high1 - low1) * 0.5);
      
      if(touchedUpper && bearish && falling)
      {
         Print("▼ SEÑAL VENTA | RSI:", DoubleToString(rsi, 1));
         return -1;
      }
   }
   
   if(rsi > 75 && close1 > upperBand && close1 < open1)
   {
      Print("▼ VENTA EXTREMA | RSI:", DoubleToString(rsi, 1));
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
void ExecuteBuySignal(double volatility, double rsi, double quality)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL/TP adaptativos
   int adaptiveSL = (int)(InpBaseSL * adaptiveSLMultiplier);
   int adaptiveTP = (int)(InpBaseTP * adaptiveTPMultiplier);
   
   // Si la calidad de condiciones es baja, SL más ajustado
   if(quality < 0.5)
      adaptiveSL = (int)(adaptiveSL * 0.85);
   
   double sl = ask - adaptiveSL * 10 * point;
   double tp = ask + adaptiveTP * 10 * point;
   
   // Riesgo adaptativo
   double adaptiveRisk = InpBaseRisk * adaptiveRiskMultiplier;
   
   // Si calidad baja, reducir riesgo adicional
   if(quality < 0.5)
      adaptiveRisk *= 0.8;
   
   double lots = CalculateAdaptiveLots(adaptiveSL * 10 * point, adaptiveRisk);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "MQ_BUY"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA | Lote:", lots, " | SL:", adaptiveSL, " TP:", adaptiveTP, "      ║");
      Print("║  Risk:", DoubleToString(adaptiveRisk, 2), "% | Calidad:", DoubleToString(quality, 2), " | Trade:", tradesThisDay, "/", InpMaxTradesPerDay, "  ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal(double volatility, double rsi, double quality)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   int adaptiveSL = (int)(InpBaseSL * adaptiveSLMultiplier);
   int adaptiveTP = (int)(InpBaseTP * adaptiveTPMultiplier);
   
   if(quality < 0.5)
      adaptiveSL = (int)(adaptiveSL * 0.85);
   
   double sl = bid + adaptiveSL * 10 * point;
   double tp = bid - adaptiveTP * 10 * point;
   
   double adaptiveRisk = InpBaseRisk * adaptiveRiskMultiplier;
   
   if(quality < 0.5)
      adaptiveRisk *= 0.8;
   
   double lots = CalculateAdaptiveLots(adaptiveSL * 10 * point, adaptiveRisk);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote muy pequeño");
      return;
   }
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "MQ_SELL"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA | Lote:", lots, " | SL:", adaptiveSL, " TP:", adaptiveTP, "      ║");
      Print("║  Risk:", DoubleToString(adaptiveRisk, 2), "% | Calidad:", DoubleToString(quality, 2), " | Trade:", tradesThisDay, "/", InpMaxTradesPerDay, "  ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
double CalculateAdaptiveLots(double slDistance, double riskPercent)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPercent / 100.0;
   
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
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      // Breakeven adaptativo
      double beThreshold = 20 * adaptiveSLMultiplier;
      if(profitPips > beThreshold)
      {
         double beOffset = 5 * adaptiveSLMultiplier;
         double breakeven = openPrice + (isBuy ? beOffset : -beOffset) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("► Breakeven adaptativo +", DoubleToString(beOffset, 1), " pips");
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("▼ Breakeven adaptativo +", DoubleToString(beOffset, 1), " pips");
         }
      }
      
      // Trailing stop adaptativo
      double trailThreshold = 35 * adaptiveTPMultiplier;
      if(profitPips > trailThreshold)
      {
         double trailDistance = 15 * adaptiveSLMultiplier;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance * 10 * point;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("► Trailing adaptativo -", DoubleToString(trailDistance, 1), " pips");
            }
         }
         else
         {
            newSL = currentPrice + trailDistance * 10 * point;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Trailing adaptativo +", DoubleToString(trailDistance, 1), " pips");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
double CalculateVolatility()
{
   double atr14 = 0;
   for(int i = 1; i <= 14; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      double prevClose = iClose(_Symbol, PERIOD_CURRENT, i + 1);
      double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      atr14 += tr;
   }
   return atr14 / 14;
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
