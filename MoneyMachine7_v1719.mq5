//+------------------------------------------------------------------+
//|  MoneyMachine7_v1719.mq5                                        |
//|  v17.19 — BE + TRAILING + LOTAJE DINAMICO                      |
//|  Base: v17.18 (NY only, EMA3/8+21, filtro pendiente simetrico) |
//|  NUEVO: Break-Even @ +0.25pts, Trailing @ +0.50pts             |
//|  Filtro vela: solo si body >= 0.10pts en direccion del trade    |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.19"
#property strict

input bool   Control_orders_user        = true;
input int    Max_Positions              = 1;
input double Lot_                       = 0.01;
input bool   Use_dynamic_lot_           = true;
input double Free_margin_for_each_Lots_ = 1000.0;
input double Max_Lot_                   = 5.0;
input int    EMA_Fast_Period            = 3;
input int    EMA_Slow_Period            = 8;
input int    EMA_Trend_Period           = 21;
input int    NY_Start_Hour              = 14;
input int    NY_Start_Min               = 30;
input int    NY_End_Hour                = 18;
input int    NY_End_Min                 = 30;
input int    NY_Max_Trades              = 6;
input double MM7_TP_FIXED               = 1.00;
input double MM7_SL_FIXED               = 0.50;
input bool   Use_BreakEven              = true;
input double BE_Trigger                 = 0.25;
input double BE_Offset                  = 0.02;
input bool   Use_Trailing               = true;
input double Trail_Trigger              = 0.50;
input double Trail_Distance             = 0.20;
input bool   Use_CandleFilter           = false; // desactivado por defecto — activa si quieres mas filtro
input double Candle_Min_Body            = 0.05;
input int    Entry_Cooldown_Secs        = 3;
input int    SL_Cooldown_Secs           = 300;
input int    InpMaxSpreadPoints         = 600;
input int    InpSlippagePoints          = 10;
input int    InpMagicNumber             = 171900;
input double InpMaxDailyLossPct         = 20.0;
input double InpMaxEquityDrawdown       = 20.0;
input bool   Enable_Dashboard           = true;
input int    Dashboard_Corner           = 0;
input int    Dashboard_X                = 10;
input int    Dashboard_Y                = 30;
input int    Font_Size                  = 11;
input bool   Enable_History_Labels      = true;

int      g_magic;
string   g_sym;
double   g_point;
int      g_hEMAf = INVALID_HANDLE;
int      g_hEMAs = INVALID_HANDLE;
int      g_hEMAt = INVALID_HANDLE;
datetime g_lastBarTime   = 0;
datetime g_lastEntryTime = 0;
datetime g_lastSLTime    = 0;
datetime g_dayStart      = 0;
double   g_dayStartBal   = 0;
bool     g_haltedToday   = false;
datetime g_lastDashTime  = 0;
datetime g_lastLblTime   = 0;
int      g_cachedSig     = 0;
double   g_cachedEMAf    = 0;
double   g_cachedEMAs    = 0;
int      g_nyTrades      = 0;
int      g_openDir       = 0;
double   g_openEntry     = 0;
double   g_trailBest     = 0;
bool     g_beActivated   = false;

int GetNowMin()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   return d.hour * 60 + d.min;
}

bool IsNYSession()
{
   int nm = GetNowMin();
   return (nm >= NY_Start_Hour * 60 + NY_Start_Min &&
           nm <  NY_End_Hour   * 60 + NY_End_Min);
}

double CalcLot()
{
   if(!Use_dynamic_lot_) return NormalizeDouble(Lot_, 2);
   bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
   double bal = isTester ? AccountInfoDouble(ACCOUNT_BALANCE)
                         : MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                                   AccountInfoDouble(ACCOUNT_EQUITY));
   double lot = MathFloor(bal / Free_margin_for_each_Lots_) * 0.01;
   double mn  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
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
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == g_magic) n++;
   }
   return n;
}

ulong GetOpenTicket()
{
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         (int)PositionGetInteger(POSITION_MAGIC) == g_magic) return tk;
   }
   return 0;
}

bool SpreadOK()
{
   double sp = (SymbolInfoDouble(g_sym, SYMBOL_ASK) -
                SymbolInfoDouble(g_sym, SYMBOL_BID)) / g_point;
   return (sp <= InpMaxSpreadPoints);
}

