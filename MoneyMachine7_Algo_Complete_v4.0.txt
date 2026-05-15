//+------------------------------------------------------------------+
//|  MoneyMachine7_Algo_Complete_v4.4.mq5                           |
//|  Versión 4.4 – Algoritmo puro, Dashboard, Sin dependencias.    |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7_Complete"
#property version   "4.04"
#property strict
#property indicator_chart_window
#property indicator_buffers 0

//===================================================================
//===  INCLUDES – SOLO LOS ESTÁNDAR DE MT5                           ===
//===================================================================
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

//===================================================================
//===  INPUTS – CONFIGURABLES EN MT5                               ===
//===================================================================

//--- Configuración general -------------------------------------------
input group "=== CONFIGURACIÓN GENERAL ==="
input int    MagicNumber                = 400000;      // Magic Number
input int    SlippagePoints             = 5;           // Slippage (puntos)
input bool   EnableLogging              = true;        // Mensajes en el log
input bool   EnableAlerts               = true;        // Alertas sonoras
input string AlertSound                 = "alert.wav"; // Sonido de alerta
input bool   ForceTrade                 = false;       // SOLO PRUEBAS: abre trade sin filtros
input bool   DebugMode                  = true;        // Visualiza valores en log y Dashboard

//--- Algoritmos de decisión -----------------------------------------
input group "=== ALGORITMOS DE DECISIÓN ==="
input int    StructureLookback          = 12;          // Barras para detectar estructura
input double MinStructureStrength       = 0.5;         // Umbral de fuerza estructural (más blando)
input int    MomentumBars               = 6;           // Barras usadas para momentum
input double MinMomentumStrength        = 0.3;         // Umbral de calidad del momentum
input int    RangeBars                  = 20;          // Barras para rango base
input double RangeThreshold             = 0.12;        // % del rango que define zona de reversión
input int    ConfirmationBars           = 2;           // Barras de confirmación
input double ConfirmPoints              = 1.0;         // Puntos de confirmación del precio

//--- Gestión de riesgo -----------------------------------------------
input group "=== GESTIÓN DE RIESGO ==="
input double BaseRiskPercent            = 1.5;         // % riesgo base por trade
input double MaxRiskPercent             = 4.0;         // % riesgo máximo permitido
input double MinLotSize                 = 0.01;        // Lote mínimo
input double MaxLotSize                 = 5.0;         // Lote máximo
input bool   UseDynamicSizing           = true;        // Tamaño de lote dinámico
input bool   UseATRBasedSL              = true;        // SL basado en ATR
input int    ATRPeriod                  = 14;          // Período ATR
input double ATRMultiplier              = 2.0;         // Multiplicador ATR para SL

//--- Configuración de sesiones ---------------------------------------
input group "=== CONFIGURACIÓN DE SESIONES ==="
input bool   EnableAsiaSession          = true;        // Activar sesión Asia (Tokyo)
input int    AsiaStartHour              = 0;           // Hora inicio (UTC)
input int    AsiaEndHour                = 9;           // Hora fin (UTC)
input double AsiaRiskMultiplier         = 1.0;         // Multiplicador riesgo Asia

input bool   EnableEuropeSession        = true;        // Activar sesión Europa (London)
input int    EuropeStartHour            = 8;
input int    EuropeEndHour              = 17;
input double EuropeRiskMultiplier       = 1.2;

input bool   EnableUSSession            = true;        // Activar sesión EE.UU. (New York)
input int    USStartHour                = 13;
input int    USEndHour                  = 22;
input double USRiskMultiplier           = 1.5;

input bool   UseCustomHours             = false;       // Horarios personalizados
input string CustomHours                = "09:00-11:00,14:00-16:00"; // HH:MM‑HH:MM,...
input double CustomRiskMultiplier       = 1.0;

//--- Control de rendimiento -----------------------------------------
input group "=== CONTROL DE RENDIMIENTO ==="
input int    MaxConsecutiveLosses       = 3;           // Máx pérdidas consecutivas
input int    CooldownBars               = 6;           // Barras de pausa tras racha
input double MaxDailyLossPercent        = 6.0;         // % pérdida diaria máxima
input double MaxDrawdownPercent         = 10.0;        // % draw‑down máximo
input bool   UseCorrelationFilter       = true;        // Filtrar por correlación con majors
input double CorrelationThreshold       = 0.7;

//--- Dashboard & visualización ---------------------------------------
input group "=== DASHBOARD & VISUALIZACIÓN ==="
input bool   ShowDashboard              = true;        // Mostrar panel
input bool   ShowAlgoInfo               = true;        // Mostrar info algoritmo
input bool   ShowTradeZones              = true;        // Dibujar zonas de trading
input bool   ShowPerformance            = true;        // Mostrar estadísticas
input int    DashboardX                 = 10;          // Posición X del panel
input int    DashboardY                 = 50;          // Posición Y del panel
input color  DashboardColor             = clrWhite;    // Color texto panel
input color  BullColor                  = clrLime;    // Color alcista
input color  BearColor                  = clrRed;     // Color bajista
input color  NeutralColor               = clrGray;    // Color neutro

