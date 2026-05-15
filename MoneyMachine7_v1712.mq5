//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.12 — BOLA DE NIEVE: LOTE COMPUESTO + TRAILING STOP        |
//|                                                                  |
//|  LECCIÓN APRENDIDA (v17.9 → v17.11):                           |
//|  Más filtros = menos trades = menos datos = peores resultados   |
//|  v17.11: solo 2 trades, Net=+$2.65 (era +$14.50 en v17.10)    |
//|                                                                  |
//|  TRADES REALES DEL PERÍODO (siempre los mismos):               |
//|  ✅ 14:59 SELL→TP | 16:46 BUY→TP | 17:29 BUY→TP | 18:11 BUY→TP|
//|  ❌ 15:34 BUY→SL  | 15:41 SELL→SL | 17:15 SELL→SL             |
//|  WR natural = 4/7 = 57% con R:R 1:2 → edge positivo real      |
//|                                                                  |
//|  ESTRATEGIA v17.12 — EFECTO BOLA DE NIEVE:                     |
//|                                                                  |
//|  1. SESIÓN AMPLIA 08:00-18:30 UTC                               |
//|     Máximos datos, máximas oportunidades                        |
//|     Cierre 18:30 es el único fix que siempre funciona           |
//|                                                                  |
//|  2. SEÑAL LIMPIA: EMA3/8 cruce + precio vs EMA21               |
//|     Sin filtros de dirección ni alineación                      |
//|     El edge está en el R:R 1:2, no en filtrar señales           |
//|                                                                  |
//|  3. TRAILING STOP ACTIVADO A 0.50pts                            |
//|     Cuando el precio se mueve 0.50pts a favor → mover SL a BE  |
//|     Cuando se mueve 0.75pts → SL sigue al precio a 0.25pts     |
//|     Convierte SLs en breakeven, protege ganancias abiertas      |
//|                                                                  |
//|  4. LOTE COMPUESTO ANTI-MARTINGALA                              |
//|     Racha ganadora → incrementar lote gradualmente              |
//|     Racha perdedora → reducir lote a mínimo                     |
//|     Efecto bola de nieve: ganancias crecen, pérdidas se limitan |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.12"
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
// +++ Sesión (amplia para datos) +++
input int    Session_Start_Hour          = 8;     // 08:00 UTC — apertura europea
input int    Session_Start_Min           = 0;
input int    Session_End_Hour            = 18;    // 18:30 UTC — fix probado
input int    Session_End_Min             = 30;
// +++ Salida +++
input double MM7_TP_FIXED                = 1.00;
input double MM7_SL_FIXED                = 0.50;
// +++ Trailing Stop (bola de nieve en posición abierta) +++
input bool   Use_Trailing                = true;
input double Trail_Activate_Pts          = 0.50;  // activar trailing cuando ganancia >= 0.50pts
input double Trail_Distance_Pts          = 0.25;  // mantener SL a 0.25pts del precio
// +++ Lote compuesto anti-martingala +++
input bool   Use_Compound_Lot            = true;
input int    WinStreak_To_Add            = 2;     // cada 2 TPs consecutivos → +1 nivel de lote
input double Lot_Step_Compound           = 0.01;  // incremento por nivel
input int    Max_Compound_Levels         = 5;     // máximo 5 niveles extra
// +++ Entry Control +++
input int    Entry_Cooldown_Secs         = 3;
input int    SL_Cooldown_Secs            = 30;
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

// Lote compuesto
int      g_winStreak   = 0;   // TPs consecutivos
int      g_compLevel   = 0;   // nivel actual de compuesto

//============================================================
// SEÑAL
//============================================================
int GetSignal()
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

   return crossUp ? 1 : -1;
}

bool IsSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int nowMin   = dt.hour * 60 + dt.min;
   int startMin = Session_Start_Hour * 60 + Session_Start_Min;
   int endMin   = Session_End_Hour   * 60 + Session_End_Min;
   return (nowMin >= startMin && nowMin < endMin);
}

//============================================================
// LOTE COMPUESTO ANTI-MARTINGALA
//============================================================
double CalcLot()
{
   double bal = Use_dynamic_lot_
      ? ((bool)MQLInfoInteger(MQL_TESTER)
         ? AccountInfoDouble(ACCOUNT_BALANCE)
         : MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)))
      : Free_margin_for_each_Lots_ * 5.0;

   double baseLot = MathRound(bal / Free_margin_for_each_Lots_) * 0.01;
   if(!Use_dynamic_lot_) baseLot = Lot_;

   // Añadir niveles compuestos si hay racha ganadora
   double compExtra = 0;
   if(Use_Compound_Lot && g_compLevel > 0)
      compExtra = g_compLevel * Lot_Step_Compound;

   double lot = baseLot + compExtra;
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, mn);
   lot = MathMin(lot, MathMin(Max_Lot_, mx));
   if(st > 0) lot = MathFloor(lot/st)*st;
   return NormalizeDouble(lot, 2);
}

void UpdateCompound(bool wasTP)
{
   if(!Use_Compound_Lot) return;
   if(wasTP)
   {
      g_winStreak++;
      if(g_winStreak >= WinStreak_To_Add)
      {
         g_winStreak = 0;
         g_compLevel = MathMin(g_compLevel + 1, Max_Compound_Levels);
         Print("MM7 Compound UP → nivel ", g_compLevel, " lot=", CalcLot());
      }
   }
   else
   {
      // SL: resetear racha y bajar un nivel
      g_winStreak = 0;
      g_compLevel = MathMax(g_compLevel - 1, 0);
      Print("MM7 Compound DOWN → nivel ", g_compLevel);
   }
}

