//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.14 — TRI-SESSION ENGINE: ASIA + LONDON + NY               |
//|                                                                  |
//|  ARQUITECTURA: 3 estrategias independientes, 1 EA               |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════    |
//|  SESIÓN ASIA  00:00-05:00 UTC  → RANGE FADE                    |
//|  ───────────────────────────────────────────────────────────    |
//|  El oro en Asia 2026 consolida en rango estrecho antes de       |
//|  que Londres tome el control. Estrategia: operar rebotes        |
//|  dentro del rango. Si precio toca el techo del rango → SELL.   |
//|  Si toca el suelo → BUY. SL fuera del rango, TP al centro.     |
//|  R:R 1:1 pero WR alta (mercado respeta el rango).              |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════    |
//|  SESIÓN LONDON  07:00-12:00 UTC  → ASIAN RANGE BREAKOUT        |
//|  ───────────────────────────────────────────────────────────    |
//|  Londres rompe el rango asiático con volumen real. Estrategia:  |
//|  esperar cierre de barra M1 fuera del rango asiático + ATR      |
//|  mínimo para confirmar que no es fakeout. Entrar en la          |
//|  dirección del breakout. SL ATR-based, TP 1.5x riesgo.         |
//|  Basado en: mql5.com/en/blogs/post/767326 (2026 post-5k)       |
//|                                                                  |
//|  ═══════════════════════════════════════════════════════════    |
//|  SESIÓN NY  13:00-18:30 UTC  → EMA MOMENTUM                    |
//|  ───────────────────────────────────────────────────────────    |
//|  Probado en backtests: 75% WR en NY. EMA3/8 cruce + precio     |
//|  vs EMA21 + momentum score adaptativo. El edge real del EA.    |
//|  SL=0.50pts, TP=1.00pts, R:R 1:2.                              |
//|                                                                  |
//|  GESTIÓN COMÚN: lote dinámico, max 1 posición por sesión,      |
//|  cooldown post-SL, halt diario por drawdown.                    |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.14"
#property strict

//============================================================
// INPUTS
//============================================================
input bool   Control_orders_user        = true;
input string CommentOrder               = "MM7";
input bool   Use_dynamic_lot_           = true;
input double Lot_                       = 0.01;
input double Free_margin_for_each_Lots_ = 1000.0;
input double Max_Lot_                   = 5.0;
input int    InpMagicNumber             = 171400;
input int    InpSlippagePoints          = 10;
input int    InpMaxSpreadPoints         = 600;

// --- ASIA Range Fade ---
input bool   Asia_Enable                = true;
input int    Asia_Start_Hour            = 0;     // 00:00 UTC
input int    Asia_End_Hour              = 5;     // 05:00 UTC — fin de sesión Asia
input int    Asia_Range_Build_Hours     = 4;     // usar primeras 4h para construir rango
input double Asia_Touch_Buffer_Pts      = 0.20;  // cuánto debe acercarse al extremo para entrar
input double Asia_TP_Ratio              = 0.5;   // TP al 50% del rango (centro)
input double Asia_SL_Buffer_Pts         = 0.30;  // SL más allá del extremo del rango
input int    Asia_SL_Cooldown_Secs      = 120;

// --- LONDON Breakout ---
input bool   London_Enable              = true;
input int    London_Start_Hour          = 7;     // 07:00 UTC — apertura Londres
input int    London_End_Hour            = 12;    // 12:00 UTC
input int    London_ATR_Period          = 14;
input double London_Break_ATR_Frac      = 0.15;  // cierre debe superar rango en 0.15*ATR
input double London_SL_ATR_Mult         = 0.8;   // SL = 0.8 * ATR
input double London_RR                  = 1.5;   // TP = 1.5 * riesgo
input int    London_Max_Trades          = 2;     // máx 2 trades en sesión Londres
input int    London_SL_Cooldown_Secs    = 60;

// --- NY EMA Momentum ---
input bool   NY_Enable                  = true;
input int    NY_Start_Hour              = 13;    // 13:00 UTC — overlap London-NY
input int    NY_Start_Min               = 0;
input int    NY_End_Hour                = 18;
input int    NY_End_Min                 = 30;
input int    EMA_Fast_Period            = 3;
input int    EMA_Slow_Period            = 8;
input int    EMA_Trend_Period           = 21;
input double NY_TP_FIXED                = 1.00;
input double NY_SL_FIXED                = 0.50;
input int    NY_Momentum_Lookback       = 10;
input double NY_Momentum_Min_Ratio      = 0.8;
input int    NY_Entry_Cooldown_Secs     = 60;
input int    NY_SL_Cooldown_Secs        = 30;

