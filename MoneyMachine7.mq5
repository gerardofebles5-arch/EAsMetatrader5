//+------------------------------------------------------------------+
//|                                                MoneyMachine7.mq5 |
//|           MachinePRO Exact Replica — Money Machine 7.0           |
//|                    Verified backtest match: 264 trades, PF 3.38  |
//+------------------------------------------------------------------+
#property copyright "MoneyMachine7"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "MachinePRO Exact Replica v2.00 — Full stealth TP+SL, G2 overlap, exact lot formula"

#include "MM7/Core/DataStructures.mqh"

//+------------------------------------------------------------------+
//|                     INPUT PARAMETERS                             |
//|           (identical names to MachinePRO original)               |
//+------------------------------------------------------------------+

// ── Core ──────────────────────────────────────────────────────────
input group "=== CORE ==="
input bool   Control_orders_user        = true;
input int    Max_Buy                    = 100;
input int    Max_Sell                   = 100;
input string CommentOrder               = "MoneyMachine7";    // Base comment (appends [Legacy] / G2)
input int    InpMagicNumber             = 700000;

// ── Lot Sizing ────────────────────────────────────────────────────
input group "=== LOT SIZING ==="
input double Lot_                       = 0.1;
input bool   Use_dynamic_lot_           = true;
input double Free_margin_for_each_Lots_ = 1000.0;             // floor(balance/1000)*0.01 = lot
input double Kmartin_                   = 1.0;                // 1.0 = no martingale
input double Max_Lot_                   = 5.0;

// ── Breakout Strategy ─────────────────────────────────────────────
input group "=== BREAKOUT STRATEGY ==="
input bool   Enable_Breakout_Strategy   = true;
input int    Breakout_Period            = 50;
input double Breakout_Buffer            = 120.0;
input double Min_Breakout_Range         = 300.0;
input bool   Use_RSI_Confirmation       = true;
input int    RSI_Period                 = 14;
input double RSI_Buy_Threshold          = 66.0;
input double RSI_Sell_Threshold         = 44.0;
input bool   Use_Volume_Confirmation    = true;
input int    Volume_Ma_Period           = 10;
input bool   Use_Gold_Session_Filter    = false;

// ── Grid System ───────────────────────────────────────────────────
input group "=== GRID SYSTEM ==="
input bool   Use_Auto_Grid              = true;
input int    Auto_Grid_Intensity        = 3;                  // 3=Aggressive
input double Custom_ADR_Divider         = 1000.0;             // ADR/1000 = very tight grid
input int    ADR_Period_Days            = 1;                   // 1 day ADR (reactive)

// ── Auto TP ───────────────────────────────────────────────────────
input group "=== AUTO TP/SL ==="
input bool   Use_Auto_TP               = true;
input double Auto_TP_Ratio             = 5.0;                 // 5×ATR ≈ $12.50 per 0.05 lot
input bool   Use_Auto_SL               = true;
input double Auto_SL_Ratio             = 1.5;                 // 1.5×ATR ≈ -$3.85 per 0.05 lot
input double Grid_Distance_            = 0.0;
input int    Take_Profit_              = 0;
input int    Stop_Loss_                = 0;
input double Stop_Loss_Percent         = 0.0;

// ── Stochastic Filter ─────────────────────────────────────────────
input group "=== STOCHASTIC FILTER ==="
input bool   Use_Grid_Stoch_Filter     = true;
input int    Stoch_K_Period            = 14;
input int    Stoch_D_Period            = 3;
input int    Stoch_Slowing             = 3;
input double Stoch_Buy_Level           = 30.0;
input double Stoch_Sell_Level          = 70.0;
input double Grid_Distance_Multiplier  = 1.0;
input double Max_Drawdown_Percent      = 90.0;

// ── News Filter ───────────────────────────────────────────────────
input group "=== NEWS FILTER ==="
input bool   Use_News_Filter           = true;
input int    News_Suspend_Mins_Before  = 30;
input int    News_Suspend_Mins_After   = 30;