ulong OpenOrder(ENUM_ORDER_TYPE type, int dir)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double tp    = NormalizeDouble(entry + dir * MM7_TP_FIXED, digs);
   double sl    = NormalizeDouble(entry - dir * MM7_SL_FIXED, digs);
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = g_sym;
   req.volume       = CalcLot();
   req.type         = type;
   req.price        = entry;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = InpSlippagePoints;
   req.magic        = g_magic;
   req.comment      = "MM7-NY";
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) {
      req.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(req, res)) {
         req.type_filling = ORDER_FILLING_RETURN;
         OrderSend(req, res);
      }
   }
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) {
      g_openDir    = dir;
      g_openEntry  = entry;
      g_trailBest  = entry;
      g_beActivated = false;
      Print("MM7 OPEN ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp,
            " lot=", req.volume);
      return res.order;
   }
   Print("MM7 OrderSend FAIL retcode=", res.retcode, " ", res.comment);
   return 0;
}

bool ModifySL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   newSL = NormalizeDouble(newSL, digs);
   if(MathAbs(newSL - curSL) < g_point) return false;
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = g_sym;
   req.position = ticket;
   req.sl       = newSL;
   req.tp       = curTP;
   req.magic    = g_magic;
   OrderSend(req, res);
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
}

void ManageOpenPosition()
{
   ulong ticket = GetOpenTicket();
   if(ticket == 0) {
      g_openDir = 0; g_openEntry = 0; g_trailBest = 0;
      return;
   }
   if(!PositionSelectByTicket(ticket)) return;
   double curSL    = PositionGetDouble(POSITION_SL);
   double bid      = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask      = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double curPrice = (g_openDir == 1) ? bid : ask;
   double profit   = g_openDir * (curPrice - g_openEntry);
   int    digs     = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   if(g_openDir == 1 && curPrice > g_trailBest) g_trailBest = curPrice;
   if(g_openDir == -1 && curPrice < g_trailBest) g_trailBest = curPrice;
   double newSL = curSL;
   if(Use_BreakEven && !g_beActivated && profit >= BE_Trigger) {
      double beSL = NormalizeDouble(g_openEntry + g_openDir * BE_Offset, digs);
      if(g_openDir == 1 && beSL > curSL) {
         newSL = beSL;
         g_beActivated = true;
         Print("MM7 BE activado SL->", beSL);
      }
      if(g_openDir == -1 && beSL < curSL) {
         newSL = beSL;
         g_beActivated = true;
         Print("MM7 BE activado SL->", beSL);
      }
   }
   if(Use_Trailing && profit >= Trail_Trigger) {
      double trailSL;
      if(g_openDir == 1) {
         trailSL = NormalizeDouble(g_trailBest - Trail_Distance, digs);
         if(trailSL > newSL) newSL = trailSL;
      } else {
         trailSL = NormalizeDouble(g_trailBest + Trail_Distance, digs);
         if(newSL == 0 || trailSL < newSL) newSL = trailSL;
      }
   }
   if(newSL != curSL && newSL != 0) ModifySL(ticket, newSL);
}

// Señal EMA3/8 cruce + EMA21 posicion + pendiente simetrica + filtro vela
// NOTA: en tester s=0 (barra actual), en live s=1 (barra cerrada)
int GetSignal()
{
   if(g_hEMAf == INVALID_HANDLE || g_hEMAs == INVALID_HANDLE ||
      g_hEMAt == INVALID_HANDLE) return 0;
   int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[], es[], et[];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   ArraySetAsSeries(et, true);
   if(CopyBuffer(g_hEMAf, 0, s, 3, ef) < 3) return 0;
   if(CopyBuffer(g_hEMAs, 0, s, 3, es) < 3) return 0;
   if(CopyBuffer(g_hEMAt, 0, s, 2, et) < 2) return 0;
   double bid    = SymbolInfoDouble(g_sym, SYMBOL_BID);
   bool crossUp   = (ef[0] > es[0] && ef[1] <= es[1]);
   bool crossDown = (ef[0] < es[0] && ef[1] >= es[1]);
   if(!crossUp && !crossDown) return 0;
   if(crossUp   && bid <= et[0]) return 0;
   if(crossDown && bid >= et[0]) return 0;
   if(crossUp   && et[0] <= et[1]) return 0;
   if(crossDown && et[0] >= et[1]) return 0;
   if(Use_CandleFilter) {
      // Barra que acaba de cerrar y genero la senal (siempre barra 1 desde la actual)
      double op[], cl[];
      ArraySetAsSeries(op, true);
      ArraySetAsSeries(cl, true);
      int barIdx = (bool)MQLInfoInteger(MQL_TESTER) ? 1 : 1;
      if(CopyOpen(g_sym, _Period, barIdx, 1, op) >= 1 &&
         CopyClose(g_sym, _Period, barIdx, 1, cl) >= 1) {
         double body = cl[0] - op[0];
         if(crossUp   && body < Candle_Min_Body)  return 0;
         if(crossDown && body > -Candle_Min_Body) return 0;
      }
   }
   return crossUp ? 1 : -1;
}

void DailyReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today == g_dayStart) return;
   g_dayStart    = today;
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                           AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday   = false;
   g_lastEntryTime = 0;
   g_lastBarTime   = 0;
   g_cachedSig     = 0;
   g_nyTrades      = 0;
}

void CheckHalt()
{
   if(g_haltedToday) return;
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartBal <= 0) return;
   double pct = (g_dayStartBal - eq) / g_dayStartBal * 100.0;
   if(InpMaxEquityDrawdown > 0 && pct >= InpMaxEquityDrawdown)
   { g_haltedToday = true; Print("MM7 HALT DD"); return; }
   if(InpMaxDailyLossPct > 0 && pct >= InpMaxDailyLossPct)
   { g_haltedToday = true; Print("MM7 HALT DL"); }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult  &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY &&
      trans.deal_type != DEAL_TYPE_SELL) return;
   ulong dk = trans.deal;
   if(!HistoryDealSelect(dk)) return;
   if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   ENUM_DEAL_REASON reason =
      (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
   if(reason == DEAL_REASON_SL) {
      g_lastSLTime = TimeCurrent();
      Print("MM7 SL hit cooldown ", SL_Cooldown_Secs, "s");
   }
   g_openDir = 0; g_openEntry = 0; g_trailBest = 0; g_beActivated = false;
}

void DashLbl(string nm, string txt, color clr, int row)
{
   string f  = "MM7D_" + nm;
   int    lh = Font_Size + 4;
   if(ObjectFind(0, f) < 0) {
      ObjectCreate(0, f, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, f, OBJPROP_CORNER, (ENUM_BASE_CORNER)Dashboard_Corner);
      ObjectSetInteger(0, f, OBJPROP_XDISTANCE, Dashboard_X);
      ObjectSetString(0, f, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, f, OBJPROP_FONTSIZE, Font_Size);
   }
   ObjectSetInteger(0, f, OBJPROP_YDISTANCE, Dashboard_Y + row * lh);
   ObjectSetString(0, f, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, f, OBJPROP_COLOR, clr);
}

void DrawDashboard()
{
   if(!Enable_Dashboard || TimeCurrent() - g_lastDashTime < 1) return;
   g_lastDashTime = TimeCurrent();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd  = (g_dayStartBal > 0) ?
                (g_dayStartBal - eq) / g_dayStartBal * 100.0 : 0;
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   double dp = 0;
   HistorySelect(ds, TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) == g_magic)
         dp += HistoryDealGetDouble(dk, DEAL_PROFIT);
   }
   bool   inNY = IsNYSession();
   string sess = inNY ? "NY 14:30-18:30" : "---";
   color  sc   = inNY ? clrLimeGreen : clrGray;
   string posStr = "---";
   ulong  tk     = GetOpenTicket();
   if(tk > 0 && PositionSelectByTicket(tk)) {
      double pnl   = PositionGetDouble(POSITION_PROFIT);
      double curSL = PositionGetDouble(POSITION_SL);
      string dirStr = (g_openDir == 1) ? "BUY" : "SELL";
      string beStr  = g_beActivated ? " [BE]" : "";
      posStr = dirStr + " PnL=$" + DoubleToString(pnl, 2) +
               " SL=" + DoubleToString(curSL, 2) + beStr;
   }
   bool   inSLCool = (TimeCurrent() - g_lastSLTime < SL_Cooldown_Secs);
   int    cdLeft   = inSLCool ? (int)(g_lastSLTime + SL_Cooldown_Secs - TimeCurrent()) : 0;
   string cdStr    = inSLCool ? (IntegerToString(cdLeft) + "s") : "OK";
   string sigStr   = (g_cachedSig == 1) ? "BUY" : (g_cachedSig == -1) ? "SELL" : "--";
   string haltStr  = g_haltedToday ? "SI" : "no";
   color  posClr   = (tk > 0) ? clrYellow : clrGray;
   color  dayClr   = (dp >= 0) ? clrLimeGreen : clrOrangeRed;
   string line2    = "Bal:$" + DoubleToString(bal, 2) + " Eq:$" + DoubleToString(eq, 2);
   string line3    = "Day:$" + DoubleToString(dp, 2) + " DD:" + DoubleToString(dd, 2) + "%";
   string line4    = "NY tr:" + IntegerToString(g_nyTrades) + "/" + IntegerToString(NY_Max_Trades) +
                     " SL=" + DoubleToString(MM7_SL_FIXED, 2) +
                     " TP=" + DoubleToString(MM7_TP_FIXED, 2) +
                     " BE@+" + DoubleToString(BE_Trigger, 2) +
                     " Trail@+" + DoubleToString(Trail_Trigger, 2);
   string line6    = "Sig:" + sigStr + " EMAf:" + DoubleToString(g_cachedEMAf, 2) +
                     " SLcool:" + cdStr + " Halt:" + haltStr;
   DashLbl("0", "[ MM7 v17.19 BE+TRAIL+LOTAJE DINAMICO ]", clrGold, 0);
   DashLbl("1", "Sesion: " + sess + " | lot=" + DoubleToString(CalcLot(), 2), sc, 1);
   DashLbl("2", line2, clrWhite, 2);
   DashLbl("3", line3, dayClr, 3);
   DashLbl("4", line4, clrCyan, 4);
   DashLbl("5", "Pos: " + posStr, posClr, 5);
   DashLbl("6", line6, clrGray, 6);
}

