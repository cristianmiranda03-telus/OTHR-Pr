//+------------------------------------------------------------------+
//| GOLD_Bull_ATR_Expansion.mq5                                      |
//| Strategy: ATR Volatility Expansion BULLISH Breakout Scalper      |
//| Asset: XAUUSD | Timeframe: M5 | Session: London + NY             |
//| Logic: When ATR expands above its 20-bar SMA (volatility surge), |
//|        and price closes above the 20-bar highest high (Donchian) |
//|        = buy the explosive move upward.                          |
//|        Targets 3x ATR from entry. Trend filter: EMA50 slope +.  |
//| Magic: 100014                                                    |
//+------------------------------------------------------------------+
#property copyright "Scalping Suite - GOLD"
#property version   "1.00"

#include "..\Common\Scalping_Common.mqh"

input group "=== ATR Expansion Settings ==="
input int    InpATR_Period      = 14;
input int    InpATR_SMA_Period  = 20;   // SMA of ATR to detect expansion
input double InpATR_ExpMult     = 1.3;  // ATR must be > N x ATR_SMA
input int    InpDonchian_Period = 20;   // Donchian channel period
input int    InpEMA_Trend       = 50;

input group "=== Risk Management ==="
input double InpRiskPct        = 0.5;
input double InpSL_ATR_Mult    = 1.5;
input double InpTP_ATR_Mult    = 3.0;
input double InpMinLot         = 0.01;
input double InpMaxLot         = 1.0;
input int    InpMaxSpread      = 60;

input group "=== Session & Trade ==="
input int    InpUTCOffset      = 0;
input int    InpMagic          = 100014;

CTrade   g_trade;
datetime g_lastBarM5 = 0;

double GetATR_SMA(int atrPeriod, int smaPeriod)
{
   double sum = 0;
   for (int i = 1; i <= smaPeriod; i++)
      sum += SC_GetATR(_Symbol, PERIOD_M5, atrPeriod, i);
   return (smaPeriod > 0) ? sum / smaPeriod : 0;
}

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

   double atr      = SC_GetATR(_Symbol, PERIOD_M5, InpATR_Period, 1);
   double atrSMA   = GetATR_SMA(InpATR_Period, InpATR_SMA_Period);
   double donchHigh= SC_GetHighestHigh(_Symbol, PERIOD_M5, InpDonchian_Period, 2); // break ABOVE prev high
   double close    = SC_Close(_Symbol, PERIOD_M5, 1);
   double ema50    = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 1);
   double ema50_2  = SC_GetEMA(_Symbol, PERIOD_M5, InpEMA_Trend, 3);
   if (atr <= 0 || atrSMA <= 0) return;

   bool volExpansion = (atr >= atrSMA * InpATR_ExpMult);
   bool donchBreak   = (close > donchHigh);
   bool upSlope      = (ema50 > ema50_2);

   if (volExpansion && donchBreak && upSlope)
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double sl    = NormalizeDouble(ask - atr * InpSL_ATR_Mult, digits);
      double tp    = NormalizeDouble(ask + atr * InpTP_ATR_Mult, digits);
      double slPts = (atr * InpSL_ATR_Mult) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double lots  = SC_CalcLotSize(slPts, InpRiskPct, InpMinLot, InpMaxLot);
      g_trade.Buy(lots, _Symbol, ask, sl, tp, "GOLD_Bull_ATR_Expansion");
   }
}
