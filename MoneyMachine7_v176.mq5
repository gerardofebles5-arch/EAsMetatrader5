//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.6 — FILTRO H1 + ARQUITECTURA MULTI-TF ROBUSTA             |
//|                                                                  |
//|  HISTORIAL DE BACKTESTS:                                         |
//|  v17.3: Net=-$2.65  | PF=0.938 | WR=35% | 20 trades            |
//|  v17.4: Net=+$14.70 | PF=2.51  | WR=57% |  7 trades ← MEJOR   |
//|  v17.5: Net=+$0.30  | PF=1.02  | WR=33% |  6 trades ← PEOR    |
//|                                                                  |
//|  DIAGNÓSTICO v17.5:                                              |
//|  5 de 6 trades fueron BUYs en día bajista (5380→5300)           |
//|  EMA50(M5) no filtró los BUYs porque en sesión 08-17 el precio  |
//|  estaba temporalmente sobre EMA50(M5) en rebotes alcistas.      |
//|  El filtro M5 es demasiado reactivo — cambia con cada rebote.   |
//|                                                                  |
//|  SOLUCIÓN v17.6:                                                 |
//|  FIX 1 — FILTRO H1: EMA(21) en H1                              |
//|    Tendencia del día real. H1 no cambia con rebotes de M5.      |
//|    bid > EMA21(H1) → solo BUYs                                  |
//|    bid < EMA21(H1) → solo SELLs                                 |
//|    En el día bajista 5380→5300: EMA21(H1) habría estado         |
//|    por encima del precio → solo SELLs → WR=100% en v17.5        |
//|  FIX 2 — CONFIRMAR CON M5: EMA50(M5) debe coincidir con H1     |
//|    Doble confirmación: H1 da dirección, M5 confirma momentum    |
//|    Si H1 dice SELL pero M5 dice BUY → no operar                 |
//|  FIX 3 — SESIÓN AMPLIADA: 05:00-21:00                           |
//|    La restricción 08-17 redujo trades sin mejorar calidad        |
//|  FIX 4 — DISTANCIA EMA21 M1: 0.05pts (era 0.10)                |
//|    0.10 era demasiado restrictivo, perdía entradas válidas       |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.60"
#property strict

// +++ Core +++
input bool   Control_orders_user         = true;
input int    Max_Positions               = 1;
input string CommentOrder                = "MM7";
input double Lot_                        = 0.01;
input bool   Use_dynamic_lot_            = true;
input double Free_margin_for_each_Lots_  = 1000.0;
input double Max_Lot_                    = 5.0;
// +++ Señal M1 — EMA cruce +++
input int    EMA_Fast_Period             = 3;
input int    EMA_Slow_Period             = 8;
input int    EMA_Trend_M1_Period         = 21;
input double EMA_Trend_MinDist           = 0.05;   // FIX 4: 0.10→0.05
// +++ Filtro tendencia H1 (FIX 1) +++
input bool   Enable_H1_Filter           = true;
input int    EMA_H1_Period               = 21;     // EMA21 H1 = tendencia del día
// +++ Filtro confirmación M5 (FIX 2) +++
input bool   Enable_M5_Filter           = true;
input int    EMA_M5_Trend_Period         = 50;
// +++ Salida — SL/TP broker +++
input double MM7_TP_FIXED                = 1.00;
input double MM7_SL_FIXED                = 0.50;
// +++ Entry Control +++
input int    Entry_Cooldown_Secs         = 5;
input int    SL_Cooldown_Secs            = 30;
input int    InpMaxSpreadPoints          = 600;
input int    InpSlippagePoints           = 10;
input int    InpMagicNumber              = 700000;
// +++ Schedule (FIX 3: ampliada) +++
input bool   Trade_Monday                = true;
input int    Monday_Start_Hour           = 5;
input int    Monday_End_Hour             = 21;
input bool   Trade_Tuesday               = true;
input int    Tuesday_Start_Hour          = 5;
input int    Tuesday_End_Hour            = 21;
input bool   Trade_Wednesday             = true;
input int    Wednesday_Start_Hour        = 5;
input int    Wednesday_End_Hour          = 21;
input bool   Trade_Thursday              = true;
input int    Thursday_Start_Hour         = 5;
input int    Thursday_End_Hour           = 21;
input bool   Trade_Friday                = true;
input int    Friday_Start_Hour           = 5;
input int    Friday_End_Hour             = 18;
input bool   Trade_Saturday              = false;
input int    Saturday_Start_Hour         = 0;
input int    Saturday_End_Hour           = 0;
input bool   Trade_Sunday                = false;
input int    Sunday_Start_Hour           = 0;
input int    Sunday_End_Hour             = 0;
// +++ Money Management +++
input double Daily_Profit_Target_USD     = 1000000.0;
input double Daily_Loss_Limit_USD        = 500000.0;
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

