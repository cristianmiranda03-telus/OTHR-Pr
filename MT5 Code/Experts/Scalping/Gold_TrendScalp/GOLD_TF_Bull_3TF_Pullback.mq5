//+------------------------------------------------------------------+
//| GOLD_TF_Bull_3TF_Pullback.mq5                                   |
//| Strategy: Triple-TF Aligned Bullish Pullback Scalper            |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY            |
//| Magic: 130001                                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO:                                                        |
//|  Entra en compras SOLO cuando los 3 macro-timeframes del oro     |
//|  apuntan al alza (D1 + H1 + M15 = score +3).                   |
//|  Dentro de ese contexto alcista, espera una micro-corrección     |
//|  en M5 hacia la EMA21 de H1 (soporte dinámico clave del oro)   |
//|  y entra cuando el RSI rebota desde la zona 40-52 con una vela  |
//|  alcista de confirmación.                                        |
//|                                                                  |
//| CONDICIONES DE ENTRADA (LONG):                                  |
//|  1. Score MTF == +3 (D1 + H1 + M15 todos alcistas)             |
//|  2. Precio en M5 llega a rango de EMA21(H1) ± 1.2 ATR          |
//|  3. RSI(14) en M5 cruza hacia arriba desde zona 38-55           |
//|  4. Vela M5 cierra alcista con cuerpo > 40% del rango           |
//|  5. ATR(14) M5 activo (> 0.8x su media de 20 barras)           |
//|                                                                  |
//| SL: mínimo de las últimas 2 barras M5 - 0.5 ATR                |
//| TP: 2.5R (recompensa mínima exigida al estar en tendencia plena)|
//|                                                                  |
//| RACIONAL DE RIESGO:                                             |
//|  Al operar solo cuando los 3 TFs coinciden, se reducen los      |
//|  scalps contra tendencia que son el principal destructor de      |
//|  cuentas en el oro. El TP de 2.5R aprovecha el momentum         |
//|  ya establecido en los marcos mayores.                           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD TrendScalp"
#property version   "1.00"
#property description "GOLD Bull Scalp | 3-TF Aligned Pullback | M5 entry | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== Filtro de Tendencia Multi-TF ==="
input int    InpMTF_MinScore   = 3;      // Score mínimo requerido: 3=todos alcistas, 2=2 de 3

input group "=== Parámetros de Entrada ==="
input int    InpRSI_Period     = 14;     // Período RSI
input double InpRSI_EntryMin   = 38.0;  // RSI mínimo para disparar (zona de pullback)
input double InpRSI_EntryMax   = 57.0;  // RSI máximo (no comprar en sobrecompra)
input double InpBody_MinPct    = 0.40;  // Cuerpo mínimo de la vela confirmadora (% rango)
input int    InpH1_EMA_Period  = 21;    // EMA de H1 usada como soporte dinámico
input double InpEMA_Proximity  = 1.2;   // Precio debe estar dentro de N ATR de la EMA(H1)
input int    InpATR_Period     = 14;    // Período ATR
input double InpATR_MinMult    = 0.8;   // ATR mínimo vs su media de 20 barras (mercado activo)

input group "=== Gestión de Riesgo ==="
input double InpRiskPct        = 0.5;   // Riesgo por operación (% equity)
input double InpSL_ATR_Mult    = 0.8;   // Multiplicador ATR para SL (stop ajustado en tendencia)
input double InpTP_RR          = 2.5;   // Relación Riesgo:Recompensa
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;    // Spread máximo en puntos

input group "=== Sesión y Trade ==="
input int    InpUTCOffset      = 0;     // Offset UTC del broker
input int    InpMagic          = 130001;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_TF_Bull_3TF_Pullback iniciado | Magic=", InpMagic, " | MinScore=", InpMTF_MinScore);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // Filtro MTF principal — requiere alineación alcista completa
   int mtfScore = SC_MTF_Score(_Symbol);
   if (mtfScore < InpMTF_MinScore) return;

   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open1  = SC_Open(_Symbol,  PERIOD_M5, 1);
   double high1  = SC_High(_Symbol,  PERIOD_M5, 1);
   double low1   = SC_Low(_Symbol,   PERIOD_M5, 1);
   double low2   = SC_Low(_Symbol,   PERIOD_M5, 2);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double rsi1   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   if (atr <= 0) return;

   // ATR debe estar activo (mercado en movimiento)
   double atrAvg = 0;
   for (int i = 2; i <= 21; i++) atrAvg += SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, i);
   atrAvg /= 20.0;
   if (atrAvg > 0 && atr < atrAvg * InpATR_MinMult) return;

   // Precio cerca de la EMA21 de H1 (zona de soporte dinámico)
   double h1Ema21 = SC_GetEMA(_Symbol, PERIOD_H1, InpH1_EMA_Period, 1);
   if (h1Ema21 <= 0) return;
   bool nearH1Support = (MathAbs(close - h1Ema21) <= atr * InpEMA_Proximity);
   if (!nearH1Support) return;

   // RSI rebotando desde zona de pullback (cruza hacia arriba)
   bool rsiCross = (rsi2 < InpRSI_EntryMin && rsi1 >= InpRSI_EntryMin && rsi1 <= InpRSI_EntryMax);
   if (!rsiCross) return;

   // Vela confirmadora alcista con cuerpo mínimo
   double range = high1 - low1;
   if (range < 1e-9) return;
   bool bullCandle = (close > open1) && ((close - open1) / range >= InpBody_MinPct);
   if (!bullCandle) return;

   // Entrada
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double swLow  = MathMin(low1, low2);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl     = NormalizeDouble(swLow - atr * InpSL_ATR_Mult, digits);
   double riskD  = ask - sl;
   if (riskD <= 0) return;
   double tp     = NormalizeDouble(ask + riskD * InpTP_RR, digits);
   double lots   = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                  InpRiskPct, InpMinLot, InpMaxLot);
   if (lots < InpMinLot) return;

   if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_TF_Bull_3TF_PB"))
      Print("COMPRA 3TF Pullback | MTF=", mtfScore, " | EMA21H1=", h1Ema21,
            " | RSI=", rsi1, " | SL=", sl, " | TP=", tp);
}
