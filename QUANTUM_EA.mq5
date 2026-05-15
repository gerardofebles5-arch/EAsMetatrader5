//+------------------------------------------------------------------+
//|                                              QUANTUM_EA.mq5      |
//|                    Mean Reversion + Market Structure              |
//|                    Enfoque: XAUUSD Específico                     |
//+------------------------------------------------------------------+
#property copyright "Quantum Trading"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN ULTRA CONSERVADORA
// ═══════════════════════════════════════════════════════════════════
input double InpRiskPercent = 0.20;          // Riesgo por trade (0.20%)
input int    InpStopLossPips = 25;           // Stop Loss en pips
input int    InpTakeProfitPips = 50;         // Take Profit en pips (1:2 RR)
input int    InpMagicNumber = 202425;        // Magic number

// FILTROS DE PROTECCIÓN
input int    InpMaxTradesPerDay = 2;         // Máximo trades por día
input int    InpMaxConsecutiveLosses = 3;    // Pausar después de N pérdidas
input double InpMaxDailyLossPercent = 1.5;   // Pérdida máxima diaria %
input double InpMaxDrawdownPercent = 15.0;   // Drawdown máximo %

// PARÁMETROS DE MEAN REVERSION
input int    InpBollingerPeriod = 20;        // Período Bollinger Bands
input double InpBollingerDeviation = 2.0;    // Desviación estándar
input int    InpRSIPeriod = 14;              // Período RSI
input int    InpRSIOversold = 30;            // RSI sobreventa
input int    InpRSIOverbought = 70;          // RSI sobrecompra

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
   Print("║           QUANTUM EA - Mean Reversion System              ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  Estrategia: Mean Reversion + Bollinger + RSI             ║");
   Print("║  Riesgo: ", InpRiskPercent, "% | SL: ", InpStopLossPips, " pips | TP: ", InpTakeProfitPips, " pips  ║");
   Print("║  Risk:Reward = 1:", DoubleToString((double)InpTakeProfitPips/InpStopLossPips, 1), "                                        ║");
   Print("║  Max Trades/Día: ", InpMaxTradesPerDay, " | Max DD: ", InpMaxDrawdownPercent, "%              ║");
   Print("╚═══════════════════════════════════════════════════════════╝");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Solo procesar en nueva vela
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   // Actualizar estadísticas y controles
   UpdateDailyControls();
   UpdatePerformanceStats();
   
   // Gestionar posiciones abiertas
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   // FILTROS DE PROTECCIÓN
   if(!PassProtectionFilters()) return;
   
   // ANÁLISIS DE MEAN REVERSION
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
   
   // Resetear controles diarios
   if(lastTradeDate != today)
   {
      tradesThisDay = 0;
      lastTradeDate = today;
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      // Resetear pausa si es un nuevo día
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
               
               Print("✓ WIN | Stats: ", totalWins, "W-", totalLosses, "L | WR: ", 
                     DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%");
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ SISTEMA PAUSADO - ", consecutiveLosses, " pérdidas consecutivas");
               }
               
               Print("✗ LOSS | Stats: ", totalWins, "W-", totalLosses, "L | Consecutive: ", consecutiveLosses);
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
   // 1. Sistema pausado
   if(isPaused)
      return false;
   
   // 2. Máximo trades por día
   if(tradesThisDay >= InpMaxTradesPerDay)
      return false;
   
   // 3. Pérdida diaria máxima
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   
   if(dailyLoss > InpMaxDailyLossPercent)
   {
      Print("⊗ Pérdida diaria máxima alcanzada: ", DoubleToString(dailyLoss, 2), "%");
      return false;
   }
   
   // 4. Drawdown máximo
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdownPercent)
   {
      Print("⊗ Drawdown máximo alcanzado: ", DoubleToString(dd, 2), "%");
      return false;
   }
   
   // 5. Spread muy alto
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(spread > 50)
   {
      Print("⊗ Spread muy alto: ", spread, " puntos");
      return false;
   }
   
   // 6. Filtro de sesión (solo Londres y NY)
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hourGMT = timeStruct.hour;
   
   bool isLondon = (hourGMT >= 8 && hourGMT < 12);
   bool isNY = (hourGMT >= 13 && hourGMT < 17);
   
   if(!isLondon && !isNY)
      return false;
   
   // 7. No operar viernes tarde
   if(timeStruct.day_of_week == 5 && hourGMT >= 15)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
