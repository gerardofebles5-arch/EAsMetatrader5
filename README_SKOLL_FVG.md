# 📘 SKOLL-FVG Expert Advisor - Guía Completa

## 🎯 Descripción

Expert Advisor profesional para MetaTrader 5 que implementa la estrategia SKOLL-FVG basada en:
- **Fair Value Gaps (FVG)** en H1/H4
- **Order Blocks (OB)** en M5
- **Change of Character (CHOCH)** en M3
- **Gestión de riesgo matemática** con RR 1:2

---

## 📦 Instalación

### Paso 1: Copiar el archivo
1. Descarga el archivo `SKOLL_FVG_EA.mq5`
2. Copia el archivo en la carpeta de Expert Advisors de MT5:
   ```
   C:\Users\TuUsuario\AppData\Roaming\MetaQuotes\Terminal\[ID_INSTALACIÓN]\MQL5\Experts\
   ```
   O simplemente abre MT5 → Archivo → Abrir carpeta de datos → `MQL5\Experts`

### Paso 2: Compilar
1. En MT5, presiona **F4** para abrir MetaEditor
2. En el navegador de la izquierda, busca `SKOLL_FVG_EA.mq5`
3. Haz clic derecho → **Compilar** (o presiona F7)
4. Verifica que no haya errores (debe aparecer "0 error(s), 0 warning(s)")

### Paso 3: Activar en el gráfico
1. Abre un gráfico de **EURUSD** o **XAUUSD**
2. En el Navegador (Ctrl+N), busca el EA en **Expert Advisors**
3. Arrastra `SKOLL_FVG_EA` al gráfico
4. En la ventana de configuración:
   - Marca ✅ **Permitir trading automático**
   - Marca ✅ **Permitir importar DLL**
5. Clic en **Aceptar**

---

## ⚙️ Configuración de Parámetros

### 🕐 Configuración Temporal
```
InpStartHour = 5      → Hora de inicio (05:00 AM VET)
InpEndHour = 13       → Hora de fin (01:00 PM VET)
```

### 💹 Instrumentos
```
InpTradeEURUSD = true  → Operar EURUSD
InpTradeXAUUSD = true  → Operar XAUUSD (ORO)
```

### 📊 Parámetros FVG
```
InpFVG_Tolerance_EURUSD = 0.00005  → 5 pips de tolerancia
InpFVG_Tolerance_XAUUSD = 0.3      → $0.30 de tolerancia
```

### 🎯 Parámetros Order Block
```
InpOB_BodyRatio = 0.7   → Cuerpo mínimo 70% del rango
InpOB_Overlap = 0.5     → Overlap mínimo 50% con FVG
```

### 📈 Parámetros CHOCH
```
InpCHOCH_Tolerance_EURUSD = 0.00003  → 3 pips
InpCHOCH_Tolerance_XAUUSD = 0.2      → $0.20
InpEMA_Period = 20                    → EMA de 20 períodos
```

### 💰 Gestión de Riesgo
```
InpRiskPercent = 1.0   → 1% de riesgo por operación
InpTP1_Ratio = 1.0     → TP1 a 1R (50% de la posición)
InpTP2_Ratio = 2.0     → TP2 a 2R (50% de la posición)
```

### 📰 Filtro de Noticias
```
InpUseNewsFilter = true  → Activar filtro de noticias
InpNewsWindow = 2        → No operar 2h antes de noticias
```

---

## 🔄 Lógica de Operación

### Condiciones para COMPRA:
1. ✅ Horario válido (05:00 - 13:00 VET)
2. ✅ Sin noticias de alto impacto
3. ✅ FVG alcista detectado en H1 o H4
4. ✅ Vela H1 cierra dentro del FVG
5. ✅ Order Block alcista identificado en M5
6. ✅ Overlap FVG-OB ≥ 50%
7. ✅ CHOCH alcista confirmado en M3 (precio rompe swing high + EMA20)