// Handles M1
int      g_hEMAf    = INVALID_HANDLE;
int      g_hEMAs    = INVALID_HANDLE;
int      g_hEMAt    = INVALID_HANDLE;
int      g_hATR     = INVALID_HANDLE;

// Handle H1 (FIX 1)
int      g_hH1Trend = INVALID_HANDLE;

// Handle M5 (FIX 2)
int      g_hM5Trend = INVALID_HANDLE;

datetime g_lastEntryTime       = 0;
datetime g_lastOpenAttemptTime = 0;
datetime g_lastBarTime         = 0;
datetime g_lastSLTime          = 0;
datetime g_dayStart            = 0;
double   g_dayStartBal         = 0;
bool     g_haltedToday         = false;
datetime g_lastDashTime        = 0;
datetime g_lastLabelTime       = 0;

// Cache por barra
int      g_cachedSig     = 0;
double   g_cachedEMAf    = 0;
double   g_cachedEMAs    = 0;
double   g_cachedEMAt    = 0;
int      g_cachedH1Trend = 0;   // 1=alcista, -1=bajista
int      g_cachedM5Trend = 0;


//============================================================
// UTILIDADES
//============================================================
double GetATR()
{
   if(g_hATR == INVALID_HANDLE) return 0.50;
   double b[]; ArraySetAsSeries(b, true);
   if(CopyBuffer(g_hATR, 0, 1, 1, b) < 1) return 0.50;
   return (b[0] > 0) ? b[0] : 0.50;
}

// FIX 1: Tendencia H1 — EMA21(H1)
// Retorna 1 si bid > EMA21(H1), -1 si bid < EMA21(H1)
int GetH1Trend()
{
   if(!Enable_H1_Filter) return 0;
   if(g_hH1Trend == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   // Barra 1 de H1 = barra H1 cerrada más reciente (más estable)
   if(CopyBuffer(g_hH1Trend, 0, 1, 1, buf) < 1) return 0;
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   return (bid > buf[0]) ? 1 : -1;
}

// FIX 2: Confirmación M5 — EMA50(M5)
int GetM5Trend()
{
   if(!Enable_M5_Filter) return 0;
   if(g_hM5Trend == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hM5Trend, 0, 1, 1, buf) < 1) return 0;
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   return (bid > buf[0]) ? 1 : -1;
}

// Señal principal: EMA cruce M1 + EMA21 M1 + H1 + M5
int GetSignal()
{
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE) return 0;

   int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;

   double ef[], es[], et[];
   ArraySetAsSeries(ef, true); ArraySetAsSeries(es, true); ArraySetAsSeries(et, true);
   if(CopyBuffer(g_hEMAf, 0, start, 3, ef) < 3) return 0;
   if(CopyBuffer(g_hEMAs, 0, start, 3, es) < 3) return 0;
   if(CopyBuffer(g_hEMAt, 0, start, 1, et) < 1) return 0;

   double ef_now  = ef[0], ef_prev = ef[1];
   double es_now  = es[0], es_prev = es[1];
   double et_now  = et[0];
   double bid     = SymbolInfoDouble(g_sym, SYMBOL_BID);

   bool crossUp   = (ef_now > es_now && ef_prev <= es_prev);
   bool crossDown = (ef_now < es_now && ef_prev >= es_prev);
   if(!crossUp && !crossDown) return 0;

   int dir = crossUp ? 1 : -1;

   // FIX 4: distancia mínima de EMA21 M1
   double dist = (bid - et_now) * dir;
   if(dist < EMA_Trend_MinDist) return 0;

   // FIX 1: filtro H1 — tendencia del día
   if(Enable_H1_Filter)
   {
      int h1trend = GetH1Trend();
      if(h1trend != 0 && h1trend != dir) return 0;
   }

   // FIX 2: confirmación M5 — debe coincidir con H1
   if(Enable_M5_Filter)
   {
      int m5trend = GetM5Trend();
      if(m5trend != 0 && m5trend != dir) return 0;
   }

   return dir;
}

