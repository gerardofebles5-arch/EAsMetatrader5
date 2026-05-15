//+------------------------------------------------------------------+
//|  MoneyMachine7_v1771.mq5                                        |
//|  v17.71 — v17.70 optimizado: más trades + autoaprendizaje ágil  |
//|                                                                  |
//|  CAMBIOS vs v17.70 (basados en datos reales):                   |
//|  1. Todas las horas activas (2,7,15,19,22) — autoaprendizaje    |
//|     bloquea H7/H22 rápido (3 muestras en vez de 8)             |
//|     Simulación: block@2losses=$269 vs no-block=$244            |
//|  2. Bloqueo diario tras 2 pérdidas (no 3)                       |
//|  3. Trail_Start=5pts, Trail_Dist=15pts (protege antes, corre más)|
//|  4. Autoaprendizaje más agresivo: bloquea horas malas con WR<35%|
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property version   "17.71"
#property strict

//=== PARAMETROS BASE (v17.60) ===
input int    Range_Bars          = 50;
input double Zone_Pct_Base       = 0.555;  // Base — se adapta
input double Confirm_Points      = 4.6;
input int    Local_Vol_Bars      = 6;
input double SL_Local_Pct        = 1.20;
input double SL_Min              = 19.2;
input double SL_Max              = 85.2;
input double TP_Ratio            = 16.0;
input bool   Use_Trail           = true;
input double Trail_Start_Pts     = 5.0;  // SUBIDO 2.9→5: activa solo cuando hay ganancia real
input double Trail_Distance_Base = 15.0; // AJUSTADO: 12.95→15pts (más espacio)
input bool   Use_Breakeven       = false;
input double BE_Trigger_Pct      = 0.60;
input bool   Use_Time_Trail      = true;
input int    Time_Trail_Sec      = 11520;
input double Trail_Progress_Pct  = 0.20;
input bool   Use_Partial_Close   = false;

//=== PARAMETROS DE AUTOAPRENDIZAJE ===
input int    Learn_Min_Samples   = 3;    // REDUCIDO 8→3: bloquea horas malas rápido
input double Learn_WR_Block      = 0.35; // SUBIDO 30→35%: más agresivo en bloquear
input double Learn_WR_Reopen     = 0.50; // SUBIDO 45→50%: solo reabre si realmente mejoró
input int    Learn_Recalc_Every  = 10;
input double Learn_Quick_Loss_Sec= 300;
input int    Learn_Vol_Window    = 20;
input double Learn_Trail_Scale   = 0.30;

//=== GESTION DE RACHA ===
input double Streak_Reduce_Pct   = 0.50; // Reducir lot 50% tras 2 SLs seguidos
input double Streak_Boost_Pct    = 1.10; // Subir lot 10% tras 3 wins seguidos
input int    Streak_Loss_Trigger = 2;    // SLs seguidos para reducir
input int    Streak_Win_Trigger  = 3;    // Wins seguidos para subir

//=== FILTROS ===
input int    Vel_Bars            = 3;
input double Vel_Threshold_Base  = 4.4;  // Base — se adapta
input int    Trend_Bars          = 100;
input double Trend_Min_Move      = 30.0;
input int    FriClose_Hour_UTC   = 20;
input bool   Close_On_FriClose   = true;
input int    Max_Consec_Losses   = 4;
input int    Pause_Bars          = 5;
input bool   Use_Hour_Filter     = true;

//=== LOTAJE ===
input bool   Use_Risk_Based_Lot  = true;
input double Risk_Pct_Per_Trade  = 0.020;
input double Cap_Pct_Of_Balance  = 0.15;
input double Min_Lot             = 0.01;
input double Max_Lot             = 10.0;

//=== SISTEMA ===
input int    Max_Positions       = 2;
input int    InpMagicNumber      = 177100;
input int    InpSlippagePoints   = 10;

//=== ESTRUCTURA DE MEMORIA ===
struct TradeRecord {
   int    hour;
   double sl_dist;
   double profit;
   double hold_sec;
   bool   is_win;
   bool   is_quick_loss; // perdida en <5min
};

