//+------------------------------------------------------------------+
//|                                          PSM_EA_Monolithic.mq5   |
//|                         Phase-State Machine Expert Advisor        |
//|                    Monolithic Version - All modules consolidated  |
//+------------------------------------------------------------------+
#property copyright   "PSM EA System"
#property version     "2.00"
#property strict
#property description "Phase-State Machine Expert Advisor for XAUUSD - Monolithic"

//+------------------------------------------------------------------+
//| ÍNDICE DE CONTENIDO                                              |
//|------------------------------------------------------------------|
//|  1. Enumeraciones Globales          (EState)                     |
//|  2. Estructuras Globales            (SHysteresisConfig,          |
//|                                      SSwingPoint)                |
//|  3. Clases de Indicadores                                        |
//|     3.1 CATR_Calculator             (CATR_Calculator.mqh)        |
//|     3.2 CEMA_Fan                    (CEMA_Fan.mqh)               |
//|     3.3 CStochastic_Oscillator      (CStochastic_Oscillator.mqh) |
//|     3.4 CVWAP_Indicator             (CVWAP_Indicator.mqh)        |
//|  4. Clases de Análisis de Mercado                                |
//|     4.1 CVolatility_Monitor         (CVolatility_Monitor.mqh)    |
//|     4.2 CVolume_Analyzer            (CVolume_Analyzer.mqh)       |
//|     4.3 CMomentum_Detector          (CMomentum_Detector.mqh)     |
//|     4.4 CSwing_Point_Tracker        (CSwing_Point_Tracker.mqh)   |
//|  5. Clases de Control                                            |
//|     5.1 CStatic_Drawdown_Monitor    (CStatic_Drawdown_Monitor.mqh)|
//|     5.2 CHysteresis_Controller      (CHysteresis_Controller.mqh) |
//|     5.3 CFSM_Manager               (CFSM_Manager.mqh)           |
//|  6. Parámetros de Entrada del EA                                 |
//|  7. Variables Globales del EA                                    |
//|  8. Función OnInit()                                             |
//|  9. Función OnDeinit()                                           |
//| 10. Función OnTick()                                             |
//| 11. Funciones Auxiliares                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| SECCIÓN 1: ENUMERACIONES GLOBALES                                |
//+------------------------------------------------------------------+

// Requirements: 3.1
// Enumeración de estados de la máquina de estados finitos
// Los valores binarios representan la combinación de bits de tendencia:
//   Bit 1 (valor 2): Tendencia alcista activa
//   Bit 0 (valor 1): Momentum positivo activo
enum EState
{
   STATE_NEUTRAL   = 0,  // 00b - Sin tendencia, sin momentum
   STATE_TRENDING  = 2,  // 10b - Tendencia activa, sin momentum confirmado
   STATE_MOMENTUM  = 1,  // 01b - Momentum activo, sin tendencia establecida
   STATE_CONFIRMED = 3   // 11b - Tendencia y momentum confirmados (señal de trading)
};

//+------------------------------------------------------------------+
//| SECCIÓN 2: ESTRUCTURAS GLOBALES                                  |
//+------------------------------------------------------------------+

// Requirements: 3.2
// Configuración del controlador de histéresis para evitar oscilaciones de estado
struct SHysteresisConfig
{
   double   entry_threshold;     // Umbral de entrada al estado (0.0 - 1.0)
   double   exit_threshold;      // Umbral de salida del estado (0.0 - 1.0)
   int      confirmation_bars;   // Número de barras de confirmación requeridas
   double   noise_filter;        // Filtro de ruido (porcentaje mínimo de cambio)
   bool     use_adaptive;        // Usar umbrales adaptativos basados en volatilidad

   SHysteresisConfig()
   {
      entry_threshold   = 0.6;
      exit_threshold    = 0.4;
      confirmation_bars = 2;
      noise_filter      = 0.01;
      use_adaptive      = false;
   }
};

// Requirements: 3.3
// Estructura que representa un punto de swing en el mercado
struct SSwingPoint
{
   datetime time;        // Tiempo de la barra del swing
   double   price;       // Precio del swing (high o low)
   int      bar_index;   // Índice de la barra en el historial
   bool     is_high;     // true = swing high, false = swing low
   int      strength;    // Fuerza del swing (número de barras que confirman)
   bool     is_valid;    // Indica si el punto es válido y no ha sido superado

   SSwingPoint()
   {
      time      = 0;
      price     = 0.0;
      bar_index = -1;
      is_high   = false;
      strength  = 0;
      is_valid  = false;
   }
};

//+------------------------------------------------------------------+
//| SECCIÓN 3.1: CLASE CATR_Calculator                               |
//| Origen: CATR_Calculator.mqh                                      |
//+------------------------------------------------------------------+

// Requirements: 5.1, 5.5, 2.1, 2.5, 12.5
// Clase para calcular el Average True Range (ATR)
// Proporciona medidas de volatilidad basadas en el rango verdadero promedio
class CATR_Calculator
{
private:
   int      m_period;           // Período del ATR
   string   m_symbol;           // Símbolo de trading
   ENUM_TIMEFRAMES m_timeframe; // Marco temporal
   double   m_atr_value;        // Último valor calculado de ATR
   double   m_atr_multiplier;   // Multiplicador para bandas de volatilidad
   bool     m_initialized;      // Estado de inicialización
   double   m_atr_buffer[];     // Buffer para valores de ATR
   int      m_atr_handle;       // Handle del indicador ATR

public:
   // Constructor
   CATR_Calculator()
   {
      m_period      = 14;
      m_symbol      = _Symbol;
      m_timeframe   = PERIOD_M5;
      m_atr_value   = 0.0;
      m_atr_multiplier = 1.5;
      m_initialized = false;
      m_atr_handle  = INVALID_HANDLE;
   }

   // Destructor
   ~CATR_Calculator()
   {
      Deinit();
   }

