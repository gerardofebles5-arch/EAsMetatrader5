//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.18 — RESTAURAR EL EDGE PROBADO + MEJORAS QUIRÚRGICAS      |
//|                                                                  |
//|  ANÁLISIS v17.17: Net=-$7.20 | WR=25% | 38 trades              |
//|  CAUSA: Asia+London con señal EMA tienen WR muy bajo            |
//|  CAUSA: R:R negativo real (WR=25% con 1:2 = -EV)               |
//|                                                                  |
//|  ÚNICO EDGE PROBADO: NY 14:30-18:30 UTC con WR=57-75%          |
//|  v17.10: +$14.50 | PF=2.46 | WR=57% | 7 trades                 |
//|                                                                  |
//|  CAMBIOS v17.18 vs v17.10:                                      |
//|  1. BASE: lógica exacta de v17.10 (la que funcionó)             |
//|  2. FILTRO BUY: EMA21 pendiente positiva (simétrico al SELL)    |
//|     → Antes solo SELLs tenían filtro de pendiente               |
//|     → Ahora BUYs también requieren EMA21 subiendo               |
//|     → Elimina BUYs en tendencia bajista (falsos cruces)         |
//|  3. LONDON OPCIONAL: desactivado por defecto                    |
//|     Solo opera si precio rompió rango asiático                  |
//|     Activar solo para recopilar datos                           |
//|  4. ASIA: eliminada completamente                               |
//|  5. DIAGNÓSTICO: Print g_point en OnInit                        |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.18"
#property strict

// +++ Core +++
input bool   Control_orders_user         = true;
input int    Max_Positions               = 1;
input string CommentOrder                = "MM7";
input double Lot_                        = 0.01;
input bool   Use_dynamic_lot_            = true;
input double Free_margin_for_each_Lots_  = 1000.0;
input double Max_Lot_                    = 5.0;
// +++ Señal EMA +++
input int    EMA_Fast_Period             = 3;
input int    EMA_Slow_Period             = 8;
input int    EMA_Trend_Period            = 21;
// +++ Sesión NY (edge probado) +++
input int    NY_Start_Hour               = 14;
input int    NY_Start_Min                = 30;
input int    NY_End_Hour                 = 18;
input int    NY_End_Min                  = 30;
input int    NY_Max_Trades               = 6;
// +++ London opcional (desactivado por defecto) +++
input bool   London_Enable               = false;
input int    London_Start_Hour           = 7;
input int    London_End_Hour             = 12;
input int    London_Max_Trades           = 3;
// +++ SL/TP fijos scalping +++
input double MM7_TP_FIXED                = 1.00;
input double MM7_SL_FIXED                = 0.50;
// +++ Entry Control +++
input int    Entry_Cooldown_Secs         = 3;
input int    SL_Cooldown_Secs            = 300;
input int    InpMaxSpreadPoints          = 600;
input int    InpSlippagePoints           = 10;
input int    InpMagicNumber              = 171800;
// +++ Money Management +++
input double InpMaxDailyLossPct          = 20.0;
input double InpMaxEquityDrawdown        = 20.0;
// +++ Dashboard +++
input bool   Enable_Dashboard            = true;
input int    Dashboard_Corner            = 0;
input int    Dashboard_X_Offset          = 10;
input int    Dashboard_Y_Offset          = 30;
input int    Font_size_Result            = 11;
input bool   Enable_History_Labels       = true;
input int    History_Labels_Limit        = 50;

//============================================================
// GLOBALES
//============================================================
int      g_magic; double g_point; string g_sym;

int      g_hEMAf = INVALID_HANDLE;
int      g_hEMAs = INVALID_HANDLE;
int      g_hEMAt = INVALID_HANDLE;

datetime g_lastEntryTime  = 0;
datetime g_lastBarTime    = 0;
datetime g_lastSLTime     = 0;
datetime g_dayStart       = 0;
double   g_dayStartBal    = 0;
bool     g_haltedToday    = false;
datetime g_lastDashTime   = 0;
datetime g_lastLabelTime  = 0;

