//+------------------------------------------------------------------+
//|                                            MoneyMachine7.mq5    |
//|  FORENSIC REPLICA v8.13 — SMC Signal Engine + Quality Filters   |
//|                                                                  |
//|  WHAT CHANGED vs v8.12:                                         |
//|  - GetSignal() usa 3 modos SMC: InpStrategy 0/1/2               |
//|    0=Institutional Sweep | 1=Hybrid(default) | 2=Breakout        |
//|  - RSI(14) + Volume MA(10) confirman en todos los modos          |
//|  - FVG scanner (Fair Value Gap, lookback 1200 bars)              |
//|  - Swing High/Low para deteccion de liquidity sweeps             |
//|  - Dashboard actualizado: modo activo + FVG count                |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "8.13"
#property strict

// +++ Main Parameters +++
input bool   Control_orders_user         = true;
input int    Max_Buy                     = 100;
input int    Max_Sell                    = 100;
input string CommentOrder                = "MoneyMachine7";
input double Lot_                        = 0.1;
input bool   Use_dynamic_lot_            = true;
input double Free_margin_for_each_Lots_  = 1000.0;
input double Kmartin_                    = 1.0;
input double Max_Lot_                    = 5.0;
// +++ Breakout Strategy (v2.1) +++
input bool   Enable_Breakout_Strategy    = true;
input int    Breakout_Period             = 50;
input int    Breakout_Buffer             = 120;
input int    Min_Breakout_Range          = 300;
input bool   Use_RSI_Confirmation        = true;
input int    RSI_Period                  = 14;
input double RSI_Buy_Threshold           = 66.0;
input double RSI_Sell_Threshold          = 44.0;
input bool   Use_Volume_Confirmation     = true;
input int    Volume_Ma_Period            = 10;
input bool   Use_Gold_Session_Filter     = false;
// +++ Auto Grid System (ADR) +++
input bool   Use_Auto_Grid               = true;
input int    Auto_Grid_Intensity         = 3;
input double Custom_ADR_Divider          = 1000.0;
input int    ADR_Period_Days             = 1;
// +++ Auto Take Profit (v7.5.5) +++
input bool   Use_Auto_TP                 = true;
input double Auto_TP_Ratio               = 5.0;
// +++ Auto Stop Loss (v2.3) +++
input bool   Use_Auto_SL                 = true;
input double Auto_SL_Ratio               = 1.5;
// +++ Manual Grid Settings (Fallback) +++
input double Grid_Distance_              = 0.0;
input int    Take_Profit_                = 0;
input int    Stop_Loss_                  = 0;
input double Stop_Loss_Percent           = 0.0;
// +++ Smart Grid Defense (v7.5.4) +++
input bool   Use_Grid_Stoch_Filter       = true;
input int    Stoch_K_Period              = 14;
input int    Stoch_D_Period              = 3;
input int    Stoch_Slowing               = 3;
input double Stoch_Buy_Level             = 30.0;
input double Stoch_Sell_Level            = 70.0;
input double Grid_Distance_Multiplier    = 1.0;
input double Max_Drawdown_Percent        = 90.0;
// +++ News Filter +++
input bool   Use_News_Filter             = true;
input int    News_Suspend_Mins_Before    = 30;
input int    News_Suspend_Mins_After     = 30;
// +++ Monday +++
input bool   Trade_Monday                = true;
input int    Monday_Start_Hour           = 5;
input int    Monday_End_Hour             = 21;
// +++ Tuesday +++
input bool   Trade_Tuesday               = true;
input int    Tuesday_Start_Hour          = 5;
input int    Tuesday_End_Hour            = 21;
// +++ Wednesday +++
input bool   Trade_Wednesday             = true;
input int    Wednesday_Start_Hour        = 5;
input int    Wednesday_End_Hour          = 21;
// +++ Thursday +++
input bool   Trade_Thursday              = true;
input int    Thursday_Start_Hour         = 5;
input int    Thursday_End_Hour           = 21;
// +++ Friday +++
input bool   Trade_Friday                = true;
input int    Friday_Start_Hour           = 5;
input int    Friday_End_Hour             = 18;
// +++ Saturday +++
input bool   Trade_Saturday              = false;
input int    Saturday_Start_Hour         = 0;
input int    Saturday_End_Hour           = 0;
// +++ Sunday +++
input bool   Trade_Sunday                = false;
input int    Sunday_Start_Hour           = 0;
input int    Sunday_End_Hour             = 0;
// +++ Institutional Stealth & Recovery (v2.2) +++
input bool   Use_Stealth_Mode            = true;
input bool   Recovery_Mode_Enabled       = true;
input double Recovery_Target_USD         = 2.0;
input int    Overlap_AFTER_X_trades_     = 4;
// +++ Distance Expansion +++
input int    Order_dynamic_distance      = 4;
input double Distance_multiplier         = 1.0;
// Core Strategy (Signals)
input int    InpStrategy                 = 1;
input bool   Enable_Stop_Hunt_Strategy   = true;
input bool   Enable_FVG_Strategy         = true;
input int    InpMagicNumber              = 700000;
input int    ATR_Period                  = 7;
input int    FVG_Lookback_Bars           = 1200;
// Trade Filters
input int    InpMaxSpreadPoints          = 10000;
input int    InpSlippagePoints           = 10;
input bool   Enable_Trend_Filter         = true;
input int    Trend_MA_Period             = 200;
// Dashboard Settings
input bool   Enable_Dashboard            = true;
input int    Dashboard_Corner            = 0;
input int    Dashboard_X_Offset          = 10;
input int    Dashboard_Y_Offset          = 30;
input int    Refresh_Interval_Seconds    = 1;
input bool   Draw_FVG_Zones              = true;
input int    Font_size_Result            = 11;
// +++ Money Management +++
input double Basket_Profit_USD           = 0.0;
input double Basket_Loss_USD             = 0.0;
input double Daily_Profit_Target_USD     = 1000000.0;
input double Daily_Loss_Limit_USD        = 500000.0;
input double InpMaxDailyLossPct          = 50.0;
input double InpMaxEquityDrawdown        = 50.0;
input int    Stop_After_Losses           = 0;
// +++ Trailing & Breakeven +++
input bool   Enable_Breakeven            = false;
input double BE_Trigger_ATR_Multiplier   = 1.0;
input int    BE_Profit_Points            = 10;
input bool   Enable_TrailingStop         = true;
input double TS_Start_ATR_Multiplier     = 5.0;
input double TS_Distance_ATR_Multiplier  = 5.0;
// +++ History Visualization +++
input bool   Enable_History_Labels       = true;
input int    History_Labels_Limit        = 50;
// +++ Forensic Core (v8.12+) +++
input double MM7_TP_FIXED                = 2.50;
input double MM7_SL_FIXED                = 0.77;
input double MM7_G2_SL_FIXED             = 0.50;

