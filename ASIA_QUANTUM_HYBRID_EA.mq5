//+------------------------------------------------------------------+
//|                          ASIA_QUANTUM_HYBRID_EA.mq5              |
//|           HÍBRIDO: Asia Breakout + Quantum Master               |
//|           Lo Mejor de Ambos Mundos                              |
//+------------------------------------------------------------------+
#property copyright "Asia Quantum Hybrid - Best of Both"
#property version   "1.00"

#include <Trade\Trade.mqh>

// ═══════════════════════════════════════════════════════════════════
// CONFIGURACIÓN BASE
// ═══════════════════════════════════════════════════════════════════
input group "═══ CONFIGURACIÓN BASE ═══"
input double InpRiskPercent = 0.50;          // Riesgo por trade
input int    InpStopLossPips = 25;           // Stop Loss base pips
input int    InpTakeProfitPips = 50;         // Take Profit pips
input int    InpMagicNumber = 888888;        // Magic number

// ═══════════════════════════════════════════════════════════════════
// RANGO ASIÁTICO (De Asia Breakout - CORREGIDO)
// ═══════════════════════════════════════════════════════════════════
input group "═══ RANGO ASIÁTICO ═══"
input int    InpAsiaStartHour = 0;           // Inicio rango (GMT)
input int    InpAsiaEndHour = 4;             // Fin rango (4 horas, no 8)
input double InpBreakoutOffsetPercent = 0.08;// Offset proporcional (8%)
input int    InpMinRangeSize = 30;           // Rango mínimo pips
input int    InpMaxRangeSize = 100;          // Rango máximo pips

// ═══════════════════════════════════════════════════════════════════
// FILTROS QUANTUM (Lo que funciona)
// ═══════════════════════════════════════════════════════════════════
input group "═══ FILTROS INTELIGENTES ═══"
input bool   InpUseConfluenceScoring = true; // Scoring por confluencia
input int    InpMinConfluenceFactors = 3;    // Factores mínimos (de 10)
input double InpMinADX = 12.0;               // ADX mínimo
input double InpMinVolatility = 0.5;         // Volatilidad mínima
input double InpMaxVolatility = 3.0;         // Volatilidad máxima
input double InpMinOrderFlowBuy = 1.1;       // Order flow compra
input double InpMaxOrderFlowSell = 0.9;      // Order flow venta
input bool   InpUseCorrelationFilter = true; // Filtro correlación
input int    InpMinMinutesBetweenTrades = 15;// Minutos entre trades

// ═══════════════════════════════════════════════════════════════════
// PROTECCIONES (De Quantum)
// ═══════════════════════════════════════════════════════════════════
input group "═══ PROTECCIONES ═══"
input int    InpMaxTradesPerDay = 15;        // Max trades/día
input int    InpMaxConsecutiveLosses = 3;    // Pausar después de N
input double InpMaxDailyLossPercent = 3.0;   // Pérdida máxima diaria %
input double InpMaxDrawdownPercent = 18.0;   // Drawdown máximo %

// ═══════════════════════════════════════════════════════════════════
// TRAILING AKALI (De Quantum - 3 niveles)
// ═══════════════════════════════════════════════════════════════════
input group "═══ TRAILING AKALI ═══"
input bool   InpUseAkaliTrailing = true;     // Usar trailing Akali
input int    InpAkaliLevel1 = 15;            // Nivel 1: Breakeven
input int    InpAkaliLevel2 = 25;            // Nivel 2: Asegurar ganancia
input int    InpAkaliLevel3 = 35;            // Nivel 3: Trailing estructura

// ═══════════════════════════════════════════════════════════════════
// SALIDAS INTELIGENTES (De Quantum)
// ═══════════════════════════════════════════════════════════════════
input group "═══ SALIDAS INTELIGENTES ═══"
input bool   InpUseSmartExit = true;         // Salidas inteligentes
input int    InpMaxHoursInTrade = 4;         // Máx horas sin progreso
input bool   InpUsePartialProfits = true;    // Toma parcial

