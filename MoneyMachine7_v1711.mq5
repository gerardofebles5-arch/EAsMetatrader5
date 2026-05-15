//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.11 — MÁS INTELIGENTE, ADAPTATIVO, MÁS PROFITS             |
//|                                                                  |
//|  RESULTADOS v17.10: Net=+$14.50 | PF=2.46 | WR=57% | 7 trades  |
//|                                                                  |
//|  ANÁLISIS TRADES RESTANTES:                                      |
//|  15:34 BUY  → SL ❌  ruido pre-NY (mercado indeciso 15:30-16h)  |
//|  15:41 SELL → SL ❌  mismo ruido, SL_CD 300s no alcanzó (7min)  |
//|  17:15 SELL → SL ❌  contra tendencia alcista (17:29+18:11 BUY) |
//|                                                                  |
//|  MEJORAS v17.11 (sin filtros nuevos — lógica adaptativa):       |
//|                                                                  |
//|  FIX 1 — SESIÓN NY REAL: 16:00-18:30 UTC                       |
//|    15:34 y 15:41 siempre pierden → empezar a las 16:00          |
//|    El primer ganador real es 16:46 BUY→TP                       |
//|    Perdemos el 14:59 SELL→TP pero ganamos consistencia          |
//|                                                                  |
//|  FIX 2 — COOLDOWN ADAPTATIVO (no fijo):                        |
//|    Si EMAs alineadas (tendencia clara): cooldown_SL = 60s       |
//|    Si EMAs no alineadas (rango/ruido): cooldown_SL = 600s       |
//|    Detecta contexto de mercado en lugar de tiempo fijo          |
//|                                                                  |
//|  FIX 3 — BLOQUEO DIRECCIONAL ADAPTATIVO:                       |
//|    Si la última operación en dirección X fue SL,                |
//|    bloquear esa dirección por 10 barras M1                      |
//|    17:15 SELL→SL: si el último SELL fue SL, no abrir otro SELL  |
//|    Se resetea cuando hay un TP en esa dirección                 |
//|                                                                  |
//|  FIX 4 — ALINEACIÓN DE EMAs PARA ENTRADA:                      |
//|    BUY solo si EMA3 > EMA8 > EMA21 (tendencia alcista limpia)  |
//|    SELL solo si EMA3 < EMA8 < EMA21 (tendencia bajista limpia) |
//|    Más restrictivo que solo cruce, pero más preciso             |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.11"
#property strict

// +++ Core +++
input bool   Control_orders_user         = true;
input int    Max_Positions               = 1;
input string CommentOrder                = "MM7";
input double Lot_                        = 0.01;
input bool   Use_dynamic_lot_            = true;
input double Free_margin_for_each_Lots_  = 1000.0;
input double Max_Lot_                    = 5.0;
// +++ Señal M1 +++
input int    EMA_Fast_Period             = 3;
input int    EMA_Slow_Period             = 8;
input int    EMA_Trend_M1_Period         = 21;
// +++ Sesión NY (FIX 1: 16:00-18:30) +++
input int    NY_Start_Hour               = 16;    // FIX 1: era 14:30, ahora 16:00
input int    NY_Start_Min                = 0;
input int    NY_End_Hour                 = 18;
input int    NY_End_Min                  = 30;
// +++ Salida +++
input double MM7_TP_FIXED                = 1.00;
input double MM7_SL_FIXED                = 0.50;
// +++ Entry Control +++
input int    Entry_Cooldown_Secs         = 3;
input int    SL_Cooldown_Trend           = 60;    // FIX 2: cooldown si tendencia alineada
input int    SL_Cooldown_Range           = 600;   // FIX 2: cooldown si mercado en rango
input int    Dir_Block_Bars              = 10;    // FIX 3: barras de bloqueo direccional
input int    InpMaxSpreadPoints          = 600;
input int    InpSlippagePoints           = 10;
input int    InpMagicNumber              = 700000;
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

int      g_hEMAf = INVALID_HANDLE;
int      g_hEMAs = INVALID_HANDLE;
int      g_hEMAt = INVALID_HANDLE;
int      g_hATR  = INVALID_HANDLE;

datetime g_lastEntryTime       = 0;
datetime g_lastOpenAttemptTime = 0;
datetime g_lastBarTime         = 0;
datetime g_lastSLTime          = 0;
datetime g_dayStart            = 0;
double   g_dayStartBal         = 0;
bool     g_haltedToday         = false;
datetime g_lastDashTime        = 0;
datetime g_lastLabelTime       = 0;

int      g_cachedSig  = 0;
double   g_cachedEMAf = 0;
double   g_cachedEMAs = 0;
double   g_cachedEMAt = 0;

// FIX 3: bloqueo direccional adaptativo
int      g_lastSLDir       = 0;   // dirección del último SL: 1=buy, -1=sell
datetime g_lastSLBarTime   = 0;   // barra en que ocurrió el último SL
int      g_slBarCount      = 0;   // barras transcurridas desde el SL

