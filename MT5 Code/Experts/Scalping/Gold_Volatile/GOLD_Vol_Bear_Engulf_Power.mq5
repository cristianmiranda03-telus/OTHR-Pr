//+------------------------------------------------------------------+
//| GOLD_Vol_Bear_Engulf_Power.mq5                                   |
//| Strategy  : Vela Envolvente Bajista Potente (Power Engulfing)    |
//| Asset     : XAUUSD | Timeframe: M5 | Session: London + NY        |
//|                                                                  |
//| Concepto  :                                                      |
//|  Complementario de GOLD_Vol_Bull_Engulf_Power.                  |
//|  Una vela envolvente bajista en zona de resistencia (EMA21/50)   |
//|  con volumen por encima del promedio es señal de distribucion     |
//|  institucional. El Oro frecuentemente produce estos patrones     |
//|  justo antes de correcciones significativas.                     |
//|  Condiciones:                                                    |
//|  1. Vela anterior alcista envuelta por vela bajista actual        |
//|  2. Cuerpo bajista > 1.0 ATR                                    |
//|  3. Precio cerca de resistencia (EMA21 o EMA50 en M5)           |
//|  4. Volumen > 1.3x promedio                                     |
//|  5. RSI > 35 (evitar sobrevendido ya)                           |
//|                                                                  |
//| Magic: 110004                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile Power Engulfing Bear - M5"

#include "..\Common\Scalping_Common.mqh"

input group "=== Engulfing Pattern Configuracion ==="
input double InpMinBodyATR       = 1.0;
input double InpMinVolMult       = 1.3;
input int    InpVolAvgBars       = 20;
input double InpResistanceATR    = 1.5;

input group "=== Filtros Multi-Timeframe ==="
input int    InpEMA_Fast_M5      = 21;
input int    InpEMA_Slow_M5      = 50;
input int    InpEMA_M15          = 21;
input int    InpRSI_Period       = 14;
input double InpRSI_Min          = 35.0;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.3;
input double InpTP_ATR_Mult      = 2.8;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 60;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 110004;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bearish: 1=loose, 2=medium, 3=strict

CTrade   g_trade;
datetime g_lastBarM5 = 0;

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
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;
   if (InpUseMTF && !SC_MTF_BearOK(_Symbol, InpMTF_MinScore)) return;

   double close1  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open1   = SC_Open(_Symbol,  PERIOD_M5, 1);
   double high1   = SC_High(_Symbol,  PERIOD_M5, 1);
   double close2  = SC_Close(_Symbol, PERIOD_M5, 2);
   double open2   = SC_Open(_Symbol,  PERIOD_M5, 2);

   double ema21_m5  = SC_GetEMA(_Symbol, PERIOD_M5,  InpEMA_Fast_M5, 1);
   double ema50_m5  = SC_GetEMA(_Symbol, PERIOD_M5,  InpEMA_Slow_M5, 1);
   double ema21_m15 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_M15,     1);
   double rsi       = SC_GetRSI(_Symbol, PERIOD_M5,  InpRSI_Period,  1);
   double atr       = SC_GetATR(_Symbol, PERIOD_M5,  InpATR_Period,  1);
   double vol1      = (double)SC_Volume(_Symbol, PERIOD_M5, 1);
   double avgVol    = SC_AvgVolume(_Symbol, PERIOD_M5, InpVolAvgBars, 2);
   if (atr <= 0) return;

   bool prevBullish   = (close2 > open2);
   bool currBearish   = (close1 < open1);
   bool engulfs       = (open1 >= close2) && (close1 <= open2);
   double body        = open1 - close1;
   bool bigBody       = (body >= atr * InpMinBodyATR);

   // Zona de resistencia: precio cerca de EMA21 o EMA50
   double distEMA21   = MathAbs(high1 - ema21_m5);
   double distEMA50   = MathAbs(high1 - ema50_m5);
   bool nearResist    = (distEMA21 < atr * InpResistanceATR || distEMA50 < atr * InpResistanceATR);

   bool volOK         = (avgVol <= 0 || vol1 >= avgVol * InpMinVolMult);
   bool m15Trend      = (close1 < ema21_m15); // tendencia M15 bajista (o en retroceso)
   bool rsiOK         = (rsi >= InpRSI_Min);

   if (prevBullish && currBearish && engulfs && bigBody && nearResist && volOK && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(high1 + atr * 0.3, digits);
      double slD   = sl - bid;
      if (slD <= 0) return;
      double tp    = NormalizeDouble(bid - slD * InpTP_ATR_Mult / InpSL_ATR_Mult, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Engulf_Bear"))
         Print("VENTA Power Engulfing | body=", body, " | vol_mult=", vol1/avgVol);
   }
}
