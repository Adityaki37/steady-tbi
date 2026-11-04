# Separate-device backend — not provisioned

This folder contains code for a new Supabase project. **No existing database has been changed and no hosted project, paid service or APNs configuration has been created.** Local demo mode needs none of this.

## Architecture

- Supabase Auth email/password accounts. The user enters credentials directly in the app; the app keeps session/refresh tokens in iOS Keychain (`WhenUnlockedThisDeviceOnly`). Passwords are not persisted by the app.
- A survivor owns one circle. Caregiver/clinician identities are separate accounts admitted by an email-bound, expiring, single-use invitation. Tokens are generated on the server, stored only as SHA-256 hashes, returned once to the owner, and shared manually. Invitations bind to known/confirmed recipient accounts; membership deletion transactionally revokes their outstanding invitations, even after email changes. A fresh owner-issued invitation is required to regain access. No invitation email is sent by this source project.
- Six public tables have RLS and explicit grants. Ownership/membership and current grants in the database authorize each action. User-editable metadata and client-selected roles are never authorization sources.
- The owner retains full access. Shared-role grants are per entry type. `add` works without `read`; inserts intentionally use minimal responses. `edit` and `delete` require read. Roles with edit/delete can change any record of that type, not merely their own. Record identity, circle, kind, author, creation time and file path are immutable.
- Storage bucket `steady-fictional` is private, with PNG/JPEG/PDF MIME types and a 15 MB cap. Object policies check the current attachment grant for the circle. Downloads are authenticated requests, not public links or long-lived signed URLs. Object replacement is deliberately disabled.
- Clinician fictional-MRI upload is enforced entirely by the same attachment grant, not by a role check. By default a clinician has Files **read** on but Files **add** off, so storage-object and attachment-record inserts are both denied. The survivor must first toggle clinician → Files → **Add** on (survivor controls access). Once granted, the clinician can upload a clearly **fictional** MRI illustration (not a real patient scan, no diagnostic interpretation), and the survivor plus any member with Files **read** can view it; a member without Files read cannot. The clinician still cannot change grants. This path is proven by `test-tools/backend.test.mjs` (with-grant and without-grant cases) and needs no schema change.
- Guarded security-definer routines are in the unexposed `private` schema with fixed empty search paths, explicit caller checks and revoked PUBLIC/anon execution. Public RPC wrappers are security-invoker. Private authorization lookups avoid recursive RLS.
- Caregiver check-ins are explicit server rows, read by the survivor. Foreground polling (15 seconds) is **not remote push** and will not wake a closed app. No device tokens, APNs keys or Push Notifications entitlement exist.

## Choose and configure a NEW project

1. Ask the user to choose a **new** test-only Supabase project and approve its exact cost/plan before provisioning. A free plan, if available for the selected organization, is the intended starting point; do not assume account eligibility or provision a paid project. Never point this migration at an existing app/database.
2. Use the dashboard or official CLI to configure that new project. Keep email confirmations **enabled**, anonymous sign-in **disabled**, and configure appropriate test-account email delivery/redirects. For this prototype, confirm email in the browser, return to the app, and sign in with the password; OAuth/deep-link login is not implemented.
3. Apply the single CLI-created file in `supabase/migrations/` to that new project after reviewing it. `backend/schema.sql` is an exact convenience copy, not a second migration. Use the CLI’s current `--help` before linking/pushing, verify the selected project reference, then run its security/performance advisors. No advisory checks have run against a hosted project yet.
4. In the iOS project, copy `Steady/Resources/Backend.example.plist` to **`Steady/Resources/Backend.local.plist`**. Enter only the new project’s HTTPS URL and **publishable** key (`sb_publishable_...`). This file is gitignored. Never put a service-role key, database password, refresh token or APNs key in the app/repository. The `.env.example` file is a reference only; the iOS app reads the bundled plist.
5. Rebuild in Xcode. Switch on **Separate accounts**, create/sign into distinct confirmed test accounts, and follow `MANUAL_TESTS.md`. Make a fictional survivor circle, invite the caregiver/clinician account emails, then enter the token on the appropriate other device. The same account may own one circle and be an invited member of another; each selected circle determines its role.
6. Use only fictional records. Import the supplied fictional MRI illustration with the sample upload button. To let a **clinician** upload the fictional MRI, the survivor first opens **Survivor access control** and turns on clinician → Files → **Add**; only then does the clinician’s **Import a fictional file** / **Upload bundled fictional MRI illustration** button act, and the survivor plus any member granted Files read can view it. The illustration is clearly fictional, not a patient scan, and Steady offers no diagnostic interpretation. Nothing from local demo mode is uploaded automatically.

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
- Live realtime subscriptions, background notifications and APNs are future work. Do not label local notifications or foreground polling as cross-device push.

## Documentation consulted

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
- [Password authentication](https://supabase.com/docs/guides/auth/passwords)
- [Current changelog](https://supabase.com/changelog): reviewed October 28, 2026. The announced [TLS cipher retirement](https://supabase.com/changelog/cbc-tls-ciphers-deprecated) affects obsolete TLS clients; this project uses standard HTTPS URLSession on iOS 17+. The [Postgres minor-update changes](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes) concern legacy pgcrypto/certain extensions not used here.
