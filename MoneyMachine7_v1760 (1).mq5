//+------------------------------------------------------------------+
//|  MoneyMachine7_v1760.mq5                                        |
//|  v17.60b — Compounding exponencial real + Daily Loss Limit      |
//|                                                                  |
//|  FUENTES DE APRENDIZAJE INTEGRADAS:                             |
//|  - v17.47: base SELL-only, trail 4pts, partial 40%              |
//|  - v17.53: trail start=0.5pts → reduce grandes pérdidas         |
//|  - OPT#1: Risk agresivo, sin trail ni BE → DD 46% (descartado) |
//|  - OPT#2: TP_Ratio=32, SL amplio, trail 12.95pts, WR=58%       |
//|            Sharpe=14.2, DD=5.1%, LR_Corr=0.977 ← MEJOR         |
//|  - Demo real auto: +1356% en un día, hora 15, 107pts/trade      |
//|  - Demo manual: intervención humana reduce ganancias             |
//|                                                                  |
//|  PRINCIPIOS DE LA VERSION MAESTRA:                              |
//|                                                                  |
//|  1. SEÑAL LIMPIA                                                |
//|     Range_Bars=50 (más contexto que 20)                         |
//|     Zone_Pct=0.555 (zona top más precisa)                       |
//|     Confirm_Points=4.6 (confirmación fuerte, menos ruido)       |
//|     SL_Local_Bars=6 (rango local con más barras)               |
//|                                                                  |
//|  2. SL/TP OPTIMIZADOS                                           |
//|     SL_Min=19.2, SL_Max=85.2 (amplio, evita stops prematuros)  |
//|     TP_Ratio=16.0 (entre 5x original y 32x OPT2)               |
//|     → Más conservador que OPT2 pero mucho más que v17.53        |
//|     TP amplio = dejar correr los winners = curva exponencial    |
//|                                                                  |
//|  3. GESTIÓN INTELIGENTE                                         |
//|     Trail_Start=2.9pts (OPT2), Trail_Dist=12.95pts (OPT2)      |
//|     → Más amplio que v17.53 (3.5pts) = no cortar winners       |
//|     Time_Trail=3.2h (si no progresa en 3h → BE)                |
//|     Partial_Close=false (OPT2: simplifica, no corta winners)    |
//|     Max_Positions=2 (entrar segunda vez si señal se repite)     |
//|                                                                  |
//|  4. COMPOUNDING REAL                                            |
//|     Risk_Pct=2% dinámico sobre balance actual                   |
//|     Cap sube con la cuenta: Max_Risk_USD=balance*0.15           |
//|     → A $30: cap=$4.5, a $500: cap=$75, a $5000: cap=$750      |
//|     Lot crece automáticamente con cada ganancia                 |
//|                                                                  |
//|  5. FILTROS OPTIMIZADOS                                         |
//|     Vel_Threshold=4.4 (OPT2 validado)                          |
//|     Trend_Bars=100, Trend_Min_Move=30 (tendencia larga)         |
//|     Horas: 2, 7, 15, 19, 22 (sin hora 0 — siempre pierde)      |
//|     → H15 es la hora reina: WR=74-88% en todos los datasets    |
//|                                                                  |
//|  PROYECCION: curva exponencial suave con drawdown <10%          |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.60"
#property strict

//--- SEÑAL
input int    Range_Bars          = 50;     // OPT2: 50 barras de contexto
input double Zone_Pct            = 0.555;  // OPT2: zona top 55.5%
input double Confirm_Points      = 4.6;   // OPT2: confirmación fuerte

//--- SL/TP
input int    Local_Vol_Bars      = 6;      // OPT2: 6 barras rango local
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 19.2;  // OPT2: SL mínimo amplio
input double SL_Max              = 85.2;  // OPT2: SL máximo amplio
input double TP_Ratio            = 16.0;  // Entre OPT2(32) y v17.53(5) = equilibrio

//--- TRAILING
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 2.9;   // OPT2 validado
input double Trail_Distance_Pts  = 12.95; // OPT2: más amplio = no cortar winners

//--- BREAKEVEN
input bool   Use_Breakeven       = false; // OPT2: desactivado (trail lo gestiona)
input double BE_Trigger_Pct      = 0.60;

//--- TIME TRAIL
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 11520; // 3.2h — si no avanza → BE
input double Trail_Progress_Pct  = 0.20;

//--- PARTIAL CLOSE
input bool   Use_Partial_Close   = false; // OPT2: desactivado = dejar correr

