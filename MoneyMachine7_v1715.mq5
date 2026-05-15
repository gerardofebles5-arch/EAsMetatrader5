//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  v17.15 — TRI-SESSION CORREGIDO + ARQUITECTURA ROBUSTA         |
//|                                                                  |
//|  DIAGNÓSTICO v17.14: Net=-$118 | 95 trades | WR=2%             |
//|                                                                  |
//|  BUG CRÍTICO: Asia_Execute() se disparaba en cada tick          |
//|  → 89 trades ASIA en un día, todos SL                          |
//|  → CountByMagic()=0 porque SL se ejecutaba antes del tick      |
//|  → La cuenta se destruyó en horas                               |
//|                                                                  |
//|  ARQUITECTURA CORREGIDA v17.15:                                 |
//|                                                                  |
//|  REGLA FUNDAMENTAL: toda lógica de entrada se ejecuta           |
//|  UNA SOLA VEZ POR BARRA M1 (guard de barra global)             |
//|  + flag booleano "ya operé esta barra" por sesión               |
//|                                                                  |
//|  SESIÓN ASIA  00:00-05:00 UTC  → RANGE FADE                    |
//|  00:00-03:59: construir rango (4h)                              |
//|  04:00-04:59: operar máximo 1 trade fade, 1 por barra           |
//|                                                                  |
//|  SESIÓN LONDON  07:00-12:00 UTC  → BREAKOUT RANGO ASIÁTICO     |
//|  Máximo 1 trade por sesión, solo en nueva barra                 |
//|  Confirmación: cierre barra anterior fuera del rango            |
//|                                                                  |
//|  SESIÓN NY  13:00-18:30 UTC  → EMA MOMENTUM (edge probado)     |
//|  75% WR histórico, señal por barra, cooldown 60s               |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.15"
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
input int    InpMagicNumber             = 171500;
input int    InpSlippagePoints          = 10;
input int    InpMaxSpreadPoints         = 600;

// --- ASIA Range Fade ---
input bool   Asia_Enable                = true;
input int    Asia_Build_Start           = 0;     // 00:00 UTC — inicio construcción rango
input int    Asia_Build_End             = 4;     // 04:00 UTC — fin construcción (4h)
input int    Asia_Trade_Start           = 4;     // 04:00 UTC — inicio trading
input int    Asia_Trade_End             = 5;     // 05:00 UTC — fin sesión Asia
input double Asia_Touch_Pct             = 0.15;  // entrar cuando precio está al 15% del extremo
input double Asia_SL_Buffer_Pts         = 0.30;  // SL más allá del extremo
input int    Asia_Max_Trades            = 1;     // máx 1 trade por sesión Asia

// --- LONDON Breakout ---
input bool   London_Enable              = true;
input int    London_Start               = 7;     // 07:00 UTC
input int    London_End                 = 12;    // 12:00 UTC
input int    London_ATR_Period          = 14;
input double London_Break_ATR_Frac      = 0.20;  // breakout mínimo = 0.20 * ATR
input double London_SL_ATR_Mult         = 1.0;   // SL = 1.0 * ATR
input double London_RR                  = 1.5;   // TP = 1.5 * riesgo
input int    London_Max_Trades          = 1;     // máx 1 trade por sesión Londres

// --- NY EMA Momentum ---
input bool   NY_Enable                  = true;
input int    NY_Start_Hour              = 13;
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

int    g_hEMAf = INVALID_HANDLE;
int    g_hEMAs = INVALID_HANDLE;
int    g_hEMAt = INVALID_HANDLE;
int    g_hATR  = INVALID_HANDLE;

// *** GUARD DE BARRA GLOBAL — la clave de todo ***
datetime g_lastBarProcessed = 0;

// Estado diario
datetime g_dayStart    = 0;
double   g_dayStartBal = 0;
bool     g_haltedToday = false;

// Estado Asia
double   g_asiaHigh       = 0;
double   g_asiaLow        = 1e10;
bool     g_asiaRangeReady = false;
int      g_asiaTrades     = 0;
datetime g_asiaLastSL     = 0;