   // Requirements: 5.1
   // Inicializa el calculador de ATR
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period, const double multiplier = 1.5)
   {
      m_symbol      = symbol;
      m_timeframe   = timeframe;
      m_period      = period;
      m_atr_multiplier = multiplier;

      if(m_period <= 0)
      {
         Print("CATR_Calculator::Init() - Período inválido: ", m_period);
         return false;
      }

      m_atr_handle = iATR(m_symbol, m_timeframe, m_period);
      if(m_atr_handle == INVALID_HANDLE)
      {
         Print("CATR_Calculator::Init() - Error al crear handle ATR: ", GetLastError());
         return false;
      }

      ArraySetAsSeries(m_atr_buffer, true);
      m_initialized = true;
      return true;
   }

   // Libera recursos
   void Deinit()
   {
      if(m_atr_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atr_handle);
         m_atr_handle = INVALID_HANDLE;
      }
      m_initialized = false;
   }

   // Requirements: 5.5
   // Actualiza el valor de ATR en cada nueva barra
   bool OnNewBar()
   {
      if(!m_initialized)
      {
         Print("CATR_Calculator::OnNewBar() - No inicializado");
         return false;
      }

      if(CopyBuffer(m_atr_handle, 0, 0, 3, m_atr_buffer) < 3)
      {
         Print("CATR_Calculator::OnNewBar() - Error copiando buffer ATR: ", GetLastError());
         return false;
      }

      m_atr_value = m_atr_buffer[1]; // Barra cerrada más reciente
      return true;
   }

   // Retorna el valor actual del ATR
   double GetATR() const { return m_atr_value; }

   // Retorna el ATR en pips
   double GetATRInPips() const
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point == 0) return 0;
      return m_atr_value / point;
   }

   // Retorna el multiplicador del ATR
   double GetMultiplier() const { return m_atr_multiplier; }

   // Retorna el band superior basado en precio y ATR
   double GetUpperBand(const double price) const { return price + m_atr_value * m_atr_multiplier; }

   // Retorna el band inferior basado en precio y ATR
   double GetLowerBand(const double price) const { return price - m_atr_value * m_atr_multiplier; }

   // Verifica si la volatilidad actual supera un umbral
   bool IsHighVolatility(const double threshold_multiplier = 2.0) const
   {
      // Comparar con el promedio histórico
      if(!m_initialized || m_atr_value <= 0) return false;
      return m_atr_value > (m_atr_value * threshold_multiplier);
   }

   // Estado de inicialización
   bool IsInitialized() const { return m_initialized; }

   // Período configurado
   int GetPeriod() const { return m_period; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 3.2: CLASE CEMA_Fan                                      |
//| Origen: CEMA_Fan.mqh                                             |
//+------------------------------------------------------------------+

// Requirements: 5.2, 5.5, 2.1, 2.5, 12.5
// Clase que implementa el abanico de EMAs (Exponential Moving Averages)
// Analiza la alineación y dispersión de múltiples EMAs para determinar tendencia
class CEMA_Fan
{
private:
   int      m_periods[5];          // Períodos de cada EMA (máx 5)
   int      m_ema_handles[5];      // Handles de los indicadores
   double   m_ema_values[5];       // Valores actuales de cada EMA
   int      m_count;               // Número de EMAs activas
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   bool     m_initialized;

public:
   CEMA_Fan()
   {
      m_count       = 0;
      m_symbol      = _Symbol;
      m_timeframe   = PERIOD_M5;
      m_initialized = false;
      for(int i = 0; i < 5; i++)
      {
         m_periods[i]     = 0;
         m_ema_handles[i] = INVALID_HANDLE;
         m_ema_values[i]  = 0.0;
      }
   }

   ~CEMA_Fan() { Deinit(); }

   // Requirements: 5.2
   // Inicializa el abanico de EMAs con períodos dados
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
             const int period1, const int period2, const int period3,
             const int period4 = 0, const int period5 = 0)
   {
      m_symbol    = symbol;
      m_timeframe = timeframe;
      m_count     = 0;

      int periods_temp[] = {period1, period2, period3, period4, period5};

      for(int i = 0; i < 5; i++)
      {
         if(periods_temp[i] <= 0) break;
         m_periods[i] = periods_temp[i];

         m_ema_handles[i] = iMA(m_symbol, m_timeframe, m_periods[i], 0, MODE_EMA, PRICE_CLOSE);
         if(m_ema_handles[i] == INVALID_HANDLE)
         {
            Print("CEMA_Fan::Init() - Error al crear EMA ", m_periods[i], ": ", GetLastError());
            Deinit();
            return false;
         }
         m_count++;
      }

      if(m_count < 2)
      {
         Print("CEMA_Fan::Init() - Se requieren al menos 2 EMAs");
         Deinit();
         return false;
      }

      m_initialized = true;
      return true;
   }

   void Deinit()
   {
      for(int i = 0; i < 5; i++)
      {
         if(m_ema_handles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_ema_handles[i]);
            m_ema_handles[i] = INVALID_HANDLE;
         }
         m_ema_values[i] = 0.0;
      }
      m_initialized = false;
   }

   // Requirements: 5.5
   // Actualiza los valores de todas las EMAs
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      for(int i = 0; i < m_count; i++)
      {
         double buf[];
         ArraySetAsSeries(buf, true);
         ArrayResize(buf, 3);
         if(CopyBuffer(m_ema_handles[i], 0, 0, 3, buf) < 3)
         {
            Print("CEMA_Fan::OnNewBar() - Error copiando EMA ", m_periods[i]);
            return false;
         }
         m_ema_values[i] = buf[1];
      }
      return true;
   }

   // Verifica si las EMAs están alineadas alcistamente (EMA corta > larga)
   bool IsBullishAlignment() const
   {
      if(!m_initialized || m_count < 2) return false;
      for(int i = 0; i < m_count - 1; i++)
      {
         if(m_ema_values[i] <= m_ema_values[i + 1]) return false;
      }
      return true;
   }

   // Verifica si las EMAs están alineadas bajistamente
   bool IsBearishAlignment() const
   {
      if(!m_initialized || m_count < 2) return false;
      for(int i = 0; i < m_count - 1; i++)
      {
         if(m_ema_values[i] >= m_ema_values[i + 1]) return false;
      }
      return true;
   }

   // Retorna la dispersión del abanico (diferencia entre mayor y menor EMA)
   double GetFanSpread() const
   {
      if(!m_initialized || m_count < 2) return 0.0;
      double max_val = m_ema_values[0];
      double min_val = m_ema_values[0];
      for(int i = 1; i < m_count; i++)
      {
         if(m_ema_values[i] > max_val) max_val = m_ema_values[i];
         if(m_ema_values[i] < min_val) min_val = m_ema_values[i];
      }
      return max_val - min_val;
   }

   // Retorna el valor de una EMA por índice
   double GetEMA(const int index) const
   {
      if(index < 0 || index >= m_count) return 0.0;
      return m_ema_values[index];
   }

   // Retorna el número de EMAs configuradas
   int GetCount() const { return m_count; }

   // Calcula el ángulo de inclinación del abanico (tendencia)
   // Retorna valor entre -1.0 (bajista fuerte) y 1.0 (alcista fuerte)
   double GetTrendStrength() const
   {
      if(!m_initialized || m_count < 2) return 0.0;
      if(IsBullishAlignment()) return 1.0;
      if(IsBearishAlignment()) return -1.0;

      // Contar cuántas EMAs están en orden correcto
      int bull_count = 0;
      for(int i = 0; i < m_count - 1; i++)
      {
         if(m_ema_values[i] > m_ema_values[i + 1]) bull_count++;
      }
      return (2.0 * bull_count / (m_count - 1)) - 1.0;
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 3.3: CLASE CStochastic_Oscillator                        |
//| Origen: CStochastic_Oscillator.mqh                               |
//+------------------------------------------------------------------+

// Requirements: 5.3, 5.5, 2.1, 2.5, 12.5
// Clase que implementa el Oscilador Estocástico
// Identifica condiciones de sobrecompra/sobreventa y cruces de señal
class CStochastic_Oscillator
{
private:
   int      m_k_period;    // Período %K
   int      m_d_period;    // Período %D (suavizado)
   int      m_slowing;     // Factor de desaceleración
   ENUM_MA_METHOD     m_ma_method;   // Método de promedio móvil
   ENUM_STO_PRICE     m_price_field; // Campo de precio
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_handle;
   double   m_k_value;     // Valor actual de %K
   double   m_d_value;     // Valor actual de %D
   double   m_k_prev;      // Valor anterior de %K
   double   m_d_prev;      // Valor anterior de %D
   double   m_overbought;  // Nivel de sobrecompra (default 80)
   double   m_oversold;    // Nivel de sobreventa (default 20)
   bool     m_initialized;

public:
   CStochastic_Oscillator()
   {
      m_k_period   = 14;
      m_d_period   = 3;
      m_slowing    = 3;
      m_ma_method  = MODE_SMA;
      m_price_field = STO_LOWHIGH;
      m_symbol     = _Symbol;
      m_timeframe  = PERIOD_M5;
      m_handle     = INVALID_HANDLE;
      m_k_value    = 50.0;
      m_d_value    = 50.0;
      m_k_prev     = 50.0;
      m_d_prev     = 50.0;
      m_overbought = 80.0;
      m_oversold   = 20.0;
      m_initialized = false;
   }

   ~CStochastic_Oscillator() { Deinit(); }

   // Requirements: 5.3
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
             const int k_period = 14, const int d_period = 3, const int slowing = 3,
             const double overbought = 80.0, const double oversold = 20.0)
   {
      m_symbol     = symbol;
      m_timeframe  = timeframe;
      m_k_period   = k_period;
      m_d_period   = d_period;
      m_slowing    = slowing;
      m_overbought = overbought;
      m_oversold   = oversold;

      m_handle = iStochastic(m_symbol, m_timeframe, m_k_period, m_d_period, m_slowing,
                              m_ma_method, m_price_field);
      if(m_handle == INVALID_HANDLE)
      {
         Print("CStochastic_Oscillator::Init() - Error al crear handle: ", GetLastError());
         return false;
      }

      m_initialized = true;
      return true;
   }

   void Deinit()
   {
      if(m_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
      }
      m_initialized = false;
   }

   // Requirements: 5.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      double k_buf[], d_buf[];
      ArraySetAsSeries(k_buf, true);
      ArraySetAsSeries(d_buf, true);
      ArrayResize(k_buf, 3);
      ArrayResize(d_buf, 3);

      if(CopyBuffer(m_handle, 0, 0, 3, k_buf) < 3) return false;
      if(CopyBuffer(m_handle, 1, 0, 3, d_buf) < 3) return false;

      m_k_prev  = m_k_value;
      m_d_prev  = m_d_value;
      m_k_value = k_buf[1];
      m_d_value = d_buf[1];

      return true;
   }

   // Valores actuales
   double GetK() const { return m_k_value; }
   double GetD() const { return m_d_value; }
   double GetKPrev() const { return m_k_prev; }
   double GetDPrev() const { return m_d_prev; }

   // Condiciones de mercado
   bool IsOverbought() const { return m_k_value >= m_overbought; }
   bool IsOversold()   const { return m_k_value <= m_oversold; }

   // Cruces de señal
   bool IsBullishCross() const { return (m_k_prev < m_d_prev) && (m_k_value > m_d_value); }
   bool IsBearishCross() const { return (m_k_prev > m_d_prev) && (m_k_value < m_d_value); }

   // Cruce desde zona de sobreventa (señal de compra fuerte)
   bool IsBullishCrossFromOversold() const
   {
      return IsBullishCross() && (m_k_prev <= m_oversold || m_d_prev <= m_oversold);
   }

   // Cruce desde zona de sobrecompra (señal de venta fuerte)
   bool IsBearishCrossFromOverbought() const
   {
      return IsBearishCross() && (m_k_prev >= m_overbought || m_d_prev >= m_overbought);
   }

   // Fuerza del momentum estocástico (-1.0 a 1.0)
   double GetMomentumStrength() const
   {
      return (m_k_value - 50.0) / 50.0;
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 3.4: CLASE CVWAP_Indicator                               |
//| Origen: CVWAP_Indicator.mqh                                      |
//+------------------------------------------------------------------+

// Requirements: 5.4, 5.5, 2.1, 2.5, 12.5
// Clase que implementa el Volume Weighted Average Price (VWAP)
// Calcula el precio promedio ponderado por volumen para el día actual
class CVWAP_Indicator
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   double   m_vwap_value;          // Valor actual del VWAP
   double   m_vwap_upper_band;     // Banda superior del VWAP (VWAP + desv. std)
   double   m_vwap_lower_band;     // Banda inferior del VWAP (VWAP - desv. std)
   double   m_std_deviation;       // Desviación estándar del precio respecto al VWAP
   double   m_band_multiplier;     // Multiplicador para las bandas (default 1.0)
   double   m_cumulative_tpv;      // Precio típico * volumen acumulado
   double   m_cumulative_volume;   // Volumen acumulado
   double   m_cumulative_tpv2;     // Para cálculo de desviación estándar
   datetime m_session_start;       // Inicio de sesión actual
   bool     m_initialized;

   // Calcula el precio típico de una barra
   double TypicalPrice(const int shift) const
   {
      double h = iHigh(m_symbol, m_timeframe, shift);
      double l = iLow(m_symbol, m_timeframe, shift);
      double c = iClose(m_symbol, m_timeframe, shift);
      return (h + l + c) / 3.0;
   }

public:
   CVWAP_Indicator()
   {
      m_symbol           = _Symbol;
      m_timeframe        = PERIOD_M5;
      m_vwap_value       = 0.0;
      m_vwap_upper_band  = 0.0;
      m_vwap_lower_band  = 0.0;
      m_std_deviation    = 0.0;
      m_band_multiplier  = 1.0;
      m_cumulative_tpv   = 0.0;
      m_cumulative_volume= 0.0;
      m_cumulative_tpv2  = 0.0;
      m_session_start    = 0;
      m_initialized      = false;
   }

   ~CVWAP_Indicator() { Deinit(); }

   // Requirements: 5.4
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const double band_multiplier = 1.0)
   {
      m_symbol          = symbol;
      m_timeframe       = timeframe;
      m_band_multiplier = band_multiplier;
      m_initialized     = true;

      // Calcular VWAP inicial
      RecalculateFromSessionStart();
      return true;
   }

   void Deinit()
   {
      m_initialized = false;
   }

   // Recalcula el VWAP desde el inicio de la sesión
   void RecalculateFromSessionStart()
   {
      if(!m_initialized) return;

      m_cumulative_tpv    = 0.0;
      m_cumulative_volume = 0.0;
      m_cumulative_tpv2   = 0.0;

      // Buscar inicio de sesión (00:00 del día actual)
      datetime current_time = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(current_time, dt);
      dt.hour = 0;
      dt.min  = 0;
      dt.sec  = 0;
      m_session_start = StructToTime(dt);

      // Calcular barras desde inicio de sesión
      int session_bars = 0;
      for(int i = iBars(m_symbol, m_timeframe) - 1; i >= 0; i--)
      {
         datetime bar_time = iTime(m_symbol, m_timeframe, i);
         if(bar_time >= m_session_start)
         {
            session_bars++;
         }
      }

      // Acumular VWAP
      for(int i = session_bars - 1; i >= 1; i--)
      {
         datetime bar_time = iTime(m_symbol, m_timeframe, i);
         if(bar_time < m_session_start) continue;

         double tp     = TypicalPrice(i);
         double vol    = (double)iVolume(m_symbol, m_timeframe, i);

         m_cumulative_tpv    += tp * vol;
         m_cumulative_volume += vol;
         m_cumulative_tpv2   += tp * tp * vol;
      }

      UpdateVWAP();
   }

   // Requirements: 5.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      // Verificar si es nueva sesión
      datetime current_time = iTime(m_symbol, m_timeframe, 1);
      MqlDateTime dt;
      TimeToStruct(current_time, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime today_start = StructToTime(dt);

      if(today_start != m_session_start)
      {
         RecalculateFromSessionStart();
         return true;
      }

      // Agregar barra más reciente cerrada
      double tp  = TypicalPrice(1);
      double vol = (double)iVolume(m_symbol, m_timeframe, 1);

      m_cumulative_tpv    += tp * vol;
      m_cumulative_volume += vol;
      m_cumulative_tpv2   += tp * tp * vol;

      UpdateVWAP();
      return true;
   }

   // Actualiza el valor del VWAP y las bandas
   void UpdateVWAP()
   {
      if(m_cumulative_volume <= 0) return;

      m_vwap_value = m_cumulative_tpv / m_cumulative_volume;

      // Calcular varianza para desviación estándar
      double variance = (m_cumulative_tpv2 / m_cumulative_volume)
                        - (m_vwap_value * m_vwap_value);
      m_std_deviation   = (variance > 0) ? MathSqrt(variance) : 0.0;
      m_vwap_upper_band = m_vwap_value + m_band_multiplier * m_std_deviation;
      m_vwap_lower_band = m_vwap_value - m_band_multiplier * m_std_deviation;
   }

   // Getters
   double GetVWAP()       const { return m_vwap_value; }
   double GetUpperBand()  const { return m_vwap_upper_band; }
   double GetLowerBand()  const { return m_vwap_lower_band; }
   double GetStdDev()     const { return m_std_deviation; }

   // Posición del precio respecto al VWAP
   bool IsPriceAboveVWAP(const double price) const { return price > m_vwap_value; }
   bool IsPriceBelowVWAP(const double price) const { return price < m_vwap_value; }

   // Precio en banda superior (posible resistencia)
   bool IsPriceAtUpperBand(const double price) const { return price >= m_vwap_upper_band; }
   // Precio en banda inferior (posible soporte)
   bool IsPriceAtLowerBand(const double price) const { return price <= m_vwap_lower_band; }

   // Distancia normalizada del precio al VWAP (-1.0 a 1.0 aprox.)
   double GetPriceDistanceNormalized(const double price) const
   {
      if(m_std_deviation <= 0) return 0.0;
      return (price - m_vwap_value) / m_std_deviation;
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 4.1: CLASE CVolatility_Monitor                           |
//| Origen: CVolatility_Monitor.mqh                                  |
//+------------------------------------------------------------------+

// Requirements: 6.1, 6.5, 2.1, 2.5, 12.5
// Clase que monitorea la volatilidad del mercado
// Compara la volatilidad actual con la histórica para identificar regímenes
class CVolatility_Monitor
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_atr_period;           // Período del ATR para volatilidad actual
   int             m_historical_period;    // Período para calcular volatilidad histórica
   double          m_current_volatility;   // Volatilidad actual (ATR)
   double          m_average_volatility;   // Volatilidad promedio histórica
   double          m_high_vol_threshold;   // Umbral de alta volatilidad (ratio)
   double          m_low_vol_threshold;    // Umbral de baja volatilidad (ratio)
   double          m_vol_ratio;            // Ratio volatilidad actual / promedio
   bool            m_initialized;
   int             m_atr_handle;
   double          m_atr_buffer[];

public:
   CVolatility_Monitor()
   {
      m_symbol             = _Symbol;
      m_timeframe          = PERIOD_M5;
      m_atr_period         = 14;
      m_historical_period  = 100;
      m_current_volatility = 0.0;
      m_average_volatility = 0.0;
      m_high_vol_threshold = 1.5;
      m_low_vol_threshold  = 0.7;
      m_vol_ratio          = 1.0;
      m_initialized        = false;
      m_atr_handle         = INVALID_HANDLE;
   }

   ~CVolatility_Monitor() { Deinit(); }

   // Requirements: 6.1
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
             const int atr_period = 14, const int historical_period = 100,
             const double high_threshold = 1.5, const double low_threshold = 0.7)
   {
      m_symbol            = symbol;
      m_timeframe         = timeframe;
      m_atr_period        = atr_period;
      m_historical_period = historical_period;
      m_high_vol_threshold = high_threshold;
      m_low_vol_threshold  = low_threshold;

      m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
      if(m_atr_handle == INVALID_HANDLE)
      {
         Print("CVolatility_Monitor::Init() - Error ATR: ", GetLastError());
         return false;
      }

      ArraySetAsSeries(m_atr_buffer, true);
      m_initialized = true;
      return true;
   }

   void Deinit()
   {
      if(m_atr_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atr_handle);
         m_atr_handle = INVALID_HANDLE;
      }
      m_initialized = false;
   }

   // Requirements: 6.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      int bars_needed = m_historical_period + m_atr_period + 1;
      if(CopyBuffer(m_atr_handle, 0, 0, bars_needed, m_atr_buffer) < bars_needed)
      {
         Print("CVolatility_Monitor::OnNewBar() - Error copiando ATR: ", GetLastError());
         return false;
      }

      m_current_volatility = m_atr_buffer[1];

      // Calcular promedio histórico
      double sum = 0.0;
      int count  = 0;
      for(int i = 1; i <= m_historical_period; i++)
      {
         if(m_atr_buffer[i] > 0)
         {
            sum += m_atr_buffer[i];
            count++;
         }
      }

      if(count > 0)
         m_average_volatility = sum / count;

      if(m_average_volatility > 0)
         m_vol_ratio = m_current_volatility / m_average_volatility;
      else
         m_vol_ratio = 1.0;

      return true;
   }

   // Getters
   double GetCurrentVolatility()  const { return m_current_volatility; }
   double GetAverageVolatility()  const { return m_average_volatility; }
   double GetVolatilityRatio()    const { return m_vol_ratio; }
   bool   IsHighVolatility()      const { return m_vol_ratio >= m_high_vol_threshold; }
   bool   IsLowVolatility()       const { return m_vol_ratio <= m_low_vol_threshold; }
   bool   IsNormalVolatility()    const { return !IsHighVolatility() && !IsLowVolatility(); }

   // Puntaje de volatilidad normalizado (0.0 = muy baja, 1.0 = muy alta)
   double GetVolatilityScore() const
   {
      if(m_vol_ratio >= m_high_vol_threshold) return 1.0;
      if(m_vol_ratio <= m_low_vol_threshold)  return 0.0;
      double range = m_high_vol_threshold - m_low_vol_threshold;
      if(range <= 0) return 0.5;
      return (m_vol_ratio - m_low_vol_threshold) / range;
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 4.2: CLASE CVolume_Analyzer                              |
//| Origen: CVolume_Analyzer.mqh                                     |
//+------------------------------------------------------------------+

// Requirements: 6.2, 6.5, 2.1, 2.5, 12.5
// Clase que analiza el volumen de trading
// Detecta anomalías de volumen y confirma la dirección del precio
class CVolume_Analyzer
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_average_period;    // Período para volumen promedio
   double          m_current_volume;    // Volumen de la barra actual cerrada
   double          m_average_volume;    // Volumen promedio histórico
   double          m_volume_ratio;      // Ratio volumen actual / promedio
   double          m_high_vol_threshold;// Umbral de volumen alto
   double          m_low_vol_threshold; // Umbral de volumen bajo
   bool            m_bullish_volume;    // El volumen confirma movimiento alcista
   bool            m_bearish_volume;    // El volumen confirma movimiento bajista
   bool            m_initialized;

   // Calcula si el volumen confirma la dirección del precio
   void AnalyzeVolumeDirection(const int shift = 1)
   {
      double open  = iOpen(m_symbol, m_timeframe, shift);
      double close = iClose(m_symbol, m_timeframe, shift);

      m_bullish_volume = (close > open) && (m_volume_ratio >= m_high_vol_threshold);
      m_bearish_volume = (close < open) && (m_volume_ratio >= m_high_vol_threshold);
   }

public:
   CVolume_Analyzer()
   {
      m_symbol              = _Symbol;
      m_timeframe           = PERIOD_M5;
      m_average_period      = 20;
      m_current_volume      = 0.0;
      m_average_volume      = 0.0;
      m_volume_ratio        = 1.0;
      m_high_vol_threshold  = 1.5;
      m_low_vol_threshold   = 0.5;
      m_bullish_volume      = false;
      m_bearish_volume      = false;
      m_initialized         = false;
   }

   ~CVolume_Analyzer() { Deinit(); }

   // Requirements: 6.2
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
             const int average_period = 20,
             const double high_threshold = 1.5, const double low_threshold = 0.5)
   {
      m_symbol             = symbol;
      m_timeframe          = timeframe;
      m_average_period     = average_period;
      m_high_vol_threshold = high_threshold;
      m_low_vol_threshold  = low_threshold;
      m_initialized        = true;
      return true;
   }

   void Deinit() { m_initialized = false; }

   // Requirements: 6.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      int bars_needed = m_average_period + 2;
      long volume_buf[];
      ArraySetAsSeries(volume_buf, true);

      if(CopyTickVolume(m_symbol, m_timeframe, 0, bars_needed, volume_buf) < bars_needed)
      {
         Print("CVolume_Analyzer::OnNewBar() - Error copiando volumen: ", GetLastError());
         return false;
      }

      m_current_volume = (double)volume_buf[1];

      // Calcular volumen promedio
      double sum = 0.0;
      for(int i = 1; i <= m_average_period; i++)
         sum += (double)volume_buf[i];
      m_average_volume = sum / m_average_period;

      if(m_average_volume > 0)
         m_volume_ratio = m_current_volume / m_average_volume;
      else
         m_volume_ratio = 1.0;

      AnalyzeVolumeDirection();
      return true;
   }

   // Getters
   double GetCurrentVolume()  const { return m_current_volume; }
   double GetAverageVolume()  const { return m_average_volume; }
   double GetVolumeRatio()    const { return m_volume_ratio; }
   bool   IsHighVolume()      const { return m_volume_ratio >= m_high_vol_threshold; }
   bool   IsLowVolume()       const { return m_volume_ratio <= m_low_vol_threshold; }
   bool   IsBullishVolume()   const { return m_bullish_volume; }
   bool   IsBearishVolume()   const { return m_bearish_volume; }

   // Puntaje de volumen normalizado
   double GetVolumeScore() const
   {
      if(m_volume_ratio >= m_high_vol_threshold) return 1.0;
      if(m_volume_ratio <= m_low_vol_threshold)  return 0.0;
      double range = m_high_vol_threshold - m_low_vol_threshold;
      if(range <= 0) return 0.5;
      return (m_volume_ratio - m_low_vol_threshold) / range;
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 4.3: CLASE CMomentum_Detector                            |
//| Origen: CMomentum_Detector.mqh                                   |
//+------------------------------------------------------------------+

// Requirements: 6.3, 6.5, 2.1, 2.5, 12.5
// Clase que detecta el momentum del mercado
// Combina múltiples indicadores para determinar la fuerza y dirección del momentum
class CMomentum_Detector
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_roc_period;        // Período del Rate of Change
   int             m_smooth_period;     // Período de suavizado del momentum
   double          m_momentum_value;    // Valor actual del momentum
   double          m_momentum_prev;     // Valor anterior del momentum
   double          m_momentum_threshold;// Umbral mínimo de momentum significativo
   double          m_momentum_score;    // Puntaje normalizado (-1.0 a 1.0)
   bool            m_initialized;
   int             m_roc_handle;
   int             m_smooth_handle;
   double          m_roc_buffer[];
   double          m_smooth_buffer[];

public:
   CMomentum_Detector()
   {
      m_symbol              = _Symbol;
      m_timeframe           = PERIOD_M5;
      m_roc_period          = 10;
      m_smooth_period       = 3;
      m_momentum_value      = 0.0;
      m_momentum_prev       = 0.0;
      m_momentum_threshold  = 0.001;
      m_momentum_score      = 0.0;
      m_initialized         = false;
      m_roc_handle          = INVALID_HANDLE;
      m_smooth_handle       = INVALID_HANDLE;
   }

   ~CMomentum_Detector() { Deinit(); }

   // Requirements: 6.3
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
             const int roc_period = 10, const int smooth_period = 3,
             const double threshold = 0.001)
   {
      m_symbol             = symbol;
      m_timeframe          = timeframe;
      m_roc_period         = roc_period;
      m_smooth_period      = smooth_period;
      m_momentum_threshold = threshold;

      m_roc_handle = iMomentum(m_symbol, m_timeframe, m_roc_period, PRICE_CLOSE);
      if(m_roc_handle == INVALID_HANDLE)
      {
         Print("CMomentum_Detector::Init() - Error al crear handle Momentum: ", GetLastError());
         return false;
      }

      m_smooth_handle = iMA(m_symbol, m_timeframe, m_smooth_period, 0, MODE_SMA, PRICE_CLOSE);
      if(m_smooth_handle == INVALID_HANDLE)
      {
         Print("CMomentum_Detector::Init() - Error al crear handle MA: ", GetLastError());
         Deinit();
         return false;
      }

      ArraySetAsSeries(m_roc_buffer, true);
      ArraySetAsSeries(m_smooth_buffer, true);
      m_initialized = true;
      return true;
   }

   void Deinit()
   {
      if(m_roc_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_roc_handle);
         m_roc_handle = INVALID_HANDLE;
      }
      if(m_smooth_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_smooth_handle);
         m_smooth_handle = INVALID_HANDLE;
      }
      m_initialized = false;
   }

   // Requirements: 6.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      if(CopyBuffer(m_roc_handle, 0, 0, 3, m_roc_buffer) < 3)
      {
         Print("CMomentum_Detector::OnNewBar() - Error copiando ROC: ", GetLastError());
         return false;
      }

      m_momentum_prev  = m_momentum_value;
      // Normalizar valor de momentum (iMomentum devuelve 100 como base)
      m_momentum_value = m_roc_buffer[1] - 100.0;

      // Calcular puntaje normalizado (-1.0 a 1.0)
      double max_momentum = 5.0; // 5% de movimiento es extremo para XAUUSD M5
      m_momentum_score = MathMax(-1.0, MathMin(1.0, m_momentum_value / max_momentum));

      return true;
   }

   // Getters
   double GetMomentum()      const { return m_momentum_value; }
   double GetMomentumPrev()  const { return m_momentum_prev; }
   double GetMomentumScore() const { return m_momentum_score; }

   // Estados del momentum
   bool IsBullishMomentum()      const { return m_momentum_value >  m_momentum_threshold; }
   bool IsBearishMomentum()      const { return m_momentum_value < -m_momentum_threshold; }
   bool IsNeutralMomentum()      const { return !IsBullishMomentum() && !IsBearishMomentum(); }
   bool IsMomentumIncreasing()   const { return m_momentum_value > m_momentum_prev; }
   bool IsMomentumDecreasing()   const { return m_momentum_value < m_momentum_prev; }

   // Detección de divergencias (precio sube pero momentum baja, y viceversa)
   bool IsBullishDivergence(const double price_change) const
   {
      return (price_change < 0) && (m_momentum_value > m_momentum_prev);
   }
   bool IsBearishDivergence(const double price_change) const
   {
      return (price_change > 0) && (m_momentum_value < m_momentum_prev);
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 4.4: CLASE CSwing_Point_Tracker                          |
//| Origen: CSwing_Point_Tracker.mqh                                 |
//+------------------------------------------------------------------+

// Requirements: 6.4, 6.5, 2.1, 2.5, 12.5
// Clase que rastrea los puntos de swing del mercado (swings highs y lows)
// Identifica niveles clave de soporte y resistencia basados en estructura de precio
class CSwing_Point_Tracker
{
private:
   SSwingPoint m_swing_highs[50];  // Array de swing highs (máx 50)
   SSwingPoint m_swing_lows[50];   // Array de swing lows  (máx 50)
   int         m_high_count;          // Número de swing highs almacenados
   int         m_low_count;           // Número de swing lows almacenados
   int         m_lookback;            // Barras a cada lado para confirmar swing
   string      m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   bool        m_initialized;
   double      m_last_swing_high;     // Último swing high identificado
   double      m_last_swing_low;      // Último swing low identificado
   bool        m_higher_highs;        // Patrón de máximos crecientes
   bool        m_lower_lows;          // Patrón de mínimos decrecientes
   bool        m_higher_lows;         // Patrón de mínimos crecientes (tendencia alcista)
   bool        m_lower_highs;         // Patrón de máximos decrecientes (tendencia bajista)

   // Detecta si existe un swing high en la barra dada
   bool IsSwingHigh(const int bar, const int lookback) const
   {
      double bar_high = iHigh(m_symbol, m_timeframe, bar);
      for(int i = 1; i <= lookback; i++)
      {
         if(iHigh(m_symbol, m_timeframe, bar - i) >= bar_high) return false;
         if(iHigh(m_symbol, m_timeframe, bar + i) >= bar_high) return false;
      }
      return true;
   }

   // Detecta si existe un swing low en la barra dada
   bool IsSwingLow(const int bar, const int lookback) const
   {
      double bar_low = iLow(m_symbol, m_timeframe, bar);
      for(int i = 1; i <= lookback; i++)
      {
         if(iLow(m_symbol, m_timeframe, bar - i) <= bar_low) return false;
         if(iLow(m_symbol, m_timeframe, bar + i) <= bar_low) return false;
      }
      return true;
   }

   // Analiza la estructura de máximos y mínimos
   void AnalyzeSwingStructure()
   {
      m_higher_highs = false;
      m_lower_lows   = false;
      m_higher_lows  = false;
      m_lower_highs  = false;

      if(m_high_count >= 2)
      {
         double prev_high = m_swing_highs[m_high_count - 2].price;
         double curr_high = m_swing_highs[m_high_count - 1].price;
         m_higher_highs = (curr_high > prev_high);
         m_lower_highs  = (curr_high < prev_high);
      }

      if(m_low_count >= 2)
      {
         double prev_low = m_swing_lows[m_low_count - 2].price;
         double curr_low = m_swing_lows[m_low_count - 1].price;
         m_higher_lows = (curr_low > prev_low);
         m_lower_lows  = (curr_low < prev_low);
      }
   }

   // Agrega un swing high al array circular
   void AddSwingHigh(const int bar)
   {
      if(m_high_count >= 50)
      {
         // Desplazar hacia atrás
         for(int i = 0; i < 49; i++)
            m_swing_highs[i] = m_swing_highs[i + 1];
         m_high_count = 49;
      }

      SSwingPoint sp;
      sp.time      = iTime(m_symbol, m_timeframe, bar);
      sp.price     = iHigh(m_symbol, m_timeframe, bar);
      sp.bar_index = bar;
      sp.is_high   = true;
      sp.strength  = m_lookback;
      sp.is_valid  = true;

      m_swing_highs[m_high_count] = sp;
      m_high_count++;
      m_last_swing_high = sp.price;
   }

   // Agrega un swing low al array circular
   void AddSwingLow(const int bar)
   {
      if(m_low_count >= 50)
      {
         for(int i = 0; i < 49; i++)
            m_swing_lows[i] = m_swing_lows[i + 1];
         m_low_count = 49;
      }

      SSwingPoint sp;
      sp.time      = iTime(m_symbol, m_timeframe, bar);
      sp.price     = iLow(m_symbol, m_timeframe, bar);
      sp.bar_index = bar;
      sp.is_high   = false;
      sp.strength  = m_lookback;
      sp.is_valid  = true;

      m_swing_lows[m_low_count] = sp;
      m_low_count++;
      m_last_swing_low = sp.price;
   }

public:
   CSwing_Point_Tracker()
   {
      m_high_count      = 0;
      m_low_count       = 0;
      m_lookback        = 3;
      m_symbol          = _Symbol;
      m_timeframe       = PERIOD_M5;
      m_initialized     = false;
      m_last_swing_high = 0.0;
      m_last_swing_low  = 0.0;
      m_higher_highs    = false;
      m_lower_lows      = false;
      m_higher_lows     = false;
      m_lower_highs     = false;
   }

   ~CSwing_Point_Tracker() { Deinit(); }

   // Requirements: 6.4
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const int lookback = 3)
   {
      m_symbol    = symbol;
      m_timeframe = timeframe;
      m_lookback  = (lookback < 1) ? 1 : lookback;

      // Escaneo inicial de swings históricos
      int total_bars = iBars(m_symbol, m_timeframe);
      int scan_limit = MathMin(total_bars - m_lookback - 1, 200);

      for(int i = scan_limit; i >= m_lookback + 1; i--)
      {
         if(IsSwingHigh(i, m_lookback)) AddSwingHigh(i);
         if(IsSwingLow(i, m_lookback))  AddSwingLow(i);
      }

      AnalyzeSwingStructure();
      m_initialized = true;
      return true;
   }

   void Deinit()
   {
      m_high_count  = 0;
      m_low_count   = 0;
      m_initialized = false;
   }

   // Requirements: 6.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      // Detectar swing en la barra recién cerrada (posición m_lookback + 1)
      int check_bar = m_lookback + 1;
      if(IsSwingHigh(check_bar, m_lookback)) AddSwingHigh(check_bar);
      if(IsSwingLow(check_bar, m_lookback))  AddSwingLow(check_bar);

      AnalyzeSwingStructure();
      return true;
   }

   // Getters de puntos de swing
   double GetLastSwingHigh() const { return m_last_swing_high; }
   double GetLastSwingLow()  const { return m_last_swing_low; }
   int    GetHighCount()     const { return m_high_count; }
   int    GetLowCount()      const { return m_low_count; }

   // Estructura del mercado
   bool HasHigherHighs()  const { return m_higher_highs; }
   bool HasLowerLows()    const { return m_lower_lows; }
   bool HasHigherLows()   const { return m_higher_lows; }
   bool HasLowerHighs()   const { return m_lower_highs; }

   // Tendencia basada en estructura
   bool IsBullishStructure() const { return m_higher_highs && m_higher_lows; }
   bool IsBearishStructure() const { return m_lower_highs && m_lower_lows; }

   // Obtener swing point por índice
   SSwingPoint GetSwingHigh(const int index) const
   {
      if(index < 0 || index >= m_high_count) return SSwingPoint();
      return m_swing_highs[index];
   }

   SSwingPoint GetSwingLow(const int index) const
   {
      if(index < 0 || index >= m_low_count) return SSwingPoint();
      return m_swing_lows[index];
   }

   // Verifica si el precio está cerca de un swing level
   bool IsPriceNearSwingHigh(const double price, const double tolerance_pct = 0.002) const
   {
      if(m_last_swing_high <= 0) return false;
      return MathAbs(price - m_last_swing_high) / m_last_swing_high <= tolerance_pct;
   }

   bool IsPriceNearSwingLow(const double price, const double tolerance_pct = 0.002) const
   {
      if(m_last_swing_low <= 0) return false;
      return MathAbs(price - m_last_swing_low) / m_last_swing_low <= tolerance_pct;
   }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 5.1: CLASE CStatic_Drawdown_Monitor                      |
