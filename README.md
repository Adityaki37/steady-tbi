# Steady

A native SwiftUI **fictional-data prototype** for noticing and recording TBI-related experiences, with survivor, caregiver and clinician contributions. Sensor-based overload prediction is future work; this app does not predict overload or interpret scans.

## Try Steady on your Mac

The download contains the iPhone app’s source code. You can run the fictional demo in the iPhone Simulator with Xcode. The demo works offline after setup and runs without a Steady account or Supabase project.

1. Install and open a compatible version of **Xcode 16 or later**. Install an **iOS Simulator runtime** if Xcode prompts you. [Xcode downloads and Mac compatibility](https://developer.apple.com/xcode/system-requirements/) · [Installing simulator runtimes](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
2. Unzip the download and double-click **`Steady.xcodeproj`** in the extracted folder. [Download Steady ZIP](https://github.com/Adityaki37/steady-tbi/archive/refs/heads/main.zip)
3. In the Xcode toolbar, select the **Steady** scheme and an **iPhone simulator** as the run destination. Press **⌘R**. In Steady, leave **Accounts and sharing** off, choose **Survivor**, and open **Today → Activity log** or tap **Log a symptom**. The role picker lets you explore the caregiver and clinician demo views.

If you prefer Terminal, run this from the extracted folder. The script builds, installs, and launches the demo in an available iPhone simulator.

```sh
sh scripts/run-on-mac.sh
```

To try survivor onboarding and sharing across separate accounts, turn on **Accounts and sharing**. The download includes the connection to the hosted demo. [Account and sharing walkthrough](#create-an-account-and-share-a-circle)

### Run on your own iPhone

1. Connect and unlock your iPhone, trust the Mac if prompted, and sign in under **Xcode → Settings → Accounts** with your Apple Account.
2. Select the **Steady** target, open **Signing & Capabilities**, enable automatic signing, and choose your **Personal Team**. Change `com.aditya.steadydemo` to a unique bundle identifier if Xcode requests it.
3. Select your connected iPhone, enable **Developer Mode** if prompted, and press **⌘R**. Follow any developer trust prompt on the device.

Apple’s free Personal Team supports own-device testing with temporary provisioning. Run again from Xcode when the provisioning profile expires. Remote push uses a paid Apple Developer Program membership and separate setup. [Apple membership comparison](https://developer.apple.com/support/compare-memberships/) · [Remote push setup](MAC_HANDOFF.md)

## What is implemented

- **Local demo:** three switchable fictional roles; symptom intensity and context; caregiver observations; clinician notes; file import, metadata editing, deletion and native image/PDF preview; explicit reset; atomic disk persistence; a clearly synthetic, labeled brain MRI illustration.
- **Permissions:** the survivor retains all access. Other roles have separate read/add/edit/delete grants for each entry type. Edit/delete require read. Grants apply to all records of that type, not only records the contributor authored. Default caregiver access is observations only; clinician reads all types and contributes clinician notes. Local repository methods reject denied actions even if called directly.
- **Separate accounts:** hosted demo usernames and passwords, Keychain sessions, one-use invitations bound to the recipient’s account, and survivor-managed access. Testers can try the hosted demo using the standard download. [Backend details](backend/README.md)
- **Check-ins and the caregiver symptom-break prompt:** a caregiver can suggest a general check-in and, with a separate action, send a calm **"I noticed a possible symptom - suggest a break"** prompt. In account mode this is stored as a `symptom_break` check-in; the survivor sees it on foreground refresh (15-second polling). Local demo can schedule an optional **same-iPhone** notification mirroring the same gentle wording. This is a supportive prompt, not a diagnosis, and does not predict overload.
- **Remote push (requires hosted setup and device verification):** the full APNs path exists end to end: a per-user `device_tokens` table with own-rows-only RLS; the iOS app registers for remote notifications, captures the APNs device token and uploads it via the account client; a `symptom_break` check-in fires an `AFTER INSERT` trigger (`private.notify_symptom_break`) that looks up the circle owner's tokens server-side and invokes a Supabase Edge Function (`supabase/functions/notify-symptom-break`) which signs an APNs JWT from Edge Function secrets and POSTs to Apple's APNs. Local tests covered the stored break prompt and per-user token permissions. The hosted webhook and APNs delivery are pending. Live cross-device delivery is **gated**: it requires a **paid Apple Developer Program membership**, an **APNs `.p8` auth key** (key id / team id / bundle id), and the **Push Notifications capability with a real provisioning profile**. A free Personal Team cannot deliver remote pushes. Until the paid account and APNs secrets are configured, the survivor still sees the prompt on foreground refresh, and the **local-notification fallback** demonstrates the UX on the same device now. The existing 15-second foreground polling is retained as the fallback either way.
- Calm system typography, adaptable light/dark colors, semantic labels, Dynamic Type-friendly layouts, and no flashing or forced animations. Actual VoiceOver, large-text and device layout QA remains pending.

## Create an account and share a circle

1. Turn on **Accounts and sharing**, choose **Sign up**, and select **Survivor**, **Caregiver**, or **Clinician**. Pick a fictional username and a new password of at least 10 characters. Use a distinct account for each role. Keep your demo password for later sign-in, since the demo has no email recovery. Use fictional data throughout.
2. Once the caregiver or clinician has signed up, the survivor selects **Create my circle → Manage sharing**, enters the recipient’s demo username, and picks their role in the circle. Create an invitation code and share it with that person.
3. The recipient signs in with their demo username and enters the code under **Join a survivor’s circle**. The circle opens with the role assigned by the invitation. To try all three accounts on one Mac, sign out before switching roles or use separate iPhone simulators.
4. In **Manage sharing**, the survivor can change read, add, edit, and delete permissions by role and record type, revoke pending invitations, or remove a person’s access.

Use **Account → Sign out** to switch accounts on the same device. Choose **Sign up** for a new account or **Sign in** to return to an existing one. Setup follows the signed-in account. Survivors with an unfinished profile see setup when they sign in, and returning survivors with a saved profile can continue where they left off.

On first sign-in, Steady asks survivors for their name, injury date if known, and optional injury details. They choose symptoms by category, can add their own, and put them in the order they usually notice them. The order is a personal estimate. The survivor can edit it from **Account → Survivor profile**.

In **Manage sharing → People with access**, the survivor can turn on **Share injury details and ranked symptoms** for each person who has joined. That person can read the survivor’s current injury date, description, notes, and symptom order under **Shared survivor profile**. Profile sharing starts off and can be turned off independently of journal access. The profile name stays private. Removing a person from the circle also revokes their profile access.

## Modes and data

Survivors can open **Activity log** from **Today** or **Journal** in the local demo, or from **Account** when signed in. Each entry records the activity, start date and time, duration in minutes, cognitive fatigue at the end on a 0–5 scale, and optional symptoms in the survivor’s own words. Tap an entry to edit it or swipe to delete it. Entries are private in account mode and the fictional demo stores its own entries on the device.

The local role picker is an explicit demonstration, **not production authentication**. Anyone with access to that demo can switch to Survivor. Separate-account mode does not use this role picker: its role comes from ownership or an accepted server invitation.

Local state is stored in the app’s Application Support directory (`SteadyDemo/demo-v1.json`), with imported files in `Attachments/`. Writes are atomic and use iOS file protection. The directory is excluded from app backups. Reset restores fictional seeds/default permissions, removes imported local files and clears the check-in notification. A corrupt file shows recovery UI instead of silently resetting. Local data is never automatically uploaded to account mode.

Shared record data is held in memory while account mode is open, persisted in the configured backend, and cleared on sign-out, backgrounding, refresh failure or circle changes. Access is rechecked server-side per request. Revocation cannot erase information someone already saw, downloaded or exported. This prototype is not suitable for real patient records.

Supported attachments: PNG/JPEG/PDF, up to 15 MB. Imported files are copied into app storage in local mode. The sample is code-drawn fictional artwork, not a patient MRI. No DICOM parser, imaging analysis or diagnosis is included.

## Verification

### What CI verifies, and what it does not

Two GitHub Actions workflows configure these checks. See [validation results](Validation/README.md) for the local Mac and Supabase runs.

| Area | Configured in CI | Not verified |
| --- | --- | --- |
| Swift package tests, unsigned simulator build, app-hosted `SteadyAppTests` | Yes, on an iOS **simulator** | Physical iPhone, free Personal Team signing |
| `SteadyUITests` (XCUITest) | Drives the **local demo mode** on a simulator: symptom logging, Journal, Files preview, permission toggles, caregiver and clinician flows, check-in, reset, large Dynamic Type. Screenshots are exported from the xcresult | VoiceOver, device layouts, account mode |
| Accessibility audit (`testAccessibilityAudit`) | Runs XCUITest `performAccessibilityAudit()` (iOS 17+) on Today (survivor and caregiver), Journal, Files, the file preview sheet, Control and the editor sheet in one run (issues are collected, then reported once), as a separate CI step so other UI tests are unaffected. It is configured to run in CI on macos-15 (not yet verified; the step is non-gating until a first baseline is triaged) and prints every issue as `A11Y_ISSUE` lines (screen, type, description, element) plus `A11Y_AUDIT_SCREEN` per screen and `A11Y_TEST_EXIT=<code>` if the markers reach the log. No audit type is excluded. It does not replace VoiceOver testing | Real VoiceOver use, contrast judgement beyond the automated checks, device layouts |
| Supabase backend | An **ephemeral local Supabase stack** started with Docker in CI (`live-supabase.yml`) exercises Auth, PostgREST, and Storage. The hosted demo has a separate smoke test for all three roles, invitations, profile sharing and revocation, and activity log privacy. | Physical devices against the hosted demo |
| Remote push (APNs) | Nothing. Only the `device_tokens` table and the `symptom_break` check-in without the Edge Function are covered by the e2e script | Edge Function, APNs delivery and token registration. These need a **paid Apple Developer Program account**, an APNs key and a real provisioning profile |

Windows host verified: **DESKTOP-5MIQVIT, Windows 10.0.26300**. Node 24.13.0, Python 3.14 and Git were available; no Swift or Xcode executable was found. No `.agents/skills`, existing project instructions, or prior test/run instructions were present in the initially empty workspace. Xcode cannot run on this OS, so no Xcode installation was attempted here.

Run portable checks:

```sh
python3 scripts/verify_project.py
npm ci --prefix test-tools --ignore-scripts
node test-tools/backend.test.mjs
node test-tools/project.test.cjs
```

Backend tests execute PostgreSQL RLS and functions using pinned PGlite, with minimal Auth/Storage test tables. They cover all **128 permission combinations** (2 roles × 4 types × 16 CRUD combinations), invitation replay/email/expiry/revocation, cross-circle isolation, author spoofing, storage gates, check-ins and member revocation. This is stronger than a JavaScript policy mock, but **does not exercise Supabase’s HTTP, Auth or Storage services**. Reports are in [Validation](Validation/).

An additional optional Swift grammar parse was run on Windows with pinned tree-sitter packages. It found no syntax errors in the nine Swift files. This is **not type checking or compilation**. To repeat: `python3 -m pip install --target .validation-python -r validation-requirements.txt`, then `python3 scripts/swift_parse.py`. Regenerating project assets with `scripts/generate_project.py` additionally needs Pillow; normal building does not.

On the Mac, before calling the app verified:

```sh
sh scripts/mac-check.sh
```

`sh scripts/run-on-mac.sh` builds and launches the app in a simulator (see Start on your Mac). `sh scripts/mac-check.sh` runs the Swift package XCTest methods, then an unsigned simulator build. The **SteadyAppTests** target in the Xcode scheme contains app-hosted regression tests. Run **Product → Test (⌘U)** with an installed simulator selected. Follow [MANUAL_TESTS.md](MANUAL_TESTS.md) for native UI and two-device checks.

## Handoff to Codex on your Mac

Open this repository folder in Codex and say:

> Continue Steady from MAC_HANDOFF.md. Inspect this Mac and Xcode first, run the provided checks, fix compile/test failures, run and screenshot the local demo in Simulator, then help me sign and run it on my own iPhone with my free Personal Team. Keep all records fictional. Do not enroll/pay, deploy or change hosted databases without confirming the exact new project.

Read [MAC_HANDOFF.md](MAC_HANDOFF.md) for the precise outstanding work and [backend/README.md](backend/README.md) before setting up separate devices.