// ═══════════════════════════════════════════════════════════════════
// RIESGO ADAPTATIVO (De Quantum)
// ═══════════════════════════════════════════════════════════════════
input group "═══ RIESGO ADAPTATIVO ═══"
input bool   InpUseAdaptiveRisk = true;      // Riesgo adaptativo
input bool   InpUseDynamicSL = true;         // Stop Loss dinámico
input double InpSLMultiplier = 1.8;          // Multiplicador SL (ATR)

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
double peakBalance = 0;
int consecutiveLosses = 0;
datetime pauseUntil = 0;
int totalWins = 0;
int totalLosses = 0;

// Para filtro de correlación
datetime lastTradeTime = 0;
string lastSignalType = "";
int lastDirection = 0;

// Para toma parcial
bool tp1Taken = false;
bool tp2Taken = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   asiaRange.isValid = false;
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   peakBalance = dailyStartBalance;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA QUANTUM HYBRID v1.00                               ║");
   Print("╠═══════════════════════════════════════════════════════════╣");
   Print("║  🎯 ESTRATEGIA: Asia Breakout + Quantum Filters         ║");
   Print("║  Rango: ", InpAsiaStartHour, ":00-", InpAsiaEndHour, ":00 (", InpAsiaEndHour-InpAsiaStartHour, "h) | Offset: ", DoubleToString(InpBreakoutOffsetPercent*100,0), "%              ║");
   Print("║  Confluence: ", InpMinConfluenceFactors, "/10 | ADX: ≥", DoubleToString(InpMinADX,1), " | Vol: ", DoubleToString(InpMinVolatility,1), "-", DoubleToString(InpMaxVolatility,1), "   ║");
   Print("║  Max: ", InpMaxTradesPerDay, "/día | Trailing: Akali 3 niveles            ║");
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
   
   if(!PassAllProtections()) return;
   
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
      tp1Taken = false;
      tp2Taken = false;
   }
}

//+------------------------------------------------------------------+
bool PassAllProtections()
{
   // Protección 1: Max trades
   if(tradesThisDay >= InpMaxTradesPerDay) return false;
   
   // Protección 2: Pausa después de pérdidas
   if(TimeCurrent() < pauseUntil) return false;
   
   // Protección 3: Pérdida diaria
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = (dailyStartBalance - currentBalance) / dailyStartBalance * 100;
   if(dailyLoss > InpMaxDailyLossPercent) return false;
   
   // Protección 4: Drawdown
   if(currentBalance > peakBalance) peakBalance = currentBalance;
   double dd = (peakBalance - currentBalance) / peakBalance * 100;
   if(dd > InpMaxDrawdownPercent) return false;
   
   // Protección 5: Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(spread > 50) return false;
   
   // Protección 6: Solo sesiones Londres/NY
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hourGMT = timeStruct.hour;
   bool isLondon = (hourGMT >= 8 && hourGMT < 12);
   bool isNY = (hourGMT >= 13 && hourGMT < 17);
   if(!isLondon && !isNY) return false;
   
   // Protección 7: No operar viernes tarde
   if(timeStruct.day_of_week == 5 && hourGMT >= 15) return false;
   
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
      if(asiaRange.range >= InpMinRangeSize && asiaRange.range <= InpMaxRangeSize)
      {
         asiaRange.isValid = true;
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         
         // Offset proporcional (no fijo)
         double offset = asiaRange.range * InpBreakoutOffsetPercent * 10 * point;
         
         asiaRange.buyTrigger = asiaRange.high + offset;
         asiaRange.sellTrigger = asiaRange.low - offset;
         asiaRange.buyTriggerHit = false;
         asiaRange.sellTriggerHit = false;
         
         Print(StringFormat("✓ RANGO ASIA: %.1f pips | Offset: %.1f pips", 
                           asiaRange.range, offset / (10 * point)));
      }
   }
}

