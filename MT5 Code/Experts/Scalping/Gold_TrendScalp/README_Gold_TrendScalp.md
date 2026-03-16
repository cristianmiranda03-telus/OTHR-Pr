# Gold_TrendScalp — Scalping con Alineación de Tendencia Multi-TF

Carpeta creada como complemento de las estrategias existentes de Gold.  
A diferencia de los otros grupos (Gold/, Gold_Advanced/, etc.), las estrategias aquí
están **diseñadas desde cero** con la tendencia D1 / H1 / M15 como eje central,
no como un filtro añadido.

---

## Sistema de Scoring MTF (en Scalping_Common.mqh)

```
SC_MTF_Score(sym)  →  -3 .. +3

  +3 = D1 alcista  + H1 alcista  + M15 alcista  (máximo bull)
  -3 = D1 bajista  + H1 bajista  + M15 bajista  (máximo bear)
   0 = mercado lateral / mixto  → Sin posición en estrategias de tendencia
```

| Función                    | Descripción                                          |
|----------------------------|------------------------------------------------------|
| `SC_TrendDir_D1(sym)`      | +1 / 0 / -1 según EMA20 vs EMA50 en D1              |
| `SC_TrendDir_H1(sym)`      | +1 / 0 / -1 según EMA21 vs EMA50 + ADX en H1        |
| `SC_TrendDir_M15(sym)`     | +1 / 0 / -1 según EMA8 vs EMA21 en M15              |
| `SC_MTF_BullOK(sym, n)`    | true si score >= n (n=1 loose, n=2 medium, n=3 all) |
| `SC_MTF_BearOK(sym, n)`    | true si score <= -n                                  |
| `SC_MTF_RangeOK(sym, n)`   | true si |score| <= n (para estrategias de rango)       |

---

## Estrategias de esta carpeta

### 1. GOLD_TF_Bull_3TF_Pullback.mq5 | Magic 130001
**Triple-TF Aligned Bullish Pullback**
- Requiere score MTF = +3 (configurable a +2)
- Entrada: pullback M5 a EMA21(H1) + RSI cruza desde zona 38-55 + vela alcista
- SL: 0.8 ATR | TP: 2.5R
- Sesión: London + NY

### 2. GOLD_TF_Bear_3TF_Pullback.mq5 | Magic 130002
**Triple-TF Aligned Bearish Pullback**
- Espejo bajista del anterior
- Requiere score MTF = -3 (configurable a -2)
- Entrada: rebote M5 a EMA21(H1) como resistencia + RSI rechaza desde 43-62
- SL: 0.8 ATR | TP: 2.5R

### 3. GOLD_TF_Bull_H1_Impulse.mq5 | Magic 130003
**H1 Bullish Impulse Continuation**
- Detecta vela H1 de impulso fuerte (cuerpo > 65%, ATR > 1.5x media)
- Scalpa la primera corrección en M5 dentro de 3 horas post-impulso
- D1 no debe ser bajista
- SL: 0.7 ATR | TP: 2.0R

### 4. GOLD_TF_Bear_H1_Impulse.mq5 | Magic 130004
**H1 Bearish Impulse Continuation**
- Espejo bajista — detecta impulso H1 bajista fuerte
- D1 no debe ser alcista
- SL: 0.7 ATR | TP: 2.0R

### 5. GOLD_TF_Daily_Bias_Scalp.mq5 | Magic 130005
**Daily Bias Adaptive Scalper**
- EA bidireccional: cambia automáticamente entre modo long/short
- Daily Bias = D1 (peso doble) + H1 → rango -3..+3
- Solo opera cuando |bias| >= 2 (mercado con dirección clara)
- Entrada: MACD(8,21,5) cruza cero + precio vs EMA21(M5) + pivot diario
- TP dinámico: 2.2R si bias = ±3, 1.8R si bias = ±2
- Máximo 3 operaciones por día

### 6. GOLD_TF_HTF_Level_Retest.mq5 | Magic 130006
**HTF Key Level Retest Scalper**
- Detecta breakouts H1 (cierre H1 sobre máximo de 8 barras previas)
- Scalpa el primer retest de ese nivel roto (ahora soporte/resistencia)
- Ventana de retest: 8 barras M5 máximo
- D1 alineado con la dirección del breakout
- SL: 0.6 ATR del nivel | TP: 2.5R

### 7. GOLD_TF_TrendSync_EMA_Cascade.mq5 | Magic 130007
**Synchronized Triple-TF EMA Cascade**
- Versión premium del EMA_Cascade original
- Exige cascada de EMAs sincronizada en D1 + H1 + M5 simultáneamente
- Long: D1(EMA20>EMA50) + H1(EMA21>EMA50) + M5(EMA5>EMA13>EMA21)
- Bear: cascada inversa en los 3 TF
- Automáticamente toma long o short según qué cascada está activa
- SL: 1.0 ATR | TP: 2.5R

---

## Filosofía de diseño

Las estrategias de esta carpeta se basan en un principio fundamental del trading del oro:

> **El oro es un activo tendencial con alta continuación intra-day cuando la macro coincide.**
> Un scalp de 5 minutos con D1+H1+M15 alineados tiene 2-3x más probabilidad de éxito
> que el mismo scalp sin esa alineación.

El coste: **menos operaciones**. Estas EAs son más selectivas que las de Gold/.
Se recomienda correr varias en conjunto o combinarlas con las estrategias de Gold_Advanced/
que ya tienen el filtro MTF activado por defecto.

---

## Parámetros recomendados por condición de mercado

| Condición oro          | MTF_MinScore | Estrategia recomendada              |
|------------------------|--------------|-------------------------------------|
| Tendencia fuerte       | 3            | Bull/Bear_3TF_Pullback              |
| Tendencia moderada     | 2            | Bull/Bear_3TF_Pullback, TrendSync   |
| Impulso H1 reciente    | n/a (D1)     | Bull/Bear_H1_Impulse                |
| Mercado con dirección  | bias ≥ 2     | Daily_Bias_Scalp                    |
| Break de nivel H1      | D1 alineado  | HTF_Level_Retest                    |
| Cualquier sesión       | 3 (máximo)   | TrendSync_EMA_Cascade               |

---

## Notas de implementación

- Todos los EAs usan `Scalping_Common.mqh` y sus funciones MTF
- Compatible con el mismo broker/spread que el resto del suite
- Magic numbers reservados: 130001 – 130099
- Requiere al menos 100 barras D1, 200 barras H1 y 500 barras M5 para cálculos correctos
