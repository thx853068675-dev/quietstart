// Runs only in the phone's authorized local HDC shell.
export const SUPERVISOR_PROGRAM: string = String.raw`#!/bin/sh
set -u
B=com.tonghongxiang.quietstart
BASE=/data/local/tmp/quietstart-supervisor
TOKEN=$1
case "$TOKEN" in *[!0-9]*|'') exit 2;; esac
[ "$(echo -n "$TOKEN" | wc -c)" -ge 13 ] || exit 2
ACCOUNT=$2
case "$ACCOUNT" in *[!0-9]*|'') exit 2;; esac
FILES=/data/app/el2/$ACCOUNT/base/$B/files
[ -r "$FILES/supervision-control.txt" ] || exit 3
control() {
  read ct cm ca < "$FILES/supervision-control.txt" 2>/dev/null || return 1
  [ "$ct" = "$TOKEN" ] && [ "$cm" = active ]
}
pause() {
  left=$1
  while [ "$left" -gt 0 ]; do
    control || return 1
    step=$left; [ "$step" -le 5 ] || step=5
    sleep "$step"; left=$((left-step))
  done
  control
}
attempts=0
retry_streak=0
healthy_since=0
last_state=
hp=0; hb=0; rpc=0; operation=initializing
command=none; command_rc=0
journal() {
  # One shell writer. Publish atomically, bound size, and allow the app UID
  # to read diagnostics inside its own sandbox (the shell has another UID).
  local stamp peers q heartbeat_ms rpc_ms
  stamp=$(date +%s)
  heartbeat_ms=0; rpc_ms=0
  [ "$hb" -le 0 ] || heartbeat_ms="$hb"000
  [ "$rpc" -le 0 ] || rpc_ms="$rpc"000
  peers=
  for q in $(pidof uitest 2>/dev/null); do
    if cat "/proc/$q/cmdline" 2>/dev/null | grep -zF "$B@$hp@" >/dev/null; then
      [ -z "$peers" ] || peers="$peers,"
      peers="$peers$q"
    fi
  done
  tail -n 119 "$BASE/supervisor-events.jsonl" > "$BASE/supervisor-events.tmp" 2>/dev/null || true
  printf '{"token":"%s","at":%s000,"supervisorPid":%s,"attempt":%s,"state":"%s","cause":"%s","workerPid":%s,"uiTestPids":"%s","heartbeatAt":%s,"rpcAt":%s,"operation":"%s","command":"%s","exitCode":%s}\n' "$TOKEN" "$stamp" "$$" "$attempts" "$state" "$cause" "$hp" "$peers" "$heartbeat_ms" "$rpc_ms" "$operation" "$command" "$command_rc" >> "$BASE/supervisor-events.tmp"
  chmod 644 "$BASE/supervisor-events.tmp"
  mv "$BASE/supervisor-events.tmp" "$BASE/supervisor-events.jsonl"
}
stop_for_restart() {
  local p stamp
  stamp=$(date +%s)
  rm -f "$BASE/supervisor-stop-intent.json"
  for p in $(pidof "$B" 2>/dev/null); do
    printf '{"token":"%s","pid":%s,"at":%s000,"attempt":%s}\n' "$TOKEN" "$p" "$stamp" "$attempts" > "$BASE/supervisor-stop-intent.tmp"
    chmod 644 "$BASE/supervisor-stop-intent.tmp"
    mv "$BASE/supervisor-stop-intent.tmp" "$BASE/supervisor-stop-intent.json"
    break
  done
  control || return 1
  /bin/timeout 10 aa force-stop "$B" >/dev/null 2>&1
  command_rc=$?
  if [ "$command_rc" -eq 0 ] && [ -f "$BASE/supervisor-stop-intent.json" ]; then
    sed 's/}$/,"completed":true}/' "$BASE/supervisor-stop-intent.json" > "$BASE/supervisor-stop-intent.tmp"
    chmod 644 "$BASE/supervisor-stop-intent.tmp"
    mv "$BASE/supervisor-stop-intent.tmp" "$BASE/supervisor-stop-intent.json"
  fi
  command=force-stop; state=command-result; journal; command=none
  [ "$command_rc" -eq 0 ]
}
status() {
  state=$1
  now=$(date +%s)
  printf '%s %s %s %s %s %s\n' "$TOKEN" "$$" "$now" "$attempts" "$state" "$cause" > "$BASE/status.tmp"
  mv "$BASE/status.tmp" "$BASE/status.txt"
  if [ "$state" != "$last_state" ]; then echo "$now $state attempt=$attempts cause=$cause"; journal; last_state=$state; fi
}
cause=initial
i=0
while ! mkdir "$BASE/run.lock" 2>/dev/null; do
  old=$(cat "$BASE/run.lock/pid" 2>/dev/null || true)
  case "$old" in *[!0-9]*|'') old=0;; esac
  if [ "$old" -gt 0 ] && ! kill -0 "$old" 2>/dev/null; then
    rm -f "$BASE/run.lock/pid"; rmdir "$BASE/run.lock" 2>/dev/null || true
  fi
  # A crash between mkdir and writing pid can leave an empty directory.
  if [ "$old" -eq 0 ] && [ "$i" -ge 3 ]; then rmdir "$BASE/run.lock" 2>/dev/null || true; fi
  i=$((i+1)); [ "$i" -le 15 ] || exit 4
  pause 1 || exit 0
done
echo $$ > "$BASE/run.lock/pid"
cleanup() {
  if [ "$(cat "$BASE/run.lock/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "$BASE/run.lock/pid"; rmdir "$BASE/run.lock" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM
trap '' HUP
worker_alive() {
  for p in $(pidof "$B" 2>/dev/null); do [ "$p" = "$hp" ] && return 0; done
  return 1
}
start_worker() {
  control || return 1
  launched=$(date +%s); ready=0
  if [ "$attempts" -eq 0 ] || pidof "$B" >/dev/null 2>&1; then
    stop_for_restart || return 1
  fi
  control || return 1
  if [ "$attempts" -gt 0 ]; then
    # Capture system exit metadata before aa test changes its context.
    # EntryAbility cancels only for explicit user stops; upgrades may recover.
    /bin/timeout 10 aa start -b "$B" -a EntryAbility --ps quietstartRecoveryToken "$TOKEN" --ps quietstartRecoveryReason "$cause" --pi quietstartRecoveryAttempt "$attempts" --ps quietstartStopIntent "$(cat "$BASE/supervisor-stop-intent.json" 2>/dev/null)" --ps quietstartSupervisorEvents "$(tail -n 12 "$BASE/supervisor-events.jsonl" 2>/dev/null)" >/dev/null 2>&1
    command_rc=$?; command=launch-recovery-ui; state=command-result; journal; command=none
    pause 2 || return 1
  fi
  control || return 1
  /bin/timeout 15 aa test -b "$B" -m entry_test -s unittest OpenHarmonyTestRunner -s mode skip -s seconds 0 -s supervisor "$TOKEN" -s recoveryAttempt "$attempts" -w 3 >/dev/null 2>&1
  command_rc=$?; command=start-worker; state=command-result; journal; command=none
  launched=$(date +%s)
  ready=0
  status starting
}
status preparing
pause 2 || exit 0
start_worker || { control || exit 0; status start-command-failed; }
bad=0
hp=0
while control; do
  pause 5 || break
  now=$(date +%s)
  cause=
  hp=0; hb=0; progress=0; rpc=0; mode=active; operation=initializing; since=0; input=0; ht=
  read ht hp hb progress rpc mode operation since input < "$FILES/worker-health.txt" 2>/dev/null || true
  valid=yes
  for n in "$hp" "$hb" "$progress" "$rpc" "$since" "$input"; do
    case "$n" in *[!0-9]*|'') valid=no;; esac
  done
  case "$operation" in *[!a-zA-Z0-9_-]*|'') operation=unknown;; esac
  if [ "$valid" != yes ] || [ "$ht" != "$TOKEN" ]; then
    hp=0; hb=0; rpc=0; cause=startup-timeout
  elif ! worker_alive; then cause=process-exited
  elif [ "$operation" = ended ]; then cause=worker-ended
  elif [ "$now" -lt "$hb" ] || [ "$now" -lt "$rpc" ] || [ "$now" -lt "$progress" ]; then
    # Wall-clock changes are not evidence of a stuck RPC.
    status clock-changed; bad=0; continue
  elif [ $((now-hb)) -gt 30 ]; then cause=heartbeat-stalled
  elif [ "$mode" != sleeping ] && { [ $((now-progress)) -gt 30 ] || [ $((now-rpc)) -gt 30 ]; }; then cause=rpc-stalled
  fi
  if [ -z "$cause" ]; then
    bad=0; ready=1
    if [ "$healthy_since" -eq 0 ] || [ "$now" -lt "$healthy_since" ]; then healthy_since=$now; fi
    # One healthy minute resets consecutive failures, not the diagnostic total.
    if [ $((now-healthy_since)) -ge 60 ]; then retry_streak=0; fi
    status healthy; continue
  fi
  healthy_since=0
  [ "$ready" -eq 1 ] || [ $((now-launched)) -ge 45 ] || continue
  # Power state comes from the worker's system API. A living, suspended
  # sleeping process may not advance its heartbeat. Do not restart it for
  # inactivity. A missing process can recover, then the new worker checks
  # power before scanning. Never issue a screen-wakeup command.
  if [ "$mode" = sleeping ] && worker_alive && [ "$cause" = heartbeat-stalled ]; then
    bad=0; status waiting-resume; pause 10 || break; continue
  fi
  bad=$((bad+1)); [ "$bad" -ge 2 ] || continue
  if [ "$retry_streak" -ge 4 ]; then
    status exhausted
    control || break
    /bin/timeout 10 aa force-stop "$B" >/dev/null 2>&1
    control || break
    /bin/timeout 10 aa start -b "$B" -a EntryAbility --ps quietstartRecoveryToken "$TOKEN" --ps quietstartSupervisorState exhausted --pi quietstartRecoveryAttempt "$attempts" --ps quietstartSupervisorEvents "$(tail -n 12 "$BASE/supervisor-events.jsonl" 2>/dev/null)" >/dev/null 2>&1
    exit 0
  fi
  attempts=$((attempts+1)); retry_streak=$((retry_streak+1)); status retrying
  case "$retry_streak" in 1) delay=5;; 2) delay=15;; 3) delay=30;; *) delay=60;; esac
  pause "$delay" || break
  start_worker || { control || break; status start-command-failed; }
  bad=0
done
cause=control-stopped
status stopped
if [ "$ct" = "$TOKEN" ] && [ "$cm" = stopped ] && worker_alive; then
  /bin/timeout 10 aa force-stop "$B" >/dev/null 2>&1
fi
`;

export function supervisorCommand(token: string, encoded: string, account: number): string {
  if (!Number.isInteger(account) || account < 0 || account > 2147483647 || !/^[0-9]{13,16}$/.test(token) || !/^[A-Za-z0-9+/=]+$/.test(encoded)) { throw new Error('Invalid supervisor program'); }
  const path = '/data/local/tmp/quietstart-supervisor/' + token;
  return 'umask 077; mkdir -p /data/local/tmp/quietstart-supervisor && ' +
    "printf '%s' '" + encoded + "' | base64 -d > " + path + '.sh && ' +
    '/bin/nohup /bin/setsid /bin/sh ' + path + '.sh ' + token + ' ' + account + ' </dev/null > ' + path +
    '.log 2>&1 & echo QuietStartLocalScheduled; wait';
}