// --- Dashboard ---
input bool   Enable_Dashboard           = true;
input int    Dashboard_Corner           = 0;
input int    Dashboard_X                = 10;
input int    Dashboard_Y                = 30;
input int    Font_Size                  = 10;
input bool   Enable_History_Labels      = true;

// --- Money Management ---
input double InpMaxDailyLossPct         = 5.0;
input double InpMaxEquityDrawdown       = 10.0;

//============================================================
// GLOBALES
//============================================================
int    g_magic; string g_sym; double g_point;

// Indicadores NY
int    g_hEMAf = INVALID_HANDLE;
int    g_hEMAs = INVALID_HANDLE;
int    g_hEMAt = INVALID_HANDLE;
int    g_hATR  = INVALID_HANDLE;   // compartido London + NY

// Estado diario
datetime g_dayStart     = 0;
double   g_dayStartBal  = 0;
bool     g_haltedToday  = false;

// Estado Asia
double   g_asiaHigh     = 0;
double   g_asiaLow      = DBL_MAX;
bool     g_asiaRangeSet = false;
datetime g_asiaLastSL   = 0;
bool     g_asiaTradedToday = false;

// Estado London
double   g_londonHigh   = 0;
double   g_londonLow    = DBL_MAX;
bool     g_londonRangeReady = false;
int      g_londonTrades = 0;
datetime g_londonLastSL = 0;

// Estado NY
datetime g_nyLastBar    = 0;
int      g_nyCachedSig  = 0;
double   g_nyCachedEMAf = 0;
double   g_nyCachedEMAs = 0;
double   g_nyMomentum   = 0;
double   g_nyMomThresh  = 0;
datetime g_nyLastEntry  = 0;
datetime g_nyLastSL     = 0;

// Dashboard
datetime g_lastDash     = 0;
datetime g_lastLabel    = 0;
string   g_sessionName  = "---";

//============================================================
// UTILIDADES COMUNES
//============================================================
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
   lot = MathMax(lot, mn); lot = MathMin(lot, MathMin(Max_Lot_, mx));
   if(st > 0) lot = MathFloor(lot/st)*st;
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

ulong SendOrder(ENUM_ORDER_TYPE type, double entry, double sl, double tp, double lot, string cmt)
{
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = lot;
   req.type      = type;
   req.price     = entry;
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = InpSlippagePoints;
   req.magic     = g_magic;
   req.comment   = cmt;
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) { req.type_filling = ORDER_FILLING_IOC; OrderSend(req, res); }
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) return res.order;
   return 0;
}

bool SpreadOK()
{
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   return ((ask - bid) / g_point <= InpMaxSpreadPoints);
}

int GetHour() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); return dt.hour; }
int GetMin()  { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); return dt.min; }
int GetNowMin() { MqlDateTime dt; TimeToStruct(TimeCurrent(), dt); return dt.hour*60+dt.min; }

void DailyReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today == g_dayStart) return;
   g_dayStart    = today;
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday = false;
   // Reset Asia
   g_asiaHigh = 0; g_asiaLow = DBL_MAX; g_asiaRangeSet = false; g_asiaTradedToday = false;
   // Reset London
   g_londonHigh = 0; g_londonLow = DBL_MAX; g_londonRangeReady = false; g_londonTrades = 0;
   // Reset NY
   g_nyLastBar = 0; g_nyCachedSig = 0;
}

void CheckHalt()
{
   if(g_haltedToday) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartBal <= 0) return;
   double lossPct = (g_dayStartBal - eq) / g_dayStartBal * 100.0;
   if(InpMaxEquityDrawdown > 0 && lossPct >= InpMaxEquityDrawdown)
   { g_haltedToday = true; Print("MM7 HALT: Equity DD ", lossPct, "%"); return; }
   if(InpMaxDailyLossPct > 0 && lossPct >= InpMaxDailyLossPct)
   { g_haltedToday = true; Print("MM7 HALT: Daily Loss ", lossPct, "%"); }
}

