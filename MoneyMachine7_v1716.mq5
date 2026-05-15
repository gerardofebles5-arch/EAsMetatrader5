//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.16 — TRI-SESSION OPTIMIZADO: MÁS TRADES, MÁS GANANCIAS   |
//|                                                                  |
//|  ANÁLISIS v17.15: Net=+$22.85 | PF=1.34 | 5 trades | WR=50%   |
//|                                                                  |
//|  PROBLEMAS:                                                      |
//|  1. NY = 0 trades — momentum score bloqueó todas las señales    |
//|  2. Solo 5 trades en 4 días — max_trades=1 por sesión           |
//|  3. Asia SL=0.30pts demasiado ajustado vs rango real 3-5pts     |
//|  4. London ATR-based funciona pero necesita más oportunidades   |
//|                                                                  |
//|  MEJORAS v17.16:                                                 |
//|  1. NY: señal pura EMA3/8+EMA21 sin momentum score             |
//|     El momentum score bloqueó el 100% de las señales NY         |
//|  2. Asia: max_trades=2, SL proporcional al rango (25%)          |
//|     SL fijo de 0.30pts es irrelevante en rango de 3-5pts        |
//|  3. London: max_trades=2 para capturar continuaciones           |
//|  4. Overlap 12:00-13:00 UTC: EMA momentum extra                 |
//|     La zona más líquida del día — London+NY juntos              |
//|  5. NY ampliado a 13:00-19:00 UTC para más señales              |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.16"
#property strict

input bool   Control_orders_user        = true;
input string CommentOrder               = "MM7";
input bool   Use_dynamic_lot_           = true;
input double Lot_                       = 0.01;
input double Free_margin_for_each_Lots_ = 1000.0;
input double Max_Lot_                   = 5.0;
input int    InpMagicNumber             = 171600;
input int    InpSlippagePoints          = 10;
input int    InpMaxSpreadPoints         = 600;

// --- ASIA Range Fade 00:00-05:00 ---
input bool   Asia_Enable                = true;
input int    Asia_Build_End_Hour        = 3;     // construir rango 00:00-02:59
input int    Asia_Trade_Start_Hour      = 3;     // operar 03:00-04:59
input int    Asia_Trade_End_Hour        = 5;
input double Asia_SL_Pct                = 0.25;  // SL = 25% del rango (proporcional)
input double Asia_TP_Pct                = 0.40;  // TP = 40% del rango desde extremo
input int    Asia_Max_Trades            = 2;

// --- LONDON Breakout 07:00-12:00 ---
input bool   London_Enable              = true;
input int    London_Start_Hour          = 7;
input int    London_End_Hour            = 12;
input int    London_ATR_Period          = 14;
input double London_Break_ATR_Frac      = 0.20;
input double London_SL_ATR_Mult         = 0.8;
input double London_RR                  = 1.5;
input int    London_Max_Trades          = 2;

// --- NY + OVERLAP EMA Momentum 12:00-19:00 ---
input bool   NY_Enable                  = true;
input int    NY_Start_Hour              = 12;    // incluye overlap London-NY
input int    NY_Start_Min               = 0;
input int    NY_End_Hour                = 19;
input int    NY_End_Min                 = 0;
input int    EMA_Fast_Period            = 3;
input int    EMA_Slow_Period            = 8;
input int    EMA_Trend_Period           = 21;
input double NY_TP_FIXED                = 1.00;
input double NY_SL_FIXED                = 0.50;
input int    NY_Entry_Cooldown_Secs     = 60;
input int    NY_SL_Cooldown_Secs        = 30;

// --- Money Management ---
input double InpMaxDailyLossPct         = 5.0;
input double InpMaxEquityDrawdown       = 10.0;

// --- Dashboard ---
input bool   Enable_Dashboard           = true;
input int    Dashboard_Corner           = 0;
input int    Dashboard_X                = 10;
input int    Dashboard_Y                = 30;
input int    Font_Size                  = 10;
input bool   Enable_History_Labels      = true;

//============================================================
// GLOBALES
//============================================================
int    g_magic; string g_sym; double g_point;
int    g_hEMAf=INVALID_HANDLE, g_hEMAs=INVALID_HANDLE;
int    g_hEMAt=INVALID_HANDLE, g_hATR=INVALID_HANDLE;

datetime g_lastBar     = 0;   // guard de barra global
datetime g_dayStart    = 0;
double   g_dayStartBal = 0;
bool     g_haltedToday = false;

// Asia
double   g_asiaHigh=0, g_asiaLow=1e10;
bool     g_asiaReady=false;
int      g_asiaTrades=0;
datetime g_asiaLastSL=0;