//| Origen: CStatic_Drawdown_Monitor.mqh                             |
//+------------------------------------------------------------------+

// Requirements: 7.2, 7.5, 2.1, 2.5, 12.5
// Clase que monitorea el drawdown de la cuenta
// Detiene el trading cuando el drawdown excede los límites configurados
class CStatic_Drawdown_Monitor
{
private:
   double m_max_drawdown_pct;        // Porcentaje máximo de drawdown permitido
   double m_daily_max_drawdown_pct;  // Porcentaje máximo de drawdown diario
   double m_initial_balance;         // Balance inicial de referencia
   double m_daily_balance_start;     // Balance al inicio del día
   double m_peak_balance;            // Balance pico (máximo histórico)
   double m_current_drawdown_pct;    // Drawdown actual respecto al pico
   double m_daily_drawdown_pct;      // Drawdown diario respecto al inicio del día
   bool   m_trading_allowed;         // Indica si el trading está permitido
   bool   m_daily_limit_hit;         // Límite diario alcanzado
   bool   m_total_limit_hit;         // Límite total alcanzado
   bool   m_initialized;
   datetime m_last_day_check;        // Última verificación de día

public:
   CStatic_Drawdown_Monitor()
   {
      m_max_drawdown_pct       = 10.0;
      m_daily_max_drawdown_pct = 5.0;
      m_initial_balance        = 0.0;
      m_daily_balance_start    = 0.0;
      m_peak_balance           = 0.0;
      m_current_drawdown_pct   = 0.0;
      m_daily_drawdown_pct     = 0.0;
      m_trading_allowed        = true;
      m_daily_limit_hit        = false;
      m_total_limit_hit        = false;
      m_initialized            = false;
      m_last_day_check         = 0;
   }

   ~CStatic_Drawdown_Monitor() { Deinit(); }

   // Requirements: 7.2
   bool Init(const double max_drawdown_pct = 10.0, const double daily_max_drawdown_pct = 5.0)
   {
      if(max_drawdown_pct <= 0 || daily_max_drawdown_pct <= 0)
      {
         Print("CStatic_Drawdown_Monitor::Init() - Porcentajes de drawdown inválidos");
         return false;
      }

      m_max_drawdown_pct       = max_drawdown_pct;
      m_daily_max_drawdown_pct = daily_max_drawdown_pct;
      m_initial_balance        = AccountInfoDouble(ACCOUNT_BALANCE);
      m_daily_balance_start    = m_initial_balance;
      m_peak_balance           = m_initial_balance;
      m_trading_allowed        = true;
      m_last_day_check         = TimeCurrent();
      m_initialized            = true;
      return true;
   }

   void Deinit() { m_initialized = false; }

   // Requirements: 7.5
   bool OnNewBar()
   {
      if(!m_initialized) return false;

      // Usar SOLO balance cerrado — la equity fluctúa con posiciones abiertas
      // y dispara falsos límites de drawdown
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Verificar si es un nuevo día
      datetime current_time = TimeCurrent();
      MqlDateTime now, last;
      TimeToStruct(current_time, now);
      TimeToStruct(m_last_day_check, last);
      if(now.day != last.day || now.mon != last.mon || now.year != last.year)
      {
         m_daily_balance_start = current_balance;
         m_daily_limit_hit     = false;
         m_last_day_check      = current_time;
         Print("CStatic_Drawdown_Monitor: Nuevo día — balance diario reset: ", current_balance);
      }

      // Actualizar pico de balance (solo balance cerrado)
      if(current_balance > m_peak_balance)
         m_peak_balance = current_balance;

      // Calcular drawdowns sobre balance cerrado
      if(m_peak_balance > 0)
         m_current_drawdown_pct = (m_peak_balance - current_balance) / m_peak_balance * 100.0;

      if(m_daily_balance_start > 0)
         m_daily_drawdown_pct = (m_daily_balance_start - current_balance) / m_daily_balance_start * 100.0;

      // Verificar límites
      m_daily_limit_hit = (m_daily_drawdown_pct >= m_daily_max_drawdown_pct);
      m_total_limit_hit = (m_current_drawdown_pct >= m_max_drawdown_pct);

      m_trading_allowed = !(m_daily_limit_hit || m_total_limit_hit);

      if(m_daily_limit_hit)
         Print("DrawdownMonitor: LÍMITE DIARIO: ",
               DoubleToString(m_daily_drawdown_pct, 2), "% >= ",
               DoubleToString(m_daily_max_drawdown_pct, 2), "%");
      if(m_total_limit_hit)
         Print("DrawdownMonitor: LÍMITE TOTAL: ",
               DoubleToString(m_current_drawdown_pct, 2), "% >= ",
               DoubleToString(m_max_drawdown_pct, 2), "%");

      return true;
   }

