//+------------------------------------------------------------------+
//|  MoneyMachine7_v1741.mq5                                        |
//|  v17.41 — TP 5x + horas limpias + lotaje proporcional al riesgo |
//|                                                                  |
//|  DIAGNOSTICO v17.40:                                            |
//|  142 trades | WR=18.3% | Net=+$1380 | DD=4.13%                 |
//|                                                                  |
//|  PROBLEMAS IDENTIFICADOS Y FIXES:                               |
//|                                                                  |
//|  1. TP_RATIO 3.0x VS REAL 5.08x: el mercado viaja 22.72pts     |
//|     promedio al TP, SL promedio 4.47pts → ratio real = 5.08x   |
//|     Con ratio 5.0x: misma WR (TP sigue alcanzable), pero       |
//|     cada ganancia es 67% mayor. EV: 0.183×(116×1.67) - 0.817×23|
//|     = 35.5 - 18.8 = +$16.7/trade vs +$2.4/trade actual        |
//|                                                                  |
//|  2. HORAS 9 Y 13 TOXICAS: WR=5.6% y 5.0% → 1 win en 38 trades |
//|     Sin ellas: net +$150 más, WR sube a 23.1%                  |
//|     Eliminadas del filtro horario                               |
//|                                                                  |
//|  3. LOTAJE: escalar el lot basado en el SL real de cada trade   |
//|     En lugar de balance/1000: usar riesgo fijo por trade (1%)  |
//|     lot = (balance × Risk_Pct) / (SL_dist × 100)              |
//|     Esto garantiza que trades con SL pequeño usan más lot      |
//|     y trades con SL grande usan menos → riesgo siempre = 1%   |
//|                                                                  |
//|  4. BUY FILTER: quitar Trend_Min_Move_Buy diferenciado.        |
//|     Usar un solo umbral para ambos pero con mayor claridad:    |
//|     Solo bloquear cuando tendencia ES CONTRARIA (no lateral)   |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.41"
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
input double TP_Ratio            = 5.0;   // ← MERCADO ENTREGA 5.08x REAL

// Trailing stop temporal
input int    Time_Trail_Sec      = 600;
input double Trail_Progress_Pct  = 0.40;
input bool   Use_Time_Trail      = true;

// Filtro velocidad
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 5.0;

// Filtro tendencia — umbral único para ambas direcciones
input int    Trend_Bars          = 15;
input double Trend_Min_Move      = 6.0;   // Bloquear solo si tendencia contraria > 6pts

// Weekend
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// Breakeven
input double BE_Trigger_Pct      = 0.50;  // BE más temprano (50% en vez de 70%)
input bool   Use_Breakeven       = true;

// Anti-racha
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// Filtro horario refinado: eliminadas 9 y 13 (tóxicas en v17.40)
// Horas activas: 0, 2, 7, 15, 19, 22
input bool   Use_Hour_Filter     = true;

// LOTAJE BASADO EN RIESGO FIJO
// En vez de balance/Margin_Per_Lot, usar:
// lot = (balance × Risk_Pct_Per_Trade) / (SL_dist × 100)
// Esto adapta el lot al riesgo REAL de cada trade
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.01;  // 1% del balance en riesgo por trade
input double Lot_Fixed           = 0.01;
input double Max_Lot             = 5.0;
input double Min_Lot             = 0.01;

// Sistema
input int    Max_Positions       = 1;
input int    InpMagicNumber      = 174100;
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
int      g_openDir       = 0;
bool     g_beMoved       = false;
datetime g_openTime      = 0;
bool     g_timeTrailDone = false;

int      g_consecLosses  = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // Horas positivas confirmadas: 0,2,7,15,19,22
   // Eliminadas: 9 (WR=5.6%), 13 (WR=5.0%)
   switch(hour) {
      case 0: case 2: case 7:
      case 15: case 19: case 22:
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Bloquea la señal si la tendencia macro va FUERTEMENTE en contra
bool TrendBlocks(int signalDir)
{
   double closeNow = iClose(g_sym, _Period, 1);
   double closeOld = iClose(g_sym, _Period, Trend_Bars + 1);
   if(closeNow == 0 || closeOld == 0) return false;
   double move = closeNow - closeOld;
   // signalDir=1 (BUY): bloqueado si mercado bajando fuerte
   if(signalDir ==  1 && move <= -Trend_Min_Move) return true;
   // signalDir=-1 (SELL): bloqueado si mercado subiendo fuerte
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
// LOTAJE BASADO EN RIESGO FIJO
// lot = (balance × Risk_Pct) / (SL_pts × valor_por_punto)
// Para XAUUSD: valor_por_punto = 100 × lot → despejando: lot = risk_$ / (SL_pts × 100)
double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Lot_Fixed, 2);
   
   double bal  = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                         AccountInfoDouble(ACCOUNT_EQUITY));
   double risk  = bal * Risk_Pct_Per_Trade;        // $ en riesgo
   double lot   = risk / (sl_dist * 100.0);         // lot = riesgo / (pts × $/pt)
   
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
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED) Print("MM7 CLOSE ",reason);
}