//--- Gestión de salidas ---------------------------------------------
input group "=== GESTIÓN DE SALIDAS ==="
input bool   UseSmartExit               = true;        // Salida inteligente (breakeven)
input bool   UsePartialExit             = true;        // Salida parcial
input double PartialExitTrigger         = 30.0;        // % beneficio para salida parcial
input double PartialExitPercent         = 50.0;        // % del volumen que se cierra
input bool   UseTrailingStop            = true;        // Trailing dinámico
input double TrailingActivation         = 25.0;        // % beneficio necesario para activar trailing
input double TrailingDistance           = 15.0;        // Distancia (pips) del trailing

//--- Filtros avanzados -----------------------------------------------
input group "=== FILTROS AVANZADOS ==="
input bool   UseVolatilityFilter        = true;        // Filtrar cuando volatilidad sea baja
input double VolatilityThreshold        = 0.5;         // Umbral (pips) de volatilidad mínima
input bool   UseNewsFilter              = true;        // Evitar operar cerca de noticias
input int    NewsAvoidMinutes           = 30;          // Minutos antes / después de noticia
input bool   UseCorrelationWithMajors   = true;        // Filtrar si está muy correlado con majors
input double CorrelationThresholdNews   = 0.7;         // Umbral de correlación para bloquear

//--- Umbral de calidad mínima (ajústalo a tu gusto) ----------------
input double SignalQualityThreshold     = 30.0;        // % (antes 70)

//===================================================================
//===  VARIABLES GLOBALES                                            ===
//===================================================================
CTrade   trade;                     // objeto para enviar órdenes
string   g_symbol;
double   g_point;
datetime g_lastBarTime = 0;
int      g_magic;

//--- Estado del algoritmo -------------------------------------------
enum MARKET_STATE
{
   STATE_NEUTRAL   = 0,
   STATE_BULLISH   = 1,
   STATE_BEARISH   = -1,
   STATE_RANGING   = 2,
   STATE_BREAKOUT  = -2
};

MARKET_STATE g_currentMarketState = STATE_NEUTRAL;
double       g_signalQuality      = 0.0;   // 0‑100 (última señal evaluada)
bool         g_highQualitySignal = false;
double       g_atrValue          = 0.0;   // ATR (pips)
double       g_currentVolatility = 0.0;   // Volatilidad 10‑barras (pips)

//--- Performance ----------------------------------------------------
struct PerformanceData
{
   double totalTrades;
   double winningTrades;
   double losingTrades;
   double totalProfit;
   double maxDrawdown;
   double currentDrawdown;
   double winRate;
   double profitFactor;
   double dailyPnL;
   double weeklyPnL;
   double monthlyPnL;
   datetime lastTradeTime;
};
PerformanceData g_perf;   // inicializado a 0 automáticamente

//--- Estado de la posición -----------------------------------------
struct TradeState
{
   bool   isOpen;
   int    direction;        // +1 BUY, -1 SELL
   double entryPrice;
   double stopLoss;
   double takeProfit;
   datetime openTime;
   bool   partialClosed;
   bool   trailingActive;
   double trailLevel;
   double unrealizedPnL;
};
TradeState g_trade;

//--- Pausa por racha -----------------------------------------------
int g_pauseBarsLeft = 0;

//--- Prefixes para objetos gráficos --------------------------------
string g_prefixDashboard = "MM7_Dash_";
string g_prefixAlgoInfo   = "MM7_Algo_";
string g_prefixTradeZone  = "MM7_Zone_";
string g_prefixPerf      = "MM7_Perf_";

//===================================================================
//===  FUNÇÕES DE AJUDA                                            ===
//===================================================================

//--- Convierte "HH:MM" a minutos desde medianoche --------------------
int TimeStrToMinutes(string s)
{
   int colon = StringFind(s, ":");
   if(colon < 0) return -1;
   int h = (int)StringToInteger(StringSubstr(s, 0, colon));
   int m = (int)StringToInteger(StringSubstr(s, colon + 1));
   return h * 60 + m;
}

//--- Verifica si el minuto actual está dentro de una ventana ------
bool IsInDayWindow(string window, int nowMinutes)
{
   if(StringLen(window) == 0) return false;

   int start = 0;
   while(start < StringLen(window))
   {
      int comma = StringFind(window, ",", start);
      string token;
      if(comma < 0) { token = StringSubstr(window, start); start = StringLen(window); }
      else          { token = StringSubstr(window, start, comma - start); start = comma + 1; }

      token = StringTrimLeft(token);
      token = StringTrimRight(token);

      int dash = StringFind(token, "-");
      if(dash < 0) continue;

      int from = TimeStrToMinutes(StringSubstr(token, 0, dash));
      int to   = TimeStrToMinutes(StringSubstr(token, dash + 1));
      if(from < 0 || to < 0) continue;
      if(nowMinutes >= from && nowMinutes <= to) return true;
   }
   return false;
}