// London
double   g_lonHigh=0, g_lonLow=1e10;
bool     g_lonReady=false;
int      g_lonTrades=0;
datetime g_lonLastSL=0;

// NY
int      g_nySig=0;
double   g_nyEMAf=0, g_nyEMAs=0;
datetime g_nyLastEntry=0, g_nyLastSL=0;

// Dashboard
datetime g_lastDash=0, g_lastLabel=0;

//============================================================
// UTILIDADES
//============================================================
int  GetHour()   { MqlDateTime d; TimeToStruct(TimeCurrent(),d); return d.hour; }
int  GetNowMin() { MqlDateTime d; TimeToStruct(TimeCurrent(),d); return d.hour*60+d.min; }

double CalcLot()
{
   if(!Use_dynamic_lot_) return NormalizeDouble(Lot_,2);
   double bal=(bool)MQLInfoInteger(MQL_TESTER)
              ?AccountInfoDouble(ACCOUNT_BALANCE)
              :MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   double lot=MathRound(bal/Free_margin_for_each_Lots_)*0.01;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot=MathMax(lot,mn); lot=MathMin(lot,MathMin(Max_Lot_,mx));
   if(st>0) lot=MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

int CountByMagic()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==g_magic) n++;
   }
   return n;
}

bool SpreadOK()
{ return ((SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/g_point<=InpMaxSpreadPoints); }

ulong SendOrder(ENUM_ORDER_TYPE type,double entry,double sl,double tp,double lot,string cmt)
{
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=type; req.price=entry; req.sl=sl; req.tp=tp;
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment=cmt;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC; OrderSend(req,res);}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED) return res.order;
   return 0;
}

void DailyReset()
{
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today==g_dayStart) return;
   g_dayStart   =today;
   g_dayStartBal=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday=false;
   g_asiaHigh=0; g_asiaLow=1e10; g_asiaReady=false; g_asiaTrades=0;
   g_lonHigh=0;  g_lonLow=1e10;  g_lonReady=false;  g_lonTrades=0;
   g_nySig=0;
}

void CheckHalt()
{
   if(g_haltedToday) return;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartBal<=0) return;
   double pct=(g_dayStartBal-eq)/g_dayStartBal*100.0;
   if(InpMaxEquityDrawdown>0&&pct>=InpMaxEquityDrawdown){g_haltedToday=true;Print("MM7 HALT DD");return;}
   if(InpMaxDailyLossPct>0&&pct>=InpMaxDailyLossPct){g_haltedToday=true;Print("MM7 HALT DL");}
}

//============================================================
// LÓGICA POR BARRA
//============================================================
void OnNewBar()
{
   int h=GetHour();

   // ── Construir rango Asia (00:00 → Asia_Build_End_Hour) ──
   if(h>=0 && h<Asia_Build_End_Hour)
   {
      double hi[],lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(g_sym,_Period,1,1,hi)>=1&&CopyLow(g_sym,_Period,1,1,lo)>=1)
      { if(hi[0]>g_asiaHigh)g_asiaHigh=hi[0]; if(lo[0]<g_asiaLow)g_asiaLow=lo[0]; }
   }
   if(h==Asia_Trade_Start_Hour && !g_asiaReady && (g_asiaHigh-g_asiaLow)>=0.30)
   { g_asiaReady=true; Print("MM7 ASIA range H=",g_asiaHigh," L=",g_asiaLow," W=",g_asiaHigh-g_asiaLow); }

   // ── Construir rango London (00:00 → London_Start_Hour) ──
   if(h>=0 && h<London_Start_Hour)
   {
      double hi[],lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(g_sym,_Period,1,1,hi)>=1&&CopyLow(g_sym,_Period,1,1,lo)>=1)
      { if(hi[0]>g_lonHigh)g_lonHigh=hi[0]; if(lo[0]<g_lonLow)g_lonLow=lo[0]; }
   }
   if(h==London_Start_Hour && !g_lonReady && (g_lonHigh-g_lonLow)>=0.30)
   { g_lonReady=true; Print("MM7 LON range H=",g_lonHigh," L=",g_lonLow," W=",g_lonHigh-g_lonLow); }

   // ── Señal NY: EMA pura sin momentum score ──────────────
   g_nySig=0;
   if(NY_Enable && g_hEMAf!=INVALID_HANDLE && g_hEMAs!=INVALID_HANDLE && g_hEMAt!=INVALID_HANDLE)
   {
      int s=(bool)MQLInfoInteger(MQL_TESTER)?0:1;
      double ef[],es[],et[];
      ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true); ArraySetAsSeries(et,true);
      if(CopyBuffer(g_hEMAf,0,s,3,ef)>=3 && CopyBuffer(g_hEMAs,0,s,3,es)>=3 && CopyBuffer(g_hEMAt,0,s,1,et)>=1)
      {
         g_nyEMAf=ef[0]; g_nyEMAs=es[0];
         double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
         bool crossUp  =(ef[0]>es[0]&&ef[1]<=es[1]);
         bool crossDown=(ef[0]<es[0]&&ef[1]>=es[1]);
         if(crossUp   && bid>et[0]) g_nySig=1;
         if(crossDown && bid<et[0]) g_nySig=-1;
      }
   }
}

