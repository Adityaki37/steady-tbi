// Read-only HTTP checks; never creates accounts or changes shared records.
import assert from 'node:assert/strict';

const base = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_PUBLISHABLE_KEY;
assert.ok(base?.startsWith('https://') && key?.startsWith('sb_publishable_'),
  'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY to public client configuration.');
const cases = [
  ['Auth is reachable', 'auth/v1/settings', undefined, 200],
  ['Journal rejects unsigned reads', 'rest/v1/records?select=id', undefined, 401],
  ['Signup quota rejects unsigned callers', 'rest/v1/rpc/reserve_demo_signup', {}, 401],
  ['Demo signup rejects invalid input', 'functions/v1/demo-signup', { username: '!', password: 'short', role: 'survivor' }, 400],
];
for (const [label, path, body, expected] of cases) {
  const response = await fetch(new URL(path, base.replace(/\/?$/, '/')), {
    method: body === undefined ? 'GET' : 'POST',
    headers: { apikey: key, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(20_000),
  });
  await response.arrayBuffer();
  assert.equal(response.status, expected, `${label}: HTTP ${response.status}`);
  console.log(`PASS: ${label} (HTTP ${response.status})`);
}
