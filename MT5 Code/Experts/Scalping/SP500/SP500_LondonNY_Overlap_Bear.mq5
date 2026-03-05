//+------------------------------------------------------------------+
//| SP500_LondonNY_Overlap_Bear.mq5                                  |
//| Strategy: London/NY Overlap BEARISH Scalper                      |
//| Asset: US500/SP500 | Timeframe: M5 | Session: 13:00-16:00 UTC   |
//| Logic: EMA5 < EMA13 + MACD histogram negative + RSI 30-50 =     |
//|        sell momentum during peak liquidity window.               |
//| Magic: 300007                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Overlap Settings ==="
input int    InpEMA_Fast       = 5;
input int    InpEMA_Slow       = 13;
input int    InpMACD_Fast      = 8;
input int    InpMACD_Slow      = 21;
input int    InpMACD_Signal    = 5;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 0.8;
input double InpTP_ATR_Mult    = 1.8;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.1;
input double InpMaxLot         = 5.0;
input int    InpMaxSpread      = 30;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 300007;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling(SC_GetFillMode());
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsLondonNYOverlap(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double ema5  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema13 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double macd1, sig1, macd2, sig2;
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 1, macd1, sig1);
   SC_GetMACD(_Symbol, PERIOD_M5, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, 2, macd2, sig2);
   double rsi  = SC_GetRSI(_Symbol, PERIOD_M5, 14, 1);
   double atr  = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool bearish   = (ema5 < ema13);
   bool histNeg   = ((macd1 - sig1) < 0 && (macd2 - sig2) >= 0);
   bool rsiOK     = (rsi <= 50 && rsi >= 30);

   if (bearish && histNeg && rsiOK)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_LonNY_Overlap_Bear");
   }
}