bool IsScheduleAllowed()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week, h = dt.hour;
   if(dow==1) return Trade_Monday    && h>=Monday_Start_Hour    && h<Monday_End_Hour;
   if(dow==2) return Trade_Tuesday   && h>=Tuesday_Start_Hour   && h<Tuesday_End_Hour;
   if(dow==3) return Trade_Wednesday && h>=Wednesday_Start_Hour && h<Wednesday_End_Hour;
   if(dow==4) return Trade_Thursday  && h>=Thursday_Start_Hour  && h<Thursday_End_Hour;
   if(dow==5) return Trade_Friday    && h>=Friday_Start_Hour    && h<Friday_End_Hour;
   if(dow==6) return Trade_Saturday  && h>=Saturday_Start_Hour  && h<Saturday_End_Hour;
   if(dow==0) return Trade_Sunday    && h>=Sunday_Start_Hour    && h<Sunday_End_Hour;
   return false;
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
   lot = MathMax(lot, mn); lot = MathMin(lot, MathMin(Max_Lot_, mx));
   if(st > 0) lot = MathFloor(lot / st) * st;
   return NormalizeDouble(lot, 2);
}

int CountByMagic()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == g_magic) n++;
   }
   return n;
}

//============================================================
// OPEN ORDER — SL/TP REALES en broker
//============================================================
ulong OpenOrder(ENUM_ORDER_TYPE type, int dir)
{
   double lot   = CalcLot();
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

   double tp_price = NormalizeDouble(entry + dir * MM7_TP_FIXED, digs);
   double sl_price = NormalizeDouble(entry - dir * MM7_SL_FIXED, digs);

   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = g_sym;
   req.volume    = lot;
   req.type      = type;
   req.price     = entry;
   req.sl        = sl_price;
   req.tp        = tp_price;
   req.deviation = InpSlippagePoints;
   req.magic     = g_magic;
   req.comment   = CommentOrder;
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
   return 0;
}

//============================================================
// DAILY RESET & HALT
//============================================================
void DailyReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today == g_dayStart) return;
   g_dayStart    = today;
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday = false;
   g_lastEntryTime = 0; g_lastBarTime = 0; g_cachedSig = 0;
}

void CheckHaltConditions()
{
   if(g_haltedToday) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxEquityDrawdown > 0 && g_dayStartBal > 0)
      if((g_dayStartBal - eq) / g_dayStartBal * 100.0 >= InpMaxEquityDrawdown)
      { g_haltedToday = true; Print("MM7 HALT: MaxEquityDrawdown"); return; }
   if(InpMaxDailyLossPct > 0 && g_dayStartBal > 0)
      if((g_dayStartBal - eq) / g_dayStartBal * 100.0 >= InpMaxDailyLossPct)
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
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
   if(reason == DEAL_REASON_SL)
   {
      g_lastSLTime = TimeCurrent();
      Print("MM7 SL hit → cooldown ", SL_Cooldown_Secs, "s");
   }
}