   // Getters
   bool   IsTradingAllowed()        const { return m_trading_allowed; }
   bool   IsDailyLimitHit()         const { return m_daily_limit_hit; }
   bool   IsTotalLimitHit()         const { return m_total_limit_hit; }
   double GetCurrentDrawdownPct()   const { return m_current_drawdown_pct; }
   double GetDailyDrawdownPct()     const { return m_daily_drawdown_pct; }
   double GetPeakBalance()          const { return m_peak_balance; }
   double GetMaxDrawdownPct()       const { return m_max_drawdown_pct; }
   double GetDailyMaxDrawdownPct()  const { return m_daily_max_drawdown_pct; }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 5.2: CLASE CHysteresis_Controller                        |
//| Origen: CHysteresis_Controller.mqh                               |
//+------------------------------------------------------------------+

// Requirements: 7.1, 7.4, 7.5, 2.1, 2.5, 12.5
// Clase que implementa histéresis en las transiciones de estado FSM
// Previene oscilaciones rápidas entre estados (ruido de mercado)
class CHysteresis_Controller
{
private:
   SHysteresisConfig m_config;           // Configuración de histéresis
   EState            m_current_state;    // Estado actual
   EState            m_pending_state;    // Estado pendiente de confirmación
   int               m_confirmation_count; // Barras de confirmación acumuladas
   double            m_entry_score;      // Puntaje acumulado para entrar al estado
   double            m_exit_score;       // Puntaje acumulado para salir del estado
   bool              m_state_locked;     // Estado bloqueado durante confirmación
   bool              m_initialized;

   // Aplica filtro de ruido: retorna true si el cambio de puntaje es significativo
   bool PassesNoiseFilter(const double new_score, const double old_score) const
   {
      if(m_config.noise_filter <= 0) return true;
      return MathAbs(new_score - old_score) >= m_config.noise_filter;
   }

public:
   CHysteresis_Controller()
   {
      m_current_state      = STATE_NEUTRAL;
      m_pending_state      = STATE_NEUTRAL;
      m_confirmation_count = 0;
      m_entry_score        = 0.0;
      m_exit_score         = 0.0;
      m_state_locked       = false;
      m_initialized        = false;
   }

   ~CHysteresis_Controller() { Deinit(); }

   // Requirements: 7.1
   bool Init(const SHysteresisConfig &config)
   {
      if(config.entry_threshold <= 0 || config.entry_threshold > 1.0 ||
         config.exit_threshold  <= 0 || config.exit_threshold  > 1.0)
      {
         Print("CHysteresis_Controller::Init() - Umbrales fuera de rango (0,1]");
         return false;
      }
      if(config.exit_threshold >= config.entry_threshold)
      {
         Print("CHysteresis_Controller::Init() - exit_threshold debe ser menor que entry_threshold");
         return false;
      }

      m_config      = config;
      m_initialized = true;
      return true;
   }

   void Deinit()
   {
      m_current_state      = STATE_NEUTRAL;
      m_confirmation_count = 0;
      m_initialized        = false;
   }

   // Requirements: 7.5
   // Evalúa si se debe realizar una transición de estado
   // raw_score: puntaje crudo entre 0.0 y 1.0
   // target_state: estado al que se quiere transicionar
   // Retorna el estado resultante después de aplicar histéresis
   EState EvaluateTransition(const double raw_score, const EState target_state)
   {
      if(!m_initialized) return m_current_state;

      if(!PassesNoiseFilter(raw_score, m_entry_score)) return m_current_state;

      // Actualizar puntaje de entrada/salida
      m_entry_score = raw_score;

      // --- Lógica de ENTRADA al estado objetivo ---
      if(m_current_state != target_state)
      {
         if(raw_score >= m_config.entry_threshold)
         {
            if(m_pending_state != target_state)
            {
               m_pending_state      = target_state;
               m_confirmation_count = 0;
            }
            m_confirmation_count++;

            if(m_confirmation_count >= m_config.confirmation_bars)
            {
               m_current_state      = target_state;
               m_confirmation_count = 0;
               m_pending_state      = target_state;
            }
         }
         else
         {
            // Reset si el puntaje cae antes de confirmar
            m_confirmation_count = 0;
            m_pending_state      = m_current_state;
         }
      }
      // --- Lógica de SALIDA del estado actual ---
      else
      {
         if(raw_score < m_config.exit_threshold)
         {
            // Salida inmediata cuando cae por debajo del umbral de salida
            m_current_state      = STATE_NEUTRAL;
            m_confirmation_count = 0;
            m_pending_state      = STATE_NEUTRAL;
         }
      }

      return m_current_state;
   }

   // Reset forzado al estado neutral
   void ForceReset()
   {
      m_current_state      = STATE_NEUTRAL;
      m_pending_state      = STATE_NEUTRAL;
      m_confirmation_count = 0;
      m_entry_score        = 0.0;
      m_exit_score         = 0.0;
   }

   // Getters
   EState GetCurrentState()      const { return m_current_state; }
   EState GetPendingState()      const { return m_pending_state; }
   int    GetConfirmationCount() const { return m_confirmation_count; }
   double GetEntryScore()        const { return m_entry_score; }
   bool   IsStateLocked()        const { return m_state_locked; }
   SHysteresisConfig GetConfig() const { return m_config; }

   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 5.3: CLASE CFSM_Manager                                  |
//| Origen: CFSM_Manager.mqh                                         |
//+------------------------------------------------------------------+

// Requirements: 7.3, 7.4, 7.5, 2.1, 2.5, 12.5
// Clase principal que gestiona la Máquina de Estados Finitos (FSM)
// Coordina todos los componentes y determina el estado del sistema
class CFSM_Manager
{
private:
   // Punteros a componentes (no propietarios - se pasan desde fuera)
   CATR_Calculator        *m_atr;
   CEMA_Fan               *m_ema_fan;
   CStochastic_Oscillator *m_stochastic;
   CVWAP_Indicator        *m_vwap;
   CVolatility_Monitor    *m_vol_monitor;
   CVolume_Analyzer       *m_vol_analyzer;
   CMomentum_Detector     *m_momentum;
   CSwing_Point_Tracker   *m_swing_tracker;
   CStatic_Drawdown_Monitor *m_drawdown_monitor;
   CHysteresis_Controller *m_hysteresis;

   // Estado de la FSM
   EState   m_current_state;       // Estado actual del sistema
   EState   m_previous_state;      // Estado anterior (para detectar transiciones)
   double   m_trend_score;         // Puntaje de tendencia (0.0 - 1.0)
   double   m_momentum_score;      // Puntaje de momentum (0.0 - 1.0)
   double   m_composite_score;     // Puntaje compuesto combinado
   bool     m_initialized;
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   // Parámetros de ponderación de puntajes
   double m_weight_ema;           // Peso del EMA Fan en tendencia
   double m_weight_swing;         // Peso de swing structure en tendencia
   double m_weight_vwap;          // Peso del VWAP en tendencia
   double m_weight_stochastic;    // Peso del Stochastic en momentum
   double m_weight_momentum;      // Peso del ROC Momentum en momentum
   double m_weight_volume;        // Peso del volumen en momentum

   // Calcula el puntaje de tendencia DIRECCIONAL — score continuo 0..1
   double CalculateTrendScore() const
   {
      double score   = 0.0;
      double weights = 0.0;

      // --- EMA Fan: score gradual según cuántas EMAs están ordenadas ---
      // Más granular que GetTrendStrength() que devuelve solo -1/0/+1
      if(m_ema_fan != NULL && m_ema_fan.IsInitialized())
      {
         // Contar pares de EMAs en orden bull (rápida > lenta)
         int bull_pairs = 0;
         int total_pairs = 0;
         for(int i = 0; i < 4; i++)
         {
            double e1 = m_ema_fan.GetEMA(i);
            double e2 = m_ema_fan.GetEMA(i + 1);
            if(e1 > 0 && e2 > 0)
            {
               total_pairs++;
               if(e1 > e2) bull_pairs++;
            }
         }
         double ema_score = (total_pairs > 0) ? (double)bull_pairs / total_pairs : 0.5;
         score   += ema_score * m_weight_ema;
         weights += m_weight_ema;
      }

      // --- VWAP: binario pero con zona neutral para evitar señales en borde ---
      if(m_vwap != NULL && m_vwap.IsInitialized())
      {
         double close_price = iClose(m_symbol, m_timeframe, 1);
         double vwap_val    = m_vwap.GetVWAP();
         double atr_ref     = (m_atr != NULL) ? m_atr.GetATR() : 0.0;
         double vwap_score  = 0.5; // neutral por defecto
         if(atr_ref > 0)
         {
            double dist = (close_price - vwap_val) / atr_ref;
            // Solo score claro si precio está al menos 0.2 ATR del VWAP
            if(dist >  0.2) vwap_score = 0.5 + MathMin(0.5, dist * 0.25);
            if(dist < -0.2) vwap_score = 0.5 + MathMax(-0.5, dist * 0.25);
         }
         else
         {
            vwap_score = m_vwap.IsPriceAboveVWAP(close_price) ? 0.7 : 0.3;
         }
         score   += vwap_score * m_weight_vwap;
         weights += m_weight_vwap;
      }

      // --- Swing Structure: HH+HL alcista, LH+LL bajista ---
      if(m_swing_tracker != NULL && m_swing_tracker.IsInitialized())
      {
         int swing_pts = 0;
         if(m_swing_tracker.HasHigherHighs()) swing_pts++;
         if(m_swing_tracker.HasHigherLows())  swing_pts++;
         if(m_swing_tracker.HasLowerHighs())  swing_pts--;
         if(m_swing_tracker.HasLowerLows())   swing_pts--;
         double swing_score = (swing_pts + 2.0) / 4.0;
         score   += swing_score * m_weight_swing;
         weights += m_weight_swing;
      }

      return (weights > 0) ? MathMax(0.0, MathMin(1.0, score / weights)) : 0.5;
   }

   // Calcula el puntaje de momentum DIRECCIONAL — score continuo 0..1
   double CalculateMomentumScore() const
   {
      double score   = 0.0;
      double weights = 0.0;

      // --- Stochastic: posición de %K con bonus por cruce desde zona extrema ---
      if(m_stochastic != NULL && m_stochastic.IsInitialized())
      {
         double k = m_stochastic.GetK();
         // Score base: posición de %K en [0,100] → [0,1]
         double pos_score = k / 100.0;
         // Bonus fuerte por cruce desde zonas extremas (señal más fiable)
         if(m_stochastic.IsBullishCrossFromOversold())     pos_score = MathMin(1.0, pos_score + 0.20);
         else if(m_stochastic.IsBearishCrossFromOverbought()) pos_score = MathMax(0.0, pos_score - 0.20);
         else if(m_stochastic.IsBullishCross())            pos_score = MathMin(1.0, pos_score + 0.08);
         else if(m_stochastic.IsBearishCross())            pos_score = MathMax(0.0, pos_score - 0.08);
         score   += pos_score * m_weight_stochastic;
         weights += m_weight_stochastic;
      }

      // --- ROC Momentum: normalizar a rango real de XAUUSD M5 ---
      // XAUUSD M5 rara vez supera 0.3% de ROC — calibrar correctamente
      if(m_momentum != NULL && m_momentum.IsInitialized())
      {
         double mv = m_momentum.GetMomentum(); // ya es % relativo (valor - 100)
         double max_roc = 0.5; // 0.5% es extremo en XAUUSD M5
         double norm = MathMax(-1.0, MathMin(1.0, mv / max_roc));
         double mom_score = (norm + 1.0) / 2.0;
         // Bonus por aceleración
         if(m_momentum.IsMomentumIncreasing() && mv > 0) mom_score = MathMin(1.0, mom_score + 0.05);
         if(m_momentum.IsMomentumDecreasing() && mv < 0) mom_score = MathMax(0.0, mom_score - 0.05);
         score   += mom_score * m_weight_momentum;
         weights += m_weight_momentum;
      }

      // --- Volumen: confirma dirección (bullish/bearish volume) ---
      if(m_vol_analyzer != NULL && m_vol_analyzer.IsInitialized())
      {
         double vol_ratio = m_vol_analyzer.GetVolumeRatio();
         double vol_score = 0.5;
         double vol_strength = MathMin(1.0, (vol_ratio - 1.0));
         if(m_vol_analyzer.IsBullishVolume() && vol_ratio > 1.0)
            vol_score = 0.5 + 0.45 * vol_strength;
         else if(m_vol_analyzer.IsBearishVolume() && vol_ratio > 1.0)
            vol_score = 0.5 - 0.45 * vol_strength;
         // Volumen bajo o normal sin dirección → neutral (0.5)
         score   += vol_score * m_weight_volume;
         weights += m_weight_volume;
      }

      return (weights > 0) ? MathMax(0.0, MathMin(1.0, score / weights)) : 0.5;
   }

   // Determina el estado objetivo — umbrales más exigentes para señales de mayor calidad
   EState DetermineTargetState(const double trend_score, const double momentum_score) const
   {
      // Umbrales más altos: 0.63 tendencia, 0.61 momentum — menos señales pero más fiables
      bool trend_bull    = (trend_score    >= 0.63);
      bool trend_bear    = (trend_score    <= 0.37);
      bool momentum_bull = (momentum_score >= 0.61);
      bool momentum_bear = (momentum_score <= 0.39);

      if(trend_bull && momentum_bull) return STATE_CONFIRMED;
      if(trend_bear && momentum_bear) return STATE_CONFIRMED;
      if(trend_bull || trend_bear)    return STATE_TRENDING;
      if(momentum_bull || momentum_bear) return STATE_MOMENTUM;
      return STATE_NEUTRAL;
   }

   // Determina si el composite score CONFIRMADO es alcista o bajista
   // Usado externamente para saber la dirección del estado CONFIRMED
   bool IsConfirmedBullish() const
   {
      return (m_trend_score >= 0.60 && m_momentum_score >= 0.58);
   }
   bool IsConfirmedBearish() const
   {
      return (m_trend_score <= 0.40 && m_momentum_score <= 0.42);
   }

public:
   CFSM_Manager()
   {
      m_atr              = NULL;
      m_ema_fan          = NULL;
      m_stochastic       = NULL;
      m_vwap             = NULL;
      m_vol_monitor      = NULL;
      m_vol_analyzer     = NULL;
      m_momentum         = NULL;
      m_swing_tracker    = NULL;
      m_drawdown_monitor = NULL;
      m_hysteresis       = NULL;
      m_current_state    = STATE_NEUTRAL;
      m_previous_state   = STATE_NEUTRAL;
      m_trend_score      = 0.0;
      m_momentum_score   = 0.0;
      m_composite_score  = 0.0;
      m_initialized      = false;
      m_symbol           = _Symbol;
      m_timeframe        = PERIOD_M5;

      // Pesos por defecto
      m_weight_ema        = 0.40;
      m_weight_swing      = 0.30;
      m_weight_vwap       = 0.30;
      m_weight_stochastic = 0.40;
      m_weight_momentum   = 0.35;
      m_weight_volume     = 0.25;
   }

   ~CFSM_Manager() { Deinit(); }

   // Requirements: 7.3
   // Inicializa el FSM Manager con todos los componentes
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
             CATR_Calculator        *atr,
             CEMA_Fan               *ema_fan,
             CStochastic_Oscillator *stochastic,
             CVWAP_Indicator        *vwap,
             CVolatility_Monitor    *vol_monitor,
             CVolume_Analyzer       *vol_analyzer,
             CMomentum_Detector     *momentum,
             CSwing_Point_Tracker   *swing_tracker,
             CStatic_Drawdown_Monitor *drawdown_monitor,
             CHysteresis_Controller *hysteresis)
   {
      m_symbol    = symbol;
      m_timeframe = timeframe;

      // Verificar componentes mínimos requeridos
      if(atr == NULL || ema_fan == NULL || hysteresis == NULL)
      {
         Print("CFSM_Manager::Init() - Componentes mínimos requeridos son NULL");
         return false;
      }

      m_atr              = atr;
      m_ema_fan          = ema_fan;
      m_stochastic       = stochastic;
      m_vwap             = vwap;
      m_vol_monitor      = vol_monitor;
      m_vol_analyzer     = vol_analyzer;
      m_momentum         = momentum;
      m_swing_tracker    = swing_tracker;
      m_drawdown_monitor = drawdown_monitor;
      m_hysteresis       = hysteresis;

      m_initialized = true;
      Print("CFSM_Manager::Init() - Inicialización exitosa");
      return true;
   }

