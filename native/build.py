from pathlib import Path
import argparse,plistlib,re,shutil,subprocess,sys
from urllib.parse import quote
root=Path(__file__).resolve().parents[1];web=root/'web';out=root/'out';out.mkdir(exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument('--html-only',action='store_true');args=parser.parse_args()
def strip(s):return re.sub(r'^import .*?;\s*','',s,flags=re.M).replace('export ','')
code='\n'.join(strip((web/name).read_text()) for name in ['core.js','school.js','edupage.js','app.js'])
html=(web/'index.html').read_text().replace('<link rel="stylesheet" href="./style.css">','<style>'+(web/'style.css').read_text()+'</style>').replace('<script type="module" src="./app.js"></script>','<script>'+code+'</script>')
html=re.sub(r'<link rel="manifest"[^>]*>','',html);html=html.replace('href="./icon.svg"','href="data:image/svg+xml,'+quote((web/'icon.svg').read_text())+'"');(out/'Orbit.html').write_text(html)
if args.html_only:print('Preview: out/Orbit.html');sys.exit(0)
if sys.platform!='darwin':raise SystemExit('Native build requires macOS; use --html-only for a browser preview.')
cache=root/'build/swift-cache';cache.mkdir(parents=True,exist_ok=True)
app=out/'Orbit.app';mac=app/'Contents/MacOS';res=app/'Contents/Resources';mac.mkdir(parents=True,exist_ok=True);res.mkdir(parents=True,exist_ok=True)
config=root/'native/Configuration.local.swift'
if not config.exists():config=root/'native/Configuration.example.swift'
subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(cache),'-O','-framework','AppKit','-framework','WebKit','-framework','Security','-framework','LocalAuthentication',str(root/'native/Orbit.swift'),str(config),'-o',str(mac/'Orbit')],check=True)
shutil.copyfile(out/'Orbit.html',res/'Orbit.html')
for name in ['edupage_sync.py','grade_reader.py','lesson_slots.py','Orbit.icns']:shutil.copyfile(root/'native'/name,res/name)
info={'CFBundleName':'Orbit','CFBundleDisplayName':'Orbit','CFBundleExecutable':'Orbit','CFBundleIdentifier':'org.orbit.school.public-template','CFBundlePackageType':'APPL','CFBundleShortVersionString':'4.3','CFBundleVersion':'4.3','CFBundleIconFile':'Orbit','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info));subprocess.run(['xattr','-cr',str(app)],check=True);subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
print('Built out/Orbit.app; local signature, without Apple notarization.')
