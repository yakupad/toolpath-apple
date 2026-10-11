// Toolpath API — cloud assistant (Claude Haiku) with per-account quotas, and
// StoreKit purchase verification. No login: an account is a random UUID the
// app keeps in the user's iCloud key-value store and also passes to StoreKit
// as appAccountToken, so purchases and quotas follow the user across devices.

import { verifySignedTransaction, type TransactionPayload } from "./appstore";
import { costUsd, decide, monthKey, PLAN_LIMITS, type Quota } from "./quota";

export interface Env {
  TOOLPATH_KV: KVNamespace;
  ANTHROPIC_API_KEY: string;
  BUNDLE_ID: string;
  DAILY_BUDGET_USD: string;
}

const MODEL = "claude-haiku-4-5";
const MAX_OUTPUT_TOKENS = 700;
const IP_REQUESTS_PER_MINUTE = 20;

const PRODUCT_SUBSCRIPTIONS = new Set(["toolpath_pro_monthly", "toolpath_pro_yearly"]);
const PRODUCT_CREDITS: Record<string, number> = { toolpath_ai_100: 100 };

const SYSTEM_PROMPT = `You are the workshop assistant inside Toolpath, an app for hobby CNC routers and desktop mills (3018, Shapeoko, Onefinity, LongMill, X-Carve, Carvera).
Answer only questions about CNC machining, G-code, tooling, materials, workholding, CAM and machine troubleshooting. For anything else, say briefly that you can only help with CNC work.
Be brief and practical: short paragraphs or numbered steps someone can follow standing at the machine.
Never give spindle RPM, feed rates, plunge rates, depth of cut or stepover numbers. Tell the user to use Toolpath's Feeds & Speeds calculator, which computes conservative values for their machine.
When workshop notes are provided, base your answer on them. If you are not sure, say so.
Prefer conservative advice and mention eye and ear protection, dust collection or workholding when relevant.
Reply in the user's language.`;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/health") return json({ ok: true });

      const account = (request.headers.get("x-account-id") ?? "").toLowerCase();
      if (!UUID.test(account)) return json({ error: "missing_account" }, 400);
      if (!(await allowIp(request, env))) return json({ error: "rate_limited" }, 429);

      if (url.pathname === "/v1/assistant/quota" && request.method === "GET") {
        return json(await loadQuota(env, account));
      }
      if (url.pathname === "/v1/assistant/ask" && request.method === "POST") {
        return await ask(request, env, account);
      }
      if (url.pathname === "/v1/iap/verify" && request.method === "POST") {
        return await verifyPurchase(request, env, account);
      }
      return json({ error: "not_found" }, 404);
    } catch (error) {
      console.error(error);
      return json({ error: "server_error" }, 500);
    }
  },
};

// MARK: Assistant

interface AskBody {
  question?: string;
  history?: { role: "user" | "assistant"; text: string }[];
  context?: string[];
  locale?: string;
}

async function ask(request: Request, env: Env, account: string): Promise<Response> {
  const body = (await request.json().catch(() => ({}))) as AskBody;
  const question = (body.question ?? "").trim().slice(0, 1000);
  if (!question) return json({ error: "empty_question" }, 400);

  const today = new Date().toISOString().slice(0, 10);
  const spent = Number((await env.TOOLPATH_KV.get(`budget:${today}`)) ?? "0");
  if (spent >= Number(env.DAILY_BUDGET_USD) * 1_000_000) return json({ error: "budget" }, 503);

  const quota = await loadQuota(env, account);
  const decision = decide(quota);
  if (decision === "deny") return json({ error: "quota_exhausted", ...quota }, 402);

  const history = (body.history ?? []).slice(-6).map((m) => ({
    role: m.role === "assistant" ? "assistant" : "user",
    content: String(m.text ?? "").slice(0, 2000),
  }));
  const notes = (body.context ?? []).map((n) => String(n)).join("\n\n").slice(0, 6000);
  const userContent = notes
    ? `Workshop notes that may help:\n${notes}\n\nQuestion: ${question}`
    : question;
  const messages = dropLeadingAssistant([...history, { role: "user", content: userContent }]);

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      system: `${SYSTEM_PROMPT}\nUser locale: ${String(body.locale ?? "en").slice(0, 20)}`,
      messages,
    }),
  });
  if (!response.ok) {
    console.error("anthropic", response.status, await response.text());
    return json({ error: "upstream" }, 502);
  }
  const result = (await response.json()) as {
    content: { type: string; text?: string }[];
    usage: { input_tokens: number; output_tokens: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number };
  };
  const answer = result.content.filter((c) => c.type === "text").map((c) => c.text).join("\n").trim();

  // Charge only for a delivered answer.
  await env.TOOLPATH_KV.put(`budget:${today}`, String(spent + Math.ceil(costUsd(result.usage) * 1_000_000)), {
    expirationTtl: 60 * 60 * 48,
  });
  const updated = await consume(env, account, quota, decision);
  return json({ answer, ...updated });
}

