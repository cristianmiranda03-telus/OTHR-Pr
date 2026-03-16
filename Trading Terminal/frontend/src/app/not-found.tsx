export default function NotFound() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-t-bg">
      <div className="t-card p-10 text-center">
        <div className="text-2xl font-bold text-t-red mb-2">404</div>
        <p className="text-t-muted text-xs mb-4">Page not found</p>
        <a href="/" className="btn btn-ghost">GO HOME</a>
      </div>
    </div>
  );
}