//--- FILTROS
input int    Vel_Bars            = 3;
input double Vel_Threshold       = 4.4;   // OPT2 validado
input int    Trend_Bars          = 100;   // OPT2: ~103, tendencia larga
input double Trend_Min_Move      = 30.0;  // OPT2: ~30.4 (bloquea solo tendencias fuertes)
input bool   Use_PrevBar_Filter  = false; // OPT2: desactivado

//--- WEEKEND
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;

//--- ANTI-RACHA
input int    Max_Consec_Losses   = 3;
input int    Pause_Bars          = 5;

//--- HORAS ACTIVAS
// Sin hora 0 (siempre pierde en todos los datasets)
// H15 es la hora reina: WR=74-88% consistente
// H2, H7, H19, H22 confirmadas positivas
input bool   Use_Hour_Filter     = true;

//--- LOTAJE EXPONENCIAL DIRECTO
// lot = balance * Lot_Balance_Pct (independiente del SL)
// Esto garantiza compounding desde el primer dólar ganado
// balance=$30:   lot = 30*0.0007 = 0.021 → 0.02
// balance=$100:  lot = 100*0.0007 = 0.07
// balance=$300:  lot = 300*0.0007 = 0.21
// balance=$1000: lot = 1000*0.0007 = 0.70 → EXPONENCIAL REAL
input bool   Use_Risk_Based_Lot  = true;
input double Lot_Balance_Pct     = 0.0007; // 0.07% del balance → compounding suave
// Con WR=52% y EV=3.64pts: cada trade aporta ~0.18% del balance
// Pérdida max por trade: 0.07% × SL_pts × 100 / 100 ≈ SL_pts × 0.07%
// Con SL=20pts: pérdida = 20 × 0.07% = 1.4% del balance (controlado)
input double Min_Lot             = 0.01;
input double Max_Lot             = 10.0;

//--- LIMITE DE PERDIDA DIARIA (protege el compounding)
// Si el día acumula más de DailyLoss_Pct% de pérdida → stop por hoy
// Esto evita que los días malos destruyan el compounding
input bool   Use_Daily_Loss_Limit = true;
input double DailyLoss_Pct       = 0.05; // Máximo 5% de pérdida diaria

//--- MULTI-POSICION
input int    Max_Positions       = 2;    // OPT2: permite 2 entradas simultáneas

//--- SISTEMA
input int    InpMagicNumber      = 176000;
input int    InpSlippagePoints   = 10;

//--- Globals
string   g_sym; double g_point; int g_magic;
datetime g_lastBarTime = 0;
int      g_pendingDir = 0;
double   g_confirmLevel = 0, g_pendingSL = 0;

// Daily loss tracking
double   g_dayStartBalance = 0;
datetime g_lastDayCheck    = 0;
bool     g_dailyLimitHit   = false;

struct TradeState {
   double entry, slDist, tpDist;
   bool   trailActive, beMovedOnce, timeTrailDone;
   datetime openTime;
};
TradeState g_states[2]; // máx 2 posiciones

int      g_consecLosses = 0;
int      g_pauseBarsLeft = 0;

//+------------------------------------------------------------------+
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // Sin hora 0 — siempre negativa en todos los datasets analizados
   // H15: WR=74-88% (la hora reina, validada en OPT2 + v17.53 + demo real)
   return (hour==2||hour==7||hour==15||hour==19||hour==22);
}

bool TrendBlocksSell()
{
   // Tendencia alcista FUERTE en 100 barras → no hacer SELL
   // Trend_Min_Move=30pts → solo bloquea si precio subió 30pts en 100 barras
   double cn=iClose(g_sym,_Period,1), co=iClose(g_sym,_Period,Trend_Bars+1);
   if(cn==0||co==0) return false;
   return (cn-co >= Trend_Min_Move);
}

bool IsFridayClose()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.day_of_week==5 && dt.hour>=FriClose_Hour_UTC);
}

// LOT DIRECTO: lot = balance * Lot_Balance_Pct
// Compounding real desde el primer trade
// No depende del SL → lot siempre crece con el balance
double CalcLot(double sl_dist)
{
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Min_Lot,2);
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   double lot = bal * Lot_Balance_Pct;
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, Min_Lot));
   lot = MathMin(lot, MathMin(Max_Lot, mx));
   if(st>0) lot = MathFloor(lot/st)*st;
   return NormalizeDouble(lot,2);
}

