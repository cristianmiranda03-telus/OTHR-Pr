//+------------------------------------------------------------------+
//| README_Gold_AI_SMC_Wyckoff.mqh                                   |
//| Documentacion - solo comentarios, sin errores compilacion        |
//+------------------------------------------------------------------+
#ifndef README_GOLD_AI_SMC_WYCKOFF_MQH
#define README_GOLD_AI_SMC_WYCKOFF_MQH
// === CARPETA: Experts\Scalping\Gold_AI_SMC_Wyckoff ===
// Estrategias de scalping oro: Smart Money, Wyckoff, Money Flow, IA
//
// --- ARCHIVOS ---
// SMC_Wyckoff_Math.mqh   : Funciones matematicas SMC/Wyckoff/MF (FVG, OB, Spring, Upthrust, MFI, Z-Score, Entropia, Realized Vol)
// Gold_SMC_FVG_OB.mq5   : Magic 102001. Fair Value Gap + Order Block. TF M1-M15.
// Gold_Wyckoff_Spring_Upthrust.mq5 : Magic 102002. Spring (falso soporte) = long; Upthrust = short.
// Gold_MFI_SmartMoney.mq5: Magic 102003. Money Flow Index sobreventa/sobrecompra.
// Gold_AI_Score_Model.mq5: Magic 102004. Score ponderado (RSI, MFI, Z-Score, entropia, vol). Umbral InpMinScore.
// Gold_SMC_Liquidity_Sweep.mq5: Magic 102005. Barrido de liquidez (sweep highs/lows) + reversal.
//
// --- INDICADOR ---
// Indicators\SMC_FVG_OB_Signals\SMC_FVG_OB_Signals.mq5 : Flechas Bull/Bear FVG y Bull/Bear OB en grafico.
//
// --- CONCEPTOS ---
// SMC: FVG = desequilibrio 3 velas (gap). OB = ultima vela opuesta antes de impulso. Liquidity sweep = nuevo extremo luego cierre dentro.
// Wyckoff: Spring = ruptura bajo soporte y cierre dentro (reversal alcista). Upthrust = bajo techo y cierre dentro (reversal bajista).
// Money Flow: MFI = 100 - 100/(1+ ratio flujo positivo/negativo). Typical price * volume.
// IA Score: combinacion lineal de features normalizados; reemplazable por modelo ONNX externo.
#endif
