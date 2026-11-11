# Validation evidence

Prepared on **DESKTOP-5MIQVIT / Windows 10.0.26300**. No Xcode or Swift executable was available, so no iOS app was launched or screenshotted here.

| Check | Result | What it establishes |
| --- | --- | --- |
| PostgreSQL schema + RLS test | PASS — see `backend-results.json` | 1,072 assertions; all 128 role/type/CRUD combinations; invitations, isolation, add-only writes, storage policies, check-ins, revocation |
| Portable structural checks | PASS — see `source-results.json` | Project references, assets, scheme XML, config template, RLS declarations and exact migration/source match |
| OpenStep Xcode project parser | PASS — see `project-parser-results.json` | Project file parses; native app/test targets and five app source files |
| Swift grammar parser | PASS — see `swift-syntax-results.json` | Nine Swift source/manifest/test files parse without grammar errors |
| Swift compiler/type checking | **NOT RUN** | Requires Mac toolchain for the app |
| Seven Swift core XCTest methods | **NOT RUN** | Source supplied; run `swift test` on Mac |
| Offline/manual-refresh app XCTest | **NOT RUN** | `AppTests/CloudClientTests.swift`; run ⌘U in the Steady scheme on Mac |
| Xcode simulator build / visual screenshots | **NOT RUN** | Requires compatible Mac/Xcode |
| Free Personal Team signing / iPhone run | **NOT RUN** | Requires user’s Mac, Apple sign-in and connected iPhone |
| Simulator UI tests (`SteadyUITests`, local demo mode) | **CI-configured, not run here** | `ios-build.yml` on macos-15; confirm in the Actions run log |
| Simulator accessibility audit (`testAccessibilityAudit`, `performAccessibilityAudit`) | **CI-configured, not run here** | `ios-build.yml` on macos-15; results in log markers `A11Y_ISSUE` and `A11Y_TEST_EXIT` |
| `scripts/run-on-mac.sh` (simulator build, install, launch) | **CI-configured, not run here** | `ios-build.yml` on macos-15; result in log marker `RUN_ON_MAC_EXIT`. On Linux it only exits 0 with a message |
| Live local Supabase HTTP flow (`test-tools/live-stack.e2e.mjs`) | **CI-configured, not run here** | `live-supabase.yml` on ubuntu-latest with Docker; tests the HTTP contract, not the iOS app |
| iOS app against a live backend / hosted Supabase project | **NOT RUN** | Requires an explicitly chosen new test backend |
| Remote APNs push delivery | **NOT RUN** | Needs a paid Apple Developer account, APNs key and a real device |
| Two-device and accessibility UI acceptance | **NOT RUN** | Follow `MANUAL_TESTS.md` |

The PostgreSQL test engine is PGlite 0.5.13. Its Auth/Storage schemas are test doubles; those tests are not evidence that Supabase authentication, JWT validation, email delivery, file service limits or networking work end-to-end. JSON reports include scope limitations and schema digests.

Review regressions covered: a second outstanding invitation cannot restore a removed member’s access (also after an email change); a fresh survivor-issued invitation can intentionally restore it. File revocation tests first confirm the caregiver can actually read the file, then remove membership and confirm denial. Storage update/delete grants and immutable attachment paths are exercised. The native manual-refresh test first loads shared history, injects an offline response, checks all shared state clears while the session remains, then checks recovery; that test is source-only until Mac execution.

No generated mockup is presented as a native app screenshot. The only supplied image is clearly labeled fictional brain-MRI illustration artwork for the attachment feature.
