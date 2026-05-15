#ifndef MM7_CORE_STRATEGYMANAGER_MQH
#define MM7_CORE_STRATEGYMANAGER_MQH

//+------------------------------------------------------------------+
//|                                            StrategyManager.mqh  |
//|         MoneyMachine7 — Strategy Orchestrator                    |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"
#include "MM7/Strategies/SMCStrategy.mqh"
#include "MM7/Strategies/GridStrategy.mqh"
#include "MM7/Strategies/BreakoutStrategy.mqh"
#include "MM7/Strategies/StopHuntStrategy.mqh"

class CStrategyManager
{
private:
   CSMCStrategy*       m_smc;
   CGridStrategy*      m_grid;
   CBreakoutStrategy*  m_breakout;
   CStopHuntStrategy*  m_stopHunt;
   bool                m_enableBreakout;
   bool                m_enableStopHunt;

public:
   CStrategyManager() : m_smc(NULL), m_grid(NULL), m_breakout(NULL),
                        m_stopHunt(NULL), m_enableBreakout(true), m_enableStopHunt(true) {}

   bool Initialize(CSMCStrategy* smc, CGridStrategy* grid,
                   CBreakoutStrategy* breakout, CStopHuntStrategy* stopHunt,
                   bool enableBreakout, bool enableStopHunt)
   {
      m_smc           = smc;
      m_grid          = grid;
      m_breakout      = breakout;
      m_stopHunt      = stopHunt;
      m_enableBreakout= enableBreakout;
      m_enableStopHunt= enableStopHunt;
      return true;
   }

   //--- Get combined signal from all enabled strategies
   SignalResult GetCombinedSignal()
   {
      SignalResult best; best.direction = DIR_NONE; best.strength = 0;

      // Stop Hunt has highest priority
      if(m_enableStopHunt && m_stopHunt != NULL)
      {
         SignalResult sig = m_stopHunt.GetSignal();
         if(sig.strength > best.strength) best = sig;
      }

      // SMC signal
      if(m_smc != NULL)
      {
         SignalResult sig = m_smc.GetSignal();
         if(sig.strength > best.strength) best = sig;
      }

      // Breakout signal
      if(m_enableBreakout && m_breakout != NULL)
      {
         SignalResult sig = m_breakout.GetSignal();
         if(sig.strength > best.strength) best = sig;
      }

      return best;
   }
};


#endif // MM7_CORE_STRATEGYMANAGER_MQH
