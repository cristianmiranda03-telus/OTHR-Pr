//+------------------------------------------------------------------+
//| GOLD_TF_Daily_Bias_Scalp.mq5                                    |
//| Strategy: Daily Bias Adaptive Scalper (GOLD)                    |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY            |
//| Magic: 130005                                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//| CONCEPTO:                                                        |
//|  Un solo EA bidireccional que cambia automáticamente de modo     |
//|  alcista a bajista dependiendo del "Daily Bias" del oro.        |
//|  Calcula el sesgo diario usando 3 factores:                     |
//|   - D1: precio vs EMA50 diaria y pendiente                      |
//|   - H1: estructura (H1 score)                                   |
//|   - Distancia al pivot diario (H/L/Close del día anterior)      |
//|                                                                  |
//| LÓGICA DE ENTRADA:                                              |
//|  MODO LONG (bias = +2 o +3):                                    |
//|   - MACD(8,21,5) cruza cero hacia arriba en M5                  |
//|   - Precio > EMA21(M5) + RSI 45-70                              |
//|   - Precio sobre el pivot midpoint (H1 High + Low previo / 2)  |
//|                                                                  |
//|  MODO SHORT (bias = -2 o -3):                                   |
//|   - MACD(8,21,5) cruza cero hacia abajo en M5                  |
//|   - Precio < EMA21(M5) + RSI 30-55                              |
//|   - Precio bajo el pivot midpoint                               |
//|                                                                  |
//|  MODO NEUTRAL (bias -1..+1): NO opera (mercado indeciso)        |
//|                                                                  |
//| SL: 1.2 ATR | TP: 2.2R en modo tendencia fuerte (±3), 1.8R si ±2|
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD TrendScalp"
#property version   "1.00"
#property description "GOLD Daily Bias Adaptive Scalp | M5 MACD entry | Auto Bull/Bear"

#include "..\Common\Scalping_Common.mqh"

input group "=== Daily Bias Filter ==="
input int    InpBias_MinAbs    = 2;      // Bias mínimo absoluto para operar (2 o 3)

input group "=== MACD Entrada M5 ==="
input int    InpMACD_Fast      = 8;
input int    InpMACD_Slow      = 21;
input int    InpMACD_Signal    = 5;
input int    InpEMA_Period     = 21;
input int    InpRSI_Period     = 14;

input group "=== Gestión de Riesgo ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_RR_Strong   = 2.2;   // R:R cuando score = ±3
input double InpTP_RR_Weak     = 1.8;   // R:R cuando score = ±2
input int    InpATR_Period     = 14;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;
input int    InpMaxTradesDay   = 3;      // Máx operaciones por día

input group "=== Sesión y Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 130005;

CTrade   g_trade;
datetime g_lastBarM5 = 0;
datetime g_lastDay   = 0;
int      g_tradesToday = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(SC_GetFillMode());
   Print("GOLD_TF_Daily_Bias_Scalp iniciado | Magic=", InpMagic, " | MinBias=", InpBias_MinAbs);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // Contador diario
   datetime today = (datetime)((long)TimeGMT() / 86400 * 86400);
   if (today != g_lastDay) { g_lastDay = today; g_tradesToday = 0; }
   if (g_tradesToday >= InpMaxTradesDay) return;

   // Calcular Daily Bias (D1 + H1)
   int mtfScore = SC_MTF_Score(_Symbol);
   // Retiramos M15 del sesgo diario: usamos D1 (x2 peso) + H1 (x1 peso)
   int biasScore = SC_TrendDir_D1(_Symbol) * 2 + SC_TrendDir_H1(_Symbol);
   // biasScore range: -3..+3

   if (MathAbs(biasScore) < InpBias_MinAbs) return;

   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double ema21  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Period, 1);
   double rsi    = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double close  = SC_Close(_Symbol,  PERIOD_M5, 1);
   double atr    = SC_GetATR(_Symbol,  PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0 || ema21 <= 0) return;

   // Pivot diario (High/Low del día anterior como referencia)
   double prevH = SC_GetHighestHigh(_Symbol, PERIOD_D1, 1, 1);
   double prevL = SC_GetLowestLow(_Symbol,   PERIOD_D1, 1, 1);
   double pivot = (prevH + prevL) / 2.0;

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double rrRatio = (MathAbs(biasScore) >= 3) ? InpTP_RR_Strong : InpTP_RR_Weak;

   // MODO LONG
   if (biasScore >= InpBias_MinAbs)
   {
      bool macdCrossUp  = (macd2 < 0 && macd1 >= 0);  // MACD cruza cero hacia arriba
      bool priceFilter  = (close > ema21 && rsi >= 45 && rsi <= 70);
      bool pivotFilter  = (close > pivot);

      if (macdCrossUp && priceFilter && pivotFilter)
      {
         double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
         double riskD = ask - sl;
         if (riskD <= 0) return;
         double tp   = NormalizeDouble(ask + riskD * rrRatio, digits);
         double lots = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      InpRiskPct, InpMinLot, InpMaxLot);
         if (lots >= InpMinLot && g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_TF_DailyBias_L"))
         {
            g_tradesToday++;
            Print("COMPRA DailyBias | Bias=", biasScore, " | MTF=", mtfScore,
                  " | MACD=", macd1, " | RSI=", rsi, " | SL=", sl, " | TP=", tp);
         }
      }
   }
   // MODO SHORT
   else if (biasScore <= -InpBias_MinAbs)
   {
      bool macdCrossDown = (macd2 > 0 && macd1 <= 0); // MACD cruza cero hacia abajo
      bool priceFilter   = (close < ema21 && rsi >= 30 && rsi <= 55);
      bool pivotFilter   = (close < pivot);

      if (macdCrossDown && priceFilter && pivotFilter)
      {
         double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
         double riskD = sl - bid;
         if (riskD <= 0) return;
         double tp   = NormalizeDouble(bid - riskD * rrRatio, digits);
         double lots = SC_CalcLotSize(riskD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      InpRiskPct, InpMinLot, InpMaxLot);
         if (lots >= InpMinLot && g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_TF_DailyBias_S"))
         {
            g_tradesToday++;
            Print("VENTA DailyBias | Bias=", biasScore, " | MTF=", mtfScore,
                  " | MACD=", macd1, " | RSI=", rsi, " | SL=", sl, " | TP=", tp);
         }
      }
   }
}