struct HourStats {
   int    n;
   int    wins;
   double total_profit;
   double total_ev;
   bool   blocked;
   int    block_samples; // cuántas muestras desde que se bloqueó
};

struct TradeState {
   double   entry, slDist, tpDist;
   bool     trailActive, beMovedOnce, timeTrailDone;
   datetime openTime;
};

//=== GLOBALS ===
string   g_sym; double g_point; int g_magic;
datetime g_lastBarTime = 0;
int      g_pendingDir  = 0;
double   g_confirmLevel = 0, g_pendingSL = 0;

TradeRecord g_history[500]; // hasta 500 trades en memoria
int         g_histCount = 0;

HourStats   g_hourStats[24]; // estadísticas por hora

TradeState  g_states[2];

int    g_consecLosses  = 0;
int    g_consecWins    = 0;
int    g_pauseBarsLeft = 0;
int    g_totalTrades   = 0;

// NUEVO: contador de pérdidas diarias para detector de día tendencial
int      g_dayLossCount  = 0;    // pérdidas acumuladas hoy
double   g_dayPnL        = 0;    // P&L acumulado hoy
datetime g_currentDay    = 0;    // día actual para resetear contadores
bool     g_dayBlocked    = false; // día bloqueado por exceso de pérdidas

// Parámetros adaptativos (se ajustan con el aprendizaje)
double g_zone_pct      = 0;  // Zone_Pct_Base + ajuste aprendido
double g_trail_dist    = 0;  // Trail_Distance_Base + ajuste volatilidad
double g_vel_threshold = 0;  // Vel_Threshold_Base + ajuste aprendido
double g_lot_scale     = 1.0; // Escala de lot según racha

//+------------------------------------------------------------------+
void InitLearning()
{
   g_zone_pct      = Zone_Pct_Base;
   g_trail_dist    = Trail_Distance_Base;
   g_vel_threshold = Vel_Threshold_Base;
   g_lot_scale     = 1.0;
   
   // NUEVO: inicializar tracking diario
   g_dayLossCount = 0;
   g_dayPnL       = 0;
   g_currentDay   = 0;
   g_dayBlocked   = false;
   
   for(int h=0; h<24; h++){
      g_hourStats[h].n             = 0;
      g_hourStats[h].wins          = 0;
      g_hourStats[h].total_profit  = 0;
      g_hourStats[h].total_ev      = 0;
      g_hourStats[h].blocked       = false;
      g_hourStats[h].block_samples = 0;
   }
}

//+------------------------------------------------------------------+
// Registra un trade completado en la memoria
void RecordTrade(int hour, double sl_dist, double profit, double hold_sec)
{
   if(g_histCount >= 500) {
      // Shift memory: drop oldest 50 trades
      for(int i=0; i<450; i++) g_history[i] = g_history[i+50];
      g_histCount = 450;
   }
   
   g_history[g_histCount].hour        = hour;
   g_history[g_histCount].sl_dist     = sl_dist;
   g_history[g_histCount].profit      = profit;
   g_history[g_histCount].hold_sec    = hold_sec;
   g_history[g_histCount].is_win      = (profit > 0);
   g_history[g_histCount].is_quick_loss = (profit < -0.5 && hold_sec < Learn_Quick_Loss_Sec);
   g_histCount++;
   g_totalTrades++;
   
   // Actualizar HourStats
   g_hourStats[hour].n++;
   g_hourStats[hour].total_profit += profit;
   if(profit > 0) g_hourStats[hour].wins++;
   
   // Recalcular WR y decidir si bloquear
   if(g_hourStats[hour].n >= Learn_Min_Samples){
      double wr = (double)g_hourStats[hour].wins / g_hourStats[hour].n;
      if(!g_hourStats[hour].blocked && wr < Learn_WR_Block){
         g_hourStats[hour].blocked = true;
         g_hourStats[hour].block_samples = 0;
         Print("LEARN: Hora ",hour," BLOQUEADA (WR=",DoubleToString(wr*100,1),"% < ",Learn_WR_Block*100,"%)");
      } else if(g_hourStats[hour].blocked){
         g_hourStats[hour].block_samples++;
         if(wr >= Learn_WR_Reopen){
            g_hourStats[hour].blocked = false;
            Print("LEARN: Hora ",hour," REABIERTA (WR=",DoubleToString(wr*100,1),"% >= ",Learn_WR_Reopen*100,"%)");
         }
      }
   }
   
   // Recalcular parámetros adaptativos cada N trades
   if(g_totalTrades % Learn_Recalc_Every == 0) AdaptParameters();
}