//============================================================
// ENTRADAS POR SESIÓN
//============================================================
void Asia_TryEntry()
{
   if(!Asia_Enable||!g_asiaReady) return;
   if(g_asiaTrades>=Asia_Max_Trades) return;
   if(CountByMagic()>0) return;
   if(TimeCurrent()-g_asiaLastSL<120) return;
   if(!SpreadOK()) return;
   int h=GetHour();
   if(h<Asia_Trade_Start_Hour||h>=Asia_Trade_End_Hour) return;

   double range=g_asiaHigh-g_asiaLow;
   if(range<0.30) return;
   double slPts=range*Asia_SL_Pct;
   double tpPts=range*Asia_TP_Pct;
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double zone=range*0.10;  // entrar cuando precio está al 10% del extremo

   if(bid>=g_asiaHigh-zone)
   {
      double sl=NormalizeDouble(g_asiaHigh+slPts,digs);
      double tp=NormalizeDouble(bid-tpPts,digs);
      if(tp<bid&&sl>bid){
         ulong tk=SendOrder(ORDER_TYPE_SELL,bid,sl,tp,CalcLot(),"MM7-ASIA-FADE");
         if(tk>0){g_asiaTrades++;Print("MM7 ASIA SELL H=",g_asiaHigh," bid=",bid," SL=",sl," TP=",tp);}
      }
   }
   else if(ask<=g_asiaLow+zone)
   {
      double sl=NormalizeDouble(g_asiaLow-slPts,digs);
      double tp=NormalizeDouble(ask+tpPts,digs);
      if(tp>ask&&sl<ask){
         ulong tk=SendOrder(ORDER_TYPE_BUY,ask,sl,tp,CalcLot(),"MM7-ASIA-FADE");
         if(tk>0){g_asiaTrades++;Print("MM7 ASIA BUY L=",g_asiaLow," ask=",ask," SL=",sl," TP=",tp);}
      }
   }
}

void London_TryEntry()
{
   if(!London_Enable||!g_lonReady) return;
   if(g_lonTrades>=London_Max_Trades) return;
   if(CountByMagic()>0) return;
   if(TimeCurrent()-g_lonLastSL<120) return;
   if(!SpreadOK()) return;
   int h=GetHour();
   if(h<London_Start_Hour||h>=London_End_Hour) return;

   double atrBuf[]; ArraySetAsSeries(atrBuf,true);
   if(CopyBuffer(g_hATR,0,1,1,atrBuf)<1) return;
   double atr=atrBuf[0]; if(atr<=0) return;

   double closeArr[]; ArraySetAsSeries(closeArr,true);
   if(CopyClose(g_sym,_Period,1,1,closeArr)<1) return;
   double prevClose=closeArr[0];

   double minBreak=atr*London_Break_ATR_Frac;
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double risk=atr*London_SL_ATR_Mult;

   if(prevClose>g_lonHigh+minBreak)
   {
      ulong tk=SendOrder(ORDER_TYPE_BUY,ask,
                         NormalizeDouble(ask-risk,digs),
                         NormalizeDouble(ask+risk*London_RR,digs),
                         CalcLot(),"MM7-LON-BRK");
      if(tk>0){g_lonTrades++;Print("MM7 LON BUY H=",g_lonHigh," ask=",ask);}
   }
   else if(prevClose<g_lonLow-minBreak)
   {
      ulong tk=SendOrder(ORDER_TYPE_SELL,bid,
                         NormalizeDouble(bid+risk,digs),
                         NormalizeDouble(bid-risk*London_RR,digs),
                         CalcLot(),"MM7-LON-BRK");
      if(tk>0){g_lonTrades++;Print("MM7 LON SELL L=",g_lonLow," bid=",bid);}
   }
}