function dropLeadingAssistant<T extends { role: string }>(messages: T[]): T[] {
  const first = messages.findIndex((m) => m.role === "user");
  return first > 0 ? messages.slice(first) : messages;
}

// MARK: Quota

async function loadQuota(env: Env, account: string): Promise<Quota> {
  const [proUntil, used, credits] = await Promise.all([
    env.TOOLPATH_KV.get(`pro:${account}`),
    env.TOOLPATH_KV.get(`use:${account}:${monthKey()}`),
    env.TOOLPATH_KV.get(`credits:${account}`),
  ]);
  const plan = proUntil && Number(proUntil) > Date.now() ? "pro" : "free";
  const monthlyLimit = PLAN_LIMITS[plan];
  const usedCount = Number(used ?? "0");
  const creditCount = Number(credits ?? "0");
  return {
    plan,
    monthlyLimit,
    used: usedCount,
    credits: creditCount,
    remaining: Math.max(monthlyLimit - usedCount, 0) + creditCount,
  };
}

async function consume(env: Env, account: string, quota: Quota, decision: "monthly" | "credit"): Promise<Quota> {
  if (decision === "monthly") {
    await env.TOOLPATH_KV.put(`use:${account}:${monthKey()}`, String(quota.used + 1), { expirationTtl: 60 * 60 * 24 * 40 });
    return { ...quota, used: quota.used + 1, remaining: quota.remaining - 1 };
  }
  await env.TOOLPATH_KV.put(`credits:${account}`, String(quota.credits - 1));
  return { ...quota, credits: quota.credits - 1, remaining: quota.remaining - 1 };
}

// MARK: Purchases

async function verifyPurchase(request: Request, env: Env, account: string): Promise<Response> {
  const body = (await request.json().catch(() => ({}))) as { signedTransaction?: string };
  if (!body.signedTransaction) return json({ error: "missing_transaction" }, 400);

  let tx: TransactionPayload;
  try {
    tx = await verifySignedTransaction(body.signedTransaction);
  } catch (error) {
    console.warn("invalid transaction", String(error));
    return json({ error: "invalid_transaction" }, 400);
  }
  if (tx.bundleId !== env.BUNDLE_ID) return json({ error: "wrong_app" }, 400);
  // Purchases are bound to the account that made them.
  if ((tx.appAccountToken ?? "").toLowerCase() !== account) return json({ error: "account_mismatch" }, 403);
  if (tx.revocationDate) return json({ error: "revoked" }, 400);

  if (PRODUCT_SUBSCRIPTIONS.has(tx.productId)) {
    const expires = Number(tx.expiresDate ?? 0);
    const current = Number((await env.TOOLPATH_KV.get(`pro:${account}`)) ?? "0");
    if (expires > current) await env.TOOLPATH_KV.put(`pro:${account}`, String(expires));
  } else if (tx.productId in PRODUCT_CREDITS) {
    // Credit each consumable transaction exactly once.
    const seen = await env.TOOLPATH_KV.get(`tx:${tx.transactionId}`);
    if (!seen) {
      const credits = Number((await env.TOOLPATH_KV.get(`credits:${account}`)) ?? "0");
      await env.TOOLPATH_KV.put(`credits:${account}`, String(credits + PRODUCT_CREDITS[tx.productId]));
      await env.TOOLPATH_KV.put(`tx:${tx.transactionId}`, "1", { expirationTtl: 60 * 60 * 24 * 400 });
    }
  } else {
    return json({ error: "unknown_product" }, 400);
  }
  return json({ ok: true, ...(await loadQuota(env, account)) });
}

// MARK: Helpers

async function allowIp(request: Request, env: Env): Promise<boolean> {
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const key = `rl:${ip}:${Math.floor(Date.now() / 60_000)}`;
  const count = Number((await env.TOOLPATH_KV.get(key)) ?? "0");
  if (count >= IP_REQUESTS_PER_MINUTE) return false;
  await env.TOOLPATH_KV.put(key, String(count + 1), { expirationTtl: 120 });
  return true;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}
