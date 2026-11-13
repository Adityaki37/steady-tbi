# Steady backend

The app bundles the URL and publishable key for the **Steady Demo** Supabase project. Testers can create accounts with fictional usernames and passwords. The `demo-signup` Edge Function creates those accounts in a reserved namespace and limits signup attempts. The app ships with the publishable key, and the function uses Supabase’s server-side secret from its environment. The dedicated demo is on the Free plan and may pause with inactivity. [Supabase project pausing](https://supabase.com/docs/guides/platform/free-project-pausing)

The owner can check or restore the project from [Supabase Dashboard](https://supabase.com/dashboard/project/sipqoeqvwkaljqifddxd). Use fictional records. Demo accounts have no email delivery or password recovery. Remote APNs is pending, and in-app check-ins sync on refresh.

Hosted smoke tests are in `test-tools/hosted-demo.e2e.mjs`. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` and run it with Node 22 or later. It creates four synthetic accounts to exercise all three roles and test switching between survivors. It signs them out and prints their IDs for targeted cleanup.

## Architecture

- Supabase Auth password accounts. The hosted demo maps usernames to synthetic addresses. The local override supports email confirmation. Signup stores the chosen profile role in `user_metadata.steady_role` for onboarding. Circle ownership and accepted invitations authorize access. The app keeps session/refresh tokens in iOS Keychain (`WhenUnlockedThisDeviceOnly`).
- Survivor onboarding stores the name, injury details, and ordered symptoms in `survivor_profiles` after sign-in. The table remains owner-only. Each circle membership has an opt-in read grant for the injury date, description, notes, and ordered symptoms. `shared_survivor_profile` checks the current membership and grant and returns those fields. The survivor can toggle the grant, and removal or rejoining resets it.
- A survivor owns one circle. Caregiver/clinician identities are separate accounts admitted by an email-bound, expiring, single-use invitation. Tokens are generated on the server, stored only as SHA-256 hashes, returned once to the owner, and shared manually. Invitations bind to known/confirmed recipient accounts; membership deletion transactionally revokes their outstanding invitations, even after email changes. A fresh owner-issued invitation is required to regain access. No invitation email is sent by this source project.
- Activity logs are private to the authenticated account that created them. They are available from the survivor’s account screen. Circle membership and profile sharing never grant access to activity entries.
- Nine public tables have RLS and explicit grants. Ownership/membership and current grants in the database authorize each action. User-editable metadata and client-selected roles are never authorization sources.
- The owner retains full access. Shared-role grants are per entry type. `add` works without `read`; inserts intentionally use minimal responses. `edit` and `delete` require read. Roles with edit/delete can change any record of that type, not merely their own. Record identity, circle, kind, author, creation time and file path are immutable.
- Storage bucket `steady-fictional` is private, with PNG/JPEG/PDF MIME types and a 15 MB cap. Object policies check the current attachment grant for the circle. Downloads are authenticated requests, not public links or long-lived signed URLs. Object replacement is deliberately disabled.
- Clinician fictional-MRI upload is enforced entirely by the same attachment grant, not by a role check. By default a clinician has Files **read** on but Files **add** off, so storage-object and attachment-record inserts are both denied. The survivor must first toggle clinician → Files → **Add** on (survivor controls access). Once granted, the clinician can upload a clearly **fictional** MRI illustration (not a real patient scan, no diagnostic interpretation), and the survivor plus any member with Files **read** can view it; a member without Files read cannot. The clinician still cannot change grants. This path is proven by `test-tools/backend.test.mjs` (with-grant and without-grant cases) and needs no schema change.
- Guarded security-definer routines are in the unexposed `private` schema with fixed empty search paths, explicit caller checks and revoked PUBLIC/anon execution. Public RPC wrappers are security-invoker. Private authorization lookups avoid recursive RLS.
- Caregiver check-ins are explicit server rows, read by the survivor. The `check_ins` table has a `category` column (`general` or `symptom_break`, default `general`); existing caregiver-insert / survivor-read RLS is unchanged. Foreground polling (15 seconds) reads these rows and is the fallback; it is **not remote push** and will not wake a closed app by itself.
- **Device tokens:** `public.device_tokens(user_id, token, platform, environment, updated_at)` stores each account's APNs device token. RLS is **own-rows-only** (`device_tokens_own`, `user_id = auth.uid()` in both `using` and `with check`): a user may read/write only their own tokens and can never see another user's. The iOS app uploads its token here after sign-in.
- **Symptom-break notification path:** when a caregiver inserts a `symptom_break` check-in, an `AFTER INSERT` trigger `private.notify_symptom_break()` (security-definer, empty search path) looks up the **circle owner's** device tokens server-side (never via caregiver-visible RLS) and invokes the Edge Function. The net call is guarded so the migration still applies cleanly under plain Postgres/PGlite (where the webhook helper is absent, the send is skipped and the insert commits). The actual APNs send lives in the `supabase/functions/notify-symptom-break` Edge Function. **PGlite tests exercise the schema, RLS and trigger-degrades-gracefully behavior; they do not exercise live APNs or the live webhook.**

## Configure a separate test project

1. Use a dedicated test project for a separate installation. The standard GitHub download already points to the hosted demo.
2. Use the dashboard or official CLI to configure that new project. Keep email confirmations **enabled**, anonymous sign-in **disabled**, and configure appropriate test-account email delivery/redirects. For this prototype, confirm email in the browser, return to the app, and sign in with the password; OAuth/deep-link login is not implemented.
3. Apply the files in `supabase/migrations/` in order. For an existing Steady test project, apply its pending migrations. `backend/schema.sql` is a reference copy of the initial migration. Verify the selected project before pushing and run its security and performance advisors.
4. Copy `Steady/SteadyResources/Backend.example.plist` to **`Steady/SteadyResources/Backend.local.plist`**. Enter the test project’s HTTPS URL and **publishable** key (`sb_publishable_...`). The gitignored local file takes precedence over `Backend.demo.plist`. Keep service-role keys, database passwords, refresh tokens, and APNs keys server-side.
5. Rebuild in Xcode. Switch on **Accounts and sharing**, sign up with a role for each fictional test account, confirm each email, and sign in. The survivor creates a circle and uses **Manage sharing** to invite the caregiver and clinician by email. Each recipient enters their code under **Join a survivor’s circle**. The selected circle determines each member’s access.
6. Use only fictional records. Import the supplied fictional MRI illustration with the sample upload button. To let a **clinician** upload the fictional MRI, the survivor first opens **Survivor access control** and turns on clinician → Files → **Add**; only then does the clinician’s **Import a fictional file** / **Upload bundled fictional MRI illustration** button act, and the survivor plus any member granted Files read can view it. The illustration is clearly fictional, not a patient scan, and Steady offers no diagnostic interpretation. Nothing from local demo mode is uploaded automatically.

## Enable the symptom-break remote push (paid Apple account required)

The device-token table, the `symptom_break` trigger and the `supabase/functions/notify-symptom-break` Edge Function are all in the repo. **Live cross-device APNs delivery is gated and has not been run here.** It requires a **paid Apple Developer Program membership**, a real **APNs `.p8` auth key**, and the Push Notifications capability enabled on a real provisioning profile. A free Personal Team can build/run the app and demonstrate the same-device local-notification fallback, but cannot receive remote pushes. To turn it on in a hosted project:

1. Create an **APNs Auth Key** in the Apple Developer portal and download the `.p8`. Record the **Key ID**, your **Team ID** and the app **Bundle ID**.
2. Set the Edge Function secrets with the CLI (**no real values live in this repo or in git**):
   ```sh
   supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=...
   supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXX.p8)"
   ```
   `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected into the function environment by the platform; the function reads the service-role key only inside its own runtime and it is never exposed to clients. The `.p8` is never committed.
3. Deploy the function and wire the trigger's webhook in the hosted project:
   ```sh
   supabase functions deploy notify-symptom-break
   ```
   The `[functions.notify-symptom-break]` entry already exists in `supabase/config.toml` (no secrets there). In a hosted project the trigger invokes the function through the `supabase_functions` webhook / `pg_net`; confirm those extensions are available. The trigger `private.notify_symptom_break` passes the bare function name `notify-symptom-break` (not a full URL) to `supabase_functions.http_request`; on the **first live deploy** confirm that the installed webhook-helper version resolves that name to the deployed function endpoint and that the argument shape matches the helper you have, because this wiring is manual and has not been exercised here.
4. Set `SYMPTOM_BREAK_WEBHOOK_SECRET` in the Edge Function environment and send the same value in the `x-steady-webhook-secret` header from the trusted database webhook. Keep the webhook configuration and secret server-side. The function rejects calls when the secret is missing or incorrect. Verify the authenticated trigger-to-function request before enabling remote push.
5. Verify delivery on two real devices. There is **no cross-device remote delivery on a free Apple account** and none of this has been validated here.

## Run backend rules on Windows, without a service

```sh
npm ci --prefix test-tools --ignore-scripts
node test-tools/backend.test.mjs
```

The test uses **PGlite 0.5.13**, a real PostgreSQL engine compiled to WASM, with minimal test doubles for `auth.users`, `auth.uid()` and Storage tables. It applies the actual SQL, switches between database roles, and executes all 128 CRUD combinations. It also checks unauthenticated denial, invitation matching/replay/expiry/revocation, unconfirmed email rejection, cross-circle isolation, author/path protections, add-only writes, storage RLS, check-ins and membership revocation.

This does **not** validate the actual Supabase API gateway, HTTP responses, JWT verification, email delivery, session rotation, MIME enforcement, Storage uploads, security advisors or two-device iOS behavior. Run service-level tests on the new project before claiming those flows work.

## Optional full local Supabase stack on the Mac

`supabase/config.toml` and the migration were generated by official CLI **2.122.0**. Docker Desktop’s daemon was unavailable on Windows, so the full stack was not started. A new Mac test setup may use:

```sh
npx --yes supabase@2.122.0 --help
npx --yes supabase@2.122.0 start --help
npx --yes supabase@2.122.0 start
```

The local config disables anonymous sign-in, requires email confirmation and contains no user seeds. The native account client intentionally requires an HTTPS project URL/publishable key. Connecting it to a LAN/local stack would additionally require a deliberately configured trusted HTTPS endpoint and current publishable key; do not disable ATS or certificate validation as a shortcut. PGlite tests need no Docker.

## Known limitations / required next work

- The app’s REST client is source only until Xcode builds and a real new test backend are exercised. JWT refresh tokens rotate; test concurrent requests, failed refresh and sign-out on the device. Existing access JWTs can remain valid until expiry after logout; for stronger production guarantees, add sensitive-operation `auth.sessions` checks and the full auth lifecycle.
- Foreground polling clears shared history on failure, on backgrounding and on sign-out. A previously seen/exported file cannot be remotely erased. A removed member loses future server access immediately; on-screen content clears on the next refresh/background/sign-out.
- Invitation/check-in abuse rate limits, audit trail, password recovery UI, MFA, clinician verification, real patient consent, production threat modeling and clinical validation are not implemented.
- File upload and record creation are separate. Failed record creation can leave an orphan, which the app reports. An owner/admin must reconcile Storage; there is no automatic cleanup worker. File deletion and entry deletion can also partially fail. Do not grant broad read/delete access to add-only contributors to mask these cases.
- **Add-only attachment upload and Storage RLS (decision: no policy change).** A member with `attachments.add=true` and `attachments.read=false` can add a file and its record but cannot download, list or read anything, including their own upload. Question researched: does storage-api need a SELECT policy for a plain upload? In the storage-api source ([`src/storage/uploader.ts`](https://github.com/supabase/storage/blob/master/src/storage/uploader.ts), [`src/storage/database/pg.ts`](https://github.com/supabase/storage/blob/master/src/storage/database/pg.ts)) a non-upsert POST runs a rolled-back permission probe as the caller using `INSERT INTO storage.objects (...) VALUES (...)` with no `RETURNING`, and checks for an existing key with a superuser connection, so the caller needs only the INSERT policy. Only `x-upsert: true` (INSERT ... ON CONFLICT DO UPDATE) needs SELECT and UPDATE, and both are intentionally absent, so overwrite and `PUT` are refused. Therefore `steady_files_add` is unchanged, the migration and `backend/schema.sql` are unchanged (still byte-identical), and no own-uploads SELECT policy was added because that would let a user without Files read see their own files. This is a reading of current `master`, not of the storage-api version pinned for CI, and older versions differ in detail. The decision is unverified until the live workflow has run against the pinned stack. `test-tools/live-stack.e2e.mjs` now runs the add-only flow against the real Storage service and prints one PASS/FAIL line per step with the HTTP status (upload accepted, record insert, no download, no list, no record read, survivor reads and downloads, duplicate and upsert and PUT refused, bytes unchanged). If the pinned CI Storage version does require SELECT for insert, the "caregiver POSTs the PNG" line will show the status and message and CI will fail rather than hide it; the narrowest fix would then be a SELECT policy on own objects (`owner_id = auth.uid()::text`) limited to circles where `attachments.add` is currently held, with its leak (own uploads only) documented, and the migration would be edited in place (acceptable only because no hosted database has applied it).
- The caregiver symptom-break remote-push path (device tokens, trigger, Edge Function, iOS registration, entitlement) is implemented but **not live**: live APNs delivery is gated on a paid Apple account + APNs `.p8` key + configured Edge Function secrets, and has not been run against a device, a live backend or live APNs here. Live realtime subscriptions are still future work. Do not label local notifications or foreground polling as cross-device push.

## Documentation consulted

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Password authentication](https://supabase.com/docs/guides/auth/passwords)
- [Current changelog](https://supabase.com/changelog): reviewed October 28, 2026. The announced [TLS cipher retirement](https://supabase.com/changelog/cbc-tls-ciphers-deprecated) affects obsolete TLS clients; this project uses standard HTTPS URLSession on iOS 17+. The [Postgres minor-update changes](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes) concern legacy pgcrypto/certain extensions not used here.
