"use client";
import { useState } from "react";
import clsx from "clsx";

type Section = "overview" | "buysell" | "tabs" | "agents" | "workflow";

const SECTIONS: { id: Section; label: string }[] = [
  { id: "overview", label: "How It Works" },
  { id: "buysell",  label: "Buy / Sell & Yes / No" },
  { id: "tabs",     label: "App Tabs Explained" },
  { id: "agents",   label: "AI Agents" },
  { id: "workflow",  label: "Your Workflow" },
];

export default function GuidePanel() {
  const [section, setSection] = useState<Section>("overview");

  return (
    <div className="flex flex-col gap-4 max-w-3xl">
      {/* Section nav */}
      <div className="flex gap-1 flex-wrap">
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            onClick={() => setSection(s.id)}
            className={clsx(
              "text-xs px-3 py-1.5 rounded border transition-all",
              section === s.id
                ? "border-neon-violet text-neon-violet bg-[#BC13FE15]"
                : "border-bg-border text-gray-500 hover:border-gray-500"
            )}
          >
            {s.label}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="joker-card p-5 space-y-4">
        {section === "overview" && <OverviewSection />}
        {section === "buysell" && <BuySellSection />}
        {section === "tabs" && <TabsSection />}
        {section === "agents" && <AgentsSection />}
        {section === "workflow" && <WorkflowSection />}
      </div>
    </div>
  );
}

function H({ children }: { children: React.ReactNode }) {
  return <h3 className="text-sm font-semibold text-neon-violet uppercase tracking-widest">{children}</h3>;
}
function P({ children }: { children: React.ReactNode }) {
  return <p className="text-xs text-gray-300 leading-relaxed">{children}</p>;
}
function Tip({ children }: { children: React.ReactNode }) {
  return (
    <div className="p-3 bg-[#0a1a0a] border border-[#39FF1433] rounded text-[11px] text-gray-300 leading-relaxed">
      <span className="text-neon-green font-semibold">TIP: </span>{children}
    </div>
  );
}

function OverviewSection() {
  return (
    <div className="space-y-4">
      <H>What is Polymarket Trader?</H>
      <P>
        This app is your AI-powered trading terminal for Polymarket, a prediction market platform
        where you trade on the outcomes of real-world events. Instead of trading stocks, you trade
        on questions like "Will X happen?" — buying shares that pay $1 if the answer is Yes, or $0 if No.
      </P>

      <H>How does this app help you?</H>
      <P>
        12 AI agents work in the background, continuously scanning markets, analyzing news,
        evaluating your positions, and finding new opportunities. They generate trading signals
        with recommendations. You simply review their analysis and approve or reject each trade.
        The system executes approved trades directly on Polymarket through the CLOB API.
      </P>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <StepCard n={1} title="Agents analyze" desc="AI scans markets, news, strategies, and your portfolio 24/7" />
        <StepCard n={2} title="You review" desc="Read signals, scenarios, and recommendations on each tab" />
        <StepCard n={3} title="Approve & earn" desc="Click Approve to execute a trade directly on Polymarket" />
      </div>

      <Tip>
        Start by setting up your API keys in the Config tab. Then go to Signals to see what
        the agents recommend, and Events to browse all active markets.
      </Tip>
    </div>
  );
}