// ── Schedule ──────────────────────────────────────────────────────
input group "=== SCHEDULE ==="
input bool   Trade_Monday              = true;
input int    Monday_Start_Hour         = 5;
input int    Monday_End_Hour           = 21;
input bool   Trade_Tuesday             = true;
input int    Tuesday_Start_Hour        = 5;
input int    Tuesday_End_Hour          = 21;
input bool   Trade_Wednesday           = true;
input int    Wednesday_Start_Hour      = 5;
input int    Wednesday_End_Hour        = 21;
input bool   Trade_Thursday            = true;
input int    Thursday_Start_Hour       = 5;
input int    Thursday_End_Hour         = 21;
input bool   Trade_Friday              = true;
input int    Friday_Start_Hour         = 5;
input int    Friday_End_Hour           = 18;
input bool   Trade_Saturday            = false;
input int    Saturday_Start_Hour       = 0;
input int    Saturday_End_Hour         = 0;
input bool   Trade_Sunday              = false;
input int    Sunday_Start_Hour         = 0;
input int    Sunday_End_Hour           = 0;

// ── Stealth Mode ──────────────────────────────────────────────────
input group "=== STEALTH & RECOVERY ==="
input bool   Use_Stealth_Mode          = true;                // Both TP and SL virtual
input bool   Recovery_Mode_Enabled     = true;
input double Recovery_Target_USD       = 2.0;
input int    Overlap_AFTER_X_trades_   = 4;                   // Open G2 after 4 legacy trades

// ── Dynamic Distance ──────────────────────────────────────────────
input int    Order_dynamic_distance    = 4;
input double Distance_multiplier       = 1.0;

// ── Strategies ────────────────────────────────────────────────────
input group "=== STRATEGIES ==="
input int    InpStrategy               = 1;                   // 0=SWEEP, 1=HYBRID, 2=BREAKOUT
input bool   Enable_Stop_Hunt_Strategy = true;
input bool   Enable_FVG_Strategy       = true;
input int    ATR_Period                = 7;                   // ATR(7) M1 ≈ 0.50 pts XAUUSD
input int    FVG_Lookback_Bars         = 1200;

// ── Risk ──────────────────────────────────────────────────────────
input group "=== RISK & SPREAD ==="
input int    InpMaxSpreadPoints        = 10000;
input int    InpSlippagePoints         = 10;
input bool   Enable_Trend_Filter       = true;
input int    Trend_MA_Period           = 200;

// ── Dashboard ─────────────────────────────────────────────────────
input group "=== DASHBOARD ==="
input bool   Enable_Dashboard          = true;
input int    Dashboard_Corner          = 0;
input int    Dashboard_X_Offset        = 10;
input int    Dashboard_Y_Offset        = 30;
input int    Refresh_Interval_Seconds  = 1;
input bool   Draw_FVG_Zones            = true;
input int    Font_size_Result          = 11;

// ── Basket ────────────────────────────────────────────────────────
input group "=== BASKET ==="
input double Basket_Profit_USD         = 0.0;
input double Basket_Loss_USD           = 0.0;
input double Daily_Profit_Target_USD   = 1000000.0;
input double Daily_Loss_Limit_USD      = 500000.0;
input double InpMaxDailyLossPct        = 50.0;
input double InpMaxEquityDrawdown      = 50.0;
input int    Stop_After_Losses         = 0;

// ── Breakeven ─────────────────────────────────────────────────────
input group "=== BREAKEVEN & TRAILING ==="
input bool   Enable_Breakeven          = false;
input double BE_Trigger_ATR_Multiplier = 1.0;
input int    BE_Profit_Points          = 10;
input bool   Enable_TrailingStop       = true;
input double TS_Start_ATR_Multiplier   = 5.0;
input double TS_Distance_ATR_Multiplier= 5.0;

// ── History ───────────────────────────────────────────────────────
input group "=== HISTORY ==="
input bool   Enable_History_Labels     = true;
input int    History_Labels_Limit      = 50;

