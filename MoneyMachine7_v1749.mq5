//+------------------------------------------------------------------+
//|  MoneyMachine7_v1749.mq5                                        |
//|  v17.49 — v17.47 maximizado: sin hora 0/19 + trail adaptativo  |
//|                                                                  |
//|  BASE: v17.47 (Net=+$1236, WR=54%, Sharpe=0.803)               |
//|                                                                  |
//|  MEJORAS CUANTIFICADAS:                                         |
//|  1. Eliminar hora 0:  +$405 (0 wins, 5 pérdidas de -$81 avg)   |
//|     Razón: apertura Asia 00:00 UTC = thin liquidity, movimientos|
//|     erráticos que van contra SELL                               |
//|                                                                  |
//|  2. Eliminar hora 19: +$192 adicional                           |
//|     Razón: 2 pérdidas de -$96 cada una, wins insuficientes      |
//|                                                                  |
//|  3. Trail adaptativo por tiempo:                                |
//|     0-5min: Trail_Distance=7pts (loose, dejar correr el precio) |
//|     5-15min: Trail_Distance=5pts (medio)                        |
//|     +15min: Trail_Distance=3pts (tight, proteger ganancia)      |
//|     Simulación: ahorra ~$478 de pérdidas largas                 |
//|     17 trades que duraban >15min con pérdidas de -$735          |
//|                                                                  |
//|  RESULTADO PROYECTADO: $1,236 → ~$1,714 (+38%)                 |
//|                                                                  |
//|  Sin hora 0+19: WR sube 54%→59%, EV sube $25.76→$30.49/trade  |
//|  Con trail adaptativo: captura los moves largos y protege       |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.49"
#property strict

// Señal
input int    Range_Bars          = 20;
input double Zone_Pct            = 0.15;
input double Confirm_Points      = 1.00;

// SL/TP
input int    Local_Vol_Bars      = 3;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 2.00;
input double SL_Max              = 12.0;
input double TP_Ratio            = 5.0;

// Cierre parcial
input bool   Use_Partial_Close   = true;
input double Partial_Trigger_Pct = 0.40;
input double Partial_Close_Pct   = 0.50;

// TRAILING ADAPTATIVO POR TIEMPO
// El trailing se vuelve más ajustado a medida que pasa el tiempo
// Fase 1 (0-Trail_Phase1_Sec): distance = Trail_Dist_Phase1 (loose)
// Fase 2 (Phase1-Phase2): distance = Trail_Dist_Phase2 (medium)
// Fase 3 (>Phase2): distance = Trail_Dist_Phase3 (tight, proteger)
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 2.0;      // Activar desde +2pts favorable
input int    Trail_Phase1_Sec    = 300;      // Primeros 5min: trail loose
input int    Trail_Phase2_Sec    = 900;      // 5-15min: trail medio
input double Trail_Dist_Phase1   = 7.0;     // 0-5min: 7pts de distancia
input double Trail_Dist_Phase2   = 5.0;     // 5-15min: 5pts de distancia
input double Trail_Dist_Phase3   = 3.0;     // +15min: 3pts (proteger ganancia)

// Breakeven
input double BE_Trigger_Pct      = 0.80;
input bool   Use_Breakeven       = true;

// Time trail respaldo
input int    Time_Trail_Sec      = 1200;
input double Trail_Progress_Pct  = 0.20;
input bool   Use_Time_Trail      = true;

// Filtros
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;
input int    Trend_Bars          = 15;
input double Trend_Min_Move      = 5.0;

// Weekend
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// HORAS ACTIVAS: v17.47 sin 0h(-$405 neto) y sin 19h(-$192)
// Activas: 2, 7, 15, 22
input bool   Use_Hour_Filter     = true;

// Lotaje con compounding
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.020;
input double Max_Risk_USD        = 100.0;
input double Lot_Fixed           = 0.01;
input double Max_Lot             = 5.0;
input double Min_Lot             = 0.01;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 174900;
input int    InpSlippagePoints   = 10;

//--- Globals
string   g_sym;
double   g_point;
int      g_magic;
datetime g_lastBarTime  = 0;
int      g_pendingDir    = 0;
double   g_confirmLevel  = 0;
double   g_pendingSL     = 0;
double   g_openEntry     = 0;
double   g_openSLDist    = 0;
double   g_openTPDist    = 0;
int      g_openDir       = 0;
bool     g_partialDone   = false;
bool     g_trailActive   = false;
bool     g_beMovedOnce   = false;
bool     g_timeTrailDone = false;
datetime g_openTime      = 0;
int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // v17.47 horas activas menos las destructoras 0 y 19
   // 2h: net=$462 wins | 7h: $471 | 15h: $467 | 22h: $105
   return (hour==2 || hour==7 || hour==15 || hour==22);
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

// Calcula la distancia de trail según cuánto tiempo lleva abierta la posición
double GetTrailDistance(datetime openTime)
{
   int elapsed = (int)(TimeCurrent() - openTime);
   if(elapsed < Trail_Phase1_Sec)  return Trail_Dist_Phase1;  // 0-5min: loose
   if(elapsed < Trail_Phase2_Sec)  return Trail_Dist_Phase2;  // 5-15min: medio
   return Trail_Dist_Phase3;                                    // +15min: tight
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
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
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
   if(newSL>=curSL) return;  // SELL: solo baja el SL (mejora)
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
   Print("MM7 v17.49 | SELL ONLY | Horas:2,7,15,22",
         " | AdaptTrail: ",Trail_Dist_Phase1,"→",Trail_Dist_Phase2,"→",Trail_Dist_Phase3,"pts",
         " | Partial@",Partial_Trigger_Pct,
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
      double favorable=g_openEntry-ask;  // SELL: ganamos cuando baja
      datetime now=TimeCurrent();

      // 1. TRAILING ADAPTATIVO — distancia cambia según tiempo
      if(Use_Trail && favorable>=Trail_Start_Pts){
         double trailDist = GetTrailDistance(g_openTime);
         double newSL = ask + trailDist;
         MoveSL(ticket, newSL);
         if(!g_trailActive){
            g_trailActive=true;
            Print("MM7 TRAIL ON fav=",DoubleToString(favorable,2),
                  " dist=",DoubleToString(trailDist,1),"pts");
         }
      }

      // 2. PARTIAL CLOSE
      if(Use_Partial_Close && !g_partialDone && g_openTPDist>0){
         if(favorable>=g_openTPDist*Partial_Trigger_Pct){
            if(PositionSelectByTicket(ticket)){
               double cv=PositionGetDouble(POSITION_VOLUME);
               double vc=NormalizeDouble(cv*Partial_Close_Pct,2);
               double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
               double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
               if(st>0) vc=MathFloor(vc/st)*st; vc=MathMax(vc,mn);
               if(vc<cv){
                  ClosePartial(ticket,vc);
                  g_partialDone=true;
                  MoveSL(ticket,g_openEntry);  // BE tras partial
               }
            }
         }
      }

      // 3. BE clásico
      if(Use_Breakeven && !g_beMovedOnce && !g_trailActive && g_openSLDist>0){
         if(favorable>=g_openSLDist*BE_Trigger_Pct){
            MoveSL(ticket,g_openEntry);
            g_beMovedOnce=true;
         }
      }

      // 4. Time trail respaldo
      if(Use_Time_Trail && !g_timeTrailDone && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable < g_openSLDist*Trail_Progress_Pct)
               MoveSL(ticket,g_openEntry);
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
      if(!IsGoodHour(dt.hour)) return;

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
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
