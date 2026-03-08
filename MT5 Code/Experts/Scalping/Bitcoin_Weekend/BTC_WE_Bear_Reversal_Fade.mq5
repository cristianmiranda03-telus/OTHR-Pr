//+------------------------------------------------------------------+
//| BTC_WE_Bear_Reversal_Fade.mq5                                    |
//| Strategy  : Extension Fade BAJISTA (contra-tendencia en extremos)|
//| Asset     : BTCUSD | Timeframe: M5 | Session: Weekend 24h        |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  Los fines de semana BTC suele tener movimientos de "fake pump"  |
//|  por baja liquidez. Cuando el precio sube demasiado lejos de la  |
//|  media (extension sobre 2x ATR desde EMA50) y el RSI llega a    |
//|  zona de extremo sobrecompra (> 75), el precio tiende a revertir.|
//|  Esta estrategia vende la extension extrema con confirmacion de: |
//|  1. Precio > EMA50 + 2x ATR (extension extrema)                 |
//|  2. RSI > 75 (sobrecompra extrema)                              |
//|  3. La vela M5 actual es bajista (cierre < apertura)             |
//|  4. CCI > 150 comenzando a revertir                             |
//|  Stop: sobre el maximo reciente (Donchian 10 periodos)          |
//|                                                                  |
//| Magic: 210005                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend Extension Fade Bear - M5 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== Extension Fade Configuracion ==="
input int    InpEMA_Period       = 50;    // EMA base de referencia
input double InpExtension_ATR    = 2.0;   // Extension minima sobre EMA en ATRs
input int    InpRSI_Period       = 14;
input double InpRSI_OB           = 75.0;  // RSI sobrecompra extrema
input int    InpCCI_Period       = 14;
input double InpCCI_OB           = 150.0; // CCI extremo overbought
input int    InpDonchian_SL      = 10;    // Barras Donchian para colocar SL

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.4;   // Riesgo conservador (fade es contra-tendencia)
input double InpTP_ATR_Mult      = 1.8;   // TP modesto hacia la media
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.1;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210005;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

bool IsWeekend()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsWeekend()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double ema50  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Period, 1);
   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open   = SC_Open(_Symbol, PERIOD_M5, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double cci    = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 1);
   double cci2   = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 2);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double donHigh = SC_GetHighestHigh(_Symbol, PERIOD_M5, InpDonchian_SL, 1);
   if (atr <= 0 || ema50 <= 0) return;

   // Condiciones de entrada: extension extrema alcista que comienza a revertir
   bool extended  = (close > ema50 + atr * InpExtension_ATR); // precio muy extendido
   bool overbought = (rsi > InpRSI_OB);                        // RSI extremo
   bool cciTurning = (cci < cci2) && (cci2 > InpCCI_OB);      // CCI girando desde extremo
   bool bearCandle = (close < open);                            // vela bajista

   if (extended && overbought && cciTurning && bearCandle)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      // SL sobre el maximo reciente (Donchian) + buffer
      double sl    = NormalizeDouble(donHigh + atr * 0.3, digits);
      double slD   = sl - bid;
      if (slD <= 0) return;
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_WE_Fade_Bear"))
         Print("VENTA Fade Bajista | extension=", close - ema50, " | rsi=", rsi);
   }
}