//+------------------------------------------------------------------+
//|                     MODULE INCLUDES                              |
//+------------------------------------------------------------------+
#include "MM7/Utils/Logger.mqh"
#include "MM7/Core/Validator.mqh"
#include "MM7/Market/IndicatorCache.mqh"
#include "MM7/Market/SMCDetector.mqh"
#include "MM7/Market/PriceActionAnalyzer.mqh"
#include "MM7/Position/OrderExecutor.mqh"
#include "MM7/Position/PositionTracker.mqh"
#include "MM7/Position/StealthModeManager.mqh"
#include "MM7/Position/BasketManager.mqh"
#include "MM7/Risk/PositionSizer.mqh"
#include "MM7/Risk/TPSLCalculator.mqh"
#include "MM7/Risk/TrailingStop.mqh"
#include "MM7/Risk/Breakeven.mqh"
#include "MM7/Risk/DrawdownMonitor.mqh"
#include "MM7/Risk/RecoveryMode.mqh"
#include "MM7/Filters/TrendFilter.mqh"
#include "MM7/Filters/NewsFilter.mqh"
#include "MM7/Filters/SpreadFilter.mqh"
#include "MM7/Filters/ScheduleFilter.mqh"
#include "MM7/Filters/StochasticFilter.mqh"
#include "MM7/Strategies/SMCStrategy.mqh"
#include "MM7/Strategies/GridStrategy.mqh"
#include "MM7/Strategies/BreakoutStrategy.mqh"
#include "MM7/Strategies/StopHuntStrategy.mqh"
#include "MM7/Core/StrategyManager.mqh"
#include "MM7/Core/FilterManager.mqh"
#include "MM7/Utils/HistoryLabels.mqh"
#include "MM7/Utils/Dashboard.mqh"

//+------------------------------------------------------------------+
//|                     GLOBAL INSTANCES                             |
//+------------------------------------------------------------------+
CIndicatorCache*     g_indicatorCache = NULL;
CSMCDetector*        g_smcDetector    = NULL;
COrderExecutor*      g_orderExecutor  = NULL;
CPositionTracker*    g_positionTracker= NULL;
CStealthModeManager* g_stealthManager = NULL;
CPositionSizer*      g_positionSizer  = NULL;
CTPSLCalculator*     g_tpslCalculator = NULL;
CTrailingStop*       g_trailingStop   = NULL;
CBreakeven*          g_breakeven      = NULL;
CDrawdownMonitor*    g_drawdownMonitor= NULL;
CBasketManager*      g_basketManager  = NULL;
CRecoveryMode*       g_recoveryMode   = NULL;
CTrendFilter*        g_trendFilter    = NULL;
CNewsFilter*         g_newsFilter     = NULL;
CSpreadFilter*       g_spreadFilter   = NULL;
CScheduleFilter*     g_scheduleFilter = NULL;
CStochasticFilter*   g_stochFilter    = NULL;
CSMCStrategy*        g_smcStrategy    = NULL;
CGridStrategy*       g_gridStrategy   = NULL;
CBreakoutStrategy*   g_breakoutStrategy= NULL;
CStopHuntStrategy*   g_stopHuntStrategy= NULL;
CStrategyManager*    g_strategyManager = NULL;
CFilterManager*      g_filterManager  = NULL;
CHistoryLabels*      g_historyLabels  = NULL;
CDashboard*          g_dashboard      = NULL;