   void Deinit()
   {
      // FSM Manager no es propietario de los componentes, no los libera
      m_atr              = NULL;
      m_ema_fan          = NULL;
      m_stochastic       = NULL;
      m_vwap             = NULL;
      m_vol_monitor      = NULL;
      m_vol_analyzer     = NULL;
      m_momentum         = NULL;
      m_swing_tracker    = NULL;
      m_drawdown_monitor = NULL;
      m_hysteresis       = NULL;
      m_initialized      = false;
   }

   // Requirements: 7.5
   // Evalúa las transiciones de estado basadas en las condiciones actuales del mercado
   EState EvaluateTransitions()
   {
      if(!m_initialized) return STATE_NEUTRAL;

      // Verificar si el trading está permitido por drawdown
      if(m_drawdown_monitor != NULL && m_drawdown_monitor.IsInitialized())
      {
         if(!m_drawdown_monitor.IsTradingAllowed())
         {
            if(m_current_state != STATE_NEUTRAL)
            {
               Print("CFSM_Manager: Trading bloqueado por drawdown. Forzando estado NEUTRAL.");
               m_hysteresis.ForceReset();
               m_previous_state = m_current_state;
               m_current_state  = STATE_NEUTRAL;
            }
            return STATE_NEUTRAL;
         }
      }

      // Calcular puntajes
      m_trend_score    = CalculateTrendScore();
      m_momentum_score = CalculateMomentumScore();
      m_composite_score = (m_trend_score + m_momentum_score) / 2.0;

      // Determinar estado objetivo
      EState target_state = DetermineTargetState(m_trend_score, m_momentum_score);

      // Aplicar histéresis
      m_previous_state = m_current_state;
      m_current_state  = m_hysteresis.EvaluateTransition(m_composite_score, target_state);

      // Log de transiciones
      if(m_current_state != m_previous_state)
      {
         string state_names[] = {"NEUTRAL", "MOMENTUM", "TRENDING", "CONFIRMED"};
         Print("CFSM_Manager: Transición de estado: ",
               state_names[m_previous_state], " -> ", state_names[m_current_state],
               " | Trend: ", DoubleToString(m_trend_score, 3),
               " | Momentum: ", DoubleToString(m_momentum_score, 3));
      }

      return m_current_state;
   }

   // Actualiza todos los componentes en nueva barra
   bool UpdateComponents()
   {
      if(!m_initialized) return false;

      bool all_ok = true;

      if(m_atr           != NULL && !m_atr.OnNewBar())           { Print("CFSM_Manager: Error actualizando ATR");           all_ok = false; }
      if(m_ema_fan       != NULL && !m_ema_fan.OnNewBar())       { Print("CFSM_Manager: Error actualizando EMA Fan");       all_ok = false; }
      if(m_stochastic    != NULL && !m_stochastic.OnNewBar())    { Print("CFSM_Manager: Error actualizando Stochastic");    all_ok = false; }
      if(m_vwap          != NULL && !m_vwap.OnNewBar())          { Print("CFSM_Manager: Error actualizando VWAP");          all_ok = false; }
      if(m_vol_monitor   != NULL && !m_vol_monitor.OnNewBar())   { Print("CFSM_Manager: Error actualizando Vol Monitor");   all_ok = false; }
      if(m_vol_analyzer  != NULL && !m_vol_analyzer.OnNewBar())  { Print("CFSM_Manager: Error actualizando Vol Analyzer");  all_ok = false; }
      if(m_momentum      != NULL && !m_momentum.OnNewBar())      { Print("CFSM_Manager: Error actualizando Momentum");      all_ok = false; }
      if(m_swing_tracker != NULL && !m_swing_tracker.OnNewBar()) { Print("CFSM_Manager: Error actualizando Swing Tracker"); all_ok = false; }
      if(m_drawdown_monitor != NULL) m_drawdown_monitor.OnNewBar();

      return all_ok;
   }

   // Getters de estado
   EState GetCurrentState()    const { return m_current_state; }
   EState GetPreviousState()   const { return m_previous_state; }
   double GetTrendScore()      const { return m_trend_score; }
   double GetMomentumScore()   const { return m_momentum_score; }
   double GetCompositeScore()  const { return m_composite_score; }
   bool   IsInitialized()      const { return m_initialized; }

   // Verifica si hubo transición en el último tick
   bool HadStateTransition()   const { return m_current_state != m_previous_state; }

   // Estado específico
   bool IsNeutral()    const { return m_current_state == STATE_NEUTRAL;   }
   bool IsTrending()   const { return m_current_state == STATE_TRENDING;  }
   bool HasMomentum()  const { return m_current_state == STATE_MOMENTUM;  }
   bool IsConfirmed()  const { return m_current_state == STATE_CONFIRMED; }

   // Dirección del mercado según scores — independiente del estado FSM
   // Retorna: 1=alcista, -1=bajista, 0=neutral/mixto
   int GetMarketDirection() const
   {
      bool bull = (m_trend_score >= 0.63 && m_momentum_score >= 0.61);
      bool bear = (m_trend_score <= 0.37 && m_momentum_score <= 0.39);
      if(bull && !bear) return  1;
      if(bear && !bull) return -1;
      return 0;
   }

   // Configurar pesos de puntajes
   void SetTrendWeights(const double ema, const double swing, const double vwap)
   {
      m_weight_ema   = ema;
      m_weight_swing = swing;
      m_weight_vwap  = vwap;
   }

   void SetMomentumWeights(const double stochastic, const double momentum, const double volume)
   {
      m_weight_stochastic = stochastic;
      m_weight_momentum   = momentum;
      m_weight_volume     = volume;
   }

   // Acceso a componentes (solo lectura)
   const CATR_Calculator        *GetATR()           const { return m_atr; }
   const CEMA_Fan               *GetEMAFan()         const { return m_ema_fan; }
   const CStochastic_Oscillator *GetStochastic()     const { return m_stochastic; }
   const CVWAP_Indicator        *GetVWAP()           const { return m_vwap; }
   const CVolatility_Monitor    *GetVolMonitor()     const { return m_vol_monitor; }
   const CVolume_Analyzer       *GetVolAnalyzer()    const { return m_vol_analyzer; }
   const CMomentum_Detector     *GetMomentum()       const { return m_momentum; }
   const CSwing_Point_Tracker   *GetSwingTracker()   const { return m_swing_tracker; }
   const CStatic_Drawdown_Monitor *GetDrawdownMonitor() const { return m_drawdown_monitor; }
};

//+------------------------------------------------------------------+
//| SECCIÓN 6: PARÁMETROS DE ENTRADA DEL EA                         |
//+------------------------------------------------------------------+

// --- Configuración General ---
input group "=== Configuración General ===";
input string   InpSymbol           = "";           // Símbolo (vacío = símbolo actual)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;    // Marco temporal principal

// --- Parámetros ATR ---
input group "=== ATR - Average True Range ===";
input int    InpATRPeriod          = 14;           // Período del ATR

// --- Parámetros EMA Fan ---
input group "=== EMA Fan - Abanico de Medias Móviles ===";
input int    InpEMA1Period         = 8;            // EMA 1 (rápida)
input int    InpEMA2Period         = 21;           // EMA 2
input int    InpEMA3Period         = 50;           // EMA 3
input int    InpEMA4Period         = 100;          // EMA 4
input int    InpEMA5Period         = 200;          // EMA 5 (lenta)

// --- Parámetros Stochastic ---
input group "=== Stochastic Oscillator ===";
input int    InpStochKPeriod       = 5;            // Período %K
input int    InpStochDPeriod       = 3;            // Período %D
input int    InpStochSlowing       = 3;            // Desaceleración
input double InpStochOverbought    = 75.0;         // Nivel sobrecompra
input double InpStochOversold      = 25.0;         // Nivel sobreventa

// --- Parámetros VWAP ---
input group "=== VWAP ===";
input double InpVWAPBandMultiplier = 1.5;          // Multiplicador bandas VWAP

// --- Parámetros Volatility Monitor ---
input group "=== Monitor de Volatilidad ===";
input int    InpVolATRPeriod       = 14;           // Período ATR volatilidad
input int    InpVolHistPeriod      = 50;           // Período histórico referencia
input double InpVolHighThreshold   = 2.0;          // Umbral alta volatilidad (bloquea entrada)
input double InpVolLowThreshold    = 0.5;          // Umbral baja volatilidad

// --- Parámetros Volume Analyzer ---
input group "=== Analizador de Volumen ===";
input int    InpVolumeAvgPeriod    = 20;           // Período promedio volumen
input double InpVolumeHighThreshold= 1.3;          // Umbral volumen alto
input double InpVolumeLowThreshold = 0.4;          // Umbral volumen bajo

// --- Parámetros Momentum ---
input group "=== Detector de Momentum ===";
input int    InpMomentumROCPeriod  = 10;           // Período ROC
input int    InpMomentumSmoothPeriod = 3;          // Suavizado
input double InpMomentumThreshold  = 0.001;        // Umbral mínimo

// --- Parámetros Swing Point Tracker ---
input group "=== Rastreador de Swings ===";
input int    InpSwingLookback      = 3;            // Barras confirmación swing

// --- Parámetros Drawdown Monitor ---
input group "=== Monitor de Drawdown ===";
input double InpMaxDrawdownPct     = 15.0;         // Drawdown máximo total (%)
input double InpDailyMaxDrawdownPct= 6.0;          // Drawdown máximo diario (%)

// --- Parámetros Histéresis FSM ---
input group "=== Controlador de Histéresis ===";
input double InpHystEntryThreshold = 0.65;         // Umbral entrada (más exigente)
input double InpHystExitThreshold  = 0.42;         // Umbral salida
input int    InpHystConfirmBars    = 3;            // Barras de confirmación (más estable)
input double InpHystNoiseFilter    = 0.010;        // Filtro de ruido
input bool   InpHystUseAdaptive    = false;        // Umbrales adaptativos

// --- Pesos FSM ---
input group "=== Pesos FSM ===";
input double InpWeightEMA          = 0.50;         // Peso EMA Fan (tendencia principal)
input double InpWeightSwing        = 0.20;         // Peso Swing Structure
input double InpWeightVWAP         = 0.30;         // Peso VWAP
input double InpWeightStochastic   = 0.40;         // Peso Stochastic
input double InpWeightMomentumROC  = 0.35;         // Peso ROC Momentum
input double InpWeightVolume       = 0.25;         // Peso Volumen

// --- Gestión de Riesgo ---
input group "=== Gestión de Riesgo ===";
input double InpRiskPercent          = 0.15;   // Riesgo por operación (% balance) - ULTRA BAJO
input double InpSLMultiplier         = 0.8;    // Stop Loss en ATRs - MUY AJUSTADO
input double InpTPMultiplier         = 2.4;    // Take Profit en ATRs (RR 1:3) - REALISTA
input bool   InpUseBreakEven         = true;   // Activar break-even automático
input double InpBreakEvenATR         = 0.5;    // ATRs de ganancia para mover SL a BE - MUY TEMPRANO
input bool   InpUseTrailingStop      = false;  // Desactivar trailing (deja que TP trabaje)
input double InpTrailingATR          = 1.0;    // ATRs de distancia del trailing stop
input double InpTrailingStepATR      = 0.2;    // ATRs mínimos para mover trailing
input int    InpMaxTradesPerDay      = 1;      // Máximo 1 operación por día - ULTRA CONSERVADOR
input int    InpMinBarsBetweenTrades = 60;     // Mínimo 5 horas entre operaciones
input bool   InpCloseOnNeutral       = true;   // Cerrar en NEUTRAL persistente
input bool   InpCloseOnOpposite      = true;   // Cerrar en señal contraria
input int    InpNeutralBarsToClose   = 2;      // Barras NEUTRAL para cerrar - MUY RÁPIDO
input int    InpSessionStartHour     = 8;      // Hora inicio sesión (servidor)
input int    InpSessionEndHour       = 20;     // Hora fin sesión (servidor)
input int    InpMagicNumber          = 202401; // Magic Number
input string InpTradeComment         = "PSM_EA"; // Comentario órdenes

// --- NUEVOS FILTROS DE CALIDAD ---
input group "=== Filtros de Calidad de Entrada ===";
input double InpMinScoreEntry        = 0.80;   // Score mínimo para entrada - MUY EXIGENTE
input int    InpMaxSpreadPoints      = 25;     // Spread máximo permitido (puntos) - MÁS ESTRICTO
input double InpMaxVolatilityMultiplier = 2.5; // ATR máximo vs promedio - MÁS ESTRICTO
input bool   InpUseTrendFilter       = true;   // Filtro de tendencia dominante (EMA 200)
input int    InpADXPeriod            = 14;     // Período ADX para fuerza de tendencia
input double InpMinADX               = 30.0;   // ADX mínimo para confirmar tendencia - MÁS EXIGENTE
input bool   InpUseSessionFilter     = true;   // Filtrar por sesión de trading
input int    InpSessionStart1        = 8;      // Sesión 1: Inicio (GMT)
input int    InpSessionEnd1          = 11;     // Sesión 1: Fin (GMT) - MÁS CORTO
input int    InpSessionStart2        = 13;     // Sesión 2: Inicio (GMT)
input int    InpSessionEnd2          = 16;     // Sesión 2: Fin (GMT) - MÁS CORTO
input bool   InpAvoidFriday          = true;   // Evitar trading viernes tarde
input int    InpFridayStopHour       = 14;     // Hora de cierre viernes (GMT) - MÁS TEMPRANO

// --- NUEVOS: Price Action & Market Structure ---
input group "=== Price Action & Market Structure ===";
input bool   InpUsePriceActionFilter = true;   // Usar filtro de price action
input bool   InpUseStructureFilter   = true;   // Usar filtro de estructura de mercado
input double InpMinPAScore           = 0.50;   // Score mínimo de price action - MÁS EXIGENTE
input double InpMinStructureScore    = 0.60;   // Score mínimo de estructura - MÁS EXIGENTE
input int    InpStructureLookback    = 12;     // Barras para detectar swing points - MÁS AMPLIO
input bool   InpAvoidSwingLevels     = true;   // Evitar entradas cerca de swing levels
input double InpSwingTolerance       = 0.0015; // Tolerancia para swing levels (0.15%) - MÁS ESTRICTO

//+------------------------------------------------------------------+
//| SECCIÓN 7: VARIABLES GLOBALES DEL EA                             |
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| NUEVAS CLASES INTEGRADAS: Price Action & Market Structure        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Estructura de mercado                                             |
//+------------------------------------------------------------------+
enum ENUM_MARKET_STRUCTURE
{
   STRUCTURE_UPTREND,      // Higher Highs + Higher Lows
   STRUCTURE_DOWNTREND,    // Lower Highs + Lower Lows
   STRUCTURE_RANGING,      // Sin estructura clara
   STRUCTURE_TRANSITION    // Cambio de estructura
};

//+------------------------------------------------------------------+
//| Clase para análisis de price action y patrones de velas          |
//+------------------------------------------------------------------+
class CPrice_Action_Analyzer
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   bool     m_initialized;
   
   // Buffers para análisis
   double   m_open[];
   double   m_high[];
   double   m_low[];
   double   m_close[];
   
public:
   CPrice_Action_Analyzer() : m_initialized(false) {}
   ~CPrice_Action_Analyzer() {}
   
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      
      ArraySetAsSeries(m_open, true);
      ArraySetAsSeries(m_high, true);
      ArraySetAsSeries(m_low, true);
      ArraySetAsSeries(m_close, true);
      