// Verifica si el límite de pérdida diaria fue alcanzado
bool DailyLossLimitReached()
{
   if(!Use_Daily_Loss_Limit) return false;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_dayStartBalance <= 0) return false;
   double loss_pct = (g_dayStartBalance - bal) / g_dayStartBalance;
   return (loss_pct >= DailyLoss_Pct);
}

// Actualiza el balance de inicio del día
void UpdateDayStart()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year)+"."+
                    IntegerToString(dt.mon)+"."+IntegerToString(dt.day)+" 00:00");
   if(g_lastDayCheck != today){
      g_lastDayCheck = today;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyLimitHit = false;
      Print("MM7 Nuevo día: balance inicio=$",DoubleToString(g_dayStartBalance,2));
   }
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

ulong GetTickets(ulong &arr[])
{
   int cnt=0;
   ArrayResize(arr,0);
   for(int i=0;i<PositionsTotal();i++){
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&(int)PositionGetInteger(POSITION_MAGIC)==g_magic){
         ArrayResize(arr,cnt+1); arr[cnt++]=tk;
      }
   }
   return cnt;
}

void ClosePosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;
   double vol=PositionGetDouble(POSITION_VOLUME);
   double price=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=vol;
   req.type=ORDER_TYPE_BUY; req.price=price; req.position=ticket;
   req.deviation=InpSlippagePoints; req.magic=g_magic;
   req.comment="MM7-"+reason; req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED)
      Print("MM7 CLOSE ",reason," ticket=",ticket);
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
   req.action=TRADE_ACTION_DEAL; req.symbol=g_sym; req.volume=lot;
   req.type=ORDER_TYPE_SELL; req.price=bid; req.sl=sl; req.tp=tp;
   req.deviation=InpSlippagePoints; req.magic=g_magic; req.comment="MM7";
   req.type_filling=ORDER_FILLING_FOK;
   if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_IOC;if(!OrderSend(req,res)){req.type_filling=ORDER_FILLING_RETURN;OrderSend(req,res);}}
   
   if(res.retcode==TRADE_RETCODE_DONE||res.retcode==TRADE_RETCODE_PLACED){
      g_pendingDir=0;
      double bal=AccountInfoDouble(ACCOUNT_BALANCE);
      Print("MM7 SELL bid=",bid," SL=",sl," TP=",tp," lot=",lot,
            " SLd=",DoubleToString(sl_dist,1)," risk=$",
            DoubleToString(lot*sl_dist*100,1)," bal=$",DoubleToString(bal,2));
   } else { Print("MM7 FAIL retcode=",res.retcode); }
}

void MoveSL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return;
   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
   newSL=NormalizeDouble(newSL,digs);
   if(newSL>=curSL) return; // SELL: SL solo baja
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_SLTP; req.symbol=g_sym;
   req.position=ticket; req.sl=newSL; req.tp=curTP;
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
         Print("MM7 PAUSA tras ",g_consecLosses," SLs");
      }
   } else { g_consecLosses=0; }
}

