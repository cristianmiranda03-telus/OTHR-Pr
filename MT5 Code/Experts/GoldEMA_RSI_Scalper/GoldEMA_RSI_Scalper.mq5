//+------------------------------------------------------------------+
//|                                    GoldEMA_RSI_Scalper.mq5       |
//| EMA Bounce with RSI Confirmation - XAU/USD M5                   |
//+------------------------------------------------------------------+
#property copyright "Gold EMA RSI Scalper"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== EMA ==="
input int    InpEMA_Period               = 50;      // EMA period
input int    InpEMA_SlopeBars            = 3;       // Bars to assess EMA slope

input group "=== RSI ==="
input int    InpRSI_Period               = 14;       // RSI period
input double InpRSI_LongMin              = 40;      // RSI min for long (above 40)
input double InpRSI_LongMax              = 70;      // RSI max for long (not overbought)
input double InpRSI_ShortMin             = 30;      // RSI min for short (not oversold)
input double InpRSI_ShortMax             = 60;      // RSI max for short (below 60)

input group "=== Candlestick & Pullback ==="
input double InpEMATouchPoints           = 30;      // Max points from EMA to count as "touch"
input double InpMinBodyRatio             = 0.4;     // Min body/range for "strong" candle

input group "=== Risk ==="
input double InpSL_PipsBuffer            = 7;       // SL pips beyond confirmation candle (5-10)
input double InpRR_Ratio                 = 1.5;    // Take profit R:R (1:1.5)
input double InpPipsPerPoint             = 10;      // Points per pip (XAU often 10)
input double InpRiskPercent              = 0.5;     // Risk % equity
input double InpMaxLotSize               = 0.5;     // Max lot
input double InpMinLotSize               = 0.01;    // Min lot

input group "=== Trade ==="
input int    InpMagic                    = 301001;  // Magic number

CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_position;
datetime       g_lastBar = 0;
int            g_emaHandle = INVALID_HANDLE;
int            g_rsiHandle = INVALID_HANDLE;

double PointToPips(double points) { return points / InpPipsPerPoint; }
double PipsToPoints(double pips) { return pips * InpPipsPerPoint; }

bool IsNewBar()
{
   datetime t[];
   if (CopyTime(_Symbol, PERIOD_M5, 0, 1, t) < 1) return false;
   if (t[0] == g_lastBar) return false;
   g_lastBar = t[0];
   return true;
}

bool IsXAU()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
}

double GetEMA(int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if (CopyBuffer(g_emaHandle, 0, shift, 1, buf) < 1) return 0;
   return buf[0];
}

double GetRSI(int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if (CopyBuffer(g_rsiHandle, 0, shift, 1, buf) < 1) return 0;
   return buf[0];
}

// EMA sloping up: bar 1 ema > bar 3 ema
bool EMASlopeUp()
{
   double e1 = GetEMA(1), e3 = GetEMA(InpEMA_SlopeBars);
   return (e1 > 0 && e3 > 0 && e1 > e3);
}

bool EMASlopeDown()
{
   double e1 = GetEMA(1), e3 = GetEMA(InpEMA_SlopeBars);
   return (e1 > 0 && e3 > 0 && e1 < e3);
}

bool PriceTouchedEMA(bool forLong, int barIdx)
{
   double o[], c[], h[], l[], ema[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   ArraySetAsSeries(ema, true);
   if (CopyOpen(_Symbol, PERIOD_M5, barIdx, 1, o) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M5, barIdx, 1, h) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, barIdx, 1, l) < 1) return false;
   if (CopyBuffer(g_emaHandle, 0, barIdx, 1, ema) < 1) return false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double dist = forLong ? MathAbs(l[0] - ema[0]) : MathAbs(h[0] - ema[0]);
   return (point > 0 && dist <= point * InpEMATouchPoints);
}

bool StrongBullishCandle(int barIdx)
{
   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M5, barIdx, 1, o) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M5, barIdx, 1, h) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, barIdx, 1, l) < 1) return false;
   if (c[0] <= o[0]) return false;
   double range = h[0] - l[0];
   if (range < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2) return false;
   double body = c[0] - o[0];
   return (body / range >= InpMinBodyRatio);
}

