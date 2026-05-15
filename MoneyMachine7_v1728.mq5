//+------------------------------------------------------------------+
//|  MoneyMachine7_v1728.mq5                                        |
//|  v17.28 — FIX LATE ENTRY: precio confirma cruce en cada tick   |
//|                                                                  |
//|  DIAGNOSTICO v17.27: Net=+$11.40 | PF=1.255 | 25 trades        |
//|  WR=36% | SLs en 1-2 segundos — late entry clasico              |
//|  El cruce EMA3/8 ocurre en barra cerrada, pero al entrar en la  |
//|  barra siguiente el precio ya revirto → SL instantaneo          |
//|                                                                  |
//|  FIX: la señal se re-evalua en cada tick                        |
//|  BUY valido solo si bid > EMAf (precio sobre EMA rapida)        |
//|  SELL valido solo si bid < EMAf (precio bajo EMA rapida)        |
//|  Si el precio revierte antes de entrar → señal se cancela       |
//|  Cruce detectado en barra cerrada, entrada solo si precio        |
//|  confirma la direccion en el tick actual                         |
//|                                                                  |
//|  Sesion NY 14:30-18:30 | Lotaje dinamico | SL/TP en broker      |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.28"
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
input double MM7_TP_FIXED               = 1.00;
input double MM7_SL_FIXED               = 0.50;
input int    InpMaxSpreadPoints         = 600;
input int    InpSlippagePoints          = 10;
input int    InpMagicNumber             = 172800;
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

datetime g_lastBarTime  = 0;
datetime g_lastDashTime = 0;
datetime g_lastLblTime  = 0;
// g_barSig: direccion del cruce detectado en la barra cerrada (1/-1/0)
// Se mantiene activo hasta que el precio confirme o la barra cambie
int      g_barSig       = 0;
double   g_cachedEMAf   = 0;
double   g_cachedEMAs   = 0;
double   g_cachedEMAt   = 0;
int      g_openDir      = 0;
double   g_openEntry    = 0;

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

// Detecta cruce EMA3/8 en barras cerradas + posicion respecto EMA21
// Solo retorna la direccion del cruce — NO verifica precio actual
// La verificacion de precio actual se hace en GetLiveSignal()
int DetectCross()
{
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE ||
      g_hEMAt==INVALID_HANDLE) return 0;
   int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[], es[], et[];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   ArraySetAsSeries(et, true);
   if(CopyBuffer(g_hEMAf, 0, s, 3, ef) < 3) return 0;
   if(CopyBuffer(g_hEMAs, 0, s, 3, es) < 3) return 0;
   if(CopyBuffer(g_hEMAt, 0, s, 2, et) < 2) return 0;
   bool crossUp   = (ef[0] > es[0] && ef[1] <= es[1]);
   bool crossDown = (ef[0] < es[0] && ef[1] >= es[1]);
   if(!crossUp && !crossDown) return 0;
   // Guardar EMAs para dashboard
   g_cachedEMAf = ef[0];
   g_cachedEMAs = es[0];
   g_cachedEMAt = et[0];
   // Precio del lado correcto de EMA21 (usando EMAf como proxy del precio)
   if(crossUp   && ef[0] <= et[0]) return 0;
   if(crossDown && ef[0] >= et[0]) return 0;
   return crossUp ? 1 : -1;
}

