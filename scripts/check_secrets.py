"""Check only this project's tracked deliverables, never ambient credentials."""
from pathlib import Path
import re
import subprocess
import json
ROOT=Path(__file__).resolve().parents[1]
names=subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
patterns=[r'gh[pousr]_[A-Za-z0-9]{30,}',r'github_pat_[A-Za-z0-9_]{30,}',r'sb_secret_[A-Za-z0-9_-]{20,}',r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',r'eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}']
failures=[]; count=0
for name in names:
    if not name: continue
    path=ROOT/name
    if path.suffix.lower() in ['.png','.jpg','.jpeg']: continue
    text=path.read_text(encoding='utf-8'); count+=1
    if any(re.search(pattern,text) for pattern in patterns): failures.append(name)
    if 'node_modules/' in name or '.validation-python/' in name or name.endswith('Backend.local.plist') or (path.name.startswith('.env') and path.name!='.env.example'): failures.append(name)
result={'status':'FAIL' if failures else 'PASS','trackedTextFilesScanned':count,'flaggedFiles':failures,'scope':'Known token/private-key patterns and excluded-path checks; not a guarantee against every possible secret format.'}
(ROOT/'Validation/credential-scan-results.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2)); raise SystemExit(bool(failures))
