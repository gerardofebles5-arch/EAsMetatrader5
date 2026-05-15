//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Sistema de Votacion v5.0 MEAN REVERSION     |
//|  Ref: Chan "Algorithmic Trading" cap.3                         |
//|  Logica: 2/3 osciladores en zona extrema = señal               |
//+------------------------------------------------------------------+
#ifndef MH7_VOTING_MQH
#define MH7_VOTING_MQH
#include "MH7_Structures.mqh"
#include "MH7_Engines.mqh"

VotingResult GenerateSignal(string symbol,
                             const SymbolConfig &cfg,
                             const MLModelParams &ml)
{
   VotingResult result;
   result.direction        = 0;
   result.quality_score    = 0.0;
   result.voting_details   = "";
   result.threshold_passed = false;

   // ---- 3 osciladores de mean reversion ----
   double bb_score    = MotorA_ValueScore(symbol, cfg.structure_lookback_bars, cfg.h_ma200_d1);
   double rsi_score   = MotorB_MomentumScore(symbol, cfg.momentum_bars);
   double stoch_score = MotorC_MLScore(symbol, ml,
                           cfg.h_atr_m15, cfg.h_rsi_m15,
                           cfg.h_ma50_m15, cfg.h_ma200_m15);

   // Zona extrema: score > 60 = BUY zone, score < 40 = SELL zone
   bool bb_buy    = (bb_score    > 60.0);
   bool bb_sell   = (bb_score    < 40.0);
   bool rsi_buy   = (rsi_score   > 60.0);
   bool rsi_sell  = (rsi_score   < 40.0);
   bool stoch_buy = (stoch_score > 60.0);
   bool stoch_sell= (stoch_score < 40.0);

   int buy_votes  = (bb_buy  ? 1 : 0) + (rsi_buy  ? 1 : 0) + (stoch_buy  ? 1 : 0);
   int sell_votes = (bb_sell ? 1 : 0) + (rsi_sell ? 1 : 0) + (stoch_sell ? 1 : 0);

   // Minimo 2/3 en acuerdo
   if(buy_votes >= 2 && buy_votes > sell_votes)
   {
      result.direction = +1;
      double sum = 0; int cnt = 0;
      if(bb_buy)    { sum += bb_score;    cnt++; }
      if(rsi_buy)   { sum += rsi_score;   cnt++; }
      if(stoch_buy) { sum += stoch_score; cnt++; }
      result.quality_score = (cnt > 0) ? sum / cnt : 65.0;
      result.voting_details = StringFormat(
         "MR-BUY %d/3 | BB=%.1f RSI=%.1f STOCH=%.1f | Q=%.1f",
         buy_votes, bb_score, rsi_score, stoch_score, result.quality_score);
   }
   else if(sell_votes >= 2 && sell_votes > buy_votes)
   {
      result.direction = -1;
      double sum = 0; int cnt = 0;
      if(bb_sell)    { sum += (100.0 - bb_score);    cnt++; }
      if(rsi_sell)   { sum += (100.0 - rsi_score);   cnt++; }
      if(stoch_sell) { sum += (100.0 - stoch_score); cnt++; }
      result.quality_score = (cnt > 0) ? sum / cnt : 65.0;
      result.voting_details = StringFormat(
         "MR-SELL %d/3 | BB=%.1f RSI=%.1f STOCH=%.1f | Q=%.1f",
         sell_votes, bb_score, rsi_score, stoch_score, result.quality_score);
   }
   else
   {
      result.voting_details = StringFormat(
         "NEUTRAL | BB=%.1f RSI=%.1f STOCH=%.1f | BUY=%d SELL=%d",
         bb_score, rsi_score, stoch_score, buy_votes, sell_votes);
      return result;
   }

   if(result.quality_score >= cfg.signal_quality_threshold)
      result.threshold_passed = true;
   else
   {
      result.direction = 0;
      result.voting_details += StringFormat(" | REJECTED Q=%.1f < %.1f",
                                             result.quality_score,
                                             cfg.signal_quality_threshold);
   }

   return result;
}

void FillSignalState(SignalState &sig,
                     const VotingResult &vote,
                     double v_score,
                     double m_score,
                     double ml_score)
{
   sig.value_score    = v_score;
   sig.momentum_score = m_score;
   sig.ml_score       = ml_score;
   sig.final_quality  = vote.quality_score;
   sig.direction      = vote.direction;
   sig.buy_votes      = (vote.direction == +1) ? 2 : 0;
   sig.sell_votes     = (vote.direction == -1) ? 2 : 0;
   sig.signal_time    = TimeCurrent();
   sig.reason         = vote.voting_details;
   sig.quality_passed = vote.threshold_passed;
}

#endif // MH7_VOTING_MQH