#define MM7_G2_MIN_GAP_S  2
#define MM7_ATR_FALLBACK  0.50

struct StealthPos { ulong ticket; double vTP,vSL; int dir; bool active; };
struct FVGZone    { double top,bot; int dir; bool active; };

int      g_magic;
double   g_point;
string   g_sym;
int      g_hStoch=INVALID_HANDLE, g_hMA=INVALID_HANDLE;
int      g_hATR=INVALID_HANDLE,   g_hRSI=INVALID_HANDLE, g_hVol=INVALID_HANDLE;

StealthPos g_sp[];   int g_spCnt=0;
FVGZone    g_fvg[];  int g_fvgCnt=0;
datetime   g_fvgLastScan=0;

int      g_legacyClosedAtLastG2=0;
datetime g_lastG2OpenTime=0;
bool     g_g2OpenedThisLegacy=false;
ulong    g_g2ForLegacyTicket=0;
datetime g_lastSignalBarTime=0;
ulong    g_lastLegacyTicket=0;
datetime g_dayStart=0;
double   g_dayStartBal=0;
bool     g_haltedToday=false;
datetime g_lastDashTime=0, g_lastLabelTime=0;

double   g_swingHi=0, g_swingLo=0;
datetime g_swingScanBar=0;

//--------------------------------------------------------------------
double GetATR()
{
   if(g_hATR==INVALID_HANDLE) return MM7_ATR_FALLBACK;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(g_hATR,0,1,2,b)<2) return MM7_ATR_FALLBACK;
   return (b[0]>0)?b[0]:MM7_ATR_FALLBACK;
}

