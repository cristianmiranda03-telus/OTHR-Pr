'use client';

import { useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';

const API = 'http://localhost:8000';

type Account = {
  login: number; server: string; balance: number;
  equity: number; currency: string;
};
type SystemState = {
  market_regime: string; opportunity_score: number;
  trading_mode: string; active_strategies: string[];
  risk_level: string; cycle_count: number; is_running: boolean;
};

const ASSETS_FOREX_OTC = ['EURUSD+', 'GBPUSD+', 'EURJPY+', 'USDJPY+', 'AUDUSD+', 'USDCAD+', 'EURGBP+', 'AUDUSD+', 'NZDUSD+'];
const ASSETS_FOREX     = ['EURUSD',  'GBPUSD', 'USDJPY', 'AUDUSD', 'USDCAD', 'EURGBP'];
const ASSETS_CRYPTO    = ['BTCUSD',  'ETHUSD', 'LTCUSD', 'XRPUSD'];
const ASSETS_STOCKS    = ['AAPL',    'GOOGL',  'MSFT',   'AMZN',   'TSLA',   'META'];
const ASSETS_COMMODITIES=['XAUUSD',  'XAGUSD', 'USOIL'];

const TIMEFRAMES = [
  { id: 'M1',  label: '1m',  sub: 'Ultra scalp' },
  { id: 'M5',  label: '5m',  sub: 'Scalping' },
  { id: 'M15', label: '15m', sub: 'Scalping' },
  { id: 'M30', label: '30m', sub: 'Swing' },
  { id: 'H1',  label: '1h',  sub: 'Day trade ↑' },
  { id: 'H4',  label: '4h',  sub: 'Swing' },
  { id: 'D1',  label: '1D',  sub: 'Position' },
];

function Section({ title, children, defaultOpen = true }: { title: string; children: React.ReactNode; defaultOpen?: boolean }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="border-b border-t-border">
      <button
        onClick={() => setOpen(v => !v)}
        className="w-full flex items-center justify-between px-3 py-1.5 text-2xs uppercase tracking-widest text-t-muted hover:text-t-text transition"
      >
        {title}
        {open ? <ChevronDown className="w-2.5 h-2.5" /> : <ChevronRight className="w-2.5 h-2.5" />}
      </button>
      {open && <div className="pb-2">{children}</div>}
    </div>
  );
}

