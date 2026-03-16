//+------------------------------------------------------------------+
//| GOLD_PullbackWindow_StateMachine.mq5                             |
//| 4-Phase State Machine Pullback Scalper for XAUUSD               |
//|                                                                  |
//| Scientific Basis:                                                |
//| - "backtrader-pullback-window-xauusd" (ilahuerta-IA, 2025)      |
//|   5-year backtest Jul 2020 - Jul 2025, M5 timeframe:            |
//|   Win rate: 55.43%, Profit Factor: 1.64, Sharpe: 0.89           |
//|   Total Return: 44.75%, Max Drawdown: 5.81%, 175 trades         |
//| - Also referenced in Adaptive Regime research as complementary  |
//|   pullback timing system                                         |
//|                                                                  |
//| 4-Phase State Machine:                                           |
//|                                                                  |
//| [SCAN] → [ARMED] → [WINDOW] → [ENTRY]                           |
//|                                                                  |
//| SCAN:   Detect trend (EMA20>EMA50 + ADX>threshold +             |
//|         3 consecutive same-direction candles)                    |
//|                                                                  |
//| ARMED:  Trend confirmed. Wait for pullback to begin             |
//|         (price retraces toward EMA20, timeout 25 bars)          |
//|                                                                  |
//| WINDOW: Pullback touched EMA20 ± 0.5 ATR zone.                  |
//|         Entry window open for 5 bars.                           |
//|                                                                  |
//| ENTRY:  Trigger: RSI turns from extreme                         |
//|         Long: RSI was <40, now crossing above 40                |
//|         Short: RSI was >60, now crossing below 60               |
//|         ATR-based SL, configurable RR                           |
//|                                                                  |
//| Magic: 110005                                                    |
//+------------------------------------------------------------------+
#property copyright "Gold Research Advanced"
#property version   "1.00"

#include "../Common/Scalping_Common.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF          = PERIOD_M5;

input group "=== Trend Detection (SCAN phase) ==="
input int    InpEMAFast              = 20;
input int    InpEMASlow              = 50;
input int    InpADX_Period           = 14;
input double InpADXMinThreshold      = 18.0; // Min ADX to confirm trend
input int    InpConsecCandles        = 3;    // Required consecutive same-dir candles

input group "=== Pullback Detection (ARMED phase) ==="
input double InpPullbackZoneATR      = 0.6;  // How close to EMA20 = "in zone"
input int    InpArmedTimeout         = 25;   // Max bars to wait for pullback → back to SCAN

input group "=== Entry Window (WINDOW phase) ==="
input int    InpWindowBars           = 5;    // Max bars for entry trigger in window

input group "=== Entry Trigger (ENTRY phase) ==="
input int    InpRSI_Period           = 14;
input double InpRSILongThresh        = 40.0; // RSI crossing above = long trigger
input double InpRSIShortThresh       = 60.0; // RSI crossing below = short trigger

input group "=== Session ==="
input int    InpUTCOffset            = 0;
input bool   InpAllSessions          = true;

input group "=== Risk ==="
input double InpRiskPct              = 0.4;
input double InpSL_ATR               = 1.0;
input double InpTP_RR                = 1.8;
input int    InpATR_Period           = 14;
input double InpMinLot               = 0.01;
input double InpMaxLot               = 0.5;
input int    InpMaxSpread            = 80;

input group "=== Trade ==="
input int    InpMagic                = 110005;

input group "=== MTF Trend Filter (D1 / H1 / M15) ==="
input bool   InpUseMTF       = true;   // Enable multi-timeframe trend filter
input int    InpMTF_MinScore = 1;      // Min score magnitude to take directional trade (1-3)

//--- State machine enum
enum StateMachine
{
   SM_SCAN   = 0,
   SM_ARMED  = 1,
   SM_WINDOW = 2
};

CTrade       g_trade;
datetime     g_lastBar    = 0;
StateMachine g_state      = SM_SCAN;
int          g_barsInState = 0;   // Bars elapsed in current ARMED/WINDOW state
int          g_direction   = 0;   // +1 = bull trend, -1 = bear trend
double       g_impulseHigh = 0;   // Highest high of the impulse leg (for sizing)
double       g_impulseLow  = 0;
double       g_prevRSI     = 50;  // Previous RSI value for crossover detection

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }
bool InSession()
{
   if (InpAllSessions) return true;
   return SC_IsLondonSession(InpUTCOffset) || SC_IsNYSession(InpUTCOffset);
}

//--- Count consecutive same-direction candles from shift=1
int CountConsecutiveCandles(int requiredDir)
{
   double o[], c[];
   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);
   if (CopyOpen(_Symbol, InpTF, 1, InpConsecCandles + 2, o) < InpConsecCandles) return 0;
   if (CopyClose(_Symbol, InpTF, 1, InpConsecCandles + 2, c) < InpConsecCandles) return 0;
   int count = 0;
   for (int i = 0; i < InpConsecCandles; i++)
   {
      bool isBull = (c[i] > o[i]);
      bool isBear = (c[i] < o[i]);
      if (requiredDir > 0 && !isBull) break;
      if (requiredDir < 0 && !isBear) break;
      count++;
   }
   return count;
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(40);
   g_trade.SetTypeFilling(SC_GetFillMode());
   g_state = SM_SCAN;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { g_state = SM_SCAN; }