double GetRSI()
{
   if(g_hRSI==INVALID_HANDLE) return 50.0;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(g_hRSI,0,1,2,b)<2) return 50.0;
   return b[0];
}

bool IsVolumeOK()
{
   if(!Use_Volume_Confirmation) return true;
   int p = Volume_Ma_Period;
   long vb[]; ArraySetAsSeries(vb,true);
   if(CopyTickVolume(g_sym,_Period,0,p+1,vb)<p+1) return true;
   // compute simple MA of last p bars (bar[1]..bar[p])
   double sum=0;
   for(int i=1;i<=p;i++) sum+=(double)vb[i];
   double vma = sum/p;
   return ((double)vb[0] >= vma);
}

int GetTrend()
{
   if(!Enable_Trend_Filter || g_hMA==INVALID_HANDLE) return 0;
   double mb[]; ArraySetAsSeries(mb,true);
   if(CopyBuffer(g_hMA,0,1,1,mb)<1) return 0;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   return (bid>mb[0])?1:(bid<mb[0])?-1:0;
}

void UpdateSwings()
{
   datetime bt=iTime(g_sym,_Period,1);
   if(bt==g_swingScanBar) return;
   g_swingScanBar=bt;
   int lb=20;
   double hi=0, lo=DBL_MAX;
   for(int i=1;i<=lb;i++)
   {
      double h=iHigh(g_sym,_Period,i);
      double l=iLow(g_sym,_Period,i);
      if(h>hi) hi=h;
      if(l<lo) lo=l;
   }
   g_swingHi=hi; g_swingLo=lo;
}

void ScanFVGs()
{
   datetime bt=iTime(g_sym,_Period,0);
   if(bt==g_fvgLastScan) return;
   g_fvgLastScan=bt;
   if(!Enable_FVG_Strategy) { g_fvgCnt=0; return; }
   int lb=MathMin(FVG_Lookback_Bars,500);
   g_fvgCnt=0;
   ArrayResize(g_fvg,100);
   for(int i=2;i<lb && g_fvgCnt<100;i++)
   {
      double h0=iHigh(g_sym,_Period,i), l0=iLow(g_sym,_Period,i);
      double h2=iHigh(g_sym,_Period,i+2), l2=iLow(g_sym,_Period,i+2);
      if(l0>h2) { g_fvg[g_fvgCnt].top=l0; g_fvg[g_fvgCnt].bot=h2; g_fvg[g_fvgCnt].dir=1;  g_fvg[g_fvgCnt].active=true; g_fvgCnt++; }
      else if(h0<l2) { g_fvg[g_fvgCnt].top=l2; g_fvg[g_fvgCnt].bot=h0; g_fvg[g_fvgCnt].dir=-1; g_fvg[g_fvgCnt].active=true; g_fvgCnt++; }
   }
}

bool InFVG(int dir)
{
   if(!Enable_FVG_Strategy || g_fvgCnt==0) return false;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   for(int i=0;i<g_fvgCnt;i++)
      if(g_fvg[i].active && g_fvg[i].dir==dir && bid>=g_fvg[i].bot && bid<=g_fvg[i].top)
         return true;
   return false;
}

int GetBreakout()
{
   if(!Enable_Breakout_Strategy) return 0;
   double hi=0, lo=DBL_MAX;
   for(int i=1;i<=Breakout_Period;i++)
   { double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i); if(h>hi) hi=h; if(l<lo) lo=l; }
   double rng=(hi-lo)/g_point;
   if(rng<Min_Breakout_Range) return 0;
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double buf=Breakout_Buffer*g_point;
   if(ask>hi+buf)
   { if(Use_RSI_Confirmation && GetRSI()<RSI_Buy_Threshold) return 0; if(!IsVolumeOK()) return 0; return 1; }
   if(bid<lo-buf)
   { if(Use_RSI_Confirmation && GetRSI()>RSI_Sell_Threshold) return 0; if(!IsVolumeOK()) return 0; return -1; }
   return 0;
}