// Verifica en tiempo real si el precio actual confirma la direccion del cruce
// BUY: bid debe estar sobre EMAf (precio no revirto)
// SELL: bid debe estar bajo EMAf (precio no revirto)
bool PriceConfirms(int dir)
{
   if(g_hEMAf == INVALID_HANDLE) return false;
   int s = (bool)MQLInfoInteger(MQL_TESTER) ? 0 : 1;
   double ef[];
   ArraySetAsSeries(ef, true);
   if(CopyBuffer(g_hEMAf, 0, s, 1, ef) < 1) return false;
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(dir ==  1) return (bid > ef[0]);
   if(dir == -1) return (bid < ef[0]);
   return false;
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
   req.comment      = "MM7-EMA";
   req.type_filling = ORDER_FILLING_FOK;
   if(!OrderSend(req, res)) {
      req.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(req, res)) {
         req.type_filling = ORDER_FILLING_RETURN;
         OrderSend(req, res);
      }
   }
   if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED) {
      g_openDir   = dir;
      g_openEntry = entry;
      Print("MM7 OPEN ", (type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=", entry, " SL=", sl, " TP=", tp,
            " lot=", req.volume,
            " EMAf=", g_cachedEMAf, " EMAs=", g_cachedEMAs, " EMA21=", g_cachedEMAt);
      return res.order;
   }
   Print("MM7 OrderSend FAIL retcode=", res.retcode);
   return 0;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult  &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY && trans.deal_type != DEAL_TYPE_SELL) return;
   ulong dk = trans.deal;
   if(!HistoryDealSelect(dk)) return;
   if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) != g_magic) return;
   if(HistoryDealGetInteger(dk, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   g_openDir = 0; g_openEntry = 0;
}

void DashLbl(string nm, string txt, color clr, int row)
{
   string f = "MM7D_" + nm;
   int lh   = Font_Size + 4;
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
   datetime ds = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   double dp = 0;
   HistorySelect(ds, TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong dk = HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk, DEAL_MAGIC) == g_magic)
         dp += HistoryDealGetDouble(dk, DEAL_PROFIT);
   }
   bool   inNY  = IsNYSession();
   color  sc    = inNY ? clrLimeGreen : clrGray;
   string sess  = inNY ? "NY 14:30-18:30" : "---";
   string posStr = "---";
   ulong  tk     = GetOpenTicket();
   if(tk > 0 && PositionSelectByTicket(tk)) {
      double pnl = PositionGetDouble(POSITION_PROFIT);
      posStr = (g_openDir==1?"BUY":"SELL") + " PnL=$" + DoubleToString(pnl,2);
   }
   string sigStr = (g_barSig==1)?"BUY wait":(g_barSig==-1)?"SELL wait":"--";
   color  dayClr = (dp >= 0) ? clrLimeGreen : clrOrangeRed;
   color  posClr = (tk > 0)  ? clrYellow    : clrGray;
   DashLbl("0", "[ MM7 v17.28 EMA3/8+EMA21 tick-confirm ]", clrGold, 0);
   DashLbl("1", "Sesion: " + sess + " | lot=" + DoubleToString(CalcLot(),2), sc, 1);
   DashLbl("2", "Bal:$" + DoubleToString(bal,2) + " Eq:$" + DoubleToString(eq,2), clrWhite, 2);
   DashLbl("3", "Day:$" + DoubleToString(dp,2), dayClr, 3);
   DashLbl("4", "EMAf:" + DoubleToString(g_cachedEMAf,2) +
               " EMAs:" + DoubleToString(g_cachedEMAs,2) +
               " EMA21:" + DoubleToString(g_cachedEMAt,2) +
               " Sig:" + sigStr, clrCyan, 4);
   DashLbl("5", "Pos: " + posStr, posClr, 5);
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
      ObjectSetString(0, nm, OBJPROP_TEXT, (pf>=0?"+":"") + DoubleToString(pf,2));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, (pf>=0)?clrLimeGreen:clrOrangeRed);
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
   if(g_hEMAf==INVALID_HANDLE || g_hEMAs==INVALID_HANDLE || g_hEMAt==INVALID_HANDLE)
   { Alert("Indicator init failed"); return INIT_FAILED; }
   Print("MM7 v17.28 EMA3/8+EMA21 tick-confirm | ", g_sym, " POINT=", g_point,
         " | SL=", MM7_SL_FIXED, " TP=", MM7_TP_FIXED,
         " | EMA(", EMA_Fast_Period, "/", EMA_Slow_Period, "/", EMA_Trend_Period, ")",
         " | NY ", NY_Start_Hour, ":", NY_Start_Min, "-", NY_End_Hour, ":", NY_End_Min);
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
   DrawDashboard();
   DrawHistoryLabels();
   if(!Control_orders_user) return;

   // Al inicio de cada barra nueva: detectar cruce en barras cerradas
   datetime curBar = iTime(g_sym, _Period, 0);
   if(curBar != g_lastBarTime) {
      g_lastBarTime = curBar;
      g_barSig = DetectCross();
   }

   // Sin señal de cruce activa → nada que hacer
   if(g_barSig == 0) return;
   if(!IsNYSession()) return;
   if(CountByMagic() >= Max_Positions) return;
   if(!SpreadOK()) return;

   // CONFIRMACION EN TIEMPO REAL: el precio debe seguir en la direccion del cruce
   // Si el precio revirto desde el cruce → no entrar, esperar siguiente barra
   if(!PriceConfirms(g_barSig)) return;

   ENUM_ORDER_TYPE otype = (g_barSig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ulong tk = OpenOrder(otype, g_barSig);
   if(tk > 0) g_barSig = 0;
}