int      g_cachedSig  = 0;
double   g_cachedEMAf = 0;
double   g_cachedEMAs = 0;

// Rango asiático para London
double   g_asiaHigh = 0;
double   g_asiaLow  = 1e10;
bool     g_asiaReady = false;

// Contadores diarios
int      g_nyTrades  = 0;
int      g_lonTrades = 0;
datetime g_lonLastEntry = 0;
datetime g_lonLastSL    = 0;

//============================================================
// UTILIDADES
//============================================================
int GetHour()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(), d); return d.hour;
}

int GetNowMin()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(), d); return d.hour*60 + d.min;
}

double CalcLot()
{
   if(!Use_dynamic_lot_) return NormalizeDouble(Lot_, 2);
   double bal = (bool)MQLInfoInteger(MQL_TESTER)
                ? AccountInfoDouble(ACCOUNT_BALANCE)
                : MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   double lot = MathRound(bal / Free_margin_for_each_Lots_) * 0.01;
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, mn);
   lot = MathMin(lot, MathMin(Max_Lot_, mx));
   if(st > 0) lot = MathFloor(lot / st) * st;
   return NormalizeDouble(lot, 2);
}

int CountByMagic()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && (int)PositionGetInteger(POSITION_MAGIC) == g_magic) n++;
   }
   return n;
}

bool SpreadOK()
{
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   return ((ask - bid) / g_point <= InpMaxSpreadPoints);
}

ulong OpenOrder(ENUM_ORDER_TYPE type, int dir, string cmt)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double tp    = NormalizeDouble(entry + dir * MM7_TP_FIXED, digs);
   double sl    = NormalizeDouble(entry - dir * MM7_SL_FIXED, digs);

   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = CalcLot();
   req.type      = type;
   req.price     = entry;
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = InpSlippagePoints;
   req.magic     = g_magic;
   req.comment   = cmt;
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) {
      req.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(req, res)) {
         req.type_filling = ORDER_FILLING_RETURN;
         OrderSend(req, res);
      }
   }
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED)
      return res.order;
   Print("MM7 OrderSend FAIL retcode=", res.retcode, " comment=", res.comment);
   return 0;
}

//============================================================
// SEÑAL EMA — calculada una vez por barra
// MEJORA v17.18: filtro de pendiente EMA21 SIMÉTRICO
//   BUY  solo si EMA21 subiendo  (et[0] > et[1])
//   SELL solo si EMA21 bajando   (et[0] < et[1])
// Esto elimina cruces falsos contra la tendencia
//============================================================
int GetSignal()
{
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE) return 0;
   int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[], es[], et[];
   ArraySetAsSeries(ef, true); ArraySetAsSeries(es, true); ArraySetAsSeries(et, true);
   if(CopyBuffer(g_hEMAf, 0, s, 3, ef) < 3) return 0;
   if(CopyBuffer(g_hEMAs, 0, s, 3, es) < 3) return 0;
   if(CopyBuffer(g_hEMAt, 0, s, 2, et) < 2) return 0;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   bool crossUp   = (ef[0] > es[0] && ef[1] <= es[1]);
   bool crossDown = (ef[0] < es[0] && ef[1] >= es[1]);
   if(!crossUp && !crossDown) return 0;

   // precio del lado correcto de EMA21
   if(crossUp   && bid <= et[0]) return 0;
   if(crossDown && bid >= et[0]) return 0;

   // FILTRO SIMÉTRICO: EMA21 debe tener pendiente en dirección del trade
   if(crossUp   && et[0] <= et[1]) return 0;  // BUY solo si EMA21 subiendo
   if(crossDown && et[0] >= et[1]) return 0;  // SELL solo si EMA21 bajando

   return crossUp ? 1 : -1;
}

