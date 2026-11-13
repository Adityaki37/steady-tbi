const reply = (status: number, message: string) => Response.json({ message }, { status });

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply(405, "Use POST to create a demo account.");

  const publishable = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}").default ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY");
  if (!publishable || request.headers.get("apikey") !== publishable) return reply(401, "Invalid demo app key.");

  let body;
  try {
    const reader = request.body?.getReader();
    if (!reader) return reply(400, "Missing signup details.");
    const decoder = new TextDecoder();
    let input = "";
    let bytes = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.length;
      if (bytes > 2048) {
        await reader.cancel();
        return reply(413, "Signup details are too long.");
      }
      input += decoder.decode(value, { stream: true });
    }
    body = JSON.parse(input + decoder.decode());
  } catch {
    return reply(400, "Invalid signup details.");
  }

  const { username, password, role } = body ?? {};
  if (typeof username !== "string" || !/^[a-z0-9][a-z0-9_-]{2,31}$/.test(username) ||
    typeof password !== "string" || password.length < 10 || new TextEncoder().encode(password).length > 72 ||
    !["survivor", "caregiver", "clinician"].includes(role)) {
    return reply(400, "Choose a valid username, a demo password of at least 10 characters, and an account role.");
  }

  const url = Deno.env.get("SUPABASE_URL");
  const secret = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}").default ??
    Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return reply(503, "Demo signup is temporarily unavailable.");
  const headers: Record<string, string> = { apikey: secret, "Content-Type": "application/json" };
  if (!secret.startsWith("sb_secret_")) headers.Authorization = `Bearer ${secret}`;

  try {
    const quota = await fetch(`${url}/rest/v1/rpc/reserve_demo_signup`, { method: "POST", headers, body: "{}" });
    if (!quota.ok) return reply(503, "Demo signup is temporarily unavailable.");
    if (!(await quota.json())) return reply(429, "Too many demo signups. Try again later.");

    const created = await fetch(`${url}/auth/v1/admin/users`, {
      method: "POST", headers,
      body: JSON.stringify({
        email: `${username}@steady-demo.example`, password, email_confirm: true,
        user_metadata: { steady_role: role }, app_metadata: { steady_demo: true },
      }),
    });
    if (created.ok) return reply(201, "Demo account created.");
    const error = await created.json();
    if (["email_exists", "user_already_exists"].includes(error.error_code ?? error.code)) {
      return reply(409, "That demo username is taken. Choose another or sign in.");
    }
    return reply(503, "Couldn’t create the demo account. Try again later.");
  } catch {
    return reply(503, "Demo signup is temporarily unavailable.");
  }
});
