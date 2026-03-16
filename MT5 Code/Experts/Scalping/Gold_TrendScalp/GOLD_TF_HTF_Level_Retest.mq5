//+------------------------------------------------------------------+
//| GOLD_TF_HTF_Level_Retest.mq5                                    |
//| Strategy: HTF Key Level Retest Scalper (GOLD)                   |
//| Asset: XAUUSD | Timeframe: H1 levels / M5 entry                 |
//| Magic: 130006                                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO:                                                        |
//|  El oro tiene niveles clave de H1 (máximos y mínimos recientes) |
//|  que se convierten en soporte/resistencia cuando son rotos.     |
//|  Este EA detecta cuando el H1 ha cerrado por encima de su       |
//|  máximo de los últimas N barras H1 (break de nivel clave),      |
//|  y luego scalpa la primera vez que el precio vuelve a retestear |
//|  ese nivel (ahora soporte) en M5, alineado con la tendencia     |
//|  D1.                                                             |
//|                                                                  |
//| CONDICIONES LONG (Break alcista + Retest):                      |
//|  1. D1 alcista (SC_TrendDir_D1 >= 0)                            |
//|  2. H1 cerró por encima del máximo de los últimas InpH1_Lookback|
//|     barras H1 (breakout de nivel H1)                            |
//|  3. En M5: precio retrocede hasta el nivel roto ± 0.5 ATR(M5)  |
//|  4. RSI(14) M5 entre 38 y 58 (zona de retest saludable)         |
//|  5. Vela M5 de confirmación alcista (hammer o bullish close)    |
//|                                                                  |
//| CONDICIONES SHORT (Break bajista + Retest):                     |
//|  1. D1 bajista (SC_TrendDir_D1 <= 0)                            |
//|  2. H1 cerró por debajo del mínimo de las últimas N barras H1   |
//|  3. Precio sube al retest de ese mínimo ahora resistencia       |
//|  4. RSI entre 42 y 62                                           |
//|  5. Vela bajista de confirmación                                |
//|                                                                  |
//| SL: 0.6 ATR más allá del nivel de retest                       |
//| TP: 2.5R (breakouts H1 suelen dar continuaciones largas en oro) |
//| Ventana retest: máx 8 barras M5 desde el breakout H1           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD TrendScalp"
#property version   "1.00"
#property description "GOLD HTF Level Retest Scalp | H1 break + M5 retest | D1 aligned"

#include "..\Common\Scalping_Common.mqh"

input group "=== Configuración de Niveles H1 ==="
input int    InpH1_Lookback     = 8;     // Barras H1 para detectar máximo/mínimo significativo
input int    InpH1_EMA_Confirm  = 21;    // EMA H1 confirma tendencia (breakout debe estar sobre ella)
input int    InpRetest_Window   = 8;     // Barras M5 máximas para el retest después del breakout H1

input group "=== Parámetros Retest M5 ==="
input double InpLevel_Buffer    = 0.5;   // ATR buffer para considerar que el precio "tocó" el nivel
input int    InpRSI_Period      = 14;
input double InpRSI_Bull_Min    = 38.0;
input double InpRSI_Bull_Max    = 58.0;
input double InpRSI_Bear_Min    = 42.0;
input double InpRSI_Bear_Max    = 62.0;
input int    InpATR_Period      = 14;

input group "=== Gestión de Riesgo ==="
input double InpRiskPct         = 0.5;
input double InpSL_ATR_Mult     = 0.6;
input double InpTP_RR           = 2.5;
input double InpMinLot          = 0.01;
input double InpMaxLot          = 1.0;
input int    InpMaxSpread       = 60;

input group "=== Sesión y Trade ==="
input int    InpUTCOffset       = 0;
input int    InpMagic           = 130006;

CTrade   g_trade;
datetime g_lastBarM5  = 0;

