//+------------------------------------------------------------------+
//| GOLD_Kalman_LSF_Trend.mq5                                        |
//| Kalman Filter + Least Squares Fitting Trend Scalper for XAUUSD  |
//|                                                                  |
//| Scientific Basis:                                                |
//| - Kalman+DRL paper (2025): 80.21% cumulative return, Sharpe 12.1|
//|   PPO with Kalman filtering on 8yr XAUUSD hourly data           |
//|   Source: thesai.org Paper_81 - Kalman Noise-Resilient DRL      |
//| - LSF-X Engine (MT5): Rate-of-change + LSF trend detection      |
//|   Source: dhruuvsharma/LSF-X-Engine                             |
//|                                                                  |
//| Strategy Logic:                                                  |
//| 1. Kalman filter applied to close prices → denoised price series |
//| 2. LSF slope on last N Kalman values → trend direction/strength  |
//| 3. Slope crossover zero + RSI alignment → entry signal          |
//| 4. M15 higher-TF Kalman slope as bias filter                    |
//| 5. ATR-based SL/TP, any session (Gold 24/5)                     |
//|                                                                  |
//| Magic: 110001                                                    |
//+------------------------------------------------------------------+
#property copyright "Gold Research Advanced"
#property version   "1.00"

#include "../Common/Scalping_Common.mqh"
#include "Gold_Research_Math.mqh"

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTF      = PERIOD_M5;   // Entry timeframe
input ENUM_TIMEFRAMES InpHTF     = PERIOD_M15;  // Higher TF Kalman bias

input group "=== Kalman Filter ==="
input double InpKalmanQ          = 0.0001;  // Process noise Q (lower=smoother)
input double InpKalmanR          = 0.005;   // Measurement noise R (higher=smoother)
input int    InpKalmanWarmup     = 100;     // Bars used to warm up Kalman state
input int    InpLSFPeriod        = 14;      // Bars for LSF slope computation

input group "=== Entry Filters ==="
input int    InpRSI_Period       = 14;
input double InpRSILongMin       = 45.0;   // RSI must be above for long
input double InpRSIShortMax      = 55.0;   // RSI must be below for short
input double InpMinSlopeATR      = 0.015;  // Min |normalized slope| to enter

input group "=== Session ==="
input int    InpUTCOffset        = 0;
input bool   InpAllSessions      = true;   // true = trade any session

input group "=== Risk ==="
input double InpRiskPct          = 0.4;
input double InpSL_ATR           = 1.2;
input double InpTP_RR            = 1.8;
input int    InpATR_Period       = 14;
input double InpMinLot           = 0.01;
input double InpMaxLot           = 0.5;
input int    InpMaxSpread        = 80;

input group "=== Trade ==="
input int    InpMagic            = 110001;

CTrade   g_trade;
datetime g_lastBar   = 0;

// Kalman state for entry TF
double g_kx_entry   = 0;
double g_kp_entry   = 1.0;
bool   g_kInit      = false;

// Kalman state for HTF bias
double g_kx_htf     = 0;
double g_kp_htf     = 1.0;
bool   g_kInitHTF   = false;

// Previous slope for crossover detection
double g_prevSlope  = 0;
bool   g_firstBar   = true;

bool IsXAU() { return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0); }

bool InSession()
{
   if (InpAllSessions) return true;
   return SC_IsLondonSession(InpUTCOffset) || SC_IsNYSession(InpUTCOffset);
}

//--- Warm up Kalman on historical bars; returns last smoothed value
double WarmupKalman(ENUM_TIMEFRAMES tf, int warmupBars,
                    double Q, double R, double &x_est, double &p_est)
{
   double closes[];
   ArraySetAsSeries(closes, true);
   if (CopyClose(_Symbol, tf, 1, warmupBars, closes) < warmupBars)
   {
      x_est = SC_Close(_Symbol, tf, 1);
      p_est = 1.0;
      return x_est;
   }
   // Start from oldest bar
   x_est = closes[warmupBars - 1];
   p_est = 1.0;
   for (int i = warmupBars - 2; i >= 0; i--)
      GRM_KalmanUpdate(closes[i], x_est, p_est, Q, R);
   return x_est;
}

