# Validation evidence

Prepared on **DESKTOP-5MIQVIT / Windows 10.0.26300**. No Xcode or Swift executable was available, so no iOS app was launched or screenshotted here.

| Check | Result | What it establishes |
| --- | --- | --- |
| PostgreSQL schema + RLS test | PASS — see `backend-results.json` | 1,061 assertions; all 128 role/type/CRUD combinations; invitations, isolation, add-only writes, storage policies, check-ins, revocation |
| Portable structural checks | PASS — see `source-results.json` | Project references, assets, scheme XML, config template, RLS declarations and exact migration/source match |
| OpenStep Xcode project parser | PASS — see `project-parser-results.json` | Project file parses; one native target and five app source files |
| Swift grammar parser | PASS — see `swift-syntax-results.json` | Eight Swift source/manifest/test files parse without grammar errors |
| Swift compiler/type checking | **NOT RUN** | Requires Mac toolchain for the app |
| Seven Swift core XCTest methods | **NOT RUN** | Source supplied; run `swift test` on Mac |
| Xcode simulator build / visual screenshots | **NOT RUN** | Requires compatible Mac/Xcode |
| Free Personal Team signing / iPhone run | **NOT RUN** | Requires user’s Mac, Apple sign-in and connected iPhone |
| Real Supabase Auth/HTTP/Storage flow | **NOT RUN** | Requires an explicitly chosen new test backend |
| Two-device and accessibility UI acceptance | **NOT RUN** | Follow `MANUAL_TESTS.md` |

The PostgreSQL test engine is PGlite 0.5.13. Its Auth/Storage schemas are test doubles; those tests are not evidence that Supabase authentication, JWT validation, email delivery, file service limits or networking work end-to-end. JSON reports include scope limitations and schema digests.

No generated mockup is presented as a native app screenshot. The only supplied image is clearly labeled fictional brain-MRI illustration artwork for the attachment feature.