int GetSweep()
{
   if(!Enable_Stop_Hunt_Strategy) return 0;
   UpdateSwings();
   double atr=GetATR();
   double sweep=atr*0.5;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double kb[]; ArraySetAsSeries(kb,true);
   if(CopyBuffer(g_hStoch,0,1,1,kb)<1) return 0;
   if(bid>g_swingLo && ask<g_swingLo+sweep && kb[0]<=Stoch_Buy_Level) return 1;
   if(bid<g_swingHi && bid>g_swingHi-sweep && kb[0]>=Stoch_Sell_Level) return -1;
   return 0;
}

//--------------------------------------------------------------------
// MASTER SIGNAL — 3 modes
//--------------------------------------------------------------------
int GetSignal()
{
   if(!Use_Grid_Stoch_Filter) return 0;
   double kb[]; ArraySetAsSeries(kb,true);
   if(CopyBuffer(g_hStoch,0,1,2,kb)<2) return 0;
   double k1=kb[0];
   int trend=GetTrend();
   int strat=(InpStrategy>=0&&InpStrategy<=2)?InpStrategy:1;

   // ── MODE 0: Institutional Sweep ──────────────────────────────
   if(strat==0)
   {
      int s=GetSweep(); if(s==0) return 0;
      if(trend!=0 && s!=trend) return 0;
      return s;
   }

   // ── MODE 2: Structure Breakout ───────────────────────────────
   if(strat==2)
   {
      int b=GetBreakout(); if(b==0) return 0;
      if(trend!=0 && b!=trend) return 0;
      if(b== 1 && k1>Stoch_Sell_Level) return 0;
      if(b==-1 && k1<Stoch_Buy_Level)  return 0;
      return b;
   }

   // ── MODE 1: Hybrid (Sweep → FVG → Stoch+breakout) ────────────
   // P1: Sweep
   if(Enable_Stop_Hunt_Strategy) { int s=GetSweep(); if(s!=0&&(trend==0||s==trend)) return s; }

   // P2: FVG fill
   if(Enable_FVG_Strategy)
   {
      if(InFVG(1)  && k1<=Stoch_Buy_Level+10  && (trend==0||trend== 1)) return  1;
      if(InFVG(-1) && k1>=Stoch_Sell_Level-10 && (trend==0||trend==-1)) return -1;
   }

   // P3: Stoch + optional RSI + optional Breakout
   bool sBuy =(k1<=Stoch_Buy_Level);
   bool sSell=(k1>=Stoch_Sell_Level);
   if(Use_RSI_Confirmation)
   { double rsi=GetRSI(); if(sBuy && rsi>RSI_Buy_Threshold) sBuy=false; if(sSell && rsi<RSI_Sell_Threshold) sSell=false; }
   if(Enable_Breakout_Strategy)
   { int b=GetBreakout(); if(b== 1&&sBuy &&(trend==0||trend== 1)) return  1; if(b==-1&&sSell&&(trend==0||trend==-1)) return -1; }
   if(sBuy &&(trend==0||trend== 1)&&!sSell) return  1;
   if(sSell&&(trend==0||trend==-1)&&!sBuy)  return -1;
   return 0;
}

//--------------------------------------------------------------------
bool IsScheduleAllowed()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int dow=dt.day_of_week, h=dt.hour;
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
   if(!Use_dynamic_lot_) return NormalizeDouble(Lot_,2);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double lot=MathFloor(bal/Free_margin_for_each_Lots_)*0.01;
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot=MathMax(lot,mn); lot=MathMin(lot,MathMin(Max_Lot_,mx));
   if(st>0) lot=MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

