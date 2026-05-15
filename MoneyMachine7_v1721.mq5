//+------------------------------------------------------------------+
//|  MoneyMachine7_v1721.mq5                                        |
//|  v17.21 — MAXIMO RENDIMIENTO BASADO EN DATOS v17.19+v17.20     |
//|                                                                  |
//|  DATOS v17.19: Net=+$11.75 | WR=43.5% | 23 trades              |
//|  BUYs WR=62.5% | SELLs WR=40% | Hora 16:xx WR=60% MEJOR       |
//|  SLs instantaneos (<10s): trades 2,3,14,15,18,19 = señales falsas|
//|                                                                  |
//|  MEJORAS v17.21 vs v17.20:                                      |
//|  1. FILTRO VELA: body >= 0.08pts en dir del trade               |
//|     Elimina señales debiles que generan SLs instantaneos        |
//|  2. RSI DINAMICO POR ZONA:                                      |
//|     14:30-15:30 (ruido): BUY>55, SELL<45 (mas estricto)        |
//|     15:30-18:30 (productivo): BUY>50, SELL<50                  |
//|  3. CIERRE PARCIAL 50% a +0.50pts + SL a BE                    |
//|     Asegura ganancia en cada trade, deja correr el resto        |
//|  4. SPREAD ESTRICTO en zona early: max 300pts (era 600)         |
//|     Los SLs instantaneos ocurren con spread alto                |
//|  5. RACHA PERDEDORA: 2 SLs consecutivos = pausa 900s           |
//|     Evita operar en mercado en contra                           |
//|  6. HORA DE ORO 16:00-17:00: max 3 trades extra                |
//|     WR=60% en v17.19, la mejor hora del dia                    |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.21"
#property strict

input bool   Control_orders_user        = true;
input int    Max_Positions              = 1;
input double Lot_                       = 0.01;
input bool   Use_dynamic_lot_           = true;
input double Free_margin_for_each_Lots_ = 1000.0;
input double Max_Lot_                   = 5.0;
// EMA
input int    EMA_Fast_Period            = 3;
input int    EMA_Slow_Period            = 8;
input int    EMA_Trend_Period           = 21;
// RSI
input int    RSI_Period                 = 14;
input double RSI_BUY_Min_Early          = 55.0;   // zona ruidosa 14:30-15:30
input double RSI_SELL_Max_Early         = 45.0;   // zona ruidosa 14:30-15:30
input double RSI_BUY_Min_Main           = 50.0;   // zona productiva 15:30-18:30
input double RSI_SELL_Max_Main          = 50.0;   // zona productiva 15:30-18:30
// Filtro vela
input bool   Use_CandleFilter           = true;
input double Candle_Min_Body            = 0.08;
// Sesion NY dividida
input int    NY_Early_Start_Hour        = 14;
input int    NY_Early_Start_Min         = 30;
input int    NY_Early_End_Hour          = 15;
input int    NY_Early_End_Min           = 30;
input int    NY_Early_Max_Trades        = 1;
input int    NY_Main_Start_Hour         = 15;
input int    NY_Main_Start_Min          = 30;
input int    NY_Main_End_Hour           = 18;
input int    NY_Main_End_Min            = 30;
input int    NY_Main_Max_Trades         = 5;
// Hora de oro
input int    GoldenHour_Start           = 16;
input int    GoldenHour_End             = 17;
input int    GoldenHour_Extra_Trades    = 3;
// SL/TP
input double MM7_TP_FIXED               = 1.00;
input double MM7_SL_FIXED               = 0.50;
// Cierre parcial
input bool   Use_PartialClose           = true;
input double PartialClose_Trigger       = 0.50;   // cierra 50% a +0.50pts
input double PartialClose_Pct           = 0.50;   // porcentaje a cerrar
// Break-Even
input bool   Use_BreakEven              = true;
input double BE_Trigger                 = 0.20;
input double BE_Offset                  = 0.02;
// Trailing
input bool   Use_Trailing               = true;
input double Trail_Trigger              = 0.50;
input double Trail_Distance             = 0.15;
// Entry control
input int    Entry_Cooldown_Secs        = 3;
input int    SL_Cooldown_Secs           = 300;
input int    SL_Fast_Cooldown_Secs      = 600;
input int    SL_Fast_Threshold_Secs     = 10;
input int    ConsecSL_Cooldown_Secs     = 900;    // 2 SLs consecutivos
input int    InpMaxSpreadPoints         = 600;
input int    InpMaxSpreadEarly          = 300;    // spread estricto en zona early
input int    InpSlippagePoints          = 10;
input int    InpMagicNumber             = 172100;
// Risk
input double InpMaxDailyLossPct         = 20.0;
input double InpMaxEquityDrawdown       = 20.0;
// Dashboard
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
int      g_hRSI  = INVALID_HANDLE;

