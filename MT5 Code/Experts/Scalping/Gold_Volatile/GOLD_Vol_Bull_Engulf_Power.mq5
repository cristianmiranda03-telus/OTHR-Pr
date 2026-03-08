//+------------------------------------------------------------------+
//| GOLD_Vol_Bull_Engulf_Power.mq5                                   |
//| Strategy  : Vela Envolvente Alcista Potente (Power Engulfing)    |
//| Asset     : XAUUSD | Timeframe: M5 | Session: London + NY        |
//|                                                                  |
//| Concepto  :                                                      |
//|  La vela envolvente (engulfing) es uno de los patrones de price  |
//|  action mas fiables en mercados volatiles. Esta version avanzada  |
//|  filtra señales de baja calidad requiriendo:                     |
//|  1. PATRON: La vela actual (alcista) envuelve completamente a la  |
//|     vela anterior (bajista): open < close_prev AND close > open_prev|
//|  2. TAMAÑO: El cuerpo de la vela envolvente > 1.0 ATR (vela      |
//|     potente, no un microenvolvente)                              |
//|  3. CONTEXTO: Precio en zona de soporte (cerca de EMA50 o EMA21) |
//|  4. VOLUMEN: La vela envolvente tiene volumen > 1.5x promedio    |
//|  5. TENDENCIA SUPERIOR: En M15, el precio esta sobre EMA21       |
//|  El patron ocurre con frecuencia en momentos de alta volatilidad  |
//|  post-noticias o en apertura de sesiones.                        |
//|                                                                  |
//| Magic: 110003                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Volatile"
#property version   "1.00"
#property description "GOLD Volatile Power Engulfing Bull - M5"

#include "..\Common\Scalping_Common.mqh"

input group "=== Engulfing Pattern Configuracion ==="
input double InpMinBodyATR       = 1.0;   // Tamaño minimo del cuerpo en ATRs
input double InpMinVolMult       = 1.3;   // Volumen minimo vs promedio
input int    InpVolAvgBars       = 20;    // Barras promedio de volumen
input double InpSupportATR       = 1.5;   // Precio debe estar a max N ATRs de EMA21/50

input group "=== Filtros Multi-Timeframe ==="
input int    InpEMA_Fast_M5      = 21;    // EMA M5 cercana al precio (zona soporte)
input int    InpEMA_Slow_M5      = 50;
input int    InpEMA_M15          = 21;    // EMA M15 para tendencia superior
input int    InpRSI_Period       = 14;
input double InpRSI_Max          = 65.0;  // No comprar si RSI ya sobrecomprado

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_ATR_Mult      = 1.3;  // SL bajo el minimo de la vela envolvente
input double InpTP_ATR_Mult      = 2.8;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 60;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 110003;

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

   // Datos de las ultimas 2 barras M5
   double close1 = SC_Close(_Symbol, PERIOD_M5, 1); // barra actual (cerrada)
   double open1  = SC_Open(_Symbol,  PERIOD_M5, 1);
   double low1   = SC_Low(_Symbol,   PERIOD_M5, 1);
   double close2 = SC_Close(_Symbol, PERIOD_M5, 2); // barra anterior
   double open2  = SC_Open(_Symbol,  PERIOD_M5, 2);

   double ema21_m5  = SC_GetEMA(_Symbol, PERIOD_M5,  InpEMA_Fast_M5, 1);
   double ema50_m5  = SC_GetEMA(_Symbol, PERIOD_M5,  InpEMA_Slow_M5, 1);
   double ema21_m15 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_M15,     1);
   double rsi       = SC_GetRSI(_Symbol, PERIOD_M5,  InpRSI_Period,  1);
   double atr       = SC_GetATR(_Symbol, PERIOD_M5,  InpATR_Period,  1);
   double vol1      = (double)SC_Volume(_Symbol, PERIOD_M5, 1);
   double avgVol    = SC_AvgVolume(_Symbol, PERIOD_M5, InpVolAvgBars, 2);
   if (atr <= 0) return;

   // Patron envolvente alcista
   bool prevBearish   = (close2 < open2);                     // barra anterior bajista
   bool currBullish   = (close1 > open1);                     // barra actual alcista
   bool engulfs       = (open1 <= close2) && (close1 >= open2); // envuelve completamente
   double body        = close1 - open1;
   bool bigBody       = (body >= atr * InpMinBodyATR);         // cuerpo potente

   // Zona de soporte: precio cerca de EMA21 o EMA50
   double distEMA21   = MathAbs(low1 - ema21_m5);
   double distEMA50   = MathAbs(low1 - ema50_m5);
   bool nearSupport   = (distEMA21 < atr * InpSupportATR || distEMA50 < atr * InpSupportATR);

   // Confirmaciones adicionales
   bool volOK         = (avgVol <= 0 || vol1 >= avgVol * InpMinVolMult);
   bool m15Trend      = (close1 > ema21_m15); // tendencia M15 alcista
   bool rsiOK         = (rsi <= InpRSI_Max);

   if (prevBearish && currBullish && engulfs && bigBody && nearSupport && volOK && m15Trend && rsiOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      // SL bajo el minimo de la vela envolvente
      double sl    = NormalizeDouble(low1 - atr * 0.3, digits);
      double slD   = ask - sl;
      if (slD <= 0) return;
      double tp    = NormalizeDouble(ask + slD * InpTP_ATR_Mult / InpSL_ATR_Mult, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Engulf_Bull"))
         Print("COMPRA Power Engulfing | body=", body, " | vol_mult=", vol1/avgVol);
   }
}
