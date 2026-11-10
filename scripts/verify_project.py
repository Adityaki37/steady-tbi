"""Portable structural checks. This does NOT compile Swift or run an iOS app."""
from pathlib import Path
import json
import plistlib
import re
import struct
import xml.etree.ElementTree as ET
import hashlib

ROOT=Path(__file__).resolve().parents[1]
checks=[]
def require(condition, label):
    if not condition: raise AssertionError(label)
    checks.append(label)

pbx=(ROOT/'Steady.xcodeproj/project.pbxproj').read_text()
definitions=re.findall(r'^([A-F0-9]{24}) = \{',pbx,re.M)
require(len(definitions)==len(set(definitions)), 'Unique Xcode object identifiers')
references=set(re.findall(r'\b[A-F0-9]{24}\b',pbx))
require(references==set(definitions), 'All Xcode object references resolve')
require(pbx.count('productType = "com.apple.product-type.application"')==1 and pbx.count('isa = PBXNativeTarget;')==2, 'One iOS app target and one app-hosted regression test target')
require('XCLocalSwiftPackageReference' in pbx and 'productName = SteadyCore' in pbx, 'Local Swift package linked')
for file in ['SteadyApp.swift','AppStore.swift','ContentView.swift','CloudClient.swift','AccountView.swift']:
    require((ROOT/'Steady'/file).is_file() and f'path = {file};' in pbx, f'Swift source exists and is referenced: {file}')
scheme=ET.parse(ROOT/'Steady.xcodeproj/xcshareddata/xcschemes/Steady.xcscheme')
require(scheme.getroot().tag=='Scheme', 'Shared Xcode scheme is well-formed XML')
require('IPHONEOS_DEPLOYMENT_TARGET = 17.0' in pbx, 'iOS deployment target is 17.0')
entitlements_path=ROOT/'Steady/Steady.entitlements'
require(entitlements_path.is_file(), 'Push entitlements file exists')
entitlements=plistlib.loads(entitlements_path.read_bytes())
require(entitlements.get('aps-environment')=='development', 'APNs entitlement declares development aps-environment (free/dev, not a provisioned paid capability)')
require('CODE_SIGN_ENTITLEMENTS' not in pbx, 'Push entitlement is opt-in: default build signs with a free Personal Team')
require('INFOPLIST_KEY_UIBackgroundModes = "remote-notification";' in pbx and pbx.count('INFOPLIST_KEY_UIBackgroundModes = "remote-notification";')==2, 'Both app configs declare the remote-notification background mode')
for file in (ROOT/'Steady/Assets.xcassets').rglob('Contents.json'):
    obj=json.loads(file.read_text()); require(obj.get('info',{}).get('version')==1, f'Valid asset manifest: {file.parent.name}')
folder_refs=re.findall(r'lastKnownFileType = folder; path = ([^;]+);',pbx)
require(folder_refs and 'Resources' not in folder_refs, 'No top-level bundle folder reference is named Resources (breaks iOS codesign/install)')
require(not (ROOT/'Steady/Resources').exists(), 'No Steady/Resources directory')
config=plistlib.loads((ROOT/'Steady/SteadyResources/Backend.example.plist').read_bytes())
require(set(config)=={'SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY'}, 'Only public client config keys in template')
require(not (ROOT/'Steady/SteadyResources/Backend.local.plist').exists(), 'No configured hosted backend in deliverable')
image=ROOT/'Steady/SteadyResources/Fictional-brain-MRI.png'
raw=image.read_bytes()
require(raw[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',raw[16:24])==(1200,1400), 'Fictional MRI PNG has expected format and dimensions')
sql=(ROOT/'backend/schema.sql').read_text()
tables=re.findall(r'create table public\.(\w+)',sql)
require(len(tables)==7,'Seven backend tables declared')
for table in tables: require(f'alter table public.{table} enable row level security;' in sql,f'RLS enabled: {table}')
require("with check(private.allowed(circle_id,kind,'edit'))" in sql, 'UPDATE has a WITH CHECK authorization clause')
require('user_metadata' not in sql.replace('-- never user_metadata or a client-selected role.',''), 'No user-editable metadata authorization')
require("false,15728640,array" in sql, 'Private storage bucket has a 15 MB limit')
migrations=list((ROOT/'supabase/migrations').glob('*_steady_initial.sql'))
require(len(migrations)==1 and migrations[0].read_bytes()==(ROOT/'backend/schema.sql').read_bytes(), 'CLI-created migration matches schema source exactly')
require((ROOT/'Tests/DemoRepositoryTests.swift').read_text().count('func test')==7,'Seven core Swift tests supplied (not executed here)')
digest=hashlib.sha256((ROOT/'backend/schema.sql').read_bytes()).hexdigest()
result={'status':'PASS','checks':len(checks),'details':checks,'schemaSHA256':digest,'scope':'Structural source/project/asset checks only. Not Swift compilation, XCTest execution, or device validation.'}
(ROOT/'Validation').mkdir(exist_ok=True)
(ROOT/'Validation/source-results.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'PASS: {len(checks)} portable structural checks; no Swift/Xcode compile claimed.')