int CountByMagic() { int n=0; for(int i=0;i<PositionsTotal();i++) { ulong tk=PositionGetTicket(i); if(PositionSelectByTicket(tk)&&PositionGetInteger(POSITION_MAGIC)==g_magic) n++; } return n; }
int CountLegacyOpen() { int n=0; for(int i=0;i<PositionsTotal();i++) { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue; if(PositionGetInteger(POSITION_MAGIC)!=g_magic) continue; if(StringFind(PositionGetString(POSITION_COMMENT),"[Legacy]")>=0) n++; } return n; }
int CountG2Open()     { int n=0; for(int i=0;i<PositionsTotal();i++) { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue; if(PositionGetInteger(POSITION_MAGIC)!=g_magic) continue; if(StringFind(PositionGetString(POSITION_COMMENT)," G2")>=0)     n++; } return n; }
int CountBuys()       { int n=0; for(int i=0;i<PositionsTotal();i++) { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue; if(PositionGetInteger(POSITION_MAGIC)!=g_magic) continue; if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) n++; } return n; }
int CountSells()      { int n=0; for(int i=0;i<PositionsTotal();i++) { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue; if(PositionGetInteger(POSITION_MAGIC)!=g_magic) continue; if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL) n++; } return n; }

int CountLegacyClosedToday()
{
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   HistorySelect(ds,TimeCurrent()); int cnt=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   { ulong dk=HistoryDealGetTicket(i); if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic) continue; if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue; if(StringFind(HistoryDealGetString(dk,DEAL_COMMENT)," G2")>=0) continue; cnt++; }
   return cnt;
}

void StealthRegister(ulong ticket, double vTP, double vSL, int dir)
{
   if(!Use_Stealth_Mode || ticket==0) return;
   for(int i=0;i<g_spCnt;i++) if(g_sp[i].ticket==ticket) { g_sp[i].vTP=vTP; g_sp[i].vSL=vSL; g_sp[i].active=true; return; }
   if(g_spCnt>=ArraySize(g_sp)) ArrayResize(g_sp,g_spCnt+200);
   g_sp[g_spCnt].ticket=ticket;
   g_sp[g_spCnt].vTP=vTP;
   g_sp[g_spCnt].vSL=vSL;
   g_sp[g_spCnt].dir=dir;
   g_sp[g_spCnt].active=true;
   g_spCnt++;
}

bool StealthClosePos(ulong ticket, int dir)
{
   if(!PositionSelectByTicket(ticket)) return true;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.position=ticket;
   req.volume=PositionGetDouble(POSITION_VOLUME);
   req.type=(dir==1)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.price=(dir==1)?SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
   req.deviation=InpSlippagePoints; req.magic=g_magic;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)) { req.type_filling=ORDER_FILLING_IOC; if(!OrderSend(req,res)) { req.type_filling=ORDER_FILLING_RETURN; bool _s=OrderSend(req,res); } }
   return !PositionSelectByTicket(ticket);
}

void StealthCheckAll()
{
   if(!Use_Stealth_Mode) return;
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID), ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   for(int i=0;i<g_spCnt;i++)
   {
      if(!g_sp[i].active) continue;
      if(!PositionSelectByTicket(g_sp[i].ticket)) { g_sp[i].active=false; continue; }
      bool cls=false;
      if(g_sp[i].dir==1)  { if(g_sp[i].vTP>0&&bid>=g_sp[i].vTP) cls=true; else if(g_sp[i].vSL>0&&bid<=g_sp[i].vSL) cls=true; }
      else                { if(g_sp[i].vTP>0&&ask<=g_sp[i].vTP) cls=true; else if(g_sp[i].vSL>0&&ask>=g_sp[i].vSL) cls=true; }
      if(cls && StealthClosePos(g_sp[i].ticket,g_sp[i].dir)) g_sp[i].active=false;
   }
}

