// Tester feedback for TestFlight builds.
//
// App (header x-app-key = TESTER_FEEDBACK_APP_KEY):
//   POST {app, install_id, name, text, context, screenshot?}  -> {id}
//   GET  ?app=..&install_id=..                                -> [{id, created_at, text, status, reply, build}]
// Admin (header x-admin-key = TESTER_FEEDBACK_ADMIN_KEY; the ops poller and build sessions):
//   GET   ?status=new                       -> rows without screenshots
//   GET   ?id=N                             -> one row, screenshot included
//   PATCH {id, status?, reply?, build?, session_url?, thread_id?}
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP_KEY = Deno.env.get("TESTER_FEEDBACK_APP_KEY") ?? "";
const ADMIN_KEY = Deno.env.get("TESTER_FEEDBACK_ADMIN_KEY") ?? "";
const APPS = new Set(["deepcuts"]);
const STATUSES = new Set(["new", "queued", "working", "shipped", "needs_jack", "declined", "failed"]);
const LIST = "id, created_at, updated_at, app, install_id, name, text, context, status, reply, build, session_url, thread_id";
const PER_DAY = 20;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function same(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const admin = same(req.headers.get("x-admin-key") ?? "", ADMIN_KEY);
  const app = admin || same(req.headers.get("x-app-key") ?? "", APP_KEY);
  if (!app) return json({ error: "unauthorized" }, 401);

  if (admin && req.method === "GET") {
    const id = url.searchParams.get("id");
    if (id) {
      const { data, error } = await db.from("tester_feedback").select("*").eq("id", Number(id)).single();
      return error ? json({ error: error.message }, 404) : json(data);
    }
    const status = url.searchParams.get("status") ?? "new";
    const { data, error } = await db.from("tester_feedback").select(LIST).eq("status", status)
      .order("created_at").limit(50);
    return error ? json({ error: error.message }, 500) : json(data);
  }

  if (admin && req.method === "PATCH") {
    const body = await req.json().catch(() => ({}));
    if (!Number.isInteger(body.id)) return json({ error: "id required" }, 400);
    if (body.status !== undefined && !STATUSES.has(body.status)) return json({ error: "bad status" }, 400);
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    for (const k of ["status", "reply", "build", "session_url", "thread_id"]) {
      if (body[k] !== undefined) patch[k] = typeof body[k] === "string" ? body[k].slice(0, 2000) : body[k];
    }
    const { data, error } = await db.from("tester_feedback").update(patch).eq("id", body.id).select(LIST).single();
    return error ? json({ error: error.message }, 500) : json(data);
  }

  if (req.method === "GET") {
    const appID = url.searchParams.get("app") ?? "";
    const install = url.searchParams.get("install_id") ?? "";
    if (!APPS.has(appID) || install.length < 8) return json({ error: "bad request" }, 400);
    const { data, error } = await db.from("tester_feedback")
      .select("id, created_at, text, status, reply, build")
      .eq("app", appID).eq("install_id", install).order("created_at", { ascending: false }).limit(20);
    return error ? json({ error: error.message }, 500) : json(data);
  }

  if (req.method === "POST") {
    const body = await req.json().catch(() => null);
    const text = typeof body?.text === "string" ? body.text.trim() : "";
    const install = typeof body?.install_id === "string" ? body.install_id : "";
    if (!body || !APPS.has(body.app) || install.length < 8 || text.length < 3) {
      return json({ error: "Please write a little more." }, 400);
    }
    if (text.length > 4000) return json({ error: "That's a bit long. Keep it under 4,000 characters." }, 400);
    const shot = typeof body.screenshot === "string" && body.screenshot.length <= 1_500_000 ? body.screenshot : null;
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const { count } = await db.from("tester_feedback").select("id", { count: "exact", head: true })
      .eq("install_id", install).gte("created_at", since);
    if ((count ?? 0) >= PER_DAY) return json({ error: "That's plenty for today. Try again tomorrow." }, 429);
    const context = body.context && typeof body.context === "object" ? body.context : {};
    const { data, error } = await db.from("tester_feedback").insert({
      app: body.app, install_id: install, name: String(body.name ?? "").slice(0, 80), text, context, screenshot: shot,
    }).select("id").single();
    return error ? json({ error: error.message }, 500) : json({ id: data.id });
  }

  return json({ error: "method not allowed" }, 405);
});
