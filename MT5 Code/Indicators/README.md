# Indicadores MT5 - OTHR

Indicadores intuitivos para MetaTrader 5, con señales claras y bajo lag cuando es posible. Usables en cualquier gráfico y timeframe.

## Instalación

Copia cada carpeta (ej. `Supertrend_Signals`) dentro de la carpeta **Indicators** de tu instalación de MT5, o compila los `.mq5` desde MetaEditor y aparecerán en el navegador de indicadores.

## Indicadores incluidos

### 1. Supertrend_Signals
- **Qué es:** Supertrend basado en ATR con línea de color (azul = alcista, naranja = bajista) y flechas en los cambios de tendencia.
- **Señales:** Flecha verde = compra (cruce alcista), flecha roja = venta (cruce bajista).
- **Uso:** Cualquier activo y timeframe. Ajustar periodo ATR (10) y multiplicador (3.0) según volatilidad.

### 2. VWAP_Bands
- **Qué es:** VWAP del día con bandas de desviación estándar (2σ y 3σ). Sin retraso en el cálculo.
- **Señales:** Precio por encima de VWAP = sesión alcista; por debajo = bajista. Rebotes en bandas como zonas de sobrecompra/sobreventa.
- **Uso:** Ideal en M1–M15 para intraday. Funciona con tick volume o volumen real.

### 3. EMA_Ribbon
- **Qué es:** Cinta de 5 EMAs (9, 21, 50, 100, 200) con zona rellena entre la rápida y la lenta.
- **Señales:** Precio encima de la cinta = tendencia alcista; debajo = bajista. Cruces de EMAs para fuerza de tendencia.
- **Uso:** Cualquier timeframe. Muy visual para ver la tendencia de un vistazo.

### 4. RSI_Zones
- **Qué es:** RSI en ventana separada con líneas en 30 (sobreventa) y 70 (sobrecompra) y flechas en cruces.
- **Señales:** Flecha verde al salir de sobreventa (posible compra), flecha roja al salir de sobrecompra (posible venta).
- **Uso:** Cualquier gráfico. Periodo por defecto 14; niveles 30/70 editables.

### 5. Daily_Pivots
- **Qué es:** Pivot Points clásicos del día anterior: P, R1, R2, S1, S2. Sin lag (niveles fijos por día).
- **Señales:** Rebotes en P o R1/S1 como zonas de reacción; rupturas de R2/S2 como continuación.
- **Uso:** Cualquier timeframe. Muy usado en índices y forex para niveles clave del día.

### 6. Hull_MA_Signals
- **Qué es:** Media móvil Hull (HMA), con menos retraso que una EMA normal, y flechas en cruces con el precio.
- **Señales:** Flecha verde cuando el precio cruza por encima de la HMA; roja cuando cruza por debajo.
- **Uso:** Cualquier activo. Periodo por defecto 20; bueno para tendencia con señales rápidas.

---

**Resumen rápido**
- **Menos lag:** VWAP_Bands, Daily_Pivots, Hull_MA_Signals.
- **Señales directas (flechas):** Supertrend_Signals, RSI_Zones, Hull_MA_Signals.
- **Visualización de tendencia:** EMA_Ribbon, Supertrend_Signals, Hull_MA_Signals.

---

## Estrategias (oro scalping)

Guía en formato MT5 (comentarios, sin errores al compilar): **`Strategies/Strategies_Guide.mqh`**.  
EAs/indicadores: `GOLD_*_MACD_Engulf_M1.mq5`, `JumpEntropy_Regime.mq5`, etc. en `Experts/` e `Indicators/`.