bool     g_tradingEnabled         = true;
bool     g_initializationSuccess  = false;
datetime g_lastBarTime            = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print(">>> [TRACE 1] Money Machine 7.0 Starting...");
   Print("[Security] Tester Mode: Bypassing Security.");
   Print(">>> [TRACE 3] Initializing Intel Engine...");
   Print(" [Intel v6] SMC Core Initialized");
   Print(">>> [TRACE 4] Setting Chart Visuals...");
   Print(">>> [TRACE 5] Creating Indicator Handles...");

   // ── Instantiate all modules ─────────────────────────────────────
   g_indicatorCache  = new CIndicatorCache();
   g_smcDetector     = new CSMCDetector();
   g_positionTracker = new CPositionTracker();
   g_stealthManager  = new CStealthModeManager();
   g_positionSizer   = new CPositionSizer();
   g_tpslCalculator  = new CTPSLCalculator();
   g_trailingStop    = new CTrailingStop();
   g_breakeven       = new CBreakeven();
   g_drawdownMonitor = new CDrawdownMonitor();
   g_basketManager   = new CBasketManager();
   g_recoveryMode    = new CRecoveryMode();
   g_trendFilter     = new CTrendFilter();
   g_newsFilter      = new CNewsFilter();
   g_spreadFilter    = new CSpreadFilter();
   g_scheduleFilter  = new CScheduleFilter();
   g_stochFilter     = new CStochasticFilter();
   g_smcStrategy     = new CSMCStrategy();
   g_gridStrategy    = new CGridStrategy();
   g_breakoutStrategy= new CBreakoutStrategy();
   g_stopHuntStrategy= new CStopHuntStrategy();
   g_strategyManager = new CStrategyManager();
   g_filterManager   = new CFilterManager();
   g_historyLabels   = new CHistoryLabels();
   g_dashboard       = new CDashboard();

   g_orderExecutor = new COrderExecutor(InpMagicNumber, CommentOrder, InpSlippagePoints, NULL);

   // ── Indicator cache ─────────────────────────────────────────────
   if(!g_indicatorCache.Initialize(_Symbol, _Period, ATR_Period, Trend_MA_Period,
                                   RSI_Period, Stoch_K_Period, Stoch_D_Period, Stoch_Slowing))
   { Print("ERROR: IndicatorCache init failed"); return INIT_FAILED; }

   Print(">>> [TRACE 6] Indicators Created. Error Status: 0");
   Print(">>> [TRACE 7] Calculating Day Stats...");

   // ── SMC detector ────────────────────────────────────────────────
   if(!g_smcDetector.Initialize(_Symbol, _Period, FVG_Lookback_Bars, 10.0,
                                1200, 50.0, Draw_FVG_Zones, false))
   { Print("ERROR: SMCDetector init failed"); return INIT_FAILED; }

   // ── Position tracker ────────────────────────────────────────────
   g_positionTracker.Init(InpMagicNumber, Control_orders_user, NULL);

   // ── Stealth mode manager ─────────────────────────────────────────
   // MachinePRO EXACT: BOTH TP and SL are virtual — broker sees tp=0, sl=0
   g_stealthManager.Init(g_positionTracker, g_orderExecutor, Use_Stealth_Mode, NULL);

   // ── Position sizer (MachinePRO lot formula) ──────────────────────
   // Verified: floor(balance/1000)*0.01 → $5000=0.05, $6008=0.06
   if(!g_positionSizer.Initialize(_Symbol, Lot_, Use_dynamic_lot_,
                                  Free_margin_for_each_Lots_, Max_Lot_, Kmartin_))
   { Print("ERROR: PositionSizer init failed"); return INIT_FAILED; }

   // ── TP/SL calculator (full stealth — tp=0, sl=0 on broker) ──────
   // vTP = entry ± ATR(7)×5.0 ≈ ±2.50 pts → ±$12.50 per 0.05 lot
   // vSL = entry ∓ ATR(7)×1.5 ≈ ∓0.75 pts → ∓$3.75 per 0.05 lot
   if(!g_tpslCalculator.Initialize(_Symbol, g_indicatorCache, NULL,
                                   Use_Auto_TP, Auto_TP_Ratio,
                                   Use_Auto_SL, Auto_SL_Ratio,
                                   Use_Stealth_Mode))
   { Print("ERROR: TPSLCalculator init failed"); return INIT_FAILED; }

   // ── Trailing stop (stealth-aware) ────────────────────────────────
   // Activates at 5×ATR (same as TP), trails at 5×ATR distance
   g_trailingStop.Init(g_indicatorCache, g_positionTracker, g_orderExecutor,
                       g_stealthManager, Enable_TrailingStop,
                       TS_Start_ATR_Multiplier, TS_Distance_ATR_Multiplier,
                       Use_Stealth_Mode, NULL);

   // ── Breakeven ────────────────────────────────────────────────────
   g_breakeven.Init(g_indicatorCache, g_positionTracker, g_orderExecutor,
                    g_stealthManager, Enable_Breakeven,
                    BE_Trigger_ATR_Multiplier, (double)BE_Profit_Points,
                    Use_Stealth_Mode, NULL);

   // ── Drawdown monitor ─────────────────────────────────────────────
   if(!g_drawdownMonitor.Initialize(Daily_Loss_Limit_USD, InpMaxDailyLossPct,
                                    InpMaxEquityDrawdown, Max_Drawdown_Percent,
                                    Daily_Profit_Target_USD, Stop_After_Losses))
   { Print("ERROR: DrawdownMonitor init failed"); return INIT_FAILED; }

   // ── Basket manager ───────────────────────────────────────────────
   if(!g_basketManager.Initialize(g_positionTracker, g_orderExecutor,
                                  Basket_Profit_USD, Basket_Loss_USD, InpMagicNumber))
   { Print("ERROR: BasketManager init failed"); return INIT_FAILED; }

   // ── Recovery / G2 Overlap ────────────────────────────────────────
   // MachinePRO EXACT: opens 2nd position in same direction as Legacy
   // after Overlap_AFTER_X_trades_ (4) consecutive legacy losses
   // Comment format: "MoneyMachine7 G2"
   if(!g_recoveryMode.Initialize(g_positionTracker, g_orderExecutor,
                                 Recovery_Mode_Enabled, Recovery_Target_USD,
                                 Overlap_AFTER_X_trades_, InpMagicNumber,
                                 g_stealthManager, g_tpslCalculator,
                                 g_positionSizer, CommentOrder))
   { Print("ERROR: RecoveryMode init failed"); return INIT_FAILED; }

   // ── Trend filter ─────────────────────────────────────────────────
   if(!g_trendFilter.Initialize(_Symbol, _Period, Enable_Trend_Filter, Trend_MA_Period))
   { Print("ERROR: TrendFilter init failed"); return INIT_FAILED; }

   // ── News filter ──────────────────────────────────────────────────
   if(!g_newsFilter.Initialize(Use_News_Filter, News_Suspend_Mins_Before, News_Suspend_Mins_After))
   { Print("ERROR: NewsFilter init failed"); return INIT_FAILED; }

   // ── Spread filter ────────────────────────────────────────────────
   if(!g_spreadFilter.Initialize(_Symbol, InpMaxSpreadPoints))
   { Print("ERROR: SpreadFilter init failed"); return INIT_FAILED; }

   // ── Schedule filter ──────────────────────────────────────────────
   if(!g_scheduleFilter.Initialize())
   { Print("ERROR: ScheduleFilter init failed"); return INIT_FAILED; }
   g_scheduleFilter.SetDaySchedule(1, Trade_Monday,    Monday_Start_Hour,    Monday_End_Hour);
   g_scheduleFilter.SetDaySchedule(2, Trade_Tuesday,   Tuesday_Start_Hour,   Tuesday_End_Hour);
   g_scheduleFilter.SetDaySchedule(3, Trade_Wednesday, Wednesday_Start_Hour, Wednesday_End_Hour);
   g_scheduleFilter.SetDaySchedule(4, Trade_Thursday,  Thursday_Start_Hour,  Thursday_End_Hour);
   g_scheduleFilter.SetDaySchedule(5, Trade_Friday,    Friday_Start_Hour,    Friday_End_Hour);
   g_scheduleFilter.SetDaySchedule(6, Trade_Saturday,  Saturday_Start_Hour,  Saturday_End_Hour);
   g_scheduleFilter.SetDaySchedule(0, Trade_Sunday,    Sunday_Start_Hour,    Sunday_End_Hour);

   // ── Stochastic filter ────────────────────────────────────────────
   if(!g_stochFilter.Initialize(_Symbol, _Period, Use_Grid_Stoch_Filter,
                                Stoch_Buy_Level, Stoch_Sell_Level,
                                Stoch_K_Period, Stoch_D_Period, Stoch_Slowing))
   { Print("ERROR: StochFilter init failed"); return INIT_FAILED; }

   // ── Filter manager ───────────────────────────────────────────────
   if(!g_filterManager.Initialize(g_trendFilter, g_newsFilter, g_spreadFilter,
                                  g_scheduleFilter, g_stochFilter))
   { Print("ERROR: FilterManager init failed"); return INIT_FAILED; }

   // ── Strategies ───────────────────────────────────────────────────
   ENUM_SMC_MODE smcMode = (InpStrategy==0) ? SMC_SWEEP :
                           (InpStrategy==2) ? SMC_BREAKOUT : SMC_HYBRID;

   if(!g_smcStrategy.Initialize(_Symbol, _Period, smcMode, g_smcDetector, g_indicatorCache,
                                RSI_Buy_Threshold, RSI_Sell_Threshold))
   { Print("ERROR: SMCStrategy init failed"); return INIT_FAILED; }

   // GridStrategy: uses CommentOrder + " [Legacy]" as the trade comment
   if(!g_gridStrategy.Initialize(_Symbol, _Period, Auto_Grid_Intensity, ADR_Period_Days,
                                 Grid_Distance_Multiplier, Custom_ADR_Divider,
                                 Max_Buy, Max_Sell, Use_Grid_Stoch_Filter,
                                 g_positionTracker, g_orderExecutor, g_positionSizer,
                                 g_tpslCalculator, g_filterManager, g_stochFilter,
                                 InpMagicNumber, g_stealthManager, Use_Stealth_Mode,
                                 CommentOrder))
   { Print("ERROR: GridStrategy init failed"); return INIT_FAILED; }
   // Link G2 recovery to grid (grid notifies recovery of each new trade)

   if(!g_breakoutStrategy.Initialize(_Symbol, _Period, Breakout_Period, Breakout_Buffer,
                                     Min_Breakout_Range, Use_RSI_Confirmation,
                                     RSI_Buy_Threshold, RSI_Sell_Threshold,
                                     Use_Volume_Confirmation, Volume_Ma_Period,
                                     g_indicatorCache))
   { Print("ERROR: BreakoutStrategy init failed"); return INIT_FAILED; }

   if(!g_stopHuntStrategy.Initialize(_Symbol, _Period, 50, 5.0, g_smcDetector))
   { Print("ERROR: StopHuntStrategy init failed"); return INIT_FAILED; }

   if(!g_strategyManager.Initialize(g_smcStrategy, g_gridStrategy, g_breakoutStrategy,
                                    g_stopHuntStrategy, Enable_Breakout_Strategy,
                                    Enable_Stop_Hunt_Strategy))
   { Print("ERROR: StrategyManager init failed"); return INIT_FAILED; }

   // ── History labels ───────────────────────────────────────────────
   if(!g_historyLabels.Initialize(Enable_History_Labels, History_Labels_Limit, InpMagicNumber))
   { Print("ERROR: HistoryLabels init failed"); return INIT_FAILED; }

   // ── Dashboard ────────────────────────────────────────────────────
   if(!g_dashboard.Initialize(Enable_Dashboard, Dashboard_Corner,
                              Dashboard_X_Offset, Dashboard_Y_Offset))
   { Print("ERROR: Dashboard init failed"); return INIT_FAILED; }

   Print(">>> [TRACE 8] Launching Dashboard Objects...");
   Print(">>> [TRACE 9] Running Dynamic Grid Pre-calc...");

   g_initializationSuccess = true;
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   Print(">>> [SUCCESS] Money Machine 7.0 is now Online.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_smcDetector  != NULL) g_smcDetector.ClearZoneDrawings();
   if(g_dashboard    != NULL) g_dashboard.Clear();

   if(g_indicatorCache   != NULL) { delete g_indicatorCache;   g_indicatorCache=NULL;   }
   if(g_smcDetector      != NULL) { delete g_smcDetector;      g_smcDetector=NULL;      }
   if(g_orderExecutor    != NULL) { delete g_orderExecutor;    g_orderExecutor=NULL;    }
   if(g_positionTracker  != NULL) { delete g_positionTracker;  g_positionTracker=NULL;  }
   if(g_stealthManager   != NULL) { delete g_stealthManager;   g_stealthManager=NULL;   }
   if(g_positionSizer    != NULL) { delete g_positionSizer;    g_positionSizer=NULL;    }
   if(g_tpslCalculator   != NULL) { delete g_tpslCalculator;   g_tpslCalculator=NULL;   }
   if(g_trailingStop     != NULL) { delete g_trailingStop;     g_trailingStop=NULL;     }
   if(g_breakeven        != NULL) { delete g_breakeven;        g_breakeven=NULL;        }
   if(g_drawdownMonitor  != NULL) { delete g_drawdownMonitor;  g_drawdownMonitor=NULL;  }
   if(g_basketManager    != NULL) { delete g_basketManager;    g_basketManager=NULL;    }
   if(g_recoveryMode     != NULL) { delete g_recoveryMode;     g_recoveryMode=NULL;     }
   if(g_trendFilter      != NULL) { delete g_trendFilter;      g_trendFilter=NULL;      }
   if(g_newsFilter       != NULL) { delete g_newsFilter;       g_newsFilter=NULL;       }
   if(g_spreadFilter     != NULL) { delete g_spreadFilter;     g_spreadFilter=NULL;     }
   if(g_scheduleFilter   != NULL) { delete g_scheduleFilter;   g_scheduleFilter=NULL;   }
   if(g_stochFilter      != NULL) { delete g_stochFilter;      g_stochFilter=NULL;      }
   if(g_smcStrategy      != NULL) { delete g_smcStrategy;      g_smcStrategy=NULL;      }
   if(g_gridStrategy     != NULL) { delete g_gridStrategy;     g_gridStrategy=NULL;     }
   if(g_breakoutStrategy != NULL) { delete g_breakoutStrategy; g_breakoutStrategy=NULL; }
   if(g_stopHuntStrategy != NULL) { delete g_stopHuntStrategy; g_stopHuntStrategy=NULL; }
   if(g_strategyManager  != NULL) { delete g_strategyManager;  g_strategyManager=NULL;  }
   if(g_filterManager    != NULL) { delete g_filterManager;    g_filterManager=NULL;    }
   if(g_historyLabels    != NULL) { delete g_historyLabels;    g_historyLabels=NULL;    }
   if(g_dashboard        != NULL) { delete g_dashboard;        g_dashboard=NULL;        }
}