function BuySellSection() {
  return (
    <div className="space-y-4">
      <H>Understanding Yes / No & Buy / Sell</H>

      <P>
        Every Polymarket event is a question with two outcomes: <strong className="text-white">Yes</strong> and <strong className="text-white">No</strong>.
        Each outcome has a price between $0.00 and $1.00 that represents the market's implied probability.
        Yes + No prices always add up to $1.00.
      </P>

      <div className="bg-[#1a1a1a] rounded p-3 border border-bg-border">
        <p className="text-[10px] text-gray-500 uppercase tracking-widest mb-2">Example</p>
        <p className="text-xs text-gray-300">
          "Will Bitcoin reach $200k by Dec 2026?" — <span className="text-neon-green font-mono">Yes = $0.35</span> / <span className="text-neon-red font-mono">No = $0.65</span>
        </p>
        <p className="text-[11px] text-gray-500 mt-1">
          The market thinks there's a 35% chance of Yes, and 65% chance of No.
        </p>
      </div>

      <H>What BUY and SELL mean</H>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="bg-[#0a1a0a] border border-[#39FF1433] rounded p-3">
          <p className="text-sm font-bold text-neon-green mb-1">BUY "Yes"</p>
          <p className="text-[11px] text-gray-300 leading-relaxed">
            You think the event <strong className="text-white">WILL happen</strong>.
            You pay the current Yes price (e.g. $0.35) per share.
            If the event happens, each share pays out $1.00.
            <span className="block mt-1 text-neon-green">Profit = $1.00 - $0.35 = $0.65 per share</span>
          </p>
        </div>
        <div className="bg-[#1a0a0a] border border-[#FF073A33] rounded p-3">
          <p className="text-sm font-bold text-neon-red mb-1">BUY "No"</p>
          <p className="text-[11px] text-gray-300 leading-relaxed">
            You think the event <strong className="text-white">WON'T happen</strong>.
            You pay the current No price (e.g. $0.65) per share.
            If the event doesn't happen, each share pays out $1.00.
            <span className="block mt-1 text-neon-green">Profit = $1.00 - $0.65 = $0.35 per share</span>
          </p>
        </div>
      </div>

      <H>SELL = close a position you already hold</H>
      <P>
        When agents recommend <strong className="text-neon-red">SELL</strong>, they mean you should sell shares
        you already own — either to lock in profit or cut losses. You sell at the current market price.
        If the price went up since you bought, you profit. If it went down, you take a loss.
      </P>

      <H>How to read a signal in this app</H>
      <div className="bg-[#1a1a1a] rounded p-3 border border-bg-border space-y-2">
        <div className="flex items-center gap-2">
          <span className="text-lg font-title font-bold text-neon-green">BUY</span>
          <span className="text-gray-400 text-sm">"Yes"</span>
          <span className="text-gray-500 text-xs">@ 0.350</span>
        </div>
        <p className="text-[11px] text-gray-400">
          = "The AI thinks this event will happen. The market prices it at 35%, but the agent
          believes the real probability is higher. Buy Yes shares at $0.35 each — if correct,
          they'll be worth $1.00."
        </p>
      </div>
      <div className="bg-[#1a1a1a] rounded p-3 border border-bg-border space-y-2">
        <div className="flex items-center gap-2">
          <span className="text-lg font-title font-bold text-neon-red">SELL</span>
          <span className="text-gray-400 text-sm">"Yes"</span>
          <span className="text-gray-500 text-xs">@ 0.820</span>
        </div>
        <p className="text-[11px] text-gray-400">
          = "The AI thinks this event is over-priced at 82%. It recommends selling your Yes shares
          before the price drops. You'd sell at $0.82 and avoid the potential loss if it goes to $0."
        </p>
      </div>

      <Tip>
        The best opportunities are when the agent's confidence is high and the price is low (for BUY)
        or when confidence is high and the price is high (for SELL). Look for large gaps between
        the market price and what the agent estimates.
      </Tip>
    </div>
  );
}

function TabsSection() {
  return (
    <div className="space-y-3">
      <H>Tabs overview</H>
      {[
        { icon: "⚡", name: "Signals", desc: "Trading signals from AI agents. Each signal has a BUY or SELL recommendation with confidence. Review, then Approve to execute or Reject to dismiss." },
        { icon: "📋", name: "Events", desc: "Browse all active Polymarket markets. Filter by expiration (short/medium/long term). Each card shows the current Yes price and time remaining." },
        { icon: "🛡", name: "Advisory", desc: "Detailed advice from AI: event scenario analysis, position-specific advice (hold/close/add), and ranked opportunities sorted by expected return." },
        { icon: "⎈", name: "Flow", desc: "Visual architecture of the 12-agent system. Shows which agents are active, their tier, and data flow from scanning to your approval." },
        { icon: "◈", name: "Agents", desc: "Status of each individual agent with recent activity logs. Expand any agent to see what it's currently doing." },
        { icon: "🔍", name: "Analysis", desc: "Market-by-market investigation details: the news context, sentiment analysis, and conclusion for each market the agents reviewed." },
        { icon: "🗺", name: "Strategies", desc: "Strategy research reports — trading patterns, arbitrage methods, and techniques discovered by the StrategyScout and evaluated by the StrategyEvaluator." },
        { icon: "💼", name: "Portfolio", desc: "Your live Polymarket balance, open positions with P&L, and open orders on the book. Refreshes every 30 seconds." },
        { icon: "⚙", name: "Config", desc: "API keys and app settings. You need Polymarket API credentials and a FuelXI/OpenAI key. Save and the system works immediately." },
      ].map((t) => (
        <div key={t.name} className="flex gap-3 items-start">
          <span className="text-base flex-shrink-0 mt-0.5">{t.icon}</span>
          <div>
            <p className="text-xs text-white font-semibold">{t.name}</p>
            <p className="text-[11px] text-gray-400 leading-relaxed">{t.desc}</p>
          </div>
        </div>
      ))}
    </div>
  );
}