bool StrongBearishCandle(int barIdx)
{
   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M5, barIdx, 1, o) < 1) return false;
   if (CopyClose(_Symbol, PERIOD_M5, barIdx, 1, c) < 1) return false;
   if (CopyHigh(_Symbol, PERIOD_M5, barIdx, 1, h) < 1) return false;
   if (CopyLow(_Symbol, PERIOD_M5, barIdx, 1, l) < 1) return false;
   if (c[0] >= o[0]) return false;
   double range = h[0] - l[0];
   if (range < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2) return false;
   double body = o[0] - c[0];
   return (body / range >= InpMinBodyRatio);
}

double CalcLots(double slPoints, double riskPct)
{
   if (slPoints <= 0) return InpMinLotSize;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * (riskPct / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (tickVal <= 0 || tickSize <= 0 || point <= 0) return InpMinLotSize;
   double valuePerPoint = tickVal * (point / tickSize);
   double lots = riskAmount / (slPoints * valuePerPoint);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(maxL, lots));
   return MathMax(InpMinLotSize, MathMin(InpMaxLotSize, lots));
}

int CountPos(ENUM_POSITION_TYPE type)
{
   int n = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_position.SelectByIndex(i)) continue;
      if (g_position.Symbol() != _Symbol || g_position.Magic() != InpMagic) continue;
      if (g_position.PositionType() == type) n++;
   }
   return n;
}

int OnInit()
{
   if (!IsXAU()) { Print("Gold EMA RSI Scalper: XAU/USD only."); return INIT_SUCCEEDED; }
   if (!g_symbol.Name(_Symbol)) return INIT_FAILED;
   g_emaHandle = iMA(_Symbol, PERIOD_M5, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   g_rsiHandle = iRSI(_Symbol, PERIOD_M5, InpRSI_Period, PRICE_CLOSE);
   if (g_emaHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE) return INIT_FAILED;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(15);
   long fill = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if ((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_emaHandle != INVALID_HANDLE) IndicatorRelease(g_emaHandle);
   if (g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
}

void OnTick()
{
   if (!IsXAU() || !g_symbol.RefreshRates()) return;
   if (!IsNewBar()) return;

   double o[], c[], h[], l[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);
   if (CopyOpen(_Symbol, PERIOD_M5, 1, 1, o) < 1 || CopyClose(_Symbol, PERIOD_M5, 1, 1, c) < 1) return;
   if (CopyHigh(_Symbol, PERIOD_M5, 1, 1, h) < 1 || CopyLow(_Symbol, PERIOD_M5, 1, 1, l) < 1) return;

   double ema1 = GetEMA(1);
   double rsi1 = GetRSI(1);
   if (ema1 <= 0) return;

   // Long: uptrend (price above EMA, EMA sloping up), pullback to EMA, RSI 40-70, strong bullish candle at EMA
   bool trendUp = (c[0] > ema1 && EMASlopeUp());
   bool pullbackLong = PriceTouchedEMA(true, 1);
   bool rsiLong = (rsi1 >= InpRSI_LongMin && rsi1 <= InpRSI_LongMax);
   bool candleLong = StrongBullishCandle(1) && (c[0] > ema1);

   if (trendUp && pullbackLong && rsiLong && candleLong && CountPos(POSITION_TYPE_BUY) == 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double slDist = PipsToPoints(InpSL_PipsBuffer);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = NormalizeDouble(l[0] - slDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double riskPoints = (ask - sl) / point;
      if (riskPoints < 1) return;
      double tpDist = riskPoints * point * InpRR_Ratio;
      double tp = NormalizeDouble(ask + tpDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double lots = CalcLots(riskPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "EMA_RSI_L");
   }

   // Short: downtrend, pullback to EMA, RSI 30-60, strong bearish candle
   bool trendDn = (c[0] < ema1 && EMASlopeDown());
   bool pullbackShort = PriceTouchedEMA(false, 1);
   bool rsiShort = (rsi1 >= InpRSI_ShortMin && rsi1 <= InpRSI_ShortMax);
   bool candleShort = StrongBearishCandle(1) && (c[0] < ema1);

   if (trendDn && pullbackShort && rsiShort && candleShort && CountPos(POSITION_TYPE_SELL) == 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double slDist = PipsToPoints(InpSL_PipsBuffer);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = NormalizeDouble(h[0] + slDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double riskPoints = (sl - bid) / point;
      if (riskPoints < 1) return;
      double tpDist = riskPoints * point * InpRR_Ratio;
      double tp = NormalizeDouble(bid - tpDist, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      double lots = CalcLots(riskPoints, InpRiskPercent);
      if (lots >= InpMinLotSize)
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "EMA_RSI_S");
   }
}