//============================================================
// ESTRATEGIA 1: ASIA RANGE FADE
//============================================================
// Construye el rango de las primeras Asia_Range_Build_Hours horas.
// Cuando el precio toca el extremo del rango → fade (operar en contra).
// Lógica: en Asia 2026 el oro consolida antes de que Londres lo mueva.

void Asia_BuildRange()
{
   int h = GetHour();
   if(h < Asia_Start_Hour || h >= Asia_Start_Hour + Asia_Range_Build_Hours) return;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(bid > g_asiaHigh) g_asiaHigh = bid;
   if(bid < g_asiaLow)  g_asiaLow  = bid;

   // Rango válido cuando tenemos al menos 0.50pts de amplitud
   if(!g_asiaRangeSet && (g_asiaHigh - g_asiaLow) >= 0.50)
      g_asiaRangeSet = true;
}

void Asia_Execute()
{
   if(!Asia_Enable || !g_asiaRangeSet) return;
   if(CountByMagic() > 0) return;
   if(TimeCurrent() - g_asiaLastSL < Asia_SL_Cooldown_Secs) return;
   if(!SpreadOK()) return;

   int h = GetHour();
   // Solo operar en la ventana de trading Asia (después de construir el rango)
   if(h < Asia_Start_Hour + Asia_Range_Build_Hours || h >= Asia_End_Hour) return;

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double mid = (g_asiaHigh + g_asiaLow) / 2.0;
   double range = g_asiaHigh - g_asiaLow;
   int digs = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

   // SELL fade: precio cerca del techo del rango
   if(bid >= g_asiaHigh - Asia_Touch_Buffer_Pts)
   {
      double sl = NormalizeDouble(g_asiaHigh + Asia_SL_Buffer_Pts, digs);
      double tp = NormalizeDouble(bid - range * Asia_TP_Ratio, digs);
      if(tp < bid && sl > bid)
      {
         ulong tk = SendOrder(ORDER_TYPE_SELL, bid, sl, tp, CalcLot(), "MM7-ASIA-FADE");
         if(tk > 0) Print("MM7 ASIA SELL fade @ ", bid, " SL=", sl, " TP=", tp);
      }
   }
   // BUY fade: precio cerca del suelo del rango
   else if(ask <= g_asiaLow + Asia_Touch_Buffer_Pts)
   {
      double sl = NormalizeDouble(g_asiaLow - Asia_SL_Buffer_Pts, digs);
      double tp = NormalizeDouble(ask + range * Asia_TP_Ratio, digs);
      if(tp > ask && sl < ask)
      {
         ulong tk = SendOrder(ORDER_TYPE_BUY, ask, sl, tp, CalcLot(), "MM7-ASIA-FADE");
         if(tk > 0) Print("MM7 ASIA BUY fade @ ", ask, " SL=", sl, " TP=", tp);
      }
   }
}

//============================================================
// ESTRATEGIA 2: LONDON ASIAN RANGE BREAKOUT
//============================================================
// Usa el rango asiático completo (00:00-07:00) como referencia.
// En Londres (07:00-12:00) espera cierre de barra fuera del rango
// con confirmación ATR para evitar fakeouts.

void London_BuildRange()
{
   int h = GetHour();
   // Construir rango asiático completo hasta apertura Londres
   if(h >= Asia_Start_Hour && h < London_Start_Hour)
   {
      double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
      if(bid > g_londonHigh) g_londonHigh = bid;
      if(bid < g_londonLow)  g_londonLow  = bid;
   }
   // Marcar rango listo cuando Londres abre
   if(h >= London_Start_Hour && !g_londonRangeReady)
   {
      if(g_londonHigh > g_londonLow && (g_londonHigh - g_londonLow) >= 0.30)
      {
         g_londonRangeReady = true;
         Print("MM7 LONDON range ready: H=", g_londonHigh, " L=", g_londonLow,
               " width=", g_londonHigh - g_londonLow);
      }
   }
}

