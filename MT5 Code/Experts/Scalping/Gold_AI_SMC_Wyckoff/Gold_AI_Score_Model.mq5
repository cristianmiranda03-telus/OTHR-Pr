//+------------------------------------------------------------------+
//| Gold_AI_Score_Model.mq5                                          |
//| Modelo tipo IA: score ponderado de features (sin ONNX)           |
//| Features: RSI, MFI, Z-Score precio, entropia, realized vol      |
//| Solo opera si score_long > umbral o score_short > umbral        |
//| Magic 102004                                                      |
//+------------------------------------------------------------------+
#property copyright "Gold AI SMC Wyckoff"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"
#include "SMC_Wyckoff_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;

input group "=== AI Score (pesos tipo modelo) ==="
input double InpW_RSI        = 0.25;   // RSI normalizado 0-1
input double InpW_MFI       = 0.25;
input double InpW_ZScore    = 0.2;    // precio bajo media -> long
input double InpW_Entropy   = -0.15;  // entropia alta penaliza
input double InpW_Vol       = 0.1;    // vol alta favorece señal
input double InpMinScore    = 0.55;   // umbral minimo para entrar

input group "=== Indicadores ==="
input int    InpRSI_Period  = 14;
input int    InpMFI_Period  = 14;
input int    InpZScoreBars  = 30;
input int    InpEntropyBars = 20;
input int    InpVolBars     = 20;

input group "=== Session ==="
input int    InpUTCOffset   = 0;

input group "=== Risk ==="
input double InpRiskPct    = 0.4;
input double InpSL_ATR     = 1.0;
input double InpTP_RR     = 1.5;
input int    InpATR_Period = 14;
input double InpMinLot     = 0.01;
input double InpMaxLot     = 0.5;
input int    InpMaxSpread  = 80;

input group "=== Trade ==="
input int    InpMagic      = 102004;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min score magnitude to take directional trade (1-3)

CTrade   g_trade;
datetime g_lastBar = 0;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(40);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsXAU()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (!SC_IsNewBar(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double rsi = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
   double mfi = Math_MFI(_Symbol, InpTF, InpMFI_Period, 1);
   double close = SC_Close(_Symbol, InpTF, 1);
   double sma = SC_GetSMA(_Symbol, InpTF, InpZScoreBars, 1);
   double rvol = Math_RealizedVol(_Symbol, InpTF, InpVolBars, 1);
   double atr = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   double stdDev = 0;
   double c[];
   ArraySetAsSeries(c, true);
   if (CopyClose(_Symbol, InpTF, 1, InpZScoreBars + 1, c) >= InpZScoreBars)
   {
      double sum = 0, sumSq = 0;
      for (int i = 0; i < InpZScoreBars; i++) { sum += c[i]; sumSq += c[i]*c[i]; }
      double mu = sum / InpZScoreBars;
      double var = (sumSq / InpZScoreBars) - mu * mu;
      if (var > 0) stdDev = MathSqrt(var);
   }
   double zScore = Math_ZScore(close, sma, stdDev);
   double entropy = Math_EntropySigns(_Symbol, InpTF, InpEntropyBars, 1);

   double normRSI = (rsi - 30) / 40.0;
   if (normRSI < 0) normRSI = 0; if (normRSI > 1) normRSI = 1;
   double normMFI = (mfi - 30) / 40.0;
   if (normMFI < 0) normMFI = 0; if (normMFI > 1) normMFI = 1;
   double zLong = (-zScore + 2) / 4;
   if (zLong < 0) zLong = 0; if (zLong > 1) zLong = 1;
   double zShort = (zScore + 2) / 4;
   if (zShort < 0) zShort = 0; if (zShort > 1) zShort = 1;
   double volNorm = (atr > 0 && rvol > 0) ? MathMin(rvol / atr, 2.0) / 2.0 : 0.5;

   double scoreLong  = InpW_RSI * (1.0 - normRSI) + InpW_MFI * (1.0 - normMFI) + InpW_ZScore * zLong
                     + InpW_Entropy * (1.0 - entropy) + InpW_Vol * volNorm;
   double scoreShort = InpW_RSI * normRSI + InpW_MFI * normMFI + InpW_ZScore * zShort
                     + InpW_Entropy * (1.0 - entropy) + InpW_Vol * volNorm;

   int mtfScore = InpUseMTF ? SC_MTF_Score(_Symbol) : 0;
   if (InpUseMTF && mtfScore <= -InpMTF_MinScore) scoreLong  = 0;
   if (InpUseMTF && mtfScore >= InpMTF_MinScore)  scoreShort = 0;

   if (scoreLong < InpMinScore && scoreShort < InpMinScore) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if (atr <= 0) return;

   if (scoreLong >= InpMinScore && scoreLong > scoreShort)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(ask - atr * InpSL_ATR, digits);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp = NormalizeDouble(ask + slD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "AI_Score_L");
      }
      return;
   }

   if (scoreShort >= InpMinScore)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(bid + atr * InpSL_ATR, digits);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp = NormalizeDouble(bid - slD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT), InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "AI_Score_S");
      }
   }
}
