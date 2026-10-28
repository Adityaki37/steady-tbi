# Native acceptance checklist — all pending on Mac/iPhone

Do not mark these passed based on source checks or PostgreSQL tests.

## Local demo

1. First launch: fictional labels are obvious, Survivor role shows two symptom entries, one observation, one clinician note and the labeled fictional MRI file.
2. Add a symptom with intensity 4; edit it; force-quit/relaunch; confirm the changes remain. Delete it and confirm it is gone after relaunch.
3. Switch to Caregiver. Symptom history and files must be private. Add an observation and confirm it appears when switching to Survivor.
4. As Survivor, turn off caregiver observation **read**, leaving **add** on. Caregiver must still save an observation, with no history/count exposed afterward. Turn edit/delete on while read remains off: those actions must still be denied.
5. Check all four grants individually for each role/type. Clinician may read shared symptoms and add notes by default. Caregiver/clinician must not change grants or reset.
6. Import fictional PNG/JPEG/PDF from Files, preview each, edit details and delete. Relaunch to confirm imported copies persist. Try unsupported/renamed/corrupt/oversized files; local import must reject mismatched signatures or files above 15 MB.
7. Preview the bundled MRI: confirm it visibly says fictional, synthetic and not a patient scan. Confirm no analysis or interpretation is offered.
8. Trigger caregiver check-in with and without optional notification. Switch to Survivor and dismiss. If notifications are denied, the app must explain that the in-app check-in is still saved. No other device should be notified.
9. Reset as Survivor. Seed counts, default permissions and sample file return; imported local files and scheduled check-in notification are removed. Relaunch confirms reset persisted.
10. VoiceOver labels, largest Dynamic Type, light/dark mode, small iPhone, landscape and iPad: no clipped controls; no information communicated only by color.

## Separate test accounts on two devices (requires a new configured backend)

1. Use distinct confirmed accounts controlled by the tester. Survivor starts a fictional circle; separately invite caregiver and clinician emails. Verify another account, expired token, revoked token and reused token cannot join.
2. Sign in on the second device and accept the matching token. The role must come from the server, without a role picker.
3. Add a survivor symptom on device A; refresh on B. Caregiver must not see it by default; clinician should see it. Add caregiver observation and clinician note on B; A sees both.
4. Enable add with read off for an entry type. Save from B. The write succeeds without returning history. Direct REST reads with B’s normal session must also return no rows. Never use service-role keys for client tests.
5. Verify each grant and each entry type across devices, including edits/deletions and permission revocation while the other device is open. Failed writes must be surfaced.
6. Import a fictional file, refresh and download/Quick Look from the other device only when file read is granted. Revoke read and confirm fresh authenticated downloads fail; previously viewed/exported copies cannot be revoked.
7. Caregiver explicitly suggests a check-in. Survivor sees it after foreground refresh. Clinician/outsider must not create or read it. Confirm there is **no remote notification** while the survivor app is closed.
8. Remove membership and verify subsequent records, file, invite and check-in requests are denied. Sign out, relaunch, expire/refresh a session and disable networking; confirm account histories clear on failure and sessions do not cross between users/projects.
9. Test orphan cleanup and interrupted file deletion before considering account mode reliable beyond this prototype. Run Supabase security/performance advisors on the new test project.
