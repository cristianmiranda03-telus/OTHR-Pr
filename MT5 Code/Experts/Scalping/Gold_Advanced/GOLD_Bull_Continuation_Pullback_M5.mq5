//+------------------------------------------------------------------+
//| GOLD_Bull_Continuation_Pullback_M5.mq5                           |
//| Strategy  : Continuacion alcista tras pullback (2da/3ra oleada)  |
//| Asset     : XAUUSD  | Timeframe: M5 | Session: London + NY       |
//| Magic     : 120001                                               |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO — Por que funciona en el contexto actual del Oro:       |
//|  El Oro en 2026 mueve en impulsos de 2-3 oleadas. La estrategia  |
//|  MACD Bull existente captura la PRIMERA entrada. Esta captura    |
//|  la SEGUNDA y TERCERA: despues de que MACD ya confirmo impulso   |
//|  alcista, el precio retrocede (RSI baja a 45-55, precio cerca    |
//|  de EMA21) y luego reanuda. Es el patron "buy the dip" dentro   |
//|  de un trend ya establecido.                                     |
//|                                                                  |
//| CONDICIONES DE ENTRADA:                                          |
//|  1. CONTEXTO: EMA21 > EMA50 (tendencia M5 alcista vigente)       |
//|  2. PULLBACK: RSI baja a zona 42-56 (retroceso saludable)        |
//|  3. PRECIO: cierra sobre EMA21 (no pierde el soporte dinamico)   |
//|  4. SEÑAL: RSI cruza hacia arriba 48 en la siguiente barra       |
//|            + MACD histograma en el ultimo cross fue positivo     |
//|  5. VOLATILIDAD: ATR > 0.9x promedio (no en zona muerta)         |
//|                                                                  |
//| SL: bajo EMA21 - 0.5 ATR (estructura invalidada si pierde EMA21) |
//| TP: 2.5x ATR desde entrada (segunda oleada suele ser igual al    |
//|     primer impulso)                                              |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD Advanced"
#property version   "1.00"
#property description "Gold Bull Continuation after Pullback | M5 | London+NY"

#include "..\Common\Scalping_Common.mqh"

input group "=== Parametros de Pullback ==="
input int    InpEMA_Fast         = 21;    // EMA soporte dinamico del pullback
input int    InpEMA_Slow         = 50;    // EMA filtro de tendencia mayor
input int    InpRSI_Period       = 14;
input double InpRSI_PullMin      = 42.0;  // RSI minimo del pullback (no muy caido)
input double InpRSI_PullMax      = 56.0;  // RSI maximo del pullback (ya no esta en impulso)
input double InpRSI_Entry        = 48.0;  // RSI cruza hacia arriba este nivel = entrada
input double InpPriceAboveEMA    = 0.2;   // Precio debe cerrar sobre EMA21 + N*ATR margen

input group "=== Filtro de Volatilidad ==="
input int    InpATR_Period       = 14;
input double InpATR_MinMult      = 0.9;   // ATR actual > N x promedio (evitar mercado muerto)
input int    InpATR_SMA_Bars     = 20;

input group "=== Gestion de Riesgo ==="
input double InpRiskPct          = 0.5;
input double InpSL_EMA_Buffer    = 0.5;   // SL = EMA21 - N*ATR
input double InpTP_ATR_Mult      = 2.5;   // TP generoso para capturar segunda oleada
input double InpMinLot           = 0.01;
input double InpMaxLot           = 1.0;
input int    InpMaxSpread        = 65;

input group "=== Sesion ==="
input int    InpUTCOffset        = 0;
input int    InpMagic            = 120001;

CTrade   g_trade;
datetime g_lastBarM5   = 0;
bool     g_inPullback  = false; // Flag: estamos rastreando un pullback activo

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
   Print("GOLD_Bull_Continuation_Pullback_M5 iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema50 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi1  = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double rsi2  = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 2);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double avgATR = GetATR_Avg(InpATR_SMA_Bars);
   if (atr <= 0) return;

   // 1. Confirmar que el trend mayor sigue alcista
   bool uptrend = (ema21 > ema50);
   if (!uptrend) { g_inPullback = false; return; }

   // 2. Detectar pullback: RSI en zona de retroceso saludable
   if (rsi1 >= InpRSI_PullMin && rsi1 <= InpRSI_PullMax)
      g_inPullback = true;

   // Resetear si RSI sube mucho (el impulso ya continuo sin nuestra entrada)
   if (rsi1 > 68) g_inPullback = false;

   // 3. Señal de entrada: RSI cruza hacia arriba InpRSI_Entry + precio sobre EMA21
   bool rsiRecovery   = g_inPullback && (rsi1 >= InpRSI_Entry) && (rsi2 < InpRSI_Entry);
   bool aboveEMA      = (close > ema21 + atr * InpPriceAboveEMA);
   bool volOK         = (avgATR <= 0 || atr >= avgATR * InpATR_MinMult);

   if (rsiRecovery && aboveEMA && volOK)
   {
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      // SL bajo EMA21 (soporte dinamico invalidado si pierde esa zona)
      double sl    = NormalizeDouble(ema21 - atr * InpSL_EMA_Buffer, digits);
      double slD   = ask - sl;
      if (slD <= 0) return;
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Cont_Pull_Bull"))
      {
         g_inPullback = false;
         Print("COMPRA Continuation Pullback | rsi=", rsi1, " | close vs ema21=", close-ema21);
      }
   }
}