// Estado London
double   g_lonHigh        = 0;
double   g_lonLow         = 1e10;
bool     g_lonRangeReady  = false;
int      g_lonTrades      = 0;
datetime g_lonLastSL      = 0;

// Estado NY
int      g_nySig          = 0;
double   g_nyEMAf         = 0;
double   g_nyEMAs         = 0;
double   g_nyMom          = 0;
double   g_nyMomThr       = 0;
datetime g_nyLastEntry    = 0;
datetime g_nyLastSL       = 0;

// Dashboard
datetime g_lastDash  = 0;
datetime g_lastLabel = 0;

//============================================================
// UTILIDADES
//============================================================
int  GetHour()   { MqlDateTime d; TimeToStruct(TimeCurrent(),d); return d.hour; }
int  GetMin()    { MqlDateTime d; TimeToStruct(TimeCurrent(),d); return d.min; }
int  GetNowMin() { MqlDateTime d; TimeToStruct(TimeCurrent(),d); return d.hour*60+d.min; }

double CalcLot()
{
   if(!Use_dynamic_lot_) return NormalizeDouble(Lot_,2);
   double bal = (bool)MQLInfoInteger(MQL_TESTER)
                ? AccountInfoDouble(ACCOUNT_BALANCE)
                : MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   double lot = MathRound(bal/Free_margin_for_each_Lots_)*0.01;
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
{
   return ((SymbolInfoDouble(g_sym,SYMBOL_ASK)-SymbolInfoDouble(g_sym,SYMBOL_BID))/g_point
           <= InpMaxSpreadPoints);
}

ulong SendOrder(ENUM_ORDER_TYPE type, double entry, double sl, double tp, double lot, string cmt)
{
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=type; req.price=entry; req.sl=sl; req.tp=tp;
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment=cmt;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){ req.type_filling=ORDER_FILLING_IOC; OrderSend(req,res); }
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED) return res.order;
   return 0;
}

void DailyReset()
{
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today==g_dayStart) return;
   g_dayStart    = today;
   g_dayStartBal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   g_haltedToday = false;
   // Reset sesiones
   g_asiaHigh=0; g_asiaLow=1e10; g_asiaRangeReady=false; g_asiaTrades=0;
   g_lonHigh=0;  g_lonLow=1e10;  g_lonRangeReady=false;  g_lonTrades=0;
   g_nySig=0;
   Print("MM7 DailyReset | bal=",AccountInfoDouble(ACCOUNT_BALANCE));
}

void CheckHalt()
{
   if(g_haltedToday) return;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartBal<=0) return;
   double pct=(g_dayStartBal-eq)/g_dayStartBal*100.0;
   if(InpMaxEquityDrawdown>0 && pct>=InpMaxEquityDrawdown)
   { g_haltedToday=true; Print("MM7 HALT DD ",pct,"%"); return; }
   if(InpMaxDailyLossPct>0 && pct>=InpMaxDailyLossPct)
   { g_haltedToday=true; Print("MM7 HALT DailyLoss ",pct,"%"); }
}

//============================================================
// LÓGICA POR BARRA — se llama UNA VEZ por barra M1
//============================================================