bool IsNYSession()
{
   int nm = GetNowMin();
   return (nm >= NY_Start_Hour*60+NY_Start_Min && nm < NY_End_Hour*60+NY_End_Min);
}

bool IsLondonSession()
{
   int h = GetHour();
   return (h >= London_Start_Hour && h < London_End_Hour);
}

void BuildAsiaRange()
{
   // Acumular rango 00:00-06:59 para contexto London
   int h = GetHour();
   if(h >= 0 && h < London_Start_Hour) {
      double hi[], lo[];
      ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true);
      if(CopyHigh(g_sym, _Period, 1, 1, hi) >= 1 && CopyLow(g_sym, _Period, 1, 1, lo) >= 1) {
         if(hi[0] > g_asiaHigh) g_asiaHigh = hi[0];
         if(lo[0] < g_asiaLow)  g_asiaLow  = lo[0];
      }
   }
   if(!g_asiaReady && g_asiaHigh > 0 && g_asiaLow < 1e9 && (g_asiaHigh - g_asiaLow) >= 0.30)
      g_asiaReady = true;
}

void DailyReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today == g_dayStart) return;
   g_dayStart    = today;
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday = false;
   g_lastEntryTime = 0; g_lastBarTime = 0; g_cachedSig = 0;
   g_nyTrades = 0; g_lonTrades = 0;
   g_asiaHigh = 0; g_asiaLow = 1e10; g_asiaReady = false;
}

void CheckHalt()
{
   if(g_haltedToday) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartBal <= 0) return;
   double pct = (g_dayStartBal - eq) / g_dayStartBal * 100.0;
   if(InpMaxEquityDrawdown > 0 && pct >= InpMaxEquityDrawdown)
   { g_haltedToday = true; Print("MM7 HALT: MaxEquityDrawdown"); return; }
   if(InpMaxDailyLossPct > 0 && pct >= InpMaxDailyLossPct)
   { g_haltedToday = true; Print("MM7 HALT: MaxDailyLoss"); }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) return;
   ulong dk = trans.deal;
   if(!HistoryDealSelect(dk)) return;
   if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   if((ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON) != DEAL_REASON_SL) return;
   string cmt = HistoryDealGetString(dk, DEAL_COMMENT);
   datetime now = TimeCurrent();
   g_lastSLTime = now;
   if(StringFind(cmt, "LON") >= 0) g_lonLastSL = now;
   Print("MM7 SL hit → cooldown ", SL_Cooldown_Secs, "s");
}

