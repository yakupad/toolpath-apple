import { describe, expect, it } from "vitest";
import { costUsd, decide, monthKey, PLAN_LIMITS } from "../src/quota";

const q = (used: number, credits: number, plan: "free" | "pro" = "free") => ({
  plan, monthlyLimit: PLAN_LIMITS[plan], used, credits, remaining: Math.max(PLAN_LIMITS[plan] - used, 0) + credits,
});

describe("quota", () => {
  it("uses the monthly allowance first", () => expect(decide(q(0, 50))).toBe("monthly"));
  it("falls back to credits", () => expect(decide(q(5, 3))).toBe("credit"));
  it("denies when both are gone", () => expect(decide(q(5, 0))).toBe("deny"));
  it("gives pro a larger allowance", () => expect(decide(q(100, 0, "pro"))).toBe("monthly"));
  it("keys months in UTC", () => expect(monthKey(new Date("2026-10-31T23:59:00Z"))).toBe("2026-10"));
  it("prices a typical question under a cent", () => {
    const c = costUsd({ input_tokens: 2500, output_tokens: 450 });
    expect(c).toBeCloseTo(0.00475, 5);
    expect(c).toBeLessThan(0.01);
  });
});
