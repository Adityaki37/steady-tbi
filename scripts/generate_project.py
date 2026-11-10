"""Deterministic Xcode project + visibly fictional artwork. Requires Pillow only
to regenerate PNGs. Running/building the supplied Xcode project needs no Python.
"""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'Steady'
PROJECT = ROOT / 'Steady.xcodeproj'

def ident(label): return hashlib.sha1(label.encode()).hexdigest()[:24].upper()
def font(size, bold=False):
    paths = [Path('C:/Windows/Fonts/' + ('arialbd.ttf' if bold else 'arial.ttf')), Path('/System/Library/Fonts/Supplemental/Arial.ttf')]
    for path in paths:
        if path.exists(): return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)

resources = APP / 'SteadyResources'; resources.mkdir(parents=True, exist_ok=True)
image = Image.new('RGB', (1200, 1400), '#10151c'); d = ImageDraw.Draw(image)
d.text((70, 55), 'FICTIONAL BRAIN MRI', font=font(62, True), fill='#e5eff0')
d.text((70, 138), 'SYNTHETIC ILLUSTRATION / DEMO ONLY', font=font(31, True), fill='#92c4b8')
# Abstract symmetrical shapes, deliberately not a patient scan or medical model.
d.ellipse((190, 270, 1010, 1110), fill='#c8ced0', outline='#f0f2f3', width=10)
d.ellipse((212, 292, 988, 1088), fill='#252b32')
for side in (-1, 1):
    cx = 600 + side * 170
    d.ellipse((cx-182, 350, cx+182, 1000), fill='#8e989e', outline='#c4cbd0', width=9)
    for i in range(9):
        y = 390 + i*65
        points = [(int(cx+math.sin(t/7+i)*105), y+t*2) for t in range(24)]
        d.line(points, fill='#555f68', width=15)
d.line((600, 352, 600, 1010), fill='#263039', width=15)
d.ellipse((530, 590, 588, 785), fill='#242d34'); d.ellipse((612, 590, 670, 785), fill='#242d34')
d.rounded_rectangle((170, 640, 1030, 770), radius=20, fill='#183e39')
d.text((260, 670), 'NOT A PATIENT SCAN', font=font(49, True), fill='#ffffff')
d.text((70, 1170), 'No diagnostic use. No scan interpretation.', font=font(38, True), fill='#ffffff')
d.text((70, 1230), 'Made for Steady attachment preview testing.', font=font(31), fill='#c4d1d5')
d.text((70, 1290), 'This is code-drawn fictional artwork.', font=font(28), fill='#92c4b8')
image.save(resources / 'Fictional-brain-MRI.png')

assets = APP / 'Assets.xcassets'; assets.mkdir(exist_ok=True)
(assets / 'Contents.json').write_text(json.dumps({'info': {'author':'xcode','version':1}},indent=2)+'\n')
iconset = assets / 'AppIcon.appiconset'; iconset.mkdir(exist_ok=True)
icon = Image.new('RGB', (1024,1024), '#18584d'); pen=ImageDraw.Draw(icon)
pen.ellipse((245,180,790,760), fill='#e7f0de')
pen.polygon([(240,180),(240,670),(800,180)], fill='#18584d')
pen.line((290,800,690,340), fill='#18584d',width=38)
pen.line((290,800,690,340), fill='#e7f0de',width=16)
icon.save(iconset / 'AppIcon.png')
(iconset/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
accent=assets/'AccentColor.colorset'; accent.mkdir(exist_ok=True)
(accent/'Contents.json').write_text(json.dumps({'colors':[
    {'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.094','green':'0.345','blue':'0.302','alpha':'1.000'}}},
    {'idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}],'color':{'color-space':'srgb','components':{'red':'0.573','green':'0.835','blue':'0.761','alpha':'1.000'}}}
],'info':{'author':'xcode','version':1}},indent=2)+'\n')

sources = ['SteadyApp.swift','AppStore.swift','ContentView.swift','CloudClient.swift','AccountView.swift']
objects={}
def obj(name, body):
    section = body.split('isa = ',1)[1].split(';',1)[0]
    objects.setdefault(section,[]).append(f'{ident(name)} = {{ {body} }};')
    return ident(name)