export function SidebarConfig({ account, systemState }: { account: Account | null; systemState: SystemState | null }) {
  const [selectedTF, setSelectedTF] = useState('M5');
  const [selectedAssets, setSelectedAssets] = useState<string[]>(['EURUSD', 'GBPUSD', 'XAUUSD']);
  const [accountType, setAccountType] = useState<'practice' | 'real'>('practice');
  const [investment, setInvestment] = useState('2');
  const [maxDailyLoss, setMaxDailyLoss] = useState('25');
  const [maxConsec, setMaxConsec] = useState('5');
  const [minWinRate, setMinWinRate] = useState('0.70');
  const [backtest, setBacktest] = useState('250');
  const [customAsset, setCustomAsset] = useState('');

  const toggleAsset = (a: string) => {
    setSelectedAssets(prev => prev.includes(a) ? prev.filter(x => x !== a) : [...prev, a]);
  };

  const AssetChip = ({ symbol }: { symbol: string }) => {
    const active = selectedAssets.includes(symbol);
    return (
      <button
        onClick={() => toggleAsset(symbol)}
        className={`text-2xs px-1.5 py-0.5 rounded border transition ${
          active
            ? 'bg-t-red border-t-red text-white'
            : 'border-t-border text-t-dim hover:border-t-borderB hover:text-t-muted'
        }`}
      >
        {symbol}
      </button>
    );
  };

  return (
    <div className="flex-1 overflow-y-auto text-xs font-mono">

      {/* Account info */}
      <Section title="Credentials">
        <div className="px-3 space-y-1.5">
          <div className="t-input text-t-text truncate" style={{ background: 'var(--t-surface)', border: '1px solid var(--t-border)', borderRadius: 2, padding: '4px 8px', fontSize: '0.65rem' }}>
            {account?.login ?? '—'} · {account?.server ?? 'Not connected'}
          </div>
          <div className="flex gap-1 mt-1">
            <button
              onClick={() => setAccountType('practice')}
              className={`flex-1 btn py-0.5 text-2xs ${accountType === 'practice' ? 'btn-ghost border-t-borderB text-t-text' : 'btn-ghost'}`}
            >PRACTICE</button>
            <button
              onClick={() => setAccountType('real')}
              className={`flex-1 btn py-0.5 text-2xs ${accountType === 'real' ? 'btn-red' : 'btn-ghost'}`}
            >REAL</button>
          </div>
        </div>
      </Section>

      {/* Timeframe */}
      <Section title="Timeframe">
        <div className="px-3 grid grid-cols-2 gap-1">
          {TIMEFRAMES.map(tf => (
            <button
              key={tf.id}
              onClick={() => setSelectedTF(tf.id)}
              className={`flex items-center justify-between px-2 py-1 border rounded text-2xs transition ${
                selectedTF === tf.id
                  ? 'border-t-red bg-t-redBg text-t-red'
                  : 'border-t-border text-t-dim hover:border-t-borderB hover:text-t-muted'
              }`}
            >
              <span className="font-semibold">{tf.label}</span>
              <span className="text-t-dim" style={{ fontSize: '0.55rem' }}>{tf.sub}</span>
            </button>
          ))}
        </div>
      </Section>

      {/* Assets */}
      <Section title={`Assets (${selectedAssets.length} selected)`}>
        <div className="px-3 space-y-2">
          <div>
            <div className="text-2xs text-t-dim mb-1 uppercase">Forex OTC</div>
            <div className="flex flex-wrap gap-1">
              {ASSETS_FOREX_OTC.slice(0, 5).map(a => <AssetChip key={a} symbol={a} />)}
            </div>
          </div>
          <div>
            <div className="text-2xs text-t-dim mb-1 uppercase">Forex</div>
            <div className="flex flex-wrap gap-1">
              {ASSETS_FOREX.map(a => <AssetChip key={a} symbol={a} />)}
            </div>
          </div>
          <div>
            <div className="text-2xs text-t-dim mb-1 uppercase">Crypto</div>
            <div className="flex flex-wrap gap-1">
              {ASSETS_CRYPTO.map(a => <AssetChip key={a} symbol={a} />)}
            </div>
          </div>
          <div>
            <div className="text-2xs text-t-dim mb-1 uppercase">Stocks</div>
            <div className="flex flex-wrap gap-1">
              {ASSETS_STOCKS.map(a => <AssetChip key={a} symbol={a} />)}
            </div>
          </div>
          <div>
            <div className="text-2xs text-t-dim mb-1 uppercase">Commodities</div>
            <div className="flex flex-wrap gap-1">
              {ASSETS_COMMODITIES.map(a => <AssetChip key={a} symbol={a} />)}
            </div>
          </div>
          <div className="flex gap-1 mt-1">
            <input
              value={customAsset}
              onChange={e => setCustomAsset(e.target.value)}
              placeholder="Custom asset..."
              className="t-input flex-1 text-2xs"
              style={{ fontSize: '0.62rem', padding: '3px 6px' }}
            />
            <button
              onClick={() => { if (customAsset.trim()) { toggleAsset(customAsset.trim().toUpperCase()); setCustomAsset(''); } }}
              className="btn btn-ghost px-2 py-0.5 text-2xs"
            >Add</button>
          </div>
        </div>
      </Section>

      {/* Risk / Size */}
      <Section title="Risk / Size">
        <div className="px-3 space-y-2">
          {[
            { label: 'Investment ($)', value: investment, set: setInvestment },
            { label: 'Max daily loss (%)', value: maxDailyLoss, set: setMaxDailyLoss },
            { label: 'Max consec. losses', value: maxConsec, set: setMaxConsec },
            { label: 'Min win rate', value: minWinRate, set: setMinWinRate },
            { label: 'Backtest candles', value: backtest, set: setBacktest },
          ].map(({ label, value, set }) => (
            <div key={label} className="flex items-center justify-between gap-2">
              <span className="text-2xs text-t-muted flex-1 truncate">{label}</span>
              <input
                type="number"
                value={value}
                onChange={e => set(e.target.value)}
                className="t-input text-right"
                style={{ width: 52, fontSize: '0.68rem', padding: '2px 6px' }}
              />
            </div>
          ))}
        </div>
      </Section>

      {/* System state */}
      {systemState && (
        <Section title="AI System" defaultOpen={false}>
          <div className="px-3 space-y-1 text-2xs">
            {[
              { label: 'Mode', value: systemState.trading_mode?.toUpperCase(), color: systemState.trading_mode === 'aggressive' ? 'text-t-red' : systemState.trading_mode === 'normal' ? 'text-t-green' : 'text-t-muted' },
              { label: 'Regime', value: systemState.market_regime?.toUpperCase(), color: 'text-t-text' },
              { label: 'Risk', value: systemState.risk_level?.toUpperCase(), color: systemState.risk_level === 'high' ? 'text-t-red' : 'text-t-text' },
              { label: 'Score', value: `${(systemState.opportunity_score * 100).toFixed(0)}%`, color: systemState.opportunity_score >= 0.65 ? 'text-t-green' : 'text-t-red' },
              { label: 'Cycles', value: String(systemState.cycle_count), color: 'text-t-text' },
            ].map(({ label, value, color }) => (
              <div key={label} className="flex justify-between">
                <span className="text-t-dim">{label}</span>
                <span className={color}>{value ?? '—'}</span>
              </div>
            ))}
            {systemState.active_strategies?.length > 0 && (
              <div className="mt-1 pt-1 border-t border-t-border">
                <div className="text-t-dim mb-0.5">Active strategies:</div>
                {systemState.active_strategies.map(s => (
                  <div key={s} className="text-t-green truncate">{s}</div>
                ))}
              </div>
            )}
          </div>
        </Section>
      )}
    </div>
  );
}
