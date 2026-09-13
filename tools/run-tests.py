"""Run offline tests; opt into downloaded community fixtures explicitly."""
import os, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]
community = '--community' in sys.argv
ide = pathlib.Path(os.environ.get('DEVECO_APP', '/Applications/DevEco-Studio.app'))
node = ide / 'Contents/tools/node/bin/node'
files = sorted(str(p.relative_to(root)) for p in (root/'tests').glob('*.test.cjs') if community or not p.name.startswith('community-'))
if not node.exists(): sys.exit('Install DevEco Studio or set DEVECO_APP (macOS layout required).')
if community:
    missing = [p.stem.replace('.meta','') for p in (root/'tests/fixtures/community').glob('*.meta.json') if not p.with_name(p.name.replace('.meta.json','.json')).exists()]
    if missing: sys.exit('Run python3 tools/community/fetch-reviewed.py first. Missing: '+', '.join(missing))
sys.exit(subprocess.call([str(node), '--test', *files], cwd=root))