//===================================================================
//===  SESIONES – HORA UTC (TimeGMT)                               ===
//===================================================================
bool IsAsiaSession()
{
   if(!EnableAsiaSession) return false;
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.hour >= AsiaStartHour && dt.hour < AsiaEndHour);
}
bool IsEuropeSession()
{
   if(!EnableEuropeSession) return false;
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.hour >= EuropeStartHour && dt.hour < EuropeEndHour);
}
bool IsUSSession()
{
   if(!EnableUSSession) return false;
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.hour >= USStartHour && dt.hour < USEndHour);
}
bool IsCustomSession()
{
   if(!UseCustomHours) return false;
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   int nowMin = dt.hour * 60 + dt.min;

   string parts[];
   int cnt = StringSplit(CustomHours, '|', parts);
   for(int i = 0; i < cnt; i++)
   {
      string s = parts[i];
      s = StringTrimLeft(s);
      s = StringTrimRight(s);
      int dash = StringFind(s, "-");
      if(dash < 0) continue;
      int from = TimeStrToMinutes(StringSubstr(s, 0, dash));
      int to   = TimeStrToMinutes(StringSubstr(s, dash + 1));
      if(from < 0 || to < 0) continue;
      if(nowMin >= from && nowMin <= to) return true;
   }
   return false;
}

//--- Multiplicador de riesgo según sesión activa -------------------
double GetRiskMultiplier()
{
   if(IsAsiaSession())   return AsiaRiskMultiplier;
   if(IsEuropeSession()) return EuropeRiskMultiplier;
   if(IsUSSession())     return USRiskMultiplier;
   if(IsCustomSession()) return CustomRiskMultiplier;
   return 0.5;   // riesgo mínimo cuando ninguna sesión está activa
}

//--- Permite operar? (alguna sesión activa) -----------------------
bool IsTradingTimeAllowed()
{
   return (IsAsiaSession() || IsEuropeSession() || IsUSSession() || IsCustomSession());
}

//--- ATR (valor actual, en precios) ---------------------------------
double GetATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   int handle = iATR(_Symbol, _Period, ATRPeriod);
   if(CopyBuffer(handle, 0, 0, 2, atr) < 2)
   {
      IndicatorRelease(handle);
      return 0;
   }
   double val = atr[0];
   IndicatorRelease(handle);
   return val;
}

//--- Volatilidad promedio de las últimas 10 barras (en precios) --
double GetCurrentVolatility()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   if(CopyHigh(_Symbol, _Period, 0, 10, high) < 10 ||
      CopyLow (_Symbol, _Period, 0, 10, low ) < 10) return 0;

   double sum = 0;
   for(int i = 0; i < 10; i++) sum += high[i] - low[i];
   return sum / 10.0;
}

//--- Estructura del mercado (devuelve enum) -----------------------
int GetMarketStructure()
{
   // Necesitamos al menos StructureLookback + 5 barras para el cálculo del breakout
   int needed = MathMax(StructureLookback, 5);
   if(Bars(_Symbol, _Period) < needed + 1) return STATE_NEUTRAL;

   int higherHighs = 0, lowerLows = 0, inside = 0;
   for(int i = 2; i < StructureLookback - 1; i++)
   {
      double h1 = iHigh(_Symbol, _Period, i);
      double h2 = iHigh(_Symbol, _Period, i+1);
      double h3 = iHigh(_Symbol, _Period, i+2);
      double l1 = iLow (_Symbol, _Period, i);
      double l2 = iLow (_Symbol, _Period, i+1);
      double l3 = iLow (_Symbol, _Period, i+2);

      if(h1 > h2 && h1 > h3) higherHighs++;
      if(l1 < l2 && l1 < l3) lowerLows++;
      if(h1 <= h2 && l1 >= l2) inside++;
   }

   double total = StructureLookback - 2;
   double bullRat = higherHighs / total;
   double bearRat = lowerLows  / total;
   double rangRat = inside     / total;

   if(rangRat > 0.4) return STATE_RANGING;
   if(bullRat > 0.3 && bullRat > bearRat * 1.5) return STATE_BULLISH;
   if(bearRat > 0.3 && bearRat > bullRat * 1.5) return STATE_BEARISH;

   // ---- Breakout ------------------------------------------------
   double recentHigh = iHigh(_Symbol, _Period,
                     iHighest(_Symbol, _Period, MODE_HIGH, 5, 0));
   double recentLow  = iLow (_Symbol, _Period,
                     iLowest (_Symbol, _Period, MODE_LOW , 5, 0));
   double price = iClose(_Symbol, _Period, 0);
   if(price >= recentHigh * 0.999) return STATE_BREAKOUT;
   if(price <= recentLow  * 1.001) return -STATE_BREAKOUT;

   return STATE_NEUTRAL;
}