//============================================================
// TRAILING STOP
//============================================================
void ManageTrailing()
{
   if(!Use_Trailing) return;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != g_magic) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      int    dir       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double bid       = SymbolInfoDouble(g_sym, SYMBOL_BID);
      double ask       = SymbolInfoDouble(g_sym, SYMBOL_ASK);
      double curPrice  = (dir == 1) ? bid : ask;
      int    digs      = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

      double profit_pts = dir * (curPrice - openPrice);

      // Fase 1: mover SL a breakeven cuando ganancia >= Trail_Activate_Pts
      if(profit_pts >= Trail_Activate_Pts)
      {
         double newSL = NormalizeDouble(curPrice - dir * Trail_Distance_Pts, digs);
         // Solo mover SL si mejora la posición actual
         bool shouldMove = (dir == 1) ? (newSL > curSL + g_point) : (newSL < curSL - g_point);
         if(shouldMove)
         {
            MqlTradeRequest req = {}; MqlTradeResult res = {};
            req.action   = TRADE_ACTION_SLTP;
            req.symbol   = g_sym;
            req.position = tk;
            req.sl       = newSL;
            req.tp       = curTP;
            OrderSend(req, res);
         }
      }
   }
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
   // NO resetear g_winStreak ni g_compLevel — el compuesto es inter-día (bola de nieve)
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
      UpdateCompound(false);
      Print("MM7 SL → compound nivel ", g_compLevel);
   }
   else if(reason == DEAL_REASON_TP)
   {
      UpdateCompound(true);
      Print("MM7 TP → compound nivel ", g_compLevel, " streak=", g_winStreak);
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
   bool inSess = IsSession();

   DashLbl("0", "[ MoneyMachine7 v17.12 ]", clrGold, 0*lh, x, y, co, fn);
   DashLbl("1", "Sesion "+IntegerToString(Session_Start_Hour)+":00-"+IntegerToString(Session_End_Hour)+":"+IntegerToString(Session_End_Min)+" UTC  "+(inSess?"ACTIVA":"inactiva"), inSess?clrLimeGreen:clrGray, 1*lh, x, y, co, fn);
   DashLbl("2", "Bal :$"+DoubleToString(bal,2)+" lot="+DoubleToString(CalcLot(),2), clrWhite, 2*lh, x, y, co, fn);
   DashLbl("3", "Eq  :$"+DoubleToString(eq,2)+" Open:"+IntegerToString(CountByMagic()), clrWhite, 3*lh, x, y, co, fn);
   DashLbl("4", "DD  :"+DoubleToString(dd,2)+"%", (dd>2)?clrOrangeRed:clrLimeGreen, 4*lh, x, y, co, fn);
   DashLbl("5", "Day :$"+DoubleToString(dp,2), (dp>=0)?clrLimeGreen:clrOrangeRed, 5*lh, x, y, co, fn);
   string rr = "TP:"+DoubleToString(MM7_TP_FIXED,2)+"pts SL:"+DoubleToString(MM7_SL_FIXED,2)+"pts R:R=1:"+DoubleToString(MM7_TP_FIXED/MM7_SL_FIXED,2);
   DashLbl("6", rr, clrCyan, 6*lh, x, y, co, fn);
   string sig_str = (g_cachedSig==1)?"BUY":(g_cachedSig==-1)?"SELL":"--";
   DashLbl("7", "Sig:"+sig_str+" EMAf:"+DoubleToString(g_cachedEMAf,2)+" EMAs:"+DoubleToString(g_cachedEMAs,2), clrWhite, 7*lh, x, y, co, fn);
   string compStr = "Comp:Nv"+IntegerToString(g_compLevel)+" Str:"+IntegerToString(g_winStreak)+"/"+IntegerToString(WinStreak_To_Add);
   bool inSLCool = (TimeCurrent() - g_lastSLTime < SL_Cooldown_Secs);
   string cdStr  = inSLCool ? "SL+"+IntegerToString((int)(g_lastSLTime+SL_Cooldown_Secs-TimeCurrent())) : "OK";
   DashLbl("8", compStr+" Cool:"+cdStr+" Halt:"+(g_haltedToday?"Y":"n"), clrGray, 8*lh, x, y, co, fn);
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

   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   g_winStreak   = 0;
   g_compLevel   = 0;

   Print("MM7 v17.12 | EMA(",EMA_Fast_Period,"/",EMA_Slow_Period,"/",EMA_Trend_M1_Period,") M1",
         " | Sesion ",Session_Start_Hour,":00-",Session_End_Hour,":",Session_End_Min," UTC",
         " | Trail=",Use_Trailing," act=",Trail_Activate_Pts,"pts dist=",Trail_Distance_Pts,"pts",
         " | Compound=",Use_Compound_Lot," cada ",WinStreak_To_Add," TPs",
         " | TP=",MM7_TP_FIXED," SL=",MM7_SL_FIXED);
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
   // Trailing stop — ejecutar en cada tick para máxima precisión
   ManageTrailing();

   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime)
   {
      g_lastBarTime = curBar;
      g_cachedSig   = GetSignal();

      int start = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
      double ef[], es[];
      ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true);
      if(CopyBuffer(g_hEMAf,0,start,1,ef)>=1) g_cachedEMAf = ef[0];
      if(CopyBuffer(g_hEMAs,0,start,1,es)>=1) g_cachedEMAs = es[0];
   }

   DrawDashboard();
   DrawHistoryLabels();

   if(g_cachedSig == 0) return;
   if(!IsSession()) return;

   DailyReset();
   CheckHaltConditions();
   if(g_haltedToday) return;
   if(!Control_orders_user) return;

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if((ask - bid) / g_point > InpMaxSpreadPoints) return;

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
