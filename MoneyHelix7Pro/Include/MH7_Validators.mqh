//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Validadores Pre-Trade TIER RESTORE          |
//+------------------------------------------------------------------+
#ifndef MH7_VALIDATORS_MQH
#define MH7_VALIDATORS_MQH
#include "MH7_Structures.mqh"

bool ValidateSession(const SymbolConfig &cfg)
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   if(h == 22) return false;
   if(h == 0 && dt.min < 5) return false;
   bool in_ny = (h >= 13 && h <= 21);
   bool in_eu = (h >= 8  && h <= 16);
   return (cfg.trading_in_ny_session && in_ny) ||
          (cfg.trading_in_eu_session  && in_eu);
}

bool ValidateVolatility(string symbol, const SymbolConfig &cfg)
{
   if(cfg.h_atr_m15 == INVALID_HANDLE) return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(cfg.h_atr_m15, 0, 0, 25, buf) < 20) return false;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0) return false;
   double atr_now = buf[0] / point;
   if(atr_now < cfg.min_volatility_atr) return false;
   double sum = 0;
   for(int i = 1; i < 21; i++) sum += buf[i];
   double avg = sum / 20.0;
   if(avg > 0 && ((buf[0] - avg) / (avg * 0.5)) > 4.0) return false;
   return true;
}

bool ValidateDrawdown(SystemState &sys, double &dd_adj)
{
   dd_adj = 1.0;
   if(sys.circuit_breaker_active)
   {
      if(TimeCurrent() < sys.circuit_breaker_until) return false;
      sys.circuit_breaker_active = false;
      sys.is_trading_allowed     = true;
      sys.account_dd_peak        = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("Circuit breaker OFF - trading resumed");
   }
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(equity > sys.account_dd_peak) sys.account_dd_peak = equity;
   double dd_pct = (sys.account_dd_peak > 0) ?
                   (sys.account_dd_peak - equity) / sys.account_dd_peak * 100.0 : 0.0;
   if(dd_pct >= sys.max_total_dd_pct)
   {
      sys.circuit_breaker_active = true;
      sys.is_trading_allowed     = false;
      sys.circuit_breaker_until  = TimeCurrent() + 86400;
      Alert(StringFormat("CIRCUIT BREAKER: DD=%.1f%% TRADING STOPPED 24h", dd_pct));
      return false;
   }
   if(MathAbs(sys.daily_loss_accumulated) >= balance * sys.max_daily_loss_pct / 100.0)
      return false;
   if(dd_pct >= sys.soft_dd_pct) dd_adj = 0.50;
   return true;
}

bool ValidateLosingStreak(const PerformanceMetrics &metrics)
{
   // Mean reversion: alta WR esperada, permitir hasta 5 losses consecutivos
   return (metrics.consecutive_losses < 5);
}

bool ValidateNewsFilter(SystemState &sys)
{
   if(!sys.news_filter_active) return true;
   if(TimeCurrent() < sys.news_block_until) return false;
   sys.news_filter_active = false;
   return true;
}

bool RunAllValidators(string symbol,
                      const SymbolConfig &cfg,
                      SystemState &sys,
                      PerformanceMetrics &metrics,
                      double &dd_adj,
                      int signal_direction = 0)
{
   dd_adj = 1.0;
   if(!ValidateSession(cfg))            return false;
   if(!ValidateVolatility(symbol, cfg)) return false;
   if(!ValidateDrawdown(sys, dd_adj))   return false;
   if(!ValidateLosingStreak(metrics))   return false;
   if(!ValidateNewsFilter(sys))         return false;

   // FILTRO DE REGIMEN: Mean reversion solo en mercado ranging
   // Ref: Chan "Algorithmic Trading" cap.2 - ADX como detector de regimen
   // ADX < 25: mercado ranging → mean reversion funciona → operar
   // ADX 25-35: transicion → reducir size 50%
   // ADX > 35: tendencia fuerte → mean reversion falla → no operar
   int adx_h = iADX(symbol, PERIOD_M15, 14);
   if(adx_h != INVALID_HANDLE)
   {
      double adx_buf[];
      ArraySetAsSeries(adx_buf, true);
      if(CopyBuffer(adx_h, 0, 0, 3, adx_buf) >= 1)
      {
         double adx = adx_buf[0];
         IndicatorRelease(adx_h);
         if(adx > 35.0)
         {
            // Tendencia fuerte: mean reversion no aplica
            return false;
         }
         if(adx > 25.0)
         {
            // Zona de transicion: reducir size
            dd_adj *= 0.50;
         }
         // ADX < 25: ranging, operar a tamaño completo
      }
      else
         IndicatorRelease(adx_h);
   }

   return true;
}

void DailyReset(SystemState &sys, PerformanceMetrics &metrics)
{
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(sys.last_daily_reset, last);
   if(now.day != last.day)
   {
      metrics.daily_pnl          = 0.0;
      sys.daily_loss_accumulated = 0.0;
      sys.last_daily_reset       = TimeCurrent();
      Print("Daily reset");
   }
}

#endif // MH7_VALIDATORS_MQH