      m_initialized = true;
      return true;
   }
   
   void Deinit() { m_initialized = false; }
   
   bool Update()
   {
      if(!m_initialized) return false;
      
      // Copiar últimas 10 velas para análisis
      if(CopyOpen(m_symbol, m_timeframe, 0, 10, m_open) <= 0) return false;
      if(CopyHigh(m_symbol, m_timeframe, 0, 10, m_high) <= 0) return false;
      if(CopyLow(m_symbol, m_timeframe, 0, 10, m_low) <= 0) return false;
      if(CopyClose(m_symbol, m_timeframe, 0, 10, m_close) <= 0) return false;
      
      return true;
   }
   
   int DetectEngulfing()
   {
      if(!m_initialized) return 0;
      
      double body1 = MathAbs(m_close[1] - m_open[1]);
      double body2 = MathAbs(m_close[2] - m_open[2]);
      
      // Bullish Engulfing
      if(m_close[2] < m_open[2] && m_close[1] > m_open[1] &&
         m_open[1] <= m_close[2] && m_close[1] >= m_open[2] && body1 > body2 * 1.2)
         return 1;
      
      // Bearish Engulfing
      if(m_close[2] > m_open[2] && m_close[1] < m_open[1] &&
         m_open[1] >= m_close[2] && m_close[1] <= m_open[2] && body1 > body2 * 1.2)
         return -1;
      
      return 0;
   }
   
   int DetectPinBar()
   {
      if(!m_initialized) return 0;
      
      double body = MathAbs(m_close[1] - m_open[1]);
      double range = m_high[1] - m_low[1];
      double upper_wick = m_high[1] - MathMax(m_open[1], m_close[1]);
      double lower_wick = MathMin(m_open[1], m_close[1]) - m_low[1];
      
      if(range == 0) return 0;
      
      // Bullish Pin Bar
      if(lower_wick > body * 2.0 && lower_wick > range * 0.6 && upper_wick < body * 0.5)
         return 1;
      
      // Bearish Pin Bar
      if(upper_wick > body * 2.0 && upper_wick > range * 0.6 && lower_wick < body * 0.5)
         return -1;
      
      return 0;
   }
   
   bool IsInsideBar()
   {
      if(!m_initialized) return false;
      return (m_high[1] < m_high[2] && m_low[1] > m_low[2]);
   }
   
   bool IsOutsideBar()
   {
      if(!m_initialized) return false;
      return (m_high[1] > m_high[2] && m_low[1] < m_low[2]);
   }
   
   double GetCandleMomentum()
   {
      if(!m_initialized) return 0.0;
      
      int bullish = 0;
      int bearish = 0;
      
      for(int i = 1; i <= 3; i++)
      {
         if(m_close[i] > m_open[i]) bullish++;
         else if(m_close[i] < m_open[i]) bearish++;
      }
      
      return (double)(bullish - bearish) / 3.0;
   }
   
   int DetectRejection(double level, double tolerance_pct = 0.001)
   {
      if(!m_initialized) return 0;
      
      double tolerance = level * tolerance_pct;
      
      // Bullish rejection
      if(m_low[1] <= level + tolerance && m_low[1] >= level - tolerance &&
         m_close[1] > m_open[1] && m_close[1] > level + tolerance)
         return 1;
      
      // Bearish rejection
      if(m_high[1] >= level - tolerance && m_high[1] <= level + tolerance &&
         m_close[1] < m_open[1] && m_close[1] < level - tolerance)
         return -1;
      
      return 0;
   }
   
   double GetSetupQuality(int direction)
   {
      if(!m_initialized) return 0.0;
      
      double score = 0.0;
      
      int engulfing = DetectEngulfing();
      int pinbar = DetectPinBar();
      
      if(direction == 1)
      {
         if(engulfing == 1) score += 0.15;
         if(pinbar == 1) score += 0.15;
      }
      else if(direction == -1)
      {
         if(engulfing == -1) score += 0.15;
         if(pinbar == -1) score += 0.15;
      }
      
      double momentum = GetCandleMomentum();
      if(direction == 1 && momentum > 0.3) score += 0.20;
      else if(direction == -1 && momentum < -0.3) score += 0.20;
      
      double avg_range = 0;
      for(int i = 2; i <= 5; i++)
         avg_range += (m_high[i] - m_low[i]);
      avg_range /= 4.0;
      
      double current_range = m_high[1] - m_low[1];
      if(current_range > avg_range * 1.2) score += 0.20;
      
      double body_position = 0;
      if(current_range > 0)
         body_position = (m_close[1] - m_low[1]) / current_range;
      
      if(direction == 1 && body_position > 0.7) score += 0.30;
      else if(direction == -1 && body_position < 0.3) score += 0.30;
      
      return MathMin(score, 1.0);
   }
   
   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| Clase para análisis de estructura de mercado                     |
//+------------------------------------------------------------------+
class CMarket_Structure_Analyzer
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   bool     m_initialized;
   
   double   m_last_swing_high;
   double   m_last_swing_low;
   double   m_prev_swing_high;
   double   m_prev_swing_low;
   
   datetime m_last_high_time;
   datetime m_last_low_time;
   
   ENUM_MARKET_STRUCTURE m_structure;
   int      m_lookback;
   
public:
   CMarket_Structure_Analyzer() : m_initialized(false), m_lookback(10) 
   {
      m_last_swing_high = 0;
      m_last_swing_low = 0;
      m_prev_swing_high = 0;
      m_prev_swing_low = 0;
      m_structure = STRUCTURE_RANGING;
   }
   
   ~CMarket_Structure_Analyzer() {}
   
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, int lookback = 10)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_lookback = lookback;
      m_initialized = true;
      return true;
   }
   
   void Deinit() { m_initialized = false; }
   
   bool Update()
   {
      if(!m_initialized) return false;
      
      double new_high = FindSwingHigh(1, m_lookback);
      if(new_high > 0 && new_high != m_last_swing_high)
      {
         m_prev_swing_high = m_last_swing_high;
         m_last_swing_high = new_high;
         m_last_high_time = iTime(m_symbol, m_timeframe, GetSwingHighBar(1, m_lookback));
      }
      
      double new_low = FindSwingLow(1, m_lookback);
      if(new_low > 0 && new_low != m_last_swing_low)
      {
         m_prev_swing_low = m_last_swing_low;
         m_last_swing_low = new_low;
         m_last_low_time = iTime(m_symbol, m_timeframe, GetSwingLowBar(1, m_lookback));
      }
      
      UpdateStructure();
      return true;
   }
   
   double FindSwingHigh(int start_bar, int lookback)
   {
      int highest_bar = start_bar;
      double highest = iHigh(m_symbol, m_timeframe, start_bar);
      
      for(int i = start_bar; i < start_bar + lookback * 2; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         if(high > highest)
         {
            highest = high;
            highest_bar = i;
         }
      }
      
      bool is_swing = true;
      for(int i = highest_bar - lookback; i < highest_bar + lookback; i++)
      {
         if(i == highest_bar) continue;
         if(i < 0) continue;
         
         if(iHigh(m_symbol, m_timeframe, i) > highest)
         {
            is_swing = false;
            break;
         }
      }
      
      return is_swing ? highest : 0;
   }
   
   double FindSwingLow(int start_bar, int lookback)
   {
      int lowest_bar = start_bar;
      double lowest = iLow(m_symbol, m_timeframe, start_bar);
      
      for(int i = start_bar; i < start_bar + lookback * 2; i++)
      {
         double low = iLow(m_symbol, m_timeframe, i);
         if(low < lowest)
         {
            lowest = low;
            lowest_bar = i;
         }
      }
      
      bool is_swing = true;
      for(int i = lowest_bar - lookback; i < lowest_bar + lookback; i++)
      {
         if(i == lowest_bar) continue;
         if(i < 0) continue;
         
         if(iLow(m_symbol, m_timeframe, i) < lowest)
         {
            is_swing = false;
            break;
         }
      }
      
      return is_swing ? lowest : 0;
   }
   
   int GetSwingHighBar(int start_bar, int lookback)
   {
      int highest_bar = start_bar;
      double highest = iHigh(m_symbol, m_timeframe, start_bar);
      
      for(int i = start_bar; i < start_bar + lookback * 2; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         if(high > highest)
         {
            highest = high;
            highest_bar = i;
         }
      }
      return highest_bar;
   }
   
   int GetSwingLowBar(int start_bar, int lookback)
   {
      int lowest_bar = start_bar;
      double lowest = iLow(m_symbol, m_timeframe, start_bar);
      
      for(int i = start_bar; i < start_bar + lookback * 2; i++)
      {
         double low = iLow(m_symbol, m_timeframe, i);
         if(low < lowest)
         {
            lowest = low;
            lowest_bar = i;
         }
      }
      return lowest_bar;
   }
   
   void UpdateStructure()
   {
      if(m_last_swing_high == 0 || m_last_swing_low == 0 ||
         m_prev_swing_high == 0 || m_prev_swing_low == 0)
      {
         m_structure = STRUCTURE_RANGING;
         return;
      }
      
      bool higher_high = (m_last_swing_high > m_prev_swing_high);
      bool higher_low = (m_last_swing_low > m_prev_swing_low);
      bool lower_high = (m_last_swing_high < m_prev_swing_high);
      bool lower_low = (m_last_swing_low < m_prev_swing_low);
      
      if(higher_high && higher_low)
      {
         if(m_structure == STRUCTURE_DOWNTREND)
            m_structure = STRUCTURE_TRANSITION;
         else
            m_structure = STRUCTURE_UPTREND;
      }
      else if(lower_high && lower_low)
      {
         if(m_structure == STRUCTURE_UPTREND)
            m_structure = STRUCTURE_TRANSITION;
         else
            m_structure = STRUCTURE_DOWNTREND;
      }
      else
      {
         m_structure = STRUCTURE_RANGING;
      }
   }
   
   ENUM_MARKET_STRUCTURE GetStructure() const { return m_structure; }
   bool IsUptrend() const { return m_structure == STRUCTURE_UPTREND; }
   bool IsDowntrend() const { return m_structure == STRUCTURE_DOWNTREND; }
   bool IsRanging() const { return m_structure == STRUCTURE_RANGING; }
   bool IsTransition() const { return m_structure == STRUCTURE_TRANSITION; }
   
   double GetLastSwingHigh() const { return m_last_swing_high; }
   double GetLastSwingLow() const { return m_last_swing_low; }
   
   bool IsNearSwingHigh(double price, double tolerance_pct = 0.002) const
   {
      if(m_last_swing_high == 0) return false;
      double tolerance = m_last_swing_high * tolerance_pct;
      return (MathAbs(price - m_last_swing_high) <= tolerance);
   }
   
   bool IsNearSwingLow(double price, double tolerance_pct = 0.002) const
   {
      if(m_last_swing_low == 0) return false;
      double tolerance = m_last_swing_low * tolerance_pct;
      return (MathAbs(price - m_last_swing_low) <= tolerance);
   }
   
   double GetStructureScore(int direction) const
   {
      if(direction == 1)
      {
         if(m_structure == STRUCTURE_UPTREND) return 1.0;
         if(m_structure == STRUCTURE_TRANSITION) return 0.5;
         if(m_structure == STRUCTURE_RANGING) return 0.3;
         return 0.0;
      }
      else if(direction == -1)
      {
         if(m_structure == STRUCTURE_DOWNTREND) return 1.0;
         if(m_structure == STRUCTURE_TRANSITION) return 0.5;
         if(m_structure == STRUCTURE_RANGING) return 0.3;
         return 0.0;
      }
      
      return 0.0;
   }
   
   int DetectBreakOfStructure()
   {
      double current_price = iClose(m_symbol, m_timeframe, 0);
      
      if(m_structure == STRUCTURE_DOWNTREND && current_price > m_last_swing_high)
         return 1;
      
      if(m_structure == STRUCTURE_UPTREND && current_price < m_last_swing_low)
         return -1;
      
      return 0;
   }
   
   bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+

CATR_Calculator          *g_atr              = NULL;
CEMA_Fan                 *g_ema_fan          = NULL;
CStochastic_Oscillator   *g_stochastic       = NULL;
CVWAP_Indicator          *g_vwap             = NULL;
CVolatility_Monitor      *g_vol_monitor      = NULL;
CVolume_Analyzer         *g_vol_analyzer     = NULL;
CMomentum_Detector       *g_momentum         = NULL;
CSwing_Point_Tracker     *g_swing_tracker    = NULL;
CStatic_Drawdown_Monitor *g_drawdown_monitor = NULL;
CHysteresis_Controller   *g_hysteresis       = NULL;
CFSM_Manager             *g_fsm_manager      = NULL;

// Nuevos analizadores avanzados
CPrice_Action_Analyzer      *g_price_action     = NULL;
CMarket_Structure_Analyzer  *g_market_structure = NULL;

CTrade        g_trade;
CPositionInfo g_position;

string g_symbol        = "";
int    g_trades_today  = 0;          // Operaciones abiertas hoy
int    g_adx_handle    = INVALID_HANDLE; // Handle para ADX
double g_adx_buffer[];               // Buffer ADX
double g_ema200_handle = INVALID_HANDLE; // Handle EMA 200
double g_ema200_buffer[];            // Buffer EMA 200
datetime g_last_trade_time = 0;      // Tiempo última operación
int    g_consecutive_losses = 0;     // Pérdidas consecutivas
int    g_bars_since_last_trade = 0;  // Barras desde última operación
datetime g_last_trade_day = 0;       // Día de la última operación (para reset diario)

//+------------------------------------------------------------------+
//| SECCIÓN 11: FUNCIONES AUXILIARES DE TRADING                      |
//+------------------------------------------------------------------+

//--- Calcula lote exacto por % de riesgo
double CalculateLotSize(const double sl_points)
{
   if(sl_points <= 0) return 0.0;

   double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money    = balance * InpRiskPercent / 100.0;
   double tick_value    = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size     = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   double point         = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

   if(tick_value <= 0 || tick_size <= 0 || point <= 0) return 0.0;

   double value_per_point = (tick_size > 0) ? (tick_value / tick_size * point) : 0.0;
   if(value_per_point <= 0) return 0.0;

   double lots     = risk_money / (sl_points * value_per_point);
   double lot_step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   double lot_min  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double lot_max  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / lot_step) * lot_step;
   lots = MathMax(lot_min, MathMin(lot_max, lots));

   return NormalizeDouble(lots, 2);
}

//--- Verifica posición abierta del EA
bool HasOpenPosition(bool &is_long)
{
   if(g_position.SelectByMagic(g_symbol, InpMagicNumber))
   {
      is_long = (g_position.PositionType() == POSITION_TYPE_BUY);
      return true;
   }
   return false;
}

//--- Cierra la posición del EA
bool ClosePosition()
{
   if(!g_position.SelectByMagic(g_symbol, InpMagicNumber)) return true;
   ulong ticket = g_position.Ticket();
   bool  result = g_trade.PositionClose(ticket);
   if(!result)
      Print("ClosePosition: Error #", ticket, " cod=", g_trade.ResultRetcode());
   else
      Print("ClosePosition: Cerrada #", ticket,
            " P&L=", DoubleToString(g_position.Profit(), 2));
   return result;
}

//--- Verifica sesión horaria válida (hora del servidor)
bool IsValidTradingSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
}

//--- NUEVO: Verifica sesión de trading óptima (GMT)
bool IsOptimalTradingSession()
{
   if(!InpUseSessionFilter) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;
   
   // Evitar viernes tarde
   if(InpAvoidFriday && dt.day_of_week == 5 && hour >= InpFridayStopHour)
   {
      return false;
   }
   
   // Sesión 1 o Sesión 2
   bool in_session1 = (hour >= InpSessionStart1 && hour < InpSessionEnd1);
   bool in_session2 = (hour >= InpSessionStart2 && hour < InpSessionEnd2);
   
   return (in_session1 || in_session2);
}

//--- NUEVO: Verifica spread máximo permitido
bool IsSpreadAcceptable()
{
   long spread_points = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD);
   if(spread_points > InpMaxSpreadPoints)
   {
      Print("IsSpreadAcceptable: Spread=", spread_points, " > máx=", InpMaxSpreadPoints, " — rechazado");
      return false;
   }
   return true;
}

//--- NUEVO: Verifica volatilidad no extrema
bool IsVolatilityAcceptable()
{
   if(g_vol_monitor == NULL || !g_vol_monitor.IsInitialized()) return true;
   
   double vol_ratio = g_vol_monitor.GetVolatilityRatio();
   if(vol_ratio > InpMaxVolatilityMultiplier)
   {
      Print("IsVolatilityAcceptable: Volatilidad=", DoubleToString(vol_ratio,2), 
            "x > máx=", InpMaxVolatilityMultiplier, "x — rechazado");
      return false;
   }
   return true;
}