refs=[]; builds=[]
for source in sources:
    ref=obj('ref:'+source, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {source}; sourceTree = "<group>";')
    refs.append(ref); builds.append(obj('build:'+source, f'isa = PBXBuildFile; fileRef = {ref};'))
assetref=obj('assetref','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
resref=obj('resref','isa = PBXFileReference; lastKnownFileType = folder; path = SteadyResources; sourceTree = "<group>";')
assetbuild=obj('assetbuild',f'isa = PBXBuildFile; fileRef = {assetref};')
resbuild=obj('resbuild',f'isa = PBXBuildFile; fileRef = {resref};')
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Steady.app; sourceTree = BUILT_PRODUCTS_DIR;')
testproduct=obj('testproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SteadyAppTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
testref=obj('testref','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CloudClientTests.swift; sourceTree = "<group>";')
testbuild=obj('testbuild',f'isa = PBXBuildFile; fileRef = {testref};')
testgroup=obj('testgroup',f'isa = PBXGroup; children = ({testref},); path = AppTests; sourceTree = "<group>";')
appgroup=obj('appgroup',f'isa = PBXGroup; children = ({",".join(refs+[assetref,resref])},); path = Steady; sourceTree = "<group>";')
productgroup=obj('productgroup',f'isa = PBXGroup; children = ({product},{testproduct},); name = Products; sourceTree = "<group>";')
rootgroup=obj('rootgroup',f'isa = PBXGroup; children = ({appgroup},{testgroup},{productgroup},); sourceTree = "<group>";')
package=obj('package','isa = XCLocalSwiftPackageReference; relativePath = .;')
packageproduct=obj('packageproduct',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = SteadyCore;')
linkbuild=obj('linkbuild',f'isa = PBXBuildFile; productRef = {packageproduct};')
sourcephase=obj('sourcephase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resphase=obj('resphase',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assetbuild},{resbuild},); runOnlyForDeploymentPostprocessing = 0;')
frameworkphase=obj('frameworkphase',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({linkbuild},); runOnlyForDeploymentPostprocessing = 0;')

def config(name, settings): return obj(name, 'isa = XCBuildConfiguration; buildSettings = {' + settings + '}; name = ' + ('Debug' if 'debug' in name else 'Release') + ';')
projectcommon='CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; '
projectdebug=config('projectdebug',projectcommon+'DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_TESTABILITY = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;')
projectrelease=config('projectrelease',projectcommon+'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";')
targetcommon='''ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ""; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0;
GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = Steady;
INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES;
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
PRODUCT_BUNDLE_IDENTIFIER = com.aditya.steadydemo; PRODUCT_NAME = "$(TARGET_NAME)";
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; TARGETED_DEVICE_FAMILY = "1,2";
LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
'''
targetdebug=config('targetdebug',targetcommon)
targetrelease=config('targetrelease',targetcommon)
projectconfigs=obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({projectdebug},{projectrelease},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
targetconfigs=obj('targetconfigs',f'isa = XCConfigurationList; buildConfigurations = ({targetdebug},{targetrelease},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {targetconfigs}; buildPhases = ({sourcephase},{frameworkphase},{resphase},); buildRules = (); dependencies = (); name = Steady; packageProductDependencies = ({packageproduct},); productName = Steady; productReference = {product}; productType = "com.apple.product-type.application";')
testsourcephase=obj('testsourcephase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({testbuild},); runOnlyForDeploymentPostprocessing = 0;')
testframeworkphase=obj('testframeworkphase','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
testcommon='CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ""; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.aditya.steadydemo.tests; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = "1,2"; BUNDLE_LOADER = "$(TEST_HOST)"; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Steady.app/Steady";'
testdebug=config('testdebug',testcommon)
testrelease=config('testrelease',testcommon)
testconfigs=obj('testconfigs',f'isa = XCConfigurationList; buildConfigurations = ({testdebug},{testrelease},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
proxy=obj('testproxy',f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Steady;')
dependency=obj('testdependency',f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
testtarget=obj('testtarget',f'isa = PBXNativeTarget; buildConfigurationList = {testconfigs}; buildPhases = ({testsourcephase},{testframeworkphase},); buildRules = (); dependencies = ({dependency},); name = SteadyAppTests; productName = SteadyAppTests; productReference = {testproduct}; productType = "com.apple.product-type.bundle.unit-test";')
project=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; {testtarget} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {projectconfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {rootgroup}; packageReferences = ({package},); productRefGroup = {productgroup}; projectDirPath = ""; projectRoot = ""; targets = ({target},{testtarget},);')
PROJECT.mkdir(exist_ok=True)
sections='\n'.join(f'/* Begin {section} section */\n'+ '\n'.join(entries)+f'\n/* End {section} section */' for section,entries in sorted(objects.items()))
(PROJECT/'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n'+sections+f'\n}};\nrootObject = {project};\n}}\n')
scheme=PROJECT/'xcshareddata'/'xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
(scheme/'Steady.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Steady.app" BlueprintName="Steady" ReferencedContainer="container:Steady.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="SteadyAppTests.xctest" BlueprintName="SteadyAppTests" ReferencedContainer="container:Steady.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Steady.app" BlueprintName="Steady" ReferencedContainer="container:Steady.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Steady.app" BlueprintName="Steady" ReferencedContainer="container:Steady.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('Generated Steady.xcodeproj, shared scheme, assets and fictional illustration.')
