// Verifies a StoreKit 2 signed transaction (JWS) locally: the x5c chain must
// end in Apple Root CA - G3 (pinned by SHA-256), each certificate must be
// signed by the next, the Apple OIDs must be present, and the JWS signature
// must verify with the leaf key. Only then is the payload trusted.

import "reflect-metadata";
import * as x509 from "@peculiar/x509";

x509.cryptoProvider.set(crypto);

const APPLE_ROOT_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const OID_LEAF = "1.2.840.113635.100.6.11.1"; // App Store receipt signing
const OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1"; // Apple WWDR intermediate

export interface TransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
  environment?: string;
  signedDate?: number;
}

export async function verifySignedTransaction(jws: string): Promise<TransactionPayload> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("not a JWS");
  const header = JSON.parse(text(b64url(parts[0]))) as { alg?: string; x5c?: string[] };
  if (header.alg !== "ES256" || !header.x5c || header.x5c.length !== 3) throw new Error("unexpected header");

  const [leaf, intermediate, root] = header.x5c.map((c) => new x509.X509Certificate(b64(c)));
  const rootHash = hex(await crypto.subtle.digest("SHA-256", root.rawData));
  if (rootHash !== APPLE_ROOT_G3_SHA256) throw new Error("untrusted root");
  if (!intermediate.getExtension(OID_INTERMEDIATE)) throw new Error("intermediate OID missing");
  if (!leaf.getExtension(OID_LEAF)) throw new Error("leaf OID missing");

  const payload = JSON.parse(text(b64url(parts[1]))) as TransactionPayload;
  const signedAt = new Date(payload.signedDate ?? Date.now());
  if (!(await intermediate.verify({ publicKey: root, date: signedAt }))) throw new Error("intermediate not signed by root");
  if (!(await leaf.verify({ publicKey: intermediate, date: signedAt }))) throw new Error("leaf not signed by intermediate");

  const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    b64url(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new Error("bad signature");
  return payload;
}

function b64(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
function b64url(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return b64(padded);
}
function text(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}
function hex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