//--- NUEVO: Filtro de tendencia dominante (EMA 200 + ADX)
bool PassesTrendFilter(const int direction)
{
   if(!InpUseTrendFilter) return true;
   
   // Actualizar buffers
   if(CopyBuffer(g_ema200_handle, 0, 0, 2, g_ema200_buffer) < 2)
   {
      Print("PassesTrendFilter: Error copiando EMA 200");
      return false;
   }
   if(CopyBuffer(g_adx_handle, 0, 0, 2, g_adx_buffer) < 2)
   {
      Print("PassesTrendFilter: Error copiando ADX");
      return false;
   }
   
   double price = (direction == 1) ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) 
                                    : SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ema200 = g_ema200_buffer[0];
   double adx = g_adx_buffer[0];
   
   // ADX debe confirmar tendencia fuerte
   if(adx < InpMinADX)
   {
      Print("PassesTrendFilter: ADX=", DoubleToString(adx,1), " < mín=", InpMinADX, " — sin tendencia clara");
      return false;
   }
   
   // Solo LONG si precio > EMA 200, solo SHORT si precio < EMA 200
   if(direction == 1 && price < ema200)
   {
      Print("PassesTrendFilter: LONG rechazado — precio ", price, " < EMA200 ", ema200);
      return false;
   }
   if(direction == -1 && price > ema200)
   {
      Print("PassesTrendFilter: SHORT rechazado — precio ", price, " > EMA200 ", ema200);
      return false;
   }
   
   return true;
}

//--- NUEVO: Verifica score mínimo de entrada
bool PassesScoreFilter()
{
   if(g_fsm_manager == NULL || !g_fsm_manager.IsInitialized()) return false;
   
   double trend_score = g_fsm_manager.GetTrendScore();
   double momentum_score = g_fsm_manager.GetMomentumScore();
   
   // Calcular score compuesto (promedio ponderado)
   double composite_score = (trend_score * 0.6) + (momentum_score * 0.4);
   
   if(composite_score < InpMinScoreEntry && composite_score > (1.0 - InpMinScoreEntry))
   {
      Print("PassesScoreFilter: Score=", DoubleToString(composite_score,3), 
            " no alcanza mínimo=", InpMinScoreEntry);
      return false;
   }
   
   return true;
}

//--- NUEVO: Verifica tiempo mínimo entre operaciones
bool PassesTimingFilter()
{
   // Verificar barras mínimas desde última operación
   if(g_bars_since_last_trade < InpMinBarsBetweenTrades)
   {
      Print("PassesTimingFilter: Solo ", g_bars_since_last_trade, 
            " barras desde última operación (mín=", InpMinBarsBetweenTrades, ")");
      return false;
   }
   
   // Verificar máximo de operaciones por día
   if(g_trades_today >= InpMaxTradesPerDay)
   {
      Print("PassesTimingFilter: Máximo diario alcanzado (", g_trades_today, "/", InpMaxTradesPerDay, ")");
      return false;
   }
   
   return true;
}

//--- Resetea contador diario de operaciones si cambió el día
void CheckDailyReset()
{
   datetime now = TimeCurrent();
   MqlDateTime nd, ld;
   TimeToStruct(now, nd);
   TimeToStruct(g_last_trade_day, ld);
   if(nd.day != ld.day || nd.mon != ld.mon)
   {
      g_trades_today = 0;
      g_last_trade_day = now;
      Print("PSM_EA: Reset diario — operaciones del día = 0");
   }
}

//--- Determina dirección del mercado: 1=LONG, -1=SHORT, 0=sin señal
int GetTradeDirection()
{
   // Validaciones básicas
   if(g_fsm_manager == NULL || !g_fsm_manager.IsInitialized()) return 0;
   if(g_fsm_manager.GetCurrentState() != STATE_CONFIRMED) return 0;

   int dir = g_fsm_manager.GetMarketDirection();
   if(dir == 0) return 0;

   // ========== FILTROS DE CALIDAD MEJORADOS ==========
   
   // 1. Verificar score mínimo de entrada
   if(!PassesScoreFilter())
   {
      Print("GetTradeDir: Score insuficiente — rechazado");
      return 0;
   }
   
   // 2. Verificar sesión óptima de trading
   if(!IsOptimalTradingSession())
   {
      Print("GetTradeDir: Fuera de sesión óptima — rechazado");
      return 0;
   }
   
   // 3. Verificar spread aceptable
   if(!IsSpreadAcceptable())
   {
      return 0; // Ya imprime mensaje
   }
   
   // 4. Verificar volatilidad no extrema
   if(!IsVolatilityAcceptable())
   {
      return 0; // Ya imprime mensaje
   }
   
   // 5. Verificar timing entre operaciones
   if(!PassesTimingFilter())
   {
      return 0; // Ya imprime mensaje
   }
   
   // 6. Filtro de tendencia dominante (EMA 200 + ADX)
   if(!PassesTrendFilter(dir))
   {
      return 0; // Ya imprime mensaje
   }

   // 7. Verificar margen mínimo de scores (señal debe ser clara, no borderline)
   double t = g_fsm_manager.GetTrendScore();
   double m = g_fsm_manager.GetMomentumScore();
   double margin = 0.08; // AUMENTADO: mínimo 8% por encima/debajo del umbral
   if(dir ==  1 && (t < 0.63 + margin || m < 0.61 + margin))
   {
      Print("GetTradeDir: Scores muy cerca del umbral — señal débil");
      return 0;
   }
   if(dir == -1 && (t > 0.37 - margin || m > 0.39 - margin))
   {
      Print("GetTradeDir: Scores muy cerca del umbral — señal débil");
      return 0;
   }

   // 8. Filtro de volatilidad extrema (spikes de noticias)
   if(g_vol_monitor != NULL && g_vol_monitor.IsInitialized() && g_vol_monitor.IsHighVolatility())
   {
      Print("GetTradeDir: Volatilidad extrema — ignorando");
      return 0;
   }

   // 9. Filtro de volumen mínimo
   if(g_vol_analyzer != NULL && g_vol_analyzer.IsInitialized() && g_vol_analyzer.IsLowVolume())
   {
      Print("GetTradeDir: Volumen bajo — ignorando");
      return 0;
   }

   // 10. EMA rápida vs EMA lenta (tendencia mayor)
   if(g_ema_fan != NULL && g_ema_fan.IsInitialized())
   {
      double ema_fast = g_ema_fan.GetEMA(0); // EMA 8
      double ema_slow = g_ema_fan.GetEMA(4); // EMA 200
      if(ema_fast > 0 && ema_slow > 0)
      {
         if(dir ==  1 && ema_fast < ema_slow)
         {
            Print("GetTradeDir: LONG rechazado — EMA8 < EMA200");
            return 0;
         }
         if(dir == -1 && ema_fast > ema_slow)
         {
            Print("GetTradeDir: SHORT rechazado — EMA8 > EMA200");
            return 0;
         }
      }
   }

   // 11. No entrar LONG con stochastic sobrecomprado ni SHORT con sobreventa
   // (evita entrar al final de un movimiento)
   if(g_stochastic != NULL && g_stochastic.IsInitialized())
   {
      double k = g_stochastic.GetK();
      if(dir ==  1 && k > 75.0) // AJUSTADO: 75 en lugar de 80
      {
         Print("GetTradeDir: Stoch sobrecomprado (", DoubleToString(k,1), ") — no LONG");
         return 0;
      }
      if(dir == -1 && k < 25.0) // AJUSTADO: 25 en lugar de 20
      {
         Print("GetTradeDir: Stoch sobrevendido (", DoubleToString(k,1), ") — no SHORT");
         return 0;
      }
   }

   // ========== NUEVOS FILTROS AVANZADOS ==========
   
   // 12. FILTRO DE ESTRUCTURA DE MERCADO
   if(InpUseStructureFilter && g_market_structure != NULL && g_market_structure.IsInitialized())
   {
      ENUM_MARKET_STRUCTURE structure = g_market_structure.GetStructure();
      
      if(dir == 1) // LONG
      {
         // No comprar en downtrend claro
         if(structure == STRUCTURE_DOWNTREND)
         {
            Print("GetTradeDir: LONG rechazado — estructura DOWNTREND");
            return 0;
         }
         
         // Verificar score mínimo de estructura
         double struct_score = g_market_structure.GetStructureScore(dir);
         if(struct_score < InpMinStructureScore)
         {
            Print("GetTradeDir: LONG rechazado — structure score=", 
                  DoubleToString(struct_score,2), " < ", InpMinStructureScore);
            return 0;
         }
      }
      else if(dir == -1) // SHORT
      {
         // No vender en uptrend claro
         if(structure == STRUCTURE_UPTREND)
         {
            Print("GetTradeDir: SHORT rechazado — estructura UPTREND");
            return 0;
         }
         
         // Verificar score mínimo de estructura
         double struct_score = g_market_structure.GetStructureScore(dir);
         if(struct_score < InpMinStructureScore)
         {
            Print("GetTradeDir: SHORT rechazado — structure score=", 
                  DoubleToString(struct_score,2), " < ", InpMinStructureScore);
            return 0;
         }
      }
   }
   
   // 13. FILTRO DE PRICE ACTION
   if(InpUsePriceActionFilter && g_price_action != NULL && g_price_action.IsInitialized())
   {
      int engulfing = g_price_action.DetectEngulfing();
      int pinbar = g_price_action.DetectPinBar();
      
      // Rechazar si price action contradice la señal
      if(dir == 1 && (engulfing == -1 || pinbar == -1))
      {
         Print("GetTradeDir: LONG rechazado — price action bajista (Engulf=", 
               engulfing, " Pin=", pinbar, ")");
         return 0;
      }
      
      if(dir == -1 && (engulfing == 1 || pinbar == 1))
      {
         Print("GetTradeDir: SHORT rechazado — price action alcista (Engulf=", 
               engulfing, " Pin=", pinbar, ")");
         return 0;
      }
      
      // Verificar score mínimo de price action
      double pa_score = g_price_action.GetSetupQuality(dir);
      if(pa_score < InpMinPAScore)
      {
         Print("GetTradeDir: Señal rechazada — PA score=", 
               DoubleToString(pa_score,2), " < ", InpMinPAScore);
         return 0;
      }
   }
   
   // 14. FILTRO DE SWING LEVELS (evitar resistencias/soportes)
   if(InpAvoidSwingLevels && g_market_structure != NULL && g_market_structure.IsInitialized())
   {
      double current_price = (dir == 1) ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) 
                                        : SymbolInfoDouble(g_symbol, SYMBOL_BID);
      
      // No comprar cerca de swing high (resistencia)
      if(dir == 1 && g_market_structure.IsNearSwingHigh(current_price, InpSwingTolerance))
      {
         Print("GetTradeDir: LONG rechazado — cerca de swing high (resistencia)");
         return 0;
      }
      
      // No vender cerca de swing low (soporte)
      if(dir == -1 && g_market_structure.IsNearSwingLow(current_price, InpSwingTolerance))
      {
         Print("GetTradeDir: SHORT rechazado — cerca de swing low (soporte)");
         return 0;
      }
   }

   // Si pasó todos los filtros, la señal es válida
   Print("GetTradeDir: Señal VÁLIDA dir=", (dir==1?"LONG":"SHORT"), 
         " | Trend=", DoubleToString(t,3), " | Mom=", DoubleToString(m,3));
   
   return dir;
}

//--- Abre una nueva operación LONG o SHORT
bool OpenTrade(const int direction)
{
   if(direction == 0) return false;

   double atr = (g_atr != NULL) ? g_atr.GetATR() : 0.0;
   if(atr <= 0) { Print("OpenTrade: ATR=0, abortando"); return false; }

   double point   = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double sl_dist = NormalizeDouble(atr * InpSLMultiplier, _Digits);
   double tp_dist = NormalizeDouble(atr * InpTPMultiplier, _Digits);
   double sl_pts  = sl_dist / point;

   double lots = CalculateLotSize(sl_pts);
   if(lots <= 0) { Print("OpenTrade: Lote=0, abortando"); return false; }

   bool result = false;

   if(direction == 1)
   {
      double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - sl_dist, _Digits);
      double tp  = NormalizeDouble(ask + tp_dist, _Digits);
      result = g_trade.Buy(lots, g_symbol, ask, sl, tp, InpTradeComment);
      if(result) Print("OpenTrade: BUY ", lots, " lotes | SL=", sl, " TP=", tp,
                       " | ATR=", DoubleToString(atr,2),
                       " | RR=1:", DoubleToString(InpTPMultiplier/InpSLMultiplier,1));
      else       Print("OpenTrade: BUY FAILED cod=", g_trade.ResultRetcode(),
                       " ", g_trade.ResultRetcodeDescription());
   }
   else
   {
      double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + sl_dist, _Digits);
      double tp  = NormalizeDouble(bid - tp_dist, _Digits);
      result = g_trade.Sell(lots, g_symbol, bid, sl, tp, InpTradeComment);
      if(result) Print("OpenTrade: SELL ", lots, " lotes | SL=", sl, " TP=", tp,
                       " | ATR=", DoubleToString(atr,2),
                       " | RR=1:", DoubleToString(InpTPMultiplier/InpSLMultiplier,1));
      else       Print("OpenTrade: SELL FAILED cod=", g_trade.ResultRetcode(),
                       " ", g_trade.ResultRetcodeDescription());
   }

   if(result)
   {
      g_trades_today++;
      g_bars_since_last_trade = 0;
      g_last_trade_day = TimeCurrent();
   }

   return result;
}

//--- Gestión activa de posición abierta: break-even y trailing stop
//    Se llama en cada tick (no solo en nueva barra) para proteger ganancias
void ManageOpenPosition()
{
   if(!g_position.SelectByMagic(g_symbol, InpMagicNumber)) return;

   double atr = (g_atr != NULL) ? g_atr.GetATR() : 0.0;
   if(atr <= 0) return;

   bool   is_buy   = (g_position.PositionType() == POSITION_TYPE_BUY);
   double open_price = g_position.PriceOpen();
   double current_sl = g_position.StopLoss();
   double current_tp = g_position.TakeProfit();
   double bid        = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask        = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double price      = is_buy ? bid : ask;
   double point      = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   double new_sl     = current_sl;

   // --- BREAK-EVEN ---
   if(InpUseBreakEven)
   {
      double be_trigger = atr * InpBreakEvenATR;
      double profit_dist = is_buy ? (price - open_price) : (open_price - price);

      if(profit_dist >= be_trigger)
      {
         // Mover SL al precio de apertura + spread mínimo
         double spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD) * point;
         double be_sl  = is_buy
                       ? NormalizeDouble(open_price + spread, _Digits)
                       : NormalizeDouble(open_price - spread, _Digits);

         bool should_move = is_buy  ? (be_sl > current_sl + point) :
                                      (be_sl < current_sl - point || current_sl == 0);
         if(should_move)
         {
            new_sl = be_sl;
         }
      }
   }

   // --- TRAILING STOP ---
   if(InpUseTrailingStop)
   {
      double trail_dist = atr * InpTrailingATR;
      double trail_step = atr * InpTrailingStepATR;

      double trail_sl = is_buy
                      ? NormalizeDouble(price - trail_dist, _Digits)
                      : NormalizeDouble(price + trail_dist, _Digits);

      // Solo mover si mejora al menos un step Y mejora el SL actual
      bool should_trail = false;
      if(is_buy)
         should_trail = (trail_sl > new_sl + trail_step) && (trail_sl > open_price);
      else
         should_trail = (trail_sl < new_sl - trail_step || new_sl == 0) && (trail_sl < open_price);

      if(should_trail) new_sl = trail_sl;
   }

   // --- Aplicar nuevo SL si cambió ---
   if(MathAbs(new_sl - current_sl) > point)
   {
      if(g_trade.PositionModify(g_position.Ticket(), new_sl, current_tp))
         Print("ManagePos: SL movido a ", DoubleToString(new_sl, _Digits),
               is_buy ? " (BE/Trail BUY)" : " (BE/Trail SELL)");
   }
}

//--- Drawdown usando solo balance (no equity — evita falsos bloqueos)
bool TradingAllowedByDrawdown()
{
   if(g_drawdown_monitor == NULL || !g_drawdown_monitor.IsInitialized()) return true;
   return g_drawdown_monitor.IsTradingAllowed();
}

