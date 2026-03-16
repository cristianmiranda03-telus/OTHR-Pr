//+------------------------------------------------------------------+
//| GOLD_TF_Bull_H1_Impulse.mq5                                     |
//| Strategy: H1 Bullish Impulse Continuation Scalper               |
//| Asset: XAUUSD | Timeframe: H1 trigger / M5 entry                |
//| Magic: 130003                                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO:                                                        |
//|  Detecta una vela H1 de impulso alcista fuerte (momentum shot)  |
//|  en el oro y luego scalpa en M5 en la misma dirección durante   |
//|  las siguientes 3 horas mientras el impulso está vigente.       |
//|                                                                  |
//| CONDICIONES (LONG):                                             |
//|  1. D1 alcista (SC_TrendDir_D1 >= 0) — no operar contra diario |
//|  2. Impulso H1: vela H1 cerró alcista con cuerpo > 65% rango   |
//|     Y ATR(H1) de esa vela > 1.5x su media de 20 barras H1      |
//|     Y cierre H1 > EMA50(H1)                                     |
//|  3. En M5: precio da un micro-pullback (baja ≥ 0.3 ATR desde   |
//|     el cierre H1) y luego forma vela alcista de continuación    |
//|  4. RSI(14) M5 entre 45 y 72 (ni sobrevendido ni sobrecomprado) |
//|  5. Solo dentro de la ventana de 3 horas post-impulso H1        |
//|                                                                  |
//| SL: mínimo de los últimos 3 cierres M5 - 0.4 ATR(M5)           |
//| TP: 2.0R (se espera continuación del impulso H1)                |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD TrendScalp"
#property version   "1.00"
#property description "GOLD Bull Scalp | H1 Impulse + M5 entry | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== Filtro D1 y Umbral Impulso H1 ==="
input int    InpH1_ATR_Period     = 14;    // ATR H1
input double InpH1_ATR_Mult       = 1.5;  // ATR H1 del impulso vs media (1.5 = muy fuerte)
input double InpH1_Body_MinPct    = 0.65; // Cuerpo mínimo vela H1 impulso (% rango)
input int    InpH1_EMA_Slow       = 50;   // EMA lenta H1 para confirmar macro uptrend
input int    InpImpulse_Window_H  = 3;    // Ventana de trading post-impulso (horas)

input group "=== Parámetros Entrada M5 ==="
input double InpPullback_Min_ATR  = 0.3;  // Pullback mínimo en M5 desde cierre H1 (ATR)
input int    InpRSI_Period        = 14;
input double InpRSI_Min           = 45.0;
input double InpRSI_Max           = 72.0;
input int    InpATR_Period        = 14;

input group "=== Gestión de Riesgo ==="
input double InpRiskPct           = 0.5;
input double InpSL_ATR_Mult       = 0.7;
input double InpTP_RR             = 2.0;
input double InpMinLot            = 0.01;
input double InpMaxLot            = 1.0;
input int    InpMaxSpread         = 60;

input group "=== Sesión y Trade ==="
input int    InpUTCOffset         = 0;
input int    InpMagic             = 130003;

CTrade   g_trade;
datetime g_lastBarM5    = 0;
datetime g_impulseBarH1 = 0;
double   g_impulseClose = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_TF_Bull_H1_Impulse iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

bool DetectH1BullImpulse()
{
   double h1Open  = SC_Open(_Symbol,  PERIOD_H1, 1);
   double h1Close = SC_Close(_Symbol, PERIOD_H1, 1);
   double h1High  = SC_High(_Symbol,  PERIOD_H1, 1);
   double h1Low   = SC_Low(_Symbol,   PERIOD_H1, 1);
   double h1ATR   = SC_GetATR(_Symbol, PERIOD_H1, InpH1_ATR_Period, 1);
   double ema50H1 = SC_GetEMA(_Symbol, PERIOD_H1, InpH1_EMA_Slow, 1);

   double range = h1High - h1Low;
   if (range < 1e-9 || h1ATR <= 0) return false;

   // Cuerpo fuerte y alcista
   if (h1Close <= h1Open) return false;
   if ((h1Close - h1Open) / range < InpH1_Body_MinPct) return false;

   // ATR del impulso supera la media histórica H1
   double h1ATRAvg = 0;
   for (int i = 2; i <= 21; i++) h1ATRAvg += SC_GetATR(_Symbol, PERIOD_H1, InpH1_ATR_Period, i);
   h1ATRAvg /= 20.0;
   if (h1ATRAvg > 0 && h1ATR < h1ATRAvg * InpH1_ATR_Mult) return false;

   // Cierre H1 por encima de EMA50(H1)
   if (h1Close <= ema50H1) return false;

   return true;
}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // D1 no debe ser bajista
   if (SC_TrendDir_D1(_Symbol) < 0) return;

   // Detectar nuevo impulso H1 al cambio de barra H1
   datetime h1Time[]; ArraySetAsSeries(h1Time, true);
   if (CopyTime(_Symbol, PERIOD_H1, 1, 1, h1Time) >= 1)
   {
      if (h1Time[0] != g_impulseBarH1 && DetectH1BullImpulse())
      {
         g_impulseBarH1 = h1Time[0];
         g_impulseClose = SC_Close(_Symbol, PERIOD_H1, 1);
      }
   }

   // Sin impulso activo
   if (g_impulseBarH1 == 0 || g_impulseClose <= 0) return;

   // Verificar que estamos dentro de la ventana post-impulso
   int secsElapsed = (int)(TimeGMT() - g_impulseBarH1);
   if (secsElapsed > InpImpulse_Window_H * 3600) return;

   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double open1 = SC_Open(_Symbol,  PERIOD_M5, 1);
   double high1 = SC_High(_Symbol,  PERIOD_M5, 1);
   double low1  = SC_Low(_Symbol,   PERIOD_M5, 1);
   double low2  = SC_Low(_Symbol,   PERIOD_M5, 2);
   double low3  = SC_Low(_Symbol,   PERIOD_M5, 3);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   if (atr <= 0) return;

   // El precio debió retroceder al menos InpPullback_Min_ATR desde el cierre H1
   double pullbackDepth = g_impulseClose - MathMin(MathMin(low1, low2), low3);
   if (pullbackDepth < atr * InpPullback_Min_ATR) return;

   // La vela actual debe ser alcista (rebote del pullback)
   double range = high1 - low1;
   if (range < 1e-9 || close <= open1) return;

   // RSI en rango válido
   if (rsi < InpRSI_Min || rsi > InpRSI_Max) return;

   // El precio no debe haber bajado por debajo del cierre del impulso H1 - 1 ATR(H1)
   double h1ATR = SC_GetATR(_Symbol, PERIOD_H1, InpH1_ATR_Period, 1);
   if (close < g_impulseClose - h1ATR) return;

   // Entrada
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double swLow  = MathMin(MathMin(low1, low2), low3);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl     = NormalizeDouble(swLow - atr * InpSL_ATR_Mult, digits);
   double riskD  = ask - sl;
   if (riskD <= 0) return;
   double tp     = NormalizeDouble(ask + riskD * InpTP_RR, digits);
   double lots   = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                  InpRiskPct, InpMinLot, InpMaxLot);
   if (lots < InpMinLot) return;

   if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_TF_H1Imp_L"))
      Print("COMPRA H1 Impulso | ImpulseClose=", g_impulseClose, " | Pullback=", pullbackDepth,
            " | RSI=", rsi, " | SL=", sl, " | TP=", tp);
}
