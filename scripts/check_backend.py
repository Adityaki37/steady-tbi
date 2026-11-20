"""Verify the shared project's configuration and immutable migration baseline."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
baseline = json.loads((ROOT / 'backend/migration-baseline.json').read_text())
directory = ROOT / 'supabase/migrations'
files = sorted(directory.glob('*.sql'))
versions = []
for path in files:
    match = re.fullmatch(r'(\d{14})_[a-z0-9_]+\.sql', path.name)
    if not match:
        raise SystemExit(f'Invalid migration filename: {path.name}')
    versions.append(match.group(1))
if len(versions) != len(set(versions)):
    raise SystemExit('Duplicate migration versions; create a new CLI migration timestamp.')
for entry in baseline['migrations']:
    path = directory / entry['file']
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        raise SystemExit(f'Applied migration was removed or edited: {entry["file"]}. Add a new migration instead.')
baseline_versions = {entry['file'].split('_')[0] for entry in baseline['migrations']}
if any(v not in baseline_versions and v <= max(baseline_versions) for v in versions):
    raise SystemExit('New migrations must follow the applied baseline.')
config = plistlib.loads((ROOT / 'Steady/SteadyResources/Backend.demo.plist').read_bytes())
if set(config) != {'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY'}:
    raise SystemExit('The bundled configuration must contain only public client settings.')
url = urlparse(config['SUPABASE_URL'])
if url.scheme != 'https' or url.hostname != baseline['project_ref'] + '.supabase.co':
    raise SystemExit('The bundled demo must target the verified Steady Demo project.')
if not config['SUPABASE_PUBLISHABLE_KEY'].startswith('sb_publishable_'):
    raise SystemExit('The app requires a publishable key, never an admin key.')
initial = next(directory.glob('*_steady_initial.sql'))
if initial.read_bytes() != (ROOT / 'backend/schema.sql').read_bytes():
    raise SystemExit('backend/schema.sql must match the original migration; later changes belong in new migrations.')
print(f'PASS: {len(baseline_versions)} applied migrations unchanged; {len(files)} migration files; hosted client configuration verified.')
