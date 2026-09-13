"""Validate and embed the signed worker before building the sole delivery HAP."""
import hashlib, json, pathlib, re, shutil, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
worker = root / 'entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap'
raw = root / 'entry/src/main/resources/rawfile'
app_text = (root / 'AppScope/app.json5').read_text()
bundle = re.search(r'"bundleName"\s*:\s*"([^"]+)"', app_text)[1]
version = int(re.search(r'"versionCode"\s*:\s*(\d+)', app_text)[1])
with zipfile.ZipFile(worker) as z:
    data = json.loads(z.read('module.json'))
    if data['app']['bundleName'] != bundle or data['app']['versionCode'] != version or data['module']['name'] != 'entry_test':
        raise SystemExit('Worker bundle/module/version mismatch; rebuild with the same signing configuration.')
    if any(n.endswith(('quietstart-worker.hap', 'quietstart-worker.json')) for n in z.namelist()):
        raise SystemExit('Recursive embedded worker detected. Remove generated rawfiles before building the worker.')
content = worker.read_bytes()
if not 1024 <= len(content) <= 16777216:
    raise SystemExit('Worker size outside supported range.')
raw.mkdir(parents=True, exist_ok=True)
shutil.copyfile(worker, raw / 'quietstart-worker.hap')
manifest = dict(bundleName=bundle, moduleName='entry_test', versionCode=version,
                sha256=hashlib.sha256(content).hexdigest(), size=len(content))
(raw / 'quietstart-worker.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Embedded worker:', version, len(content), 'bytes')
