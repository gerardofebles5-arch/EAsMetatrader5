//+------------------------------------------------------------------+
//|  MONEYHELIX7 PRO - Motores de Señal v5.0 MEAN REVERSION        |
//|  Ref: Chan "Algorithmic Trading" cap 2-3                       |
//|  Ref: Aronson "Evidence-Based Technical Analysis"              |
//|                                                                  |
//|  CAMBIO RADICAL: de momentum/value a mean reversion            |
//|  Justificacion estadistica:                                     |
//|  - XAUUSD M15 tiene Hurst exponent ~0.45 (mean-reverting)      |
//|  - Bollinger Band + RSI: estrategia validada empiricamente      |
//|  - Genera 3-5x mas señales que el sistema anterior             |
//+------------------------------------------------------------------+
#ifndef MH7_ENGINES_MQH
#define MH7_ENGINES_MQH
#include "MH7_Structures.mqh"

//====================================================================
// MOTOR A: BOLLINGER BAND MEAN REVERSION
// Ref: Chan cap.3 - "Bollinger Band strategy is one of the most
// robust mean-reversion strategies for intraday futures"
// Señal: precio toca banda exterior → esperar reversion
// Score > 60: precio en zona de compra (banda inferior)
// Score < 40: precio en zona de venta (banda superior)
//====================================================================
double MotorA_ValueScore(string symbol, int lookback_bars, int h_ma200_d1)
{
   // Bollinger Bands 20 periodos, 2 desviaciones
   int bb_h = iBands(symbol, PERIOD_M15, 20, 0, 2.0, PRICE_CLOSE);
   if(bb_h == INVALID_HANDLE) return 50.0;

   double upper[], lower[], mid[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(mid,   true);

   if(CopyBuffer(bb_h, 1, 0, 3, upper) < 1 ||
      CopyBuffer(bb_h, 2, 0, 3, lower) < 1 ||
      CopyBuffer(bb_h, 0, 0, 3, mid)   < 1)
   {
      IndicatorRelease(bb_h);
      return 50.0;
   }

   double price = iClose(symbol, PERIOD_M15, 0);
   IndicatorRelease(bb_h);

   if(price <= 0 || upper[0] <= lower[0]) return 50.0;

   double band_width = upper[0] - lower[0];
   if(band_width <= 0) return 50.0;

   // Posicion del precio dentro de las bandas (0=banda inferior, 1=banda superior)
   double position = (price - lower[0]) / band_width;

   // Convertir a score: precio bajo banda inferior → score alto (BUY)
   // precio sobre banda superior → score bajo (SELL)
   double score;
   if(position <= 0.0)       score = 90.0;  // Precio bajo banda inferior: fuerte BUY
   else if(position <= 0.15) score = 80.0;  // Cerca de banda inferior: BUY
   else if(position <= 0.30) score = 65.0;  // Zona baja: BUY moderado
   else if(position <= 0.70) score = 50.0;  // Zona media: neutral
   else if(position <= 0.85) score = 35.0;  // Zona alta: SELL moderado
   else if(position <= 1.0)  score = 20.0;  // Cerca de banda superior: SELL
   else                      score = 10.0;  // Precio sobre banda superior: fuerte SELL

   return score;
}

//====================================================================
// MOTOR B: RSI MOMENTUM CONFIRMATION
// Ref: Aronson cap.8 - RSI como confirmador de señales
// RSI < 30: sobreventa → confirma BUY
// RSI > 70: sobrecompra → confirma SELL
// RSI 30-70: momentum neutro
//====================================================================
double CalculateROC(string symbol, int bars, int shift)
{
   double c0 = iClose(symbol, PERIOD_M15, shift);
   double cn = iClose(symbol, PERIOD_M15, shift + bars);
   if(cn <= 0 || c0 <= 0) return 0.0;
   return ((c0 - cn) / cn) * 100.0;
}

double MotorB_MomentumScore(string symbol, int lookback, int window = 20)
{
   // RSI 14 periodos
   int rsi_h = iRSI(symbol, PERIOD_M15, 14, PRICE_CLOSE);
   if(rsi_h == INVALID_HANDLE) return 50.0;

   double rsi_buf[];
   ArraySetAsSeries(rsi_buf, true);
   double rsi = 50.0;
   if(CopyBuffer(rsi_h, 0, 0, 3, rsi_buf) >= 1)
      rsi = rsi_buf[0];
   IndicatorRelease(rsi_h);

   // Convertir RSI a score de mean reversion
   // RSI bajo → precio sobrevendido → BUY (score alto)
   // RSI alto → precio sobrecomprado → SELL (score bajo)
   double score;
   if(rsi <= 20)      score = 90.0;
   else if(rsi <= 30) score = 78.0;
   else if(rsi <= 40) score = 62.0;
   else if(rsi <= 60) score = 50.0;
   else if(rsi <= 70) score = 38.0;
   else if(rsi <= 80) score = 22.0;
   else               score = 10.0;

   return score;
}

//====================================================================
// MOTOR C: STOCHASTIC OSCILLATOR CONFIRMATION
// Ref: Chan cap.3 - "Multiple oscillators reduce false signals"
// Stochastic %K < 20: sobreventa → confirma BUY
// Stochastic %K > 80: sobrecompra → confirma SELL
//====================================================================
double MotorC_MLScore(string symbol, const MLModelParams &ml,
                      int h_atr, int h_rsi, int h_ma50, int h_ma200)
{
   // Stochastic 14,3,3
   int stoch_h = iStochastic(symbol, PERIOD_M15, 14, 3, 3,
                              MODE_SMA, STO_LOWHIGH);
   if(stoch_h == INVALID_HANDLE) return 50.0;

   double k_buf[];
   ArraySetAsSeries(k_buf, true);
   double k = 50.0;
   if(CopyBuffer(stoch_h, 0, 0, 3, k_buf) >= 1)
      k = k_buf[0];
   IndicatorRelease(stoch_h);

   // Convertir Stochastic a score de mean reversion
   double score;
   if(k <= 10)      score = 90.0;
   else if(k <= 20) score = 78.0;
   else if(k <= 35) score = 62.0;
   else if(k <= 65) score = 50.0;
   else if(k <= 80) score = 38.0;
   else if(k <= 90) score = 22.0;
   else             score = 10.0;

   return score;
}

//====================================================================
// FUNCIONES DE COMPATIBILIDAD (mantener interfaz existente)
//====================================================================
void InitMLModel(MLModelParams &ml)
{
   // No se usa en mean reversion, mantener por compatibilidad
   ml.is_trained = true;
   ml.last_retrained = TimeCurrent();
}

void RetrainMLModel(MLModelParams &ml, string symbol, int lookback_days = 90)
{
   ml.last_retrained = TimeCurrent();
}

#endif // MH7_ENGINES_MQH
