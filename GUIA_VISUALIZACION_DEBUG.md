# 🎨 GUÍA DE VISUALIZACIÓN Y DEBUGGING - SKOLL-FVG v2.0

## 🆕 Novedades de la Versión Visual

Esta versión incluye:
✅ **Dibujo automático** de FVGs, Order Blocks y señales en el gráfico
✅ **Análisis histórico** de setups pasados (últimas 100 barras)
✅ **Panel de información** en tiempo real
✅ **Correcciones para backtest** (horario, fills, logs mejorados)
✅ **Modo debug** con logs detallados

---

## 🎨 Elementos Visuales en el Gráfico

### 1. **Fair Value Gaps (FVG)**

**FVG Alcistas (Azul)**
- Color: `DodgerBlue` 🔵
- Estilo: Rectángulo sólido con transparencia
- Ubicación: Entre velas 1-2-3 en H1
- Nombre: `FVG_Bull_XXX`

**FVG Bajistas (Naranja/Rojo)**
- Color: `OrangeRed` 🔴
- Estilo: Rectángulo sólido con transparencia
- Ubicación: Entre velas 1-2-3 en H1
- Nombre: `FVG_Bear_XXX`

### 2. **Order Blocks (OB)**

**OB Alcistas (Verde)**
- Color: `LimeGreen` 🟢
- Estilo: Rectángulo punteado
- Ubicación: Velas M5 con cuerpo ≥70%
- Nombre: `OB_Bull_XXX`

**OB Bajistas (Rojo)**
- Color: `Tomato` 🔴
- Estilo: Rectángulo punteado
- Ubicación: Velas M5 con cuerpo ≥70%
- Nombre: `OB_Bear_XXX`

### 3. **Señales de Entrada**

**Señal de COMPRA**
- Símbolo: Flecha hacia arriba ↑ (código 233)
- Color: `Lime` 🟢
- Ubicación: Precio de entrada en M3
- Nombre: `SIGNAL_XXX`

**Señal de VENTA**
- Símbolo: Flecha hacia abajo ↓ (código 234)
- Color: `Red` 🔴
- Ubicación: Precio de entrada en M3
- Nombre: `SIGNAL_XXX`

### 4. **Setups Históricos**

**FVGs Históricos**
- Mismo color que FVGs actuales
- Estilo: **Punteado** (para distinguir)
- Nombre: `HIST_FVG_Bull_XXX` o `HIST_FVG_Bear_XXX`

---

## 📊 Panel de Información

En la esquina superior izquierda verás:

```
═══ SKOLL-FVG v2.0 ═══
Trading: ON
Horario: 5:00-13:00 VET
FVGs: 12
OBs: 8
Señales: 3
```

**Explicación:**
- `Trading`: Estado del trading automático (ON/OFF)
- `Horario`: Ventana operativa configurada
- `FVGs`: Cantidad de Fair Value Gaps detectados
- `OBs`: Cantidad de Order Blocks encontrados
- `Señales`: Número de señales de entrada generadas

---

## 🔍 Cómo Interpretar el Gráfico

### Ejemplo de Setup Completo:

```
1. Rectángulo azul (FVG alcista) en H1
2. Precio cierra dentro del FVG
3. Rectángulo verde punteado (OB alcista) en M5
4. OB solapa al menos 50% con FVG
5. Flecha verde ↑ indica señal de compra confirmada
```

### Visualización Paso a Paso:

**Hora 08:00 VET:**
- 🔵 Aparece FVG alcista en H1

**Hora 09:00 VET:**
- Precio retrocede y cierra dentro del FVG
- 🟢 Se dibuja Order Block en M5

**Hora 09:15 VET:**
- Se confirma CHOCH en M3
- ↑ Aparece flecha de señal de COMPRA

---

## 🐛 Debugging - Lectura de Logs

### Logs Normales (Sin Señales):

```
=== Inicializando SKOLL-FVG EA v2.0 ===
=== VERSIÓN CON VISUALIZACIÓN GRÁFICA ===
🔍 Analizando setups históricos...
✅ Análisis histórico completado:
   📈 Setups alcistas: 15
   📉 Setups bajistas: 12
   🎯 Total: 27
✅ EA inicializado correctamente
⏰ Horario operativo: 5:00 - 13:00 VET
💰 Riesgo por trade: 1.0%
🎯 RR configurado: 1:2
🤖 Trading automático: ACTIVADO
```

### Logs Cuando Detecta FVG:

