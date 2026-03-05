//+------------------------------------------------------------------+
//| BTC_Range_Keltner_Reversion.mq5                                  |
//| Strategy: Keltner Channel Mean Reversion - RANGE Scalper         |
//| Asset: BTCUSD | Timeframe: M5 | Session: Asian (low vol)         |
//| Logic: Keltner Channel uses EMA20 as center + 2xATR bands.       |
//|        Price touches or crosses outer band then reverses:         |
//|        Below lower KC + CCI < -100 = buy to center.              |
//|        Above upper KC + CCI > +100 = sell to center.             |
//| Magic: 200003                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - BTC"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== Keltner Settings ==="
input int    InpKC_EMA_Period  = 20;   // Keltner center EMA
input double InpKC_ATR_Mult    = 2.0;  // Keltner band width
input int    InpKC_ATR_Period  = 14;
input int    InpCCI_Period     = 20;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.4;
input double InpSL_ATR_Mult    = 1.5;
input double InpTP_ATR_Mult    = 1.5;  // TP at KC center
input double InpMinLot         = 0.001;
input double InpMaxLot         = 0.1;
input int    InpMaxSpread      = 500;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 200003;

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
   if (SC_TotalPositions(InpMagic) > 0) return;

   double ema    = SC_GetEMA(_Symbol, PERIOD_M5, InpKC_EMA_Period, 1);
   double atr    = SC_GetATR(_Symbol, PERIOD_M5, InpKC_ATR_Period, 1);
   double close  = SC_Close(_Symbol, PERIOD_M5, 1);
   double cci    = SC_GetCCI(_Symbol, PERIOD_M5, InpCCI_Period, 1);
   if (atr <= 0) return;

   double upper = ema + atr * InpKC_ATR_Mult;
   double lower = ema - atr * InpKC_ATR_Mult;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (close <= lower && cci < -100)
   {
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl   = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ema, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "BTC_KC_Reversion_BUY");
   }
   else if (close >= upper && cci > 100)
   {
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl   = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp   = NormalizeDouble(ema, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "BTC_KC_Reversion_SELL");
   }
}