//--- Momentum (suma de diferencias de cierre) ----------------------
double GetMomentum()
{
   if(Bars(_Symbol, _Period) < MomentumBars + 2) return 0;
   double sum = 0;
   for(int i = 0; i < MomentumBars; i++)
      sum += iClose(_Symbol, _Period, i) - iClose(_Symbol, _Period, i+1);
   return sum;
}

//--- Rango (máximo y mínimo) ---------------------------------------
bool GetRange(double &rangeHigh, double &rangeLow)
{
   if(Bars(_Symbol, _Period) < RangeBars) return false;
   rangeHigh = iHigh(_Symbol, _Period,
                     iHighest(_Symbol, _Period, MODE_HIGH, RangeBars, 0));
   rangeLow  = iLow (_Symbol, _Period,
                     iLowest (_Symbol, _Period, MODE_LOW , RangeBars, 0));
   return true;
}

//--- Puntuación de señal (0‑100) -----------------------------------
double CalculateSignalScore(int direction)   // direction: +1 BUY, -1 SELL
{
   // Si se fuerza el trade (pruebas) devolvemos puntuación máxima
   if(ForceTrade) return 99.0;

   double score = 0;

   // 1) Estructura del mercado (25 pts)
   int st = GetMarketStructure();
   if(direction > 0 && st == STATE_BULLISH) score += 25;
   else if(direction < 0 && st == STATE_BEARISH) score += 25;
   else if(st == STATE_RANGING) score += 15;
   else if(MathAbs(st) == STATE_BREAKOUT) score += 20;

   // 2) Momentum (30 pts)
   double mom = MathAbs(GetMomentum());
   if(mom >= MinMomentumStrength)          score += 30;
   else if(mom >= MinMomentumStrength*0.7) score += 20;

   // 3) Volatilidad (20 pts)
   g_currentVolatility = GetCurrentVolatility();
   if(UseVolatilityFilter)
   {
      if(g_currentVolatility >= VolatilityThreshold)          score += 20;
      else if(g_currentVolatility >= VolatilityThreshold*0.7) score += 10;
   }
   else score += 20;

   // 4) Posición en rango (15 pts)
   double high, low;
   if(GetRange(high, low))
   {
      double range = high - low;
      double upperZ = high - range * RangeThreshold;
      double lowerZ = low  + range * RangeThreshold;
      double price = iClose(_Symbol, _Period, 0);

      if(direction < 0 && price >= upperZ) score += 15;
      if(direction > 0 && price <= lowerZ) score += 15;
   }

   // 5) Confirmación de precios (10 pts)
   int confirms = 0;
   for(int i = 0; i < ConfirmationBars; i++)
   {
      double cur  = iClose(_Symbol, _Period, i);
      double prev = iClose(_Symbol, _Period, i+1);
      if(direction > 0 && cur < prev) confirms++;
      if(direction < 0 && cur > prev) confirms++;
   }
   if(confirms == ConfirmationBars) score += 10;

   if(EnableLogging && DebugMode)
      PrintFormat("DEBUG → Dir:%s | Struct:%d | Mom:%.3f | Vol:%.4f | Score:%.1f",
                  (direction>0?"BUY":"SELL"), st, mom,
                  g_currentVolatility, score);

   return score;   // 0‑100
}

//--- SL/TP (según ATR o volatilidad) -----------------------------
void GetSLTP(int direction, double entry, double &sl, double &tp)
{
   if(UseATRBasedSL && g_atrValue > 0)
   {
      double atr = g_atrValue * ATRMultiplier;
      sl = (direction>0) ? entry - atr : entry + atr;
      tp = (direction>0) ? entry + atr*2.0 : entry - atr*2.0;
   }
   else
   {
      double vol = g_currentVolatility * 0.5;
      sl = (direction>0) ? entry - vol : entry + vol;
      tp = (direction>0) ? entry + vol*1.5 : entry - vol*1.5;
   }
}

//--- Cálculo del lote óptimo ---------------------------------------
double CalcOptimalLot(double stopDist)
{
   double riskPct = BaseRiskPercent * GetRiskMultiplier();
   riskPct = MathMin(riskPct, MaxRiskPercent);

   if(!UseDynamicSizing) return MathMin(MaxLotSize, MathMax(MinLotSize, 0.1));

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskUSD = balance * riskPct / 100.0;
   if(stopDist <= 0) return MinLotSize;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointVal  = tickValue * _Point / tickSize;

   double lot = riskUSD / (stopDist * pointVal);
   lot = MathMax(lot, MinLotSize);
   lot = MathMin(lot, MaxLotSize);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;

   return NormalizeDouble(lot,2);
}