void OnNewBar()
{
   int h = GetHour();

   // ── CONSTRUIR RANGO ASIA (00:00-03:59) ──────────────────
   if(h >= Asia_Build_Start && h < Asia_Build_End)
   {
      double hi[], lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(g_sym,_Period,1,1,hi)>=1 && CopyLow(g_sym,_Period,1,1,lo)>=1)
      {
         if(hi[0]>g_asiaHigh) g_asiaHigh=hi[0];
         if(lo[0]<g_asiaLow)  g_asiaLow=lo[0];
      }
   }

   // Marcar rango Asia listo cuando empieza la ventana de trading
   if(h==Asia_Trade_Start && !g_asiaRangeReady)
   {
      double width=g_asiaHigh-g_asiaLow;
      if(width>=0.50)
      {
         g_asiaRangeReady=true;
         Print("MM7 ASIA range: H=",g_asiaHigh," L=",g_asiaLow," W=",width);
      }
   }

   // ── CONSTRUIR RANGO LONDON (00:00-06:59) ────────────────
   if(h < London_Start)
   {
      double hi[], lo[];
      ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true);
      if(CopyHigh(g_sym,_Period,1,1,hi)>=1 && CopyLow(g_sym,_Period,1,1,lo)>=1)
      {
         if(hi[0]>g_lonHigh) g_lonHigh=hi[0];
         if(lo[0]<g_lonLow)  g_lonLow=lo[0];
      }
   }

   // Marcar rango London listo cuando abre Londres
   if(h==London_Start && !g_lonRangeReady)
   {
      double width=g_lonHigh-g_lonLow;
      if(width>=0.30)
      {
         g_lonRangeReady=true;
         Print("MM7 LONDON range: H=",g_lonHigh," L=",g_lonLow," W=",width);
      }
   }

   // ── SEÑAL NY (calcular una vez por barra) ───────────────
   g_nySig = 0;
   if(NY_Enable && g_hEMAf!=INVALID_HANDLE && g_hEMAs!=INVALID_HANDLE && g_hEMAt!=INVALID_HANDLE)
   {
      int start=(bool)MQLInfoInteger(MQL_TESTER)?0:1;
      double ef[],es[],et[];
      ArraySetAsSeries(ef,true); ArraySetAsSeries(es,true); ArraySetAsSeries(et,true);
      if(CopyBuffer(g_hEMAf,0,start,3,ef)>=3 &&
         CopyBuffer(g_hEMAs,0,start,3,es)>=3 &&
         CopyBuffer(g_hEMAt,0,start,1,et)>=1)
      {
         g_nyEMAf=ef[0]; g_nyEMAs=es[0];
         bool crossUp  =(ef[0]>es[0]&&ef[1]<=es[1]);
         bool crossDown=(ef[0]<es[0]&&ef[1]>=es[1]);
         double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);

         if(crossUp   && bid>et[0]) g_nySig=1;
         if(crossDown && bid<et[0]) g_nySig=-1;

         // Momentum score adaptativo
         if(g_nySig!=0)
         {
            double sep=MathAbs(ef[0]-es[0]);
            g_nyMom=sep;
            int needed=NY_Momentum_Lookback+start+1;
            double ef2[],es2[];
            ArraySetAsSeries(ef2,true); ArraySetAsSeries(es2,true);
            if(CopyBuffer(g_hEMAf,0,start,needed,ef2)>=needed &&
               CopyBuffer(g_hEMAs,0,start,needed,es2)>=needed)
            {
               double sum=0;
               for(int i=1;i<=NY_Momentum_Lookback;i++) sum+=MathAbs(ef2[i]-es2[i]);
               g_nyMomThr=sum/NY_Momentum_Lookback;
               if(g_nyMomThr>0 && sep<g_nyMomThr*NY_Momentum_Min_Ratio) g_nySig=0;
            }
         }
      }
   }
}

//============================================================
// EJECUCIÓN POR SESIÓN — también por barra, después de OnNewBar
//============================================================