//+------------------------------------------------------------------+
void CheckBreakoutSignals()
{
   if(!asiaRange.isValid) return;
   
   // Validar vela ACTUAL (índice 0, no 1)
   double currentPrice = iClose(_Symbol, PERIOD_M5, 0);
   
   if(!asiaRange.buyTriggerHit && currentPrice > asiaRange.buyTrigger)
   {
      if(ValidateEntry(true))
      {
         ExecuteBuySignal();
         asiaRange.buyTriggerHit = true;
      }
   }
   
   if(!asiaRange.sellTriggerHit && currentPrice < asiaRange.sellTrigger)
   {
      if(ValidateEntry(false))
      {
         ExecuteSellSignal();
         asiaRange.sellTriggerHit = true;
      }
   }
}

//+------------------------------------------------------------------+
bool ValidateEntry(bool isBuySignal)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // CRÍTICO: Validar vela ACTUAL (índice 0)
   double open0 = iOpen(_Symbol, PERIOD_M5, 0);
   double close0 = iClose(_Symbol, PERIOD_M5, 0);
   double high0 = iHigh(_Symbol, PERIOD_M5, 0);
   double low0 = iLow(_Symbol, PERIOD_M5, 0);
   
   double body = MathAbs(close0 - open0);
   double range = high0 - low0;
   
   // Validar dirección de vela
   if(isBuySignal && close0 <= open0) return false;
   if(!isBuySignal && close0 >= open0) return false;
   
   // Validar impulso (65%)
   if(range == 0) return false;
   double bodyPercent = body / range;
   if(bodyPercent < 0.65) return false;
   
   // Validar tamaño mínimo (10 pips)
   double candleSizePips = range / (10 * point);
   if(candleSizePips < 10) return false;
   
   // FILTROS QUANTUM
   if(!PassMarketRegimeFilter()) return false;
   if(!PassOrderFlowFilter(isBuySignal ? 1 : -1)) return false;
   if(!PassCorrelationFilter(isBuySignal ? 1 : -1)) return false;
   
   // CONFLUENCE SCORING
   if(InpUseConfluenceScoring)
   {
      int confluenceScore = CalculateConfluenceScore(isBuySignal);
      
      int minRequired = InpMinConfluenceFactors;
      if(consecutiveLosses >= 2) minRequired++;
      
      if(confluenceScore < minRequired)
      {
         Print(StringFormat("⊗ CONFLUENCIA: %d/%d (mín: %d)", confluenceScore, 10, minRequired));
         return false;
      }
      
      Print(StringFormat("✅ CONFLUENCIA: %d/10 factores", confluenceScore));
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassMarketRegimeFilter()
{
   // ADX mínimo
   double adx = CalculateADX(14);
   if(adx < InpMinADX)
   {
      Print(StringFormat("⊗ ADX bajo: %.1f (mín: %.1f)", adx, InpMinADX));
      return false;
   }
   
   // Volatilidad
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateAvgATR(24);
   double volatilityRatio = atr / avgATR;
   
   if(volatilityRatio < InpMinVolatility || volatilityRatio > InpMaxVolatility)
   {
      Print(StringFormat("⊗ Volatilidad: %.2fx (rango: %.1f-%.1f)", 
            volatilityRatio, InpMinVolatility, InpMaxVolatility));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassOrderFlowFilter(int direction)
{
   double imbalance = CalculateOrderFlowImbalance(10);
   
   if(direction > 0 && imbalance < InpMinOrderFlowBuy)
   {
      Print(StringFormat("⊗ Order Flow compra: %.2f (mín: %.2f)", imbalance, InpMinOrderFlowBuy));
      return false;
   }
   
   if(direction < 0 && imbalance > InpMaxOrderFlowSell)
   {
      Print(StringFormat("⊗ Order Flow venta: %.2f (máx: %.2f)", imbalance, InpMaxOrderFlowSell));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool PassCorrelationFilter(int direction)
{
   if(!InpUseCorrelationFilter) return true;
   
   // Evitar trades muy seguidos en misma dirección
   int minutesSinceLastTrade = (int)((TimeCurrent() - lastTradeTime) / 60);
   
   if(minutesSinceLastTrade < InpMinMinutesBetweenTrades && lastDirection == direction)
   {
      Print(StringFormat("⊗ Correlación: Solo %d min desde último trade", minutesSinceLastTrade));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
int CalculateConfluenceScore(bool isBuySignal)
{
   int score = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Factor 1: Impulso fuerte (>70%)
   double open0 = iOpen(_Symbol, PERIOD_M5, 0);
   double close0 = iClose(_Symbol, PERIOD_M5, 0);
   double high0 = iHigh(_Symbol, PERIOD_M5, 0);
   double low0 = iLow(_Symbol, PERIOD_M5, 0);
   double body = MathAbs(close0 - open0);
   double range = high0 - low0;
   if(range > 0 && body / range > 0.70) score++;
   
   // Factor 2: Vela grande (>15 pips)
   if(range / (10 * point) > 15) score++;
   
   // Factor 3: ADX fuerte (>20)
   double adx = CalculateADX(14);
   if(adx > 20) score++;
   
   // Factor 4: Volatilidad óptima (1.0-2.0x)
   double atr = CalculateATR(14, PERIOD_M5);
   double avgATR = CalculateAvgATR(24);
   double volRatio = atr / avgATR;
   if(volRatio >= 1.0 && volRatio <= 2.0) score++;
   
   // Factor 5: Order flow fuerte
   double imbalance = CalculateOrderFlowImbalance(10);
   if(isBuySignal && imbalance > 1.3) score++;
   if(!isBuySignal && imbalance < 0.7) score++;
   
   // Factor 6: Rango asiático óptimo (40-80 pips)
   if(asiaRange.range >= 40 && asiaRange.range <= 80) score++;
   
   // Factor 7: Hora óptima (Londres o NY apertura)
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int hour = timeStruct.hour;
   if((hour >= 8 && hour <= 10) || (hour >= 13 && hour <= 15)) score++;
   
   // Factor 8: Tendencia M15 alineada
   if(IsTrendAligned(isBuySignal)) score++;
   
   // Factor 9: Sin pérdidas recientes
   if(consecutiveLosses == 0) score++;
   
   // Factor 10: Spread bajo (<20 pips)
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / point;
   if(spread < 20) score++;
   
   return score;
}

//+------------------------------------------------------------------+
bool IsTrendAligned(bool isBuySignal)
{
   double closes[];
   ArraySetAsSeries(closes, true);
   
   if(CopyClose(_Symbol, PERIOD_M15, 0, 20, closes) < 20) return true;
   
   int bullish = 0, bearish = 0;
   for(int i = 1; i < 20; i++)
   {
      if(closes[i-1] > closes[i]) bullish++;
      else bearish++;
   }
   
   double trendStrength = (double)MathMax(bullish, bearish) / 19.0;
   bool isBullish = (bullish > bearish);
   
   // Rechazar si contra tendencia fuerte
   if(isBuySignal && !isBullish && trendStrength > 0.65) return false;
   if(!isBuySignal && isBullish && trendStrength > 0.65) return false;
   
   return true;
}

//+------------------------------------------------------------------+
void ExecuteBuySignal()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // SL dinámico o fijo
   double slPips = InpUseDynamicSL ? CalculateDynamicSL() : InpStopLossPips;
   double sl = ask - slPips * 10 * point;
   double tp = ask + InpTakeProfitPips * 10 * point;
   
   // Riesgo adaptativo
   double lots = CalculatePositionSize(slPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Buy(lots, _Symbol, ask, sl, tp, "ASIA_QUANTUM_BUY"))
   {
      tradesThisDay++;
      lastTradeTime = TimeCurrent();
      lastDirection = 1;
      tp1Taken = false;
      tp2Taken = false;
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ COMPRA ASIA QUANTUM                                   ║");
      Print(StringFormat("║  Entry: %s | SL: %.1f | TP: %d | Lote: %.2f      ║", 
            DoubleToString(ask, _Digits), slPips, InpTakeProfitPips, lots));
      Print(StringFormat("║  Trade %d/%d hoy                                         ║", 
            tradesThisDay, InpMaxTradesPerDay));
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
void ExecuteSellSignal()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double slPips = InpUseDynamicSL ? CalculateDynamicSL() : InpStopLossPips;
   double sl = bid + slPips * 10 * point;
   double tp = bid - InpTakeProfitPips * 10 * point;
   
   double lots = CalculatePositionSize(slPips * 10 * point);
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   if(trade.Sell(lots, _Symbol, bid, sl, tp, "ASIA_QUANTUM_SELL"))
   {
      tradesThisDay++;
      lastTradeTime = TimeCurrent();
      lastDirection = -1;
      tp1Taken = false;
      tp2Taken = false;
      
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║  ✓ VENTA ASIA QUANTUM                                    ║");
      Print(StringFormat("║  Entry: %s | SL: %.1f | TP: %d | Lote: %.2f      ║", 
            DoubleToString(bid, _Digits), slPips, InpTakeProfitPips, lots));
      Print(StringFormat("║  Trade %d/%d hoy                                         ║", 
            tradesThisDay, InpMaxTradesPerDay));
      Print("╚═══════════════════════════════════════════════════════════╝");
   }
}

//+------------------------------------------------------------------+
double CalculatePositionSize(double slDistance)
{
   double riskMultiplier = 1.0;
   
   // Riesgo adaptativo: reducir después de pérdidas
   if(InpUseAdaptiveRisk)
   {
      if(consecutiveLosses >= 2) riskMultiplier = 0.5;
      else if(consecutiveLosses == 1) riskMultiplier = 0.75;
      else if(totalWins > totalLosses && totalWins > 5) riskMultiplier = 1.2;
   }
   
   double adjustedRisk = InpRiskPercent * riskMultiplier;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * adjustedRisk / 100.0;
   
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
double CalculateDynamicSL()
{
   double atr = CalculateATR(14, PERIOD_M5);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPips = (atr * InpSLMultiplier) / (10 * point);
   
   // Limitar entre 15-40 pips
   slPips = MathMax(15, MathMin(40, slPips));
   
   return slPips;
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   UpdateTradeStatistics();
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double profit = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double profitPips = profit / (10 * point);
      
      // TOMA PARCIAL
      if(InpUsePartialProfits)
      {
         ManagePartialProfits(ticket, isBuy, profitPips);
      }
      
      // SALIDAS INTELIGENTES
      if(InpUseSmartExit)
      {
         ApplySmartExit(ticket, isBuy, openTime, profitPips);
      }
      
      // TRAILING AKALI
      if(InpUseAkaliTrailing)
      {
         AkaliTrailingStop(ticket, isBuy, openPrice, currentPrice, currentSL, currentTP, profitPips, point);
      }
   }
}

//+------------------------------------------------------------------+
void ManagePartialProfits(ulong ticket, bool isBuy, double profitPips)
{
   double positionVolume = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   // TP1: 50% en +25 pips
   if(!tp1Taken && profitPips >= 25 && positionVolume >= minLot * 2)
   {
      double closeVolume = MathFloor(positionVolume / 2 / minLot) * minLot;
      if(closeVolume >= minLot)
      {
         if(trade.PositionClosePartial(ticket, closeVolume))
         {
            tp1Taken = true;
            Print(StringFormat("✓ TP1: 50%% cerrado en +%.1f pips", profitPips));
         }
      }
   }
   
   // TP2: 25% adicional en +40 pips
   if(tp1Taken && !tp2Taken && profitPips >= 40 && positionVolume >= minLot * 2)
   {
      double closeVolume = MathFloor(positionVolume / 2 / minLot) * minLot;
      if(closeVolume >= minLot)
      {
         if(trade.PositionClosePartial(ticket, closeVolume))
         {
            tp2Taken = true;
            Print(StringFormat("✓ TP2: 25%% cerrado en +%.1f pips", profitPips));
         }
      }
   }
}

//+------------------------------------------------------------------+
void ApplySmartExit(ulong ticket, bool isBuy, datetime openTime, double profitPips)
{
   int hoursInTrade = (int)((TimeCurrent() - openTime) / 3600);
   
   // Cerrar si lleva mucho tiempo sin alcanzar 50% del TP
   if(hoursInTrade >= InpMaxHoursInTrade && profitPips < InpTakeProfitPips * 0.5)
   {
      trade.PositionClose(ticket);
      Print(StringFormat("⚠ SMART EXIT: %d horas sin progreso (%.1f pips)", hoursInTrade, profitPips));
      return;
   }
   
   // Cerrar si vela opuesta fuerte en ganancia
   if(profitPips > 10)
   {
      double open0 = iOpen(_Symbol, PERIOD_M5, 0);
      double close0 = iClose(_Symbol, PERIOD_M5, 0);
      double high0 = iHigh(_Symbol, PERIOD_M5, 0);
      double low0 = iLow(_Symbol, PERIOD_M5, 0);
      double range = high0 - low0;
      double body = MathAbs(close0 - open0);
      
      if(range > 0 && body / range > 0.70)
      {
         if(isBuy && close0 < open0)
         {
            trade.PositionClose(ticket);
            Print(StringFormat("⚠ SMART EXIT: Vela bajista fuerte (%.1f pips)", profitPips));
            return;
         }
         if(!isBuy && close0 > open0)
         {
            trade.PositionClose(ticket);
            Print(StringFormat("⚠ SMART EXIT: Vela alcista fuerte (%.1f pips)", profitPips));
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
void AkaliTrailingStop(ulong ticket, bool isBuy, double openPrice, double currentPrice, 
                       double currentSL, double currentTP, double profitPips, double point)
{
   // NIVEL 1: Breakeven en +15 pips
   if(profitPips >= InpAkaliLevel1)
   {
      double breakeven = openPrice + (isBuy ? 5 : -5) * 10 * point;
      
      if(isBuy && breakeven > currentSL)
      {
         trade.PositionModify(ticket, breakeven, currentTP);
         Print(StringFormat("► Akali L1: BE +5 pips (profit: %.1f)", profitPips));
         return;
      }
      else if(!isBuy && (currentSL == 0 || breakeven < currentSL))
      {
         trade.PositionModify(ticket, breakeven, currentTP);
         Print(StringFormat("▼ Akali L1: BE +5 pips (profit: %.1f)", profitPips));
         return;
      }
   }
   
   // NIVEL 2: Asegurar +10 pips en +25 pips
   if(profitPips >= InpAkaliLevel2)
   {
      double secureSL = openPrice + (isBuy ? 10 : -10) * 10 * point;
      
      if(isBuy && secureSL > currentSL)
      {
         trade.PositionModify(ticket, secureSL, currentTP);
         Print(StringFormat("► Akali L2: SL +10 pips (profit: %.1f)", profitPips));
         return;
      }
      else if(!isBuy && (currentSL == 0 || secureSL < currentSL))
      {
         trade.PositionModify(ticket, secureSL, currentTP);
         Print(StringFormat("▼ Akali L2: SL +10 pips (profit: %.1f)", profitPips));
         return;
      }
   }
   
   // NIVEL 3: Trailing dinámico en +35 pips
   if(profitPips >= InpAkaliLevel3)
   {
      double trailDistance = 15 * 10 * point;
      double newSL;
      
      if(isBuy)
      {
         newSL = currentPrice - trailDistance;
         if(newSL > currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print(StringFormat("► Akali L3: Trailing -15 pips (profit: %.1f)", profitPips));
         }
      }
      else
      {
         newSL = currentPrice + trailDistance;
         if(currentSL == 0 || newSL < currentSL)
         {
            trade.PositionModify(ticket, newSL, currentTP);
            Print(StringFormat("▼ Akali L3: Trailing +15 pips (profit: %.1f)", profitPips));
         }
      }
   }
}

//+------------------------------------------------------------------+
void UpdateTradeStatistics()
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
               Print(StringFormat("✓ WIN | %dW-%dL | WR: %.1f%%", 
                     totalWins, totalLosses, (double)totalWins/(totalWins+totalLosses)*100));
            }
            else if(profit < 0)
            {
               totalLosses++;
               consecutiveLosses++;
               
               if(consecutiveLosses >= InpMaxConsecutiveLosses)
               {
                  pauseUntil = TimeCurrent() + 3600;
                  Print(StringFormat("⚠ PAUSA: %d pérdidas | Hasta: %s", 
                        consecutiveLosses, TimeToString(pauseUntil)));
                  consecutiveLosses = 0;
               }
               
               Print(StringFormat("✗ LOSS | %dW-%dL | Consecutive: %d", 
                     totalWins, totalLosses, consecutiveLosses));
            }
            
            lastProcessedTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
// FUNCIONES AUXILIARES
//+------------------------------------------------------------------+
double CalculateATR(int period, ENUM_TIMEFRAMES tf)
{
   double atr = 0;
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(_Symbol, tf, i);
      double low = iLow(_Symbol, tf, i);
      double prevClose = iClose(_Symbol, tf, i + 1);
      double tr = MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
      atr += tr;
   }
   return atr / period;
}

double CalculateAvgATR(int hours)
{
   double sum = 0;
   for(int i = 1; i <= hours; i++)
   {
      double high = iHigh(_Symbol, PERIOD_H1, i);
      double low = iLow(_Symbol, PERIOD_H1, i);
      sum += (high - low);
   }
   return sum / hours;
}

double CalculateADX(int period)
{
   double plusDM = 0, minusDM = 0, tr = 0;
   
   for(int i = 1; i <= period; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      double prevHigh = iHigh(_Symbol, PERIOD_M5, i + 1);
      double prevLow = iLow(_Symbol, PERIOD_M5, i + 1);
      double prevClose = iClose(_Symbol, PERIOD_M5, i + 1);
      
      double highDiff = high - prevHigh;
      double lowDiff = prevLow - low;
      
      if(highDiff > lowDiff && highDiff > 0) plusDM += highDiff;
      if(lowDiff > highDiff && lowDiff > 0) minusDM += lowDiff;
      
      tr += MathMax(high - low, MathMax(MathAbs(high - prevClose), MathAbs(low - prevClose)));
   }
   
   if(tr == 0) return 0;
   
   double plusDI = (plusDM / tr) * 100;
   double minusDI = (minusDM / tr) * 100;
   double diDiff = MathAbs(plusDI - minusDI);
   double diSum = plusDI + minusDI;
   
   if(diSum == 0) return 0;
   
   return (diDiff / diSum) * 100;
}

double CalculateOrderFlowImbalance(int bars)
{
   long buyVolume = 0, sellVolume = 0;
   
   for(int i = 1; i <= bars; i++)
   {
      double open = iOpen(_Symbol, PERIOD_M5, i);
      double close = iClose(_Symbol, PERIOD_M5, i);
      long volume = iVolume(_Symbol, PERIOD_M5, i);
      
      if(close > open) buyVolume += volume;
      else sellVolume += volume;
   }
   
   if(sellVolume == 0) return 2.0;
   return (double)buyVolume / sellVolume;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   double winRate = (totalWins + totalLosses > 0) ? (double)totalWins / (totalWins + totalLosses) * 100 : 0;
   
   Print("╔═══════════════════════════════════════════════════════════╗");
   Print("║  ASIA QUANTUM HYBRID - Detenido                          ║");
   Print(StringFormat("║  Trades: %dW-%dL | WR: %.1f%%                           ║", 
         totalWins, totalLosses, winRate));
   Print(StringFormat("║  Trades hoy: %d                                          ║", tradesThisDay));
   Print("╚═══════════════════════════════════════════════════════════╝");
}
//+------------------------------------------------------------------+