//+------------------------------------------------------------------+
// Adapta parámetros basándose en el historial
void AdaptParameters()
{
   if(g_histCount < 10) return;
   
   int look = MathMin(g_histCount, 50); // últimos 50 trades
   
   // 1. ADAPTAR VELOCIDAD: si hay muchos quick_losses → endurecer filtro vel
   int quick_losses = 0;
   for(int i=g_histCount-look; i<g_histCount; i++)
      if(g_history[i].is_quick_loss) quick_losses++;
   double quick_ratio = (double)quick_losses / look;
   
   if(quick_ratio > 0.20) { // >20% de trades son quick_losses
      g_vel_threshold = MathMin(Vel_Threshold_Base * 0.85, Vel_Threshold_Base);
      Print("LEARN: Vel_Threshold endurecido a ",DoubleToString(g_vel_threshold,2),
            " (quick_loss_ratio=",DoubleToString(quick_ratio*100,1),"%)");
   } else if(quick_ratio < 0.05) { // <5% → relajar un poco
      g_vel_threshold = MathMin(Vel_Threshold_Base * 1.10, Vel_Threshold_Base * 1.20);
   } else {
      g_vel_threshold = Vel_Threshold_Base;
   }
   
   // 2. ADAPTAR TRAIL: medir volatilidad reciente del mercado
   double vol_sum = 0;
   for(int i=1; i<=Learn_Vol_Window; i++){
      double h = iHigh(g_sym,_Period,i), l = iLow(g_sym,_Period,i);
      if(h>0 && l>0) vol_sum += (h-l);
   }
   double avg_bar_range = vol_sum / Learn_Vol_Window;
   
   // Si barras son muy volátiles (>5pts promedio) → ampliar trail
   // Si barras tranquilas (<2pts) → ajustar trail más
   double vol_factor = 1.0;
   if(avg_bar_range > 5.0)      vol_factor = 1.0 + Learn_Trail_Scale;
   else if(avg_bar_range < 2.0) vol_factor = 1.0 - Learn_Trail_Scale * 0.5;
   g_trail_dist = Trail_Distance_Base * vol_factor;
   g_trail_dist = MathMax(g_trail_dist, 5.0);
   g_trail_dist = MathMin(g_trail_dist, 25.0);
   
   // 3. ADAPTAR ZONA: analizar si señales más extremas (precio más arriba del top)
   // ganan más. Si wins tienen sl_dist más pequeño → señales precisas son mejores
   double win_sl_avg = 0, loss_sl_avg = 0;
   int wn = 0, ln = 0;
   for(int i=g_histCount-look; i<g_histCount; i++){
      if(g_history[i].is_win){ win_sl_avg += g_history[i].sl_dist; wn++; }
      else { loss_sl_avg += g_history[i].sl_dist; ln++; }
   }
   // (Este análisis se podría expandir en futuras versiones)
   
   Print("LEARN Adapt: vel=",DoubleToString(g_vel_threshold,2),
         " trail=",DoubleToString(g_trail_dist,2),"pts",
         " vol=",DoubleToString(avg_bar_range,2),"pts/barra",
         " quick_loss%=",DoubleToString(quick_ratio*100,1),"%");
}