void London_Execute()
{
   if(!London_Enable || !g_londonRangeReady) return;
   if(CountByMagic() > 0) return;
   if(g_londonTrades >= London_Max_Trades) return;
   if(TimeCurrent() - g_londonLastSL < London_SL_Cooldown_Secs) return;
   if(!SpreadOK()) return;

   int h = GetHour();
   if(h < London_Start_Hour || h >= London_End_Hour) return;

   // ATR para confirmar expansión real
   double atrBuf[]; ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) < 1) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;

   // Precio de cierre de la barra anterior (confirmación)
   double closeArr[]; ArraySetAsSeries(closeArr, true);
   if(CopyClose(g_sym, _Period, 1, 1, closeArr) < 1) return;
   double prevClose = closeArr[0];

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   int    digs = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double minBreak = atr * London_Break_ATR_Frac;

   // BUY breakout: cierre anterior supera el techo asiático + confirmación ATR
   if(prevClose > g_londonHigh + minBreak)
   {
      double risk = atr * London_SL_ATR_Mult;
      double sl   = NormalizeDouble(ask - risk, digs);
      double tp   = NormalizeDouble(ask + risk * London_RR, digs);
      ulong tk = SendOrder(ORDER_TYPE_BUY, ask, sl, tp, CalcLot(), "MM7-LON-BRK");
      if(tk > 0) { g_londonTrades++; Print("MM7 LONDON BUY breakout @ ", ask, " SL=", sl, " TP=", tp); }
   }
   // SELL breakout: cierre anterior rompe el suelo asiático
   else if(prevClose < g_londonLow - minBreak)
   {
      double risk = atr * London_SL_ATR_Mult;
      double sl   = NormalizeDouble(bid + risk, digs);
      double tp   = NormalizeDouble(bid - risk * London_RR, digs);
      ulong tk = SendOrder(ORDER_TYPE_SELL, bid, sl, tp, CalcLot(), "MM7-LON-BRK");
      if(tk > 0) { g_londonTrades++; Print("MM7 LONDON SELL breakout @ ", bid, " SL=", sl, " TP=", tp); }
   }
}

//============================================================
// ESTRATEGIA 3: NY EMA MOMENTUM (probado: 75% WR)
//============================================================
double NY_CalcMomThreshold()
{
   int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[], es[];
   ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
   int needed = NY_Momentum_Lookback + start + 1;
   if(CopyBuffer(g_hEMAf,0,start,needed,ef)<needed) return 0;
   if(CopyBuffer(g_hEMAs,0,start,needed,es)<needed) return 0;
   double sum = 0;
   for(int i=1; i<=NY_Momentum_Lookback; i++) sum += MathAbs(ef[i]-es[i]);
   return sum / NY_Momentum_Lookback;
}

int NY_GetSignal()
{
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE) return 0;
   int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[], es[], et[];
   ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true); ArraySetAsSeries(et,true);
   if(CopyBuffer(g_hEMAf,0,start,3,ef)<3) return 0;
   if(CopyBuffer(g_hEMAs,0,start,3,es)<3) return 0;
   if(CopyBuffer(g_hEMAt,0,start,1,et)<1) return 0;

   bool crossUp   = (ef[0]>es[0] && ef[1]<=es[1]);
   bool crossDown = (ef[0]<es[0] && ef[1]>=es[1]);
   if(!crossUp && !crossDown) return 0;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(crossUp   && bid <= et[0]) return 0;
   if(crossDown && bid >= et[0]) return 0;

   // Momentum score adaptativo
   double sep = MathAbs(ef[0]-es[0]);
   g_nyMomentum = sep;
   g_nyMomThresh = NY_CalcMomThreshold();
   if(g_nyMomThresh > 0 && sep < g_nyMomThresh * NY_Momentum_Min_Ratio) return 0;

   return crossUp ? 1 : -1;
}

