# Mac handoff

## What Aditya needs to bring

- His Mac, its macOS version and available disk space (inspect locally; no need to send machine identifiers).
- The private repository checkout or portable ZIP.
- His iPhone, iOS version and a data-capable cable.
- A free Apple Account, entered by him in Apple’s own sign-in flow. No paid membership needed for own-device testing.
- For separate-device testing later: a **new** Supabase project URL/publishable key after explicit project/cost choice, and distinct test login accounts. No backend credentials are required for local demo mode.

## What the next agent should do

1. Inspect `sw_vers`, `uname -m`, `df -h`, `xcode-select -p`, `xcodebuild -version` and `xcrun simctl list devices available`. Do not assume the Mac is compatible. Check Apple’s current Xcode support table if installation/update is needed.
2. The user authorized installing official Xcode if absent on a compatible Mac. Use Apple’s source, surface Apple login, disk, compatibility or license blockers, and let the user handle passwords, 2FA and any required agreement acceptance. Do not buy membership or install Xcode on the Windows PC.
3. Run `sh scripts/mac-check.sh`. Swift source is prepared but **no compiler has type-checked it yet**. Fix any build/test issues before presenting it as runnable. Run `swift test` for the actual `Domain.swift` implementation, then **⌘U** in Xcode on an installed simulator for `SteadyAppTests` (offline refresh regression).
4. Run the simulator, perform `MANUAL_TESTS.md`, inspect accessibility/large text/dark mode, and save actual simulator screenshots in `Validation/`. No iOS screenshots were created on Windows.
5. Help Aditya select his Personal Team and run the app on his connected iPhone. The **`remote-notification` background mode** is in the project. The **Push Notifications entitlement** file (`Steady/Steady.entitlements`, `aps-environment = development`) exists but is **not wired into the default build**, so a free Personal Team can sign. A **free Personal Team can build and run the app on device**, and the **local-notification fallback** already demonstrates the symptom-break UX on that single device; it **cannot enable the push capability with a real provisioning profile and cannot receive remote pushes**, and Personal Team provisioning expires in about **7 days**. **Live cross-device remote APNs delivery is not part of what a free account can do**: it requires a **paid Apple Developer Program membership ($99/yr)**, a real **APNs `.p8` auth key**, and the **Push Notifications capability** enabled with a real profile. None of the remote-push path has been run on device, simulator, a live backend or live APNs here. To enable live delivery when the paid account exists:
   - In Xcode, on **Steady target → Signing & Capabilities**, add the **Push Notifications** capability. Xcode will set **Code Signing Entitlements**; point it at the existing `Steady/Steady.entitlements` (switch `aps-environment` to `production` for release builds). Confirm the `remote-notification` background mode is present.
   - In the Apple Developer portal, create an **APNs Auth Key** and download the **`.p8`** file. Note the **Key ID**, your **Team ID**, and the app's **Bundle ID**. Never commit the `.p8` or any of these values.
   - Set them as **Supabase Edge Function secrets** (never in the repo or in git):
     ```sh
     supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=...
     supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXX.p8)"
     ```
   - Deploy the function: `supabase functions deploy notify-symptom-break`, and wire the `check_ins` symptom-break trigger to invoke it in the hosted project (see [backend/README.md](backend/README.md)). Then verify delivery on two real devices.
6. Separate-account mode is source-complete prototype work that still requires a new backend, real service checks, separate test accounts and two-device verification. Follow `backend/README.md`; do not apply the migration to an existing database or provision a paid service without the exact authorization.

## Known prototype limits

- Account-mode networking/auth/session/Keychain behavior and shared attachment transfers are unverified against a real Supabase project.
- Shared feed currently shows up to 200 records; check-ins up to 25. There is no pagination, recovery-password UI, audit-event history, rate limiting for invitations/check-ins, production authentication hardening or clinician workflow integration.
- A completed file upload followed by failed record creation may leave an orphan object. The app reports the path; a survivor/admin must clean it up in Storage. Do not silently grant extra delete/read permissions to add-only roles to solve this.
- Shared file deletion and record deletion are two operations. A service failure between them can leave an entry whose file is missing. This needs reconciliation before production use.
- The remote APNs push path is implemented (device tokens, trigger, Edge Function, iOS registration, entitlement) but **not yet live**: foreground polling and the same-device local notification are what work on a free account today. Remote cross-device delivery stays dark until the paid membership, APNs `.p8` key and Edge Function secrets are configured. Previously displayed content can remain visible until the next successful refresh; downloaded/exported information cannot be revoked. No real patient data should be used.
- Local mode is intentionally single-device; its role switcher is not authentication.
- Sensor prediction, HealthKit, DICOM, diagnosis, actual patient enrollment, clinical validation and production compliance are outside this prototype.

## Relevant sources

- [Apple Xcode compatibility](https://developer.apple.com/xcode/system-requirements/)
- [Apple developer-account overview](https://developer.apple.com/support/compare-memberships/)
- [Supabase row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
