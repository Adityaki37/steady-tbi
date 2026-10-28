# Steady

A native SwiftUI **fictional-data prototype** for noticing and recording TBI-related experiences, with survivor, caregiver and clinician contributions. Sensor-based overload prediction is future work; this app does not predict overload or interpret scans.

## Start on your Mac

1. Clone [the private repository](https://github.com/Adityaki37/steady-tbi) with `git clone https://github.com/Adityaki37/steady-tbi.git` (sign into your own GitHub account on the Mac), or unzip the complete project folder. Open **`Steady.xcodeproj`**, not an individual Swift file. No third-party Swift dependencies or project-generator install is required.
2. Use Xcode 16 or newer, with an iOS SDK compatible with your iPhone. The deployment target is **iOS 17.0**. Check [Apple’s Xcode compatibility table](https://developer.apple.com/xcode/system-requirements/) for your Mac’s macOS version. Use the latest compatible official Xcode from Apple; do not install Xcode on Windows.
3. In Xcode, choose the **Steady** scheme and an installed iPhone simulator. Press **⌘R**. Local demo mode works without an account, internet or backend configuration.
4. For your own iPhone, connect it by cable, unlock it and trust the Mac. In **Xcode → Settings → Accounts**, sign in yourself with your free Apple Account. Do not send your password or verification codes to an agent.
5. Select the **Steady target → Signing & Capabilities**. Leave automatic signing enabled, choose your **Personal Team**, and change `com.aditya.steadydemo` to a unique identifier if Xcode requests it. No Push Notifications capability is needed.
6. Select your connected iPhone as the run destination. Enable **Developer Mode** on the iPhone if requested, restart/confirm the system prompt, and press **⌘R**. Follow any developer trust prompt on the device.

No paid Apple membership, TestFlight, Rork or cloud build service is required for own-device development. Free Personal Team provisioning is temporary and has limits; rerun from Xcode when signing expires. Consult [Apple’s membership information](https://developer.apple.com/support/compare-memberships/) and the actual Xcode signing message rather than enrolling or paying to solve a demo build error.

## What is implemented

- **Local demo:** three switchable fictional roles; symptom intensity and context; caregiver observations; clinician notes; file import, metadata editing, deletion and native Quick Look preview; explicit reset; atomic disk persistence; a clearly synthetic, labeled brain MRI illustration.
- **Permissions:** the survivor retains all access. Other roles have separate read/add/edit/delete grants for each entry type. Edit/delete require read. Grants apply to all records of that type, not only records the contributor authored. Default caregiver access is observations only; clinician reads all types and contributes clinician notes. Local repository methods reject denied actions even if called directly.
- **Separate accounts:** email/password sign-up/sign-in, Keychain sessions and refresh, server-assigned circle roles, one-use email-bound invitations, membership removal, owner-managed grants, shared records and private file upload/download. This mode requires a newly configured Supabase backend; it is **not provisioned or end-to-end verified yet**. See [backend setup](backend/README.md).
- **Check-ins:** local demo can schedule an optional same-iPhone notification. Account mode stores a caregiver check-in on the server; the survivor sees it on foreground refresh (15-second polling). **Neither is remote APNs push.**
- Calm system typography, adaptable light/dark colors, semantic labels, Dynamic Type-friendly layouts, and no flashing or forced animations. Actual VoiceOver, large-text and device layout QA remains pending.

## Modes and data

The local role picker is an explicit demonstration, **not production authentication**. Anyone with access to that demo can switch to Survivor. Separate-account mode does not use this role picker: its role comes from ownership or an accepted server invitation.

Local state is stored in the app’s Application Support directory (`SteadyDemo/demo-v1.json`), with imported files in `Attachments/`. Writes are atomic and use iOS file protection. The directory is excluded from app backups. Reset restores fictional seeds/default permissions, removes imported local files and clears the check-in notification. A corrupt file shows recovery UI instead of silently resetting. Local data is never automatically uploaded to account mode.

Shared record data is held in memory while account mode is open, persisted in the configured backend, and cleared on sign-out, backgrounding, refresh failure or circle changes. Access is rechecked server-side per request. Revocation cannot erase information someone already saw, downloaded or exported. This prototype is not suitable for real patient records.

Supported attachments: PNG/JPEG/PDF, up to 15 MB. Imported files are copied into app storage in local mode. The sample is code-drawn fictional artwork, not a patient MRI. No DICOM parser, imaging analysis or diagnosis is included.

## Verification

Windows host verified: **DESKTOP-5MIQVIT, Windows 10.0.26300**. Node 24.13.0, Python 3.14 and Git were available; no Swift or Xcode executable was found. No `.agents/skills`, existing project instructions, or prior test/run instructions were present in the initially empty workspace. Xcode cannot run on this OS, so no Xcode installation was attempted here.

Run portable checks:

```sh
python3 scripts/verify_project.py
npm ci --prefix test-tools --ignore-scripts
node test-tools/backend.test.mjs
node test-tools/project.test.cjs
```

Backend tests execute PostgreSQL RLS and functions using pinned PGlite, with minimal Auth/Storage test tables. They cover all **128 permission combinations** (2 roles × 4 types × 16 CRUD combinations), invitation replay/email/expiry/revocation, cross-circle isolation, author spoofing, storage gates, check-ins and member revocation. This is stronger than a JavaScript policy mock, but **does not exercise Supabase’s HTTP, Auth or Storage services**. Reports are in [Validation](Validation/).

An additional optional Swift grammar parse was run on Windows with pinned tree-sitter packages. It found no syntax errors in the eight Swift files. This is **not type checking or compilation**. To repeat: `python3 -m pip install --target .validation-python -r validation-requirements.txt`, then `python3 scripts/swift_parse.py`. Regenerating project assets with `scripts/generate_project.py` additionally needs Pillow; normal building does not.

On the Mac, before calling the app verified:

```sh
sh scripts/mac-check.sh
```

That runs the seven supplied Swift package XCTest methods (including the complete permission matrix, disk persistence/reset, corruption and failed-write recovery), then an unsigned simulator build. These Swift tests and the build have **not run on Windows**. The Xcode scheme has no app-hosted XCTest target; core tests are run with `swift test`. Follow [MANUAL_TESTS.md](MANUAL_TESTS.md) for native UI and two-device checks.

## Handoff to Codex on your Mac

Open this repository folder in Codex and say:

> Continue Steady from MAC_HANDOFF.md. Inspect this Mac and Xcode first, run the provided checks, fix compile/test failures, run and screenshot the local demo in Simulator, then help me sign and run it on my own iPhone with my free Personal Team. Keep all records fictional. Do not enroll/pay, deploy or change hosted databases without confirming the exact new project.

Read [MAC_HANDOFF.md](MAC_HANDOFF.md) for the precise outstanding work and [backend/README.md](backend/README.md) before setting up separate devices.