### Condiciones para VENTA:
Condiciones inversas con FVG bajista, OB bajista y CHOCH bajista.

### Gestión de Posición:
```
Entrada:    Precio actual (Ask/Bid)
Stop Loss:  Por debajo/encima del Order Block
TP1 (50%):  1R desde entrada
TP2 (50%):  2R desde entrada
```

**NO hay trailing stop ni breakeven** — Respeta el RR matemático 1:2.

---

## 📊 Interpretación de Logs

El EA genera logs detallados en la pestaña **Expertos** de MT5:

### Ejemplo de log exitoso:
```
=== Inicializando SKOLL-FVG EA ===
Parámetros cargados:
- Horario: 5:00 - 13:00 VET
- RR: 1:2
- Riesgo: 1.0%

▲ FVG ALCISTA detectado en H1
  Rango: 1.08234 - 1.08289

✓ Precio cerró en FVG H1 ALCISTA

✓ ORDER BLOCK ALCISTA encontrado en M5
  Rango: 1.08201 - 1.08245

✓ Overlap FVG-OB: 73.45%

✓ CHOCH ALCISTA confirmado en M3
  Swing High roto: 1.08267
  Cierre actual: 1.08291

======================================
POSICIÓN ABIERTA - COMPRA
Entrada: 1.08290
SL: 1.08195
TP1 (1R): 1.08385
TP2 (2R): 1.08480
Volumen: 0.20 (50% + 50%)
Riesgo: 100.00 USD
======================================
```

---

## 🛠️ Troubleshooting

### ❌ El EA no opera
**Posible causa:** Trading automático desactivado
- **Solución:** Verifica que el botón **AutoTrading** en la barra superior esté activado (verde)

### ❌ Error "Trade context is busy"
**Posible causa:** Operación manual en curso
- **Solución:** Espera a que termine la operación manual o reinicia el EA

### ❌ No detecta FVG
**Posible causa:** Tolerancias muy estrictas
- **Solución:** Aumenta ligeramente `InpFVG_Tolerance_EURUSD` o `InpFVG_Tolerance_XAUUSD`

### ❌ "Insufficient funds"
**Posible causa:** Riesgo muy alto para el capital disponible
- **Solución:** Reduce `InpRiskPercent` a 0.5% o menos

---

## 📈 Backtesting

Para hacer backtesting en el Strategy Tester de MT5:

1. Presiona **Ctrl+R** para abrir el tester
2. Selecciona:
   - **Expert Advisor:** SKOLL_FVG_EA
   - **Símbolo:** EURUSD o XAUUSD
   - **Período:** M3 (importante para CHOCH)
   - **Fechas:** Rango deseado
   - **Modo:** Every tick based on real ticks
3. Clic en **Iniciar**

**Nota:** El backtest requiere datos históricos de calidad en M3, M5, H1 y H4.

---

## ⚠️ Advertencias Importantes

1. **NO modifiques manualmente las posiciones** abiertas por el EA
2. **Usa cuentas demo primero** hasta validar la estrategia
3. **El EA NO predice el futuro** — es una herramienta probabilística
4. **Monitorea el riesgo** — nunca arriesgues más del 1-2% por operación
5. **Respeta las noticias** — eventos de alto impacto pueden invalidar setups

---

## 📞 Soporte

Para reportar bugs o sugerencias:
- Revisa los logs en la pestaña **Expertos**
- Anota el número de ticket de la operación problemática
- Copia el mensaje de error exacto

---

## 📄 Licencia

Este Expert Advisor es de uso privado. Prohibida su distribución sin autorización.

---

## 🎓 Recordatorio Final

> "Este EA implementa tu estrategia con precisión matemática.  
> No es un sistema de hacerse rico rápido.  
> Es una herramienta para ejecutar tu edge con disciplina."

**¡Buena suerte en los mercados!** 🚀