```
▲ FVG ALCISTA: 1.08234 - 1.08289
```

### Logs Cuando Precio Entra en FVG:

```
✓ Precio cerró en FVG H1 ALCISTA
  FVG: 1.08234 - 1.08289
  Cierre H1: 1.08256
```

### Logs Cuando Encuentra Order Block:

```
✓ Order Block encontrado: 1.08201 - 1.08245
✓ Overlap: 73.45%
```

### Logs Cuando Confirma CHOCH:

```
✓ CHOCH ALCISTA:
  Swing High: 1.08267
  Cierre: 1.08291
  EMA: 1.08245
✓ CHOCH confirmado
```

### Logs Cuando Abre Posición:

```
✅ Posición TP2 abierta: #123456789
✅ Posición TP1 abierta: #123456790
═══════════════════════════════════
🚀 POSICIÓN ABIERTA - COMPRA
📍 Entrada: 1.08290
🛑 SL: 1.08195 (95 pips)
🎯 TP1: 1.08385
🎯 TP2: 1.08480
💰 Volumen: 0.20
💵 Riesgo: $100.00
═══════════════════════════════════
```

---

## 🚨 Solución de Problemas de Backtest

### ❌ Problema: "No hay operaciones en backtest"

**Causas posibles:**

1. **Horario incorrecto**
   - ✅ Solución: Verifica que las barras de tu backtest estén en el rango 09:00-17:00 UTC
   - En código: `05:00 VET = 09:00 UTC` / `13:00 VET = 17:00 UTC`

2. **No hay datos en M3**
   - ✅ Solución: En Strategy Tester, selecciona **"Every tick based on real ticks"**
   - Asegúrate de tener datos históricos de M3

3. **Tolerancias muy estrictas**
   - ✅ Solución: Prueba estos valores más permisivos:
   ```
   InpFVG_Tolerance_EURUSD = 0.00008    (8 pips)
   InpOB_BodyRatio = 0.60               (60%)
   InpOB_Overlap = 0.40                 (40%)
   ```

4. **Filtro de noticias activado**
   - ✅ Solución: Desactiva `InpUseNewsFilter = false` para backtest

5. **Trading deshabilitado**
   - ✅ Solución: Verifica `InpEnableTrading = true`

### ❌ Problema: "El gráfico no muestra dibujos"

**Causas posibles:**

1. **Objetos deshabilitados**
   - ✅ Solución: En el gráfico, presiona `Ctrl+B` para mostrar objetos

2. **Zoom muy cercano/lejano**
   - ✅ Solución: Ajusta el zoom con la rueda del mouse

3. **Parámetros de visualización desactivados**
   - ✅ Solución: Verifica:
   ```
   InpShowFVG = true
   InpShowOB = true
   InpShowEntrySignals = true
   InpShowHistoricalSetups = true
   ```

### ❌ Problema: "Insufficient funds" en backtest

**Causas:**

1. **Capital inicial muy bajo**
   - ✅ Solución: En Strategy Tester, usa al menos $10,000 inicial

2. **Riesgo muy alto**
   - ✅ Solución: Reduce `InpRiskPercent = 0.5`

---

## 🔧 Configuración Óptima para Backtest

### Para EURUSD:

```ini
[EURUSD_Backtest]
InpStartHour = 5
InpEndHour = 13

# Visualización
InpShowFVG = true
InpShowOB = true
InpShowEntrySignals = true
InpShowHistoricalSetups = true

# FVG más permisivo
InpFVG_Tolerance_EURUSD = 0.00008
InpOB_BodyRatio = 0.60
InpOB_Overlap = 0.40

# CHOCH más sensible
InpCHOCH_Tolerance_EURUSD = 0.00004
InpEMA_Period = 20

# Riesgo conservador
InpRiskPercent = 0.5

# Desactivar filtro de noticias
InpUseNewsFilter = false

# Habilitar trading
InpEnableTrading = true
```

### Para XAUUSD:

```ini
[XAUUSD_Backtest]
InpStartHour = 5
InpEndHour = 13

# Visualización
InpShowFVG = true
InpShowOB = true
InpShowEntrySignals = true
InpShowHistoricalSetups = true

# FVG para oro
InpFVG_Tolerance_XAUUSD = 0.5
InpOB_BodyRatio = 0.60
InpOB_Overlap = 0.40

# CHOCH para oro
InpCHOCH_Tolerance_XAUUSD = 0.3
InpEMA_Period = 20

# Riesgo
InpRiskPercent = 0.5

# Desactivar noticias
InpUseNewsFilter = false

# Habilitar trading
InpEnableTrading = true
```