//+------------------------------------------------------------------+
// Actualiza la escala de lot según racha de wins/losses
void UpdateStreakScale(bool is_win)
{
   if(is_win){
      g_consecWins++;
      g_consecLosses = 0;
      if(g_consecWins >= Streak_Win_Trigger){
         g_lot_scale = MathMin(g_lot_scale * Streak_Boost_Pct, 1.5);
         Print("STREAK WIN×",g_consecWins," → lot_scale=",DoubleToString(g_lot_scale,2));
      }
   } else {
      g_consecLosses++;
      g_consecWins = 0;
      if(g_consecLosses >= Streak_Loss_Trigger){
         g_lot_scale = MathMax(g_lot_scale * Streak_Reduce_Pct, 0.25);
         Print("STREAK LOSS×",g_consecLosses," → lot_scale=",DoubleToString(g_lot_scale,2));
      }
      // Reset parcial en racha muy larga
      if(g_consecLosses >= Max_Consec_Losses){
         g_pauseBarsLeft = Pause_Bars;
         g_pendingDir = 0;
         g_lot_scale = MathMax(g_lot_scale, 0.25); // no bajar de 25%
         Print("MM7 PAUSA tras ",g_consecLosses," SLs");
      }
   }
}

//+------------------------------------------------------------------+
// Todas las horas activas — autoaprendizaje bloquea las malas rápido
// Con Learn_Min_Samples=3: H7(WR=33%) se bloquea tras solo 3 trades
// Con Learn_Min_Samples=3: H22(WR=29%) se bloquea aún más rápido
bool IsGoodHour(int hour)
{
   if(!Use_Hour_Filter) return true;
   // Horas base: todas las históricamente activas
   bool base_ok = (hour==2||hour==7||hour==15||hour==19||hour==22);
   if(!base_ok) return false;
   // Autoaprendizaje bloquea si WR<35% con ≥3 muestras
   if(g_hourStats[hour].blocked){
      if(g_hourStats[hour].n >= Learn_Min_Samples) return false;
   }
   // Bloqueo diario: parar si el día ya acumuló demasiadas pérdidas
   if(g_dayBlocked) return false;
   return true;
}

//+------------------------------------------------------------------+
// Detector de día tendencial — bloquea tras 2 pérdidas (no 3)
void UpdateDayTracking(double profit)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",dt.year,dt.mon,dt.day));
   if(g_currentDay != today){
      g_currentDay   = today;
      g_dayLossCount = 0;
      g_dayPnL       = 0;
      g_dayBlocked   = false;
   }
   g_dayPnL += profit;
   if(profit < -0.5){
      g_dayLossCount++;
      // AJUSTADO: bloquear tras 2 pérdidas (simulación: +$269 vs +$244 sin bloqueo)
      if(g_dayLossCount >= 2 && !g_dayBlocked){
         g_dayBlocked = true;
         g_pendingDir = 0;
         Print("MM7 DIA BLOQUEADO tras 2 losses: PnL=$",DoubleToString(g_dayPnL,2));
      }
   }
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
   if(!Use_Risk_Based_Lot) return NormalizeDouble(Min_Lot,2);
   double bal = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                        AccountInfoDouble(ACCOUNT_EQUITY));
   double cap_usd = bal * Cap_Pct_Of_Balance;
   double risk    = MathMin(bal * Risk_Pct_Per_Trade, cap_usd);
   if(sl_dist <= 0) sl_dist = SL_Min;
   double lot = (risk / (sl_dist * 100.0)) * g_lot_scale;
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

