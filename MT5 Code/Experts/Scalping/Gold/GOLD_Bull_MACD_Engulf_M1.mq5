//+------------------------------------------------------------------+
//| GOLD_Bull_MACD_Engulf_M1.mq5                                     |
//| Estrategia: doble confirmación MACD alcista + Power Engulf M1   |
//| Activo: XAU | TF: M1 | Sesión: London + NY                       |
//| Lógica: histograma MACD > 0 + vela envolvente alcista con        |
//|         cuerpo >= N*ATR y volumen > media * mult.               |
//| Magic: 100014                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD M1"
#property version   "1.00"
#property description "MACD Bull + Vol Engulf Power - M1 scalping"

#include "..\Common\Scalping_Common.mqh"

input group "=== MACD M1 ==="
input int    InpMACD_Fast      = 5;
input int    InpMACD_Slow      = 13;
input int    InpMACD_Signal    = 9;
input bool   InpMACD_CrossOnly = false;  // true = solo cruce a positivo

input group "=== Engulf Power M1 ==="
input double InpMinBodyATR     = 0.6;    // cuerpo mínimo en ATRs (M1 más pequeño que M5)
input double InpMinVolMult     = 1.2;
input int    InpVolAvgBars     = 20;

input group "=== Filtros ==="
input int    InpEMA_Trend      = 21;     // precio > EMA = sesgo alcista
input bool   InpUseEMAFilter   = true;
input int    InpRSI_Period     = 14;
input double InpRSI_Max        = 68.0;

input group "=== Riesgo ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.0;
input double InpTP_RR          = 1.5;    // TP = RR * riesgo
input int    InpATR_Period     = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 80;

input group "=== Sesión ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100014;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bullish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBarM1 = 0;

bool IsXAU()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
}

int OnInit()
{
   if (!IsXAU())
      Print("GOLD_Bull_MACD_Engulf_M1: recomendado en XAU/GOLD.");
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
   if (!SC_IsNewBar(PERIOD_M1, g_lastBarM1)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_BullOK(_Symbol, InpMTF_MinScore)) return;

   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M1, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M1, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double hist1 = macd1 - sig1;
   double hist2 = macd2 - sig2;
   bool macdBull = (hist1 > 0);
   if (InpMACD_CrossOnly)
      macdBull = (hist1 > 0 && hist2 <= 0);
   if (!macdBull) return;

   double close1 = SC_Close(_Symbol, PERIOD_M1, 1);
   double open1  = SC_Open(_Symbol, PERIOD_M1, 1);
   double low1   = SC_Low(_Symbol, PERIOD_M1, 1);
   double close2 = SC_Close(_Symbol, PERIOD_M1, 2);
   double open2  = SC_Open(_Symbol, PERIOD_M1, 2);

   double atr = SC_GetATR(_Symbol, PERIOD_M1, InpATR_Period, 1);
   if (atr <= 0) return;

   bool prevBear = (close2 < open2);
   bool currBull = (close1 > open1);
   bool engulfs  = (open1 <= close2) && (close1 >= open2);
   double body   = close1 - open1;
   bool bigBody  = (body >= atr * InpMinBodyATR);

   double vol1   = (double)SC_Volume(_Symbol, PERIOD_M1, 1);
   double avgVol = SC_AvgVolume(_Symbol, PERIOD_M1, InpVolAvgBars, 2);
   bool volOK    = (avgVol <= 0 || vol1 >= avgVol * InpMinVolMult);

   if (InpUseEMAFilter)
   {
      double ema = SC_GetEMA(_Symbol, PERIOD_M1, InpEMA_Trend, 1);
      if (close1 <= ema) return;
   }
   double rsi = SC_GetRSI(_Symbol, PERIOD_M1, InpRSI_Period, 1);
   if (rsi > InpRSI_Max) return;

   if (prevBear && currBull && engulfs && bigBody && volOK)
   {
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl     = NormalizeDouble(low1 - atr * 0.25, digits);
      double slD    = ask - sl;
      if (slD <= 0) return;
      double tp     = NormalizeDouble(ask + slD * InpTP_RR, digits);
      double slPts  = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots   = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_MACD_Engulf_M1_L");
   }
}
