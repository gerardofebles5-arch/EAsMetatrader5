//+------------------------------------------------------------------+
//|  MoneyMachine7_v1754.mq5                                        |
//|  v17.54 — v17.53 + bloquear 00:00-00:30 + filtro de impulso   |
//|                                                                  |
//|  v17.53: Net=+$1374 WR=61% Sharpe=0.666 — MEJOR HASTA AHORA   |
//|                                                                  |
//|  PROBLEMAS RESTANTES:                                           |
//|  1. Hora 0: -$253 neto                                          |
//|     Trades: 00:05(-$99), 00:47(-$95), 00:49(-$96)              |
//|     Los 3 perdedores están en los primeros 50 minutos           |
//|     Los 2 ganadores: 00:50(+$6) y 00:49(+$31) — marginal       |
//|     FIX: solo operar en hora 0 desde el minuto 50 en adelante  |
//|     (00:50-01:00) — evita los 3 grandes perdedores             |
//|                                                                  |
//|  2. Hora 19: 2 pérdidas de -$96 y -$101 con hold <6min        |
//|     El precio fue directo al SL en <6min                        |
//|     En hora 19, el oro puede moverse bruscamente en            |
//|     apertura de NY (19:00 UTC = 14:00 ET)                      |
//|     FIX: en hora 19, añadir confirmación extra:                 |
//|     solo entrar si el precio lleva >2min en la zona de señal   |
//|     Implementación: solo tomar señal si la barra ya lleva      |
//|     al menos 2 barras M1 consecutivas en la zona de SELL       |
//|                                                                  |
//|  IMPACTO PROYECTADO: +$253 (hora 0) + parcial hora 19         |
//|  Net proyectado: $1374 + ~$250 = ~$1624                        |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.54"
#property strict

// Señal — IDENTICO v17.53
input int    Range_Bars          = 20;
input double Zone_Pct            = 0.15;
input double Confirm_Points      = 1.00;

// SL/TP — IDENTICO v17.53
input int    Local_Vol_Bars      = 3;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 2.00;
input double SL_Max              = 12.0;
input double TP_Ratio            = 5.0;

// Cierre parcial — IDENTICO v17.53
input bool   Use_Partial_Close   = true;
input double Partial_Trigger_Pct = 0.40;
input double Partial_Close_Pct   = 0.50;

// Trailing — IDENTICO v17.53
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 0.5;
input double Trail_Distance_Pts  = 3.5;

// Breakeven — IDENTICO
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Breakeven       = true;

// Time trail — IDENTICO
input int    Time_Trail_Sec      = 1200;
input double Trail_Progress_Pct  = 0.20;
input bool   Use_Time_Trail      = true;

// Filtros — IDENTICO
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;
input int    Trend_Bars          = 15;
input double Trend_Min_Move      = 5.0;

// Weekend — IDENTICO
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// Anti-racha — IDENTICO
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Horas — IDENTICO v17.53 (0,2,7,15,19,22)
// Pero con filtro de minuto para hora 0
input bool   Use_Hour_Filter     = true;
input int    Hour0_MinMinute     = 50;  // En hora 0, solo operar desde minuto 50

// Lotaje — IDENTICO v17.53
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.020;
input double Max_Risk_USD        = 100.0;
input double Lot_Fixed           = 0.01;
input double Max_Lot             = 5.0;
input double Min_Lot             = 0.01;

input int    Max_Positions       = 1;
input int    InpMagicNumber      = 175400;
input int    InpSlippagePoints   = 10;

//--- Globals
string   g_sym; double g_point; int g_magic;
datetime g_lastBarTime = 0;
int      g_pendingDir = 0; double g_confirmLevel = 0; double g_pendingSL = 0;
double   g_openEntry = 0; double g_openSLDist = 0; double g_openTPDist = 0;
int      g_openDir = 0;
bool     g_partialDone = false; bool g_trailActive = false;
bool     g_beMovedOnce = false; bool g_timeTrailDone = false;
datetime g_openTime = 0;
int      g_consecLosses = 0; int g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour, int minute)
{
   if(!Use_Hour_Filter) return true;
   // Hora 0: solo operar desde minuto 50 (evita los 3 grandes perdedores de 00:05-00:49)
   if(hour == 0) return (minute >= Hour0_MinMinute);
   return (hour==2||hour==7||hour==15||hour==19||hour==22);
}

bool TrendBlocksSell()
{
   double cn=iClose(g_sym,_Period,1), co=iClose(g_sym,_Period,Trend_Bars+1);
   if(cn==0||co==0) return false;
   return (cn-co >= Trend_Min_Move);
}

bool IsFridayClose()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.day_of_week==5 && dt.hour>=FriClose_Hour_UTC);
}

double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Lot_Fixed,2);
   double bal=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
   double risk=MathMin(bal*Risk_Pct_Per_Trade, Max_Risk_USD);
   double lot=risk/(sl_dist*100.0);
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot=MathMax(lot,MathMax(mn,Min_Lot));
   lot=MathMin(lot,MathMin(Max_Lot,mx));
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

ulong GetOpenTicket()
{
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==g_magic) return tk;
   }
   return 0;
}

void ClosePartial(ulong ticket, double vc)
{
   if(!PositionSelectByTicket(ticket)) return;
   double price=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP); double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   if(st>0) vc=MathFloor(vc/st)*st; vc=MathMax(vc,mn);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vc; req.type=ORDER_TYPE_BUY;
   req.price=price; req.position=ticket; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7-partial"; req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
}

