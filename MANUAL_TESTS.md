# Native acceptance checklist — all pending on Mac/iPhone

Do not mark these passed based on source checks or PostgreSQL tests.

CI context: simulator XCUITests (`SteadyUITests`) are configured to cover local demo flows (logging, Journal, Files preview, permission toggles, caregiver/clinician actions, check-in, reset, large text), and a local Supabase stack e2e script covers the HTTP contract. Neither runs on a physical iPhone, neither runs the iOS app against a live backend, and neither tests remote APNs. The items below stay pending until you perform them on a real device.

## Local demo

1. First launch: fictional labels are obvious, Survivor role shows two symptom entries, one observation, one clinician note and the labeled fictional MRI file.
2. Add a symptom with intensity 4; edit it; force-quit/relaunch; confirm the changes remain. Delete it and confirm it is gone after relaunch.
3. Switch to Caregiver. Symptom history and files must be private. Add an observation and confirm it appears when switching to Survivor.
4. As Survivor, turn off caregiver observation **read**, leaving **add** on. Caregiver must still save an observation, with no history/count exposed afterward. Turn edit/delete on while read remains off: those actions must still be denied.
5. Check all four grants individually for each role/type. Clinician may read shared symptoms and add notes by default. Caregiver/clinician must not change grants or reset.
6. Import fictional PNG/JPEG/PDF from Files, preview each, edit details and delete. Relaunch to confirm imported copies persist. Try unsupported/renamed/corrupt/oversized files; local import must reject mismatched signatures or files above 15 MB.
7. Preview the bundled MRI: confirm it visibly says fictional, synthetic and not a patient scan. Confirm no analysis or interpretation is offered.
8. Trigger caregiver check-in with and without optional notification. Switch to Survivor and dismiss. If notifications are denied, the app must explain that the in-app check-in is still saved. No other device should be notified.
8a. As Caregiver, use the **"suggest taking a break" / possible-symptom** action. Confirm the same-iPhone local notification (and the in-app notice) uses calm, supportive wording and explicitly says it is a supportive prompt, **not a diagnosis** and does not predict overload. Confirm it is **same-device only, no remote push** is sent to any other device in local demo mode.
9. Reset as Survivor. Seed counts, default permissions and sample file return; imported local files and scheduled check-in notification are removed. Relaunch confirms reset persisted.
10. VoiceOver labels, largest Dynamic Type, light/dark mode, small iPhone, landscape and iPad: no clipped controls; no information communicated only by color.

## Separate test accounts on two devices (requires a new configured backend)

None of the steps below have been run here (no Mac/iPhone, no live backend, no live APNs). **There is no cross-device remote delivery on a free Apple account.** The remote-push steps are live only on a **paid Apple Developer Program membership** with an APNs `.p8` auth key and the Edge Function secrets configured; otherwise the survivor still sees the prompt on foreground refresh, and the same-device local-demo notification shows the UX.

1. Use distinct confirmed accounts controlled by the tester. Survivor starts a fictional circle; separately invite caregiver and clinician emails. Verify another account, expired token, revoked token and reused token cannot join.
2. Sign in on the second device and accept the matching token. The role must come from the server, without a role picker.
3. Add a survivor symptom on device A; refresh on B. Caregiver must not see it by default; clinician should see it. Add caregiver observation and clinician note on B; A sees both.
4. Enable add with read off for an entry type. Save from B. The write succeeds without returning history. Direct REST reads with B’s normal session must also return no rows. Never use service-role keys for client tests.
5. Verify each grant and each entry type across devices, including edits/deletions and permission revocation while the other device is open. Failed writes must be surfaced.
6. Import a fictional file, refresh and download/preview from the other device only when file read is granted. Revoke read and confirm fresh authenticated downloads fail; previously viewed/exported copies cannot be revoked.
   Clinician fictional-MRI upload: with the clinician's default Files grant (read on, add off), confirm the clinician has **no** working upload button and sees guidance that the survivor must grant Files → Add first; direct storage-object and attachment-record inserts are rejected. As Survivor, turn on clinician → Files → **Add**, then upload the bundled fictional MRI (or import a fictional file) from the clinician device. Confirm the survivor and any member with Files read can view it after refresh, a member without Files read cannot, and the illustration still reads as clearly fictional, not a patient scan, with no diagnostic interpretation. Confirm the clinician still cannot change any grant.
7. Caregiver explicitly suggests a check-in. Survivor sees it after foreground refresh. Clinician/outsider must not create or read it.
7a. **Device-token upload (pending on Mac/iPhone):** on the survivor device, grant notification permission and sign in. Confirm the app registers for remote notifications and uploads its APNs device token: a row appears in `public.device_tokens` for that survivor's `user_id` only. Confirm another account cannot read or write that token row (own-rows-only RLS).
7b. **Caregiver symptom-break prompt → survivor receipt (pending on Mac/iPhone):** as Caregiver, trigger the **"I noticed a possible symptom - suggest a break"** action. It is stored as a `symptom_break` check-in; the survivor sees it after foreground refresh. Clinician/outsider must not create or read it. **Live remote push** that wakes a closed survivor app arrives **only when a paid Apple account + APNs key + Edge Function secrets are configured** and the survivor's device token is registered; on a free account there is **no remote notification** while the survivor app is closed, so the survivor instead sees it on the next foreground refresh, and the local-demo notification demonstrates the UX on the same device. Confirm the wording is calm and non-diagnostic.
8. Remove membership and verify subsequent records, file, invite and check-in requests are denied. Sign out, relaunch, expire/refresh a session and disable networking; confirm account histories clear on failure and sessions do not cross between users/projects.
   Also issue two invitations to the same account, accept the first, remove membership, then try the second: it must be revoked. After loading history, disconnect and use **Refresh shared data**: records/permissions/circle labels must clear, with the session retained for retry. Run the included `SteadyAppTests` offline regression test in Xcode.
9. Test orphan cleanup and interrupted file deletion before considering account mode reliable beyond this prototype. Run Supabase security/performance advisors on the new test project.
