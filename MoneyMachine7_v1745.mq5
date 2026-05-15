//+------------------------------------------------------------------+
//|  MoneyMachine7_v1745.mq5                                        |
//|  v17.45 — Trailing progresivo inteligente                       |
//|                                                                  |
//|  DIAGNOSTICO v17.44:                                            |
//|  Net=+$1567 | WR=34% | 50 trades reales                        |
//|  30/33 perdidas (91%) son >15min = precio se movio y revirtio  |
//|  Perdidas largas: -$2,043 de un total de -$2,268               |
//|                                                                  |
//|  CAUSA: el trailing actual es binario:                          |
//|  - BE al 60% del SL (muy temprano, solo 1.2pts)                |
//|  - Time-trail a los 15min (demasiado tarde en muchos casos)    |
//|  El precio va 5-8pts favorable, no alcanza el partial (40% TP) |
//|  y luego revierte completamente hasta el SL original           |
//|                                                                  |
//|  FIX v17.45 — TRAILING PROGRESIVO:                             |
//|  El SL sube/baja siguiendo al precio con un "colchon" fijo     |
//|  Una vez que el precio supera Trail_Start_Pts en nuestro favor |
//|  el SL se mueve a: precio_actual - Trail_Distance_Pts          |
//|  (para BUY) o precio_actual + Trail_Distance_Pts (para SELL)   |
//|                                                                  |
//|  Esto captura: si precio va 10pts favorable y Trail_Dist=5,    |
//|  el SL queda en +5pts → ganancia minima garantizada            |
//|  Si luego va a 20pts → SL en +15pts etc.                       |
//|  El partial close al 40% sigue funcionando ademas              |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.45"
#property strict

// Señal
input int    Range_Bars          = 20;
input double Zone_Pct            = 0.15;
input double Confirm_Points      = 1.00;

// SL/TP local
input int    Local_Vol_Bars      = 3;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 2.00;
input double SL_Max              = 12.0;
input double TP_Ratio            = 5.0;

// Cierre parcial — igual que v17.44
input bool   Use_Partial_Close   = true;
input double Partial_Trigger_Pct = 0.40;
input double Partial_Close_Pct   = 0.50;

// TRAILING PROGRESIVO — nuevo mecanismo clave
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 3.0;   // Activar trailing cuando precio supera X pts favorable
input double Trail_Distance_Pts  = 2.0;   // Mantener SL a X pts del precio actual

// Breakeven clasico (respaldo si trailing no se activó)
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Breakeven       = true;

// Time trail (respaldo final)
input int    Time_Trail_Sec      = 900;
input double Trail_Progress_Pct  = 0.25;
input bool   Use_Time_Trail      = true;

// Filtro velocidad
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;

// Filtro tendencia
input int    Trend_Bars          = 15;
input double Trend_Min_Move      = 6.0;

// Weekend
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Horas: 0,2,7,9(sell),19,22 — igual v17.44
input bool   Use_Hour_Filter     = true;

// Lotaje — igual v17.44
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.015;
input double Max_Risk_USD        = 80.0;
input double Lot_Fixed           = 0.01;
input double Max_Lot             = 5.0;
input double Min_Lot             = 0.01;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 174500;
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
bool     g_trailActive   = false;    // trailing progresivo activado
bool     g_beMovedOnce   = false;    // para BE clasico
bool     g_timeTrailDone = false;
datetime g_openTime      = 0;

int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
int GetHourMode(int hour)
{
   if(!Use_Hour_Filter) return 1;
   switch(hour) {
      case 0: case 2: case 7: case 19: case 22: return 1;
      case 9:  return -1;
      default: return 0;
   }
}

bool TrendBlocks(int signalDir)
{
   double cn=iClose(g_sym,_Period,1), co=iClose(g_sym,_Period,Trend_Bars+1);
   if(cn==0||co==0) return false;
   double mv=cn-co;
   if(signalDir==1 && mv<=-Trend_Min_Move) return true;
   if(signalDir==-1 && mv>=Trend_Min_Move) return true;
   return false;
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
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ENUM_ORDER_TYPE ct=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   double price=(ct==ORDER_TYPE_SELL)?SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   if(st>0) vc=MathFloor(vc/st)*st;
   vc=MathMax(vc,mn);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vc; req.type=ct;
   req.price=price; req.position=ticket; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7-partial";
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED) Print("MM7 PARTIAL vol=",vc);
}

void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double vol=PositionGetDouble(POSITION_VOLUME);
   ENUM_ORDER_TYPE ct=(pt==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   double price=(ct==ORDER_TYPE_SELL)?SymbolInfoDouble(g_sym,SYMBOL_BID):SymbolInfoDouble(g_sym,SYMBOL_ASK);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol; req.type=ct;
   req.price=price; req.position=ticket; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7-"+reason;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED) Print("MM7 CLOSE ",reason);
}