void DrawHistoryLabels()
{
   if(!Enable_History_Labels || TimeCurrent() - g_lastLblTime < 10) return;
   g_lastLblTime = TimeCurrent();
   ObjectsDeleteAll(0, "MM7L_");
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(ds, TimeCurrent());
   int tot = HistoryDealsTotal();
   int st  = MathMax(0, tot - 50);
   for(int i = st; i < tot; i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) != g_magic) continue;
      if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double   pf = HistoryDealGetDouble(dk, DEAL_PROFIT);
      double   px = HistoryDealGetDouble(dk, DEAL_PRICE);
      datetime t  = (datetime)HistoryDealGetInteger(dk, DEAL_TIME);
      string   nm = "MM7L_" + (string)dk;
      if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TEXT, 0, t, px);
      ObjectSetString(0, nm, OBJPROP_TEXT,
                      (pf >= 0 ? "+" : "") + DoubleToString(pf, 2));
      ObjectSetInteger(0, nm, OBJPROP_COLOR,
                       (pf >= 0) ? clrLimeGreen : clrOrangeRed);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 8);
   }
}

int OnInit()
{
   g_magic = InpMagicNumber;
   g_sym   = _Symbol;
   g_point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_point <= 0) { Alert("Invalid SYMBOL_POINT"); return INIT_FAILED; }
   g_hEMAf = iMA(g_sym, _Period, EMA_Fast_Period,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMAs = iMA(g_sym, _Period, EMA_Slow_Period,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMAt = iMA(g_sym, _Period, EMA_Trend_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMAf == INVALID_HANDLE || g_hEMAs == INVALID_HANDLE ||
      g_hEMAt == INVALID_HANDLE)
   { Alert("EMA init failed"); return INIT_FAILED; }
   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                           AccountInfoDouble(ACCOUNT_EQUITY));
   Print("MM7 v17.19 | ", g_sym,
         " POINT=", g_point,
         " DIGITS=", SymbolInfoInteger(g_sym, SYMBOL_DIGITS),
         " | SL=", MM7_SL_FIXED, " TP=", MM7_TP_FIXED,
         " | BE@+", BE_Trigger, " Trail@+", Trail_Trigger,
         " | NY ", NY_Start_Hour, ":", NY_Start_Min,
         "-", NY_End_Hour, ":", NY_End_Min,
         " | SL_CD=", SL_Cooldown_Secs, "s",
         " | CandleFilter=", Use_CandleFilter,
         " MinBody=", Candle_Min_Body);
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
   ManageOpenPosition();
   if(g_haltedToday || !Control_orders_user) return;
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      g_cachedSig   = GetSignal();
      int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
      double ef[], es[];
      ArraySetAsSeries(ef, true);
      ArraySetAsSeries(es, true);
      if(CopyBuffer(g_hEMAf, 0, s, 1, ef) >= 1) g_cachedEMAf = ef[0];
      if(CopyBuffer(g_hEMAs, 0, s, 1, es) >= 1) g_cachedEMAs = es[0];
   }
   if(g_cachedSig == 0) return;
   if(!IsNYSession()) return;
   if(g_nyTrades >= NY_Max_Trades) return;
   if(CountByMagic() >= Max_Positions) return;
   if(TimeCurrent() - g_lastSLTime    < SL_Cooldown_Secs) return;
   if(TimeCurrent() - g_lastEntryTime < Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;
   ENUM_ORDER_TYPE otype =
      (g_cachedSig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong tk = OpenOrder(otype, g_cachedSig);
   if(tk > 0) {
      g_nyTrades++;
      g_lastEntryTime = TimeCurrent();
      g_cachedSig     = 0;
   }
}