//--- Creación de objetos de texto (Dashboard) ----------------------
void CreateTextObject(string name, int x, int y, string txt, color clr, int fsize = 8)
{
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsize);
   ObjectSetString (0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//--- Dashboard ---------------------------------------------------
void UpdateDashboard()
{
   if(!ShowDashboard) return;
   ObjectsDeleteAll(0, g_prefixDashboard);

   int x = DashboardX, y = DashboardY;
   CreateTextObject(g_prefixDashboard+"Title", x, y,
                    "🚀 MoneyMachine7 v4.4", DashboardColor, 10);
   y += 25;

   // Hora UTC y sesión activa
   MqlDateTime utc; TimeToStruct(TimeGMT(), utc);
   string sess = "Sesión (UTC): ";
   if(IsAsiaSession())   sess += "Asia 🗾 ";
   else if(IsEuropeSession()) sess += "Europa 🇪🇺 ";
   else if(IsUSSession())     sess += "EE.UU. 🇺🇸 ";
   else if(IsCustomSession()) sess += "Custom ⏰ ";
   else sess += "CERRADO 🔒 ";

   CreateTextObject(g_prefixDashboard+"Time", x, y,
                    StringFormat("UTC %02d:%02d", utc.hour, utc.min), DashboardColor);
   y += 15;
   CreateTextObject(g_prefixDashboard+"Session", x, y, sess, DashboardColor);
   y += 20;

   // Estado del mercado
   string ms;
   switch(g_currentMarketState)
   {
      case STATE_BULLISH: ms = "ALCISTA 🟢"; break;
      case STATE_BEARISH: ms = "BAJISTA 🔴"; break;
      case STATE_RANGING: ms = "RANGO ⚪";   break;
      case STATE_BREAKOUT: ms = "BREAKOUT ⚡";break;
      default: ms = "NEUTRAL ⚪"; break;
   }
   CreateTextObject(g_prefixDashboard+"Market", x, y,
                    "Estado: "+ms, DashboardColor);
   y += 20;

   // Calidad de señal (última evaluada)
   string qs = "Calidad señal: "+DoubleToString(g_signalQuality,1)+"%";
   color qscol = (g_signalQuality>=SignalQualityThreshold) ? BullColor :
                 (g_signalQuality>=SignalQualityThreshold*0.5 ? NeutralColor : BearColor);
   CreateTextObject(g_prefixDashboard+"Quality", x, y, qs, qscol);
   y += 20;

   // ATR y volatilidad
   CreateTextObject(g_prefixDashboard+"ATR", x, y,
                    "ATR: "+DoubleToString(g_atrValue/g_point,1)+" pts", DashboardColor);
   y += 15;
   CreateTextObject(g_prefixDashboard+"Vol", x, y,
                    "Vol: "+DoubleToString(g_currentVolatility/g_point,1)+" pts", DashboardColor);
   y += 20;

   // Multiplicador de riesgo
   CreateTextObject(g_prefixDashboard+"RiskMult", x, y,
                    "Riesgo x"+DoubleToString(GetRiskMultiplier(),2), DashboardColor);
   y += 20;

   // Estado de la posición (si la hay)
   if(g_trade.isOpen)
   {
      string dir = (g_trade.direction>0)?"BUY":"SELL";
      string pos = "Pos: "+dir+" | P&L: "+DoubleToString(g_trade.unrealizedPnL/g_point,1)+" pts";
      color pcl = (g_trade.unrealizedPnL>=0) ? BullColor : BearColor;
      CreateTextObject(g_prefixDashboard+"Pos", x, y, pos, pcl);
   }
   else
      CreateTextObject(g_prefixDashboard+"Pos", x, y,
                        "Posición: ESPERANDO señal", NeutralColor);
}

//--- Información del algoritmo -----------------------------------
void UpdateAlgoInfo()
{
   if(!ShowAlgoInfo) return;
   ObjectsDeleteAll(0, g_prefixAlgoInfo);

   int x = DashboardX + 300, y = DashboardY;
   CreateTextObject(g_prefixAlgoInfo+"Title", x, y,
                    "🧠 Información del algoritmo", DashboardColor, 10);
   y += 25;

   string estr = "Estructura: ";
   switch(g_currentMarketState)
   {
      case STATE_BULLISH: estr += "ALCISTA"; break;
      case STATE_BEARISH: estr += "BAJISTA"; break;
      case STATE_RANGING: estr += "RANGO";  break;
      case STATE_BREAKOUT: estr += "BREAKOUT";break;
      default: estr += "NEUTRAL"; break;
   }
   CreateTextObject(g_prefixAlgoInfo+"Struct", x, y, estr, DashboardColor);
   y += 15;

   CreateTextObject(g_prefixAlgoInfo+"Momentum", x, y,
                    "Momentum: "+DoubleToString(GetMomentum(),2), DashboardColor);
   y += 15;

   CreateTextObject(g_prefixAlgoInfo+"ATR", x, y,
                    "ATR: "+DoubleToString(g_atrValue/g_point,2), DashboardColor);
   y += 15;

   CreateTextObject(g_prefixAlgoInfo+"Vol", x, y,
                    "Vol: "+DoubleToString(g_currentVolatility/g_point,2), DashboardColor);
   y += 15;

   string sess = "";
   if(EnableAsiaSession)   sess += "Asia "+StringFormat("%02d-%02d ",AsiaStartHour,AsiaEndHour);
   if(EnableEuropeSession) sess += "Europa "+StringFormat("%02d-%02d ",EuropeStartHour,EuropeEndHour);
   if(EnableUSSession)     sess += "EE.UU. "+StringFormat("%02d-%02d ",USStartHour,USEndHour);
   if(UseCustomHours)      sess += "Custom "+CustomHours;
   CreateTextObject(g_prefixAlgoInfo+"Sessions", x, y,
                    "Sesiones: "+sess, DashboardColor);
}

//--- Zonas de soporte / resistencia -------------------------------
void DrawTradeZones()
{
   if(!ShowTradeZones) return;
   ObjectsDeleteAll(0, g_prefixTradeZone);

   double high, low;
   if(!GetRange(high, low)) return;   // datos insuficientes

   double range = high - low;
   double upperZ = high - range * RangeThreshold;
   double lowerZ = low  + range * RangeThreshold;

   // Zona de venta (resistencia)
   if(ObjectCreate(0, g_prefixTradeZone+"Upper", OBJ_RECTANGLE, 0,
                    iTime(_Symbol,_Period,100), upperZ,
                    TimeCurrent(),            high))
   {
      ObjectSetInteger(0, g_prefixTradeZone+"Upper", OBJPROP_COLOR, BearColor);
      ObjectSetInteger(0, g_prefixTradeZone+"Upper", OBJPROP_BACK,  true);
      ObjectSetInteger(0, g_prefixTradeZone+"Upper", OBJPROP_FILL,  true);
      ObjectSetString (0, g_prefixTradeZone+"Upper", OBJPROP_TOOLTIP, "Zona de venta");
   }

   // Zona de compra (soporte)
   if(ObjectCreate(0, g_prefixTradeZone+"Lower", OBJ_RECTANGLE, 0,
                    iTime(_Symbol,_Period,100), low,
                    TimeCurrent(),            lowerZ))
   {
      ObjectSetInteger(0, g_prefixTradeZone+"Lower", OBJPROP_COLOR, BullColor);
      ObjectSetInteger(0, g_prefixTradeZone+"Lower", OBJPROP_BACK,  true);
      ObjectSetInteger(0, g_prefixTradeZone+"Lower", OBJPROP_FILL,  true);
      ObjectSetString (0, g_prefixTradeZone+"Lower", OBJPROP_TOOLTIP, "Zona de compra");
   }
}

//--- Estadísticas de performance ----------------------------------
void UpdatePerformanceDisplay()
{
   if(!ShowPerformance) return;
   ObjectsDeleteAll(0, g_prefixPerf);

   int x = DashboardX + 600, y = DashboardY;
   CreateTextObject(g_prefixPerf+"Title", x, y,
                    "📊 Performance", DashboardColor, 10);
   y += 25;

   string stats = StringFormat("Trades: %d | Wins: %.1f%% | P&L: $%.2f",
                               (int)g_perf.totalTrades,
                               g_perf.winRate,
                               g_perf.totalProfit);
   CreateTextObject(g_prefixPerf+"Stats", x, y, stats, DashboardColor);
   y += 15;

   string dd = "Drawdown: "+DoubleToString(g_perf.currentDrawdown,2)+"%";
   color ddcol = (g_perf.currentDrawdown<5)?BullColor:
                 (g_perf.currentDrawdown<10?NeutralColor:BearColor);
   CreateTextObject(g_prefixPerf+"DD", x, y, dd, ddcol);
   y += 15;

   string pf = "ProfitFactor: "+DoubleToString(g_perf.profitFactor,2);
   CreateTextObject(g_prefixPerf+"PF", x, y, pf, DashboardColor);
}

//===================================================================
//===  HELPERS                                                    ===
//===================================================================

//--- Ticket de la posición actual (con magic) -----------------------
ulong GetCurrentPositionTicket()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && (int)PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         return tk;
   }
   return 0;
}

