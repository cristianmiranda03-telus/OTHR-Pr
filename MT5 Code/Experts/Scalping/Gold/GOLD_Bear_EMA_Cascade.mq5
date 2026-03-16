//+------------------------------------------------------------------+
//| GOLD_Bear_EMA_Cascade.mq5                                        |
//| Strategy: EMA 5/13/21 Cascade - BEARISH Trend Scalper            |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY             |
//| Logic: EMA5 < EMA13 < EMA21 (cascade down) + RSI < 50 + price   |
//|        bounces up to EMA13 then resumes down = sell entry.       |
//| Magic: 100002                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== EMA Cascade Settings ==="
input int    InpEMA_Fast      = 5;       // Fast EMA period
input int    InpEMA_Mid       = 13;      // Mid EMA period
input int    InpEMA_Slow      = 21;      // Slow EMA period
input int    InpRSI_Period    = 14;      // RSI period
input double InpRSI_Max       = 50.0;   // RSI maximum for bearish

input group "=== Risk Management ==="
input double InpRiskPct       = 0.5;
input double InpSL_ATR_Mult   = 1.2;
input double InpTP_ATR_Mult   = 2.0;
input int    InpATR_Period     = 14;
input double InpMinLot        = 0.01;
input double InpMaxLot        = 1.0;
input int    InpMaxSpread     = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset     = 0;
input int    InpMagic         = 100002;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min TFs aligned bearish: 1=loose, 2=medium, 3=strict

CTrade  g_trade;
datetime g_lastBarM5 = 0;

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
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
   if (InpUseMTF && !SC_MTF_BearOK(_Symbol, InpMTF_MinScore)) return;

   double ema5  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Fast, 1);
   double ema13 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Mid,  1);
   double ema21 = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Slow, 1);
   double rsi   = SC_GetRSI(_Symbol, PERIOD_M5, InpRSI_Period, 1);
   double close = SC_Close(_Symbol, PERIOD_M5, 1);
   double atr   = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   if (atr <= 0) return;

   bool cascade = (ema5 < ema13) && (ema13 < ema21);
   bool nearMid  = (MathAbs(close - ema13) < atr * 0.5);
   bool rsiOK    = (rsi <= InpRSI_Max);

   if (cascade && nearMid && rsiOK)
   {
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl     = NormalizeDouble(bid + atr * InpSL_ATR_Mult, digits);
      double tp     = NormalizeDouble(bid - atr * InpTP_ATR_Mult, digits);
      double slPts  = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots   = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Sell(lots, _Symbol, bid, sl, tp, "GOLD_Bear_EMA_Cascade");
   }
}
