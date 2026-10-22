// Deep Cuts live content, layered over the crates bundled in the app.
//
// App (header x-app-key = TESTER_FEEDBACK_APP_KEY):
//   GET ?since=N  -> {items: [{id, crate, kind, body, status, rev}], more}  rows with rev > N, oldest first
// Admin (header x-admin-key = TESTER_FEEDBACK_ADMIN_KEY; scripts/content-remote.py, the weekly job):
//   GET  ?since=N              -> same, plus source, note, updated_at
//   POST {items: [{id, crate, kind, body, status?, source?, note?}]}  -> {upserted}
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP_KEY = Deno.env.get("TESTER_FEEDBACK_APP_KEY") ?? "";
const ADMIN_KEY = Deno.env.get("TESTER_FEEDBACK_ADMIN_KEY") ?? "";
const KINDS = new Set(["question", "song", "cover", "story"]);
const STATUSES = new Set(["live", "retired"]);
const PAGE = 1000;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function same(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function problem(item: Record<string, unknown>): string | null {
  if (typeof item.id !== "string" || !/^[a-z0-9-]+$/.test(item.id)) return "bad id";
  if (typeof item.crate !== "string" || !/^[a-z0-9-]+$/.test(item.crate)) return `${item.id}: bad crate`;
  if (!KINDS.has(item.kind as string)) return `${item.id}: bad kind`;
  const body = item.body as Record<string, unknown> | null;
  if (!body || typeof body !== "object" || body.id !== item.id) return `${item.id}: body.id must match id`;
  if (item.status !== undefined && !STATUSES.has(item.status as string)) return `${item.id}: bad status`;
  return null;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const admin = same(req.headers.get("x-admin-key") ?? "", ADMIN_KEY);
  const app = admin || same(req.headers.get("x-app-key") ?? "", APP_KEY);
  if (!app) return json({ error: "unauthorized" }, 401);

  if (req.method === "GET") {
    const since = Number(url.searchParams.get("since") ?? "0");
    if (!Number.isFinite(since) || since < 0) return json({ error: "bad since" }, 400);
    const cols = admin ? "id, crate, kind, body, status, rev, source, note, updated_at" : "id, crate, kind, body, status, rev";
    const { data, error } = await db.from("deepcuts_content").select(cols).gt("rev", since)
      .order("rev").limit(PAGE + 1);
    if (error) return json({ error: error.message }, 500);
    return json({ items: data.slice(0, PAGE), more: data.length > PAGE });
  }

  if (admin && req.method === "POST") {
    const body = await req.json().catch(() => null);
    const items = Array.isArray(body?.items) ? body.items : null;
    if (!items || items.length === 0 || items.length > 500) return json({ error: "items: 1 to 500 rows" }, 400);
    for (const item of items) {
      const why = problem(item);
      if (why) return json({ error: why }, 400);
    }
    const rows = items.map((i: Record<string, unknown>) => ({
      id: i.id, crate: i.crate, kind: i.kind, body: i.body, status: i.status ?? "live",
      source: String(i.source ?? "manual").slice(0, 40), note: i.note ? String(i.note).slice(0, 2000) : null,
    }));
    const { error } = await db.from("deepcuts_content").upsert(rows, { onConflict: "id" });
    return error ? json({ error: error.message }, 500) : json({ upserted: rows.length });
  }

  return json({ error: "method not allowed" }, 405);
});
