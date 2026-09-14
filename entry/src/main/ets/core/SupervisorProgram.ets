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
last_state=
status() {
  state=$1
  now=$(date +%s)
  printf '%s %s %s %s %s %s\n' "$TOKEN" "$$" "$now" "$attempts" "$state" "$cause" > "$BASE/status.tmp"
  mv "$BASE/status.tmp" "$BASE/status.txt"
  if [ "$state" != "$last_state" ]; then echo "$now $state attempt=$attempts cause=$cause"; last_state=$state; fi
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
  if [ "$attempts" -eq 0 ] || pidof "$B" >/dev/null 2>&1; then
    /bin/timeout 10 aa force-stop "$B" >/dev/null 2>&1
  fi
  control || return 1
  if [ "$attempts" -gt 0 ]; then
    # Capture system exit metadata before aa test changes its context.
    # EntryAbility cancels supervision for USER_REQUEST and UPGRADE.
    /bin/timeout 10 aa start -b "$B" -a EntryAbility --ps quietstartRecoveryToken "$TOKEN" --ps quietstartRecoveryReason "$cause" --pi quietstartRecoveryAttempt "$attempts" >/dev/null 2>&1
    pause 2 || return 1
  fi
  control || return 1
  /bin/timeout 15 aa test -b "$B" -m entry_test -s unittest OpenHarmonyTestRunner -s mode skip -s seconds 0 -s supervisor "$TOKEN" -s recoveryAttempt "$attempts" -w 3 >/dev/null 2>&1
  launched=$(date +%s)
  ready=0
  status starting
}
status preparing
pause 2 || exit 0
start_worker || exit 0
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
  if [ "$valid" != yes ] || [ "$ht" != "$TOKEN" ]; then cause=startup-timeout
  elif ! worker_alive; then cause=process-exited
  elif [ "$operation" = ended ]; then cause=worker-ended
  elif [ "$now" -lt "$hb" ] || [ "$now" -lt "$rpc" ] || [ "$now" -lt "$progress" ]; then
    # Wall-clock changes are not evidence of a stuck RPC.
    status clock-changed; bad=0; continue
  elif [ $((now-hb)) -gt 30 ]; then cause=heartbeat-stalled
  elif [ "$mode" != sleeping ] && { [ $((now-progress)) -gt 30 ] || [ $((now-rpc)) -gt 30 ]; }; then cause=rpc-stalled
  fi
  if [ -z "$cause" ]; then bad=0; ready=1; status healthy; continue; fi
  [ "$ready" -eq 1 ] || [ $((now-launched)) -ge 45 ] || continue
  # Power state comes from the worker's system API. A living, suspended
  # sleeping process may not advance its heartbeat. Do not restart it for
  # inactivity. A missing process can recover, then the new worker checks
  # power before scanning. Never issue a screen-wakeup command.
  if [ "$mode" = sleeping ] && worker_alive && [ "$cause" = heartbeat-stalled ]; then
    bad=0; status waiting-resume; pause 10 || break; continue
  fi
  bad=$((bad+1)); [ "$bad" -ge 2 ] || continue
  if [ "$attempts" -ge 3 ]; then
    status exhausted
    control || break
    /bin/timeout 10 aa force-stop "$B" >/dev/null 2>&1
    control || break
    /bin/timeout 10 aa start -b "$B" -a EntryAbility --ps quietstartRecoveryToken "$TOKEN" --ps quietstartSupervisorState exhausted >/dev/null 2>&1
    exit 0
  fi
  attempts=$((attempts+1)); status retrying
  case "$attempts" in 1) delay=5;; 2) delay=15;; *) delay=45;; esac
  pause "$delay" || break
  start_worker || break
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