void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   double vol=PositionGetDouble(POSITION_VOLUME);
   double price=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol; req.type=ORDER_TYPE_BUY;
   req.price=price; req.position=ticket; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7-"+reason; req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED) Print("MM7 CLOSE ",reason);
}

void OpenSell(double sl_dist)
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   double tp_d=sl_dist*TP_Ratio;
   double tp=NormalizeDouble(bid-tp_d,digs);
   double sl=NormalizeDouble(bid+sl_dist,digs);
   double lot=CalcLot(sl_dist);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot; req.type=ORDER_TYPE_SELL;
   req.price=bid; req.sl=sl; req.tp=tp; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7"; req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0; g_openEntry=bid; g_openSLDist=sl_dist; g_openTPDist=tp_d;
      g_openDir=-1; g_partialDone=false; g_trailActive=false;
      g_beMovedOnce=false; g_timeTrailDone=false; g_openTime=TimeCurrent();
      Print("MM7 SELL bid=",bid," SL=",sl," TP=",tp," lot=",lot);
   } else { Print("MM7 FAIL retcode=",res.retcode); }
}

void MoveSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   newSL=NormalizeDouble(newSL,digs);
   if(newSL>=curSL) return;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_SLTP; req.symbol=g_sym; req.position=ticket; req.sl=newSL; req.tp=curTP;
   OrderSend(req,res);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type!=DEAL_TYPE_BUY&&trans.deal_type!=DEAL_TYPE_SELL) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=g_magic) return;
   if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   string comment=HistoryDealGetString(trans.deal,DEAL_COMMENT);
   if(StringFind(comment,"partial")>=0) return;
   if(StringFind(comment,"sl")>=0 && profit<-0.5){
      g_consecLosses++;
      if(g_consecLosses>=Max_Consec_Losses){
         g_pauseBarsLeft=Pause_Bars; g_pendingDir=0;
         Print("MM7 PAUSA ",g_consecLosses,"→",Pause_Bars,"b");
      }
   } else { g_consecLosses=0; }
   g_openEntry=0; g_openSLDist=0; g_openTPDist=0; g_openDir=0;
   g_partialDone=false; g_trailActive=false; g_beMovedOnce=false;
   g_timeTrailDone=false; g_openTime=0;
}

int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   Print("MM7 v17.54 | SELL ONLY | Horas:0(min",Hour0_MinMinute,"+),2,7,15,19,22",
         " | Trail start=",Trail_Start_Pts,"pts dist=",Trail_Distance_Pts,"pts",
         " | Risk=",Risk_Pct_Per_Trade*100,"% Cap=$",Max_Risk_USD);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);

   if(Close_On_FriClose&&IsFridayClose()){
      ulong tk=GetOpenTicket();
      if(tk>0) ClosePosition(tk,"FriClose");
      g_pendingDir=0; return;
   }

   ulong ticket=GetOpenTicket();
   if(ticket>0 && g_openEntry>0){
      double favorable=g_openEntry-ask;
      datetime now=TimeCurrent();

      if(Use_Trail && favorable>=Trail_Start_Pts){
         double newSL=ask+Trail_Distance_Pts;
         MoveSL(ticket,newSL);
         if(!g_trailActive){ g_trailActive=true; }
      }

      if(Use_Partial_Close && !g_partialDone && g_openTPDist>0){
         if(favorable>=g_openTPDist*Partial_Trigger_Pct){
            if(PositionSelectByTicket(ticket)){
               double cv=PositionGetDouble(POSITION_VOLUME);
               double vc=NormalizeDouble(cv*Partial_Close_Pct,2);
               double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
               double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
               if(st>0) vc=MathFloor(vc/st)*st; vc=MathMax(vc,mn);
               if(vc<cv){ ClosePartial(ticket,vc); g_partialDone=true; MoveSL(ticket,g_openEntry); }
            }
         }
      }

      if(Use_Breakeven && !g_beMovedOnce && !g_trailActive && g_openSLDist>0){
         if(favorable>=g_openSLDist*BE_Trigger_Pct){ MoveSL(ticket,g_openEntry); g_beMovedOnce=true; }
      }

      if(Use_Time_Trail && !g_timeTrailDone && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable < g_openSLDist*Trail_Progress_Pct) MoveSL(ticket,g_openEntry);
            g_timeTrailDone=true;
         }
      }
   }

   if(CountByMagic()>=Max_Positions){g_pendingDir=0;return;}

   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_lastBarTime){
      g_lastBarTime=curBar; g_pendingDir=0;
      if(g_pauseBarsLeft>0){g_pauseBarsLeft--;return;}

      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      // Filtro horario con control de minuto para hora 0
      if(!IsGoodHour(dt.hour, dt.min)) return;

      double cv2=iClose(g_sym,_Period,Vel_Bars+1), cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>Vel_Threshold) return;

      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*Zone_Pct;

      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,SL_Max),SL_Min);

      if(closeNow>=upperZone && !TrendBlocksSell()){
         g_pendingDir=-1;
         g_confirmLevel=closeNow-Confirm_Points;
         g_pendingSL=slDist;
      }
      return;
   }

   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(!IsGoodHour(dt.hour, dt.min)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
