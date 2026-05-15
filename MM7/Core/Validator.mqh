#ifndef MM7_CORE_VALIDATOR_MQH
#define MM7_CORE_VALIDATOR_MQH

//+------------------------------------------------------------------+
//|                                                  Validator.mqh   |
//|                     MoneyMachine7 — Input Validator              |
//+------------------------------------------------------------------+

#include "MM7/Core/DataStructures.mqh"

class CValidator
{
public:
   static bool ValidateSymbol(string symbol)
   {
      if(StringLen(symbol) == 0) { Print("ERROR: Empty symbol"); return false; }
      return true;
   }

   static bool ValidateLot(double lot, double maxLot)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(lot < minLot) { Print("WARN: Lot " + DoubleToString(lot,2) + " below min " + DoubleToString(minLot,2)); return false; }
      if(lot > maxLot) { Print("WARN: Lot " + DoubleToString(lot,2) + " above max " + DoubleToString(maxLot,2)); return false; }
      return true;
   }

   static double NormalizeLot(double lot)
   {
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      lot = MathFloor(lot / step) * step;
      if(lot < minL) lot = minL;
      return NormalizeDouble(lot, 2);
   }
};


#endif // MM7_CORE_VALIDATOR_MQH
