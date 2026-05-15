# MONEYHELIX7 PRO v1.0
## Expert Advisor para MetaTrader 5
### Sistema Algoritmico Profesional de 15 Instancias

---

## ESTRUCTURA DEL PROYECTO

```
MoneyHelix7Pro/
├── MoneyHelix7Pro.mq5              ← EA PRINCIPAL (compilar este)
└── Include/
    ├── MH7_Structures.mqh          ← Estructuras de datos globales
    ├── MH7_SymbolConfig.mqh        ← Config de los 15 simbolos
    ├── MH7_Engines.mqh             ← 3 Motores de senal
    ├── MH7_Voting.mqh              ← Sistema votacion 2/3
    ├── MH7_Validators.mqh          ← 6 Validadores pre-trade
    ├── MH7_Execution.mqh           ← Lot sizing + envio ordenes
    ├── MH7_PositionMgmt.mqh        ← 5 Metodos de salida
    ├── MH7_Performance.mqh         ← Metricas Sharpe/Sortino/DD
    ├── MH7_Dashboard.mqh           ← Panel visual en MT5
    └── MH7_Logger.mqh              ← Log CSV + alertas Telegram
```

---

## INSTALACION PASO A PASO

### 1. Copiar archivos a MT5

Abrir el folder de datos de MT5:
- En MT5: Archivo → Abrir carpeta de datos
- Navegar a: `MQL5/Experts/`
- Crear carpeta: `MoneyHelix7Pro/`
- Crear subcarpeta: `MoneyHelix7Pro/Include/`

Copiar:
- `MoneyHelix7Pro.mq5` → `MQL5/Experts/MoneyHelix7Pro/`
- Todos los archivos `.mqh` → `MQL5/Experts/MoneyHelix7Pro/Include/`

### 2. Compilar el EA

- En MT5: Abrir MetaEditor (F4)
- Abrir `MoneyHelix7Pro.mq5`
- Compilar (F7)
- Debe compilar SIN errores

### 3. Configurar grafico

- Timeframe: **M15** (obligatorio)
- Simbolo base: cualquiera (el EA maneja sus propios simbolos)
- Arrastrar el EA al grafico

### 4. Parametros recomendados (primera ejecucion)

```
RiskPercent          = 2.0    (2% del balance por trade)
MaxDailyLossPct      = 6.0    (maximo 6% de perdida diaria)
MaxTotalDDPct        = 20.0   (circuit breaker al 20% DD)
SoftDDPct            = 15.0   (reducir tamaño al 15% DD)
MinQuality           = 60.0   (calidad minima de senal)
MaxBarsOpen          = 96     (24 horas maximo en posicion)
EnableDashboard      = true   (panel visual activado)
EnableLogging        = true   (log CSV activado)
```

### 5. Simbolos activos por defecto

Al activar por primera vez, solo estan habilitados:
- XAUUSD (Magic: 700001)
- DXY    (Magic: 700002)
- EURUSD (Magic: 700003)
- GBPUSD (Magic: 700004)
- USDJPY (Magic: 700005)
- XAGUSD (Magic: 700006)

Activar mas simbolos segun disponibilidad del broker.

### 6. Permisos necesarios en MT5

- Algoritmic Trading: ACTIVADO (en propiedades del EA)
- WebRequest (para Telegram): `Herramientas → Opciones → Asesores Expertos`
  - Añadir: `https://api.telegram.org`

---

## ALERTAS POR TELEGRAM (opcional)

1. Crear bot en @BotFather de Telegram
2. Obtener token del bot
3. Obtener chat_id (usar @userinfobot)
4. Rellenar en los inputs:
   - `TelegramToken` = "123456:ABC-..."
   - `TelegramChatID` = "-1001234567890"
   - `EnableTelegram` = true

---

## ARQUITECTURA (6 CAPAS)