function AgentsSection() {
  return (
    <div className="space-y-3">
      <H>The 12 AI agents</H>
      <P>
        Agents are organized in 3 tiers. Tier 1 collects data, Tier 2 evaluates and advises,
        Tier 3 optimizes and prioritizes.
      </P>
      <div className="space-y-1">
        <p className="text-[10px] text-neon-blue uppercase tracking-widest mt-2 mb-1">Tier 1 — Data Collection</p>
        {[
          { icon: "🏛", name: "PoliticsAgent", desc: "Scans political prediction markets" },
          { icon: "₿", name: "CryptoAgent", desc: "Scans crypto prediction markets" },
          { icon: "⚽", name: "SportsAgent", desc: "Scans sports prediction markets" },
          { icon: "🔬", name: "ScienceAgent", desc: "Scans science/tech prediction markets" },
          { icon: "🕵", name: "StrategyScout", desc: "Researches trading strategies from external sources" },
          { icon: "🐋", name: "WhaleWatcher", desc: "Tracks top Polymarket traders and mirrors their positions" },
          { icon: "📋", name: "PortfolioAnalyst", desc: "Analyzes your open positions against latest news" },
        ].map((a) => <AgentRow key={a.name} {...a} />)}

        <p className="text-[10px] text-neon-green uppercase tracking-widest mt-3 mb-1">Tier 2 — Advisory & Evaluation</p>
        {[
          { icon: "🎯", name: "EventEvaluator", desc: "Creates probability scenarios for each active market" },
          { icon: "⚖", name: "StrategyEvaluator", desc: "Reviews strategies from Scout — rates quality and feasibility" },
          { icon: "🛡", name: "PositionAdvisor", desc: "Tells you whether to HOLD, CLOSE, or ADD to each position" },
          { icon: "🔎", name: "EntryAnalyst", desc: "Evaluates new markets you haven't entered — should you?" },
        ].map((a) => <AgentRow key={a.name} {...a} />)}

        <p className="text-[10px] text-neon-yellow uppercase tracking-widest mt-3 mb-1">Tier 3 — Optimization</p>
        {[
          { icon: "📊", name: "OpportunityOptimizer", desc: "Ranks all pending signals by expected return and opportunity cost" },
        ].map((a) => <AgentRow key={a.name} {...a} />)}
      </div>
    </div>
  );
}

function WorkflowSection() {
  return (
    <div className="space-y-4">
      <H>Your daily workflow</H>

      <div className="space-y-3">
        <WorkflowStep n={1} title="Check Signals"
          desc="Open the Signals tab. Review pending BUY/SELL recommendations. Read the agent analysis, check confidence level." />
        <WorkflowStep n={2} title="Browse Events"
          desc="Go to Events to see what markets are active. Filter by short term (quick trades) or long term (bigger plays). Each event shows the Yes/No probability." />
        <WorkflowStep n={3} title="Read Advisory"
          desc="Check the Advisory tab for deeper analysis — event scenarios, position advice, and ranked opportunities. This is your AI research team." />
        <WorkflowStep n={4} title="Approve trades"
          desc="On any signal you agree with, click Approve, choose your amount in USDC, and confirm. The system places the order directly on Polymarket via CLOB API." />
        <WorkflowStep n={5} title="Monitor portfolio"
          desc="Go to Portfolio to see your positions, P&L, and open orders. The PositionAdvisor will tell you when to close or add to positions." />
        <WorkflowStep n={6} title="Repeat"
          desc="Agents run continuously. New signals appear as they find opportunities. Check back periodically to approve or reject." />
      </div>

      <Tip>
        You have full control. Nothing executes without your explicit Approve click.
        The agents suggest — you decide. Start with small amounts ($5-$10) until you
        understand the market dynamics.
      </Tip>
    </div>
  );
}

function StepCard({ n, title, desc }: { n: number; title: string; desc: string }) {
  return (
    <div className="bg-[#1a1a1a] rounded p-3 border border-bg-border text-center">
      <div className="text-lg font-title font-bold text-neon-violet">{n}</div>
      <p className="text-xs text-white font-semibold mt-1">{title}</p>
      <p className="text-[10px] text-gray-500 mt-0.5">{desc}</p>
    </div>
  );
}

function AgentRow({ icon, name, desc }: { icon: string; name: string; desc: string }) {
  return (
    <div className="flex gap-2 items-start py-1">
      <span className="text-sm flex-shrink-0">{icon}</span>
      <div>
        <span className="text-[11px] text-white font-mono">{name}</span>
        <span className="text-[11px] text-gray-500"> — {desc}</span>
      </div>
    </div>
  );
}

function WorkflowStep({ n, title, desc }: { n: number; title: string; desc: string }) {
  return (
    <div className="flex gap-3 items-start">
      <div className="w-6 h-6 rounded-full bg-[#BC13FE22] border border-neon-violet flex items-center justify-center flex-shrink-0">
        <span className="text-[10px] font-bold text-neon-violet">{n}</span>
      </div>
      <div>
        <p className="text-xs text-white font-semibold">{title}</p>
        <p className="text-[11px] text-gray-400 leading-relaxed">{desc}</p>
      </div>
    </div>
  );
}