ulong GetTickets(ulong &arr[])
{
   int cnt=0; ArrayResize(arr,0);
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
      Print("MM7 SELL bid=",bid," SL=",sl," TP=",tp," lot=",lot,
            " trail_dist=",DoubleToString(g_trail_dist,2),
            " vel_thr=",DoubleToString(g_vel_threshold,2),
            " lot_scale=",DoubleToString(g_lot_scale,2));
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
   double profit  = HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   string comment = HistoryDealGetString(trans.deal,DEAL_COMMENT);
   if(StringFind(comment,"partial")>=0) return;
   
   // Buscar el trade en estados abiertos para obtener metadata
   datetime open_t = (datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   double   close_price = HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   
   // Registrar en memoria de aprendizaje
   MqlDateTime dt; TimeToStruct(open_t, dt);
   // Buscar sl_dist del trade (aproximar desde profit y vol)
   double vol = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double hold_sec = 0;
   // Buscar en states
   for(int i=0;i<2;i++){
      if(g_states[i].entry>0){
         hold_sec = (double)(open_t - g_states[i].openTime);
         RecordTrade(dt.hour, g_states[i].slDist, profit, hold_sec);
         break;
      }
   }
   if(hold_sec == 0) RecordTrade(dt.hour, SL_Min, profit, 0);
   
   // Actualizar racha
   bool is_win = (profit > 0);
   UpdateStreakScale(is_win);
   
   // MEJORA 2: actualizar tracking diario
   UpdateDayTracking(profit);
   
   // Limpiar estado
   for(int i=0;i<2;i++){
      if(g_states[i].entry>0){
         g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
         g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
         g_states[i].timeTrailDone=false; g_states[i].openTime=0;
         break;
      }
   }
}

int OnInit()
{
   g_sym=_Symbol; g_magic=InpMagicNumber;
   g_point=SymbolInfoDouble(g_sym,SYMBOL_POINT);
   if(g_point<=0){Alert("Invalid SYMBOL_POINT");return INIT_FAILED;}
   InitLearning();
   for(int i=0;i<2;i++){
      g_states[i].entry=0; g_states[i].slDist=0; g_states[i].tpDist=0;
      g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
      g_states[i].timeTrailDone=false; g_states[i].openTime=0;
   }
   Print("MM7 v17.71 | ",g_sym,
         " | Horas:2,7,15,19,22 (autoaprendizaje bloquea malas con 3 muestras)",
         " | DayBlock tras 2 losses",
         " | Trail start=",Trail_Start_Pts,"pts dist=",Trail_Distance_Base,"pts");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   double bid=SymbolInfoDouble(g_sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(g_sym,SYMBOL_ASK);
   datetime now=TimeCurrent();

   if(Close_On_FriClose&&IsFridayClose()){
      ulong tks[]; GetTickets(tks);
      for(int i=0;i<ArraySize(tks);i++) ClosePosition(tks[i],"FriClose");
      g_pendingDir=0; return;
   }

   // GESTIÓN POSICIONES ABIERTAS
   ulong tks[]; int npos=GetTickets(tks);
   for(int pi=0;pi<npos;pi++){
      ulong tk=tks[pi];
      if(!PositionSelectByTicket(tk)) continue;
      double entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double favorable= entry - ask;
      int si=-1;
      for(int i=0;i<2;i++){
         if(MathAbs(g_states[i].entry-entry)<0.01&&g_states[i].entry>0){si=i;break;}
      }
      if(si<0){
         for(int i=0;i<2;i++){
            if(g_states[i].entry==0){si=i;break;}
         }
         if(si<0) continue;
         g_states[si].entry=entry;
         g_states[si].slDist=MathAbs(curSL-entry);
         g_states[si].tpDist=g_states[si].slDist*TP_Ratio;
         g_states[si].openTime=now;
         g_states[si].trailActive=false;
         g_states[si].beMovedOnce=false;
         g_states[si].timeTrailDone=false;
      }
      double slD=g_states[si].slDist;

      // Trail con distancia ADAPTATIVA (aprende del mercado)
      if(Use_Trail && favorable>=Trail_Start_Pts){
         double newSL=ask+g_trail_dist; // usa trail_dist aprendido
         if(PositionSelectByTicket(tk)){
            double csl=PositionGetDouble(POSITION_SL),ctp=PositionGetDouble(POSITION_TP);
            int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
            newSL=NormalizeDouble(newSL,digs);
            if(newSL<csl){
               MqlTradeRequest rr={}; MqlTradeResult rs={};
               rr.action=TRADE_ACTION_SLTP; rr.symbol=g_sym;
               rr.position=tk; rr.sl=newSL; rr.tp=ctp;
               OrderSend(rr,rs);
            }
         }
         if(!g_states[si].trailActive) g_states[si].trailActive=true;
      }

      if(Use_Breakeven&&!g_states[si].beMovedOnce&&!g_states[si].trailActive&&slD>0){
         if(favorable>=slD*BE_Trigger_Pct){
            if(PositionSelectByTicket(tk)){
               double csl=PositionGetDouble(POSITION_SL),ctp=PositionGetDouble(POSITION_TP);
               int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
               double nsl=NormalizeDouble(entry,digs);
               if(nsl<csl){MqlTradeRequest rr={}; MqlTradeResult rs={};
                  rr.action=TRADE_ACTION_SLTP; rr.symbol=g_sym;
                  rr.position=tk; rr.sl=nsl; rr.tp=ctp; OrderSend(rr,rs);}
            }
            g_states[si].beMovedOnce=true;
         }
      }

      if(Use_Time_Trail&&!g_states[si].timeTrailDone&&g_states[si].openTime>0){
         if((now-g_states[si].openTime)>=Time_Trail_Sec){
            if(favorable<slD*Trail_Progress_Pct){
               if(PositionSelectByTicket(tk)){
                  double csl=PositionGetDouble(POSITION_SL),ctp=PositionGetDouble(POSITION_TP);
                  int digs=(int)SymbolInfoInteger(g_sym,SYMBOL_DIGITS);
                  double nsl=NormalizeDouble(entry,digs);
                  if(nsl<csl){MqlTradeRequest rr={}; MqlTradeResult rs={};
                     rr.action=TRADE_ACTION_SLTP; rr.symbol=g_sym;
                     rr.position=tk; rr.sl=nsl; rr.tp=ctp; OrderSend(rr,rs);}
               }
            }
            g_states[si].timeTrailDone=true;
         }
      }
   }

   // Limpiar estados cerrados
   npos=GetTickets(tks);
   for(int i=0;i<2;i++){
      if(g_states[i].entry==0) continue;
      bool found=false;
      for(int pi=0;pi<ArraySize(tks);pi++){
         if(PositionSelectByTicket(tks[pi]))
            if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN)-g_states[i].entry)<0.01){found=true;break;}
      }
      if(!found){
         g_states[i].entry=0; g_states[i].slDist=0;
         g_states[i].trailActive=false; g_states[i].beMovedOnce=false;
         g_states[i].timeTrailDone=false; g_states[i].openTime=0;
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

      // Filtro velocidad ADAPTATIVO (aprende del historial)
      double cv2=iClose(g_sym,_Period,Vel_Bars+1), cn2=iClose(g_sym,_Period,1);
      if(cv2>0&&cn2>0&&MathAbs(cn2-cv2)/Vel_Bars>g_vel_threshold) return;

      // Rango señal
      double rH=-DBL_MAX, rL=DBL_MAX;
      for(int i=1;i<=Range_Bars;i++){
         double h=iHigh(g_sym,_Period,i), l=iLow(g_sym,_Period,i);
         if(h==0||l==0) return;
         if(h>rH) rH=h; if(l<rL) rL=l;
      }
      double range=rH-rL; if(range<=0) return;
      double closeNow=iClose(g_sym,_Period,1); if(closeNow==0) return;
      double upperZone=rH-range*g_zone_pct; // zona ADAPTATIVA

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
   MqlDateTime dt; TimeToStruct(now,dt);
   if(!IsGoodHour(dt.hour)){g_pendingDir=0;return;}
   if(dt.day_of_week==5&&dt.hour>=FriClose_Hour_UTC){g_pendingDir=0;return;}

   if(g_pendingDir==-1 && ask<=g_confirmLevel)
      OpenSell(g_pendingSL);
}
//+------------------------------------------------------------------+
