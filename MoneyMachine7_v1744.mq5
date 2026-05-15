//+------------------------------------------------------------------+
//|  MoneyMachine7_v1744.mq5                                        |
//|  v17.44 — v17.42 + cap $80/trade + sin horas 13/15             |
//|                                                                  |
//|  BASE: v17.42 (mejor version, Net=+$2328, curva suave)          |
//|                                                                  |
//|  ANALISIS FINAL:                                                 |
//|  - EV real = +$8.91/trade (edge solido)                         |
//|  - 2.1 ganancias/dia × $114 avg = $239/dia bruto               |
//|  - Horas 13 y 15 = -$406 acumulado → eliminar                  |
//|  - Lot max llegó a 0.53 → losses de $270 en un trade           |
//|  - Sin esas dos correcciones: +$400 extra de net                |
//|                                                                  |
//|  CAMBIOS vs v17.42 (MINIMOS):                                   |
//|  1. Eliminar horas 13 y 15 del filtro                          |
//|  2. Añadir Max_Risk_USD=$80 como tope duro al lotaje            |
//|     lot = min(balance×Risk%, Max_Risk_USD) / (SL×100)          |
//|  3. Todo lo demás IDENTICO a v17.42                             |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.44"
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

// Cierre parcial
input bool   Use_Partial_Close   = true;
input double Partial_Trigger_Pct = 0.40;
input double Partial_Close_Pct   = 0.50;

// Trailing temporal
input int    Time_Trail_Sec      = 900;
input double Trail_Progress_Pct  = 0.30;
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

// Breakeven
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Breakeven       = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Filtro horario
// v17.42 activo: 0,2,7,9(sell),13,15,19,22
// v17.44: eliminadas 13(-$113) y 15(-$293) → horas activas: 0,2,7,9(sell),19,22
input bool   Use_Hour_Filter     = true;

// LOTAJE: igual que v17.42 PERO con cap duro en dolares
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.015;  // 1.5% del balance (igual v17.42)
input double Max_Risk_USD        = 80.0;   // NUEVO: tope duro $80 por trade
input double Lot_Fixed           = 0.01;
input double Max_Lot             = 5.0;
input double Min_Lot             = 0.01;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 174400;
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
bool     g_beMoved       = false;
bool     g_partialDone   = false;
datetime g_openTime      = 0;
bool     g_timeTrailDone = false;

int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
// 0=no operar | 1=ambas | -1=solo SELL
int GetHourMode(int hour)
{
   if(!Use_Hour_Filter) return 1;
   switch(hour) {
      case 0: case 2: case 7:
      case 19: case 22:
         return 1;   // ambas direcciones
      case 9:
         return -1;  // solo SELL (en v17.42 era positivo para SELL)
      // 13 y 15: ELIMINADAS (v17.42: -$113 y -$293)
      default:
         return 0;
   }
}

//+------------------------------------------------------------------+
bool TrendBlocks(int signalDir)
{
   double closeNow = iClose(g_sym, _Period, 1);
   double closeOld = iClose(g_sym, _Period, Trend_Bars + 1);
   if(closeNow == 0 || closeOld == 0) return false;
   double move = closeNow - closeOld;
   if(signalDir ==  1 && move <= -Trend_Min_Move) return true;
   if(signalDir == -1 && move >=  Trend_Min_Move) return true;
   return false;
}

//+------------------------------------------------------------------+
bool IsFridayClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= FriClose_Hour_UTC);
}

