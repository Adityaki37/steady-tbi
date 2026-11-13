import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';

const base = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_PUBLISHABLE_KEY;
assert.ok(base && key?.startsWith('sb_publishable_'), 'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY');
const run = randomBytes(7).toString('hex');
const password = randomBytes(24).toString('base64url');
const roles = ['survivor', 'caregiver', 'clinician', 'new-survivor'];
const people = {};

async function api(path, { token, body, method = body === undefined ? 'GET' : 'POST', prefer = 'return=representation' } = {}) {
  const headers = { apikey: key, 'Content-Type': 'application/json', Prefer: prefer };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(`${base}/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const raw = await response.text();
  return { status: response.status, data: raw ? JSON.parse(raw) : null };
}

function expect(response, status, label) {
  assert.equal(response.status, status, `${label} returned HTTP ${response.status}`);
  return response.data;
}

const auth = role => ({ token: people[role].token });
const rpc = (role, name, body) => api(`rest/v1/rpc/${name}`, { ...auth(role), body });

for (const role of roles) {
  const username = `qa-${role}-${run}`;
  const email = `${username}@steady-demo.example`;
  const profileRole = role === 'new-survivor' ? 'survivor' : role;
  expect(await api('functions/v1/demo-signup', { body: { username, password, role: profileRole } }), 201, `${role} signup`);
  const session = expect(await api('auth/v1/token?grant_type=password', { body: { email, password } }), 200, `${role} sign-in`);
  assert.equal(session.user.user_metadata.steady_role, profileRole);
  people[role] = { token: session.access_token, id: session.user.id, username, email };
}
expect(await api('functions/v1/demo-signup', { body: { username: people.survivor.username, password, role: 'clinician' } }), 409, 'duplicate signup');
expect(await api('functions/v1/demo-signup', { body: { username: 'person@example.com', password, role: 'survivor' } }), 400, 'real email rejected');
for (const path of ['auth/v1/signup', 'rest/v1/rpc/reserve_demo_signup']) {
  const direct = await api(path, { body: path.startsWith('auth/') ? { email: `qa-direct-${run}@steady-demo.example`, password } : {} });
  assert.ok(direct.status >= 400, 'direct access is denied');
}
console.log('PASS: public signup and sign-in for all three demo roles');

const circle = expect(await rpc('survivor', 'create_circle', { n: 'Fictional QA circle' }), 200, 'create circle');
const entry = { id: randomUUID(), circle_id: circle, author_id: people.survivor.id, kind: 'symptoms', title: 'Fictional headache', severity: 2 };
expect(await api('rest/v1/records', { ...auth('survivor'), body: entry }), 201, 'create survivor journal entry');
const profile = {
  user_id: people.survivor.id, display_name: 'Fictional Alex', injury_description: 'Fictional concussion',
  symptoms: [{ id: randomUUID(), category: 'cognitive', name: 'Mental fatigue' }, { id: randomUUID(), category: 'balance', name: 'Dizziness' }]
};
expect(await api('rest/v1/survivor_profiles?on_conflict=user_id', {
  ...auth('survivor'), body: profile, prefer: 'resolution=merge-duplicates,return=minimal'
}), 201, 'save profile');
for (const role of ['caregiver', 'clinician']) {
  assert.deepEqual(expect(await api('rest/v1/circles?select=id', auth(role)), 200, 'pre-invitation circles'), []);
  const code = expect(await rpc('survivor', 'invite_member', { c: circle, email: people[role].email, r: role }), 200, 'create invitation');
  if (role === 'caregiver') expect(await rpc('clinician', 'accept_invite', { token: code }), 403, 'wrong user denied');
  assert.equal(expect(await rpc(role, 'accept_invite', { token: code }), 200, 'accept invitation'), circle);
  assert.equal(expect(await rpc(role, 'my_role', { c: circle }), 200, 'assigned circle role'), role);
  expect(await rpc(role, 'accept_invite', { token: code }), 403, 'invitation replay denied');
  const records = expect(await api(`rest/v1/records?id=eq.${entry.id}&select=title`, auth(role)), 200, 'journal read');
  assert.deepEqual(records, role === 'clinician' ? [{ title: entry.title }] : []);
  assert.deepEqual(expect(await rpc(role, 'shared_survivor_profile', { c: circle }), 200, 'profile private by default'), []);
  const member = `rest/v1/circle_members?circle_id=eq.${circle}&user_id=eq.${people[role].id}`;
  expect(await api(member, { ...auth('survivor'), method: 'PATCH', body: { shares_survivor_profile: true } }), 200, 'share profile');
  const [shared] = expect(await rpc(role, 'shared_survivor_profile', { c: circle }), 200, 'read shared profile');
  assert.deepEqual(shared.symptoms, profile.symptoms);
  assert.equal(shared.injury_description, profile.injury_description);
  assert.equal(shared.display_name, undefined);
  expect(await api(member, { ...auth('survivor'), method: 'PATCH', body: { shares_survivor_profile: false } }), 200, 'revoke profile');
  assert.deepEqual(expect(await rpc(role, 'shared_survivor_profile', { c: circle }), 200, 'revocation takes effect'), []);
}
console.log('PASS: recipient-bound invitations, journal permissions, profile sharing and revocation for both member roles');

const activity = { id: randomUUID(), user_id: people.survivor.id, activity: 'Fictional reading', started_at: new Date().toISOString(), duration_minutes: 20, fatigue: 3 };
expect(await api('rest/v1/activity_logs', { ...auth('survivor'), body: activity }), 201, 'save private activity');
for (const role of ['caregiver', 'clinician']) {
  assert.deepEqual(expect(await api(`rest/v1/activity_logs?id=eq.${activity.id}`, auth(role)), 200, 'member cannot see activity'), []);
}
console.log('PASS: activity entries remain private');

const survivorProfile = 'rest/v1/survivor_profiles?select=display_name,symptoms';
expect(await api('auth/v1/logout?scope=local', { ...auth('survivor'), method: 'POST' }), 204, 'survivor sign-out');
assert.deepEqual(expect(await api(survivorProfile, auth('new-survivor')), 200, 'new survivor starts without a profile'), []);
assert.deepEqual(expect(await api('rest/v1/circles?select=id', auth('new-survivor')), 200, 'new survivor starts without a circle'), []);
const returning = expect(await api('auth/v1/token?grant_type=password', {
  body: { email: people.survivor.email, password }
}), 200, 'sign back in');
assert.equal(returning.user.id, people.survivor.id);
people.survivor.token = returning.access_token;
assert.deepEqual(expect(await api(survivorProfile, auth('survivor')), 200, 'returning survivor profile'), [
  { display_name: profile.display_name, symptoms: profile.symptoms }
]);
assert.deepEqual(expect(await api('rest/v1/circles?select=id', auth('survivor')), 200, 'returning survivor circle'), [{ id: circle }]);
console.log('PASS: a new survivor starts fresh and a returning survivor keeps their saved setup');

for (const role of roles) {
  expect(await api('auth/v1/logout?scope=local', { ...auth(role), method: 'POST' }), 204, `${role} sign-out`);
}
// Report only the synthetic account IDs so an operator can remove exactly these test rows.
console.log('QA_IDS=' + JSON.stringify(roles.map(role => people[role].id)));