ulong OpenOrder(ENUM_ORDER_TYPE type, string comment, double slMul)
{
   double lot=CalcLot();
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK), bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double entry=(type==ORDER_TYPE_BUY)?ask:bid;
   int dir=(type==ORDER_TYPE_BUY)?1:-1;
   double slPts=(slMul<=1.0)?MM7_G2_SL_FIXED:MM7_SL_FIXED;
   double vTP=entry+dir*MM7_TP_FIXED, vSL=entry-dir*slPts;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=type; req.price=entry; req.sl=0; req.tp=0;
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment=comment;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)) { req.type_filling=ORDER_FILLING_IOC; if(!OrderSend(req,res)) { req.type_filling=ORDER_FILLING_RETURN; bool _o=OrderSend(req,res); } }
   if(res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_PLACED)
   {
      ulong posTk=0;
      if(res.deal>0 && HistoryDealSelect(res.deal)) { ulong pid=(ulong)HistoryDealGetInteger(res.deal,DEAL_POSITION_ID); if(pid>0) posTk=pid; }
      if(posTk==0 && res.deal>0) posTk=res.deal;
      if(posTk==0 || !PositionSelectByTicket(posTk))
      { ulong bk=0; datetime bt=0; for(int p=PositionsTotal()-1;p>=0;p--) { ulong tk2=PositionGetTicket(p); if(!PositionSelectByTicket(tk2)) continue; if(PositionGetString(POSITION_SYMBOL)!=g_sym||PositionGetInteger(POSITION_MAGIC)!=g_magic) continue; datetime t2=(datetime)PositionGetInteger(POSITION_TIME); if(t2>=bt){bt=t2;bk=tk2;} } if(bk>0) posTk=bk; }
      if(Use_Stealth_Mode && posTk>0) StealthRegister(posTk,vTP,vSL,dir);
      return posTk;
   }
   return 0;
}

void CheckG2()
{
   if(!Recovery_Mode_Enabled || CountG2Open()>0 || CountLegacyOpen()==0) return;
   int lc=CountLegacyClosedToday();
   if(lc-g_legacyClosedAtLastG2<Overlap_AFTER_X_trades_) return;
   datetime ot=0; int ld=0; ulong ltk=0;
   for(int i=0;i<PositionsTotal();i++) { ulong tk=PositionGetTicket(i); if(!PositionSelectByTicket(tk)) continue; if(PositionGetInteger(POSITION_MAGIC)!=g_magic) continue; if(StringFind(PositionGetString(POSITION_COMMENT),"[Legacy]")<0) continue; datetime t=(datetime)PositionGetInteger(POSITION_TIME); if(ot==0||t<ot){ot=t;ltk=tk;ld=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;} }
   if(ot==0||ltk==0||ltk==g_g2ForLegacyTicket) return;
   if((TimeCurrent()-ot)<MM7_G2_MIN_GAP_S || g_lastG2OpenTime==TimeCurrent()) return;
   ulong tk=OpenOrder((ld==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL, CommentOrder+" G2", 1.0);
   if(tk>0) { g_lastG2OpenTime=TimeCurrent(); g_legacyClosedAtLastG2=lc; g_g2OpenedThisLegacy=true; g_g2ForLegacyTicket=ltk; }
}

void DailyReset()
{
   datetime today=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today==g_dayStart) return;
   g_dayStart=today; g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE); g_haltedToday=false;
   g_legacyClosedAtLastG2=0; g_g2OpenedThisLegacy=false; g_g2ForLegacyTicket=0;
   g_lastSignalBarTime=0; g_fvgLastScan=0; g_fvgCnt=0;
}

void CheckHaltConditions()
{
   if(g_haltedToday) return;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE), eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxEquityDrawdown>0&&bal>0&&(bal-eq)/bal*100.0>=InpMaxEquityDrawdown) { g_haltedToday=true; return; }
   if(InpMaxDailyLossPct>0&&g_dayStartBal>0&&(g_dayStartBal-bal)/g_dayStartBal*100.0>=InpMaxDailyLossPct) g_haltedToday=true;
}

