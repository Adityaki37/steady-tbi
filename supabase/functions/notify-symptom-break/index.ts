// Steady: fictional-data prototype Edge Function (Deno).
//
// Caregiver-triggered cross-device push. A symptom-break check-in fires the
// database trigger private.notify_symptom_break(), which invokes this function
// with the circle owner's registered device tokens. This function signs an APNs
// JWT from secrets and sends a calm notification to the survivor's devices.
//
// NO SECRETS ARE COMMITTED. All credentials are read ONLY from Deno.env and must
// be provided via `supabase secrets set` (see README.md in this directory).
// Live APNs delivery requires a PAID Apple Developer account and a real APNs
// auth key (.p8). Never commit a .p8 or any key/team/bundle value to the repo.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

// Calm copy shown to the survivor. Intentionally gentle and non-alarming.
const MESSAGE =
  "A caregiver noticed a possible symptom and suggests taking a break.";

interface IncomingToken {
  token: string;
  environment?: "sandbox" | "production";
}
interface Payload {
  check_in_id?: string;
  circle_id?: string;
  owner_id?: string;
  // The trigger forwards the owner's tokens, but we re-load them with the
  // service role below so authorization never depends on request-body data.
  tokens?: IncomingToken[];
}

const env = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
};

// APNs host per token environment. Sandbox tokens go to the sandbox gateway.
const apnsHost = (environment: string): string =>
  environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";

// Import the .p8 PKCS#8 private key contents (ES256) for signing the APNs JWT.
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  // Strip the PKCS#8 PEM header/footer and whitespace, leaving base64 DER.
  const marker = (edge: string) => `-----${edge} PRIVATE KEY-----`;
  const body = pem
    .replace(marker("BEGIN"), "")
    .replace(marker("END"), "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

// Sign the short-lived APNs provider JWT (valid up to 60 minutes per Apple).
async function apnsAuthToken(): Promise<string> {
  const key = await importPrivateKey(env("APNS_PRIVATE_KEY"));
  return await create(
    { alg: "ES256", kid: env("APNS_KEY_ID"), typ: "JWT" },
    { iss: env("APNS_TEAM_ID"), iat: getNumericDate(0) },
    key,
  );
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const webhookSecret = Deno.env.get("SYMPTOM_BREAK_WEBHOOK_SECRET");
  if (!webhookSecret || req.headers.get("x-steady-webhook-secret") !== webhookSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON body", { status: 400 });
  }
  if (!payload.owner_id) {
    return new Response("Missing owner_id", { status: 400 });
  }

  // Re-load the owner's tokens with the service role so authorization is a
  // server-side decision, never trust-the-body. SUPABASE_URL and
  // SUPABASE_SERVICE_ROLE_KEY are injected into the function environment.
  const supabase = createClient(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
  );
  const { data: rows, error } = await supabase
    .from("device_tokens")
    .select("token, environment")
    .eq("user_id", payload.owner_id)
    .eq("platform", "ios");
  if (error) {
    return new Response(`Token lookup failed: ${error.message}`, {
      status: 500,
    });
  }
  const tokens = (rows ?? []) as IncomingToken[];
  if (tokens.length === 0) {
    return new Response(JSON.stringify({ sent: 0, reason: "no tokens" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const bundleId = env("APNS_BUNDLE_ID");
  const authToken = await apnsAuthToken();
  const body = JSON.stringify({
    aps: {
      alert: { title: "Steady", body: MESSAGE },
      sound: "default",
    },
    category: "symptom_break",
    check_in_id: payload.check_in_id ?? null,
    circle_id: payload.circle_id ?? null,
  });

  let sent = 0;
  const failures: string[] = [];
  for (const entry of tokens) {
    const environment = entry.environment === "production"
      ? "production"
      : "sandbox";
    try {
      const resp = await fetch(`${apnsHost(environment)}/3/device/${entry.token}`, {
        method: "POST",
        headers: {
          "authorization": `bearer ${authToken}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "content-type": "application/json",
        },
        body,
      });
      if (resp.ok) sent++;
      else failures.push(`${resp.status}`);
    } catch (e) {
      failures.push(String(e));
    }
  }

  return new Response(JSON.stringify({ sent, failures }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
