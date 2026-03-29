"use client";
import { useEffect, useRef, useCallback, useState } from "react";
import type { WsMessage } from "@/types";

type MessageHandler = (msg: WsMessage) => void;

export function useWebSocket(handlers: Partial<Record<string, MessageHandler>>) {
  const wsRef = useRef<WebSocket | null>(null);
  const [connected, setConnected] = useState(false);
  const [reconnectCount, setReconnectCount] = useState(0);
  const handlersRef = useRef(handlers);

  useEffect(() => {
    handlersRef.current = handlers;
  }, [handlers]);

  const connect = useCallback(() => {
    const wsUrl =
      (process.env.NEXT_PUBLIC_WS_URL || "ws://localhost:8000") + "/ws/updates";

    const ws = new WebSocket(wsUrl);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      setReconnectCount(0);

      const ping = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.send("ping");
      }, 25000);
      ws.addEventListener("close", () => clearInterval(ping));
    };

    ws.onmessage = (event) => {
      try {
        const msg: WsMessage = JSON.parse(event.data);
        if (msg.data === "pong") return;
        const handler = handlersRef.current[msg.event];
        handler?.(msg);
        handlersRef.current["*"]?.(msg);
      } catch {
        // ignore malformed frames
      }
    };

    ws.onclose = () => {
      setConnected(false);
      const delay = Math.min(1000 * 2 ** reconnectCount, 30000);
      setTimeout(() => {
        setReconnectCount((c) => c + 1);
        connect();
      }, delay);
    };

    ws.onerror = () => ws.close();
  }, [reconnectCount]);

  useEffect(() => {
    connect();
    return () => wsRef.current?.close();
  }, []);

  return { connected };
}