//===================================================================
//===  OPERACIONES DE TRADE                                        ===
//===================================================================

//--- Ejecutar orden BUY / SELL ------------------------------------
bool ExecuteTrade(int direction)   // direction: +1 BUY, -1 SELL
{
   if(g_trade.isOpen) return false;               // posición ya abierta

   // --------------------------------------------------------------
   //  1) COMPROBACIONES (salta si ForceTrade está activo)
   // --------------------------------------------------------------
   if(!ForceTrade && !IsTradingTimeAllowed())
   {
      if(EnableLogging) Print("Operación bloqueada: fuera de sesión");
      return false;
   }
   if(!ForceTrade && UseVolatilityFilter && g_currentVolatility < VolatilityThreshold)
   {
      if(EnableLogging) Print("Operación bloqueada: volatilidad insuficiente (",g_currentVolatility,")");
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (direction>0)? ask : bid;

   // SL / TP
   double sl, tp;
   GetSLTP(direction, entry, sl, tp);

   // Tamaño de lote
   double stopDist = MathAbs(entry - sl);
   double lot = CalcOptimalLot(stopDist);
   lot = MathMax(lot, MinLotSize);
   lot = MathMin(lot, MaxLotSize);

   // Preparar la orden
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool result = false;
   if(direction>0) // BUY
      result = trade.Buy(lot, _Symbol, entry, sl, tp, "MM7_BUY");
   else
      result = trade.Sell(lot,_Symbol, entry, sl, tp, "MM7_SELL");

   if(result)
   {
      // Guardar estado interno
      g_trade.isOpen        = true;
      g_trade.direction    = direction;
      g_trade.entryPrice   = entry;
      g_trade.stopLoss     = sl;
      g_trade.takeProfit   = tp;
      g_trade.openTime     = TimeCurrent();
      g_trade.partialClosed= false;
      g_trade.trailingActive= false;
      g_trade.trailLevel   = 0;
      g_trade.unrealizedPnL= 0;

      if(EnableLogging)
         Print("ORDEN ",(direction>0?"BUY":"SELL"),
               " | Precio=",entry,
               " | SL=",sl,
               " | TP=",tp,
               " | Lote=",lot);
      if(EnableAlerts){ Alert("MoneyMachine7 – "+(direction>0?"BUY":"SELL")+" abierto"); PlaySound(AlertSound); }
   }
   else
   {
      if(EnableLogging) Print("Error enviando orden. Código: ",GetLastError());
   }
   return result;
}

//--- Gestión de la posición abierta --------------------------------
void ManageOpenTrade()
{
   if(!g_trade.isOpen) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (g_trade.direction>0)? ask : bid;

   // P&L no realizado
   g_trade.unrealizedPnL = (g_trade.direction>0)? (bid - g_trade.entryPrice)
                                                : (g_trade.entryPrice - ask);
   double profitPct = (g_trade.unrealizedPnL / g_trade.entryPrice) * 100.0;

   // ---------- Salida parcial ----------
   if(UsePartialExit && !g_trade.partialClosed && profitPct >= PartialExitTrigger)
   {
      ulong ticket = GetCurrentPositionTicket();
      if(ticket)
      {
         double vol = PositionGetDouble(POSITION_VOLUME);
         double closeVol = NormalizeDouble(vol * PartialExitPercent / 100.0, 2);
         double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         if(step>0) closeVol = MathFloor(closeVol/step)*step;
         if(closeVol < vol)
         {
            MqlTradeRequest req={}; MqlTradeResult res={};
            req.action   = TRADE_ACTION_DEAL;
            req.symbol   = _Symbol;
            req.volume   = closeVol;
            req.type     = (g_trade.direction>0)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
            req.price    = (g_trade.direction>0)?bid:ask;
            req.position = ticket;
            req.deviation= SlippagePoints;
            req.magic    = MagicNumber;
            req.comment  = "MM7_Partial";
            req.type_filling = ORDER_FILLING_FOK;
            if(OrderSend(req, res))
            {
               g_trade.partialClosed = true;
               if(EnableLogging) Print("Salida parcial ejecutada, vol=",closeVol);
               if(EnableAlerts){ Alert("MoneyMachine7 – Salida parcial"); PlaySound(AlertSound); }
            }
         }
      }
   }

   // ---------- Trailing ----------
   if(UseTrailingStop && profitPct >= TrailingActivation)
   {
      double newSL = (g_trade.direction>0)?
                     price - TrailingDistance * _Point :
                     price + TrailingDistance * _Point;

      if(!g_trade.trailingActive ||
         (g_trade.direction>0 && newSL > g_trade.stopLoss) ||
         (g_trade.direction<0 && newSL < g_trade.stopLoss))
      {
         ulong ticket = GetCurrentPositionTicket();
         if(ticket)
         {
            MqlTradeRequest tr={}; MqlTradeResult rs={};
            tr.action   = TRADE_ACTION_SLTP;
            tr.symbol   = _Symbol;
            tr.position = ticket;
            tr.sl       = newSL;
            tr.tp       = g_trade.takeProfit;
            if(OrderSend(tr, rs))
            {
               g_trade.stopLoss = newSL;
               g_trade.trailingActive = true;
               if(EnableLogging) Print("Trailing activado, nuevo SL=",newSL);
            }
         }
      }
   }

   // ---------- Breakeven (Smart Exit) ----------
   if(UseSmartExit && !g_trade.trailingActive && profitPct >= 20.0)
   {
      ulong ticket = GetCurrentPositionTicket();
      if(ticket)
      {
         MqlTradeRequest tr={}; MqlTradeResult rs={};
         tr.action   = TRADE_ACTION_SLTP;
         tr.symbol   = _Symbol;
         tr.position = ticket;
         tr.sl       = g_trade.entryPrice;   // breakeven
         tr.tp       = g_trade.takeProfit;
         if(OrderSend(tr, rs))
            if(EnableLogging) Print("Breakeven activado");
      }
   }
}

//===================================================================
//===  EVENT HANDLERS                                            ===
//===================================================================

int OnInit()
{
   g_symbol = _Symbol;
   g_magic  = MagicNumber;
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(g_point <= 0)
   {
      Alert("Error: SYMBOL_POINT inválido");
      return INIT_FAILED;
   }

   Print("MoneyMachine7 v4.4 inicializado");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefixDashboard);
   ObjectsDeleteAll(0, g_prefixAlgoInfo);
   ObjectsDeleteAll(0, g_prefixTradeZone);
   ObjectsDeleteAll(0, g_prefixPerf);
   Print("MoneyMachine7 detenido. Razón: ",reason);
}