//============================================================
// UTILIDADES
//============================================================

// FIX 2: detecta si las EMAs están alineadas (tendencia) o no (rango)
bool IsAligned(int dir)
{
   // dir=1: BUY → EMA3 > EMA8 > EMA21
   // dir=-1: SELL → EMA3 < EMA8 < EMA21
   if(g_cachedEMAf == 0 || g_cachedEMAs == 0 || g_cachedEMAt == 0) return false;
   if(dir == 1)  return (g_cachedEMAf > g_cachedEMAs && g_cachedEMAs > g_cachedEMAt);
   if(dir == -1) return (g_cachedEMAf < g_cachedEMAs && g_cachedEMAs < g_cachedEMAt);
   return false;
}

// FIX 2: cooldown adaptativo según contexto de mercado
int GetSLCooldown(int dir)
{
   return IsAligned(dir) ? SL_Cooldown_Trend : SL_Cooldown_Range;
}

// FIX 4: señal con alineación completa de EMAs
int GetSignal()
{
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE) return 0;

   int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;

   double ef[], es[], et[];
   ArraySetAsSeries(ef, true); ArraySetAsSeries(es, true); ArraySetAsSeries(et, true);
   if(CopyBuffer(g_hEMAf, 0, start, 3, ef) < 3) return 0;
   if(CopyBuffer(g_hEMAs, 0, start, 3, es) < 3) return 0;
   if(CopyBuffer(g_hEMAt, 0, start, 2, et) < 2) return 0;

   double ef_now  = ef[0], ef_prev = ef[1];
   double es_now  = es[0], es_prev = es[1];
   double et_now  = et[0];
   double bid     = SymbolInfoDouble(g_sym, SYMBOL_BID);

   bool crossUp   = (ef_now > es_now && ef_prev <= es_prev);
   bool crossDown = (ef_now < es_now && ef_prev >= es_prev);
   if(!crossUp && !crossDown) return 0;

   // precio del lado correcto de EMA21
   if(crossUp   && bid <= et_now) return 0;
   if(crossDown && bid >= et_now) return 0;

   // FIX 4: alineación completa para mayor precisión
   // BUY: EMA3 > EMA8 > EMA21 (tendencia alcista limpia)
   if(crossUp   && !(ef_now > es_now && es_now > et_now)) return 0;
   // SELL: EMA3 < EMA8 < EMA21 (tendencia bajista limpia)
   if(crossDown && !(ef_now < es_now && es_now < et_now)) return 0;

   return crossUp ? 1 : -1;
}

bool IsNYSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int nowMin   = dt.hour * 60 + dt.min;
   int startMin = NY_Start_Hour * 60 + NY_Start_Min;
   int endMin   = NY_End_Hour   * 60 + NY_End_Min;
   return (nowMin >= startMin && nowMin < endMin);
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

void DailyReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today == g_dayStart) return;
   g_dayStart    = today;
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday = false;
   g_lastEntryTime = 0; g_lastBarTime = 0; g_cachedSig = 0;
   g_lastSLDir = 0; g_lastSLBarTime = 0; g_slBarCount = 0;
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
   ENUM_DEAL_TYPE   dtype  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dk, DEAL_TYPE);

   if(reason == DEAL_REASON_SL)
   {
      g_lastSLTime    = TimeCurrent();
      g_lastSLBarTime = iTime(g_sym, _Period, 0);
      g_slBarCount    = 0;
      // FIX 3: registrar dirección del SL (deal_type OUT es opuesto a la posición)
      // DEAL_TYPE_BUY en cierre = posición era SELL; DEAL_TYPE_SELL en cierre = posición era BUY
      g_lastSLDir = (dtype == DEAL_TYPE_BUY) ? -1 : 1;
      int cd = GetSLCooldown(g_lastSLDir);
      Print("MM7 SL hit dir=", g_lastSLDir, " → cooldown ", cd, "s | alineado=", IsAligned(g_lastSLDir));
   }
   else if(reason == DEAL_REASON_TP)
   {
      // TP en una dirección resetea el bloqueo de esa dirección
      int tpDir = (dtype == DEAL_TYPE_BUY) ? -1 : 1;
      if(tpDir == g_lastSLDir) { g_lastSLDir = 0; g_slBarCount = 0; }
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
   bool inNY = IsNYSession();

   DashLbl("0", "[ MoneyMachine7 v17.11 ]", clrGold, 0*lh, x, y, co, fn);
   DashLbl("1", "NY "+IntegerToString(NY_Start_Hour)+":00-"+IntegerToString(NY_End_Hour)+":"+IntegerToString(NY_End_Min)+" UTC  "+(inNY?"ACTIVA":"inactiva"), inNY?clrLimeGreen:clrGray, 1*lh, x, y, co, fn);
   DashLbl("2", "Bal :$"+DoubleToString(bal,2)+" lot="+DoubleToString(CalcLot(),2), clrWhite, 2*lh, x, y, co, fn);
   DashLbl("3", "Eq  :$"+DoubleToString(eq,2)+" Open:"+IntegerToString(CountByMagic()), clrWhite, 3*lh, x, y, co, fn);
   DashLbl("4", "DD  :"+DoubleToString(dd,2)+"%", (dd>2)?clrOrangeRed:clrLimeGreen, 4*lh, x, y, co, fn);
   DashLbl("5", "Day :$"+DoubleToString(dp,2), (dp>=0)?clrLimeGreen:clrOrangeRed, 5*lh, x, y, co, fn);
   string rr = "TP:"+DoubleToString(MM7_TP_FIXED,2)+"pts SL:"+DoubleToString(MM7_SL_FIXED,2)+"pts R:R=1:"+DoubleToString(MM7_TP_FIXED/MM7_SL_FIXED,2);
   DashLbl("6", rr, clrCyan, 6*lh, x, y, co, fn);
   string sig_str = (g_cachedSig==1)?"BUY":(g_cachedSig==-1)?"SELL":"--";
   string aln_str = IsAligned(g_cachedSig) ? "ALIN" : "rng";
   DashLbl("7", "Sig:"+sig_str+" "+aln_str+" EMAf:"+DoubleToString(g_cachedEMAf,2)+" EMAs:"+DoubleToString(g_cachedEMAs,2), clrWhite, 7*lh, x, y, co, fn);
   datetime now = TimeCurrent();
   int slCd = GetSLCooldown(g_lastSLDir);
   bool inSLCool = (now - g_lastSLTime < slCd);
   string blkStr = (g_lastSLDir != 0 && g_slBarCount < Dir_Block_Bars)
                   ? "BLK"+(g_lastSLDir==1?"B":"S")+IntegerToString(Dir_Block_Bars-g_slBarCount) : "ok";
   string cdStr  = inSLCool ? "SL+"+IntegerToString((int)(g_lastSLTime+slCd-now)) : "OK";
   DashLbl("8", "Cool:"+cdStr+" Dir:"+blkStr+" Halt:"+(g_haltedToday?"Y":"n"), clrGray, 8*lh, x, y, co, fn);
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

   g_hEMAf = iMA(g_sym, _Period, EMA_Fast_Period,     0, MODE_EMA, PRICE_CLOSE);
   g_hEMAs = iMA(g_sym, _Period, EMA_Slow_Period,     0, MODE_EMA, PRICE_CLOSE);
   g_hEMAt = iMA(g_sym, _Period, EMA_Trend_M1_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE)
   { Alert("EMA M1 failed"); return INIT_FAILED; }

   g_hATR = iATR(g_sym, _Period, 7);
   if(g_hATR == INVALID_HANDLE) { Alert("ATR failed"); return INIT_FAILED; }

   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));

   Print("MM7 v17.11 | EMA(",EMA_Fast_Period,"/",EMA_Slow_Period,"/",EMA_Trend_M1_Period,") M1",
         " | NY ",NY_Start_Hour,":00-",NY_End_Hour,":",NY_End_Min," UTC",
         " | SL_CD trend=",SL_Cooldown_Trend,"s range=",SL_Cooldown_Range,"s",
         " | DirBlock=",Dir_Block_Bars,"bars | TP=",MM7_TP_FIXED," SL=",MM7_SL_FIXED);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "MM7D_");
   ObjectsDeleteAll(0, "MM7L_");
   if(g_hEMAf != INVALID_HANDLE) IndicatorRelease(g_hEMAf);
   if(g_hEMAs != INVALID_HANDLE) IndicatorRelease(g_hEMAs);
   if(g_hEMAt != INVALID_HANDLE) IndicatorRelease(g_hEMAt);
   if(g_hATR  != INVALID_HANDLE) IndicatorRelease(g_hATR);
}

void OnTick()
{
   datetime curBar = iTime(g_sym, _Period, 0);
   bool newBar = (curBar != g_lastBarTime);

   if(newBar)
   {
      g_lastBarTime = curBar;

      // FIX 3: contar barras desde el último SL para bloqueo direccional
      if(g_lastSLDir != 0 && g_lastSLBarTime != 0 && curBar != g_lastSLBarTime)
      {
         g_slBarCount++;
         if(g_slBarCount >= Dir_Block_Bars) { g_lastSLDir = 0; g_slBarCount = 0; }
      }

      // Calcular señal una vez por barra
      g_cachedSig = GetSignal();

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

   // FIX 1: sesión NY 16:00-18:30 UTC
   if(!IsNYSession()) return;

   DailyReset();
   CheckHaltConditions();
   if(g_haltedToday) return;
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

   datetime now = TimeCurrent();

   // FIX 2: cooldown adaptativo según alineación de EMAs
   int slCd = GetSLCooldown(g_cachedSig);
   if(now - g_lastSLTime < slCd) return;

   // FIX 3: bloqueo direccional — no operar en la dirección del último SL por N barras
   if(g_lastSLDir != 0 && g_cachedSig == g_lastSLDir && g_slBarCount < Dir_Block_Bars) return;

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
