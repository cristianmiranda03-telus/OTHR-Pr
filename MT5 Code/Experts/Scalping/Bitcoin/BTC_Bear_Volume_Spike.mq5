//+------------------------------------------------------------------+
//| BTC_Bear_Volume_Spike.mq5                                        |
//| Strategy: Volume Spike BEARISH Momentum Scalper                  |
//| Asset: BTCUSD | Timeframe: M5 | Session: NY (highest BTC vol)    |
//| Logic: Volume spike (>2x 20-bar average) on a bearish close bar  |
//|        while price is below EMA21 = institutional selling signal.|
//|        Capture the continuation of the high-volume dump move.    |
//| Magic: 200005                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Volume Spike Settings ==="
input int    InpVol_AvgBars    = 20;
input double InpVol_SpikeMult  = 2.0;
input int    InpEMA_Trend      = 21;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.3;
input double InpTP_ATR_Mult    = 2.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200005;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

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
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!SC_IsNewBar(PERIOD_M5, g_lastBarM5)) return;
   if (!SC_IsNYSession(InpUTCOffset) && !SC_IsLondonSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double vol    = (double)SC_Volume(_Symbol, PERIOD_M5, 1);
   double avgVol = SC_AvgVolume(_Symbol, PERIOD_M5, InpVol_AvgBars, 2);
   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double open   = SC_Open(_Symbol, PERIOD_M5, 1);
   double ema    = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0 || avgVol <= 0) return;

   bool spikeDown = (vol >= avgVol * InpVol_SpikeMult) && (close < open);
   bool belowEMA  = (close < ema);

   if (spikeDown && belowEMA)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_Bear_Volume_Spike");
   }
}