// Requirements: 9.5
// Libera todos los componentes del sistema
void CleanupComponents()
{
   // Liberar FSM Manager primero (solo tiene punteros, no propietario)
   if(g_fsm_manager != NULL)
   {
      g_fsm_manager.Deinit();
      delete g_fsm_manager;
      g_fsm_manager = NULL;
   }

   // Liberar controlador de histéresis
   if(g_hysteresis != NULL)
   {
      g_hysteresis.Deinit();
      delete g_hysteresis;
      g_hysteresis = NULL;
   }

   // Liberar monitor de drawdown
   if(g_drawdown_monitor != NULL)
   {
      g_drawdown_monitor.Deinit();
      delete g_drawdown_monitor;
      g_drawdown_monitor = NULL;
   }

   // Liberar rastreador de swings
   if(g_swing_tracker != NULL)
   {
      g_swing_tracker.Deinit();
      delete g_swing_tracker;
      g_swing_tracker = NULL;
   }

   // Liberar detector de momentum
   if(g_momentum != NULL)
   {
      g_momentum.Deinit();
      delete g_momentum;
      g_momentum = NULL;
   }

   // Liberar analizador de volumen
   if(g_vol_analyzer != NULL)
   {
      g_vol_analyzer.Deinit();
      delete g_vol_analyzer;
      g_vol_analyzer = NULL;
   }

   // Liberar monitor de volatilidad
   if(g_vol_monitor != NULL)
   {
      g_vol_monitor.Deinit();
      delete g_vol_monitor;
      g_vol_monitor = NULL;
   }

   // Liberar indicador VWAP
   if(g_vwap != NULL)
   {
      g_vwap.Deinit();
      delete g_vwap;
      g_vwap = NULL;
   }

   // Liberar oscilador estocástico
   if(g_stochastic != NULL)
   {
      g_stochastic.Deinit();
      delete g_stochastic;
      g_stochastic = NULL;
   }

   // Liberar abanico de EMAs
   if(g_ema_fan != NULL)
   {
      g_ema_fan.Deinit();
      delete g_ema_fan;
      g_ema_fan = NULL;
   }

   // Liberar calculador de ATR
   if(g_atr != NULL)
   {
      g_atr.Deinit();
      delete g_atr;
      g_atr = NULL;
   }

   Print("PSM_EA: Todos los componentes han sido liberados.");
}

//+------------------------------------------------------------------+
//| SECCIÓN 8: FUNCIÓN OnInit()                                      |
//+------------------------------------------------------------------+

// Requirements: 8.1, 8.4, 9.2, 9.4, 9.5
int OnInit()
{
   Print("PSM_EA_Monolithic: Iniciando...");

   // Determinar símbolo efectivo
   g_symbol = (InpSymbol == "") ? _Symbol : InpSymbol;

   // Configurar objeto de trading
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   // ---------------------------------------------------------------
   // Requirements: 9.1, 9.2
   // Crear instancias de todos los componentes
   // ---------------------------------------------------------------

   // 1. ATR Calculator
   g_atr = new CATR_Calculator();
   if(g_atr == NULL)
   {
      Print("OnInit: Error - No se pudo crear CATR_Calculator");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_atr.Init(g_symbol, InpTimeframe, InpATRPeriod, 1.5))
   {
      Print("OnInit: Error - CATR_Calculator::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 2. EMA Fan
   g_ema_fan = new CEMA_Fan();
   if(g_ema_fan == NULL)
   {
      Print("OnInit: Error - No se pudo crear CEMA_Fan");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_ema_fan.Init(g_symbol, InpTimeframe,
                      InpEMA1Period, InpEMA2Period, InpEMA3Period,
                      InpEMA4Period, InpEMA5Period))
   {
      Print("OnInit: Error - CEMA_Fan::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 3. Stochastic Oscillator
   g_stochastic = new CStochastic_Oscillator();
   if(g_stochastic == NULL)
   {
      Print("OnInit: Error - No se pudo crear CStochastic_Oscillator");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_stochastic.Init(g_symbol, InpTimeframe,
                          InpStochKPeriod, InpStochDPeriod, InpStochSlowing,
                          InpStochOverbought, InpStochOversold))
   {
      Print("OnInit: Error - CStochastic_Oscillator::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 4. VWAP Indicator
   g_vwap = new CVWAP_Indicator();
   if(g_vwap == NULL)
   {
      Print("OnInit: Error - No se pudo crear CVWAP_Indicator");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_vwap.Init(g_symbol, InpTimeframe, InpVWAPBandMultiplier))
   {
      Print("OnInit: Error - CVWAP_Indicator::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 5. Volatility Monitor
   g_vol_monitor = new CVolatility_Monitor();
   if(g_vol_monitor == NULL)
   {
      Print("OnInit: Error - No se pudo crear CVolatility_Monitor");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_vol_monitor.Init(g_symbol, InpTimeframe,
                           InpVolATRPeriod, InpVolHistPeriod,
                           InpVolHighThreshold, InpVolLowThreshold))
   {
      Print("OnInit: Error - CVolatility_Monitor::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 6. Volume Analyzer
   g_vol_analyzer = new CVolume_Analyzer();
   if(g_vol_analyzer == NULL)
   {
      Print("OnInit: Error - No se pudo crear CVolume_Analyzer");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_vol_analyzer.Init(g_symbol, InpTimeframe,
                            InpVolumeAvgPeriod,
                            InpVolumeHighThreshold, InpVolumeLowThreshold))
   {
      Print("OnInit: Error - CVolume_Analyzer::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 7. Momentum Detector
   g_momentum = new CMomentum_Detector();
   if(g_momentum == NULL)
   {
      Print("OnInit: Error - No se pudo crear CMomentum_Detector");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_momentum.Init(g_symbol, InpTimeframe,
                        InpMomentumROCPeriod, InpMomentumSmoothPeriod,
                        InpMomentumThreshold))
   {
      Print("OnInit: Error - CMomentum_Detector::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 8. Swing Point Tracker
   g_swing_tracker = new CSwing_Point_Tracker();
   if(g_swing_tracker == NULL)
   {
      Print("OnInit: Error - No se pudo crear CSwing_Point_Tracker");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_swing_tracker.Init(g_symbol, InpTimeframe, InpSwingLookback))
   {
      Print("OnInit: Error - CSwing_Point_Tracker::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 9. Drawdown Monitor
   g_drawdown_monitor = new CStatic_Drawdown_Monitor();
   if(g_drawdown_monitor == NULL)
   {
      Print("OnInit: Error - No se pudo crear CStatic_Drawdown_Monitor");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_drawdown_monitor.Init(InpMaxDrawdownPct, InpDailyMaxDrawdownPct))
   {
      Print("OnInit: Error - CStatic_Drawdown_Monitor::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 10. Hysteresis Controller
   g_hysteresis = new CHysteresis_Controller();
   if(g_hysteresis == NULL)
   {
      Print("OnInit: Error - No se pudo crear CHysteresis_Controller");
      CleanupComponents();
      return INIT_FAILED;
   }
   SHysteresisConfig hyst_config;
   hyst_config.entry_threshold   = InpHystEntryThreshold;
   hyst_config.exit_threshold    = InpHystExitThreshold;
   hyst_config.confirmation_bars = InpHystConfirmBars;
   hyst_config.noise_filter      = InpHystNoiseFilter;
   hyst_config.use_adaptive      = InpHystUseAdaptive;
   if(!g_hysteresis.Init(hyst_config))
   {
      Print("OnInit: Error - CHysteresis_Controller::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // 11. FSM Manager (último - depende de todos los anteriores)
   g_fsm_manager = new CFSM_Manager();
   if(g_fsm_manager == NULL)
   {
      Print("OnInit: Error - No se pudo crear CFSM_Manager");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_fsm_manager.Init(g_symbol, InpTimeframe,
                           g_atr, g_ema_fan, g_stochastic, g_vwap,
                           g_vol_monitor, g_vol_analyzer, g_momentum,
                           g_swing_tracker, g_drawdown_monitor, g_hysteresis))
   {
      Print("OnInit: Error - CFSM_Manager::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }

   // Configurar pesos del FSM
   g_fsm_manager.SetTrendWeights(InpWeightEMA, InpWeightSwing, InpWeightVWAP);
   g_fsm_manager.SetMomentumWeights(InpWeightStochastic, InpWeightMomentumROC, InpWeightVolume);

   Print("PSM_EA_Monolithic: Inicialización completada exitosamente.");
   Print("PSM_EA_Monolithic: Símbolo=", g_symbol,
         " | TF=", EnumToString(InpTimeframe),
         " | Drawdown máx=", InpMaxDrawdownPct, "%");

   // Inicializar indicadores adicionales para filtros
   if(InpUseTrendFilter)
   {
      g_ema200_handle = iMA(g_symbol, InpTimeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(g_ema200_handle == INVALID_HANDLE)
      {
         Print("OnInit: Error - No se pudo crear EMA 200");
         CleanupComponents();
         return INIT_FAILED;
      }
      ArraySetAsSeries(g_ema200_buffer, true);
      
      g_adx_handle = iADX(g_symbol, InpTimeframe, InpADXPeriod);
      if(g_adx_handle == INVALID_HANDLE)
      {
         Print("OnInit: Error - No se pudo crear ADX");
         CleanupComponents();
         return INIT_FAILED;
      }
      ArraySetAsSeries(g_adx_buffer, true);
      Print("PSM_EA_Monolithic: Filtros de tendencia activados (EMA200 + ADX)");
   }

   // ---------------------------------------------------------------
   // NUEVOS MÓDULOS AVANZADOS: Price Action & Market Structure
   // ---------------------------------------------------------------
   
   // Price Action Analyzer
   g_price_action = new CPrice_Action_Analyzer();
   if(g_price_action == NULL)
   {
      Print("OnInit: Error - No se pudo crear CPrice_Action_Analyzer");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_price_action.Init(g_symbol, InpTimeframe))
   {
      Print("OnInit: Error - CPrice_Action_Analyzer::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }
   Print("PSM_EA_Monolithic: Price Action Analyzer inicializado");
   
   // Market Structure Analyzer
   g_market_structure = new CMarket_Structure_Analyzer();
   if(g_market_structure == NULL)
   {
      Print("OnInit: Error - No se pudo crear CMarket_Structure_Analyzer");
      CleanupComponents();
      return INIT_FAILED;
   }
   if(!g_market_structure.Init(g_symbol, InpTimeframe, InpStructureLookback))
   {
      Print("OnInit: Error - CMarket_Structure_Analyzer::Init() falló");
      CleanupComponents();
      return INIT_FAILED;
   }
   Print("PSM_EA_Monolithic: Market Structure Analyzer inicializado");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| SECCIÓN 9: FUNCIÓN OnDeinit()                                    |
//+------------------------------------------------------------------+

// Requirements: 8.2, 8.5, 9.3
void OnDeinit(const int reason)
{
   string reason_str = "";
   switch(reason)
   {
      case REASON_PROGRAM:    reason_str = "Programa finalizado";      break;
      case REASON_REMOVE:     reason_str = "EA removido del gráfico";  break;
      case REASON_RECOMPILE:  reason_str = "Recompilación";            break;
      case REASON_CHARTCHANGE:reason_str = "Cambio de gráfico";        break;
      case REASON_CHARTCLOSE: reason_str = "Gráfico cerrado";          break;
      case REASON_PARAMETERS: reason_str = "Parámetros modificados";   break;
      case REASON_ACCOUNT:    reason_str = "Cambio de cuenta";         break;
      default:                reason_str = "Razón desconocida";        break;
   }

   Print("PSM_EA_Monolithic: Desinicializando... Razón: ", reason_str, " (", reason, ")");
   
   // Liberar handles de indicadores adicionales
   if(g_ema200_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_ema200_handle);
      g_ema200_handle = INVALID_HANDLE;
   }
   if(g_adx_handle != INVALID_HANDLE)
   {
      IndicatorRelease(g_adx_handle);
      g_adx_handle = INVALID_HANDLE;
   }
   
   // Desinicializar nuevos módulos avanzados
   if(g_price_action != NULL)
   {
      g_price_action.Deinit();
      delete g_price_action;
      g_price_action = NULL;
   }
   if(g_market_structure != NULL)
   {
      g_market_structure.Deinit();
      delete g_market_structure;
      g_market_structure = NULL;
   }
   
   CleanupComponents();
   Print("PSM_EA_Monolithic: Desinicialización completada.");
}

//+------------------------------------------------------------------+
//| SECCIÓN 10: FUNCIÓN OnTick()                                     |
//+------------------------------------------------------------------+

void OnTick()
{
   if(g_fsm_manager == NULL || !g_fsm_manager.IsInitialized()) return;

   //--- Gestión activa cada tick (trailing stop + break-even)
   //    Independiente de la nueva barra para máxima protección
   ManageOpenPosition();

   //--- A partir de aquí, solo en nueva barra M5
   static datetime last_bar_time = 0;
   static int      neutral_bars  = 0;

   datetime current_bar_time = iTime(g_symbol, InpTimeframe, 0);
   if(current_bar_time == last_bar_time) return;
   last_bar_time = current_bar_time;

   //--- Reset diario y contador de barras
   CheckDailyReset();
   g_bars_since_last_trade++;

   //--- 1. Actualizar indicadores
   g_fsm_manager.UpdateComponents();

   //--- 1.1 Actualizar nuevos módulos avanzados
   if(InpUsePriceActionFilter && g_price_action != NULL)
   {
      if(!g_price_action.Update())
      {
         Print("OnTick: Error actualizando Price Action Analyzer");
      }
   }
   
   if(InpUseStructureFilter && g_market_structure != NULL)
   {
      if(!g_market_structure.Update())
      {
         Print("OnTick: Error actualizando Market Structure Analyzer");
      }
   }

   //--- 2. Evaluar FSM
   EState state = g_fsm_manager.EvaluateTransitions();

   //--- 3. Estado posición
   bool pos_open = false;
   bool pos_long = false;
   pos_open = HasOpenPosition(pos_long);

   //--- 4. Contabilizar barras NEUTRAL mientras hay posición
   if(pos_open)
      neutral_bars = (state == STATE_NEUTRAL) ? neutral_bars + 1 : 0;
   else
      neutral_bars = 0;

   //--- 5. Drawdown guard
   if(!TradingAllowedByDrawdown())
   {
      if(pos_open)
      {
         Print("OnTick: Drawdown máximo — cerrando posición");
         ClosePosition();
      }
      return;
   }

   //--- 6. Filtro de sesión
   if(!IsValidTradingSession()) return;

   //--- 7. Gestión de SALIDA por señal / NEUTRAL
   if(pos_open)
   {
      // 7a. Reversión confirmada — cerrar inmediatamente
      if(InpCloseOnOpposite && state == STATE_CONFIRMED)
      {
         int new_dir = GetTradeDirection();
         bool reversal = (pos_long && new_dir == -1) || (!pos_long && new_dir == 1);
         if(reversal)
         {
            Print("OnTick: Reversión — cerrando posición actual");
            if(ClosePosition())
            {
               pos_open     = false;
               neutral_bars = 0;
            }
         }
      }

      // 7b. NEUTRAL persistente con posición en pérdida
      if(pos_open && InpCloseOnNeutral && neutral_bars >= InpNeutralBarsToClose)
      {
         double profit = 0.0;
         if(g_position.SelectByMagic(g_symbol, InpMagicNumber))
            profit = g_position.Profit();

         bool close_now = (profit <  0 && neutral_bars >= InpNeutralBarsToClose)
                       || (profit >= 0 && neutral_bars >= InpNeutralBarsToClose * 2);
         if(close_now)
         {
            Print("OnTick: NEUTRAL ", neutral_bars, " barras | P&L=",
                  DoubleToString(profit, 2), " — cerrando");
            ClosePosition();
            pos_open     = false;
            neutral_bars = 0;
         }
      }
   }

   //--- 8. Abrir nueva posición
   if(!pos_open && state == STATE_CONFIRMED)
   {
      if(g_trades_today >= InpMaxTradesPerDay)
      {
         static int last_block = -1;
         if(last_block != g_trades_today)
         {
            Print("OnTick: Límite diario (", g_trades_today, "/", InpMaxTradesPerDay, ")");
            last_block = g_trades_today;
         }
         return;
      }

      if(g_bars_since_last_trade < InpMinBarsBetweenTrades) return;

      int direction = GetTradeDirection();
      if(direction != 0)
      {
         Print("OnTick: ", (direction == 1 ? "LONG ▲" : "SHORT ▼"),
               " | T=",   DoubleToString(g_fsm_manager.GetTrendScore(),    3),
               " | M=",   DoubleToString(g_fsm_manager.GetMomentumScore(), 3),
               " | ATR=", (g_atr != NULL) ? DoubleToString(g_atr.GetATR(), 2) : "?",
               " | #",    g_trades_today + 1, "/", InpMaxTradesPerDay);
         OpenTrade(direction);
      }
   }
}
//+------------------------------------------------------------------+
