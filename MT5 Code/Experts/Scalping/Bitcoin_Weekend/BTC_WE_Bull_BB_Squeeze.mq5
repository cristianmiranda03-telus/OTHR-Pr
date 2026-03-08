//+------------------------------------------------------------------+
//| BTC_WE_Bull_BB_Squeeze.mq5                                       |
//| Strategy  : Bollinger Band Squeeze BULLISH Breakout              |
//| Asset     : BTCUSD | Timeframe: M15 | Session: Weekend 24h       |
//| Timezone  : UTC-6 (Central Time, e.g. Mexico City / Chicago)     |
//|                                                                  |
//| Concepto  :                                                      |
//|  El "squeeze" de Bandas de Bollinger indica que la volatilidad   |
//|  ha comprimido el precio en un rango estrecho. Cuando las bandas |
//|  se expanden nuevamente (la expansion comienza), se produce un   |
//|  impulso direccional explosivo.                                  |
//|  Este EA detecta:                                                |
//|  1. Squeeze: ancho BB < ancho minimo de los ultimos N bares      |
//|  2. Expansion: la banda comienza a abrirse (width crece)         |
//|  3. Direccion alcista: precio cierra sobre BB mid + EMA21 UP     |
//|  4. Confirmacion: CCI > 0 (momentum positivo)                   |
//|  Solo opera en fin de semana (sabado-domingo UTC).               |
//|                                                                  |
//| Magic: 210001                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC Weekend"
#property version   "1.00"
#property description "BTC Weekend Squeeze Bull - M15 - UTC-6"

#include "..\Common\Scalping_Common.mqh"

//--- Inputs
input group "=== Bollinger Band Squeeze ==="
input int    InpBB_Period        = 20;    // Periodo de las Bandas de Bollinger
input double InpBB_Dev           = 2.0;   // Desviacion estandar BB
input int    InpSqueeze_Lookback = 30;    // Barras para detectar squeeze (minimo historico)
input double InpExpansion_Pct    = 0.05;  // % de expansion minimo respecto al squeeze minimo

input group "=== Filtros de Confirmacion ==="
input int    InpEMA_Period       = 21;    // EMA de tendencia
input int    InpCCI_Period       = 14;    // CCI momentum
input int    InpATR_Period       = 14;    // ATR para SL/TP dinamico

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;   // Riesgo por operacion (% del equity)
input double InpSL_ATR_Mult      = 1.5;   // Multiplicador ATR para Stop Loss
input double InpTP_ATR_Mult      = 3.0;   // Multiplicador ATR para Take Profit
input double InpMinLot           = 0.001; // Lote minimo
input double InpMaxLot           = 0.2;   // Lote maximo
input int    InpMaxSpread        = 600;   // Spread maximo permitido (puntos)

input group "=== Configuracion de Sesion ==="
input int    InpUTCOffset        = -6;    // Offset UTC del broker (-6 para UTC-6)
input int    InpMagic            = 210001; // Numero magico unico

//--- Globales
CTrade   g_trade;
datetime g_lastBarM15 = 0;

//+------------------------------------------------------------------+
//| Calcula el ancho de BB (upper - lower) en la barra shift         |
//+------------------------------------------------------------------+
double GetBBWidth(int shift)
{
   double u, m, l;
   SC_GetBB(_Symbol, PERIOD_M15, InpBB_Period, InpBB_Dev, shift, u, m, l);
   return (u > 0) ? (u - l) : 0;
}

//+------------------------------------------------------------------+
//| Detecta squeeze: el ancho actual es el minimo de los ultimos N   |
//+------------------------------------------------------------------+
bool IsSqueeze(int shift = 1)
{
   double currentWidth = GetBBWidth(shift);
   if (currentWidth <= 0) return false;
   for (int i = shift + 1; i <= shift + InpSqueeze_Lookback; i++)
   {
      if (GetBBWidth(i) <= currentWidth) return false; // No es el minimo
   }
   return true; // Es el ancho minimo -> squeeze
}

//+------------------------------------------------------------------+
//| Detecta que el squeeze acaba de expandirse respecto a barra prev |
//+------------------------------------------------------------------+
bool IsExpanding()
{
   double w1 = GetBBWidth(1); // barra cerrada mas reciente
   double w2 = GetBBWidth(2); // barra anterior
   if (w1 <= 0 || w2 <= 0) return false;
   // Se expande si el ancho actual supera el anterior por el % minimo
   return (w1 > w2 * (1.0 + InpExpansion_Pct));
}

//+------------------------------------------------------------------+
//| Verifica si es fin de semana (sabado=6, domingo=0 en UTC)        |
//+------------------------------------------------------------------+
bool IsWeekend()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("BTC_WE_Bull_BB_Squeeze iniciado | Magic=", InpMagic, " | UTC Offset=", InpUTCOffset);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Print("BTC_WE_Bull_BB_Squeeze detenido."); }

//+------------------------------------------------------------------+
void OnTick()
{
   // Solo operar en fin de semana
   if (!IsWeekend()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M15, g_lastBarM15)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double upper, mid, lower;
   SC_GetBB(_Symbol, PERIOD_M15, InpBB_Period, InpBB_Dev, 1, upper, mid, lower);
   double close = SC_Close(_Symbol, PERIOD_M15, 1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M15, InpEMA_Period, 1);
   double cci   = SC_GetCCI(_Symbol, PERIOD_M15, InpCCI_Period, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M15, InpATR_Period, 1);
   if (atr <= 0 || upper <= 0) return;

   // Condicion: squeeze detectado en barra anterior y expansion comienza ahora
   bool squeezeWas = IsSqueeze(2);   // barra 2 era squeeze
   bool nowExpand  = IsExpanding();   // barra 1 comienza a expandirse
   bool bullDir    = (close > mid) && (close > ema21); // direccion alcista
   bool cciOK      = (cci > 0);      // momentum positivo

   if (squeezeWas && nowExpand && bullDir && cciOK)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_WE_Squeeze_Bull"))
         Print("Entrada COMPRA | lots=", lots, " | BB Squeeze expansion alcista");
   }
}
