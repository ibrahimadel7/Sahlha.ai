import { Container, getContainer } from "@cloudflare/containers";

interface Env {
  SAHLHA_BACKEND: DurableObjectNamespace<SahlhaBackend>;
}

// One Durable Object instance fronts one container instance.
// Container disk is ephemeral; use DO storage (this.ctx.storage) for anything
// that must survive container restarts. SQLite file inside the container
// resets on eviction — fine for demo, Postgres/D1 needed for production.
export class SahlhaBackend extends Container<Env> {
  defaultPort = 8000;
  sleepAfter = "10m";
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    // Liveness probe served at the edge (does not wake the container).
    if (url.pathname === "/edge-health") {
      return Response.json({ ok: true, edge: true });
    }
    return getContainer(env.SAHLHA_BACKEND).fetch(request);
  },
};
