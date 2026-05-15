//+------------------------------------------------------------------+
//|                                          QUANTUM_PRO_EA.mq5      |
//|                Enhanced Mean Reversion + Adaptive System          |
//|                    Versión Mejorada de QUANTUM                    |
//+------------------------------------------------------------------+
#property copyright "Quantum Pro Trading"
#property version   "2.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN MEJORADA
// ═══════════════════════════════════════════════════════════════════
input double InpRiskPercent = 0.25;          // Riesgo por trade (0.25%)
input int    InpStopLossPips = 22;           // Stop Loss en pips
input int    InpTakeProfitPips = 55;         // Take Profit en pips (1:2.5 RR)
input int    InpMagicNumber = 303435;        // Magic number

// FILTROS DE PROTECCIÓN MEJORADOS
input int    InpMaxTradesPerDay = 3;         // Máximo trades por día
input int    InpMaxConsecutiveLosses = 2;    // Pausar después de N pérdidas
input double InpMaxDailyLossPercent = 1.2;   // Pérdida máxima diaria %
input double InpMaxDrawdownPercent = 12.0;   // Drawdown máximo %
input double InpMinWinRatePercent = 35.0;    // Win rate mínimo para continuar

// PARÁMETROS DE MEAN REVERSION MEJORADOS
input int    InpBollingerPeriod = 20;        // Período Bollinger Bands
input double InpBollingerDeviation = 2.2;    // Desviación estándar (más selectivo)
input int    InpRSIPeriod = 14;              // Período RSI
input int    InpRSIOversold = 28;            // RSI sobreventa (más extremo)
input int    InpRSIOverbought = 72;          // RSI sobrecompra (más extremo)

// PARÁMETROS DE CONFIRMACIÓN ADICIONAL
input bool   InpUseVolumeFilter = true;      // Usar filtro de volumen
input bool   InpUseATRFilter = true;         // Usar filtro de volatilidad
input bool   InpUseTrendFilter = true;       // Confirmar con tendencia mayor

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
double totalProfit = 0;
double totalLoss = 0;

