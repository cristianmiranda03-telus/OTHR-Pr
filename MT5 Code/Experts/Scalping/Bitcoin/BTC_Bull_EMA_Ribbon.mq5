//+------------------------------------------------------------------+
//| BTC_Bull_EMA_Ribbon.mq5                                          |
//| Strategy: EMA Ribbon BULLISH Scalper                             |
//| Asset: BTCUSD | Timeframe: M5 | Session: NY + London             |
//| Logic: 4-EMA ribbon (8/13/21/34) all aligned upward.            |
//|        Price retraces to EMA8 zone then next candle shows        |
//|        bullish close above EMA8 = buy.                           |
//|        BTC is 24/7 but best momentum in NY+London sessions.     |
//| Magic: 200001                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== EMA Ribbon Settings ==="
input int    InpE1 = 8;
input int    InpE2 = 13;
input int    InpE3 = 21;
input int    InpE4 = 34;
input double InpPullbackATR = 0.4;   // Max distance from EMA8 for entry (in ATR)

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.2;
input double InpTP_ATR_Mult    = 2.5;
input int    InpATR_Period      = 14;
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;  // BTC has higher spread

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200001;

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
   if (!SC_IsLondonSession(InpUTCOffset) && !SC_IsNYSession(InpUTCOffset)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   double e1 = SC_GetEMA(_Symbol, PERIOD_M5, InpE1, 1);
   double e2 = SC_GetEMA(_Symbol, PERIOD_M5, InpE2, 1);
   double e3 = SC_GetEMA(_Symbol, PERIOD_M5, InpE3, 1);
   double e4 = SC_GetEMA(_Symbol, PERIOD_M5, InpE4, 1);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool ribbon   = (e1 > e2) && (e2 > e3) && (e3 > e4);
   bool nearE1   = (close >= e1 - atr * InpPullbackATR) && (close <= e1 + atr * InpPullbackATR);
   bool bullClose = (SC_Close(_Symbol, PERIOD_M5, 1) > SC_Open(_Symbol, PERIOD_M5, 1));

   if (ribbon && nearE1 && bullClose)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(e4 - atr * 0.5, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slD   = ask - sl;
      double slPts = slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_Bull_EMA_Ribbon");
   }
}
