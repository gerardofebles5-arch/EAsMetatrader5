//+------------------------------------------------------------------+
//|                                            APEX_TRADER_EA.mq5    |
//|                    Ultra-Selective Price Action System            |
//|                    CALIDAD > CANTIDAD                             |
//+------------------------------------------------------------------+
#property copyright "Apex Trading"
#property version   "1.00"

#include <Trade\Trade.mqh>

// INPUTS ULTRA CONSERVADORES
input double InpRiskPercent = 0.25;          // Riesgo por operación (0.25%)
input int    InpMaxTradesPerDay = 1;         // Máximo 1 operación por día
input int    InpStopLossPips = 18;           // SL fijo en pips (18 pips)
input int    InpTakeProfitPips = 54;         // TP fijo en pips (54 pips = 1:3 RR)
input int    InpMagicNumber = 100200;        // Magic number

// FILTROS DE CALIDAD
input bool   InpUseSessionFilter = true;     // Solo operar en sesiones activas
input bool   InpUseTrendFilter = true;       // Solo operar con tendencia clara
input bool   InpUseVolatilityFilter = true;  // Filtrar baja volatilidad
input int    InpMaxConsecutiveLosses = 2;    // Pausar después de N pérdidas

// GLOBALES
CTrade trade;
datetime lastBarTime = 0;
datetime lastTradeDate = 0;
int tradesThisDay = 0;
int consecutiveLosses = 0;
bool isPaused = false;

double peakBalance = 0;
int totalWins = 0;
int totalLosses = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("═══════════════════════════════════════════");
   Print("  APEX TRADER EA - Ultra Selective System");
   Print("  Risk: ", InpRiskPercent, "% | Max Trades/Day: ", InpMaxTradesPerDay);
   Print("  SL: ", InpStopLossPips, " pips | TP: ", InpTakeProfitPips, " pips");
   Print("  Risk:Reward = 1:", (double)InpTakeProfitPips/InpStopLossPips);
   Print("═══════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Solo procesar en nueva vela
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;
   
   // Actualizar estadísticas
   UpdatePerformanceStats();
   
   // Gestionar posiciones abiertas
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   // FILTROS DE PROTECCIÓN
   if(!PassProtectionFilters()) return;
   
   // FILTROS DE CALIDAD DE MERCADO
   if(!PassMarketQualityFilters()) return;
   
   // ANÁLISIS DE SEÑAL
   int signal = AnalyzePriceAction();
   
   if(signal == 1)
      ExecuteBuySignal();
   else if(signal == -1)
      ExecuteSellSignal();
}

//+------------------------------------------------------------------+
void UpdatePerformanceStats()
{
   static ulong lastProcessedTicket = 0;
   
   // Verificar si hay nuevas operaciones cerradas
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
               isPaused = false;
               Print("✓ WIN | Total: ", totalWins, "W-", totalLosses, "L | WR: ", 
                     DoubleToString((double)totalWins/(totalWins+totalLosses)*100, 1), "%");
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  isPaused = true;
                  Print("⚠ PAUSED after ", consecutiveLosses, " consecutive losses");
               }
               
               Print("✗ LOSS | Total: ", totalWins, "W-", totalLosses, "L | Consecutive: ", consecutiveLosses);
            }
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            if(balance > peakBalance) peakBalance = balance;
            
            lastProcessedTicket = ticket;
         }
      }
   }
   
   // Resetear contador diario
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime today = StringToTime(IntegerToString(timeStruct.year) + "." + 
                                  IntegerToString(timeStruct.mon) + "." + 
                                  IntegerToString(timeStruct.day));
   
   if(lastTradeDate != today)
   {
      tradesThisDay = 0;
      lastTradeDate = today;
   }
}