//============================================================
// DASHBOARD
//============================================================
void DashLbl(string nm, string txt, color clr, int oy, int x, int y, ENUM_BASE_CORNER c, int fn)
{
   string f = "MM7D_" + nm;
   if(ObjectFind(0, f) < 0) {
      ObjectCreate(0, f, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, f, OBJPROP_CORNER, c);
      ObjectSetInteger(0, f, OBJPROP_XDISTANCE, x);
      ObjectSetString(0, f, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, f, OBJPROP_FONTSIZE, fn);
   }
   ObjectSetInteger(0, f, OBJPROP_YDISTANCE, y + oy);
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
   int x = Dashboard_X_Offset, y = Dashboard_Y_Offset, fn = Font_size_Result, lh = fn + 4;
   ENUM_BASE_CORNER co = (ENUM_BASE_CORNER)Dashboard_Corner;

   DashLbl("0", "[ MoneyMachine7 v17.6 ]", clrGold, 0*lh, x, y, co, fn);
   string h1str = (g_cachedH1Trend==1)?"H1:UP":(g_cachedH1Trend==-1)?"H1:DN":"H1:--";
   string m5str = (g_cachedM5Trend==1)?"M5:UP":(g_cachedM5Trend==-1)?"M5:DN":"M5:--";
   DashLbl("1", h1str+" "+m5str+" EMA("+IntegerToString(EMA_Fast_Period)+"/"+IntegerToString(EMA_Slow_Period)+"/"+IntegerToString(EMA_Trend_M1_Period)+")", clrCyan, 1*lh, x, y, co, fn);
   DashLbl("2", "Bal :$"+DoubleToString(bal,2)+" lot="+DoubleToString(CalcLot(),2), clrWhite, 2*lh, x, y, co, fn);
   DashLbl("3", "Eq  :$"+DoubleToString(eq,2)+" Open:"+IntegerToString(CountByMagic()), clrWhite, 3*lh, x, y, co, fn);
   DashLbl("4", "DD  :"+DoubleToString(dd,2)+"%", (dd>2)?clrOrangeRed:clrLimeGreen, 4*lh, x, y, co, fn);
   DashLbl("5", "Day :$"+DoubleToString(dp,2), (dp>=0)?clrLimeGreen:clrOrangeRed, 5*lh, x, y, co, fn);
   string rr = "TP:"+DoubleToString(MM7_TP_FIXED,2)+"pts SL:"+DoubleToString(MM7_SL_FIXED,2)+"pts R:R=1:"+DoubleToString(MM7_TP_FIXED/MM7_SL_FIXED,2);
   DashLbl("6", rr, clrCyan, 6*lh, x, y, co, fn);
   string sig_str = (g_cachedSig==1)?"BUY":(g_cachedSig==-1)?"SELL":"--";
   DashLbl("7", "Sig:"+sig_str+" EMAf:"+DoubleToString(g_cachedEMAf,2)+" EMAs:"+DoubleToString(g_cachedEMAs,2), clrWhite, 7*lh, x, y, co, fn);
   datetime now = TimeCurrent();
   bool inSLCool = (now - g_lastSLTime < SL_Cooldown_Secs);
   int  cdSecs   = inSLCool ? (int)(g_lastSLTime + SL_Cooldown_Secs - now)
                             : (int)(g_lastEntryTime + Entry_Cooldown_Secs - now);
   string cdStr  = (cdSecs > 0) ? (inSLCool?"SL+":"C")+IntegerToString(cdSecs) : "OK";
   DashLbl("8", "Cool:"+cdStr+" ATR:"+DoubleToString(GetATR(),2)+" Halt:"+(g_haltedToday?"Y":"n"), clrGray, 8*lh, x, y, co, fn);
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

   // Handles M1
   g_hEMAf = iMA(g_sym, _Period, EMA_Fast_Period,     0, MODE_EMA, PRICE_CLOSE);
   g_hEMAs = iMA(g_sym, _Period, EMA_Slow_Period,     0, MODE_EMA, PRICE_CLOSE);
   g_hEMAt = iMA(g_sym, _Period, EMA_Trend_M1_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE)
   { Alert("EMA M1 failed"); return INIT_FAILED; }

   // Handle H1 (FIX 1)
   g_hH1Trend = iMA(g_sym, PERIOD_H1, EMA_H1_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hH1Trend == INVALID_HANDLE) { Alert("EMA H1 failed"); return INIT_FAILED; }

   // Handle M5 (FIX 2)
   g_hM5Trend = iMA(g_sym, PERIOD_M5, EMA_M5_Trend_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hM5Trend == INVALID_HANDLE) { Alert("EMA M5 failed"); return INIT_FAILED; }

   g_hATR = iATR(g_sym, _Period, 7);
   if(g_hATR == INVALID_HANDLE) { Alert("ATR failed"); return INIT_FAILED; }

   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));

   Print("MM7 v17.6 | EMA(",EMA_Fast_Period,"/",EMA_Slow_Period,"/",EMA_Trend_M1_Period,") M1 | EMA",EMA_H1_Period,"(H1) | EMA",EMA_M5_Trend_Period,"(M5) | TP=",MM7_TP_FIXED," SL=",MM7_SL_FIXED," | Cool=",Entry_Cooldown_Secs,"s SLCool=",SL_Cooldown_Secs,"s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "MM7D_");
   ObjectsDeleteAll(0, "MM7L_");
   if(g_hEMAf    != INVALID_HANDLE) IndicatorRelease(g_hEMAf);
   if(g_hEMAs    != INVALID_HANDLE) IndicatorRelease(g_hEMAs);
   if(g_hEMAt    != INVALID_HANDLE) IndicatorRelease(g_hEMAt);
   if(g_hH1Trend != INVALID_HANDLE) IndicatorRelease(g_hH1Trend);
   if(g_hM5Trend != INVALID_HANDLE) IndicatorRelease(g_hM5Trend);
   if(g_hATR     != INVALID_HANDLE) IndicatorRelease(g_hATR);
}