void Asia_TryEntry()
{
   if(!Asia_Enable || !g_asiaRangeReady) return;
   if(g_asiaTrades >= Asia_Max_Trades) return;
   if(CountByMagic() > 0) return;
   if(TimeCurrent()-g_asiaLastSL < 120) return;
   if(!SpreadOK()) return;

   int h=GetHour();
   if(h<Asia_Trade_Start || h>=Asia_Trade_End) return;

   double range=g_asiaHigh-g_asiaLow;
   if(range<=0) return;
   double zone=range*Asia_Touch_Pct;
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);

   // SELL fade: precio en zona superior del rango
   if(bid >= g_asiaHigh - zone)
   {
      double sl=NormalizeDouble(g_asiaHigh+Asia_SL_Buffer_Pts,digs);
      double tp=NormalizeDouble(g_asiaLow+zone,digs);  // TP cerca del suelo
      if(tp<bid && sl>bid)
      {
         ulong tk=SendOrder(ORDER_TYPE_SELL,bid,sl,tp,CalcLot(),"MM7-ASIA-FADE");
         if(tk>0){ g_asiaTrades++; Print("MM7 ASIA SELL fade H=",g_asiaHigh," bid=",bid," SL=",sl," TP=",tp); }
      }
   }
   // BUY fade: precio en zona inferior del rango
   else if(ask <= g_asiaLow + zone)
   {
      double sl=NormalizeDouble(g_asiaLow-Asia_SL_Buffer_Pts,digs);
      double tp=NormalizeDouble(g_asiaHigh-zone,digs);  // TP cerca del techo
      if(tp>ask && sl<ask)
      {
         ulong tk=SendOrder(ORDER_TYPE_BUY,ask,sl,tp,CalcLot(),"MM7-ASIA-FADE");
         if(tk>0){ g_asiaTrades++; Print("MM7 ASIA BUY fade L=",g_asiaLow," ask=",ask," SL=",sl," TP=",tp); }
      }
   }
}

void London_TryEntry()
{
   if(!London_Enable || !g_lonRangeReady) return;
   if(g_lonTrades >= London_Max_Trades) return;
   if(CountByMagic() > 0) return;
   if(TimeCurrent()-g_lonLastSL < 120) return;
   if(!SpreadOK()) return;

   int h=GetHour();
   if(h<London_Start || h>=London_End) return;

   double atrBuf[]; ArraySetAsSeries(atrBuf,true);
   if(CopyBuffer(g_hATR,0,1,1,atrBuf)<1) return;
   double atr=atrBuf[0];
   if(atr<=0) return;

   // Usar cierre de barra anterior para confirmación
   double closeArr[]; ArraySetAsSeries(closeArr,true);
   if(CopyClose(g_sym,_Period,1,1,closeArr)<1) return;
   double prevClose=closeArr[0];

   double minBreak=atr*London_Break_ATR_Frac;
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double risk=atr*London_SL_ATR_Mult;

   if(prevClose > g_lonHigh+minBreak)
   {
      double sl=NormalizeDouble(ask-risk,digs);
      double tp=NormalizeDouble(ask+risk*London_RR,digs);
      ulong tk=SendOrder(ORDER_TYPE_BUY,ask,sl,tp,CalcLot(),"MM7-LON-BRK");
      if(tk>0){ g_lonTrades++; Print("MM7 LON BUY brk H=",g_lonHigh," ask=",ask," SL=",sl," TP=",tp); }
   }
   else if(prevClose < g_lonLow-minBreak)
   {
      double sl=NormalizeDouble(bid+risk,digs);
      double tp=NormalizeDouble(bid-risk*London_RR,digs);
      ulong tk=SendOrder(ORDER_TYPE_SELL,bid,sl,tp,CalcLot(),"MM7-LON-BRK");
      if(tk>0){ g_lonTrades++; Print("MM7 LON SELL brk L=",g_lonLow," bid=",bid," SL=",sl," TP=",tp); }
   }
}

void NY_TryEntry()
{
   if(!NY_Enable || g_nySig==0) return;
   if(CountByMagic()>0) return;
   if(TimeCurrent()-g_nyLastSL<NY_SL_Cooldown_Secs) return;
   if(TimeCurrent()-g_nyLastEntry<NY_Entry_Cooldown_Secs) return;
   if(!SpreadOK()) return;

   int nowMin=GetNowMin();
   if(nowMin<NY_Start_Hour*60+NY_Start_Min || nowMin>=NY_End_Hour*60+NY_End_Min) return;

   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);

   if(g_nySig==1)
   {
      ulong tk=SendOrder(ORDER_TYPE_BUY,ask,
                         NormalizeDouble(ask-NY_SL_FIXED,digs),
                         NormalizeDouble(ask+NY_TP_FIXED,digs),
                         CalcLot(),"MM7-NY-MOM");
      if(tk>0){ g_nyLastEntry=TimeCurrent(); g_nySig=0; Print("MM7 NY BUY @ ",ask); }
   }
   else if(g_nySig==-1)
   {
      ulong tk=SendOrder(ORDER_TYPE_SELL,bid,
                         NormalizeDouble(bid+NY_SL_FIXED,digs),
                         NormalizeDouble(bid-NY_TP_FIXED,digs),
                         CalcLot(),"MM7-NY-MOM");
      if(tk>0){ g_nyLastEntry=TimeCurrent(); g_nySig=0; Print("MM7 NY SELL @ ",bid); }
   }
}