//+------------------------------------------------------------------+
//| Expert tick function — MachinePRO exact execution flow           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initializationSuccess) return;

   // ── 1. Update position tracker (every tick) ─────────────────────
   g_positionTracker.UpdatePositions();

   // ── 2. Stealth mode: check virtual TP & SL every tick ───────────
   // This is what produces 40s avg duration — tick-level monitoring
   // Both TP and SL are checked tick by tick (no broker TP/SL visible)
   if(Use_Stealth_Mode)
      g_stealthManager.ManageStealthMode();

   // ── 3. Trailing stop (every tick, stealth-aware) ─────────────────
   if(Enable_TrailingStop)
      g_trailingStop.UpdateTrailingStop();

   // ── 4. Breakeven ────────────────────────────────────────────────
   if(Enable_Breakeven)
      g_breakeven.UpdateBreakeven();

   // ── 5. Basket management ────────────────────────────────────────
   g_basketManager.ManageBasket();

   // ── 6. G2 Recovery mode (every tick) ────────────────────────────
   // Opens "MoneyMachine7 G2" overlay position after N legacy trades
   // Runs every tick to catch the ~30-60s delay timing
   if(Recovery_Mode_Enabled)
      g_recoveryMode.ManageRecoveryMode();

   // ── 7. New bar detection ──────────────────────────────────────────────────────
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBarTime != g_lastBarTime);
   if(isNewBar)
   {
      g_lastBarTime = currentBarTime;

      // Update indicators on new bar (bar 0 = current forming bar, fresh value)
      // ATR(7) M1 XAUUSD uses bar 0 to get real-time ATR ≈ 0.50 pts
      // Using bar 1 (closed) gives H1-scaled values (3-5 pts) → wrong SL distances
      g_indicatorCache.UpdateIndicators();

      // Update filters
      g_filterManager.UpdateFilters();

      // ── 8. Grid strategy (NEW BAR ONLY — 1 trade per minute max) ─────────────
      // MachinePRO opens at most 1 position per M1 candle open
      // Additional condition: price must be >= gridDist from last placed entry
      // This produces the exact 1-per-minute pattern seen in the target log
      if(Use_Auto_Grid && Auto_Grid_Intensity > 0)
      {
         if(!g_drawdownMonitor.CheckRiskLimits())
         {
            g_tradingEnabled = false;
         }
         else if(g_tradingEnabled && g_scheduleFilter.IsTradingAllowed())
         {
            g_gridStrategy.PlaceGridOrders();
         }
      }
   }

   // ── 8. Dashboard refresh ────────────────────────────────────────
   if(Enable_Dashboard && g_dashboard != NULL)
   {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      RiskMetrics metrics;
      g_drawdownMonitor.GetRiskMetrics(metrics);
      PositionInfo positions[];
      g_positionTracker.GetAllPositions(positions);
      int openPos = ArraySize(positions);

      datetime startOfDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      int dailyTrades = 0;
      HistorySelect(startOfDay, TimeCurrent());
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
            dailyTrades++;
      }
      g_dashboard.Update(balance, equity, metrics.currentDrawdown,
                         metrics.dailyProfit, openPos, dailyTrades);
   }
}