void OnTick()
{
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime)
   {
      g_lastBarTime    = curBar;
      g_cachedSig      = GetSignal();
      g_cachedH1Trend  = GetH1Trend();
      g_cachedM5Trend  = GetM5Trend();

      int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
      double ef[], es[], et[];
      ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true); ArraySetAsSeries(et,true);
      if(CopyBuffer(g_hEMAf,0,start,1,ef)>=1) g_cachedEMAf = ef[0];
      if(CopyBuffer(g_hEMAs,0,start,1,es)>=1) g_cachedEMAs = es[0];
      if(CopyBuffer(g_hEMAt,0,start,1,et)>=1) g_cachedEMAt = et[0];
   }

   DrawDashboard();
   DrawHistoryLabels();

   if(g_cachedSig == 0) return;

   DailyReset();
   CheckHaltConditions();
   if(g_haltedToday) return;
   if(!IsScheduleAllowed()) return;
   if(!Control_orders_user) return;

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double spreadPts = (ask - bid) / g_point;
   if(spreadPts > InpMaxSpreadPoints) return;

   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(ds, TimeCurrent());
   double dp = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) == g_magic)
         dp += HistoryDealGetDouble(dk, DEAL_PROFIT);
   }
   if(Daily_Profit_Target_USD > 0 && dp >= Daily_Profit_Target_USD) return;
   if(Daily_Loss_Limit_USD    > 0 && dp <= -Daily_Loss_Limit_USD)   return;

   if(CountByMagic() >= Max_Positions) return;

   // Cooldown adaptativo
   datetime now = TimeCurrent();
   if(now - g_lastSLTime < SL_Cooldown_Secs) return;
   bool isLive = !(bool)MQLInfoInteger(MQL_TESTER);
   datetime cdRef = isLive ? g_lastOpenAttemptTime : g_lastEntryTime;
   if(now - cdRef < Entry_Cooldown_Secs) return;

   ENUM_ORDER_TYPE otype = (g_cachedSig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong tk = OpenOrder(otype, g_cachedSig);
   if(tk > 0)
   {
      g_lastEntryTime = now;
      if(isLive) g_lastOpenAttemptTime = now;
      g_cachedSig = 0;
   }
}
