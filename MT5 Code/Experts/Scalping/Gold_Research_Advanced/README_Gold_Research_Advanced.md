# Gold Research Advanced — Expert Advisors

Carpeta con 6 EAs para XAUUSD basados en investigación científica reciente,
estrategias algorítmicas no convencionales y papers académicos 2024–2026.
Diseñadas para scalping en **cualquier sesión** (Londres, NY, Asiática) y
**cualquier nivel de volatilidad** (baja compresión o alta expansión).

---

## Estructura de Archivos

```
Gold_Research_Advanced/
├── Gold_Research_Math.mqh              ← Librería matemática compartida
├── GOLD_Kalman_LSF_Trend.mq5           ← EA 1: Kalman + LSF
├── GOLD_Hurst_Regime_Adaptive.mq5      ← EA 2: Exponente de Hurst
├── GOLD_RSI_Hidden_Divergence.mq5      ← EA 3: Divergencia Oculta RSI
├── GOLD_VolumeImbalance_DeltaScalp.mq5 ← EA 4: Delta de Volumen
├── GOLD_PullbackWindow_StateMachine.mq5 ← EA 5: Máquina de estados 4 fases
└── GOLD_AdaptiveRegime_Entropy.mq5     ← EA 6: Régimen Adaptativo Entropía
```

---

## Gold_Research_Math.mqh — Librería Matemática

Funciones matemáticas avanzadas que no existen como indicadores nativos en MT5:

| Función | Descripción |
|---------|-------------|
| `GRM_KalmanUpdate()` | Filtro de Kalman escalar 1D con tracking de velocidad |
| `GRM_KalmanBatch()` | Kalman sobre array de precios + slope de velocidad |
| `GRM_LSFSlope()` | Pendiente de regresión lineal (Least Squares Fit) |
| `GRM_LSFSlopeNorm()` | LSF normalizado por ATR |
| `GRM_HurstRS()` | Exponente de Hurst via análisis R/S (Rescaled Range) |
| `GRM_BarVolumeDelta()` | Delta de volumen por vela (volumen direccional) |
| `GRM_CumDelta()` | Delta acumulado N velas |
| `GRM_DeltaStreak()` | Racha consecutiva de velas con mismo delta |
| `GRM_VolumeImbalanceRatio()` | Ratio bull_vol / total_vol |
| `GRM_HiddenBullDiv()` / `GRM_HiddenBearDiv()` | Divergencia oculta RSI (continuación) |
| `GRM_RegularBullDiv()` / `GRM_RegularBearDiv()` | Divergencia regular RSI (reversión) |
| `GRM_ATRRatio()` | ATR corto / ATR largo (detección régimen volatilidad) |
| `GRM_GetADX()` / `GRM_GetADXFull()` | ADX con +DI y -DI |
| `GRM_LastImpulseSize()` | Tamaño del último impulso direccional |

---

## EA 1: GOLD_Kalman_LSF_Trend.mq5

**Magic:** 110001 | **TF:** M5 (entrada), M15 (filtro HTF)

