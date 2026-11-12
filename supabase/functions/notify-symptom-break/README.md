# notify-symptom-break (Supabase Edge Function)

Caregiver-triggered cross-device push for the Steady fictional-data prototype.

When a caregiver records a **symptom-break** check-in (`public.check_ins.category = 'symptom_break'`),
the database trigger `private.notify_symptom_break()` invokes this function with the
circle owner's id and tokens. The function re-loads the owner's registered iOS device
tokens with the service role, signs an APNs provider JWT, and sends a calm notification:

> A caregiver noticed a possible symptom and suggests taking a break.

## Security and honesty

- **No secrets are committed.** All credentials are read only from the function
  environment (`Deno.env`). The repository contains placeholders / variable names only.
- **Never commit a `.p8`** APNs auth key, key id, team id, or bundle id.
- Live APNs delivery requires a **paid Apple Developer account** and a **real APNs auth
  key**. Without those, the function returns gracefully and no push is delivered.
- Authorization to read survivor device tokens happens **server-side only** (service role
  inside this function / the security-definer trigger). It is never exposed to caregivers
  through RLS.
- This is a fictional-data prototype. It is **not a medical device**, does not diagnose,
  and does not predict overload.

## Required secrets

Set these with the Supabase CLI before deploying (values are examples of the *shape*
only; use your own real values and never commit them):

```sh
supabase secrets set APNS_KEY_ID=XXXXXXXXXX
supabase secrets set APNS_TEAM_ID=YYYYYYYYYY
supabase secrets set APNS_BUNDLE_ID=com.example.steady
supabase secrets set APNS_PRIVATE_KEY="$(cat /secure/path/AuthKey_XXXXXXXXXX.p8)"
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically into the
Edge Function runtime by Supabase; you do not set those yourself.

| Variable | Purpose |
| --- | --- |
| `SYMPTOM_BREAK_WEBHOOK_SECRET` | Shared secret from the database webhook, sent as `x-steady-webhook-secret` |
| `APNS_KEY_ID` | APNs auth key id (`kid`) from the Apple Developer portal |
| `APNS_TEAM_ID` | Apple Developer team id (`iss`) |
| `APNS_BUNDLE_ID` | App bundle id, sent as the `apns-topic` header |
| `APNS_PRIVATE_KEY` | Contents of the `.p8` ES256 private key (PKCS#8 PEM) |
| `SUPABASE_URL` | Injected by Supabase runtime |
| `SUPABASE_SERVICE_ROLE_KEY` | Injected by Supabase runtime |

## Deploy

```sh
supabase functions deploy notify-symptom-break
```

To wire the database trigger to this function in the hosted project, the webhook helper
(`supabase_functions.http_request` / `pg_net`) must be available. In plain Postgres and
in the PGlite test harness that helper is absent, so `private.notify_symptom_break()`
no-ops the network call and the check-in still inserts cleanly. The deployed webhook must send the shared secret header. The function returns HTTP 401 when the secret is absent or incorrect.

## Local check

```sh
supabase functions serve notify-symptom-break
```

Invoking without the APNs secrets set will fail fast with a clear
`Missing required secret: ...` message instead of sending anything.