void OpenOrder(ENUM_ORDER_TYPE type, double sl_dist)
{
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double entry=(type==ORDER_TYPE_BUY)?ask:bid;
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   int dir=(type==ORDER_TYPE_BUY)?1:-1;
   double tp_dist=sl_dist*TP_Ratio;
   double tp=NormalizeDouble(entry+dir*tp_dist,digs);
   double sl=NormalizeDouble(entry-dir*sl_dist,digs);
   double lot=CalcLot(sl_dist);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot; req.type=type;
   req.price=entry; req.sl=sl; req.tp=tp; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7";
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0; g_openEntry=entry; g_openSLDist=sl_dist; g_openTPDist=tp_dist;
      g_openDir=dir; g_partialDone=false; g_trailActive=false;
      g_beMovedOnce=false; g_timeTrailDone=false; g_openTime=TimeCurrent();
      Print("MM7 OPEN ",(type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=",entry," SL=",sl," TP=",tp," lot=",lot);
   } else { Print("MM7 FAIL retcode=",res.retcode); }
}

void MoveSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   newSL=NormalizeDouble(newSL,digs);
   if(g_openDir==1 && newSL<=curSL) return;   // solo mover en direccion favorable
   if(g_openDir==-1 && newSL>=curSL) return;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_SLTP; req.symbol=g_sym; req.position=ticket; req.sl=newSL; req.tp=curTP;
   if(OrderSend(req,res)) {} // silencioso para no spammear el log con cada tick
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
   Print("MM7 v17.45 | ",g_sym,
         " | TP=",TP_Ratio,"x Partial@",Partial_Trigger_Pct,
         " | Trail: start=",Trail_Start_Pts,"pts dist=",Trail_Distance_Pts,"pts",
         " | Risk=",Risk_Pct_Per_Trade*100,"% Cap=$",Max_Risk_USD,
         " | Horas:0,2,7,9(SELL),19,22");
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
      double favorable=(g_openDir==1)?(bid-g_openEntry):(g_openEntry-ask);
      datetime now=TimeCurrent();

      // === TRAILING PROGRESIVO ===
      // Una vez que precio supera Trail_Start_Pts en nuestro favor:
      // SL se mueve a precio_actual - Trail_Distance_Pts (BUY)
      // o a precio_actual + Trail_Distance_Pts (SELL)
      // El SL solo se SUBE (nunca baja), protegiendo ganancias acumuladas
      if(Use_Trail && favorable >= Trail_Start_Pts){
         double newSL;
         if(g_openDir==1)
            newSL = bid - Trail_Distance_Pts;     // BUY: SL sigue al bid
         else
            newSL = ask + Trail_Distance_Pts;     // SELL: SL sigue al ask
         MoveSL(ticket, newSL);
         if(!g_trailActive){
            g_trailActive=true;
            g_timeTrailDone=true; // el trail progresivo reemplaza al time-trail
            Print("MM7 TRAIL ACTIVO @ fav=",DoubleToString(favorable,2)," SL→",DoubleToString(newSL,2));
         }
      }

      // === CIERRE PARCIAL al 40% del TP ===
      if(Use_Partial_Close && !g_partialDone && g_openTPDist>0){
         if(favorable >= g_openTPDist * Partial_Trigger_Pct){
            if(PositionSelectByTicket(ticket)){
               double cv=PositionGetDouble(POSITION_VOLUME);
               double vc=NormalizeDouble(cv*Partial_Close_Pct,2);
               double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
               double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
               if(st>0) vc=MathFloor(vc/st)*st;
               vc=MathMax(vc,mn);
               if(vc<cv){
                  ClosePartial(ticket,vc);
                  g_partialDone=true;
                  // Después del partial, mover SL a BE como garantía extra
                  MoveSL(ticket, g_openEntry);
                  Print("MM7 PARTIAL done, SL→BE");
               }
            }
         }
      }

      // === BE CLASICO (respaldo si trailing no llegó aún) ===
      if(Use_Breakeven && !g_beMovedOnce && !g_trailActive && g_openSLDist>0){
         if(favorable >= g_openSLDist * BE_Trigger_Pct){
            MoveSL(ticket, g_openEntry);
            g_beMovedOnce=true; g_timeTrailDone=true;
         }
      }

      // === TIME TRAIL (respaldo final) ===
      if(Use_Time_Trail && !g_timeTrailDone && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable < g_openSLDist * Trail_Progress_Pct){
               MoveSL(ticket, g_openEntry);
               Print("MM7 TIME-TRAIL→BE");
            }
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
      int hmode=GetHourMode(dt.hour);
      if(hmode==0) return;

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
      double upperZone=rH-range*Zone_Pct, lowerZone=rL+range*Zone_Pct;

      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,SL_Max),SL_Min);

      if(closeNow>=upperZone && !TrendBlocks(-1)){
         g_pendingDir=-1; g_confirmLevel=closeNow-Confirm_Points; g_pendingSL=slDist;
      } else if(closeNow<=lowerZone && !TrendBlocks(1) && hmode==1){
         g_pendingDir=1; g_confirmLevel=closeNow+Confirm_Points; g_pendingSL=slDist;
      }
      return;
   }

   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int hmode=GetHourMode(dt.hour);
   if(hmode==0){g_pendingDir=0;return;}
   if(g_pendingDir==1&&hmode==-1){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==1&&bid>=g_confirmLevel)
      OpenOrder(ORDER_TYPE_BUY,g_pendingSL);
   else if(g_pendingDir==-1&&ask<=g_confirmLevel)
      OpenOrder(ORDER_TYPE_SELL,g_pendingSL);
}
//+------------------------------------------------------------------+