//+------------------------------------------------------------------+
bool PassProtectionFilters()
{
   // 1. Sistema pausado por pérdidas consecutivas
   if(isPaused)
   {
      Print("⊗ Sistema PAUSADO por pérdidas consecutivas");
      return false;
   }
   
   // 2. Máximo de operaciones por día alcanzado
   if(tradesThisDay >= InpMaxTradesPerDay)
   {
      return false; // Silencioso, no spam
   }
   
   // 3. Drawdown máximo
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd = (peakBalance - balance) / peakBalance * 100;
   
   if(dd > 20)
   {
      Print("⊗ Drawdown alto: ", DoubleToString(dd, 1), "% - NO OPERAR");
      return false;
   }
   
   // 4. Spread muy alto
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(spread > 40)
   {
      Print("⊗ Spread muy alto: ", spread, " puntos");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassMarketQualityFilters()
{
   // FILTRO 1: SESIÓN ACTIVA
   if(InpUseSessionFilter)
   {
      MqlDateTime timeStruct;
      TimeToStruct(TimeCurrent(), timeStruct);
      int hourGMT = timeStruct.hour;
      
      // Solo Londres (8-12 GMT) y Nueva York (13-17 GMT)
      bool isLondonSession = (hourGMT >= 8 && hourGMT < 12);
      bool isNYSession = (hourGMT >= 13 && hourGMT < 17);
      
      if(!isLondonSession && !isNYSession)
         return false;
      
      // No operar viernes tarde
      if(timeStruct.day_of_week == 5 && hourGMT >= 15)
         return false;
   }
   
   // FILTRO 2: VOLATILIDAD ADECUADA
   if(InpUseVolatilityFilter)
   {
      double atr14 = CalculateATR(14);
      double atr50 = CalculateATR(50);
      
      // Volatilidad debe ser normal o alta (no baja)
      if(atr14 < atr50 * 0.75)
         return false;
   }
   
   // FILTRO 3: TENDENCIA CLARA
   if(InpUseTrendFilter)
   {
      double ema20 = CalculateEMA(20);
      double ema50 = CalculateEMA(50);
      double ema100 = CalculateEMA(100);
      
      // Debe haber alineación de EMAs
      bool bullishAlignment = (ema20 > ema50 && ema50 > ema100);
      bool bearishAlignment = (ema20 < ema50 && ema50 < ema100);
      
      if(!bullishAlignment && !bearishAlignment)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
int AnalyzePriceAction()
{
   // Obtener datos de velas
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, 2);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double low2 = iLow(_Symbol, PERIOD_CURRENT, 2);
   
   // EMAs para contexto
   double ema20 = CalculateEMA(20);
   double ema50 = CalculateEMA(50);
   double ema100 = CalculateEMA(100);
   
   // ATR para medir tamaños
   double atr = CalculateATR(14);
   
   // Determinar contexto de tendencia
   bool bullishTrend = (ema20 > ema50 && ema50 > ema100);
   bool bearishTrend = (ema20 < ema50 && ema50 < ema100);
   
   // ═══════════════════════════════════════════════════════════
   // SEÑAL ALCISTA: Rechazo en soporte + tendencia alcista
   // ═══════════════════════════════════════════════════════════
   if(bullishTrend)
   {
      // Buscar swing low reciente
      double swingLow = FindSwingLow(20);
      
      // Precio debe estar cerca del swing low
      bool nearSupport = (low1 <= swingLow * 1.0015);
      
      if(nearSupport)
      {
         // PATRÓN 1: Pin Bar alcista (rechazo con mecha inferior larga)
         double body1 = MathAbs(close1 - open1);
         double lowerWick1 = MathMin(close1, open1) - low1;
         double upperWick1 = high1 - MathMax(close1, open1);
         double totalRange1 = high1 - low1;
         
         bool isPinBar = (lowerWick1 > body1 * 1.5 && 
                         lowerWick1 > totalRange1 * 0.5 && 
                         close1 > open1);
         
         // PATRÓN 2: Engulfing alcista
         bool isEngulfing = (close2 < open2 && // Vela anterior bajista
                            close1 > open1 && // Vela actual alcista
                            close1 > open2 && // Cierra por encima del open anterior
                            open1 < close2);  // Abre por debajo del close anterior
         
         // PATRÓN 3: Pullback a EMA20 con rechazo
         bool isPullbackToEMA = (low1 <= ema20 * 1.001 && 
                                close1 > ema20 && 
                                close1 > close2);
         
         // Confirmación de volumen
         long vol1 = iVolume(_Symbol, PERIOD_CURRENT, 1);
         long avgVol = 0;
         for(int i = 2; i <= 11; i++)
            avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
         avgVol /= 10;
         
         bool volumeConfirmation = (vol1 > avgVol * 1.1);
         
         // SEÑAL ALCISTA si hay patrón + volumen
         if((isPinBar || isEngulfing || isPullbackToEMA) && volumeConfirmation)
         {
            Print("► SEÑAL ALCISTA detectada | Patrón: ", 
                  isPinBar ? "PinBar" : (isEngulfing ? "Engulfing" : "Pullback"));
            return 1;
         }
      }
   }
   
   // ═══════════════════════════════════════════════════════════
   // SEÑAL BAJISTA: Rechazo en resistencia + tendencia bajista
   // ═══════════════════════════════════════════════════════════
   if(bearishTrend)
   {
      // Buscar swing high reciente
      double swingHigh = FindSwingHigh(20);
      
      // Precio debe estar cerca del swing high
      bool nearResistance = (high1 >= swingHigh * 0.9985);
      
      if(nearResistance)
      {
         // PATRÓN 1: Pin Bar bajista (rechazo con mecha superior larga)
         double body1 = MathAbs(close1 - open1);
         double upperWick1 = high1 - MathMax(close1, open1);
         double lowerWick1 = MathMin(close1, open1) - low1;
         double totalRange1 = high1 - low1;
         
         bool isPinBar = (upperWick1 > body1 * 1.5 && 
                         upperWick1 > totalRange1 * 0.5 && 
                         close1 < open1);
         
         // PATRÓN 2: Engulfing bajista
         bool isEngulfing = (close2 > open2 && // Vela anterior alcista
                            close1 < open1 && // Vela actual bajista
                            close1 < open2 && // Cierra por debajo del open anterior
                            open1 > close2);  // Abre por encima del close anterior
         
         // PATRÓN 3: Pullback a EMA20 con rechazo
         bool isPullbackToEMA = (high1 >= ema20 * 0.999 && 
                                close1 < ema20 && 
                                close1 < close2);
         
         // Confirmación de volumen
         long vol1 = iVolume(_Symbol, PERIOD_CURRENT, 1);
         long avgVol = 0;
         for(int i = 2; i <= 11; i++)
            avgVol += iVolume(_Symbol, PERIOD_CURRENT, i);
         avgVol /= 10;
         
         bool volumeConfirmation = (vol1 > avgVol * 1.1);
         
         // SEÑAL BAJISTA si hay patrón + volumen
         if((isPinBar || isEngulfing || isPullbackToEMA) && volumeConfirmation)
         {
            Print("▼ SEÑAL BAJISTA detectada | Patrón: ", 
                  isPinBar ? "PinBar" : (isEngulfing ? "Engulfing" : "Pullback"));
            return -1;
         }
      }
   }
   
   return 0; // Sin señal
}

//+------------------------------------------------------------------+
void ExecuteBuySignal()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL y TP fijos en pips
   double sl = ask - InpStopLossPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   // Calcular lote basado en riesgo
   double lots = CalculatePositionSize(InpStopLossPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote calculado muy pequeño: ", lots);
      return;
   }
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "APEX_BUY"))
   {
      tradesThisDay++;
      Print("═══════════════════════════════════════════");
      Print("  ✓ COMPRA EJECUTADA");
      Print("  Precio: ", ask);
      Print("  SL: ", sl, " (", InpStopLossPips, " pips)");
      Print("  TP: ", tp, " (", InpTakeProfitPips, " pips)");
      Print("  Lote: ", lots);
      Print("  Riesgo: ", InpRiskPercent, "%");
      Print("  Operación ", tradesThisDay, " de ", InpMaxTradesPerDay, " hoy");
      Print("═══════════════════════════════════════════");
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL y TP fijos en pips
   double sl = bid + InpStopLossPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   // Calcular lote basado en riesgo
   double lots = CalculatePositionSize(InpStopLossPips * 10 * point);
   
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("⊗ Lote calculado muy pequeño: ", lots);
      return;
   }
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "APEX_SELL"))
   {
      tradesThisDay++;
      Print("═══════════════════════════════════════════");
      Print("  ✓ VENTA EJECUTADA");
      Print("  Precio: ", bid);
      Print("  SL: ", sl, " (", InpStopLossPips, " pips)");
      Print("  TP: ", tp, " (", InpTakeProfitPips, " pips)");
      Print("  Lote: ", lots);
      Print("  Riesgo: ", InpRiskPercent, "%");
      Print("  Operación ", tradesThisDay, " de ", InpMaxTradesPerDay, " hoy");
      Print("═══════════════════════════════════════════");
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
   
   // Normalizar lote
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
      double atr = CalculateATR(14);
      
      // Trailing stop cuando la operación está en profit > 1.5 ATR
      if(profit > atr * 1.5)
      {
         double newSL;
         if(isBuy)
         {
            newSL = currentPrice - atr * 0.8;
            if(newSL > currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("► Trailing Stop actualizado (BUY): ", newSL);
            }
         }
         else
         {
            newSL = currentPrice + atr * 0.8;
            if(currentSL == 0 || newSL < currentSL)
            {
               trade.PositionModify(ticket, newSL, currentTP);
               Print("▼ Trailing Stop actualizado (SELL): ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
double FindSwingLow(int bars)
{
   double lowest = 999999;
   
   for(int i = 3; i <= bars; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      // Verificar que sea un mínimo local
      for(int j = i - 2; j <= i + 2; j++)
      {
         if(j == i || j < 1) continue;
         if(iLow(_Symbol, PERIOD_CURRENT, j) < low)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && low < lowest)
         lowest = low;
   }
   
   return lowest;
}

//+------------------------------------------------------------------+
double FindSwingHigh(int bars)
{
   double highest = 0;
   
   for(int i = 3; i <= bars; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      bool isSwing = true;
      
      // Verificar que sea un máximo local
      for(int j = i - 2; j <= i + 2; j++)
      {
         if(j == i || j < 1) continue;
         if(iHigh(_Symbol, PERIOD_CURRENT, j) > high)
         {
            isSwing = false;
            break;
         }
      }
      
      if(isSwing && high > highest)
         highest = high;
   }
   
   return highest;
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
