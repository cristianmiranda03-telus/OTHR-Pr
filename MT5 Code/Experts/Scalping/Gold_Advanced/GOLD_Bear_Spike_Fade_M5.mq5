//+------------------------------------------------------------------+
//| GOLD_Bear_Spike_Fade_M5.mq5                                      |
//| Strategy  : Fade de spike alcista falso (contra-impulso puntual) |
//| Asset     : XAUUSD  | Timeframe: M5 | Session: London + NY       |
//| Magic     : 120005                                               |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO — Por que funciona en el contexto actual del Oro:       |
//|  El Oro frecuentemente produce "fake pumps" en noticias          |
//|  ambiguas o en gaps de liquidez. La estructura es:               |
//|  - Una vela M5 con ATR > 2x baseline (extreme spike alcista)     |
//|  - El movimiento NO tiene continuacion — es un spike aislado     |
//|  - En la siguiente vela, el precio revierte al menos 50%         |
//|  del spike mientras el "squeeze" de posiciones largas se         |
//|  deshace.                                                        |
//|                                                                  |
//|  DIFERENCIA clave vs Bear ATR Expansion:                         |
//|  - ATR Expansion busca continuation de un breakdown              |
//|  - Spike Fade busca REVERSION de un spike alcista aislado        |
//|  Son estrategias complementarias: una opera tendencia,           |
//|  la otra opera la trampa.                                        |
//|                                                                  |
//| CONDICIONES DE ENTRADA (en la barra SIGUIENTE al spike):         |
//|  1. Barra anterior: ATR_bar > 2x ATR_baseline (extreme spike)    |
//|  2. Barra anterior: es alcista (close > open) — spike hacia arb  |
//|  3. Barra anterior: cuerpo > 1.5 ATR (movimiento grande)         |
//|  4. Barra actual: abre y la primera accion es bajista             |
//|     (close_actual < open_actual en la barra cerrada)             |
//|  5. EMA50 en M5: el spike esta SOBRE EMA50 en zona de resistencia|
//|  6. RSI de la barra del spike > 70 (extremo sobrecompra)         |
//|                                                                  |
//| SL: sobre el maximo del spike + 0.4 ATR                          |
//| TP: 1.8x riesgo (reversion parcial — no busca tendencia completa)|
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Advanced"
#property version   "1.00"
#property description "Gold Bear Spike Fade (anti-fake pump) | M5 | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== Deteccion del Spike ==="
input int    InpATR_Period       = 5;     // ATR corto para medir el spike (sensible)
input int    InpATR_Baseline     = 20;    // Barras para la baseline del ATR
input double InpSpike_ATR_Mult   = 2.0;  // El spike debe ser > N x ATR baseline
input double InpSpike_Body_ATR   = 1.5;  // Cuerpo del spike > N x ATR baseline
input double InpRSI_Spike_Min    = 70.0; // RSI del spike en sobrecompra

input group "=== Confirmacion de Reversion ==="
input int    InpEMA_Resist       = 50;   // EMA de resistencia (spike debe estar sobre ella)
input double InpBody_Confirm     = 0.3;  // Cuerpo minimo de la vela de confirmacion en ATR

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.4;  // Riesgo conservador (fade es contra-tendencia)
input double InpSL_SpikeBuffer   = 0.4;  // SL sobre el maximo del spike en ATR
input double InpTP_RR            = 1.8;  // Ratio riesgo/recompensa
input double InpMinLot           = 0.01;
input double InpMaxLot           = 0.8;
input int    InpMaxSpread        = 65;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 120005;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

// Obtiene el ATR de una barra especifica usando el rango H-L-C anterior
double GetBarATR(int shift)
{
   return SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, shift);
}

// Calcula ATR promedio de los InpATR_Baseline barras antes del shift
double GetATRBaseline(int shift)
{
   double sum = 0;
   for (int i = shift + 1; i <= shift + InpATR_Baseline; i++)
      sum += GetBarATR(i);
   return (InpATR_Baseline > 0) ? sum / InpATR_Baseline : 0;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_Bear_Spike_Fade_M5 iniciado | Spike mult=", InpSpike_ATR_Mult, "x | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // --- Analizar la barra anterior (el posible spike) ---
   double spikeClose = SC_Close(_Symbol, PERIOD_M5, 2); // barra del spike
   double spikeOpen  = SC_Open(_Symbol,  PERIOD_M5, 2);
   double spikeHigh  = SC_High(_Symbol,  PERIOD_M5, 2);
   double spikeBody  = spikeClose - spikeOpen; // positivo si alcista

   double spikeATR   = GetBarATR(2);           // ATR en el momento del spike
   double baseline   = GetATRBaseline(2);       // ATR promedio antes del spike
   if (baseline <= 0 || spikeATR <= 0) return;

   // --- Analizar la barra actual (confirmacion de reversion) ---
   double confirmClose = SC_Close(_Symbol, PERIOD_M5, 1);
   double confirmOpen  = SC_Open(_Symbol,  PERIOD_M5, 1);
   double confirmBody  = confirmOpen - confirmClose; // positivo si bajista

   double ema50     = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Resist, 1);
   double rsiSpike  = SC_GetRSI(_Symbol, PERIOD_M5, 14, 2); // RSI del spike
   double atrNow    = GetBarATR(1);

   // Condicion 1: la barra anterior fue un spike extremo alcista
   bool wasBigSpike  = (spikeATR >= baseline * InpSpike_ATR_Mult);
   bool wasAlcista   = (spikeBody >= baseline * InpSpike_Body_ATR);
   bool wasOverbought = (rsiSpike >= InpRSI_Spike_Min);

   // Condicion 2: el spike ocurrio en zona de resistencia (sobre EMA50)
   bool atResistance = (spikeClose > ema50);

   // Condicion 3: la barra actual confirma reversion bajista
   bool confirmBear  = (confirmBody >= atrNow * InpBody_Confirm);

   if (wasBigSpike && wasAlcista && wasOverbought && atResistance && confirmBear)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      // SL sobre el maximo del spike
      double sl    = NormalizeDouble(spikeHigh + atrNow * InpSL_SpikeBuffer, digits);
      double slD   = sl - bid;
      if (slD <= 0) return;
      double tp    = NormalizeDouble(bid - slD * InpTP_RR, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Spike_Fade"))
         Print("VENTA Spike Fade | spike_atr=", spikeATR, " | baseline=", baseline,
               " | ratio=", spikeATR/baseline, "x | rsi_spike=", rsiSpike);
   }
}
