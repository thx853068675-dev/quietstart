#!/usr/bin/env python3
"""Real, bounded device memory pressure. Never signals the application under test.

Uses existing system dd processes to fill anonymous pipe-blocked buffers with
random data. Measures RSS (not just reservation). HAP/test-session unchanged.
Every slot exits on-device after <=300s even if the USB connection is lost.
"""
import argparse, json, pathlib, re, subprocess, time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--serial',required=True)
p.add_argument('--out',required=True)
p.add_argument('--max-mib',type=int,default=6144)
p.add_argument('--hdc',default='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
a=p.parse_args()
if not re.fullmatch(r'[A-Za-z0-9.:_-]+',a.serial) or a.max_mib not in (1024,2048,3072,4096,5120,6144): p.error('Invalid serial or ceiling')
h=[a.hdc,'-t',a.serial]
bundle='com.tonghongxiang.quietstart'
files=f'/data/app/el2/100/base/{bundle}/files/'
base='/data/local/tmp/quietstart-pressure/' + str(int(time.time()*1000))
out=pathlib.Path(a.out);out.mkdir(parents=True,exist_ok=False)
slots=[];events=[];start=time.monotonic(); logproc=None; logfile=None; original_pid=0

def shell(command,timeout=12):
 r=subprocess.run(h+['shell',command],capture_output=True,text=True,timeout=timeout)
 if r.returncode: raise RuntimeError(r.stderr or r.stdout)
 return r.stdout.strip()

def emit(event,**data):
 row={'at':int(time.time()*1000),'elapsed':round(time.monotonic()-start,1),'event':event,**data}
 events.append(row)
 with (out/'events.jsonl').open('a') as f:f.write(json.dumps(row,ensure_ascii=False)+'\n')
 print(json.dumps(row,ensure_ascii=False),flush=True)

def status(pid):
 if pid<=1:return {'alive':False,'rssKiB':0}
 raw=shell(f'cat /proc/{pid}/status')
 name=re.search(r'^Name:\s*(.*)',raw,re.M)
 return {'alive':bool(name),'name':name.group(1) if name else '',
  **{key:int(m.group(1)) if (m:=re.search(r'^'+field+r':\s*(\d+)',raw,re.M)) else 0
   for key,field in [('rssKiB','VmRSS'),('swapKiB','VmSwap')]}}

def snapshot():
 raw=shell('cat /proc/meminfo')
 mem={k:int(v) for k,v in re.findall(r'^(MemAvailable|MemFree|Cached|SwapFree|ZramUsed):\s*(\d+)',raw,re.M)}
 if 'MemAvailable' not in mem:raise RuntimeError('No memory safety telemetry')
 raw=shell('hidumper -s BatteryService -a -i')
 match=re.search(r'^temperature:\s*(\d+)',raw,re.M)
 if not match:raise RuntimeError('No temperature safety telemetry')
 battery=int(match.group(1))/10
 health=shell('cat '+files+'worker-health.txt').split()
 sup=shell('cat /data/local/tmp/quietstart-supervisor/status.txt').split()
 control=shell('cat '+files+'supervision-control.txt').split()
 if len(health)!=9 or len(sup)<5 or len(control)!=3:raise RuntimeError('Invalid health/control telemetry')
 pid=int(health[1]); spid=int(sup[1]); process=status(pid);supervisor=status(spid)
 oom=shell(f'cat /proc/{pid}/oom_score_adj') if process['alive'] else ''
 cgroup=shell(f'cat /proc/{pid}/cgroup') if process['alive'] else ''
 processes=[]
 for slot in slots:
  raw=shell(f'cat {slot}/pids').split()
  if len(raw)==3 and all(x.isdigit() for x in raw):
   item=status(int(raw[2]));item['pid']=int(raw[2]);processes.append(item)
 pressure_rss=sum(x['rssKiB'] for x in processes if x['name']=='dd')
 return {'memoryKiB':mem,'batteryC':battery,'token':health[0],'workerPid':pid,'worker':process,
  'heartbeatAge':int(time.time())-int(health[2]),'rpcAge':int(time.time())-int(health[4]) if int(health[4])>0 else None,
  'mode':health[5],'operation':health[6],'supervisorPid':spid,'supervisorAlive':supervisor['alive'],
  'supervisorState':sup[4],'attempt':int(sup[3]),'control':control[1],
  'workerOomAdj':int(oom) if re.fullmatch(r'-?\d+',oom) else None,'workerCgroup':cgroup,
  'pressureRssKiB':pressure_rss,'pressureProcesses':processes}

def add_slot():
 slot=base+'/slot'+str(len(slots)+1)
 shell('mkdir -p '+slot)
 # Slot script has strict path/size/lifetime validation, exits and cleans up by itself.
 shell('/bin/nohup /bin/sh /data/local/tmp/quietstart-pressure/slot.sh '+slot+' 512 300 </dev/null >'+slot+'/job.log 2>&1 &')
 slots.append(slot);emit('allocate',requestedMiB=len(slots)*512)

def release():
 for slot in slots:
  try:shell('echo stop > '+slot+'/stop',timeout=4)
  except Exception:pass
 emit('release-requested',slots=len(slots))

def capture(name):
 for key,path in [('supervisor','/data/local/tmp/quietstart-supervisor/supervisor-events.jsonl'),('exits',files+'system-exits.json'),('fault-events',files+'system-fault-events.json'),('worker-failures',files+'worker-failures.json')]:
  try:(out/(name+'-'+key+'.json')).write_text(shell('cat '+path)+'\n')
  except Exception:pass

try:
 initial=snapshot();original_pid=initial['workerPid']
 if initial['control']!='active' or not initial['worker']['alive'] or not initial['supervisorAlive'] or initial['rpcAge'] is None or initial['rpcAge']>15:
  raise RuntimeError('Need an existing healthy session; no automatic reactivation')
 if initial['batteryC']>=38 or initial['memoryKiB']['MemAvailable']<1536*1024:
  raise RuntimeError('Baseline too hot or too little available memory to start')
 # Copy only the reviewed test helper; no HAP changes or signing are needed.
 helper=pathlib.Path(__file__).with_name('memory-slot.sh')
 shell('mkdir -p /data/local/tmp/quietstart-pressure')
 subprocess.run(h+['file','send',str(helper),'/data/local/tmp/quietstart-pressure/slot.sh'],check=True,capture_output=True,text=True,timeout=20)
 if shell('cat /data/local/tmp/quietstart-pressure/slot.sh') != helper.read_text().strip():
  raise RuntimeError('Pressure helper did not transfer intact')
 # Read-only streaming. Preserve existing OS log buffers and settings.
 logfile=(out/'system.log').open('w')
 logproc=subprocess.Popen(h+['shell','hilog -v epoch -e "quietstart|LowMemoryKiller|MemoryManager|MemMgr|oom-kill|LowMem"'],stdout=logfile,stderr=subprocess.STDOUT)
 (out/'scope.json').write_text(json.dumps({'bundle':bundle,'serial':a.serial,'maxMiB':a.max_mib,'devicePath':base,
 'allocationStopMiB':1408,'hardReserveMiB':384,'batteryStopC':43,'slotLifetimeSeconds':300,
 'initialForegroundApp':'system launcher','manuallySignalQuietStart':False,'changeOomPolicy':False},indent=2))
 capture('before');shell('uitest uiInput keyEvent Home');emit('baseline',**initial)
 last_allocation=0; pressure_end=None; death_at=None
 # 230 seconds max pressure; allocation every 12 seconds. Auto lifetime is longer
 # than the test phase, but protects against a lost host/USB connection.
 while time.monotonic()-start<230:
  s=snapshot();emit('sample',**s)
  if s['token']!=initial['token']:raise RuntimeError('Session replaced externally; stop test')
  if s['batteryC']>=43 or s['memoryKiB']['MemAvailable']<384*1024:
   emit('safety-stop',reason='temperature' if s['batteryC']>=43 else 'memory-reserve');break
  if not s['worker']['alive'] or s['workerPid']!=original_pid or not s['supervisorAlive']:
   if death_at is None:death_at=time.monotonic();emit('process-change',originalWorkerPid=original_pid);capture('process-change')
   # Give the supervisor up to 60s under the same pressure. Do not intensify
   # further after a process change. Then release and observe another 120s.
   if time.monotonic()-death_at>60:break
  if death_at is None and pressure_end is None:
   if len(slots)*512<a.max_mib and time.monotonic()-last_allocation>=12 and s['memoryKiB']['MemAvailable']>1408*1024:
    add_slot();last_allocation=time.monotonic()
   elif len(slots)*512>=a.max_mib or s['memoryKiB']['MemAvailable']<=1408*1024:
    pressure_end=time.monotonic()+70;emit('hold',requestedMiB=len(slots)*512)
  if pressure_end and time.monotonic()>=pressure_end:break
  time.sleep(5)
 release();released=time.monotonic()
 while time.monotonic()-released<120:
  s=snapshot();emit('post-release',**s)
  if s['token']!=initial['token']:raise RuntimeError('Session replaced externally after pressure')
  time.sleep(5)
 capture('after')
 emit('result',originalWorkerPid=original_pid,finalWorkerPid=s['workerPid'],workerAlive=s['worker']['alive'],
  supervisorAlive=s['supervisorAlive'],control=s['control'],rpcAge=s['rpcAge'],pressureRssKiB=s['pressureRssKiB'])
finally:
 release()
 if logproc:
  logproc.terminate()
  try:logproc.wait(timeout=5)
  except subprocess.TimeoutExpired:logproc.kill()
 if logfile:logfile.close()
 for slot in slots:
  try:
   for name in ['dd.log','job.log','pids','done']:(out/(slot.rsplit('/',1)[-1]+'-'+name)).write_text(shell('cat '+slot+'/'+name))
  except Exception:pass