//============================================================
// OnTradeTransaction
//============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
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
   Print("MM7 SL: ",cmt);
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
   if(h>=Asia_Trade_Start&&h<Asia_Trade_End)          {sess="ASIA (Range Fade)";   sc=clrDodgerBlue;}
   else if(h>=London_Start&&h<London_End)             {sess="LONDON (Breakout)";   sc=clrOrange;}
   else if(nm>=NY_Start_Hour*60+NY_Start_Min&&nm<NY_End_Hour*60+NY_End_Min)
                                                      {sess="NY (EMA Momentum)";   sc=clrLimeGreen;}
   else if(h>=Asia_Build_Start&&h<Asia_Build_End)     {sess="ASIA building range"; sc=clrSteelBlue;}
   else if(h>=Asia_Build_End&&h<London_Start)         {sess="LON building range";  sc=clrSandyBrown;}

   DashLbl("0","[ MoneyMachine7 v17.15 — TRI-SESSION ]",clrGold,0);
   DashLbl("1","Sesion: "+sess,sc,1);
   DashLbl("2","Bal:$"+DoubleToString(bal,2)+" Eq:$"+DoubleToString(eq,2)+" lot="+DoubleToString(CalcLot(),2),clrWhite,2);
   DashLbl("3","Day:$"+DoubleToString(dp,2)+" DD:"+DoubleToString(dd,2)+"%",(dp>=0)?clrLimeGreen:clrOrangeRed,3);
   string asiaStr="ASIA H:"+DoubleToString(g_asiaHigh,2)+" L:"+DoubleToString(g_asiaLow>=1e9?0:g_asiaLow,2)
                  +" rdy:"+(g_asiaRangeReady?"Y":"n")+" tr:"+IntegerToString(g_asiaTrades);
   DashLbl("4",asiaStr,clrDodgerBlue,4);
   string lonStr ="LON  H:"+DoubleToString(g_lonHigh,2)+" L:"+DoubleToString(g_lonLow>=1e9?0:g_lonLow,2)
                  +" rdy:"+(g_lonRangeReady?"Y":"n")+" tr:"+IntegerToString(g_lonTrades);
   DashLbl("5",lonStr,clrOrange,5);
   string nySig=(g_nySig==1)?"BUY":(g_nySig==-1)?"SELL":"--";
   DashLbl("6","NY   Sig:"+nySig+" Mom:"+DoubleToString(g_nyMom,4)+" Thr:"+DoubleToString(g_nyMomThr,4),clrLimeGreen,6);
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

   Print("MM7 v17.15 TRI-SESSION | guard-barra activo | ASIA fade | LON breakout | NY EMA");
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
   DrawDashboard();
   DrawHistoryLabels();

   if(g_haltedToday||!Control_orders_user) return;

   // *** GUARD DE BARRA — toda la lógica de entrada solo en barra nueva ***
   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar==g_lastBarProcessed) return;
   g_lastBarProcessed=curBar;

   // 1. Actualizar rangos y señales (una vez por barra)
   OnNewBar();

   // 2. Intentar entrada según sesión activa
   int h=GetHour();
   int nowMin=GetNowMin();

   if(h>=Asia_Trade_Start && h<Asia_Trade_End)
      Asia_TryEntry();
   else if(h>=London_Start && h<London_End)
      London_TryEntry();
   else if(nowMin>=NY_Start_Hour*60+NY_Start_Min && nowMin<NY_End_Hour*60+NY_End_Min)
      NY_TryEntry();
}
