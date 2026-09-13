"""Build a standalone source archive without local signing or device data."""
import hashlib, pathlib, re, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
TOP={'README.md','LICENSE','THIRD_PARTY_NOTICES.md','SECURITY.md','CONTRIBUTING.md','.gitignore','build-profile.example.json5','code-linter.json5','hvigorfile.ts','oh-package.json5','oh-package-lock.json5'}
DIRS={'AppScope','entry','hvigor','rules','scripts','tests','tools','docs'}
PUBLIC_DOCS={'ARCHITECTURE.md','BUILD.md','INSTALL.md','RESIGN.md','RELEASING.md','TESTING.md','USAGE.md',
             'share-to-users-guide.md','single-package-0.9.42.md','community-learning-0.9.40.md',
             'community-structural-before-0.9.40.json','community-structural-results-0.9.40.json'}
PUBLIC_SCREENSHOTS={'overview.jpeg','connection.jpeg','apps.jpeg','rules.jpeg','records.jpeg','settings.jpeg','preferences.jpeg'}
BLOCK={'build','oh_modules','node_modules','.hvigor','.idea','__pycache__','.git','dist','.cxx','.preview','.test'}
EXT={'.hap','.app','.pem','.key','.p12','.p7b','.cer','.csr','.jks','.keystore','.pyc','.zip','.log','.pfx'}
selected=[]
for p in sorted(ROOT.rglob('*')):
    rel=p.relative_to(ROOT)
    if not p.is_file() or p.is_symlink() or any((ROOT/pathlib.Path(*rel.parts[:i])).is_symlink() for i in range(1,len(rel.parts))):continue
    if any(x in BLOCK for x in rel.parts) or p.suffix in EXT or p.name in {'local.properties','.DS_Store','quietstart-worker.json'} or p.name.startswith('.env'):continue
    if len(rel.parts)==1 and p.name not in TOP:continue
    if len(rel.parts)>1 and rel.parts[0] not in DIRS:continue
    if rel.parts[0]=='docs':
        public_doc=len(rel.parts)==2 and p.name in PUBLIC_DOCS
        public_image=len(rel.parts)==3 and rel.parts[1]=='images' and p.name in PUBLIC_SCREENSHOTS
        if not (public_doc or public_image):continue
    if rel.parts[:3]==('tests','fixtures','community') and re.fullmatch(r'\d+\.json',p.name):continue
    raw=p.read_bytes()
    try:
        text=raw.decode('utf-8')
    except UnicodeDecodeError:
        text=None
    if text is not None:
        secret=re.search(r'-----BEGIN [A-Z ]*PRIVATE KEY-----|[\"\x27]?(?:storePassword|keyPassword)[\"\x27]?\s*:',text)
        personal=re.search(r'/Users/[A-Za-z0-9_.-]+/',text)
        if secret or personal:raise SystemExit('Review private data before exporting: '+str(rel))
    selected.append((rel,raw))
version=re.search(r'"versionName"\s*:\s*"([^"]+)"',(ROOT/'AppScope/app.json5').read_text())[1]
out=ROOT/'dist'/f'quietstart-source-{version}.zip';out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
    for rel,raw in selected:
        info=zipfile.ZipInfo('quietstart/'+rel.as_posix()); info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=((ROOT/rel).stat().st_mode & 0xFFFF)<<16
        z.writestr(info,raw)
print(f'{out}\nFiles: {len(selected)}; bytes: {out.stat().st_size}\nSHA256: {hashlib.sha256(out.read_bytes()).hexdigest()}')