---

## 📈 Cómo Hacer un Backtest Correcto

### Paso 1: Preparar el Strategy Tester

1. Presiona `Ctrl+R` para abrir el tester
2. Selecciona:
   - **Expert:** `SKOLL_FVG_EA_VISUAL`
   - **Símbolo:** `EURUSD` o `XAUUSD`
   - **Período:** `M3` (importante para CHOCH)
   - **Fechas:** Al menos 3 meses de datos
   - **Modo:** `Every tick based on real ticks`
   - **Optimización:** Desactivada (por ahora)

### Paso 2: Configurar Parámetros

En la pestaña **Inputs**, configura:

```
InpEnableTrading = true
InpUseNewsFilter = false
InpShowFVG = true
InpShowOB = true
InpShowEntrySignals = true
```

### Paso 3: Ajustar Capital y Riesgo

En la pestaña **Settings**:
```
Deposit: 10000 USD
Leverage: 1:100
```

### Paso 4: Ejecutar

1. Clic en **Start**
2. Espera a que termine (puede tardar 5-30 minutos)
3. Revisa la pestaña **Journal** para logs detallados

### Paso 5: Análizar Resultados

Revisa:
- **Total trades:** ¿Cuántas operaciones abrió?
- **Win rate:** ¿Porcentaje de ganancia?
- **Profit factor:** Debe ser >1.5
- **Max drawdown:** Idealmente <10%

### Paso 6: Ver Gráfico Visual

1. Clic en **Open chart** en el tester
2. Verás todos los FVGs, OBs y señales dibujados
3. Zoom para ver detalles de cada setup

---

## 🎯 Verificación de que el EA Funciona

### Checklist Visual:

- ✅ ¿Ves rectángulos azules/rojos en el gráfico? → FVGs detectados
- ✅ ¿Ves rectángulos verdes/rojos punteados? → OBs detectados
- ✅ ¿Ves flechas verdes/rojas? → Señales de entrada
- ✅ ¿Ves líneas de posiciones? → Trading activo
- ✅ ¿Ves el panel superior izquierdo? → Info panel funcionando

### Checklist de Logs:

- ✅ "Inicializando SKOLL-FVG EA v2.0" → EA cargó bien
- ✅ "Análisis histórico completado" → Escaneó el historial
- ✅ "FVG ALCISTA/BAJISTA" → Detectó fair value gaps
- ✅ "Order Block encontrado" → Identificó OBs
- ✅ "CHOCH confirmado" → Validó cambio de carácter
- ✅ "POSICIÓN ABIERTA" → Ejecutó trade

---

## 🔥 Modo Debug Avanzado

Si aún no ves operaciones, activa el debug manual:

### En el código, busca la función `CheckForEntrySignal()` y agrega prints:

```cpp
void CheckForEntrySignal()
{
    Print("DEBUG: Verificando señal de entrada...");
    
    // 1. Detectar FVG
    FVG_Structure fvg_h1;
    if(!DetectFVG(PERIOD_H1, fvg_h1)) {
        Print("DEBUG: No se detectó FVG");
        return;
    }
    Print("DEBUG: FVG detectado ✓");
    
    // ... resto del código con más prints
}
```

Esto te dirá **exactamente** en qué paso falla la detección.

---

## 📞 Si Todavía No Opera...

Envíame estos datos:

1. **Screenshot del gráfico** con objetos visibles
2. **Últimos 50 logs** de la pestaña Journal
3. **Parámetros exactos** que usaste
4. **Símbolo y timeframe** del backtest
5. **Rango de fechas** probado

---

## ✅ Confirmación de Éxito

Cuando el EA funcione correctamente verás:

```
Gráfico:
- 5-15 FVGs dibujados (azules y rojos)
- 3-10 Order Blocks (verdes y rojos punteados)
- 1-5 Flechas de señales (verdes o rojas)

Logs:
- "Análisis histórico completado: Total: XX"
- "FVG ALCISTA detectado" (múltiples veces)
- "Order Block encontrado" (múltiples veces)
- "POSICIÓN ABIERTA" (al menos 1 vez)

Resultados:
- Total trades: 3-10 (en 3 meses de backtest)
- Win rate: 60-75%
- Profit: Positivo
```

---

**¡Buena suerte con el backtest!** 🚀

Si sigues teniendo problemas, comparte los logs y te ayudo a diagnosticar el issue exacto.