datetime g_lastBarTime     = 0;
datetime g_lastEntryTime   = 0;
datetime g_lastSLTime      = 0;
datetime g_dayStart        = 0;
double   g_dayStartBal     = 0;
bool     g_haltedToday     = false;
datetime g_lastDashTime    = 0;
datetime g_lastLblTime     = 0;

int      g_cachedSig       = 0;
double   g_cachedEMAf      = 0;
double   g_cachedEMAs      = 0;
double   g_cachedRSI       = 0;
int      g_earlyTrades     = 0;
int      g_mainTrades      = 0;
int      g_goldenTrades    = 0;

int      g_openDir         = 0;
double   g_openEntry       = 0;
double   g_trailBest       = 0;
bool     g_beActivated     = false;
bool     g_partialDone     = false;
datetime g_openTime        = 0;
double   g_openLot         = 0;

int      g_consecSL        = 0;   // contador SLs consecutivos
datetime g_consecSLTime    = 0;   // cuando se activo la pausa por racha

int GetNowMin()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   return d.hour * 60 + d.min;
}

int GetNowHour()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   return d.hour;
}

bool IsEarlyNY()
{
   int nm = GetNowMin();
   return (nm >= NY_Early_Start_Hour * 60 + NY_Early_Start_Min &&
           nm <  NY_Early_End_Hour   * 60 + NY_Early_End_Min);
}

bool IsMainNY()
{
   int nm = GetNowMin();
   return (nm >= NY_Main_Start_Hour * 60 + NY_Main_Start_Min &&
           nm <  NY_Main_End_Hour   * 60 + NY_Main_End_Min);
}

bool IsGoldenHour()
{
   int h = GetNowHour();
   return (h >= GoldenHour_Start && h < GoldenHour_End);
}

bool IsAnyNY() { return IsEarlyNY() || IsMainNY(); }

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
   int maxSp = IsEarlyNY() ? InpMaxSpreadEarly : InpMaxSpreadPoints;
   return (sp <= maxSp);
}

ulong OpenOrder(ENUM_ORDER_TYPE type, int dir)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double tp    = NormalizeDouble(entry + dir * MM7_TP_FIXED, digs);
   double sl    = NormalizeDouble(entry - dir * MM7_SL_FIXED, digs);
   double lot   = CalcLot();
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = g_sym;
   req.volume       = lot;
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
      g_openDir     = dir;
      g_openEntry   = entry;
      g_trailBest   = entry;
      g_beActivated = false;
      g_partialDone = false;
      g_openTime    = TimeCurrent();
      g_openLot     = lot;
      Print("MM7 OPEN ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp,
            " lot=", lot, " RSI=", g_cachedRSI,
            " zona=", IsEarlyNY() ? "EARLY" : (IsGoldenHour() ? "GOLDEN" : "MAIN"));
      return res.order;
   }
   Print("MM7 OrderSend FAIL retcode=", res.retcode);
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

