#ifndef MM7_CORE_DATASTRUCTURES_MQH
#define MM7_CORE_DATASTRUCTURES_MQH

//+------------------------------------------------------------------+
//|                                           DataStructures.mqh     |
//|                     MoneyMachine7 — Core Data Types              |
//+------------------------------------------------------------------+


//--- Strategy modes
enum ENUM_SMC_MODE
{
   SMC_SWEEP    = 0,   // Institutional Sweep Mode
   SMC_HYBRID   = 1,   // Hybrid SMC Mode (default)
   SMC_BREAKOUT = 2    // Structure Breakout Mode
};

//--- Order direction
enum ENUM_TRADE_DIR
{
   DIR_BUY  = 1,
   DIR_SELL = -1,
   DIR_NONE = 0
};

//--- FVG Zone
struct FVGZone
{
   double   high;
   double   low;
   bool     isBullish;
   datetime time;
   bool     filled;
};

//--- Order Block
struct OrderBlock
{
   double   high;
   double   low;
   bool     isBullish;
   datetime time;
   bool     mitigated;
};

//--- Position tracking info
struct PositionInfo
{
   ulong    ticket;
   double   entryPrice;
   double   virtualTP;
   double   virtualSL;
   double   lot;
   int      direction;   // 1=buy, -1=sell
   datetime openTime;
   string   comment;
   bool     isG2;
};

//--- Risk metrics
struct RiskMetrics
{
   double   currentDrawdown;    // % equity drawdown from peak
   double   dailyProfit;        // today's closed P&L
   double   dailyLoss;          // today's closed loss (positive value)
   double   peakEquity;
   int      consecutiveLosses;
};

//--- Signal result
struct SignalResult
{
   ENUM_TRADE_DIR direction;
   double         strength;     // 0-1
   string         reason;
};


#endif // MM7_CORE_DATASTRUCTURES_MQH