//--- Compute LSF slope on last lsfPeriod Kalman values (shift 1)
double ComputeKalmanSlope(ENUM_TIMEFRAMES tf, double Q, double R,
                          double &x_est, double &p_est, int lsfPeriod)
{
   double closes[];
   ArraySetAsSeries(closes, true);
   // We need lsfPeriod+warmup bars; use a rolling approach on last lsfPeriod bars
   if (CopyClose(_Symbol, tf, 1, lsfPeriod + 20, closes) < lsfPeriod) return 0;

   // Rebuild filtered values for the lsfPeriod window without altering main state
   double xTmp = closes[lsfPeriod + 19];
   double pTmp = 1.0;
   // warm up on oldest 20 bars
   for (int i = lsfPeriod + 18; i >= lsfPeriod; i--)
      GRM_KalmanUpdate(closes[i], xTmp, pTmp, Q, R);

   double filtered[];
   ArrayResize(filtered, lsfPeriod);
   for (int i = lsfPeriod - 1; i >= 0; i--)
   {
      filtered[lsfPeriod - 1 - i] = GRM_KalmanUpdate(closes[i], xTmp, pTmp, Q, R);
   }

   // Update main state with last close
   double lastClose = SC_Close(_Symbol, tf, 1);
   GRM_KalmanUpdate(lastClose, x_est, p_est, Q, R);

   double atr = SC_GetATR(_Symbol, tf, InpATR_Period, 1);
   return GRM_LSFSlopeNorm(filtered, lsfPeriod, (atr > 0 ? atr : 1.0));
}

int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(40);
   g_trade.SetTypeFilling(SC_GetFillMode());
   g_kInit    = false;
   g_kInitHTF = false;
   g_firstBar = true;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {}

void OnTick()
{
   if (!IsXAU()) return;
   if (!SC_SpreadOK(InpMaxSpread)) return;
   if (!InSession()) return;
   if (!SC_IsNewBar(InpTF, g_lastBar)) return;
   if (SC_TotalPositions(InpMagic) > 0) return;

   // Initialize Kalman states on first bar
   if (!g_kInit)
   {
      WarmupKalman(InpTF,  InpKalmanWarmup, InpKalmanQ, InpKalmanR, g_kx_entry, g_kp_entry);
      g_kInit = true;
   }
   if (!g_kInitHTF)
   {
      WarmupKalman(InpHTF, InpKalmanWarmup, InpKalmanQ, InpKalmanR, g_kx_htf, g_kp_htf);
      g_kInitHTF = true;
   }

   // HTF Kalman slope for directional bias
   double htfSlope = ComputeKalmanSlope(InpHTF, InpKalmanQ, InpKalmanR,
                                        g_kx_htf, g_kp_htf, InpLSFPeriod);

   // Entry TF Kalman slope
   double entrySlope = ComputeKalmanSlope(InpTF, InpKalmanQ, InpKalmanR,
                                          g_kx_entry, g_kp_entry, InpLSFPeriod);

   if (g_firstBar) { g_prevSlope = entrySlope; g_firstBar = false; return; }

   double rsi  = SC_GetRSI(_Symbol, InpTF, InpRSI_Period, 1);
   double atr  = SC_GetATR(_Symbol, InpTF, InpATR_Period, 1);
   int    digs = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if (atr <= 0) { g_prevSlope = entrySlope; return; }

   double absSlope = MathAbs(entrySlope);

   // Long: entry slope crossed zero upward + HTF also positive + RSI bullish zone
   bool longSignal  = (g_prevSlope <= 0 && entrySlope > 0)
                    && htfSlope > 0
                    && absSlope >= InpMinSlopeATR
                    && rsi >= InpRSILongMin;

   // Short: entry slope crossed zero downward + HTF also negative + RSI bearish zone
   bool shortSignal = (g_prevSlope >= 0 && entrySlope < 0)
                    && htfSlope < 0
                    && absSlope >= InpMinSlopeATR
                    && rsi <= InpRSIShortMax;

   g_prevSlope = entrySlope;

   if (longSignal)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - atr * InpSL_ATR, digs);
      double slD = ask - sl;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(ask + slD * InpTP_RR, digs);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Buy(lots, _Symbol, ask, sl, tp, "Kalman_LSF_L");
      }
   }
   else if (shortSignal)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + atr * InpSL_ATR, digs);
      double slD = sl - bid;
      if (slD > 0)
      {
         double tp   = NormalizeDouble(bid - slD * InpTP_RR, digs);
         double lots = SC_CalcLotSize(slD / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                                      InpRiskPct, InpMinLot, InpMaxLot);
         g_trade.Sell(lots, _Symbol, bid, sl, tp, "Kalman_LSF_S");
      }
   }
}
