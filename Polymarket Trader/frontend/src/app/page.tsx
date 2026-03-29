import Dashboard from "@/components/Dashboard";

// Force dynamic rendering — this page uses client-only APIs (WebSocket, Date)
export const dynamic = "force-dynamic";

export default function Home() {
  return <Dashboard />;
}