### Base Científica
- **Kalman-Enhanced DRL Trading (2025)**
  - *"Kalman Enhanced Deep Reinforcement Learning for Noise-Resilient Algorithmic Trading"*
  - Source: [thesai.org Paper_81](https://thesai.org/Downloads/Volume16No11/Paper_81-Kalman_Enhanced_Deep_Reinforcement_Learning_for_Noise_Resilient_Algorithmic_Trading.pdf)
  - PPO + Kalman: 80.21% retorno acumulado, Sharpe 12.10, 88-96% reducción drawdown vs sin Kalman
- **LSF-X Engine (MT5, 2025)**
  - Source: [dhruuvsharma/LSF-X-Engine](https://github.com/dhruuvsharma/lsf-x-engine)
  - Combina Rate-of-Change + Least Squares Fitting + Kalman para detección de momentum

### Lógica
1. Filtro de Kalman aplica sobre precios de cierre → serie denoised
2. Pendiente LSF sobre los últimos N valores Kalman → dirección e intensidad de tendencia
3. **Señal:** cruce de pendiente por cero (neg→pos = BUY, pos→neg = SELL)
4. Filtro HTF: pendiente Kalman en M15 debe estar alineada con entrada
5. Filtro RSI: RSI > 45 para longs, < 55 para shorts

### Parámetros Clave
| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `InpKalmanQ` | 0.0001 | Ruido de proceso (menor = más suave) |
| `InpKalmanR` | 0.005 | Ruido de medición (mayor = más suave) |
| `InpLSFPeriod` | 14 | Barras para cálculo de pendiente LSF |
| `InpMinSlopeATR` | 0.015 | Pendiente mínima normalizada para entrar |

---

## EA 2: GOLD_Hurst_Regime_Adaptive.mq5

**Magic:** 110002 | **TF:** M5

### Base Científica
- **"Improved prediction of global gold prices: Hurst-reconfiguration-based ML"**
  - Source: [IDEAS RePec 2024](https://ideas.repec.org/a/eee/jrpoli/v88y2024ics0301420723011418.html)
  - Relación negativa entre error de forecast y exponente de Hurst en oro
- **"Comparison of Fractal Dimension Algorithms by Hurst Exponent using Gold Price"**
  - Source: [ResearchGate](https://www.researchgate.net/publication/329845330)
  - Demuestra long-memory y persistencia en series de tiempo de oro

### Interpretación del Exponente de Hurst
| Valor H | Régimen | Estrategia |
|---------|---------|-----------|
| H > 0.55 | Persistente / Tendencial | Momentum: cruce EMA + ADX |
| H 0.45–0.55 | Aleatorio / Ruidoso | **Sin operaciones** |
| H < 0.45 | Anti-persistente / Mean Reversion | Fade extremos: BB + RSI + Stoch |

### Implementación R/S Analysis
- Log returns sobre N barras (default 64)
- Rango rescalado (R/S) en lags: 8, 16, 32, 48
- Regresión log-log → pendiente = exponente de Hurst

---

## EA 3: GOLD_RSI_Hidden_Divergence.mq5

**Magic:** 110003 | **TF:** M5

### Base Científica
- **"Advanced Gold Scalping Strategy with RSI Divergence"** (TradingView, atakhadivi)
  - Divergencia en M1 XAUUSD: long si RSI <40, short si RSI >60
- **SMC + XGBoost (Sept 2025)**
  - RSI como feature principal (peso elevado) en modelo de 85.4% win-rate sobre 6 años XAUUSD

### Tipos de Divergencia
| Tipo | Precio | RSI | Señal |
|------|--------|-----|-------|
| **Hidden Bullish** | Higher Low | Lower Low | BUY (continuación) |
| **Hidden Bearish** | Lower High | Higher High | SELL (continuación) |
| **Regular Bullish** | Lower Low | Higher Low | BUY (reversión) |
| **Regular Bearish** | Higher High | Lower High | SELL (reversión) |

**Confirmación:** EMA200 — divergencias ocultas requieren alineación con tendencia HTF.

---

## EA 4: GOLD_VolumeImbalance_DeltaScalp.mq5

**Magic:** 110004 | **TF:** M5

### Base Científica
- **"Order Flow for Gold Signals: Footprint, Delta & Imbalance Entries" (FXPremiere 2025)**
  - Source: [fxpremiere.com](https://www.fxpremiere.com/order-flow-for-gold-signals-footprint-delta-imbalance-entries-2025/)
- **"Order Flow Imbalance Scalping"** (traders.mba)
  - Identificar presión compradora/vendedora en tiempo real
- **"XAUUSD Ultimate Sniper v6.0 [Order Flow & Macro]"** (TradingView)

### Lógica
1. **Delta por vela:** vela alcista = volumen positivo; bajista = negativo
2. **Racha (streak):** 3+ velas consecutivas con mismo delta = presión sostenida
3. **Ratio de desequilibrio:** bull_vol / total_vol > 0.62 = convicción compradora
4. **Spike de volumen:** volumen actual > 1.3× promedio 20 barras
5. **EMA50:** precio debe estar en lado correcto de la tendencia

---

## EA 5: GOLD_PullbackWindow_StateMachine.mq5

**Magic:** 110005 | **TF:** M5

### Base Científica
- **"backtrader-pullback-window-xauusd"** (ilahuerta-IA, 2025)
  - Source: [github.com/ilahuerta-IA](https://github.com/ilahuerta-IA/backtrader-pullback-window-xauusd)
  - 5 años backtest (Jul 2020 – Jul 2025):
    - Win Rate: **55.43%**
    - Profit Factor: **1.64**
    - Sharpe Ratio: **0.89**
    - Retorno Total: **44.75%**
    - Max Drawdown: **5.81%**
    - 175 operaciones en M5

### Máquina de Estados 4 Fases

```
[SCAN] ──→ [ARMED] ──→ [WINDOW] ──→ [ENTRY]
   ↑           |            |
   └───────────┴────────────┘ (timeout / señal fallida)
```

| Fase | Condición de Entrada | Acción |
|------|---------------------|--------|
| **SCAN** | EMA20>EMA50 + ADX>18 + 3 velas consecutivas | Detectar tendencia → ARMED |
| **ARMED** | Tendencia confirmada | Esperar pullback a zona EMA20 (timeout 25 barras) |
| **WINDOW** | Precio toca EMA20 ± 0.6×ATR | Ventana de entrada abierta 5 barras |
| **ENTRY** | RSI cruza 40 (largo) o 60 (corto) | Abrir posición con ATR SL/TP |

---

## EA 6: GOLD_AdaptiveRegime_Entropy.mq5

**Magic:** 110006 | **TF:** M5

### Base Científica
- **"Why Most Trend EAs Fail on Gold (And How Adaptive Regime Logic Fixes It)"**
  - Source: [MQL5 Blog, Enero 2026](https://www.mql5.com/en/blogs/post/766905)
  - Motor de régimen: ADX + ATR Ratio + Entropía
- **"Mentor Michael - Adaptive Regime Pro v1.0"** (TradingView)
  - Entropía normalizada 0-1 desde dispersión de retornos logarítmicos

### Motor de Régimen — Clasificación

| Régimen | Condición | Estrategia | Riesgo |
|---------|-----------|-----------|--------|
| **TREND** | ADX>25 + Entropía<0.70 + ATR ratio<1.5 | EMA8/21 cross + RSI | Normal |
| **RANGE** | ADX<20 + ATR ratio 0.7-1.3 | BB extremos + Stoch + CCI | Normal |
| **VOLATILE** | ATR ratio>1.5 ó Entropía>0.80 | 3+ señales confluencia | 50% reducido |

### Entropía de Shannon en Velas
```
H = -Σ p(i) × ln(p(i)) / ln(3)
donde: p(up), p(down), p(flat)
```
- H cercana a 0: mercado predecible (buenas señales)
- H cercana a 1: mercado aleatorio/caótico (evitar operar)

---

## Configuración para Backtesting en MT5

### Parámetros Recomendados (punto de partida)

| EA | Symbol | TF | Fecha Inicio | Modo Ticks |
|----|--------|----|-------------|-----------|
| GOLD_Kalman_LSF_Trend | XAUUSD | M5 | 2020.01.01 | Every tick |
| GOLD_Hurst_Regime_Adaptive | XAUUSD | M5 | 2020.01.01 | Every tick |
| GOLD_RSI_Hidden_Divergence | XAUUSD | M5 | 2021.01.01 | Every tick |
| GOLD_VolumeImbalance_DeltaScalp | XAUUSD | M5 | 2020.01.01 | Every tick |
| GOLD_PullbackWindow_StateMachine | XAUUSD | M5 | 2020.07.01 | Every tick |
| GOLD_AdaptiveRegime_Entropy | XAUUSD | M5 | 2020.01.01 | Every tick |

### Notas Importantes
1. **Tick Volume vs Real Volume:** MT5 usa tick volume como proxy de volumen real en Forex/XAUUSD. Los EAs de volumen (EA4) funcionan mejor con brokers que proveen real volume. Si no está disponible, el código automáticamente usa tick volume.
2. **Kalman Warmup:** EA1 necesita `InpKalmanWarmup=100` barras para inicializar. Asegúrate de que el historial de datos inicia al menos 100 barras antes de la fecha de prueba.
3. **Hurst Mínimo:** EA2 requiere mínimo 64 barras históricas (`InpHurstBars`) para calcular R/S correctamente. No reducir por debajo de 32.
4. **Spread:** Para XAUUSD, el spread típico es 20-40 puntos. `InpMaxSpread=80` cubre spreads normales + noticias moderadas.

### Optimización Sugerida

#### GOLD_Kalman_LSF_Trend
- Optimizar: `InpKalmanQ` (1e-5 a 1e-3), `InpKalmanR` (0.001 a 0.05), `InpLSFPeriod` (8-21)

#### GOLD_Hurst_Regime_Adaptive
- Optimizar: `InpHurstBars` (48-128), `InpHurstTrend` (0.52-0.62), `InpHurstRange` (0.38-0.48)

#### GOLD_PullbackWindow_StateMachine
- Optimizar: `InpADXMinThreshold` (15-25), `InpPullbackZoneATR` (0.4-0.8), `InpWindowBars` (3-8)

#### GOLD_AdaptiveRegime_Entropy
- Optimizar: `InpADXTrendMin` (20-30), `InpATRRatioVolatile` (1.3-1.8), `InpEntropyLowMax` (0.60-0.75)

---

## Referencias Científicas Completas

1. **Kalman DRL (2025):** Kalman Enhanced Deep Reinforcement Learning for Noise-Resilient Algorithmic Trading. thesai.org, Vol.16 No.11, Paper 81.
2. **Hurst Gold (2024):** "Improved prediction of global gold prices: An innovative Hurst-reconfiguration-based machine learning approach." Journal of Resources Policy, Vol. 88, 2024.
3. **Fractal Hurst (2018):** "A Comparison of Fractal Dimension Algorithms by Hurst Exponent using Gold Price Time Series." ResearchGate.
4. **SMC+XGBoost (2025):** XAUUSD Trading AI Paper — XGBoost classification 85.4% win rate, 23 features including FVG + OB + RSI. HuggingFace: JonusNattapong/xauusd-trading-ai-smc-v2.
5. **Pullback Window (2025):** backtrader-pullback-window-xauusd, 4-phase state machine, 5yr backtest 44.75% return. GitHub: ilahuerta-IA.
6. **Order Flow Gold (2025):** "Order Flow for Gold Signals: Footprint, Delta & Imbalance Entries." FXPremiere.com.
7. **Adaptive Regime (2026):** "Why Most Trend EAs Fail on Gold (And How Adaptive Regime Logic Fixes It)." MQL5 Blog, January 2026.
8. **LSF-X Engine (2025):** Kalman + Rate-of-Change + LSF MT5 EA. GitHub: dhruuvsharma/LSF-X-Engine.
9. **Golden Gauss (2026):** Gradient Boosting + ONNX para evitar overfitting en oro. MQL5 Blog, February 2026.