//============================================================
// LÓGICA DE ENTRADA NY — edge probado (base v17.10)
//============================================================
void NY_TryEntry()
{
   if(!IsNYSession()) return;
   if(g_cachedSig == 0) return;
   if(g_nyTrades >= NY_Max_Trades) return;
   if(CountByMagic() >= Max_Positions) return;
   if(TimeCurrent() - g_lastSLTime < SL_Cooldown_Secs) return;
   if(TimeCurrent() - g_lastEntryTime < Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;

   ENUM_ORDER_TYPE otype = (g_cachedSig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong tk = OpenOrder(otype, g_cachedSig, "MM7-NY");
   if(tk > 0) {
      g_nyTrades++;
      g_lastEntryTime = TimeCurrent();
      g_cachedSig = 0;
      Print("MM7 NY ", (otype==ORDER_TYPE_BUY?"BUY":"SELL"), " #", g_nyTrades,
            " lot=", CalcLot(), " SL=", MM7_SL_FIXED, " TP=", MM7_TP_FIXED);
   }
}

//============================================================
// LÓGICA DE ENTRADA LONDON — opcional, breakout asiático
//============================================================
void London_TryEntry()
{
   if(!London_Enable) return;
   if(!IsLondonSession()) return;
   if(g_cachedSig == 0) return;
   if(g_lonTrades >= London_Max_Trades) return;
   if(CountByMagic() >= Max_Positions) return;
   if(TimeCurrent() - g_lonLastSL < SL_Cooldown_Secs) return;
   if(TimeCurrent() - g_lonLastEntry < Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;

   // Filtro breakout: solo operar en dirección del breakout del rango asiático
   if(g_asiaReady) {
      double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
      if(g_cachedSig == 1  && bid < g_asiaHigh) return;  // BUY solo si rompió arriba
      if(g_cachedSig == -1 && bid > g_asiaLow)  return;  // SELL solo si rompió abajo
   }

   ENUM_ORDER_TYPE otype = (g_cachedSig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong tk = OpenOrder(otype, g_cachedSig, "MM7-LON");
   if(tk > 0) {
      g_lonTrades++;
      g_lonLastEntry = TimeCurrent();
      g_cachedSig = 0;
      Print("MM7 LON ", (otype==ORDER_TYPE_BUY?"BUY":"SELL"), " #", g_lonTrades);
   }
}

//============================================================
// DASHBOARD
//============================================================
void DashLbl(string nm, string txt, color clr, int row)
{
   string f = "MM7D_" + nm; int lh = Font_size_Result + 4;
   if(ObjectFind(0, f) < 0) {
      ObjectCreate(0, f, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, f, OBJPROP_CORNER, (ENUM_BASE_CORNER)Dashboard_Corner);
      ObjectSetInteger(0, f, OBJPROP_XDISTANCE, Dashboard_X_Offset);
      ObjectSetString(0, f, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, f, OBJPROP_FONTSIZE, Font_size_Result);
   }
   ObjectSetInteger(0, f, OBJPROP_YDISTANCE, Dashboard_Y_Offset + row*lh);
   ObjectSetString(0, f, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, f, OBJPROP_COLOR, clr);
}

void DrawDashboard()
{
   if(!Enable_Dashboard || TimeCurrent() - g_lastDashTime < 1) return;
   g_lastDashTime = TimeCurrent();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd  = (g_dayStartBal > 0) ? (g_dayStartBal - eq) / g_dayStartBal * 100.0 : 0;
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   double dp = 0; HistorySelect(ds, TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) == g_magic)
         dp += HistoryDealGetDouble(dk, DEAL_PROFIT);
   }
   bool inNY  = IsNYSession();
   bool inLon = IsLondonSession();
   string sess = inNY ? "NY 14:30-18:30" : (inLon ? "LONDON" : "---");
   color  sc   = inNY ? clrLimeGreen : (inLon ? clrOrange : clrGray);

   DashLbl("0", "[ MoneyMachine7 v17.18 — NY EDGE + FILTRO SIMETRICO ]", clrGold, 0);
   DashLbl("1", "Sesion: " + sess + " | SL=" + DoubleToString(MM7_SL_FIXED,2) + " TP=" + DoubleToString(MM7_TP_FIXED,2) + " R:R=1:2", sc, 1);
   DashLbl("2", "Bal:$" + DoubleToString(bal,2) + " Eq:$" + DoubleToString(eq,2) + " lot=" + DoubleToString(CalcLot(),2), clrWhite, 2);
   DashLbl("3", "Day:$" + DoubleToString(dp,2) + " DD:" + DoubleToString(dd,2) + "%", (dp>=0)?clrLimeGreen:clrOrangeRed, 3);
   DashLbl("4", "NY tr:" + IntegerToString(g_nyTrades) + "/" + IntegerToString(NY_Max_Trades) +
               " LON tr:" + IntegerToString(g_lonTrades) + "/" + IntegerToString(London_Max_Trades) +
               (London_Enable ? "" : " [OFF]"), clrCyan, 4);
   string sigStr = (g_cachedSig==1) ? "BUY" : (g_cachedSig==-1) ? "SELL" : "--";
   bool inSLCool = (TimeCurrent() - g_lastSLTime < SL_Cooldown_Secs);
   int  cdLeft   = inSLCool ? (int)(g_lastSLTime + SL_Cooldown_Secs - TimeCurrent()) : 0;
   DashLbl("5", "Sig:" + sigStr + " EMAf:" + DoubleToString(g_cachedEMAf,2) + " EMAs:" + DoubleToString(g_cachedEMAs,2), clrWhite, 5);
   DashLbl("6", "SLcool:" + (inSLCool ? IntegerToString(cdLeft)+"s" : "OK") + " Halt:" + (g_haltedToday?"SI":"no"), clrGray, 6);
}

void DrawHistoryLabels()
{
   if(!Enable_History_Labels || TimeCurrent() - g_lastLabelTime < 10) return;
   g_lastLabelTime = TimeCurrent();
   ObjectsDeleteAll(0, "MM7L_");
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(ds, TimeCurrent());
   int tot = HistoryDealsTotal(), st = MathMax(0, tot - History_Labels_Limit);
   for(int i = st; i < tot; i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) != g_magic) continue;
      if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double pf = HistoryDealGetDouble(dk, DEAL_PROFIT);
      double px = HistoryDealGetDouble(dk, DEAL_PRICE);
      datetime t = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);
      string nm = "MM7L_" + (string)dk;
      if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TEXT, 0, t, px);
      ObjectSetString(0, nm, OBJPROP_TEXT, (pf>=0?"+":"")+DoubleToString(pf,2));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, (pf>=0)?clrLimeGreen:clrOrangeRed);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
   }
}

