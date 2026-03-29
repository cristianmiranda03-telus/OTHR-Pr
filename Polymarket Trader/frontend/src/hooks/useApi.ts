"use client";
import { useState, useCallback } from "react";
import type { ApiResponse } from "@/types";

// Use relative /api so Next.js rewrites proxy to backend (avoids CORS and "Failed to fetch")
function getApiBase(): string {
  if (typeof window === "undefined") return "";
  return "";
}

export async function apiFetch<T>(
  path: string,
  options?: RequestInit
): Promise<ApiResponse<T>> {
  const base = getApiBase();
  const url = path.startsWith("http") ? path : `${base}${path}`;
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status}: ${text}`);
  }
  return res.json() as Promise<ApiResponse<T>>;
}

export function useApiAction<TResult = unknown>(
  fn: () => Promise<ApiResponse<TResult>>
) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const execute = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await fn();
      return result;
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Unknown error";
      setError(msg);
      return null;
    } finally {
      setLoading(false);
    }
  }, [fn]);

  return { execute, loading, error };
}
