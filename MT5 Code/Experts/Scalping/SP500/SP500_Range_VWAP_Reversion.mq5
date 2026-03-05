//+------------------------------------------------------------------+
//| SP500_Range_VWAP_Reversion.mq5                                   |
//| Strategy: VWAP Mean Reversion RANGE Scalper                      |
//| Asset: US500/SP500 | Timeframe: M5 | Session: NY session          |
//| Logic: VWAP is approximated as intraday SMA of typical price.    |
//|        Price deviates > 1.5 ATR from VWAP = mean reversion entry.|
//|        Below VWAP - 1.5ATR + Stoch oversold = buy.              |
//|        Above VWAP + 1.5ATR + Stoch overbought = sell.           |
//|        SP500 strongly reverts to VWAP intraday.                 |
//| Magic: 300003                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - SP500"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== VWAP Reversion Settings ==="
input int    InpVWAP_Period    = 20;   // SMA period approximating VWAP
input double InpDeviation_ATR  = 1.5;  // ATR deviation to trigger
input int    InpStoch_K        = 5;
input int    InpStoch_D        = 3;
input int    InpStoch_Slow     = 3;
input double InpStoch_OB       = 75.0;
input double InpStoch_OS       = 25.0;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.4;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_ATR_Mult    = 1.5;  // Short targets for reversion
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.1;
input double InpMaxLot         = 5.0;
input int    InpMaxSpread      = 30;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 300003;

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
   if (!SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double vwap  = SC_GetSMA(_Symbol, PERIOD_M5, InpVWAP_Period, 1);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double k1, d1, k2, d2;
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 1, k1, d1);
   SC_GetStoch(_Symbol, PERIOD_M5, InpStoch_K, InpStoch_D, InpStoch_Slow, 2, k2, d2);
   if (atr <= 0) return;

   double deviation = close - vwap;
   int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Buy: price below VWAP by > 1.5 ATR + stoch oversold
   if (deviation < -atr * InpDeviation_ATR && k1 < InpStoch_OS && k1 > d1)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(vwap, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "SP500_VWAP_Rev_BUY");
   }
   else if (deviation > atr * InpDeviation_ATR && k1 > InpStoch_OB && k1 < d1)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(vwap, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "SP500_VWAP_Rev_SELL");
   }
}
