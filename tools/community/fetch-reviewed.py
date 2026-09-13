"""Explicitly fetch reviewed snapshot bytes; never update the source manifest."""
import hashlib, io, json, pathlib, urllib.request, zipfile
root = pathlib.Path(__file__).resolve().parents[2] / 'tests/fixtures/community'
for meta_path in sorted(root.glob('*.meta.json')):
    meta = json.loads(meta_path.read_text())
    url = meta['url']
    if not url.startswith('https://github.com/user-attachments/files/'):
        raise ValueError('Unexpected source: '+meta_path.name)
    with urllib.request.urlopen(url, timeout=30) as response:
        archive = response.read(12*1024*1024+1)
    if len(archive)>12*1024*1024: raise ValueError('Archive too large')
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        names=[n for n in z.namelist() if n.endswith('.json') and not n.startswith('__MACOSX/')]
        if len(names)!=1 or z.getinfo(names[0]).file_size>8*1024*1024: raise ValueError('Unexpected archive')
        raw=z.read(names[0])
    if hashlib.sha256(raw).hexdigest()!=meta['sha256']: raise ValueError('Source hash changed: '+meta_path.name)
    json.loads(raw)
    dest=meta_path.with_name(meta_path.name.replace('.meta.json','.json'))
    tmp=dest.with_suffix('.tmp'); tmp.write_bytes(raw); tmp.replace(dest)
    print('Verified',dest.name)
