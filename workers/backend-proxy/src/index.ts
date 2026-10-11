import { Container, getContainer } from "@cloudflare/containers";

interface Env {
  SAHLHA_BACKEND: DurableObjectNamespace<SahlhaBackend>;
  FALLBACK_API_URL?: string;
  FALLBACK_API?: Fetcher;
}

const DEFAULT_FALLBACK_API_URL = "https://sahlha-api.ibrahimadel2810.workers.dev";

function isMissingContainerApp(err: unknown): boolean {
  const msg = err instanceof Error ? err.message : String(err ?? "");
  const m = msg.toLowerCase();
  return (
    m.includes("no container application assigned") ||
    m.includes("no container instance") ||
    m.includes("containers requires the workers paid plan") ||
    m.includes("workers paid plan") ||
    m.includes("failed to start container")
  );
}

async function proxyToFallback(request: Request, env: Env): Promise<Response> {
  const base = (env.FALLBACK_API_URL || DEFAULT_FALLBACK_API_URL).replace(/\/+$/, "");
  const incoming = new URL(request.url);
  const target = new URL(base + incoming.pathname + incoming.search);
  const method = request.method.toUpperCase();
  // Rebuild headers without the original Host / Cloudflare edge headers so
  // the subrequest is a clean fetch to the fallback origin. Auth and
  // content headers are preserved.
  const headers = new Headers();
  request.headers.forEach((value, key) => {
    const k = key.toLowerCase();
    if (k === "host" || k === "cf-ray" || k === "cf-connecting-ip" || k === "cf-ipcountry" || k === "cf-visitor" || k === "x-real-ip" || k === "x-forwarded-proto" || k === "connection" || k === "content-length") return;
    headers.set(key, value);
  });
  let body: BodyInit | undefined;
  if (method !== "GET" && method !== "HEAD") {
    const buf = await request.arrayBuffer().catch(() => null);
    if (buf && buf.byteLength > 0) body = buf;
  }
  // Prefer the service binding (direct worker-to-worker, no egress/DNS).
  // Public-URL fetch from inside a Worker can be rejected by the edge
  // (observed HTTP 404 / error 1042), so it is only the backup path.
  if (env.FALLBACK_API) {
    const res = await env.FALLBACK_API.fetch(
      new Request("https://fallback" + incoming.pathname + incoming.search, { method, headers, body }),
    );
    console.log(`fallback proxy ${method} ${incoming.pathname} -> binding = ${res.status}`);
    const out = new Response(res.body, res);
    out.headers.set("x-sahlha-backend", "fallback");
    return out;
  }
  const res = await fetch(target.toString(), {
    method,
    headers,
    body,
    redirect: "manual",
  });
  console.log(`fallback proxy ${method} ${incoming.pathname} -> ${target} = ${res.status}`);
  const out = new Response(res.body, res);
  out.headers.set("x-sahlha-backend", "fallback");
  return out;
}

async function fallbackOr503(request: Request, env: Env): Promise<Response> {
  try {
    return await proxyToFallback(request, env);
  } catch (err) {
    console.error(`fallback proxy failed: ${err instanceof Error ? err.message : String(err)}`);
    return Response.json(
      {
        ok: false,
        backend: "fallback",
        detail:
          "Container backend unavailable (Workers Paid plan required for Containers). Fallback API also failed.",
      },
      { status: 503 },
    );
  }
}

// One Durable Object instance fronts one container instance.
// Container disk is ephemeral; use DO storage (this.ctx.storage) for anything
// that must survive container restarts. SQLite file inside the container
// resets on eviction — fine for demo, Postgres/D1 needed for production.
export class SahlhaBackend extends Container<Env> {
  defaultPort = 8000;
  sleepAfter = "10m";
}

// Free tier has no container image, so the container path never succeeds.
// Remember that across requests (isolate reuse) to avoid paying the start
// timeout on every call; retry the container periodically in case the
// account is upgraded / an image is pushed later.
let containerUnavailableUntil = 0;
const CONTAINER_RETRY_AFTER_MS = 5 * 60 * 1000;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    // Liveness probe served at the edge (does not wake the container).
    if (url.pathname === "/edge-health") {
      return Response.json({ ok: true, edge: true });
    }
    // Clone upfront: container.fetch() may consume the body stream, and
    // the fallback needs an unconsumed copy for non-GET/HEAD requests.
    let fallbackRequest = request;
    try {
      fallbackRequest = request.clone() as unknown as typeof request;
    } catch {
      fallbackRequest = request;
    }
    if (Date.now() < containerUnavailableUntil) {
      return await fallbackOr503(fallbackRequest, env);
    }
    // Race the container against a timeout: with no image assigned
    // (free tier) getContainer().fetch() can hang until the worker is
    // cancelled instead of throwing. Fall back to the native API then.
    const CONTAINER_TIMEOUT_MS = 9000;
    let container: { fetch: (r: Request) => Promise<Response> };
    try {
      container = getContainer(env.SAHLHA_BACKEND);
    } catch (err) {
      console.error(`getContainer failed, using fallback: ${err instanceof Error ? err.message : String(err)}`);
      containerUnavailableUntil = Date.now() + CONTAINER_RETRY_AFTER_MS;
      return await fallbackOr503(fallbackRequest, env);
    }
    try {
      const res = await Promise.race([
        container.fetch(request),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error("container-start-timeout")), CONTAINER_TIMEOUT_MS),
        ),
      ]);
      // Tag container-served responses so operators can tell which
      // backend actually answered (container vs free-tier fallback).
      try {
        res.headers.set("x-sahlha-backend", "container");
      } catch {
        /* headers may be immutable in some runtimes */
      }
      return res;
    } catch (err) {
      // Any container failure (no image assigned on free tier, start
      // timeout, aborted readiness checks, crash) falls back to the native
      // Workers API. A healthy container returns Responses (even 5xx from
      // the app itself) rather than throwing, so throwing here always
      // means container infra — never the app — failed.
      console.error(`container path failed, using fallback: ${err instanceof Error ? err.message : String(err)}`);
      containerUnavailableUntil = Date.now() + CONTAINER_RETRY_AFTER_MS;
      return await fallbackOr503(fallbackRequest, env);
    }
  },
};