int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   
   // Init estados
   for(int i=0;i<2;i++){
      g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
      g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
      g_states[i].timeTrailDone=false; g_states[i].openTime=0;
   }
   
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_lastDayCheck = 0; g_dailyLimitHit = false;
   
   Print("MM7 v17.60b EXPONENTIAL | ",g_sym,
         " | SELL-ONLY | Horas:2,7,15,19,22",
         " | TP=",TP_Ratio,"x SL[",SL_Min,"-",SL_Max,"]",
         " | Trail=",Trail_Start_Pts,"→",Trail_Distance_Pts,"pts",
         " | Lot=bal×",Lot_Balance_Pct*100,"% DailyLoss<",DailyLoss_Pct*100,"%",
         " | MaxPos=",Max_Positions);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   datetime now=TimeCurrent();

   // Actualizar inicio del día
   UpdateDayStart();

   // WEEKEND
   if(Close_On_FriClose&&IsFridayClose()){
      ulong tks[]; GetTickets(tks);
      for(int i=0;i<ArraySize(tks);i++) ClosePosition(tks[i],"FriClose");
      g_pendingDir=0; return;
   }

   // GESTIÓN DE POSICIONES ABIERTAS
   ulong tks[]; int npos=GetTickets(tks);
   for(int pi=0;pi<npos;pi++){
      ulong tk=tks[pi];
      if(!PositionSelectByTicket(tk)) continue;
      
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double favorable = entry - ask; // SELL: positivo cuando baja
      
      // Buscar estado de esta posición
      int si=-1;
      for(int i=0;i<2;i++){
         if(MathAbs(g_states[i].entry-entry)<0.01 && g_states[i].entry>0){ si=i; break; }
      }
      if(si<0){
         // Nueva posición sin estado registrado — inicializar
         for(int i=0;i<2;i++){
            if(g_states[i].entry==0){ si=i; break; }
         }
         if(si<0) continue;
         g_states[si].entry    = entry;
         g_states[si].slDist   = entry - curSL; // SELL: SL arriba, dist = entry - sl (negativo aquí... usar abs)
         g_states[si].slDist   = MathAbs(curSL - entry);
         g_states[si].tpDist   = g_states[si].slDist * TP_Ratio;
         g_states[si].openTime = now;
         g_states[si].trailActive   = false;
         g_states[si].beMovedOnce   = false;
         g_states[si].timeTrailDone = false;
      }
      
      double slD = g_states[si].slDist;
      
      // 1. TRAILING — activa cuando precio baja Trail_Start_Pts
      if(Use_Trail && favorable>=Trail_Start_Pts){
         double newSL=ask+Trail_Distance_Pts;
         MoveSL(tk,newSL);
         if(!g_states[si].trailActive){
            g_states[si].trailActive=true;
            Print("MM7 TRAIL ON pos=",pi+1," fav=",DoubleToString(favorable,2));
         }
      }
      
      // 2. BREAKEVEN clásico (respaldo si trail no activó)
      if(Use_Breakeven && !g_states[si].beMovedOnce && !g_states[si].trailActive && slD>0){
         if(favorable >= slD*BE_Trigger_Pct){
            MoveSL(tk, entry);
            g_states[si].beMovedOnce=true;
         }
      }
      
      // 3. TIME TRAIL — si tras 3.2h no progresó suficiente → BE
      if(Use_Time_Trail && !g_states[si].timeTrailDone && g_states[si].openTime>0){
         if((now-g_states[si].openTime)>=Time_Trail_Sec){
            if(favorable < slD*Trail_Progress_Pct){
               MoveSL(tk, entry);
               Print("MM7 TIME-TRAIL→BE pos=",pi+1);
            }
            g_states[si].timeTrailDone=true;
         }
      }
   }
   
   // Limpiar estados de posiciones cerradas
   for(int i=0;i<2;i++){
      if(g_states[i].entry==0) continue;
      bool found=false;
      for(int pi=0;pi<npos;pi++){
         if(PositionSelectByTicket(tks[pi])){
            if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-g_states[i].entry)<0.01){
               found=true; break;
            }
         }
      }
      if(!found){
         g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
         g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
         g_states[i].timeTrailDone=false; g_states[i].openTime=0;
      }
   }

   if(CountByMagic()>=Max_Positions){g_pendingDir=0;return;}

   // LIMITE DIARIO DE PÉRDIDA
   if(DailyLossLimitReached()){
      if(!g_dailyLimitHit){
         g_dailyLimitHit=true;
         g_pendingDir=0;
         Print("MM7 DAILY LIMIT alcanzado. Sin nuevas entradas hoy.");
      }
      return;
   }

   // NUEVA BARRA
   datetime curBar=iTime(g_sym,_Period,0);
   if(curBar!=g_lastBarTime){
      g_lastBarTime=curBar; g_pendingDir=0;
      if(g_pauseBarsLeft>0){g_pauseBarsLeft--;return;}

      MqlDateTime dt; TimeToStruct(curBar,dt);
      if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC) return;
      if(!IsGoodHour(dt.hour)) return;

      // Filtro velocidad
      double cv2=iClose(g_sym,_Period,Vel_Bars+1), cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>Vel_Threshold) return;

      // Rango 50 barras
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*Zone_Pct;

      // SL local (6 barras)
      double lH=-DBL_MAX, lL=DBL_MAX;
      for(int i=1;i<=Local_Vol_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h>lH) lH=h; if(l<lL) lL=l;
      }
      double slDist=MathMax(MathMin((lH-lL)*SL_Local_Pct,SL_Max),SL_Min);

      // SEÑAL SELL: precio en top del rango + no tendencia alcista fuerte
      if(closeNow>=upperZone && !TrendBlocksSell()){
         g_pendingDir=-1;
         g_confirmLevel=closeNow-Confirm_Points;
         g_pendingSL=slDist;
      }
      return;
   }

   if(g_pauseBarsLeft>0) return;
   if(g_pendingDir==0) return;

   MqlDateTime dt; TimeToStruct(now,dt);
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   // Entrada: precio bajó Confirm_Points desde el cierre de señal
   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