//--------------------------------------------------------------------
void OnTick()
{
   // 1) Sólo procesar una vez por barra nueva
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_lastBarTime) return;
   g_lastBarTime = curBar;

   // 2) Actualizar indicadores internos
   g_atrValue          = GetATR();
   g_currentVolatility = GetCurrentVolatility();
   g_currentMarketState = (MARKET_STATE)GetMarketStructure();

   // 3) Dashboard y objetos gráficos
   UpdateDashboard();
   UpdateAlgoInfo();
   DrawTradeZones();
   UpdatePerformanceDisplay();

   // 4) Pausa por racha negativa
   if(g_pauseBarsLeft > 0)
   {
      g_pauseBarsLeft--;
      return;
   }

   // 5) Si hay posición abierta, gestionarla
   if(g_trade.isOpen) { ManageOpenTrade(); return; }

   // 6) Generar señal de trading
   double buyScore  = CalculateSignalScore(+1);
   double sellScore = CalculateSignalScore(-1);

   int direction = 0;
   if(buyScore >= SignalQualityThreshold && buyScore > sellScore)
   {
      direction = +1;
      g_signalQuality = buyScore;
   }
   else if(sellScore >= SignalQualityThreshold && sellScore > buyScore)
   {
      direction = -1;
      g_signalQuality = sellScore;
   }
   else
      g_signalQuality = MathMax(buyScore, sellScore);   // solo para el Dashboard

   if(direction != 0)
   {
      PrintFormat("Señal → Dir:%s | BuyScore:%.1f | SellScore:%.1f | FinalScore:%.1f",
                  (direction>0?"BUY":"SELL"), buyScore, sellScore, g_signalQuality);
      ExecuteTrade(direction);
   }
}

