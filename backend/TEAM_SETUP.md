# Shared Supabase setup

Steady uses the hosted **Steady Demo** project, reference `sipqoeqvwkaljqifddxd`, in the owner's Supabase organization. The app connects to `https://sipqoeqvwkaljqifddxd.supabase.co`. This is a shared fictional-data demo, not a production patient-record system.

## Access and app configuration

- Developers use their own GitHub and Supabase accounts. The owner invites them to the repository and the Supabase organization's Team page. Developer access supports database work; project settings need Administrator access. Do not share the owner's login.
- A fresh checkout uses `Steady/SteadyResources/Backend.demo.plist`. It contains only the project URL and a publishable key. Regular testers need no Supabase dashboard account.
- `Steady/SteadyResources/Backend.local.plist`, when present, overrides that default. Use it only for a deliberate alternate backend. Remove or rename it to return to the shared demo. A `localhost` URL works only where that server is reachable; it does not connect another phone to the developer's Mac.
- The old `Steady/DemoResources/Backend.local.plist` path is no longer loaded. On the setup Mac, the old localhost configuration was preserved at `.git/steady-backups/DemoResources/Backend.local.plist`.
- Database passwords, access tokens, service-role keys, and APNs secrets never belong in app resources or Git. User sessions remain in each device's Keychain.

## Migration history reconciled November 19, 2026

The old repository used a different timestamp for the initial schema and separate files for changes that were deployed together. It also combined the signup quota and identity-trigger fix into one file. Those files have been replaced with the **actual SQL and versions from the hosted migration history**. No existing tables or user data were recreated.

`migration-baseline.json` records the hashes of the applied migrations. `python3 scripts/check_backend.py` rejects changes to those files. Add a new migration for every subsequent change; do not edit an applied migration, replay the initial schema, or use `--include-all` to work around a history mismatch. `backend/schema.sql` is only the original schema reference.

After later deployments, extend the baseline using the versions and SQL hashes verified against the hosted migration history. Preserve the existing entries.

If you previously ran the older migration filenames on a disposable local database, preserve any local data you need, then recreate **only that local test database** using the reconciled files. Do not reset the hosted project. A separately deployed project with an old history needs its own reviewed reconciliation before deployment.

## Development and testing

Use the pinned CLI `npx --yes supabase@2.122.0`; the deployment script also pins it because CLI v3 changes remote-targeting behavior. Check `--help` when changing CLI commands.

1. Pull current main and create a feature branch.
2. Create migrations with `npx --yes supabase@2.122.0 migration new descriptive_name`.
3. Develop against a local Supabase stack or an explicitly selected test project. A publishable key cannot administer a database.
4. Run:

   ```sh
   python3 scripts/check_backend.py
   python3 scripts/verify_project.py
   npm ci --prefix test-tools --ignore-scripts
   node test-tools/backend.test.mjs
   node test-tools/project.test.cjs
   ```

5. Open a pull request containing both app changes and migration SQL. CI tests the database rules and starts an isolated local Supabase stack. It does not deploy to the hosted project.
6. For changes used by existing app versions, add compatible columns/functions first. Release the updated app before removing an old API or column.

## Deploy the shared backend

The owner or an authorized developer sets **their own** `SUPABASE_ACCESS_TOKEN` in their shell or secret manager. The pinned CLI obtains a temporary database login from that token; no master database password is needed. Do not paste the token into source files, chat, or command-line arguments.

```sh
sh scripts/deploy-backend.sh plan
sh scripts/deploy-backend.sh apply
```

The first command previews pending migrations. The second previews again, applies pending migrations to the exact shared project, deploys only `demo-signup`, and lists migration status. It never resets the database, loads seeds, pushes project configuration, or deploys the unfinished APNs function. Stop and investigate any history mismatch. Check Supabase security/health advisors and test the affected app flows after deployment.

For read-only hosted HTTP checks, set the public `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, then run `node test-tools/hosted-health.mjs`. This checks Auth, unsigned-access denial, and invalid-signup rejection without creating any users. The more extensive `hosted-demo.e2e.mjs` creates synthetic users and needs targeted cleanup afterward.

For GitHub-based deployment, create an Actions environment named `steady-demo` and add these environment secrets:

- `SUPABASE_ACCESS_TOKEN`: a token scoped only to Steady Demo, with Database and Edge Functions read-write, and Project Settings and Connection Pooling read access. The configured deployment token does not expire, as requested by the project owner. Revoke or replace it in Supabase and update the GitHub secret when access needs to change.

After this branch is merged, open **Actions → Deploy shared Supabase backend → Run workflow** on `main`. Leave **apply** unchecked for a preview; check it to deploy. The workflow runs backend tests first and serializes deploys. GitHub pushes alone do not change the live database. The `steady-demo` environment should permit deployments only from `main`. GitHub deployment requires the environment secret above; Supabase app users and the app's publishable key cannot deploy schema changes.

App changes still require a new Xcode build and distribution to testers. Database deployment does not replace an installed app binary.

## Current boundaries

- Auth, private storage, and the nine public tables are present; all public tables have RLS enabled.
- The signup-quota table is intentionally private with no client policies. Do not add a permissive policy just to remove its [informational advisor notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Leaked-password protection is disabled on this Free-plan demo. Supabase makes [leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) available on Pro and above; this setup did not change billing or plans.
- APNs credentials and live remote push remain separate work. Foreground check-ins continue to use polling.

References: [Supabase access control](https://supabase.com/docs/guides/platform/access-control), [migration workflow](https://supabase.com/docs/guides/deployment/managing-environments), [API keys](https://supabase.com/docs/guides/getting-started/api-keys).
