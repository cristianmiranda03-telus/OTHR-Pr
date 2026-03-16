'use client';

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-t-bg p-4">
      <div className="t-card p-8 text-center max-w-md">
        <div className="text-sm font-semibold text-t-red mb-2">APPLICATION ERROR</div>
        <p className="text-t-muted text-xs mb-4">{error?.message || 'Unknown error'}</p>
        <button onClick={reset} className="btn btn-red">RETRY</button>
      </div>
    </div>
  );
}
