#!/usr/bin/env python3
"""Cycle explicitly selected apps while observing QuietStart; never stop QuietStart.

Run separately from UI automation/recording so concurrent UiTest clients do not
contaminate the result. Cold starts force-stop only the selected native app.
Raw diagnostics stay in the supplied output directory, not public fixtures.
"""
import argparse,json,pathlib,re,subprocess,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--serial',required=True);p.add_argument('--out',required=True)
p.add_argument('--apps',nargs='+',required=True);p.add_argument('--rounds',type=int,default=30)
p.add_argument('--dwell',type=float,default=8);p.add_argument('--cold',action='store_true')
p.add_argument('--hdc',default='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
a=p.parse_args();own='com.tonghongxiang.quietstart'
if not 1<=a.rounds<=300 or not 3<=a.dwell<=60 or any(not re.fullmatch(r'[A-Za-z][\w]*(\.[\w]+)+',b) or b==own for b in a.apps):p.error('Invalid apps/count/dwell')
h=[a.hdc,'-t',a.serial,'shell'];d=f'/data/app/el2/100/base/{own}/files/'
o=pathlib.Path(a.out);o.mkdir(parents=True,exist_ok=False)
def sh(c):
 r=subprocess.run(h+[c],capture_output=True,text=True,timeout=15)
 if r.returncode:raise RuntimeError(r.stderr or r.stdout)
 return r.stdout.strip()
def health():
 raw=sh('cat '+d+'worker-health.txt').split()
 if len(raw)!=9:raise RuntimeError('Invalid health record')
 return {'token':raw[0],'pid':int(raw[1]),'heartbeat':int(raw[2]),'rpc':int(raw[4]),'mode':raw[5],'operation':raw[6]}
commands={};native=set()
for b in a.apps:
 raw=sh('bm dump -n '+b)
 try:
  info=json.loads(raw[raw.index('{'):]);mods=info['hapModuleInfos'];entries=[]
  for m in mods:
   for v in m.get('abilityInfos',[]):
    if v.get('visible') and v.get('enabled') and v.get('type')==1 and v['name']==(m.get('mainElementName') or m.get('mainAbility')):
     if m['moduleName']==info['entryModuleName']:entries.append((m['moduleName'],v['name']))
  if len(entries)!=1:raise ValueError('Ambiguous native entry')
  mod,ability=entries[0]
  if not all(re.fullmatch(r'[A-Za-z0-9_.]+',s) for s in [mod,ability]):raise ValueError('Invalid entry')
  commands[b]=f'aa start -b {b} -m {mod} -a {ability}';native.add(b)
 except (ValueError,KeyError):commands[b]=f'aa start -b {b} -A action.system.home -e entity.system.home'
initial=health();rows=[]
(o/'scope.json').write_text(json.dumps({'apps':a.apps,'rounds':a.rounds,'dwell':a.dwell,'cold':a.cold,'commands':commands,'initialToken':initial['token']},ensure_ascii=False,indent=2))
logfile=(o/'system.log').open('w')
log=subprocess.Popen(h+['hilog -v epoch -e "quietstart|QuietStart|LowMemoryKill|PROCESS_KILL|AAMS|UITEST"'],stdout=logfile,stderr=subprocess.STDOUT)
try:
 for i in range(a.rounds):
  b=a.apps[i%len(a.apps)];before=health()
  if before['token']!=initial['token']:raise RuntimeError('Session replaced; results are not comparable')
  if a.cold and b in native:sh('aa force-stop '+b);time.sleep(.5)
  started=int(time.time()*1000);result=sh(commands[b]);time.sleep(a.dwell)
  after=health();status=json.loads(sh('cat '+d+'debug-status.json'))
  pid=after['pid'];proc=sh(f'cat /proc/{pid}/status; cat /proc/{pid}/oom_score_adj')
  (o/f'process-{i+1}.txt').write_text(proc)
  (o/f'status-{i+1}.json').write_text(json.dumps(status,ensure_ascii=False))
  r={'round':i+1,'at':started,'bundle':b,'cold':a.cold and b in native,'launch':result,
     'arrived':status.get('lastBundle')==b,'health':after,'supervisor':sh('cat /data/local/tmp/quietstart-supervisor/status.txt'),
     'events':[e for e in status.get('history',[]) if e.get('at',0)>=started and e.get('bundle')==b]}
  rows.append(r);(o/'rounds.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2));print(json.dumps(r,ensure_ascii=False),flush=True)
finally:
 for f in ['worker-failures.json','system-exits.json','system-fault-events.json','worker-health.txt']:
  try:(o/f).write_text(sh('cat '+d+f))
  except Exception:pass
 log.terminate();log.wait(timeout=5);logfile.close()
