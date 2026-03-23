import { cn } from "@/lib/utils";

interface BadgeProps {
  children: React.ReactNode;
  variant?: "default" | "profit" | "loss" | "neutral" | "brand" | "dim";
  size?: "sm" | "md";
  className?: string;
}

export function Badge({ children, variant = "default", size = "sm", className }: BadgeProps) {
  const variants = {
    default: "bg-bg-border text-gray-300",
    profit:  "bg-profit/10 text-profit border border-profit/20",
    loss:    "bg-loss/10 text-loss border border-loss/20",
    neutral: "bg-neutral/10 text-neutral border border-neutral/20",
    brand:   "bg-brand/10 text-brand border border-brand/20",
    dim:     "bg-bg-raised text-gray-500 border border-bg-border",
  };
  const sizes = {
    sm: "px-2 py-0.5 text-[10px] font-mono",
    md: "px-3 py-1 text-xs font-mono",
  };
  return (
    <span className={cn("inline-flex items-center rounded font-medium uppercase tracking-wider",
                         variants[variant], sizes[size], className)}>
      {children}
    </span>
  );
}
