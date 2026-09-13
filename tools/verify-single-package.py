"""Reject stale main/worker combinations before distributing a single HAP."""
import hashlib, io, json, pathlib, sys, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
p = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root/'entry/build/default/outputs/default/entry-default-signed.hap'
with zipfile.ZipFile(p) as z:
    def item(suffix):
        matches = [n for n in z.namelist() if n.endswith('/' + suffix)]
        if len(matches) != 1: raise SystemExit('Missing/duplicate embedded resource: ' + suffix)
        return z.read(matches[0])
    app = json.loads(z.read('module.json'))
    manifest = json.loads(item('quietstart-worker.json'))
    worker = item('quietstart-worker.hap')
    if manifest['sha256'] != hashlib.sha256(worker).hexdigest() or manifest['size'] != len(worker):
        raise SystemExit('Embedded worker checksum mismatch')
    with zipfile.ZipFile(io.BytesIO(worker)) as w:
        module = json.loads(w.read('module.json'))
        if any(n.endswith('quietstart-worker.hap') for n in w.namelist()): raise SystemExit('Recursive worker payload')
    if not (app['app']['bundleName'] == module['app']['bundleName'] == manifest['bundleName'] and
            app['app']['versionCode'] == module['app']['versionCode'] == manifest['versionCode'] and
            module['module']['name'] == manifest['moduleName'] == 'entry_test'):
        raise SystemExit('Main and embedded worker bundle/version mismatch')
print('Single-package verified:', p.name, 'version', manifest['versionCode'])
