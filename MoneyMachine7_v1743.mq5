//+------------------------------------------------------------------+
//|  MoneyMachine7_v1743.mq5                                        |
//|  v17.43 — Lotaje controlado + horas limpias + estabilidad total |
//|                                                                  |
//|  DIAGNOSTICO v17.42:                                            |
//|  105 trades | Net=+$933 | Max DD=$772 | Sharpe=0.208           |
//|  Dias positivos: 8/12 | std=$374/dia (demasiado volatil)       |
//|                                                                  |
//|  PROBLEMAS CRITICOS IDENTIFICADOS:                               |
//|                                                                  |
//|  1. BUG LOTAJE: Risk=1.5%, SL_Min=2pts → lot=balance×0.015/200 |
//|     Con cuenta=$6000: lot=0.45. Si SL realmente es 5pts → loss  |
//|     de $225. El riesgo REAL no es 1.5% sino hasta 5-10%.        |
//|     FIX: cap duro en dolares por trade (Max_Risk_USD)           |
//|     lot = min(riesgo_calculado, Max_Risk_USD) / (SL × 100)     |
//|                                                                  |
//|  2. HORAS 13 y 15 NEGATIVAS: npt=-10 y -24 en v17.42           |
//|     Aunque eran positivas antes, con el nuevo lotaje grande      |
//|     las perdidas se amplifican. Eliminar 13 y 15 del filtro.    |
//|     Horas limpias confirmadas: 0,2,7,9(sell),19,22             |
//|                                                                  |
//|  3. VOLATILIDAD DIARIA MUY ALTA: std=$374/dia                  |
//|     Reducir Risk_Pct a 0.8% + Max_Risk_USD=$50                 |
//|     Objetivo: std < $100/dia para curva suave                   |
//|                                                                  |
//|  4. PARTIAL CLOSE: funciona bien (33 eventos/dia positivos)     |
//|     Mantener pero ajustar trigger al 35% del TP                 |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.43"
#property strict

// Señal
input int    Range_Bars          = 20;
input double Zone_Pct            = 0.15;
input double Confirm_Points      = 1.00;

// SL/TP local
input int    Local_Vol_Bars      = 3;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 2.00;
input double SL_Max              = 10.0;   // Bajado de 12 a 10
input double TP_Ratio            = 5.0;

// Cierre parcial
input bool   Use_Partial_Close   = true;
input double Partial_Trigger_Pct = 0.35;   // 35% del TP
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

// Filtro horario — solo horas con edge limpio
// 0,2,7: ambas direcciones | 9: solo SELL
// Eliminadas: 13,15 (negativas en v17.42)
input bool   Use_Hour_Filter     = true;

