//+------------------------------------------------------------------+
//|  MoneyMachine7_v1761.mq5                                        |
//|  v17.61 — Compounding real desde $30: señal OPT2 + SL escalable |
//|                                                                  |
//|  DIAGNOSTICO v17.60:                                            |
//|  TODOS los 63 trades usaron exactamente 0.01 lots               |
//|  El compounding no activa hasta balance=$2,000                  |
//|  CAUSA: SL_Min=19.2pts → lot = bal*2% / (19.2*100)             |
//|         → necesita $1,920 de balance para subir a 0.02 lots     |
//|  RESULTADO: curva lineal con pendiente fija, no exponencial     |
//|                                                                  |
//|  FIX ESTRUCTURAL:                                               |
//|  SL_Min vuelve a 3.0pts (v17.53 original)                      |
//|  Con SL=3: lot = bal*2% / (3*100) = bal/15000                  |
//|  → bal=$30: lot=0.002 → 0.01 mínimo (OK)                      |
//|  → bal=$150: lot=0.01 (primer nivel)                           |
//|  → bal=$300: lot=0.02 (doble)                                  |
//|  → bal=$1500: lot=0.10 (×10)                                   |
//|  → bal=$3000: lot=0.20 (×20) → EXPONENCIAL REAL                |
//|                                                                  |
//|  SEÑAL: mantener lo mejor de OPT2 que funciona                 |
//|  - Range_Bars=50 (más contexto)                                 |
//|  - Zone_Pct=0.555 (zona precisa)                               |
//|  - Confirm_Points=2.0 (reducido para más trades)               |
//|  - Trend_Bars=50, Trend_Min_Move=15 (filtro moderado)          |
//|                                                                  |
//|  GESTIÓN: lo mejor de v17.53 + OPT2                            |
//|  - Trail_Start=0.5pts (v17.53: activa inmediato)               |
//|  - Trail_Dist=5.0pts (entre v17.53=3.5 y OPT2=12.95)          |
//|  - TP_Ratio=8.0x (entre 5x de v17.53 y 32x de OPT2)           |
//|  - Partial=true al 40% TP (captura ganancias intermedias)      |
//|  - Time_Trail=2h (si no progresa → BE)                         |
//|  - Max_Positions=1 (simplicidad y control)                      |
//|                                                                  |
//|  HORAS: solo las mejores confirmadas en TODOS los datasets      |
//|  H15: WR=67% OPT2, WR=88% v17.53 — REINA ABSOLUTA             |
//|  H2, H19, H22: consistentemente positivas                       |
//|  H7: marginal, incluida pero vigilada                           |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.61"
#property strict

// SEÑAL — Lo mejor de OPT2 adaptado
input int    Range_Bars          = 50;    // OPT2: más contexto que 20
input double Zone_Pct            = 0.555; // OPT2: zona precisa
input double Confirm_Points      = 2.0;   // Reducido para más trades calificados

// SL/TP — ESCALABLE para compounding desde $30
input int    Local_Vol_Bars      = 6;     // OPT2: 6 barras
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 3.0;  // ← CLAVE: permite compounding desde $30
input double SL_Max              = 15.0; // Cap razonable
input double TP_Ratio            = 8.0;  // 8x = equilibrio OPT2(32x) y v17.53(5x)

// PARTIAL CLOSE — captura ganancias intermedias (suaviza curva)
input bool   Use_Partial_Close   = true;
input double Partial_Trigger_Pct = 0.40;
input double Partial_Close_Pct   = 0.50;

// TRAILING — activa casi inmediato (v17.53 aprendizaje)
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 0.5;  // v17.53: activa en 0.5pts
input double Trail_Distance_Pts  = 5.0;  // Intermedio OPT2(12.95) y v17.53(3.5)

// BREAKEVEN
input bool   Use_Breakeven       = true;
input double BE_Trigger_Pct      = 0.60;

// TIME TRAIL
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 7200; // 2h — si no avanza → BE
input double Trail_Progress_Pct  = 0.20;

