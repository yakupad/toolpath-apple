// Pure quota and cost logic, kept separate so it can be unit tested.

export const PLAN_LIMITS = { free: 5, pro: 150 } as const;
export type Plan = keyof typeof PLAN_LIMITS;

export interface Quota {
  plan: Plan;
  monthlyLimit: number;
  used: number;
  credits: number;
  remaining: number;
}

/** Monthly allowance first, then purchased credits. */
export function decide(quota: Quota): "monthly" | "credit" | "deny" {
  if (quota.used < quota.monthlyLimit) return "monthly";
  if (quota.credits > 0) return "credit";
  return "deny";
}

export function monthKey(date = new Date()): string {
  return date.toISOString().slice(0, 7);
}

/** Claude Haiku 4.5 list prices, USD per million tokens. */
const PRICE = { input: 1, cacheWrite: 1.25, cacheRead: 0.1, output: 5 };

export function costUsd(usage: {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}): number {
  return (
    (usage.input_tokens * PRICE.input +
      (usage.cache_creation_input_tokens ?? 0) * PRICE.cacheWrite +
      (usage.cache_read_input_tokens ?? 0) * PRICE.cacheRead +
      usage.output_tokens * PRICE.output) /
    1_000_000
  );
}