//--------------------------------------------------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest    &req,
                        const MqlTradeResult      &res)
{
   // Sólo nos interesan los deals que cierran una posición del EA
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   ulong  ticket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_TICKET);

   // ----- Performance -------------------------------------------------
   g_perf.totalTrades++;
   if(profit > 0) { g_perf.winningTrades++; g_perf.totalProfit += profit; }
   else          { g_perf.losingTrades++; g_perf.totalProfit += profit; }

   if(g_perf.totalTrades > 0)
   {
      g_perf.winRate = (g_perf.winningTrades / g_perf.totalTrades) * 100.0;
      double gp = 0, gl = 0;
      if(profit > 0) gp += profit; else gl += MathAbs(profit);
      g_perf.profitFactor = (gl > 0) ? gp / gl : 999.0;
   }

   // ----- Control de rachas negativas ---------------------------------
   static int consecutiveLosses = 0;
   if(profit < 0)
   {
      consecutiveLosses++;
      if(consecutiveLosses >= MaxConsecutiveLosses)
      {
         g_pauseBarsLeft = CooldownBars;
         if(EnableLogging)
            Print("Racha de ",consecutiveLosses," pérdidas – pausa de ",CooldownBars," barras");
         if(EnableAlerts){ Alert("MoneyMachine7 – Pausa por racha negativa"); PlaySound(AlertSound); }
      }
   }
   else
      consecutiveLosses = 0;

   // ----- Reset interno de la posición (ya cerrada) ------------------
   g_trade.isOpen        = false;
   g_trade.direction    = 0;
   g_trade.entryPrice   = 0;
   g_trade.stopLoss     = 0;
   g_trade.takeProfit   = 0;
   g_trade.openTime     = 0;
   g_trade.partialClosed= false;
   g_trade.trailingActive= false;
   g_trade.trailLevel   = 0;
   g_trade.unrealizedPnL = 0;
}

//+------------------------------------------------------------------+