// FILTROS — Moderados
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 4.4;  // OPT2 validado
input int    Trend_Bars          = 50;   // Moderado
input double Trend_Min_Move      = 15.0; // Bloquea solo alzas fuertes (50 barras)

// WEEKEND
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

// ANTI-RACHA
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

// HORAS: las mejores de todos los datasets
input bool   Use_Hour_Filter     = true;

// LOTAJE — COMPOUNDING REAL
// lot = balance * Risk_Pct / (SL_dist * 100)
// Con SL_Min=3: el lot CRECE desde el primer dólar de ganancia
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.020; // 2% del balance en riesgo
input double Max_Risk_USD        = 200.0; // Sube con la cuenta manualmente si se desea
input double Min_Lot             = 0.01;
input double Max_Lot             = 10.0;

input int    Max_Positions       = 1;
input int    InpMagicNumber      = 176100;
input int    InpSlippagePoints   = 10;

//--- Globals
string   g_sym; double g_point; int g_magic;
datetime g_lastBarTime = 0;
int      g_pendingDir = 0; double g_confirmLevel = 0, g_pendingSL = 0;
double   g_openEntry = 0, g_openSLDist = 0, g_openTPDist = 0;
bool     g_partialDone = false, g_trailActive = false;
bool     g_beMovedOnce = false, g_timeTrailDone = false;
datetime g_openTime = 0;
int      g_consecLosses = 0, g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // H15: reina absoluta (WR=67-88% en todos los datasets)
   // H2, H19, H22: positivas y consistentes
   // H7: marginal pero incluida
   // Sin H0: pierde en todos los datasets sin excepción
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
   if(!Use_Risk_Based_Lot) return Min_Lot;
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   double risk = MathMin(bal * Risk_Pct_Per_Trade, Max_Risk_USD);
   double lot  = risk / (sl_dist * 100.0);
   double mn=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_MAX);
   double st=SymbolInfoDouble(g_sym,SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st>0) lot = MathFloor(lot/st)*st;
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
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
      Print("MM7 CLOSE ",reason);
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
      g_partialDone=false; g_trailActive=false; g_beMovedOnce=false;
      g_timeTrailDone=false; g_openTime=TimeCurrent();
      Print("MM7 SELL bid=",bid," SL=",sl," TP=",tp,
            " lot=",lot," SLd=",DoubleToString(sl_dist,1),
            " risk=$",DoubleToString(lot*sl_dist*100,1),
            " bal=$",DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
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
   req.action=TRADE_ACTION_SLTP; req.symbol=g_sym; req.position=ticket;
   req.sl=newSL; req.tp=curTP; OrderSend(req,res);
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
   g_openEntry=0; g_openSLDist=0; g_openTPDist=0;
   g_partialDone=false; g_trailActive=false; g_beMovedOnce=false;
   g_timeTrailDone=false; g_openTime=0;
}

int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   Print("MM7 v17.61 | SELL-ONLY | Horas:2,7,15,19,22",
         " | Range=",Range_Bars," Zone=",Zone_Pct,
         " | SL[",SL_Min,"-",SL_Max,"] TP=",TP_Ratio,"x",
         " | Trail ",Trail_Start_Pts,"→",Trail_Distance_Pts,"pts",
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

      // 1. TRAILING (activa desde 0.5pts)
      if(Use_Trail && favorable>=Trail_Start_Pts){
         double newSL=ask+Trail_Distance_Pts;
         MoveSL(ticket,newSL);
         if(!g_trailActive){ g_trailActive=true; }
      }

      // 2. PARTIAL al 40% TP
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

      // 3. BE clásico
      if(Use_Breakeven && !g_beMovedOnce && !g_trailActive && g_openSLDist>0){
         if(favorable>=g_openSLDist*BE_Trigger_Pct){ MoveSL(ticket,g_openEntry); g_beMovedOnce=true; }
      }

      // 4. TIME TRAIL 2h
      if(Use_Time_Trail && !g_timeTrailDone && g_openTime>0){
         if((now-g_openTime)>=Time_Trail_Sec){
            if(favorable<g_openSLDist*Trail_Progress_Pct) MoveSL(ticket,g_openEntry);
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
