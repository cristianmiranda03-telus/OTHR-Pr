//+------------------------------------------------------------------+
//| GOLD_Vol_Bear_MTF_Confluence.mq5                                 |
//| Strategy  : Confluencia Multi-Timeframe BAJISTA (MTF)            |
//| Asset     : XAUUSD | Timeframe: M1 (entrada) | Session: London+NY|
//|                                                                  |
//| Concepto  :                                                      |
//|  Complementario de GOLD_Vol_Bull_MTF_Confluence.                |
//|  Se requiere alineacion bajista en 3 temporalidades:             |
//|                                                                  |
//|  NIVEL 1 - M15 (contexto macro):                                 |
//|   - EMA21 < EMA50 (tendencia bajista macro para scalping)        |
//|   - Precio bajo EMA21 M15                                        |
//|                                                                  |
//|  NIVEL 2 - M5 (tendencia intermedia):                            |
//|   - EMA8 < EMA21 (micro-tendencia bajista)                       |
//|   - RSI(14) entre 30-50 (momentum debil)                         |
//|                                                                  |
//|  NIVEL 3 - M1 (entrada precisa):                                 |
//|   - Stoch(5,3,3) K cruza D desde arriba en zona > 60            |
//|                                                                  |
//|  VOLATILIDAD: ATR M5 expandido > 1.2x promedio                  |
//|                                                                  |
//| Magic: 110007                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile MTF Confluence Bear - M1 entry"

#include "..\Common\Scalping_Common.mqh"

input group "=== M15 Contexto Macro ==="
input int    InpM15_EMA_Fast     = 21;
input int    InpM15_EMA_Slow     = 50;

input group "=== M5 Tendencia Intermedia ==="
input int    InpM5_EMA_Fast      = 8;
input int    InpM5_EMA_Slow      = 21;
input int    InpM5_RSI_Period    = 14;
input double InpM5_RSI_Min       = 30.0;
input double InpM5_RSI_Max       = 50.0;

input group "=== M1 Entrada Precisa ==="
input int    InpM1_Stoch_K       = 5;
input int    InpM1_Stoch_D       = 3;
input int    InpM1_Stoch_Slow    = 3;
input double InpM1_Stoch_Min     = 60.0;  // Entrada solo si stoch > este nivel

input group "=== Volatilidad ==="
input int    InpATR_Period       = 14;
input double InpATR_VolMult      = 1.2;
input int    InpATR_SMA_Bars     = 20;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.0;
input double InpTP_ATR_Mult      = 2.5;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 60;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 110007;

CTrade   g_trade;
datetime g_lastBarM1 = 0;

double GetATR_Avg(int bars)
{
   double sum = 0;
   for (int i = 2; i <= bars + 1; i++)
      sum += SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, i);
   return (bars > 0) ? sum / bars : 0;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M1, g_lastBarM1)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   //--- NIVEL 1: M15 contexto bajista
   double m15_ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpM15_EMA_Fast, 1);
   double m15_ema50 = SC_GetEMA(_Symbol, PERIOD_M15, InpM15_EMA_Slow, 1);
   double m15_close = SC_Close(_Symbol,  PERIOD_M15, 1);
   bool   m15_bear  = (m15_ema21 < m15_ema50) && (m15_close < m15_ema21);
   if (!m15_bear) return;

   //--- NIVEL 2: M5 micro-tendencia bajista
   double m5_ema8   = SC_GetEMA(_Symbol, PERIOD_M5, InpM5_EMA_Fast, 1);
   double m5_ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpM5_EMA_Slow, 1);
   double m5_rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpM5_RSI_Period, 1);
   bool   m5_bear   = (m5_ema8 < m5_ema21) && (m5_rsi >= InpM5_RSI_Min) && (m5_rsi <= InpM5_RSI_Max);
   if (!m5_bear) return;

   //--- NIVEL 3: M1 entrada en pico stochastico
   double k1, d1, k2, d2;
   SC_GetStoch(_Symbol, PERIOD_M1, InpM1_Stoch_K, InpM1_Stoch_D, InpM1_Stoch_Slow, 1, k1, d1);
   SC_GetStoch(_Symbol, PERIOD_M1, InpM1_Stoch_K, InpM1_Stoch_D, InpM1_Stoch_Slow, 2, k2, d2);
   bool m1_entry = (k1 < d1 && k2 >= d2 && k2 > InpM1_Stoch_Min);

   //--- Confirmacion de volatilidad
   double atr_m5  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR  = GetATR_Avg(InpATR_SMA_Bars);
   bool   highVol = (avgATR <= 0 || atr_m5 >= avgATR * InpATR_VolMult);

   if (m1_entry && highVol)
   {
      double atr_m1  = SC_GetATR(_Symbol, PERIOD_M1, InpATR_Period, 1);
      if (atr_m1 <= 0) atr_m1 = atr_m5 / 5.0;
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl      = NormalizeDouble(bid + atr_m1 * InpSL_ATR_Mult * 3, digits);
      double tp      = NormalizeDouble(bid - atr_m5 * InpTP_ATR_Mult, digits);
      double slD     = sl - bid;
      if (slD <= 0) return;
      double slPts   = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots    = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_MTF_Bear"))
         Print("VENTA MTF Confluencia | M15=bear | M5=bear | M1=stoch_cross | stoch_k=", k1);
   }
}