// Adaptive risk management
double riskMultiplier = 1.0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyStartBalance = peakBalance;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║        QUANTUM PRO EA - Enhanced Mean Reversion           ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Estrategia: Mean Reversion + Confirmaciones Múltiples    ║");
   Print("║  Riesgo: ", InpRiskPercent, "% | SL: ", InpStopLossPips, " | TP: ", InpTakeProfitPips, "     ║");
   Print("║  Risk:Reward = 1:", DoubleToString((double)InpTakeProfitPips/InpStopLossPips, 1), "                                        ║");
   Print("║  Filtros: Volumen + ATR + Tendencia + Bollinger + RSI     ║");
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
   if(!PassMarketQualityFilters()) return;
   
   int signal = AnalyzeEnhancedMeanReversion();
   
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
               totalProfit += profit;
               consecutiveLosses = 0;
               
               // Aumentar riesgo gradualmente después de wins
               riskMultiplier = MathMin(1.3, riskMultiplier * 1.05);
               
               if(isPaused)
               {
                  isPaused = false;
                  Print("✓ WIN - Sistema reactivado");
               }
               
               double winRate = (double)totalWins/(totalWins+totalLosses)*100;
               double profitFactor = (totalLoss > 0) ? totalProfit/totalLoss : 0;
               
               Print("✓ WIN | WR: ", DoubleToString(winRate, 1), "% | PF: ", 
                     DoubleToString(profitFactor, 2), " | Risk: ", DoubleToString(riskMultiplier, 2));
            }
            else if(profit < 0)
            {
               totalLosses++;
               totalLoss += MathAbs(profit);
               consecutiveLosses++;
               
               // Reducir riesgo después de pérdidas
               riskMultiplier = MathMax(0.5, riskMultiplier * 0.85);
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ SISTEMA PAUSADO - ", consecutiveLosses, " pérdidas consecutivas");
               }
               
               double winRate = (double)totalWins/(totalWins+totalLosses)*100;
               Print("✗ LOSS | WR: ", DoubleToString(winRate, 1), "% | Consecutive: ", 
                     consecutiveLosses, " | Risk: ", DoubleToString(riskMultiplier, 2));
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
      Print("⊗ Pérdida diaria máxima: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdownPercent)
   {
      Print("⊗ Drawdown máximo: ", DoubleToString(dd, 2), "%");
      return false;
   }
   
   // Verificar win rate mínimo (después de 10 trades)
   int totalTrades = totalWins + totalLosses;
   if(totalTrades >= 10)
   {
      double winRate = (double)totalWins / totalTrades * 100;
      if(winRate < InpMinWinRatePercent)
      {
         Print("⊗ Win rate bajo: ", DoubleToString(winRate, 1), "% (mín: ", InpMinWinRatePercent, "%)");
         return false;
      }
   }
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(spread > 45)
   {
      Print("⊗ Spread alto: ", spread, " puntos");
      return false;
   }
   
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
bool PassMarketQualityFilters()
{
   // FILTRO ATR: Volatilidad adecuada
   if(InpUseATRFilter)
   {
      double atr14 = CalculateATR(14);
      double atr50 = CalculateATR(50);
      
      // Volatilidad debe estar en rango normal (no extrema ni muy baja)
      if(atr14 < atr50 * 0.7 || atr14 > atr50 * 2.0)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
int AnalyzeEnhancedMeanReversion()
{
   // Calcular indicadores
   double sma = CalculateSMA(InpBollingerPeriod);
   double stdDev = CalculateStdDev(InpBollingerPeriod, sma);
   double upperBand = sma + (InpBollingerDeviation * stdDev);
   double lowerBand = sma - (InpBollingerDeviation * stdDev);
   double middleBand = sma;
   
   double rsi = CalculateRSI(InpRSIPeriod);
   double atr = CalculateATR(14);
   
   // Datos de velas
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double low2 = iLow(_Symbol, PERIOD_CURRENT, 2);
   
   // Confirmación de volumen
   bool volumeConfirmed = true;
   if(InpUseVolumeFilter)
   {
      long vol1 = iVolume(_Symbol, PERIOD_CURRENT, 1);
      long avgVol = 0;
      for(int i = 2; i <= 11; i++)
         avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
      avgVol /= 10;
      
      volumeConfirmed = (vol1 > avgVol * 1.15);
   }
   
   // Confirmación de tendencia mayor (EMA 50)
   bool trendConfirmed = true;
   if(InpUseTrendFilter)
   {
      double ema50 = CalculateEMA(50);
      // Para compra: precio debe estar por encima de EMA50 o cerca
      // Para venta: precio debe estar por debajo de EMA50 o cerca
      trendConfirmed = true; // Se verifica en cada señal específica
   }
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL DE COMPRA MEJORADA
   // ═══════════════════════════════════════════════════════════════
   if(rsi < InpRSIOversold)
   {
      bool touchedLowerBand = (low1 <= lowerBand * 1.0008);
      bool bullishCandle = (close1 > open1);
      bool strongBounce = (close1 > low1 + (high1 - low1) * 0.6);
      
      // Confirmación adicional: precio está rebotando desde mínimo
      bool reboundConfirmed = (close1 > close2 || (close1 > open1 && low1 < low2));
      
      // Verificar tendencia mayor
      bool trendOK = true;
      if(InpUseTrendFilter)
      {
         double ema50 = CalculateEMA(50);
         trendOK = (close1 > ema50 * 0.997); // Cerca o por encima de EMA50
      }
      
      if(touchedLowerBand && bullishCandle && strongBounce && 
         reboundConfirmed && volumeConfirmed && trendOK)
      {
         // Confirmación final: distancia desde banda
         double distanceFromBand = (close1 - lowerBand) / atr;
         
         if(distanceFromBand < 0.5) // Muy cerca de la banda
         {
            Print("► SEÑAL COMPRA | RSI: ", DoubleToString(rsi, 1), 
                  " | Dist: ", DoubleToString(distanceFromBand, 2), " ATR");
            return 1;
         }
      }
   }
   
   // Señal extrema de compra
   if(rsi < 22 && low1 < lowerBand && close1 > open1 && volumeConfirmed)
   {
      Print("► SEÑAL COMPRA EXTREMA | RSI: ", DoubleToString(rsi, 1));
      return 1;
   }
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL DE VENTA MEJORADA
   // ═══════════════════════════════════════════════════════════════
   if(rsi > InpRSIOverbought)
   {
      bool touchedUpperBand = (high1 >= upperBand * 0.9992);
      bool bearishCandle = (close1 < open1);
      bool strongDrop = (close1 < high1 - (high1 - low1) * 0.6);
      
      bool dropConfirmed = (close1 < close2 || (close1 < open1 && high1 > high2));
      
      bool trendOK = true;
      if(InpUseTrendFilter)
      {
         double ema50 = CalculateEMA(50);
         trendOK = (close1 < ema50 * 1.003);
      }
      
      if(touchedUpperBand && bearishCandle && strongDrop && 
         dropConfirmed && volumeConfirmed && trendOK)
      {
         double distanceFromBand = (upperBand - close1) / atr;
         
         if(distanceFromBand < 0.5)
         {
            Print("▼ SEÑAL VENTA | RSI: ", DoubleToString(rsi, 1), 
                  " | Dist: ", DoubleToString(distanceFromBand, 2), " ATR");
            return -1;
         }
      }
   }
   
   if(rsi > 78 && high1 > upperBand && close1 < open1 && volumeConfirmed)
   {
      Print("▼ SEÑAL VENTA EXTREMA | RSI: ", DoubleToString(rsi, 1));
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
      Print("⊗ Lote muy pequeño: ", lots);
      return;
   }
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "QPRO_BUY"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA EJECUTADA                                       ║");
      Print("║  Precio: ", ask, " | Lote: ", lots, "                      ║");
      Print("║  SL: ", InpStopLossPips, " pips | TP: ", InpTakeProfitPips, " pips              ║");
      Print("║  Riesgo: ", DoubleToString(InpRiskPercent * riskMultiplier, 2), "% | Trade ", tradesThisDay, "/", InpMaxTradesPerDay, "                ║");
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
      Print("⊗ Lote muy pequeño: ", lots);
      return;
   }
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "QPRO_SELL"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA EJECUTADA                                        ║");
      Print("║  Precio: ", bid, " | Lote: ", lots, "                      ║");
      Print("║  SL: ", InpStopLossPips, " pips | TP: ", InpTakeProfitPips, " pips              ║");
      Print("║  Riesgo: ", DoubleToString(InpRiskPercent * riskMultiplier, 2), "% | Trade ", tradesThisDay, "/", InpMaxTradesPerDay, "                ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent * riskMultiplier / 100.0;
   
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
      
      // Breakeven mejorado: cuando profit > 18 pips, mover SL a +3 pips
      if(profitPips > 18)
      {
         double breakeven = openPrice + (isBuy ? 3 : -3) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
         {
            if(trade.PositionModify(ticket, breakeven, currentTP))
               Print("► Breakeven +3 pips (BUY)");
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            if(trade.PositionModify(ticket, breakeven, currentTP))
               Print("▼ Breakeven +3 pips (SELL)");
         }
      }
      
      // Trailing stop mejorado: cuando profit > 30 pips
      if(profitPips > 30)
      {
         double trailDistance = 12 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("► Trailing -12 pips (BUY) | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("▼ Trailing +12 pips (SELL) | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
         }
      }
      
      // Cierre parcial en profit extremo (opcional)
      if(profitPips > 45)
      {
         // Mover SL muy cerca para asegurar ganancia
         double secureSL;
         if(isBuy)
         {
            secureSL = currentPrice - 8 * 10 * point;
            if(secureSL > currentSL)
            {
               if(trade.PositionModify(ticket, secureSL, currentTP))
                  Print("► SL asegurado -8 pips | Profit: ", DoubleToString(profitPips, 1), " pips");
            }
         }
         else
         {
            secureSL = currentPrice + 8 * 10 * point;
            if(currentSL == 0 || secureSL < currentSL)
            {
               if(trade.PositionModify(ticket, secureSL, currentTP))
                  Print("▼ SL asegurado +8 pips | Profit: ", DoubleToString(profitPips, 1), " pips");
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
double CalculateATR(int period)
{
   double atr = 0;
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      double prevClose = iClose(_Symbol, PERIOD_CURRENT, i + 1);
      double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      atr += tr;
   }
   return atr / period;
}

//+------------------------------------------------------------------+
double CalculateEMA(int period)
{
   double multiplier = 2.0 / (period + 1);
   double ema = iClose(_Symbol, PERIOD_CURRENT, period);
   
   for(int i = period - 1; i >= 1; i--)
   {
      double close = iClose(_Symbol, PERIOD_CURRENT, i);
      ema = (close - ema) * multiplier + ema;
   }
   
   return ema;
}
//+------------------------------------------------------------------+