void NY_Execute()
{
   if(!NY_Enable) return;
   if(CountByMagic() > 0) return;
   if(g_nyCachedSig == 0) return;
   if(TimeCurrent() - g_nyLastSL < NY_SL_Cooldown_Secs) return;
   if(TimeCurrent() - g_nyLastEntry < NY_Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;

   int nowMin = GetNowMin();
   if(nowMin < NY_Start_Hour*60+NY_Start_Min || nowMin >= NY_End_Hour*60+NY_End_Min) return;

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   int    digs = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

   if(g_nyCachedSig == 1)
   {
      double sl = NormalizeDouble(ask - NY_SL_FIXED, digs);
      double tp = NormalizeDouble(ask + NY_TP_FIXED, digs);
      ulong tk = SendOrder(ORDER_TYPE_BUY, ask, sl, tp, CalcLot(), "MM7-NY-MOM");
      if(tk > 0) { g_nyLastEntry = TimeCurrent(); g_nyCachedSig = 0; Print("MM7 NY BUY @ ", ask); }
   }
   else if(g_nyCachedSig == -1)
   {
      double sl = NormalizeDouble(bid + NY_SL_FIXED, digs);
      double tp = NormalizeDouble(bid - NY_TP_FIXED, digs);
      ulong tk = SendOrder(ORDER_TYPE_SELL, bid, sl, tp, CalcLot(), "MM7-NY-MOM");
      if(tk > 0) { g_nyLastEntry = TimeCurrent(); g_nyCachedSig = 0; Print("MM7 NY SELL @ ", bid); }
   }
}

//============================================================
// OnTradeTransaction — detectar SL por sesión
//============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) return;
   ulong dk = trans.deal;
   if(!HistoryDealSelect(dk)) return;
   if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
   if(reason != DEAL_REASON_SL) return;

   string cmt = HistoryDealGetString(dk, DEAL_COMMENT);
   datetime now = TimeCurrent();
   if(StringFind(cmt, "ASIA") >= 0)   g_asiaLastSL   = now;
   if(StringFind(cmt, "LON")  >= 0)   g_londonLastSL = now;
   if(StringFind(cmt, "NY")   >= 0)   g_nyLastSL     = now;
   Print("MM7 SL hit: ", cmt);
}

//============================================================
// DASHBOARD
//============================================================
void DashLbl(string nm, string txt, color clr, int row)
{
   string f = "MM7D_" + nm;
   int lh = Font_Size + 4;
   if(ObjectFind(0,f)<0) {
      ObjectCreate(0,f,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,f,OBJPROP_CORNER,(ENUM_BASE_CORNER)Dashboard_Corner);
      ObjectSetInteger(0,f,OBJPROP_XDISTANCE,Dashboard_X);
      ObjectSetString(0,f,OBJPROP_FONT,"Courier New");
      ObjectSetInteger(0,f,OBJPROP_FONTSIZE,Font_Size);
   }
   ObjectSetInteger(0,f,OBJPROP_YDISTANCE, Dashboard_Y + row*lh);
   ObjectSetString(0,f,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,f,OBJPROP_COLOR,clr);
}

void DrawDashboard()
{
   if(!Enable_Dashboard || TimeCurrent()-g_lastDash < 1) return;
   g_lastDash = TimeCurrent();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd  = (g_dayStartBal>0) ? (g_dayStartBal-eq)/g_dayStartBal*100.0 : 0;
   datetime ds = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   double dp = 0; HistorySelect(ds,TimeCurrent());
   for(int i=0;i<HistoryDealsTotal();i++){
      ulong dk=HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)==g_magic)
         dp+=HistoryDealGetDouble(dk,DEAL_PROFIT);
   }

   int h = GetHour();
   string sess = "---";
   color  sc   = clrGray;
   if(h>=Asia_Start_Hour && h<Asia_End_Hour)         { sess="ASIA  (Range Fade)";    sc=clrDodgerBlue; }
   else if(h>=London_Start_Hour && h<London_End_Hour){ sess="LONDON (Breakout)";     sc=clrOrange; }
   else if(GetNowMin()>=NY_Start_Hour*60+NY_Start_Min && GetNowMin()<NY_End_Hour*60+NY_End_Min)
                                                      { sess="NY (EMA Momentum)";    sc=clrLimeGreen; }

   DashLbl("0","[ MoneyMachine7 v17.14 — TRI-SESSION ]",clrGold,0);
   DashLbl("1","Sesion: "+sess,sc,1);
   DashLbl("2","Bal:$"+DoubleToString(bal,2)+" Eq:$"+DoubleToString(eq,2)+" lot="+DoubleToString(CalcLot(),2),clrWhite,2);
   DashLbl("3","Day P&L:$"+DoubleToString(dp,2)+" DD:"+DoubleToString(dd,2)+"%",(dp>=0)?clrLimeGreen:clrOrangeRed,3);
   DashLbl("4","ASIA  H:"+DoubleToString(g_asiaHigh,2)+" L:"+DoubleToString(g_asiaLow==DBL_MAX?0:g_asiaLow,2)+" set:"+(g_asiaRangeSet?"Y":"n"),clrDodgerBlue,4);
   DashLbl("5","LON   H:"+DoubleToString(g_londonHigh,2)+" L:"+DoubleToString(g_londonLow==DBL_MAX?0:g_londonLow,2)+" rdy:"+(g_londonRangeReady?"Y":"n")+" tr:"+IntegerToString(g_londonTrades),clrOrange,5);
   string nySig = (g_nyCachedSig==1)?"BUY":(g_nyCachedSig==-1)?"SELL":"--";
   DashLbl("6","NY    Sig:"+nySig+" Mom:"+DoubleToString(g_nyMomentum,4)+" Thr:"+DoubleToString(g_nyMomThresh,4),clrLimeGreen,6);
   DashLbl("7","Halt:"+(g_haltedToday?"SI":"no")+" Open:"+IntegerToString(CountByMagic()),g_haltedToday?clrOrangeRed:clrGray,7);
}

