# 🎛️ CONFIGURACIONES ÓPTIMAS - SKOLL-FVG EA

## 📊 Configuración para EURUSD (Conservadora)

```ini
[EURUSD_Conservative]
InpStartHour = 5
InpEndHour = 13
InpTradeEURUSD = true
InpTradeXAUUSD = false

# FVG Parameters
InpFVG_Tolerance_EURUSD = 0.00005  # 5 pips
InpOB_BodyRatio = 0.75              # Requiere 75% de cuerpo
InpOB_Overlap = 0.60                # Requiere 60% overlap

# CHOCH Parameters
InpCHOCH_Tolerance_EURUSD = 0.00003 # 3 pips
InpEMA_Period = 20

# Risk Management
InpRiskPercent = 0.5                # Solo 0.5% de riesgo
InpTP1_Ratio = 1.0
InpTP2_Ratio = 2.0

# News Filter
InpUseNewsFilter = true
InpNewsWindow = 2
```

**Ideal para:** Cuentas pequeñas (<$1,000), principiantes, baja volatilidad

---

## 💰 Configuración para XAUUSD (Agresiva)

```ini
[XAUUSD_Aggressive]
InpStartHour = 5
InpEndHour = 13
InpTradeEURUSD = false
InpTradeXAUUSD = true

# FVG Parameters
InpFVG_Tolerance_XAUUSD = 0.5       # $0.50 (más permisivo)
InpOB_BodyRatio = 0.65              # 65% de cuerpo
InpOB_Overlap = 0.45                # 45% overlap

# CHOCH Parameters
InpCHOCH_Tolerance_XAUUSD = 0.3     # $0.30
InpEMA_Period = 20

# Risk Management
InpRiskPercent = 1.5                # 1.5% de riesgo
InpTP1_Ratio = 1.0
InpTP2_Ratio = 2.0

# News Filter
InpUseNewsFilter = true
InpNewsWindow = 2
```

**Ideal para:** Cuentas medianas ($2,000-$10,000), traders experimentados, alta volatilidad

---

## ⚖️ Configuración Multi-Asset (Balanceada)

```ini
[Multi_Asset_Balanced]
InpStartHour = 5
InpEndHour = 13
InpTradeEURUSD = true
InpTradeXAUUSD = true

# FVG Parameters
InpFVG_Tolerance_EURUSD = 0.00005
InpFVG_Tolerance_XAUUSD = 0.3
InpOB_BodyRatio = 0.70
InpOB_Overlap = 0.50

# CHOCH Parameters
InpCHOCH_Tolerance_EURUSD = 0.00003
InpCHOCH_Tolerance_XAUUSD = 0.2
InpEMA_Period = 20

# Risk Management
InpRiskPercent = 1.0
InpTP1_Ratio = 1.0
InpTP2_Ratio = 2.0

# News Filter
InpUseNewsFilter = true
InpNewsWindow = 2
```

**Ideal para:** Diversificación, cuentas grandes (>$10,000), trading sostenible

---

## 🧪 Configuración para Backtesting (Máxima Frecuencia)

```ini
[Backtest_HighFrequency]
InpStartHour = 5
InpEndHour = 13
InpTradeEURUSD = true
InpTradeXAUUSD = true

# FVG Parameters (Permisivos)
InpFVG_Tolerance_EURUSD = 0.00003   # 3 pips
InpFVG_Tolerance_XAUUSD = 0.2       # $0.20
InpOB_BodyRatio = 0.60              # 60% cuerpo
InpOB_Overlap = 0.40                # 40% overlap

# CHOCH Parameters (Sensibles)
InpCHOCH_Tolerance_EURUSD = 0.00002 # 2 pips
InpCHOCH_Tolerance_XAUUSD = 0.15    # $0.15
InpEMA_Period = 15                  # EMA más rápida

# Risk Management
InpRiskPercent = 1.0
InpTP1_Ratio = 1.0
InpTP2_Ratio = 2.0

# News Filter (Desactivado para backtest)
InpUseNewsFilter = false
InpNewsWindow = 0
```

**Ideal para:** Encontrar el máximo potencial de setups, validar lógica de detección

---

## 🔒 Configuración Ultra-Conservadora (Draw Down Mínimo)

```ini
[Ultra_Conservative]
InpStartHour = 6                    # Espera 1h después de London Open
InpEndHour = 12                     # Cierra 1h antes de NY Close
InpTradeEURUSD = true
InpTradeXAUUSD = false              # Solo EURUSD

# FVG Parameters (Muy Estrictos)
InpFVG_Tolerance_EURUSD = 0.00007   # 7 pips
InpOB_BodyRatio = 0.80              # 80% cuerpo
InpOB_Overlap = 0.70                # 70% overlap

# CHOCH Parameters (Muy Estrictos)
InpCHOCH_Tolerance_EURUSD = 0.00005 # 5 pips
InpEMA_Period = 25                  # EMA más lenta

# Risk Management
InpRiskPercent = 0.25               # Solo 0.25%
InpTP1_Ratio = 1.0
InpTP2_Ratio = 2.0

# News Filter (Muy Estricto)
InpUseNewsFilter = true
InpNewsWindow = 4                   # 4 horas de ventana
```

