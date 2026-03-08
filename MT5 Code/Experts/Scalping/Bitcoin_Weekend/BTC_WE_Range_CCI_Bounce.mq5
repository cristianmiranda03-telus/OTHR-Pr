//+------------------------------------------------------------------+
//| BTC_WE_Range_CCI_Bounce.mq5                                      |
//| Strategy  : CCI Oscillator Range Bounce (ambas direcciones)      |
//| Asset     : BTCUSD | Timeframe: M5/M15 | Session: Weekend 24h    |
//| Timezone  : UTC-6 (Central Time)                                 |
//|                                                                  |
//| Concepto  :                                                      |
//|  Los fines de semana BTC tiende a rangear. El CCI (Commodity     |
//|  Channel Index) oscila entre -200 y +200 en condiciones de rango.|
//|  Esta estrategia opera rebotes en los extremos:                  |
//|  - CCI < -150 y vuelve a cruzar -100 desde abajo = COMPRA       |
//|  - CCI > +150 y vuelve a cruzar +100 desde arriba = VENTA       |
//|  Filtro adicional: el rango del mercado se confirma con un       |
//|  ADX < 25 (tendencia debil) y BB ancho estrecho.                 |
//|  Trades frecuentes y cortos, ideal para scalping de fin semana.  |
//|                                                                  |
//| Magic: 210003                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend Range CCI Bounce - M5 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

input group "=== CCI Configuracion ==="
input int    InpCCI_Period       = 14;    // Periodo del CCI
input double InpCCI_ExtremeBuy   = -150.0; // CCI debe haber estado bajo este nivel (extremo OS)
input double InpCCI_EntryBuy     = -100.0; // Cruzar de nuevo sobre este nivel = entrada compra
input double InpCCI_ExtremeSell  = 150.0;  // CCI debe haber estado sobre este nivel (extremo OB)
input double InpCCI_EntrySell    = 100.0;  // Cruzar de nuevo bajo este nivel = entrada venta

input group "=== Filtro de Rango (ADX) ==="
input int    InpADX_Period       = 14;    // Periodo ADX
input double InpADX_Max          = 25.0;  // ADX maximo para confirmar rango (< 25 = sin tendencia)

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.4;
input double InpSL_ATR_Mult      = 1.0;
input double InpTP_ATR_Mult      = 1.8;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.001;
input double InpMaxLot           = 0.1;
input int    InpMaxSpread        = 600;

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;
input int    InpMagic            = 210003;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
bool     g_cciWasExtremeLow  = false; // Flag: CCI estuvo bajo el extremo OS
bool     g_cciWasExtremeHigh = false; // Flag: CCI estuvo sobre el extremo OB

//+------------------------------------------------------------------+
//| Obtiene el valor ADX (usa iADX handle)                           |
//+------------------------------------------------------------------+
double GetADX(int shift = 1)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   int h = iADX(_Symbol, PERIOD_M5, InpADX_Period);
   if (h == INVALID_HANDLE) return 50; // Asumir tendencia si falla
   double v = (CopyBuffer(h, 0, shift, 1, buf) >= 1) ? buf[0] : 50;
   IndicatorRelease(h);
   return v;
}

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
   Print("BTC_WE_Range_CCI_Bounce iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsWeekend()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double cci1 = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 1); // ultima barra cerrada
   double cci2 = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 2); // barra anterior
   double adx  = GetADX(1);
   double atr  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   // Confirmar rango: ADX < 25
   bool isRange = (adx < InpADX_Max);

   // Actualizar flags de extremos
   if (cci1 < InpCCI_ExtremeBuy)  g_cciWasExtremeLow  = true;
   if (cci1 > InpCCI_ExtremeSell) g_cciWasExtremeHigh = true;
   // Resetear flags cuando CCI se normaliza
   if (cci1 > 0)  g_cciWasExtremeLow  = false;
   if (cci1 < 0)  g_cciWasExtremeHigh = false;

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // COMPRA: CCI rebota desde extremo OS hacia arriba sobre InpCCI_EntryBuy
   bool buySignal = isRange && g_cciWasExtremeLow
                    && (cci1 >= InpCCI_EntryBuy) && (cci2 < InpCCI_EntryBuy);

   // VENTA: CCI rebota desde extremo OB hacia abajo bajo InpCCI_EntrySell
   bool sellSignal = isRange && g_cciWasExtremeHigh
                     && (cci1 <= InpCCI_EntrySell) && (cci2 > InpCCI_EntrySell);

   if (buySignal && SC_CountPositions(POSITION_TYPE_BUY, InpMagic) == 0)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_WE_CCI_BUY"))
      {
         g_cciWasExtremeLow = false;
         Print("COMPRA CCI Bounce | cci=", cci1, " | adx=", adx);
      }
   }
   else if (sellSignal && SC_CountPositions(POSITION_TYPE_SELL, InpMagic) == 0)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_WE_CCI_SELL"))
      {
         g_cciWasExtremeHigh = false;
         Print("VENTA CCI Bounce | cci=", cci1, " | adx=", adx);
      }
   }
}