void OnTick()
{
   if (!IsXAU()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!InSession()) return;
   if (!SC_IsNewBar(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) { g_state = SM_SCAN; return; }

   int mtfScore = InpUseMTF ? SC_MTF_Score(_Symbol) : 0;

   double emaFast = SC_GetEMA(_Symbol, InpTF, InpEMAFast, 1);
   double emaSlow = SC_GetEMA(_Symbol, InpTF, InpEMASlow, 1);
   double atr     = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   double close   = SC_Close(_Symbol, InpTF, 1);
   double rsi     = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
   double plusDI, minusDI;
   double adx     = GRM_GetADXFull(_Symbol, InpTF, InpADX_Period, 1, plusDI, minusDI);
   int    digs    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (atr <= 0 || point <= 0) return;

   switch (g_state)
   {
      case SM_SCAN:
      {
         // Detect bullish trend
         bool bullTrend = (emaFast > emaSlow)
                        && (adx >= InpADXMinThreshold)
                        && (plusDI > minusDI)
                        && (CountConsecutiveCandles(1) >= InpConsecCandles)
                        && (mtfScore >= -InpMTF_MinScore);

         // Detect bearish trend
         bool bearTrend = (emaFast < emaSlow)
                        && (adx >= InpADXMinThreshold)
                        && (minusDI > plusDI)
                        && (CountConsecutiveCandles(-1) >= InpConsecCandles)
                        && (mtfScore <= InpMTF_MinScore);

         if (bullTrend || bearTrend)
         {
            g_direction  = bullTrend ? 1 : -1;
            g_state      = SM_ARMED;
            g_barsInState = 0;
            // Record impulse high/low for later reference
            g_impulseHigh = SC_GetHighestHigh(_Symbol, InpTF, InpConsecCandles + 2, 1);
            g_impulseLow  = SC_GetLowestLow(_Symbol, InpTF, InpConsecCandles + 2, 1);
         }
         break;
      }

      case SM_ARMED:
      {
         g_barsInState++;

         // Timeout: if price never pulled back, abandon and re-scan
         if (g_barsInState > InpArmedTimeout)
         {
            g_state = SM_SCAN;
            break;
         }

         // Pullback condition: price enters EMA20 zone
         double zoneRadius = atr * InpPullbackZoneATR;
         bool inZone = (MathAbs(close - emaFast) <= zoneRadius);

         // Trend must still be intact (price hasn't broken through EMA50)
         bool trendIntact = (g_direction > 0) ? (close > emaSlow) : (close < emaSlow);

         if (inZone && trendIntact)
         {
            g_state       = SM_WINDOW;
            g_barsInState = 0;
            g_prevRSI     = rsi;
         }

         // If price has made a new extreme past the impulse without pullback, reset
         if (g_direction > 0 && close > g_impulseHigh + atr) { g_state = SM_SCAN; }
         if (g_direction < 0 && close < g_impulseLow  - atr) { g_state = SM_SCAN; }
         break;
      }

      case SM_WINDOW:
      {
         g_barsInState++;

         // Window expired: go back to SCAN
         if (g_barsInState > InpWindowBars)
         {
            g_state = SM_SCAN;
            break;
         }

         // Entry trigger: RSI crossing the threshold in the direction of the trend
         bool longTrigger  = (g_direction > 0)
                           && (g_prevRSI <= InpRSILongThresh)
                           && (rsi > InpRSILongThresh);

         bool shortTrigger = (g_direction < 0)
                           && (g_prevRSI >= InpRSIShortThresh)
                           && (rsi < InpRSIShortThresh);

         g_prevRSI = rsi;

         if (longTrigger)
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl  = NormalizeDouble(ask - atr * InpSL_ATR, digs);
            double slD = ask - sl;
            if (slD > 0)
            {
               double tp   = NormalizeDouble(ask + slD * InpTP_RR, digs);
               double lots = SC_CalcLotSize(slD / point, InpRiskPct, InpMinLot, InpMaxLot);
               if (g_trade.Buy(lots, _Symbol, ask, sl, tp, "PBW_SM_L"))
                  g_state = SM_SCAN;
            }
         }
         else if (shortTrigger)
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl  = NormalizeDouble(bid + atr * InpSL_ATR, digs);
            double slD = sl - bid;
            if (slD > 0)
            {
               double tp   = NormalizeDouble(bid - slD * InpTP_RR, digs);
               double lots = SC_CalcLotSize(slD / point, InpRiskPct, InpMinLot, InpMaxLot);
               if (g_trade.Sell(lots, _Symbol, bid, sl, tp, "PBW_SM_S"))
                  g_state = SM_SCAN;
            }
         }
         break;
      }
   }

   // Update RSI reference for next bar (ARMED phase pre-tracking)
   if (g_state != SM_WINDOW) g_prevRSI = rsi;
}
