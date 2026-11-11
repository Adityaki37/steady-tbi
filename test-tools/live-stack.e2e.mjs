// Live local-Supabase end-to-end check. Talks to a real `supabase start` stack over
// HTTP with the same paths, headers and bodies as Steady/CloudClient.swift.
// Needs Node 22 (built-in fetch) and these environment variables, supplied by CI:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Fictional data only. Keys and environment are never printed.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';

const base = (process.env.SUPABASE_URL ?? '').replace(/\/+$/, '');
const anon = process.env.SUPABASE_ANON_KEY ?? '';
const service = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
if (!base || !anon || !service) {
  console.error('Missing SUPABASE_URL, SUPABASE_ANON_KEY or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(2);
}

let passed = 0, failed = 0;
async function check(label, fn) {
  try { await fn(); passed++; console.log(`PASS: ${label}`); }
  catch (error) { failed++; console.log(`FAIL: ${label} :: ${String(error.message ?? error).split('\n')[0].slice(0, 300)}`); }
}

// Mirrors CloudClient.request: apikey + Bearer + Prefer return=minimal|representation.
async function api(path, { method = 'GET', token, key = anon, body, bytes, mime = 'application/json', representation = false, prefer, extraHeaders = {} } = {}) {
  const headers = { apikey: key, 'Content-Type': mime, Prefer: prefer ?? (representation ? 'return=representation' : 'return=minimal'), ...extraHeaders };
  if (token) headers.Authorization = `Bearer ${token}`;
  const payload = bytes ?? (body === undefined ? undefined : JSON.stringify(body));
  const response = await fetch(`${base}/${path}`, { method, headers, body: payload });
  const buffer = Buffer.from(await response.arrayBuffer());
  let json = null;
  try { json = JSON.parse(buffer.toString('utf8')); } catch { /* binary or empty */ }
  return { status: response.status, ok: response.ok, json, buffer };
}
const rpc = (name, token, body) => api(`rest/v1/rpc/${name}`, { method: 'POST', token, body });
const ok = (r, label = 'request') => assert.ok(r.ok, `${label} expected 2xx, got ${r.status}`);
const rejected = (r, label = 'request') => assert.ok(!r.ok, `${label} expected rejection, got ${r.status}`);
// Per-step reporting for the add-only upload section: every step prints its own line with the HTTP status.
const message = (r) => String(r.json?.message ?? r.json?.error ?? r.json?.msg ?? '').slice(0, 120);
async function step(label, fn) {
  let r;
  try {
    r = await fn();
    passed++; console.log(`PASS: ${label} [HTTP ${r.status}${message(r) ? ` ${message(r)}` : ''}]`);
  } catch (error) {
    failed++; console.log(`FAIL: ${label} [${r ? `HTTP ${r.status}` : 'no response'}] :: ${String(error.message ?? error).split('\n')[0].slice(0, 300)}`);
  }
}
const emptyRows = (r, label) => { ok(r, label); assert.deepEqual(r.json, [], `${label} expected no rows`); };

const run = randomBytes(4).toString('hex');
const password = 'Fictional-pass-' + randomBytes(6).toString('hex');
const emailFor = (name) => `${name}.${run}@example.com`;
const people = {};

async function adminCreate(name) {
  const r = await api('auth/v1/admin/users', { method: 'POST', key: service, token: service, body: { email: emailFor(name), password, email_confirm: true } });
  ok(r, `admin create ${name}`);
  people[name] = { email: emailFor(name), id: r.json.id };
}
async function signIn(name) {
  const r = await api('auth/v1/token?grant_type=password', { method: 'POST', body: { email: people[name].email, password } });
  ok(r, `sign in ${name}`);
  people[name].token = r.json.access_token;
  people[name].id = r.json.user.id;
}
const T = (name) => people[name].token;

// 1x1 transparent PNG.
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');

let circle, caregiverToken, clinicianToken;
const permissionPatch = (role, kind, patch) =>
  api(`rest/v1/circle_permissions?circle_id=eq.${circle}&role=eq.${role}&kind=eq.${kind}`, { method: 'PATCH', token: T('survivor'), body: patch, representation: true });
const records = (who, query = '') => api(`rest/v1/records?circle_id=eq.${circle}${query}&order=created_at.desc`, { token: T(who) });
const newRecord = (who, kind, title, extra = {}, representation = false) =>
  api('rest/v1/records', { method: 'POST', token: T(who), representation, body: { circle_id: circle, author_id: people[who].id, kind, title, body: 'Fictional entry.', ...extra } });

// ---------------------------------------------------------------- accounts
await check('sign up via /auth/v1/signup returns no session while email is unconfirmed', async () => {
  const email = emailFor('survivor');
  const r = await api('auth/v1/signup', { method: 'POST', body: { email, password } });
  ok(r, 'signup');
  assert.ok(!r.json.access_token, 'no session before confirmation');
  people.survivor = { email, id: r.json.id ?? r.json.user?.id };
  assert.ok(people.survivor.id, 'user id returned');
});
await check('password sign-in is refused until the email is confirmed', async () => {
  rejected(await api('auth/v1/token?grant_type=password', { method: 'POST', body: { email: people.survivor.email, password } }));
});
await check('admin API confirms the email and password sign-in then works', async () => {
  const r = await api(`auth/v1/admin/users/${people.survivor.id}`, { method: 'PUT', key: service, token: service, body: { email_confirm: true } });
  ok(r, 'admin confirm');
  await signIn('survivor');
});
for (const name of ['caregiver', 'clinician', 'outsider', 'unconfirmed']) {
  await check(`create account ${name}`, async () => {
    if (name === 'unconfirmed') {
      const email = emailFor(name);
      const r = await api('auth/v1/signup', { method: 'POST', body: { email, password } });
      ok(r, 'signup'); people[name] = { email, id: r.json.id ?? r.json.user?.id };
    } else { await adminCreate(name); await signIn(name); }
  });
}

// ---------------------------------------------------------------- circle and invitations
await check('anonymous key cannot create a circle', async () => {
  rejected(await rpc('create_circle', undefined, { n: 'No account' }));
});
await check('create_circle returns a uuid and my_role is survivor', async () => {
  const r = await rpc('create_circle', T('survivor'), { n: 'Fictional Alex’s circle' });
  ok(r, 'create_circle'); circle = r.json; assert.match(circle, /^[0-9a-f-]{36}$/);
  const role = await rpc('my_role', T('survivor'), { c: circle });
  ok(role); assert.equal(role.json, 'survivor');
});
await check('survivor lists exactly their own circle', async () => {
  const r = await api('rest/v1/circles?select=id,name,owner_id&order=created_at', { token: T('survivor') });
  ok(r); assert.equal(r.json.length, 1); assert.equal(r.json[0].id, circle);
});
await check('outsider sees no circle and my_role is null', async () => {
  const list = await api('rest/v1/circles?select=id', { token: T('outsider') });
  emptyRows(list, 'circles');
  const role = await rpc('my_role', T('outsider'), { c: circle });
  ok(role); assert.equal(role.json, null);
  const perms = await rpc('my_permissions', T('outsider'), { c: circle });
  ok(perms); assert.deepEqual(perms.json, []);
});
let pendingCaregiverToken;
await check('invite_member: only the survivor may invite, tokens are returned once', async () => {
  rejected(await rpc('invite_member', T('outsider'), { c: circle, email: people.outsider.email, r: 'clinician' }), 'outsider invite');
  const a = await rpc('invite_member', T('survivor'), { c: circle, email: people.caregiver.email, r: 'caregiver' });
  ok(a); caregiverToken = a.json;
  const b = await rpc('invite_member', T('survivor'), { c: circle, email: people.clinician.email, r: 'clinician' });
  ok(b); clinicianToken = b.json;
  const c = await rpc('invite_member', T('survivor'), { c: circle, email: people.caregiver.email, r: 'caregiver' });
  ok(c); pendingCaregiverToken = c.json;
  assert.ok(caregiverToken.length > 40);
  rejected(await rpc('invite_member', T('survivor'), { c: circle, email: 'not-an-email', r: 'caregiver' }), 'invalid email');
  rejected(await rpc('invite_member', T('survivor'), { c: circle, email: people.outsider.email, r: 'survivor' }), 'invalid role');
});
await check('accept_invite rejects a wrong recipient, accepts the right one, rejects replay', async () => {
  rejected(await rpc('accept_invite', T('outsider'), { token: caregiverToken }), 'wrong recipient');
  const r = await rpc('accept_invite', T('caregiver'), { token: caregiverToken });
  ok(r, 'accept'); assert.equal(r.json, circle);
  rejected(await rpc('accept_invite', T('caregiver'), { token: caregiverToken }), 'replay');
  const c = await rpc('accept_invite', T('clinician'), { token: clinicianToken });
  ok(c, 'clinician accept'); assert.equal(c.json, circle);
  rejected(await rpc('accept_invite', T('clinician'), { token: clinicianToken }), 'clinician replay');
});
await check('an unconfirmed account cannot sign in or accept an invitation', async () => {
  const t = await rpc('invite_member', T('survivor'), { c: circle, email: people.unconfirmed.email, r: 'caregiver' });
  ok(t);
  rejected(await api('auth/v1/token?grant_type=password', { method: 'POST', body: { email: people.unconfirmed.email, password } }), 'unconfirmed sign in');
  rejected(await rpc('accept_invite', anon, { token: t.json }), 'anon key as bearer');
});
await check('revoke_invite blocks acceptance and only the survivor may revoke', async () => {
  const t = await rpc('invite_member', T('survivor'), { c: circle, email: people.outsider.email, r: 'clinician' });
  ok(t);
  const list = await api(`rest/v1/circle_invitations?select=id,recipient_email,role,expires_at,accepted_at,revoked_at&circle_id=eq.${circle}`, { token: T('survivor') });
  ok(list);
  const row = list.json.find((i) => i.recipient_email === people.outsider.email);
  assert.ok(row, 'invitation visible to owner');
  rejected(await rpc('revoke_invite', T('caregiver'), { i: row.id }), 'caregiver revoke');
  ok(await rpc('revoke_invite', T('survivor'), { i: row.id }), 'owner revoke');
  rejected(await rpc('accept_invite', T('outsider'), { token: t.json }), 'revoked token');
});
await check('shared roles cannot read invitations, members of others or owner controls', async () => {
  emptyRows(await api(`rest/v1/circle_invitations?circle_id=eq.${circle}`, { token: T('caregiver') }), 'invitations');
  emptyRows(await api(`rest/v1/circle_permissions?circle_id=eq.${circle}`, { token: T('caregiver') }), 'permissions');
  const own = await api(`rest/v1/circle_members?circle_id=eq.${circle}`, { token: T('caregiver') });
  ok(own); assert.deepEqual(own.json.map((m) => m.user_id), [people.caregiver.id]);
  const all = await api(`rest/v1/circle_members?circle_id=eq.${circle}`, { token: T('survivor') });
  ok(all); assert.equal(all.json.length, 2);
});

// ---------------------------------------------------------------- permissions
await check('my_role and my_permissions match the default matrix', async () => {
  const cg = await rpc('my_role', T('caregiver'), { c: circle }); assert.equal(cg.json, 'caregiver');
  const cl = await rpc('my_role', T('clinician'), { c: circle }); assert.equal(cl.json, 'clinician');
  const perms = await rpc('my_permissions', T('caregiver'), { c: circle });
  ok(perms);
  const byKind = Object.fromEntries(perms.json.map((p) => [p.kind, p]));
  assert.equal(byKind.observations.can_read, true);
  assert.equal(byKind.observations.can_add, true);
  assert.equal(byKind.symptoms.can_read, false);
  assert.equal(byKind.symptoms.can_add, false);
  const clinician = Object.fromEntries((await rpc('my_permissions', T('clinician'), { c: circle })).json.map((p) => [p.kind, p]));
  assert.equal(clinician.symptoms.can_read, true);
  assert.equal(clinician.notes.can_add, true);
  assert.equal(clinician.attachments.can_add, false);
});

let symptomID, observationID;
await check('records: survivor adds a symptom; caregiver adds an observation but not a symptom', async () => {
  const s = await newRecord('survivor', 'symptoms', 'Fictional headache', { severity: 3 }, true);
  ok(s, 'survivor symptom'); symptomID = s.json[0].id;
  const o = await newRecord('caregiver', 'observations', 'Fictional rested well', {}, true);
  ok(o, 'caregiver observation'); observationID = o.json[0].id;
  rejected(await newRecord('caregiver', 'symptoms', 'Not allowed'), 'caregiver symptom');
  rejected(await newRecord('caregiver', 'observations', 'Spoofed author', { author_id: people.survivor.id }), 'author spoof');
  rejected(await newRecord('survivor', 'symptoms', 'Bad severity', { severity: 9 }), 'severity range');
});
await check('records: caregiver reads only observations; clinician reads everything', async () => {
  const cg = await records('caregiver'); ok(cg);
  assert.ok(cg.json.length >= 1 && cg.json.every((r) => r.kind === 'observations'), 'caregiver sees observations only');
  const cl = await records('clinician'); ok(cl);
  assert.ok(cl.json.some((r) => r.id === symptomID) && cl.json.some((r) => r.id === observationID));
  emptyRows(await records('outsider'), 'outsider records');
});
await check('add-without-read: caregiver can add a note with return=minimal but cannot read it back', async () => {
  ok(await permissionPatch('caregiver', 'notes', { can_add: true }), 'grant notes.add');
  const minimal = await newRecord('caregiver', 'notes', 'Fictional add-only note');
  ok(minimal, 'minimal insert'); assert.equal(minimal.status, 201);
  rejected(await newRecord('caregiver', 'notes', 'Needs RETURNING', {}, true), 'representation requires read');
  const seen = await records('caregiver', '&kind=eq.notes'); emptyRows(seen, 'notes read');
  const owner = await records('survivor', '&kind=eq.notes'); ok(owner);
  assert.ok(owner.json.some((r) => r.title === 'Fictional add-only note'), 'survivor sees the note');
  ok(await permissionPatch('caregiver', 'notes', { can_add: false }), 'revoke notes.add');
  rejected(await newRecord('caregiver', 'notes', 'After revoke'), 'add after revoke');
});
await check('edit and delete honour ownership of permissions; update needs read too', async () => {
  const other = await api(`rest/v1/records?id=eq.${symptomID}&circle_id=eq.${circle}`, { method: 'PATCH', token: T('caregiver'), body: { title: 'Hijack' }, representation: true });
  emptyRows(other, 'caregiver edit of symptom');
  const own = await api(`rest/v1/records?id=eq.${observationID}&circle_id=eq.${circle}`, { method: 'PATCH', token: T('caregiver'), body: { title: 'Fictional rested well (edited)', body: 'Edited.', severity: null }, representation: true });
  ok(own); assert.equal(own.json.length, 1); assert.equal(own.json[0].title, 'Fictional rested well (edited)');
  rejected(await api(`rest/v1/records?id=eq.${observationID}`, { method: 'PATCH', token: T('caregiver'), body: { kind: 'symptoms' }, representation: true }), 'kind immutable');
  rejected(await api(`rest/v1/records?id=eq.${observationID}`, { method: 'PATCH', token: T('caregiver'), body: { circle_id: randomUUID() }, representation: true }), 'circle immutable');
  ok(await permissionPatch('caregiver', 'observations', { can_read: false }), 'drop read');
  emptyRows(await api(`rest/v1/records?id=eq.${observationID}`, { method: 'PATCH', token: T('caregiver'), body: { title: 'No read' }, representation: true }), 'edit without read');
  ok(await permissionPatch('caregiver', 'observations', { can_read: true }), 'restore read');
  const clinicianDelete = await api(`rest/v1/records?id=eq.${observationID}`, { method: 'DELETE', token: T('clinician'), representation: true });
  emptyRows(clinicianDelete, 'clinician delete of observation');
  const del = await api(`rest/v1/records?id=eq.${observationID}`, { method: 'DELETE', token: T('caregiver'), representation: true });
  ok(del); assert.equal(del.json.length, 1);
});
await check('clinician adds a note but not an observation; notes survive to the survivor', async () => {
  const n = await newRecord('clinician', 'notes', 'Fictional clinician note', {}, true);
  ok(n, 'clinician note');
  rejected(await newRecord('clinician', 'observations', 'Not allowed'), 'clinician observation');
  const owner = await records('survivor', '&kind=eq.notes'); ok(owner);
  assert.ok(owner.json.some((r) => r.title === 'Fictional clinician note'));
});
await check('shared roles cannot change permissions; the survivor can', async () => {
  const attempt = await api(`rest/v1/circle_permissions?circle_id=eq.${circle}&role=eq.caregiver&kind=eq.symptoms`, { method: 'PATCH', token: T('caregiver'), body: { can_read: true }, representation: true });
  emptyRows(attempt, 'caregiver patch');
  emptyRows(await records('caregiver', '&kind=eq.symptoms'), 'symptoms still hidden');
  const own = await permissionPatch('caregiver', 'symptoms', { can_read: true });
  ok(own); assert.equal(own.json.length, 1);
  const visible = await records('caregiver', '&kind=eq.symptoms'); ok(visible); assert.ok(visible.json.length >= 1);
  ok(await permissionPatch('caregiver', 'symptoms', { can_read: false }), 'restore');
  emptyRows(await records('caregiver', '&kind=eq.symptoms'), 'symptoms hidden again');
});

// ---------------------------------------------------------------- storage
const uploadPath = () => `${circle}/${randomUUID()}.png`;
const upload = (who, path, bytes = png, mime = 'image/png') => api(`storage/v1/object/steady-fictional/${path}`, { method: 'POST', token: T(who), bytes, mime });
const download = (who, path) => api(`storage/v1/object/authenticated/steady-fictional/${path}`, { token: T(who) });
let clinicianPath, attachmentID;
await check('storage: clinician upload and attachment record are denied before attachments.add is granted', async () => {
  rejected(await upload('clinician', uploadPath()), 'upload without grant');
  rejected(await newRecord('clinician', 'attachments', 'Fictional MRI', { file_path: uploadPath(), file_name: 'mri.png' }), 'record without grant');
  rejected(await upload('caregiver', uploadPath()), 'caregiver upload');
  rejected(await upload('outsider', uploadPath()), 'outsider upload');
});
await check('storage: survivor upload works; bad paths and types are refused', async () => {
  const path = uploadPath();
  ok(await upload('survivor', path), 'survivor upload');
  rejected(await upload('survivor', `${circle}/not-a-uuid.png`), 'bad name');
  rejected(await upload('survivor', `${randomUUID()}/${randomUUID()}.png`), 'foreign circle path');
  rejected(await upload('survivor', `${circle}/${randomUUID()}.png`, Buffer.from('hi'), 'text/plain'), 'bad mime');
});
await check('storage: clinician uploads after the survivor grants attachments.add', async () => {
  ok(await permissionPatch('clinician', 'attachments', { can_add: true }), 'grant');
  clinicianPath = uploadPath();
  ok(await upload('clinician', clinicianPath), 'clinician upload');
  const rec = await newRecord('clinician', 'attachments', 'Fictional MRI', { file_path: clinicianPath, file_name: 'mri.png' }, true);
  ok(rec, 'attachment record'); attachmentID = rec.json[0].id;
  rejected(await newRecord('clinician', 'attachments', 'Wrong circle path', { file_path: `${randomUUID()}/${randomUUID()}.png`, file_name: 'x.png' }), 'path outside circle');
});
await check('storage: authenticated download rechecks access (survivor and clinician yes; caregiver and outsider no)', async () => {
  for (const who of ['survivor', 'clinician']) {
    const r = await download(who, clinicianPath);
    ok(r, `${who} download`); assert.ok(r.buffer.equals(png), `${who} bytes match`);
  }
  rejected(await download('caregiver', clinicianPath), 'caregiver download');
  rejected(await download('outsider', clinicianPath), 'outsider download');
  rejected(await api(`storage/v1/object/public/steady-fictional/${clinicianPath}`), 'bucket is private');
});
await check('storage: revoking attachments.add blocks new uploads but keeps read access', async () => {
  ok(await permissionPatch('clinician', 'attachments', { can_add: false }), 'revoke');
  rejected(await upload('clinician', uploadPath()), 'upload after revoke');
  ok(await download('clinician', clinicianPath), 'still readable');
});
await check('storage: delete is permission checked and removes the object', async () => {
  const denied = await api('storage/v1/object/steady-fictional', { method: 'DELETE', token: T('caregiver'), body: { prefixes: [clinicianPath] } });
  assert.ok(!denied.ok || (Array.isArray(denied.json) && denied.json.length === 0), 'caregiver delete removed nothing');
  const stillThere = await download('survivor', clinicianPath); ok(stillThere, 'object survives caregiver delete');
  const r = await api('storage/v1/object/steady-fictional', { method: 'DELETE', token: T('survivor'), body: { prefixes: [clinicianPath] } });
  ok(r, 'survivor delete');
  rejected(await download('survivor', clinicianPath), 'gone');
  const rec = await api(`rest/v1/records?id=eq.${attachmentID}`, { method: 'DELETE', token: T('survivor'), representation: true });
  ok(rec); assert.equal(rec.json.length, 1);
});

// ---------------------------------------------------------------- add-only attachment upload
// attachments.add=true with attachments.read=false: the caregiver may contribute a file and its
// record but must not be able to see, list or download anything. Storage RLS is checked by the
// real storage-api, which also decides whether INSERT needs a SELECT policy (see backend/README.md).
{
  const addOnlyPath = uploadPath();
  const overwrite = Buffer.concat([png, Buffer.from([0])]);
  let addOnlyRecord;
  await step('add-only: survivor grants caregiver attachments add=true (read stays false)', async () => {
    const r = await permissionPatch('caregiver', 'attachments', { can_add: true, can_read: false });
    ok(r, 'grant'); assert.equal(r.json.length, 1); assert.equal(r.json[0].can_add, true); assert.equal(r.json[0].can_read, false);
    return r;
  });
  await step('add-only: caregiver POSTs the PNG without x-upsert (Storage RLS accepts add-only insert)', async () => {
    const r = await upload('caregiver', addOnlyPath);
    ok(r, 'add-only upload'); return r;
  });
  await step('add-only: caregiver inserts the attachment record with return=minimal', async () => {
    const r = await newRecord('caregiver', 'attachments', 'Fictional add-only scan', { file_path: addOnlyPath, file_name: 'scan.png' });
    ok(r, 'record insert'); assert.equal(r.status, 201); return r;
  });
  await step('add-only: return=representation on the record is refused because read is false', async () => {
    const r = await newRecord('caregiver', 'attachments', 'Fictional needs RETURNING', { file_path: uploadPath(), file_name: 'x.png' }, true);
    rejected(r, 'representation'); return r;
  });
  await step('add-only: caregiver cannot download the object they just uploaded', async () => {
    const r = await download('caregiver', addOnlyPath); rejected(r, 'caregiver download'); return r;
  });
  await step('add-only: caregiver cannot list the circle folder (no entries returned)', async () => {
    const r = await api('storage/v1/object/list/steady-fictional', { method: 'POST', token: T('caregiver'), body: { prefix: circle, limit: 100, offset: 0 } });
    if (r.ok) { assert.ok(Array.isArray(r.json), 'list body is an array'); assert.equal(r.json.length, 0, 'list must be empty'); }
    return r;
  });
  await step('add-only: caregiver cannot read the attachment record', async () => {
    const r = await records('caregiver', '&kind=eq.attachments'); emptyRows(r, 'attachment records'); return r;
  });
  await step('add-only: caregiver cannot edit or delete the record or the object', async () => {
    const edit = await api(`rest/v1/records?circle_id=eq.${circle}&kind=eq.attachments&file_path=eq.${addOnlyPath}`, { method: 'PATCH', token: T('caregiver'), body: { title: 'Hijack' }, representation: true });
    assert.ok(!edit.ok || edit.json.length === 0, `record edit changed ${edit.json?.length} rows`);
    const del = await api(`rest/v1/records?circle_id=eq.${circle}&kind=eq.attachments`, { method: 'DELETE', token: T('caregiver'), representation: true });
    assert.ok(!del.ok || del.json.length === 0, 'record delete removed rows');
    const obj = await api('storage/v1/object/steady-fictional', { method: 'DELETE', token: T('caregiver'), body: { prefixes: [addOnlyPath] } });
    assert.ok(!obj.ok || (Array.isArray(obj.json) && obj.json.length === 0), 'object delete removed nothing');
    return obj;
  });
  await step('add-only: survivor reads the record', async () => {
    const r = await records('survivor', '&kind=eq.attachments'); ok(r, 'survivor records');
    const row = r.json.find((x) => x.file_path === addOnlyPath);
    assert.ok(row, 'record visible to survivor'); assert.equal(row.author_id, people.caregiver.id); addOnlyRecord = row; return r;
  });
  await step('add-only: survivor downloads the exact bytes', async () => {
    const r = await download('survivor', addOnlyPath); ok(r, 'survivor download'); assert.ok(r.buffer.equals(png), 'bytes match'); return r;
  });
  await step('add-only: re-POST to the same path without x-upsert is a conflict (non-upsert)', async () => {
    const r = await upload('caregiver', addOnlyPath, overwrite); rejected(r, 'duplicate'); return r;
  });
  await step('add-only: POST with x-upsert true is refused for the caregiver (no UPDATE policy)', async () => {
    const r = await api(`storage/v1/object/steady-fictional/${addOnlyPath}`, { method: 'POST', token: T('caregiver'), bytes: overwrite, mime: 'image/png', extraHeaders: { 'x-upsert': 'true' } });
    rejected(r, 'caregiver upsert'); return r;
  });
  await step('add-only: POST with x-upsert true is refused even for the survivor (objects are immutable)', async () => {
    const r = await api(`storage/v1/object/steady-fictional/${addOnlyPath}`, { method: 'POST', token: T('survivor'), bytes: overwrite, mime: 'image/png', extraHeaders: { 'x-upsert': 'true' } });
    rejected(r, 'survivor upsert'); return r;
  });
  await step('add-only: PUT (update object) is refused for caregiver and survivor', async () => {
    const c = await api(`storage/v1/object/steady-fictional/${addOnlyPath}`, { method: 'PUT', token: T('caregiver'), bytes: overwrite, mime: 'image/png' });
    rejected(c, 'caregiver PUT');
    const r = await api(`storage/v1/object/steady-fictional/${addOnlyPath}`, { method: 'PUT', token: T('survivor'), bytes: overwrite, mime: 'image/png' });
    rejected(r, 'survivor PUT'); return r;
  });
  await step('add-only: original bytes are unchanged after every overwrite attempt', async () => {
    const r = await download('survivor', addOnlyPath); ok(r, 'survivor download'); assert.ok(r.buffer.equals(png), 'bytes still match'); return r;
  });
  await step('add-only: a path in another circle or a bad type is refused for the add-only caregiver', async () => {
    rejected(await upload('caregiver', `${randomUUID()}/${randomUUID()}.png`), 'foreign circle');
    const r = await upload('caregiver', uploadPath(), Buffer.from('hi'), 'text/plain'); rejected(r, 'bad mime'); return r;
  });
  await step('add-only: revoking attachments.add blocks the next caregiver upload', async () => {
    ok(await permissionPatch('caregiver', 'attachments', { can_add: false }), 'revoke');
    const r = await upload('caregiver', uploadPath()); rejected(r, 'upload after revoke'); return r;
  });
  await step('add-only: cleanup, survivor deletes the object and the record', async () => {
    const o = await api('storage/v1/object/steady-fictional', { method: 'DELETE', token: T('survivor'), body: { prefixes: [addOnlyPath] } });
    ok(o, 'object delete');
    const r = await api(`rest/v1/records?id=eq.${addOnlyRecord.id}`, { method: 'DELETE', token: T('survivor'), representation: true });
    ok(r, 'record delete'); assert.equal(r.json.length, 1); return r;
  });
}

// ---------------------------------------------------------------- check-ins and device tokens
let generalCheckIn;
await check('check-ins: caregiver adds general and symptom_break (no Edge Function needed); others cannot', async () => {
  const text = 'Fictional caregiver suggests a check-in.';
  const g = await api('rest/v1/check_ins', { method: 'POST', token: T('caregiver'), body: { circle_id: circle, sender_id: people.caregiver.id, body: text } });
  ok(g, 'general');
  const s = await api('rest/v1/check_ins', { method: 'POST', token: T('caregiver'), body: { circle_id: circle, sender_id: people.caregiver.id, category: 'symptom_break', body: 'Possible symptom, suggest a break.' } });
  ok(s, 'symptom_break');
  rejected(await api('rest/v1/check_ins', { method: 'POST', token: T('clinician'), body: { circle_id: circle, sender_id: people.clinician.id, body: 'Nope' } }), 'clinician');
  rejected(await api('rest/v1/check_ins', { method: 'POST', token: T('caregiver'), body: { circle_id: circle, sender_id: people.survivor.id, body: 'Spoof' } }), 'sender spoof');
  rejected(await api('rest/v1/check_ins', { method: 'POST', token: T('caregiver'), body: { circle_id: circle, sender_id: people.caregiver.id, category: 'other', body: 'Bad category' } }), 'bad category');
});
await check('check-ins: survivor sees both, clinician none, caregiver only own; only the survivor dismisses', async () => {
  const owner = await api(`rest/v1/check_ins?circle_id=eq.${circle}&order=created_at.desc&limit=25`, { token: T('survivor') });
  ok(owner); assert.ok(owner.json.length >= 2); generalCheckIn = owner.json[0].id;
  emptyRows(await api(`rest/v1/check_ins?circle_id=eq.${circle}`, { token: T('clinician') }), 'clinician');
  const own = await api(`rest/v1/check_ins?circle_id=eq.${circle}`, { token: T('caregiver') });
  ok(own); assert.equal(own.json.length, owner.json.length);
  emptyRows(await api(`rest/v1/check_ins?id=eq.${generalCheckIn}`, { method: 'DELETE', token: T('caregiver'), representation: true }), 'caregiver dismiss');
  const del = await api(`rest/v1/check_ins?id=eq.${generalCheckIn}`, { method: 'DELETE', token: T('survivor'), representation: true });
  ok(del); assert.equal(del.json.length, 1);
});
await check('device_tokens: own rows only, upsert via on_conflict, no cross-user read or write', async () => {
  const hex = randomBytes(32).toString('hex');
  const put = () => api('rest/v1/device_tokens?on_conflict=user_id,token', { method: 'POST', token: T('survivor'), prefer: 'resolution=merge-duplicates,return=minimal', body: { user_id: people.survivor.id, token: hex, platform: 'ios', environment: 'sandbox' } });
  ok(await put(), 'first upsert'); ok(await put(), 'repeat upsert');
  const mine = await api('rest/v1/device_tokens?select=user_id,token', { token: T('survivor') });
  ok(mine); assert.equal(mine.json.length, 1);
  emptyRows(await api('rest/v1/device_tokens?select=token', { token: T('caregiver') }), 'caregiver read');
  rejected(await api('rest/v1/device_tokens', { method: 'POST', token: T('caregiver'), body: { user_id: people.survivor.id, token: randomBytes(16).toString('hex') } }), 'insert for another user');
  emptyRows(await api(`rest/v1/device_tokens?user_id=eq.${people.survivor.id}`, { method: 'DELETE', token: T('caregiver'), representation: true }), 'caregiver delete');
  rejected(await api('rest/v1/device_tokens?select=token', { token: anon }), 'anon read');
});

// ---------------------------------------------------------------- revoke and re-invite
await check('revoking a member removes access and cancels their pending invitations', async () => {
  const removed = await api(`rest/v1/circle_members?circle_id=eq.${circle}&user_id=eq.${people.caregiver.id}`, { method: 'DELETE', token: T('caregiver'), representation: true });
  emptyRows(removed, 'member cannot remove themselves via API');
  const del = await api(`rest/v1/circle_members?circle_id=eq.${circle}&user_id=eq.${people.caregiver.id}`, { method: 'DELETE', token: T('survivor'), representation: true });
  ok(del); assert.equal(del.json.length, 1);
  const role = await rpc('my_role', T('caregiver'), { c: circle }); assert.equal(role.json, null);
  emptyRows(await records('caregiver'), 'records after removal');
  rejected(await newRecord('caregiver', 'observations', 'After removal'), 'add after removal');
  rejected(await rpc('accept_invite', T('caregiver'), { token: pendingCaregiverToken }), 'pending invite cancelled');
  rejected(await rpc('accept_invite', T('caregiver'), { token: caregiverToken }), 'old token replay');
});
await check('re-invite after removal works and restores the caregiver role', async () => {
  const t = await rpc('invite_member', T('survivor'), { c: circle, email: people.caregiver.email, r: 'caregiver' });
  ok(t);
  const r = await rpc('accept_invite', T('caregiver'), { token: t.json });
  ok(r); assert.equal(r.json, circle);
  const role = await rpc('my_role', T('caregiver'), { c: circle }); assert.equal(role.json, 'caregiver');
  ok(await newRecord('caregiver', 'observations', 'Fictional back again'), 'add after re-invite');
});
await check('a token refresh and sign-out work against the auth endpoints CloudClient uses', async () => {
  const s = await api('auth/v1/token?grant_type=password', { method: 'POST', body: { email: people.outsider.email, password } });
  ok(s);
  const refreshed = await api('auth/v1/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: s.json.refresh_token } });
  ok(refreshed); assert.ok(refreshed.json.access_token && refreshed.json.user?.id && refreshed.json.expires_at);
  ok(await api('auth/v1/logout?scope=local', { method: 'POST', token: refreshed.json.access_token }), 'logout');
});

// ---------------------------------------------------------------- cleanup and summary
for (const name of Object.keys(people)) {
  try { await api(`auth/v1/admin/users/${people[name].id}`, { method: 'DELETE', key: service, token: service }); } catch { /* best effort */ }
}
const status = failed === 0 ? 'PASS' : 'FAIL';
console.log(`LIVE_STACK_SUMMARY: ${status} passed=${passed} failed=${failed}`);
process.exit(failed === 0 ? 0 : 1);