```
CAPA 1: SENALES
   Motor A: Value (Graham) - Precio vs SMA200 diario
   Motor B: Momentum (Clenow) - ROC normalizado z-score
   Motor C: ML Ensemble (Lopez de Prado) - RF+SVM+GB

CAPA 2: VOTACION 2/3
   Minimo 2 de 3 motores en acuerdo
   Score de calidad ponderado (0-100)
   Threshold configurable por simbolo

CAPA 3: VALIDADORES (6)
   1. Sesion (NY 13-21 UTC | EU 08-16 UTC)
   2. Volatilidad (ATR minimo + maximo)
   3. Correlacion (signo vs XAUUSD)
   4. Drawdown (soft 15% | hard 20%)
   5. Racha negativa (max 4 consecutivas)
   6. Noticias (bloqueo manual configurable)

CAPA 4: EJECUCION
   Lot size: Kelly Criterion 25% (2% del balance)
   SL: ATR x multiplicador por simbolo
   TP: SL x ratio (2.5x - 5.0x segun simbolo)

CAPA 5: GESTION DE POSICION (5 metodos)
   1. TP/SL mecanico
   2. Trailing stop dinamico (35% del SL)
   3. Breakeven (buffer de 2 pips)
   4. Cierre parcial 50% (al 40% del TP)
   5. Salida por divergencia de momentum

CAPA 6: MONITOREO
   Dashboard en tiempo real (15 sec)
   Log CSV de todos los trades
   Alertas Telegram
   Reporte diario automatico
   Metricas: Sharpe, Sortino, DD, WR, PF
```

---

## MAGIC NUMBERS Y SIMBOLOS

| Instancia | Simbolo   | Magic  | Sesion    | Corr XAUUSD |
|-----------|-----------|--------|-----------|-------------|
| 01        | XAUUSD    | 700001 | NY+EU     | +1.00       |
| 02        | DXY       | 700002 | NY        | -0.95       |
| 03        | EURUSD    | 700003 | NY+EU     | -0.85       |
| 04        | GBPUSD    | 700004 | NY+EU     | -0.78       |
| 05        | USDJPY    | 700005 | NY        | -0.72       |
| 06        | XAGUSD    | 700006 | NY+EU     | +0.82       |
| 07        | WTICRUSD  | 700007 | NY        | +0.65       |
| 08        | NATGAS    | 700008 | NY        | +0.45       |
| 09        | SPX       | 700009 | NY        | -0.58       |
| 10        | DAX       | 700010 | NY+EU     | -0.52       |
| 11        | FTSE      | 700011 | NY+EU     | -0.48       |
| 12        | NIKKEI    | 700012 | NY        | -0.42       |
| 13        | COPPER    | 700013 | NY        | +0.58       |
| 14        | BTCUSD    | 700014 | NY        | -0.35       |
| 15        | VIX       | 700015 | NY        | +0.55       |

---

## NOTAS IMPORTANTES

- El EA debe correr en un servidor VPS con MT5 activo 24/5
- Los simbolos deben estar disponibles en tu broker
- En algunos brokers los nombres pueden variar (ej: "GOLD" en lugar de "XAUUSD")
  → Ajustar en MH7_SymbolConfig.mqh si es necesario
- Hacer backtesting de 2+ años ANTES de usar en cuenta real
- Comenzar con cuenta demo o prop firm en modo evaluacion

---

## REFERENCIAS TEORICAS

| Modulo          | Libro                                    | Autor              |
|-----------------|------------------------------------------|--------------------|
| Motor A         | The Intelligent Investor                 | Graham             |
| Motor B         | Stocks on the Move                       | Clenow             |
| Motor C         | Advances in Financial ML                 | Lopez de Prado     |
| Kelly/Sizing    | Mathematics of Money Management          | Vince              |
| Drawdown        | Systematic Trading                       | Carver             |
| Backtesting     | Building Winning Algo Trading Systems    | Davey              |
| Validacion      | Evidence-Based Technical Analysis       | Aronson            |
| Price Action    | The Art and Science of Technical Analysis| Grimes             |
| Ensemble        | Inside the Black Box                     | Narang             |
| Metricas        | Active Portfolio Management              | Grinold & Kahn     |
| ATR/SL          | New Concepts in Technical Trading Sys.  | Wilder             |
| Latencia        | Machine Trading                          | Chan               |
| GARCH/Stats     | Analysis of Financial Time Series       | Tsay               |

---

## SOPORTE Y AJUSTES

Para ajustar el sistema sin recompilar:
- Los inputs de MT5 permiten cambiar risk%, thresholds y sesiones
- Para cambiar nombres de simbolos del broker: editar MH7_SymbolConfig.mqh
- Para ajustar pesos del ML: editar InitMLModel() en MH7_Engines.mqh
- Para cambiar SL/TP multipliers: ajustar en MH7_SymbolConfig.mqh

---

*MoneyHelix7 Pro v1.0 | Basado en 39 libros + 100 respuestas del operador*
