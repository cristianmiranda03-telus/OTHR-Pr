//+------------------------------------------------------------------+
//| GOLD_Vol_Bull_MTF_Confluence.mq5                                 |
//| Strategy  : Confluencia Multi-Timeframe ALCISTA (MTF)            |
//| Asset     : XAUUSD | Timeframe: M1 (entrada) | Session: London+NY|
//|                                                                  |
//| Concepto  :                                                      |
//|  Una de las estrategias mas potentes para scalping profesional:  |
//|  confluencia de señales en multiples temporalidades.             |
//|  Se requiere alineacion en 3 niveles:                            |
//|                                                                  |
//|  NIVEL 1 - M15 (contexto macro):                                 |
//|   - EMA21 > EMA50 (tendencia alcista macro para scalping)        |
//|   - Precio sobre EMA21 M15                                       |
//|                                                                  |
//|  NIVEL 2 - M5 (tendencia intermedia):                            |
//|   - EMA8 > EMA21 (micro-tendencia alcista)                       |
//|   - RSI(14) entre 50-70 (momentum saludable)                     |
//|                                                                  |
//|  NIVEL 3 - M1 (entrada precisa):                                 |
//|   - Stoch(5,3,3) K cruza D desde abajo en zona < 40             |
//|   - La señal de entrada es la mas precisa posible                |
//|                                                                  |
//|  VOLATILIDAD: ATR M5 expandido > 1.2x promedio                  |
//|  Este nivel de confluencia da alta probabilidad de exito.        |
//|                                                                  |
//| Magic: 110006                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile MTF Confluence Bull - M1 entry"

#include "..\Common\Scalping_Common.mqh"

input group "=== M15 Contexto Macro ==="
input int    InpM15_EMA_Fast     = 21;
input int    InpM15_EMA_Slow     = 50;

input group "=== M5 Tendencia Intermedia ==="
input int    InpM5_EMA_Fast      = 8;
input int    InpM5_EMA_Slow      = 21;
input int    InpM5_RSI_Period    = 14;
input double InpM5_RSI_Min       = 50.0;
input double InpM5_RSI_Max       = 70.0;

input group "=== M1 Entrada Precisa ==="
input int    InpM1_Stoch_K       = 5;
input int    InpM1_Stoch_D       = 3;
input int    InpM1_Stoch_Slow    = 3;
input double InpM1_Stoch_Max     = 40.0;  // Entrada solo si stoch < este nivel

input group "=== Volatilidad ==="
input int    InpATR_Period       = 14;
input double InpATR_VolMult      = 1.2;
input int    InpATR_SMA_Bars     = 20;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.0;  // SL ajustado por ATR M1
input double InpTP_ATR_Mult      = 2.5;  // TP en ATR M5
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 60;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 110006;

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
   Print("GOLD_Vol_Bull_MTF_Confluence iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M1, g_lastBarM1)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   //--- NIVEL 1: M15 contexto alcista
   double m15_ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpM15_EMA_Fast, 1);
   double m15_ema50 = SC_GetEMA(_Symbol, PERIOD_M15, InpM15_EMA_Slow, 1);
   double m15_close = SC_Close(_Symbol,  PERIOD_M15, 1);
   bool   m15_bull  = (m15_ema21 > m15_ema50) && (m15_close > m15_ema21);

   if (!m15_bull) return; // Sin tendencia M15 alcista, no operar

   //--- NIVEL 2: M5 micro-tendencia alcista
   double m5_ema8   = SC_GetEMA(_Symbol, PERIOD_M5, InpM5_EMA_Fast, 1);
   double m5_ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpM5_EMA_Slow, 1);
   double m5_rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpM5_RSI_Period, 1);
   bool   m5_bull   = (m5_ema8 > m5_ema21) && (m5_rsi >= InpM5_RSI_Min) && (m5_rsi <= InpM5_RSI_Max);

   if (!m5_bull) return; // Sin confirmacion M5

   //--- NIVEL 3: M1 entrada en dip stochastico
   double k1, d1, k2, d2;
   SC_GetStoch(_Symbol, PERIOD_M1, InpM1_Stoch_K, InpM1_Stoch_D, InpM1_Stoch_Slow, 1, k1, d1);
   SC_GetStoch(_Symbol, PERIOD_M1, InpM1_Stoch_K, InpM1_Stoch_D, InpM1_Stoch_Slow, 2, k2, d2);
   bool   m1_entry  = (k1 > d1 && k2 <= d2 && k2 < InpM1_Stoch_Max); // stoch cross en oversold

   //--- Confirmacion de volatilidad
   double atr_m5    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR    = GetATR_Avg(InpATR_SMA_Bars);
   bool   highVol   = (avgATR <= 0 || atr_m5 >= avgATR * InpATR_VolMult);

   if (m1_entry && highVol)
   {
      double atr_m1  = SC_GetATR(_Symbol, PERIOD_M1, InpATR_Period, 1);
      if (atr_m1 <= 0) atr_m1 = atr_m5 / 5.0; // fallback
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl      = NormalizeDouble(ask - atr_m1 * InpSL_ATR_Mult * 3, digits); // SL en M1 ATR escalado
      double tp      = NormalizeDouble(ask + atr_m5 * InpTP_ATR_Mult, digits);     // TP en M5 ATR
      double slD     = ask - sl;
      if (slD <= 0) return;
      double slPts   = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots    = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_MTF_Bull"))
         Print("COMPRA MTF Confluencia | M15=bull | M5=bull | M1=stoch_cross | stoch_k=", k1);
   }
}
