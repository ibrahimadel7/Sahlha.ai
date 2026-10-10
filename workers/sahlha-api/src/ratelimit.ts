import type { Context } from "hono";
import type { Env } from "./env";

// KV-backed fixed-window rate limiter. Fail-OPEN: if KV is unavailable or
// its free write quota is exhausted, requests are allowed (learning never
// breaks because of a limiter). Limits are generous by design — this stops
// credential-stuffing and AI-cost burn, not legitimate classroom use.
export async function checkRate(
  env: Env,
  scope: string,
  id: string,
  limit: number,
  windowSec: number,
): Promise<{ allowed: boolean; remaining: number }> {
  const win = Math.floor(Date.now() / 1000 / windowSec);
  const key = `rl:${scope}:${id}:${win}`;
  try {
    const cur = await env.MEDIA.get(key);
    const n = cur ? parseInt(cur, 10) || 0 : 0;
    if (n >= limit) return { allowed: false, remaining: 0 };
    await env.MEDIA.put(key, String(n + 1), { expirationTtl: windowSec + 5 });
    return { allowed: true, remaining: limit - n - 1 };
  } catch {
    return { allowed: true, remaining: limit };
  }
}

export function clientIp(c: Context): string {
  return (
    c.req.header("CF-Connecting-IP") ||
    (c.req.header("X-Forwarded-For") || "").split(",")[0].trim() ||
    "anon"
  );
}