//+------------------------------------------------------------------+
// DOBLE CAPA: Risk_Pct × balance Y tope duro Max_Risk_USD
// Usa el MENOR → nunca arriesga más de $80 independientemente de la cuenta
double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Lot_Fixed, 2);
   double bal   = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                          AccountInfoDouble(ACCOUNT_EQUITY));
   double risk  = MathMin(bal * Risk_Pct_Per_Trade, Max_Risk_USD);
   double lot   = risk / (sl_dist * 100.0);
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st > 0) lot = MathFloor(lot / st) * st;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
void ClosePartial(ulong ticket, double vol_close)
{
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ENUM_ORDER_TYPE ct = (pt == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (ct == ORDER_TYPE_SELL) ? SymbolInfoDouble(g_sym, SYMBOL_BID)
                                          : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   if(st > 0) vol_close = MathFloor(vol_close / st) * st;
   vol_close = MathMax(vol_close, mn);
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol_close; req.type=ct;
   req.price=price; req.position=ticket; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7-partial";
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
      Print("MM7 PARTIAL vol=",vol_close);
}

void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double vol = PositionGetDouble(POSITION_VOLUME);
   ENUM_ORDER_TYPE ct = (pt == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (ct == ORDER_TYPE_SELL) ? SymbolInfoDouble(g_sym, SYMBOL_BID)
                                          : SymbolInfoDouble(g_sym, SYMBOL_ASK);
   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol; req.type=ct;
   req.price=price; req.position=ticket; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7-"+reason;
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
      Print("MM7 CLOSE ",reason);
}

//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type, double sl_dist)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   int    dir   = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp_dist = sl_dist * TP_Ratio;
   double tp    = NormalizeDouble(entry + dir * tp_dist, digs);
   double sl    = NormalizeDouble(entry - dir * sl_dist, digs);
   double lot   = CalcLot(sl_dist);

   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot; req.type=type;
   req.price=entry; req.sl=sl; req.tp=tp; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7";
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}

   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0; g_openEntry=entry; g_openSLDist=sl_dist; g_openTPDist=tp_dist;
      g_openDir=dir; g_beMoved=false; g_partialDone=false;
      g_openTime=TimeCurrent(); g_timeTrailDone=false;
      Print("MM7 OPEN ",(type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=",entry," SL=",sl," TP=",tp,
            " lot=",lot," risk≈$",DoubleToString(lot*sl_dist*100,1));
   } else { Print("MM7 FAIL retcode=",res.retcode); }
}

//+------------------------------------------------------------------+
void MoveSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   newSL=NormalizeDouble(newSL,digs);
   if(g_openDir==1 && newSL<=curSL) return;
   if(g_openDir==-1 && newSL>=curSL) return;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_SLTP; req.symbol=g_sym; req.position=ticket; req.sl=newSL; req.tp=curTP;
   if(OrderSend(req,res)) Print("MM7 SL→",newSL);
}

//+------------------------------------------------------------------+
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
   g_beMoved=false; g_partialDone=false; g_openTime=0; g_timeTrailDone=false;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   Print("MM7 v17.44 | ",g_sym,
         " | TP=",TP_Ratio,"x Partial@",Partial_Trigger_Pct,
         " | Risk=",Risk_Pct_Per_Trade*100,"% Cap=$",Max_Risk_USD,
         " | Horas:0,2,7,9(SELL),19,22",
         " | SL[",SL_Min,"-",SL_Max,"]");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
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
   if(ticket>0 && g_openEntry>0 && g_openSLDist>0 && g_openTPDist>0){
      double favorable=(g_openDir==1)?(bid-g_openEntry):(g_openEntry-ask);
      datetime now=TimeCurrent();

      if(Use_Partial_Close && !g_partialDone){
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
                  MoveSL(ticket,g_openEntry);
                  g_beMoved=true; g_timeTrailDone=true;
               }
            }
         }
      }

      if(Use_Breakeven && !g_beMoved && !g_partialDone){
         if(favorable >= g_openSLDist*BE_Trigger_Pct){
            MoveSL(ticket,g_openEntry);
            g_beMoved=true; g_timeTrailDone=true;
         }
      }

      if(Use_Time_Trail && !g_timeTrailDone && !g_beMoved && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable < g_openSLDist*Trail_Progress_Pct){
               MoveSL(ticket,g_openEntry);
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

      double cv=iClose(g_sym,_Period,Vel_Bars+1), cn=iClose(g_sym,_Period,1);
      if(cv>0&&cn>0&&MathAbs(cn-cv)/Vel_Bars>Vel_Threshold) return;

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