// Estado del breakout detectado
bool     g_bullBreak  = false;
bool     g_bearBreak  = false;
double   g_breakLevel = 0;
datetime g_breakTime  = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_TF_HTF_Level_Retest iniciado | Magic=", InpMagic);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void CheckH1Breakout()
{
   double h1Close    = SC_Close(_Symbol, PERIOD_H1, 1);
   double h1Open     = SC_Open(_Symbol,  PERIOD_H1, 1);
   double h1High     = SC_High(_Symbol,  PERIOD_H1, 1);
   double h1Low      = SC_Low(_Symbol,   PERIOD_H1, 1);
   double ema21H1    = SC_GetEMA(_Symbol, PERIOD_H1, InpH1_EMA_Confirm, 1);
   // Nivel de los últimos InpH1_Lookback barras H1 (excluyendo la barra actual)
   double prevH1High = SC_GetHighestHigh(_Symbol, PERIOD_H1, InpH1_Lookback, 2);
   double prevH1Low  = SC_GetLowestLow(_Symbol,   PERIOD_H1, InpH1_Lookback, 2);

   // Bull breakout: H1 cierra por encima del máximo previo Y sobre EMA21
   if (h1Close > prevH1High && h1Close > ema21H1 && h1Close > h1Open)
   {
      g_bullBreak  = true;
      g_bearBreak  = false;
      g_breakLevel = prevH1High;
      g_breakTime  = iTime(_Symbol, PERIOD_H1, 1);
      return;
   }
   // Bear breakout: H1 cierra por debajo del mínimo previo Y bajo EMA21
   if (h1Close < prevH1Low && h1Close < ema21H1 && h1Close < h1Open)
   {
      g_bearBreak  = true;
      g_bullBreak  = false;
      g_breakLevel = prevH1Low;
      g_breakTime  = iTime(_Symbol, PERIOD_H1, 1);
   }
}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // Detectar nuevos breakouts H1
   CheckH1Breakout();

   if (!g_bullBreak && !g_bearBreak) return;
   if (g_breakLevel <= 0 || g_breakTime == 0) return;

   // Verificar que estamos dentro de la ventana de retest
   datetime m5Time[]; ArraySetAsSeries(m5Time, true);
   if (CopyTime(_Symbol, PERIOD_M5, 0, 1, m5Time) < 1) return;
   int m5BarsSinceBreak = (int)((m5Time[0] - g_breakTime) / (5 * 60));
   if (m5BarsSinceBreak > InpRetest_Window) { g_bullBreak = g_bearBreak = false; return; }

   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open1  = SC_Open(_Symbol,  PERIOD_M5, 1);
   double high1  = SC_High(_Symbol,  PERIOD_M5, 1);
   double low1   = SC_Low(_Symbol,   PERIOD_M5, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   if (atr <= 0) return;

   double range  = high1 - low1;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buf    = atr * InpLevel_Buffer;

   // LONG: retest del nivel roto (ahora soporte)
   if (g_bullBreak && SC_TrendDir_D1(_Symbol) >= 0)
   {
      bool retested  = (low1 <= g_breakLevel + buf && close > g_breakLevel - buf);
      bool rsiOK     = (rsi >= InpRSI_Bull_Min && rsi <= InpRSI_Bull_Max);
      bool bullCnfm  = (close > open1 && range > 1e-9 && (close - open1) / range >= 0.40);

      if (retested && rsiOK && bullCnfm)
      {
         double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl   = NormalizeDouble(g_breakLevel - atr * InpSL_ATR_Mult, digits);
         double riskD = ask - sl;
         if (riskD <= 0) return;
         double tp   = NormalizeDouble(ask + riskD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      InpRiskPct, InpMinLot, InpMaxLot);
         if (lots >= InpMinLot && g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_TF_HTF_L"))
         {
            Print("COMPRA HTF Retest | Level=", g_breakLevel, " | RSI=", rsi,
                  " | SL=", sl, " | TP=", tp);
            g_bullBreak = false;
         }
      }
   }

   // SHORT: retest del nivel roto (ahora resistencia)
   if (g_bearBreak && SC_TrendDir_D1(_Symbol) <= 0)
   {
      bool retested  = (high1 >= g_breakLevel - buf && close < g_breakLevel + buf);
      bool rsiOK     = (rsi >= InpRSI_Bear_Min && rsi <= InpRSI_Bear_Max);
      bool bearCnfm  = (close < open1 && range > 1e-9 && (open1 - close) / range >= 0.40);

      if (retested && rsiOK && bearCnfm)
      {
         double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl   = NormalizeDouble(g_breakLevel + atr * InpSL_ATR_Mult, digits);
         double riskD = sl - bid;
         if (riskD <= 0) return;
         double tp   = NormalizeDouble(bid - riskD * InpTP_RR, digits);
         double lots = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      InpRiskPct, InpMinLot, InpMaxLot);
         if (lots >= InpMinLot && g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_TF_HTF_S"))
         {
            Print("VENTA HTF Retest | Level=", g_breakLevel, " | RSI=", rsi,
                  " | SL=", sl, " | TP=", tp);
            g_bearBreak = false;
         }
      }
   }
}