void NY_TryEntry()
{
   if(!NY_Enable||g_nySig==0) return;
   if(CountByMagic()>0) return;
   if(TimeCurrent()-g_nyLastSL<NY_SL_Cooldown_Secs) return;
   if(TimeCurrent()-g_nyLastEntry<NY_Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;
   int nm=GetNowMin();
   if(nm<NY_Start_Hour*60+NY_Start_Min||nm>=NY_End_Hour*60+NY_End_Min) return;

   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);

   if(g_nySig==1){
      ulong tk=SendOrder(ORDER_TYPE_BUY,ask,
                         NormalizeDouble(ask-NY_SL_FIXED,digs),
                         NormalizeDouble(ask+NY_TP_FIXED,digs),
                         CalcLot(),"MM7-NY-MOM");
      if(tk>0){g_nyLastEntry=TimeCurrent();g_nySig=0;Print("MM7 NY BUY @ ",ask);}
   }
   else if(g_nySig==-1){
      ulong tk=SendOrder(ORDER_TYPE_SELL,bid,
                         NormalizeDouble(bid+NY_SL_FIXED,digs),
                         NormalizeDouble(bid-NY_TP_FIXED,digs),
                         CalcLot(),"MM7-NY-MOM");
      if(tk>0){g_nyLastEntry=TimeCurrent();g_nySig=0;Print("MM7 NY SELL @ ",bid);}
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type!=DEAL_TYPE_BUY&&trans.deal_type!=DEAL_TYPE_SELL) return;
   ulong dk=trans.deal;
   if(!HistoryDealSelect(dk)) return;
   if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic) return;
   if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   if((ENUM_DEAL_REASON)HistoryDealGetInteger(dk,DEAL_REASON)!=DEAL_REASON_SL) return;
   string cmt=HistoryDealGetString(dk,DEAL_COMMENT);
   datetime now=TimeCurrent();
   if(StringFind(cmt,"ASIA")>=0) g_asiaLastSL=now;
   if(StringFind(cmt,"LON") >=0) g_lonLastSL=now;
   if(StringFind(cmt,"NY")  >=0) g_nyLastSL=now;
}

//============================================================
// DASHBOARD
//============================================================
void DashLbl(string nm,string txt,color clr,int row)
{
   string f="MM7D_"+nm; int lh=Font_Size+4;
   if(ObjectFind(0,f)<0){
      ObjectCreate(0,f,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,f,OBJPROP_CORNER,(ENUM_BASE_CORNER)Dashboard_Corner);
      ObjectSetInteger(0,f,OBJPROP_XDISTANCE,Dashboard_X);
      ObjectSetString(0,f,OBJPROP_FONT,"Courier New");
      ObjectSetInteger(0,f,OBJPROP_FONTSIZE,Font_Size);
   }
   ObjectSetInteger(0,f,OBJPROP_YDISTANCE,Dashboard_Y+row*lh);
   ObjectSetString(0,f,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,f,OBJPROP_COLOR,clr);
}

void DrawDashboard()
{
   if(!Enable_Dashboard||TimeCurrent()-g_lastDash<1) return;
   g_lastDash=TimeCurrent();
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
   double dd =(g_dayStartBal>0)?(g_dayStartBal-eq)/g_dayStartBal*100.0:0;
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   double dp=0; HistorySelect(ds,TimeCurrent());
   for(int i=0;i<HistoryDealsTotal();i++){
      ulong dk=HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)==g_magic)
         dp+=HistoryDealGetDouble(dk,DEAL_PROFIT);
   }
   int h=GetHour(); int nm=GetNowMin();
   string sess="---"; color sc=clrGray;
   if(h>=Asia_Trade_Start_Hour&&h<Asia_Trade_End_Hour)    {sess="ASIA (Fade)";      sc=clrDodgerBlue;}
   else if(h>=London_Start_Hour&&h<London_End_Hour)       {sess="LONDON (Breakout)";sc=clrOrange;}
   else if(nm>=NY_Start_Hour*60+NY_Start_Min&&nm<NY_End_Hour*60+NY_End_Min)
                                                          {sess="NY+OVL (Momentum)";sc=clrLimeGreen;}
   else if(h>=0&&h<Asia_Build_End_Hour)                   {sess="ASIA building";    sc=clrSteelBlue;}
   else if(h>=Asia_Build_End_Hour&&h<London_Start_Hour)   {sess="LON building";     sc=clrSandyBrown;}

   DashLbl("0","[ MoneyMachine7 v17.16 — TRI-SESSION ]",clrGold,0);
   DashLbl("1","Sesion: "+sess,sc,1);
   DashLbl("2","Bal:$"+DoubleToString(bal,2)+" Eq:$"+DoubleToString(eq,2)+" lot="+DoubleToString(CalcLot(),2),clrWhite,2);
   DashLbl("3","Day:$"+DoubleToString(dp,2)+" DD:"+DoubleToString(dd,2)+"%",(dp>=0)?clrLimeGreen:clrOrangeRed,3);
   DashLbl("4","ASIA H:"+DoubleToString(g_asiaHigh,2)+" L:"+DoubleToString(g_asiaLow>=1e9?0:g_asiaLow,2)
              +" rdy:"+(g_asiaReady?"Y":"n")+" tr:"+IntegerToString(g_asiaTrades)+"/"+IntegerToString(Asia_Max_Trades),clrDodgerBlue,4);
   DashLbl("5","LON  H:"+DoubleToString(g_lonHigh,2)+" L:"+DoubleToString(g_lonLow>=1e9?0:g_lonLow,2)
              +" rdy:"+(g_lonReady?"Y":"n")+" tr:"+IntegerToString(g_lonTrades)+"/"+IntegerToString(London_Max_Trades),clrOrange,5);
   string nySig=(g_nySig==1)?"BUY":(g_nySig==-1)?"SELL":"--";
   DashLbl("6","NY   Sig:"+nySig+" EMAf:"+DoubleToString(g_nyEMAf,2)+" EMAs:"+DoubleToString(g_nyEMAs,2),clrLimeGreen,6);
   DashLbl("7","Open:"+IntegerToString(CountByMagic())+" Halt:"+(g_haltedToday?"SI":"no"),g_haltedToday?clrOrangeRed:clrGray,7);
}

