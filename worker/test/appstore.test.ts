import "reflect-metadata";
import * as x509 from "@peculiar/x509";
import { describe, expect, it } from "vitest";
import { verifySignedTransaction } from "../src/appstore";

const alg = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" } as const;
const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const der = (c: x509.X509Certificate) => btoa(String.fromCharCode(...new Uint8Array(c.rawData)));

async function forgedJWS(payload: object): Promise<string> {
  const keys = (await crypto.subtle.generateKey(alg, true, ["sign", "verify"])) as CryptoKeyPair;
  const cert = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Not Apple", notBefore: new Date(Date.now() - 1e8), notAfter: new Date(Date.now() + 1e8),
    keys, signingAlgorithm: alg,
  });
  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", x5c: [der(cert), der(cert), der(cert)] })));
  const body = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, keys.privateKey, new TextEncoder().encode(`${header}.${body}`)));
  return `${header}.${body}.${b64url(sig)}`;
}

describe("signed transaction verification", () => {
  it("rejects garbage", async () => {
    await expect(verifySignedTransaction("not-a-jws")).rejects.toThrow();
  });
  it("rejects a well-formed JWS whose chain is not Apple's", async () => {
    const jws = await forgedJWS({ transactionId: "1", bundleId: "com.yakupad.toolpath", productId: "toolpath_ai_100" });
    await expect(verifySignedTransaction(jws)).rejects.toThrow("untrusted root");
  });
});