//============================================================
// OnInit / OnDeinit / OnTick
//============================================================
int OnInit()
{
   g_magic = InpMagicNumber;
   g_sym   = _Symbol;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }

   g_hEMAf = iMA(g_sym, _Period, EMA_Fast_Period,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMAs = iMA(g_sym, _Period, EMA_Slow_Period,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMAt = iMA(g_sym, _Period, EMA_Trend_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE)
   { Alert("EMA init failed"); return INIT_FAILED; }

   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_asiaLow     = 1e10;

   // DIAGNÓSTICO: verificar g_point para XAUUSD
   Print("MM7 v17.18 INIT | Symbol=", g_sym,
         " | SYMBOL_POINT=", g_point,
         " | DIGITS=", SymbolInfoInteger(g_sym, SYMBOL_DIGITS),
         " | SL=", MM7_SL_FIXED, "pts (precio: entry±", MM7_SL_FIXED, ")",
         " | TP=", MM7_TP_FIXED, "pts",
         " | NY ", NY_Start_Hour, ":", NY_Start_Min, "-", NY_End_Hour, ":", NY_End_Min, " UTC",
         " | SL_CD=", SL_Cooldown_Secs, "s",
         " | London=", London_Enable ? "ON" : "OFF");
   Print("MM7 FILTRO: BUY solo EMA21 subiendo | SELL solo EMA21 bajando (simétrico)");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "MM7D_");
   ObjectsDeleteAll(0, "MM7L_");
   if(g_hEMAf != INVALID_HANDLE) IndicatorRelease(g_hEMAf);
   if(g_hEMAs != INVALID_HANDLE) IndicatorRelease(g_hEMAs);
   if(g_hEMAt != INVALID_HANDLE) IndicatorRelease(g_hEMAt);
}

void OnTick()
{
   DailyReset();
   CheckHalt();
   DrawDashboard();
   DrawHistoryLabels();

   if(g_haltedToday || !Control_orders_user) return;

   // Guard de barra — señal calculada una vez por barra M1
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      BuildAsiaRange();
      g_cachedSig = GetSignal();
      int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
      double ef[], es[];
      ArraySetAsSeries(ef, true); ArraySetAsSeries(es, true);
      if(CopyBuffer(g_hEMAf, 0, s, 1, ef) >= 1) g_cachedEMAf = ef[0];
      if(CopyBuffer(g_hEMAs, 0, s, 1, es) >= 1) g_cachedEMAs = es[0];
   }

   if(g_cachedSig == 0) return;

   // Intentar entrada según sesión activa
   NY_TryEntry();
   if(g_cachedSig != 0) London_TryEntry();
}