**Ideal para:** Cuentas institucionales, capital de riesgo bajo, máxima calidad de setups

---

## 🚀 Configuración Scalping (Experimental - NO RECOMENDADO)

```ini
[Scalping_Experimental]
InpStartHour = 5
InpEndHour = 13
InpTradeEURUSD = true
InpTradeXAUUSD = true

# FVG Parameters (Ultra Permisivos)
InpFVG_Tolerance_EURUSD = 0.00002   # 2 pips
InpFVG_Tolerance_XAUUSD = 0.1       # $0.10
InpOB_BodyRatio = 0.50              # 50% cuerpo
InpOB_Overlap = 0.30                # 30% overlap

# CHOCH Parameters (Ultra Sensibles)
InpCHOCH_Tolerance_EURUSD = 0.00001 # 1 pip
InpCHOCH_Tolerance_XAUUSD = 0.1     # $0.10
InpEMA_Period = 10                  # EMA rápida

# Risk Management
InpRiskPercent = 0.5
InpTP1_Ratio = 0.5                  # TP1 a 0.5R
InpTP2_Ratio = 1.0                  # TP2 a 1R

# News Filter
InpUseNewsFilter = true
InpNewsWindow = 1
```

**⚠️ ADVERTENCIA:** Esta configuración genera muchas señales pero con menor calidad. Solo para traders muy experimentados.

---

## 📋 Tabla Comparativa de Configuraciones

| Config | Trades/Mes (Est.) | Win Rate (Est.) | Drawdown Max (Est.) | Riesgo/Trade |
|--------|-------------------|-----------------|---------------------|--------------|
| Conservadora | 3-5 | 70-75% | 3-5% | 0.5% |
| Agresiva | 8-12 | 60-65% | 8-12% | 1.5% |
| Balanceada | 5-8 | 65-70% | 5-8% | 1.0% |
| Ultra-Conservadora | 1-3 | 75-80% | 1-3% | 0.25% |
| Scalping | 15-25 | 55-60% | 15-20% | 0.5% |

---

## 🎯 Cómo Elegir Tu Configuración

### Si eres principiante:
→ Empieza con **Conservadora** o **Ultra-Conservadora**

### Si tienes experiencia pero capital limitado:
→ Usa **Balanceada** con riesgo 0.5-1%

### Si tienes capital amplio y tolerancia al riesgo:
→ Prueba **Agresiva** o **Multi-Asset**

### Si quieres analizar datos históricos:
→ Usa **Backtesting** para encontrar parámetros óptimos

---

## 🔧 Cómo Aplicar una Configuración

1. Abre MetaEditor (F4)
2. Abre el archivo `SKOLL_FVG_EA.mq5`
3. Modifica los valores de `input` con los de la configuración elegida
4. Compila (F7)
5. Arrastra al gráfico

**O alternativamente:**

1. Arrastra el EA al gráfico
2. En la ventana de parámetros, modifica manualmente cada valor
3. Guarda el set como plantilla (botón "Guardar")

---

## 📊 Optimización de Parámetros

Para encontrar la configuración óptima para TU broker y condiciones:

1. Abre el **Strategy Tester** (Ctrl+R)
2. Activa el modo **Optimización**
3. Selecciona los parámetros a optimizar:
   - `InpFVG_Tolerance_EURUSD`: 0.00003 - 0.00008 (paso 0.00001)
   - `InpOB_BodyRatio`: 0.60 - 0.85 (paso 0.05)
   - `InpOB_Overlap`: 0.40 - 0.70 (paso 0.05)
   - `InpRiskPercent`: 0.5 - 2.0 (paso 0.25)
4. Criterio de optimización: **Profit Factor** o **Sharp Ratio**
5. Ejecuta la optimización (puede tardar horas)

---

## ⚡ Consejos Finales

1. **No cambies parámetros cada semana** — Dale al menos 1 mes de datos
2. **Forward testing** — Prueba en demo antes de real
3. **Ajusta según volatilidad** — Mercados volátiles requieren tolerancias mayores
4. **Monitorea el win rate** — Si cae bajo 55%, revisa parámetros
5. **Respeta el riesgo** — Nunca excedas 2% por trade

---

**Recuerda:** La mejor configuración es la que puedes seguir consistentemente. No busques el "santo grial", busca **estabilidad estadística**.

🚀 ¡Buena suerte!