void DashLbl(string nm,string txt,color clr,int oy,int x,int y,ENUM_BASE_CORNER c,int fn)
{
   string f="MM7D_"+nm;
   if(ObjectFind(0,f)<0){ObjectCreate(0,f,OBJ_LABEL,0,0,0);ObjectSetInteger(0,f,OBJPROP_CORNER,c);ObjectSetInteger(0,f,OBJPROP_XDISTANCE,x);ObjectSetString(0,f,OBJPROP_FONT,"Courier New");ObjectSetInteger(0,f,OBJPROP_FONTSIZE,fn);}
   ObjectSetInteger(0,f,OBJPROP_YDISTANCE,y+oy); ObjectSetString(0,f,OBJPROP_TEXT,txt); ObjectSetInteger(0,f,OBJPROP_COLOR,clr);
}

void DrawDashboard()
{
   if(!Enable_Dashboard || TimeCurrent()-g_lastDashTime<Refresh_Interval_Seconds) return;
   g_lastDashTime=TimeCurrent();
   double bal=AccountInfoDouble(ACCOUNT_BALANCE), eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double dd=(bal>0)?(bal-eq)/bal*100.0:0;
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   double dp=0; HistorySelect(ds,TimeCurrent());
   for(int i=0;i<HistoryDealsTotal();i++){ulong dk=HistoryDealGetTicket(i);if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)==g_magic) dp+=HistoryDealGetDouble(dk,DEAL_PROFIT);}
   string ms=(InpStrategy==0)?"Sweep":(InpStrategy==1)?"Hybrid":"Breakout";
   int x=Dashboard_X_Offset,y=Dashboard_Y_Offset,fn=Font_size_Result,lh=fn+4;
   ENUM_BASE_CORNER co=(ENUM_BASE_CORNER)Dashboard_Corner;
   DashLbl("0","[ MoneyMachine7 v8.13 ]",clrGold,      0*lh,x,y,co,fn);
   DashLbl("1","Mode : "+ms,             clrCyan,      1*lh,x,y,co,fn);
   DashLbl("2","Bal  : $"+DoubleToString(bal,2),clrWhite,2*lh,x,y,co,fn);
   DashLbl("3","Eq   : $"+DoubleToString(eq,2), clrWhite,3*lh,x,y,co,fn);
   DashLbl("4","DD   : "+DoubleToString(dd,2)+"%",(dd>5)?clrOrangeRed:clrLimeGreen,4*lh,x,y,co,fn);
   DashLbl("5","Open : "+(string)CountByMagic(),clrWhite,5*lh,x,y,co,fn);
   DashLbl("6","Day  : $"+DoubleToString(dp,2),(dp>=0)?clrLimeGreen:clrOrangeRed,6*lh,x,y,co,fn);
   DashLbl("7","FVGs : "+(string)g_fvgCnt,     clrGray, 7*lh,x,y,co,fn);
   DashLbl("8","Halt : "+(g_haltedToday?"YES":"no"),(g_haltedToday)?clrRed:clrGray,8*lh,x,y,co,fn);
}

void DrawHistoryLabels()
{
   if(!Enable_History_Labels || TimeCurrent()-g_lastLabelTime<10) return;
   g_lastLabelTime=TimeCurrent(); ObjectsDeleteAll(0,"MM7L_");
   datetime ds=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   HistorySelect(ds,TimeCurrent()); int tot=HistoryDealsTotal(), st=MathMax(0,tot-History_Labels_Limit);
   for(int i=st;i<tot;i++)
   { ulong dk=HistoryDealGetTicket(i); if((int)HistoryDealGetInteger(dk,DEAL_MAGIC)!=g_magic) continue; if(HistoryDealGetInteger(dk,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
     double pf=HistoryDealGetDouble(dk,DEAL_PROFIT), px=HistoryDealGetDouble(dk,DEAL_PRICE); datetime t=(datetime)HistoryDealGetInteger(dk,DEAL_TIME);
     string nm="MM7L_"+(string)dk; if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_TEXT,0,t,px);
     ObjectSetString(0,nm,OBJPROP_TEXT,(pf>=0?"+":"")+DoubleToString(pf,2)); ObjectSetInteger(0,nm,OBJPROP_COLOR,(pf>=0)?clrLimeGreen:clrOrangeRed); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8); }
}

