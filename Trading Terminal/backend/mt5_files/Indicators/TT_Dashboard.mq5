//+------------------------------------------------------------------+
//|                    Trading Terminal Dashboard Indicator           |
//|                    Shows session quality, signals & key metrics  |
//+------------------------------------------------------------------+
#property copyright "Trading Terminal"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

// Inputs
input color    BullColor    = clrLime;
input color    BearColor    = clrRed;
input color    NeutralColor = clrGray;
input int      ATR_Period   = 14;
input int      RSI_Period   = 14;
input int      EMA_Fast     = 8;
input int      EMA_Slow     = 21;

// Handles
int h_atr, h_rsi, h_ema_fast, h_ema_slow;

int OnInit()
{
   h_atr      = iATR(Symbol(), Period(), ATR_Period);
   h_rsi      = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE);
   h_ema_fast = iMA(Symbol(), Period(), EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(Symbol(), Period(), EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   IndicatorRelease(h_atr);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_ema_fast);
   IndicatorRelease(h_ema_slow);
   Comment("");
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < 50) return 0;
   
   double atr[1], rsi[1], ema_f[1], ema_s[1];
   if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return 0;
   if(CopyBuffer(h_rsi, 0, 0, 1, rsi) < 1) return 0;
   if(CopyBuffer(h_ema_fast, 0, 0, 1, ema_f) < 1) return 0;
   if(CopyBuffer(h_ema_slow, 0, 0, 1, ema_s) < 1) return 0;
   
   // Determine signal
   string signal = "◆ HOLD";
   color sig_color = NeutralColor;
   if(ema_f[0] > ema_s[0] && rsi[0] < 65)  { signal = "▲ BUY";  sig_color = BullColor; }
   if(ema_f[0] < ema_s[0] && rsi[0] > 35)  { signal = "▼ SELL"; sig_color = BearColor; }
   
   // Session
   string sess = GetSession();
   int score = GetScore();
   
   // Regime
   double close_price = close[rates_total-1];
   string regime = ema_f[0] > ema_s[0] * 1.001 ? "TRENDING UP" :
                   ema_f[0] < ema_s[0] * 0.999 ? "TRENDING DOWN" : "RANGING";
   
   // ATR in pips
   double atr_pips = atr[0] / SymbolInfoDouble(Symbol(), SYMBOL_POINT) / 10.0;
   
   Comment(
      "╔═══ TRADING TERMINAL ══════════════════╗\n",
      "║  Signal:  ", signal, "\n",
      "╠══════════════════════════════════════╣\n",
      "║  RSI:     ", DoubleToString(rsi[0], 1),
      "   ATR:  ", DoubleToString(atr_pips, 1), " pips\n",
      "║  EMA F:   ", DoubleToString(ema_f[0], Digits()),
      "  EMA S: ", DoubleToString(ema_s[0], Digits()), "\n",
      "║  Regime:  ", regime, "\n",
      "╠══════════════════════════════════════╣\n",
      "║  Session: ", sess, "\n",
      "║  Score:   ", score, "/100\n",
      "╚══════════════════════════════════════╝"
   );
   
   return rates_total;
}

string GetSession() {
   datetime now = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int t = dt.hour * 60 + dt.min;
   if(t >= 810 && t < 990) return "🔥 LDN-NY OVERLAP";
   if(t >= 480 && t < 990) return "🇬🇧 LONDON";
   if(t >= 810 && t < 1200) return "🇺🇸 NEW YORK";
   if(t >= 0 && t < 360) return "🇯🇵 TOKYO";
   return "💤 OFF-SESSION";
}

int GetScore() {
   datetime now = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int t = dt.hour * 60 + dt.min;
   if(t >= 810 && t < 990) return 95;
   if(t >= 480 && t < 600) return 85;
   if(t >= 810 && t < 900) return 85;
   if(t >= 600 && t < 810) return 60;
   return 20;
}