void DrawHistoryLabels()
{
   if(!Enable_History_Labels||TimeCurrent()-g_lastLabel<10) return;
   g_lastLabel=TimeCurrent();
   ObjectsDeleteAll(0,"MM7L_");
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   HistorySelect(ds,TimeCurrent());
   int tot=HistoryDealsTotal(),st=MathMax(0,tot-50);
   for(int i=st;i<tot;i++){
      ulong dk=HistoryDealGetTicket(i);
      if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic) continue;
      if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double pf=HistoryDealGetDouble(dk,DEAL_PROFIT);
      double px=HistoryDealGetDouble(dk,DEAL_PRICE);
      datetime t=(datetime)HistoryDealGetInteger(dk,DEAL_TIME);
      string nm2="MM7L_"+(string)dk;
      if(ObjectFind(0,nm2)<0) ObjectCreate(0,nm2,OBJ_TEXT,0,t,px);
      ObjectSetString(0,nm2,OBJPROP_TEXT,(pf>=0?"+":"")+DoubleToString(pf,2));
      ObjectSetInteger(0,nm2,OBJPROP_COLOR,(pf>=0)?clrLimeGreen:clrOrangeRed);
      ObjectSetInteger(0,nm2,OBJPROP_FONTSIZE,8);
   }
}

//============================================================
// OnInit / OnDeinit / OnTick
//============================================================
int OnInit()
{
   g_magic=InpMagicNumber; g_sym=_Symbol;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   g_hEMAf=iMA(g_sym,_Period,EMA_Fast_Period, 0,MODE_EMA,PRICE_CLOSE);
   g_hEMAs=iMA(g_sym,_Period,EMA_Slow_Period, 0,MODE_EMA,PRICE_CLOSE);
   g_hEMAt=iMA(g_sym,_Period,EMA_Trend_Period,0,MODE_EMA,PRICE_CLOSE);
   g_hATR =iATR(g_sym,_Period,London_ATR_Period);
   if(g_hEMAf==INVALID_HANDLE||g_hEMAs==INVALID_HANDLE||
      g_hEMAt==INVALID_HANDLE||g_hATR==INVALID_HANDLE)
   {Alert("Indicator init failed");return INIT_FAILED;}
   g_dayStart   =StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   g_dayStartBal=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   g_asiaLow=1e10; g_lonLow=1e10;
   Print("MM7 v17.16 | ASIA fade | LON breakout | NY+OVL EMA puro | guard-barra");
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
   DailyReset(); CheckHalt();
   DrawDashboard(); DrawHistoryLabels();
   if(g_haltedToday||!Control_orders_user) return;

   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar==g_lastBar) return;
   g_lastBar=curBar;

   OnNewBar();

   int h=GetHour(); int nm=GetNowMin();
   if(h>=Asia_Trade_Start_Hour&&h<Asia_Trade_End_Hour)
      Asia_TryEntry();
   else if(h>=London_Start_Hour&&h<London_End_Hour)
      London_TryEntry();
   else if(nm>=NY_Start_Hour*60+NY_Start_Min&&nm<NY_End_Hour*60+NY_End_Min)
      NY_TryEntry();
}