//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type, double sl_dist)
{
   double ask   = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double entry = (type == ORDER_TYPE_BUY) ? ask : bid;
   int    digs  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   int    dir   = (type == ORDER_TYPE_BUY) ? 1 : -1;
   double tp    = NormalizeDouble(entry + dir * sl_dist * TP_Ratio, digs);
   double sl    = NormalizeDouble(entry - dir * sl_dist, digs);
   double lot   = CalcLot(sl_dist);

   MqlTradeRequest req = {}; MqlTradeResult res = {};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot; req.type=type;
   req.price=entry; req.sl=sl; req.tp=tp; req.deviation=InpSlippagePoints;
   req.magic=g_magic; req.comment="MM7";
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}

   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0; g_openEntry=entry; g_openSLDist=sl_dist;
      g_openDir=dir; g_beMoved=false; g_openTime=TimeCurrent(); g_timeTrailDone=false;
      Print("MM7 OPEN ",(type==ORDER_TYPE_BUY?"BUY":"SELL"),
            " entry=",entry," SL=",sl," TP=",tp,
            " SLd=",DoubleToString(sl_dist,2)," lot=",lot,
            " risk=$",DoubleToString(sl_dist*lot*100,2));
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
   if(StringFind(comment,"sl")>=0 && profit<-0.5){
      g_consecLosses++;
      if(g_consecLosses>=Max_Consec_Losses){
         g_pauseBarsLeft=Pause_Bars; g_pendingDir=0;
         Print("MM7 PAUSA ",g_consecLosses,"SLs→",Pause_Bars,"barras");
      }
   } else { g_consecLosses=0; }
   g_openEntry=0; g_openSLDist=0; g_openDir=0;
   g_beMoved=false; g_openTime=0; g_timeTrailDone=false;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   Print("MM7 v17.41 | ",g_sym,
         " | TP=",TP_Ratio,"x SL_Max=",SL_Max,
         " | BE@",BE_Trigger_Pct," Trail@",Time_Trail_Sec,"s",
         " | Vel<=",Vel_Threshold," Trend>=",Trend_Min_Move,
         " | Risk=",Risk_Pct_Per_Trade*100,"% MaxLot=",Max_Lot,
         " | Hours:0,2,7,15,19,22");
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

   // GESTIÓN POSICION ABIERTA
   ulong ticket=GetOpenTicket();
   if(ticket>0 && g_openEntry>0 && g_openSLDist>0){
      datetime now=TimeCurrent();
      double favorable=(g_openDir==1)?(bid-g_openEntry):(g_openEntry-ask);

      // BE cuando precio alcanza BE_Trigger_Pct×SL
      if(Use_Breakeven && !g_beMoved){
         if(favorable >= g_openSLDist*BE_Trigger_Pct){
            MoveSL(ticket,g_openEntry);
            g_beMoved=true; g_timeTrailDone=true;
         }
      }

      // TIME TRAIL: si pasó el tiempo y no progresó → BE
      if(Use_Time_Trail && !g_timeTrailDone && !g_beMoved && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable < g_openSLDist*Trail_Progress_Pct){
               MoveSL(ticket,g_openEntry);
               Print("MM7 TIME-TRAIL progress=",DoubleToString(favorable,2)," → BE");
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
      if(!IsGoodHour(dt.hour)) return;

      // Velocidad
      double cv=iClose(g_sym,_Period,Vel_Bars+1), cn=iClose(g_sym,_Period,1);
      if(cv>0&&cn>0&&MathAbs(cn-cv)/Vel_Bars>Vel_Threshold) return;

      // Rango señal (20 barras)
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*Zone_Pct, lowerZone=rL+range*Zone_Pct;

      // SL local (3 barras)
      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,SL_Max),SL_Min);

      // Señal con filtro tendencia
      if(closeNow>=upperZone && !TrendBlocks(-1)){
         g_pendingDir=-1; g_confirmLevel=closeNow-Confirm_Points; g_pendingSL=slDist;
      } else if(closeNow<=lowerZone && !TrendBlocks(1)){
         g_pendingDir=1; g_confirmLevel=closeNow+Confirm_Points; g_pendingSL=slDist;
      }
      return;
   }

   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0)   return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==1&&bid>=g_confirmLevel)
      OpenOrder(ORDER_TYPE_BUY,g_pendingSL);
   else if(g_pendingDir==-1&&ask<=g_confirmLevel)
      OpenOrder(ORDER_TYPE_SELL,g_pendingSL);
}
//+------------------------------------------------------------------+