// LOTAJE — riesgo fijo con tope absoluto en dolares
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.008;  // 0.8% del balance
input double Max_Risk_USD        = 50.0;   // Tope duro: maximo $50 en riesgo/trade
input double Lot_Fixed           = 0.01;
input double Max_Lot             = 3.0;    // Bajado de 5 a 3
input double Min_Lot             = 0.01;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 174300;
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
// 0 = no operar | 1 = ambas direcciones | -1 = solo SELL
int GetHourMode(int hour)
{
   if(!Use_Hour_Filter) return 1;
   switch(hour) {
      case 0: case 2: case 7: case 19: case 22:
         return 1;   // ambas direcciones
      case 9:
         return -1;  // solo SELL
      default:
         return 0;   // no operar
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
// Lotaje con doble capa de proteccion:
// 1. Risk_Pct × balance / (SL × 100)
// 2. Cap duro: Max_Risk_USD / (SL × 100)
// Usa el menor de los dos → nunca arriesga mas de Max_Risk_USD
double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Lot_Fixed, 2);
   
   double bal  = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                         AccountInfoDouble(ACCOUNT_EQUITY));
   
   // Calculo por porcentaje
   double risk_pct  = bal * Risk_Pct_Per_Trade;
   // Calculo por tope absoluto
   double risk_cap  = Max_Risk_USD;
   // Usar el menor
   double risk      = MathMin(risk_pct, risk_cap);
   
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

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
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
   double real_risk = lot * sl_dist * 100;

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
            " lot=",lot," risk=$",DoubleToString(real_risk,2));
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
   if(StringFind(comment,"partial")>=0) return; // no contar cierre parcial
   if(StringFind(comment,"sl")>=0 && profit<-0.5){
      g_consecLosses++;
      if(g_consecLosses>=Max_Consec_Losses){
         g_pauseBarsLeft=Pause_Bars; g_pendingDir=0;
         Print("MM7 PAUSA ",g_consecLosses,"→",Pause_Bars,"barras");
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
   Print("MM7 v17.43 | ",g_sym,
         " | TP=",TP_Ratio,"x SL[",SL_Min,"-",SL_Max,"]",
         " | Partial@",Partial_Trigger_Pct,"x×50%",
         " | BE@",BE_Trigger_Pct," Trail@",Time_Trail_Sec,"s",
         " | Risk=",Risk_Pct_Per_Trade*100,"% Cap=$",Max_Risk_USD,
         " | Hours:0,2,7,9(sell),19,22");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);

   // WEEKEND
   if(Close_On_FriClose&&IsFridayClose()){
      ulong tk=GetOpenTicket();
      if(tk>0) ClosePosition(tk,"FriClose");
      g_pendingDir=0; return;
   }

   // GESTION POSICION ABIERTA
   ulong ticket=GetOpenTicket();
   if(ticket>0 && g_openEntry>0 && g_openSLDist>0 && g_openTPDist>0){
      double favorable=(g_openDir==1)?(bid-g_openEntry):(g_openEntry-ask);
      datetime now=TimeCurrent();

      // CIERRE PARCIAL al 35% del TP
      if(Use_Partial_Close && !g_partialDone){
         if(favorable >= g_openTPDist * Partial_Trigger_Pct){
            if(PositionSelectByTicket(ticket)){
               double cur_vol=PositionGetDouble(POSITION_VOLUME);
               double close_vol=NormalizeDouble(cur_vol*Partial_Close_Pct,2);
               double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
               double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
               if(st>0) close_vol=MathFloor(close_vol/st)*st;
               close_vol=MathMax(close_vol,mn);
               if(close_vol<cur_vol){
                  ClosePartial(ticket,close_vol);
                  g_partialDone=true;
                  MoveSL(ticket,g_openEntry);
                  g_beMoved=true; g_timeTrailDone=true;
               }
            }
         }
      }

      // BE clasico
      if(Use_Breakeven && !g_beMoved && !g_partialDone){
         if(favorable >= g_openSLDist*BE_Trigger_Pct){
            MoveSL(ticket,g_openEntry);
            g_beMoved=true; g_timeTrailDone=true;
         }
      }

      // TIME TRAIL
      if(Use_Time_Trail && !g_timeTrailDone && !g_beMoved && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable < g_openSLDist*Trail_Progress_Pct){
               MoveSL(ticket,g_openEntry);
               Print("MM7 TIME-TRAIL→BE fav=",DoubleToString(favorable,2));
            }
            g_timeTrailDone=true;
         }
      }
   }

   if(CountByMagic()>=Max_Positions){g_pendingDir=0;return;}

   // NUEVA BARRA
   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_lastBarTime){
      g_lastBarTime=curBar; g_pendingDir=0;
      if(g_pauseBarsLeft>0){g_pauseBarsLeft--;return;}

      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;

      int hmode=GetHourMode(dt.hour);
      if(hmode==0) return;

      // Velocidad
      double cv=iClose(g_sym,_Period,Vel_Bars+1), cn=iClose(g_sym,_Period,1);
      if(cv>0&&cn>0&&MathAbs(cn-cv)/Vel_Bars>Vel_Threshold) return;

      // Rango señal
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*Zone_Pct, lowerZone=rL+range*Zone_Pct;

      // SL local
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