bool PartialClose(ulong ticket, double pct)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double vol  = PositionGetDouble(POSITION_VOLUME);
   double mn   = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double st   = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double cVol = MathFloor(vol * pct / st) * st;
   if(cVol < mn) return false;
   ENUM_ORDER_TYPE cType = (g_openDir == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (cType == ORDER_TYPE_SELL) ? SymbolInfoDouble(g_sym, SYMBOL_BID)
                                             : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = g_sym;
   req.volume       = cVol;
   req.type         = cType;
   req.price        = price;
   req.position     = ticket;
   req.deviation    = InpSlippagePoints;
   req.magic        = g_magic;
   req.comment      = "MM7-PARTIAL";
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) {
      req.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(req, res)) {
         req.type_filling = ORDER_FILLING_RETURN;
         OrderSend(req, res);
      }
   }
   bool ok = (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
   if(ok) Print("MM7 PARTIAL CLOSE ", cVol, " lots @ ", price);
   return ok;
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
   if(g_openDir ==  1 && curPrice > g_trailBest) g_trailBest = curPrice;
   if(g_openDir == -1 && curPrice < g_trailBest) g_trailBest = curPrice;
   // Cierre parcial 50% a +0.50pts — asegura ganancia
   if(Use_PartialClose && !g_partialDone && profit >= PartialClose_Trigger) {
      if(PartialClose(ticket, PartialClose_Pct)) {
         g_partialDone = true;
         // Mover SL a BE inmediatamente tras cierre parcial
         double beSL = NormalizeDouble(g_openEntry + g_openDir * BE_Offset, digs);
         if(g_openDir ==  1 && beSL > curSL) { ModifySL(ticket, beSL); g_beActivated = true; }
         if(g_openDir == -1 && beSL < curSL) { ModifySL(ticket, beSL); g_beActivated = true; }
         Print("MM7 PARTIAL+BE profit=", profit);
         return;
      }
   }
   double newSL = curSL;
   // Break-Even normal (si no se hizo cierre parcial)
   if(Use_BreakEven && !g_beActivated && profit >= BE_Trigger) {
      double beSL = NormalizeDouble(g_openEntry + g_openDir * BE_Offset, digs);
      if(g_openDir ==  1 && beSL > curSL) { newSL = beSL; g_beActivated = true; Print("MM7 BE SL->", beSL); }
      if(g_openDir == -1 && beSL < curSL) { newSL = beSL; g_beActivated = true; Print("MM7 BE SL->", beSL); }
   }
   // Trailing
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

// Señal EMA3/8 cruce + EMA21 posicion + pendiente simetrica + RSI dinamico + filtro vela
int GetSignal()
{
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE ||
      g_hEMAt==INVALID_HANDLE || g_hRSI==INVALID_HANDLE) return 0;
   int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[], es[], et[], rsi[];
   ArraySetAsSeries(ef,  true);
   ArraySetAsSeries(es,  true);
   ArraySetAsSeries(et,  true);
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_hEMAf, 0, s, 3, ef)  < 3) return 0;
   if(CopyBuffer(g_hEMAs, 0, s, 3, es)  < 3) return 0;
   if(CopyBuffer(g_hEMAt, 0, s, 2, et)  < 2) return 0;
   if(CopyBuffer(g_hRSI,  0, s, 1, rsi) < 1) return 0;
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   bool crossUp   = (ef[0] > es[0] && ef[1] <= es[1]);
   bool crossDown = (ef[0] < es[0] && ef[1] >= es[1]);
   if(!crossUp && !crossDown) return 0;
   // Precio del lado correcto de EMA21
   if(crossUp   && bid <= et[0]) return 0;
   if(crossDown && bid >= et[0]) return 0;
   // EMA21 pendiente en direccion del trade
   if(crossUp   && et[0] <= et[1]) return 0;
   if(crossDown && et[0] >= et[1]) return 0;
   // RSI dinamico segun zona horaria
   double rsiMin = IsEarlyNY() ? RSI_BUY_Min_Early  : RSI_BUY_Min_Main;
   double rsiMax = IsEarlyNY() ? RSI_SELL_Max_Early  : RSI_SELL_Max_Main;
   g_cachedRSI = rsi[0];
   if(crossUp   && rsi[0] < rsiMin) return 0;
   if(crossDown && rsi[0] > rsiMax) return 0;
   // Filtro vela: body minimo en direccion del trade
   if(Use_CandleFilter) {
      double op[], cl[];
      ArraySetAsSeries(op, true);
      ArraySetAsSeries(cl, true);
      int barIdx = 1;
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
   g_haltedToday  = false;
   g_lastEntryTime = 0;
   g_lastBarTime   = 0;
   g_cachedSig     = 0;
   g_earlyTrades   = 0;
   g_mainTrades    = 0;
   g_goldenTrades  = 0;
   g_consecSL      = 0;
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
   // Ignorar cierres parciales (comment = MM7-PARTIAL)
   string cmt = HistoryDealGetString(dk, DEAL_COMMENT);
   if(StringFind(cmt, "PARTIAL") >= 0) return;
   ENUM_DEAL_REASON reason =
      (ENUM_DEAL_REASON)HistoryDealGetInteger(dk, DEAL_REASON);
   if(reason == DEAL_REASON_SL) {
      datetime now = TimeCurrent();
      int elapsed = (int)(now - g_openTime);
      int cd = SL_Cooldown_Secs;
      if(elapsed <= SL_Fast_Threshold_Secs) cd = SL_Fast_Cooldown_Secs;
      g_lastSLTime = now;
      g_consecSL++;
      if(g_consecSL >= 2) {
         g_consecSLTime = now;
         Print("MM7 RACHA SL x", g_consecSL, " pausa ", ConsecSL_Cooldown_Secs, "s");
      }
      Print("MM7 SL hit elapsed=", elapsed, "s cooldown=", cd, "s consecSL=", g_consecSL);
   } else {
      // Trade cerrado con ganancia o TP — resetear racha
      g_consecSL = 0;
   }
   g_openDir = 0; g_openEntry = 0; g_trailBest = 0;
   g_beActivated = false; g_partialDone = false; g_openTime = 0;
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
   double dd  = 0;
   if(g_dayStartBal > 0) dd = (g_dayStartBal - eq) / g_dayStartBal * 100.0;
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   double dp = 0;
   HistorySelect(ds, TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) == g_magic)
         dp += HistoryDealGetDouble(dk, DEAL_PROFIT);
   }
   bool   inEarly  = IsEarlyNY();
   bool   inMain   = IsMainNY();
   bool   inGolden = IsGoldenHour();
   string sess; color sc;
   if(inGolden && inMain) { sess="GOLDEN HOUR 16:00-17:00"; sc=clrGold; }
   else if(inEarly)       { sess="NY EARLY 14:30-15:30";    sc=clrOrange; }
   else if(inMain)        { sess="NY MAIN  15:30-18:30";    sc=clrLimeGreen; }
   else                   { sess="---";                     sc=clrGray; }
   string posStr = "---";
   ulong  tk     = GetOpenTicket();
   if(tk > 0 && PositionSelectByTicket(tk)) {
      double pnl   = PositionGetDouble(POSITION_PROFIT);
      double curSL = PositionGetDouble(POSITION_SL);
      string dirStr = (g_openDir == 1) ? "BUY" : "SELL";
      string beStr  = g_beActivated ? " [BE]" : "";
      string pcStr  = g_partialDone ? " [50%]" : "";
      posStr = dirStr + " PnL=$" + DoubleToString(pnl,2) + " SL=" + DoubleToString(curSL,2) + beStr + pcStr;
   }
   bool   inSLCool  = (TimeCurrent() - g_lastSLTime < SL_Cooldown_Secs);
   bool   inConsSL  = (g_consecSL >= 2 && TimeCurrent() - g_consecSLTime < ConsecSL_Cooldown_Secs);
   int    cdLeft    = inSLCool ? (int)(g_lastSLTime + SL_Cooldown_Secs - TimeCurrent()) : 0;
   string cdStr     = inConsSL ? ("RACHA " + IntegerToString(ConsecSL_Cooldown_Secs - (int)(TimeCurrent()-g_consecSLTime)) + "s")
                               : (inSLCool ? (IntegerToString(cdLeft) + "s") : "OK");
   string sigStr; if(g_cachedSig==1) sigStr="BUY"; else if(g_cachedSig==-1) sigStr="SELL"; else sigStr="--";
   string haltStr  = g_haltedToday ? "SI" : "no";
   color  dayClr   = (dp >= 0) ? clrLimeGreen : clrOrangeRed;
   color  posClr   = (tk > 0)  ? clrYellow    : clrGray;
   double rsiMin   = inEarly ? RSI_BUY_Min_Early : RSI_BUY_Min_Main;
   double rsiMax   = inEarly ? RSI_SELL_Max_Early : RSI_SELL_Max_Main;
   string line1    = "Sesion: " + sess + " | lot=" + DoubleToString(CalcLot(), 2);
   string line2    = "Bal:$" + DoubleToString(bal, 2) + " Eq:$" + DoubleToString(eq, 2);
   string line3    = "Day:$" + DoubleToString(dp, 2) + " DD:" + DoubleToString(dd, 2) + "%";
   string line4    = "Early:" + IntegerToString(g_earlyTrades) + "/1" +
                     " Main:" + IntegerToString(g_mainTrades) + "/5" +
                     " Gold:" + IntegerToString(g_goldenTrades) + "/3" +
                     " RSI=" + DoubleToString(g_cachedRSI, 1) +
                     " [>" + DoubleToString(rsiMin,0) + "/<" + DoubleToString(rsiMax,0) + "]";
   string line5    = "BE@+" + DoubleToString(BE_Trigger,2) +
                     " Tr@+" + DoubleToString(Trail_Trigger,2) +
                     " PC@+" + DoubleToString(PartialClose_Trigger,2) +
                     " consecSL=" + IntegerToString(g_consecSL);
   string line6    = "Sig:" + sigStr + " EMAf:" + DoubleToString(g_cachedEMAf, 2) +
                     " SLcool:" + cdStr + " Halt:" + haltStr;
   DashLbl("0", "[ MM7 v17.21 RSI-DIN+VELA+PARTIAL+RACHA ]", clrGold, 0);
   DashLbl("1", line1, sc, 1);
   DashLbl("2", line2, clrWhite, 2);
   DashLbl("3", line3, dayClr, 3);
   DashLbl("4", line4, clrCyan, 4);
   DashLbl("5", line5, clrCyan, 5);
   DashLbl("6", "Pos: " + posStr, posClr, 6);
   DashLbl("7", line6, clrGray, 7);
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
   g_hRSI  = iRSI(g_sym, _Period, RSI_Period, PRICE_CLOSE);
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE ||
      g_hEMAt==INVALID_HANDLE || g_hRSI==INVALID_HANDLE)
   { Alert("Indicator init failed"); return INIT_FAILED; }
   g_dayStart    = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                           AccountInfoDouble(ACCOUNT_EQUITY));
   Print("MM7 v17.21 | ", g_sym,
         " POINT=", g_point,
         " | SL=", MM7_SL_FIXED, " TP=", MM7_TP_FIXED,
         " | RSI Early BUY>", RSI_BUY_Min_Early, " SELL<", RSI_SELL_Max_Early,
         " | RSI Main BUY>", RSI_BUY_Min_Main, " SELL<", RSI_SELL_Max_Main,
         " | CandleFilter=", Use_CandleFilter, " MinBody=", Candle_Min_Body,
         " | PartialClose=", Use_PartialClose, " @+", PartialClose_Trigger,
         " | BE@+", BE_Trigger, " Trail@+", Trail_Trigger, " dist=", Trail_Distance,
         " | ConsecSL_CD=", ConsecSL_Cooldown_Secs, "s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "MM7D_");
   ObjectsDeleteAll(0, "MM7L_");
   if(g_hEMAf != INVALID_HANDLE) IndicatorRelease(g_hEMAf);
   if(g_hEMAs != INVALID_HANDLE) IndicatorRelease(g_hEMAs);
   if(g_hEMAt != INVALID_HANDLE) IndicatorRelease(g_hEMAt);
   if(g_hRSI  != INVALID_HANDLE) IndicatorRelease(g_hRSI);
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
      double ef[], es[], rsi[];
      ArraySetAsSeries(ef,  true);
      ArraySetAsSeries(es,  true);
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(g_hEMAf, 0, s, 1, ef)  >= 1) g_cachedEMAf = ef[0];
      if(CopyBuffer(g_hEMAs, 0, s, 1, es)  >= 1) g_cachedEMAs = es[0];
      if(CopyBuffer(g_hRSI,  0, s, 1, rsi) >= 1) g_cachedRSI  = rsi[0];
   }
   if(g_cachedSig == 0) return;
   if(!IsAnyNY()) return;
   if(CountByMagic() >= Max_Positions) return;
   // Pausa por racha perdedora (2 SLs consecutivos)
   if(g_consecSL >= 2 && TimeCurrent() - g_consecSLTime < ConsecSL_Cooldown_Secs) return;
   // Cooldown adaptativo post-SL
   int activeCd = SL_Cooldown_Secs;
   if(g_openTime > 0) {
      int elapsed = (int)(TimeCurrent() - g_openTime);
      if(elapsed <= SL_Fast_Threshold_Secs) activeCd = SL_Fast_Cooldown_Secs;
   }
   if(TimeCurrent() - g_lastSLTime    < activeCd) return;
   if(TimeCurrent() - g_lastEntryTime < Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;
   // Limites por sub-sesion
   if(IsEarlyNY() && g_earlyTrades >= NY_Early_Max_Trades) return;
   if(IsMainNY()  && !IsGoldenHour() && g_mainTrades >= NY_Main_Max_Trades) return;
   if(IsGoldenHour() && g_goldenTrades >= GoldenHour_Extra_Trades) return;
   ENUM_ORDER_TYPE otype = (g_cachedSig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong tk = OpenOrder(otype, g_cachedSig);
   if(tk > 0) {
      if(IsEarlyNY())        g_earlyTrades++;
      else if(IsGoldenHour()) g_goldenTrades++;
      else                   g_mainTrades++;
      g_lastEntryTime = TimeCurrent();
      g_cachedSig     = 0;
   }
}