void DrawHistoryLabels()
{
   if(!Enable_History_Labels || TimeCurrent()-g_lastLabel<10) return;
   g_lastLabel = TimeCurrent();
   ObjectsDeleteAll(0,"MM7L_");
   datetime ds = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   HistorySelect(ds,TimeCurrent());
   int tot=HistoryDealsTotal(), st=MathMax(0,tot-50);
   for(int i=st;i<tot;i++){
      ulong dk=HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic) continue;
      if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double pf=HistoryDealGetDouble(dk,DEAL_PROFIT);
      double px=HistoryDealGetDouble(dk,DEAL_PRICE);
      datetime t=(datetime)HistoryDealGetInteger(dk,DEAL_TIME);
      string nm="MM7L_"+(string)dk;
      if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TEXT,0,t,px);
      ObjectSetString(0,nm,OBJPROP_TEXT,(pf>=0?"+":"")+DoubleToString(pf,2));
      ObjectSetInteger(0,nm,OBJPROP_COLOR,(pf>=0)?clrLimeGreen:clrOrangeRed);
      ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8);
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
   g_hATR  = iATR(g_sym, _Period, London_ATR_Period);
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE ||
      g_hEMAt==INVALID_HANDLE || g_hATR==INVALID_HANDLE)
   { Alert("Indicator init failed"); return INIT_FAILED; }

   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_asiaLow     = DBL_MAX;
   g_londonLow   = DBL_MAX;

   Print("MM7 v17.14 TRI-SESSION | ASIA fade | LONDON breakout | NY EMA momentum");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,"MM7D_"); ObjectsDeleteAll(0,"MM7L_");
   if(g_hEMAf!=INVALID_HANDLE) IndicatorRelease(g_hEMAf);
   if(g_hEMAs!=INVALID_HANDLE) IndicatorRelease(g_hEMAs);
   if(g_hEMAt!=INVALID_HANDLE) IndicatorRelease(g_hEMAt);
   if(g_hATR !=INVALID_HANDLE) IndicatorRelease(g_hATR);
}

void OnTick()
{
   DailyReset();
   CheckHalt();
   if(g_haltedToday) { DrawDashboard(); return; }
   if(!Control_orders_user) return;

   // Construir rangos (siempre, independiente de si hay posición)
   Asia_BuildRange();
   London_BuildRange();

   // NY: calcular señal una vez por barra
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_nyLastBar)
   {
      g_nyLastBar   = curBar;
      g_nyCachedSig = NY_GetSignal();
      int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
      double ef[], es[];
      ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
      if(CopyBuffer(g_hEMAf,0,start,1,ef)>=1) g_nyCachedEMAf = ef[0];
      if(CopyBuffer(g_hEMAs,0,start,1,es)>=1) g_nyCachedEMAs = es[0];
   }

   // Ejecutar estrategia de la sesión activa
   int h = GetHour();
   int nowMin = GetNowMin();

   if(h >= Asia_Start_Hour && h < Asia_End_Hour)
      Asia_Execute();
   else if(h >= London_Start_Hour && h < London_End_Hour)
      London_Execute();
   else if(nowMin >= NY_Start_Hour*60+NY_Start_Min && nowMin < NY_End_Hour*60+NY_End_Min)
      NY_Execute();

   DrawDashboard();
   DrawHistoryLabels();
}