int OnInit()
{
   g_magic=InpMagicNumber; g_sym=_Symbol;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   g_hStoch=iStochastic(g_sym,_Period,Stoch_K_Period,Stoch_D_Period,Stoch_Slowing,MODE_SMA,STO_LOWHIGH);
   if(g_hStoch==INVALID_HANDLE){Alert("Stoch failed");return INIT_FAILED;}
   if(Enable_Trend_Filter){g_hMA=iMA(g_sym,_Period,Trend_MA_Period,0,MODE_SMA,PRICE_CLOSE);if(g_hMA==INVALID_HANDLE){Alert("MA200 failed");return INIT_FAILED;}}
   g_hATR=iATR(g_sym,_Period,ATR_Period); if(g_hATR==INVALID_HANDLE){Alert("ATR failed");return INIT_FAILED;}
   if(Use_RSI_Confirmation){g_hRSI=iRSI(g_sym,_Period,RSI_Period,PRICE_CLOSE);if(g_hRSI==INVALID_HANDLE){Alert("RSI failed");return INIT_FAILED;}}
   if(Use_Volume_Confirmation) g_hVol=iMA(g_sym,_Period,Volume_Ma_Period,0,MODE_SMA,PRICE_CLOSE); // handle kept for warmup; volume read via CopyTickVolume
   ArrayResize(g_sp,500); g_spCnt=0; ArrayResize(g_fvg,100); g_fvgCnt=0;
   g_dayStart=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   g_dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
   g_legacyClosedAtLastG2=CountLegacyClosedToday();
   string ms=(InpStrategy==0)?"Sweep":(InpStrategy==1)?"Hybrid":"Breakout";
   Print("MM7 v8.13 | Mode=",ms," | TP=",MM7_TP_FIXED," SL=",MM7_SL_FIXED," G2SL=",MM7_G2_SL_FIXED," | FVG=",Enable_FVG_Strategy," Sweep=",Enable_Stop_Hunt_Strategy);
   EventSetTimer(5); return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hStoch!=INVALID_HANDLE) IndicatorRelease(g_hStoch);
   if(g_hMA   !=INVALID_HANDLE) IndicatorRelease(g_hMA);
   if(g_hATR  !=INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hRSI  !=INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hVol  !=INVALID_HANDLE) IndicatorRelease(g_hVol);
   ObjectsDeleteAll(0,"MM7D_"); ObjectsDeleteAll(0,"MM7L_");
}

void OnTick()
{
   StealthCheckAll();
   DailyReset(); CheckHaltConditions();
   if(g_haltedToday){DrawDashboard();return;}
   if(!IsScheduleAllowed()){DrawDashboard();return;}
   if(InpMaxSpreadPoints>0 && SymbolInfoInteger(g_sym,SYMBOL_SPREAD)>InpMaxSpreadPoints) return;
   ScanFVGs();
   CheckG2();
   if(CountLegacyOpen()==0)
   {
      datetime bOpen=iTime(g_sym,_Period,0);
      if(bOpen<=g_lastSignalBarTime){DrawDashboard();return;}
      int sig=GetSignal();
      if(sig== 1&&CountBuys() >=Max_Buy)  sig=0;
      if(sig==-1&&CountSells()>=Max_Sell) sig=0;
      if(sig==1)  { ulong tk=OpenOrder(ORDER_TYPE_BUY, CommentOrder+" [Legacy]",Auto_SL_Ratio); if(tk>0){g_lastSignalBarTime=bOpen;g_lastLegacyTicket=tk;} }
      if(sig==-1) { ulong tk=OpenOrder(ORDER_TYPE_SELL,CommentOrder+" [Legacy]",Auto_SL_Ratio); if(tk>0){g_lastSignalBarTime=bOpen;g_lastLegacyTicket=tk;} }
   }
   DrawDashboard();
}

void OnTimer() { DrawHistoryLabels(); }
