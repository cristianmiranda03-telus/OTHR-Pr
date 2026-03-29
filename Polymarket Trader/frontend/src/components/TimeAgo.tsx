"use client";
/**
 * Client-only time display — avoids SSR/hydration mismatches.
 *
 * mode="relative" (default) → "3 minutes ago"
 * mode="clock"              → "10:30:45"
 */
import { formatDistanceToNow } from "date-fns";
import { useMounted } from "@/hooks/useMounted";

interface Props {
  date: string | null | undefined;
  className?: string;
  mode?: "relative" | "clock";
}

export default function TimeAgo({ date, className, mode = "relative" }: Props) {
  const mounted = useMounted();

  if (!mounted || !date) {
    return <span className={className}>—</span>;
  }

  try {
    const d = new Date(date);
    if (isNaN(d.getTime())) return <span className={className}>—</span>;

    const text =
      mode === "clock"
        ? d.toLocaleTimeString()
        : formatDistanceToNow(d, { addSuffix: true });

    return <span className={className}>{text}</span>;
  } catch {
    return <span className={className}>—</span>;
  }
}