int AnalyzeMeanReversion()
{
   // ═══════════════════════════════════════════════════════════════
   // ESTRATEGIA: Mean Reversion con Bollinger Bands + RSI
   // 
   // COMPRA cuando:
   // - Precio toca o cruza banda inferior de Bollinger
   // - RSI está en sobreventa (< 30)
   // - Confirmación: vela alcista
   //
   // VENTA cuando:
   // - Precio toca o cruza banda superior de Bollinger
   // - RSI está en sobrecompra (> 70)
   // - Confirmación: vela bajista
   // ═══════════════════════════════════════════════════════════════
   
   // Calcular Bollinger Bands
   double sma = CalculateSMA(InpBollingerPeriod);
   double stdDev = CalculateStdDev(InpBollingerPeriod, sma);
   double upperBand = sma + (InpBollingerDeviation * stdDev);
   double lowerBand = sma - (InpBollingerDeviation * stdDev);
   
   // Calcular RSI
   double rsi = CalculateRSI(InpRSIPeriod);
   
   // Datos de velas
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double low2 = iLow(_Symbol, PERIOD_CURRENT, 2);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL DE COMPRA (Mean Reversion desde sobreventa)
   // ═══════════════════════════════════════════════════════════════
   if(rsi < InpRSIOversold)
   {
      // Precio debe tocar o estar cerca de banda inferior
      bool touchedLowerBand = (low1 <= lowerBand * 1.001);
      
      // Confirmación: vela alcista (cierre > apertura)
      bool bullishCandle = (close1 > open1);
      
      // Confirmación adicional: precio está rebotando
      bool bouncing = (close1 > low1 + (high1 - low1) * 0.5);
      
      if(touchedLowerBand && bullishCandle && bouncing)
      {
         Print("► SEÑAL COMPRA | RSI: ", DoubleToString(rsi, 1), 
               " | Precio: ", close1, " | Banda Inf: ", lowerBand);
         return 1;
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL DE VENTA (Mean Reversion desde sobrecompra)
   // ═══════════════════════════════════════════════════════════════
   if(rsi > InpRSIOverbought)
   {
      // Precio debe tocar o estar cerca de banda superior
      bool touchedUpperBand = (high1 >= upperBand * 0.999);
      
      // Confirmación: vela bajista (cierre < apertura)
      bool bearishCandle = (close1 < open1);
      
      // Confirmación adicional: precio está cayendo desde el tope
      bool falling = (close1 < high1 - (high1 - low1) * 0.5);
      
      if(touchedUpperBand && bearishCandle && falling)
      {
         Print("▼ SEÑAL VENTA | RSI: ", DoubleToString(rsi, 1), 
               " | Precio: ", close1, " | Banda Sup: ", upperBand);
         return -1;
      }
   }
   
   // ═══════════════════════════════════════════════════════════════
   // SEÑAL ADICIONAL: Reversión extrema
   // ═══════════════════════════════════════════════════════════════
   
   // Compra en RSI extremadamente bajo
   if(rsi < 25 && close1 < lowerBand && close1 > open1)
   {
      Print("► SEÑAL COMPRA EXTREMA | RSI: ", DoubleToString(rsi, 1));
      return 1;
   }
   
   // Venta en RSI extremadamente alto
   if(rsi > 75 && close1 > upperBand && close1 < open1)
   {
      Print("▼ SEÑAL VENTA EXTREMA | RSI: ", DoubleToString(rsi, 1));
      return -1;
   }
   
   return 0; // Sin señal
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
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "QUANTUM_BUY"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA EJECUTADA                                       ║");
      Print("║  Precio: ", ask, " | SL: ", sl, " | TP: ", tp, "  ║");
      Print("║  Lote: ", lots, " | Riesgo: ", InpRiskPercent, "%                    ║");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
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
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "QUANTUM_SELL"))
   {
      tradesThisDay++;
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA EJECUTADA                                        ║");
      Print("║  Precio: ", bid, " | SL: ", sl, " | TP: ", tp, "  ║");
      Print("║  Lote: ", lots, " | Riesgo: ", InpRiskPercent, "%                    ║");
      Print("║  Trade ", tradesThisDay, "/", InpMaxTradesPerDay, " hoy                                      ║");
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
      
      // Breakeven cuando profit > 20 pips
      if(profitPips > 20)
      {
         double breakeven = openPrice + (isBuy ? 5 : -5) * 10 * point;
         
         if(isBuy && breakeven > currentSL)
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("► Breakeven activado (BUY) en +5 pips");
         }
         else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
         {
            trade.PositionModify(ticket, breakeven, currentTP);
            Print("▼ Breakeven activado (SELL) en +5 pips");
         }
      }
      
      // Trailing stop cuando profit > 35 pips
      if(profitPips > 35)
      {
         double trailDistance = 15 * 10 * point;
         double newSL;
         
         if(isBuy)
         {
            newSL = currentPrice - trailDistance;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("► Trailing stop actualizado (BUY): ", newSL);
            }
         }
         else
         {
            newSL = currentPrice + trailDistance;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Trailing stop actualizado (SELL): ", newSL);
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
