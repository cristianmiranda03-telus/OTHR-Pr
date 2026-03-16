//+------------------------------------------------------------------+
//| GOLD_TF_Bear_3TF_Pullback.mq5                                   |
//| Strategy: Triple-TF Aligned Bearish Pullback Scalper            |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY            |
//| Magic: 130002                                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO:                                                        |
//|  Espejo bajista de GOLD_TF_Bull_3TF_Pullback.                   |
//|  Entra en ventas SOLO cuando D1 + H1 + M15 son bajistas         |
//|  (score = -3), esperando un micro-rebote hasta la EMA21(H1)     |
//|  como resistencia dinámica, con RSI rechazándose en zona alta.  |
//|                                                                  |
//| CONDICIONES DE ENTRADA (SHORT):                                 |
//|  1. Score MTF <= -MinScore (D1 + H1 + M15 todos bajistas)      |
//|  2. Precio en M5 llega a EMA21(H1) ± 1.2 ATR (resistencia)     |
//|  3. RSI(14) en M5 cruza hacia abajo desde zona 43-62           |
//|  4. Vela M5 cierra bajista con cuerpo > 40% del rango           |
//|  5. ATR activo vs su media de 20 barras                         |
//|                                                                  |
//| SL: máximo de las últimas 2 barras M5 + 0.5 ATR                |
//| TP: 2.5R                                                         |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD TrendScalp"
#property version   "1.00"
#property description "GOLD Bear Scalp | 3-TF Aligned Pullback | M5 entry | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== Filtro de Tendencia Multi-TF ==="
input int    InpMTF_MinScore   = 3;      // Score máximo (negativo) requerido: 3=todos bajistas

input group "=== Parámetros de Entrada ==="
input int    InpRSI_Period     = 14;
input double InpRSI_EntryMin   = 43.0;  // RSI mínimo al entrar (no short en sobreventa)
input double InpRSI_EntryMax   = 62.0;  // RSI máximo antes de cruzar hacia abajo (zona de rebote)
input double InpBody_MinPct    = 0.40;
input int    InpH1_EMA_Period  = 21;
input double InpEMA_Proximity  = 1.2;
input int    InpATR_Period     = 14;
input double InpATR_MinMult    = 0.8;

input group "=== Gestión de Riesgo ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 0.8;
input double InpTP_RR          = 2.5;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Sesión y Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 130002;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_TF_Bear_3TF_Pullback iniciado | Magic=", InpMagic, " | MinScore=", InpMTF_MinScore);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // Filtro MTF principal — requiere alineación bajista completa
   int mtfScore = SC_MTF_Score(_Symbol);
   if (mtfScore > -InpMTF_MinScore) return;

   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open1  = SC_Open(_Symbol,  PERIOD_M5, 1);
   double high1  = SC_High(_Symbol,  PERIOD_M5, 1);
   double low1   = SC_Low(_Symbol,   PERIOD_M5, 1);
   double high2  = SC_High(_Symbol,  PERIOD_M5, 2);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double rsi1   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   if (atr <= 0) return;

   // ATR activo
   double atrAvg = 0;
   for (int i = 2; i <= 21; i++) atrAvg += SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, i);
   atrAvg /= 20.0;
   if (atrAvg > 0 && atr < atrAvg * InpATR_MinMult) return;

   // Precio cerca de EMA21(H1) como resistencia dinámica
   double h1Ema21 = SC_GetEMA(_Symbol, PERIOD_H1, InpH1_EMA_Period, 1);
   if (h1Ema21 <= 0) return;
   bool nearH1Res = (MathAbs(close - h1Ema21) <= atr * InpEMA_Proximity);
   if (!nearH1Res) return;

   // RSI rechazándose desde zona de rebote (cruza hacia abajo)
   bool rsiCross = (rsi2 > InpRSI_EntryMax && rsi1 <= InpRSI_EntryMax && rsi1 >= InpRSI_EntryMin);
   if (!rsiCross) return;

   // Vela confirmadora bajista
   double range = high1 - low1;
   if (range < 1e-9) return;
   bool bearCandle = (close < open1) && ((open1 - close) / range >= InpBody_MinPct);
   if (!bearCandle) return;

   // Entrada
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double swHigh = MathMax(high1, high2);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl     = NormalizeDouble(swHigh + atr * InpSL_ATR_Mult, digits);
   double riskD  = sl - bid;
   if (riskD <= 0) return;
   double tp     = NormalizeDouble(bid - riskD * InpTP_RR, digits);
   double lots   = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                  InpRiskPct, InpMinLot, InpMaxLot);
   if (lots < InpMinLot) return;

   if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_TF_Bear_3TF_PB"))
      Print("VENTA 3TF Pullback | MTF=", mtfScore, " | EMA21H1=", h1Ema21,
            " | RSI=", rsi1, " | SL=", sl, " | TP=", tp);
}
