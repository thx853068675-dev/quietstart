"""Exercise the production shell state machine with a virtual clock and fake OS commands."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'entry/src/main/ets/core/SupervisorProgram.ets'
PROGRAM = SOURCE.read_text().split('String.raw' + chr(96), 1)[1].split(chr(96) + ';', 1)[0]
TOKEN = '1789400000000'

MOCK = r'''#!/bin/sh
name=$(basename "$0")
R="$MOCK_ROOT"
APP="$R/app"
TOKEN=1789400000000
case "$name" in
date) cat "$R/clock";;
pidof) [ "$1" = uitest ] || cat "$R/pid" 2>/dev/null;;
hidumper) echo "Current State: $MOCK_POWER Reason: 1";;
timeout) shift; exec "$@";;
aa)
  echo "$*" >> "$R/commands"
  if [ "$MOCK_CASE" = command-fail ] && [ "$1" = force-stop ] && [ ! -f "$R/failed-command" ]; then
    touch "$R/failed-command"; exit 7
  fi
  if [ "$1" = force-stop ]; then rm -f "$R/pid"; exit 0; fi
  if [ "$1" = test ]; then
    n=$(cat "$R/tests"); n=$((n+1)); echo "$n" > "$R/tests"
    echo "$((1234+n))" > "$R/pid"; cat "$R/clock" > "$R/last-start"
  fi
  if [ "$MOCK_CASE" = user-request ] && [ "$1" = start ]; then echo "$TOKEN stopped 0" > "$APP/supervision-control.txt"; fi
  case "$*" in *exhausted*) echo "$TOKEN stopped 0" > "$APP/supervision-control.txt";; esac
  ;;
sleep)
  t=$(cat "$R/clock"); t=$((t+$1)); echo "$t" > "$R/clock"
  n=$(cat "$R/tests"); pid=$((1234+n)); start=$(cat "$R/last-start" 2>/dev/null || echo 1000)
  if [ "$MOCK_CASE" = fail ] || [ "$MOCK_CASE" = stop-backoff ] || [ "$MOCK_CASE" = stop-cooldown ]; then
    rm -f "$APP/worker-health.txt"
  elif [ "$MOCK_CASE" = rpc ] && [ "$n" -eq 1 ]; then
    echo "$TOKEN $pid $t 1000 1000 active snapshot 1000 0" > "$APP/worker-health.txt"
  elif [ "$MOCK_CASE" = sleeping ]; then
    echo "$TOKEN $pid $t $t 1000 sleeping sleeping 1000 0" > "$APP/worker-health.txt"
  elif [ "$MOCK_CASE" = frozen ]; then
    echo "$TOKEN $pid 1000 1000 1000 sleeping scan 1000 0" > "$APP/worker-health.txt"
  else
    echo "$TOKEN $pid $t $t $t active waiting $t 0" > "$APP/worker-health.txt"
  fi
  if { [ "$MOCK_CASE" = process ] || [ "$MOCK_CASE" = user-request ]; } && [ "$n" -eq 1 ] && [ "$t" -gt 1020 ]; then rm -f "$R/pid"; fi
  if [ "$MOCK_CASE" = stable-reset ]; then
    if [ "$n" -eq 1 ] && [ "$t" -gt 1020 ]; then rm -f "$R/pid"; fi
    if [ "$n" -eq 2 ] && [ "$t" -gt $((start+70)) ]; then rm -f "$R/pid"; fi
  fi
  stop=0
  case "$MOCK_CASE" in healthy|sleeping|frozen|empty-lock) [ "$t" -gt 1120 ] && stop=1;; esac
  case "$MOCK_CASE" in rpc|process) [ "$n" -gt 1 ] && [ "$t" -gt $((start+60)) ] && stop=1;; esac
  if [ "$MOCK_CASE" = stop-backoff ] && [ "$t" -ge 1055 ]; then stop=1; fi
  if [ "$MOCK_CASE" = command-fail ] && [ "$n" -ge 1 ] && [ "$t" -gt $((start+60)) ]; then stop=1; fi
  if [ "$MOCK_CASE" = stable-reset ] && [ "$n" -ge 3 ] && [ "$t" -gt $((start+60)) ]; then stop=1; fi
  if [ "$MOCK_CASE" = stop-cooldown ] && [ "$t" -ge 1300 ]; then stop=1; fi
  [ "$t" -gt 2000 ] && stop=1
  [ "$stop" -eq 1 ] && echo "$TOKEN stopped 0" > "$APP/supervision-control.txt"
  ;;
esac
exit 0
'''

class SupervisorTests(unittest.TestCase):
    def run_case(self, case):
        with tempfile.TemporaryDirectory(prefix='quietstart-supervisor-') as temp:
            root = pathlib.Path(temp)
            for name in ['bin', 'app', 'supervisor']:
                (root / name).mkdir()
            (root/'clock').write_text('1000')
            (root/'tests').write_text('0')
            (root/'app/supervision-control.txt').write_text(TOKEN+' active 1000000\n')
            for name in ['date', 'pidof', 'hidumper', 'timeout', 'aa', 'sleep']:
                path = root/'bin'/name
                path.write_text(MOCK)
                path.chmod(0o700)
            if case == 'empty-lock': (root/'supervisor/run.lock').mkdir()
            if case == 'locked':
                (root/'supervisor/run.lock').mkdir()
                (root/'supervisor/run.lock/pid').write_text(str(os.getpid()))
            # Paths/timeout executable only; the control flow and thresholds
            # remain the exact program embedded in the application.
            program = PROGRAM.replace('/data/local/tmp/quietstart-supervisor', str(root/'supervisor'))
            program = program.replace('/data/app/el2/$ACCOUNT/base/$B/files', str(root/'app'))
            program = program.replace('/bin/timeout', 'timeout')
            script = root/'run.sh'
            script.write_text(program)
            run = subprocess.run(['/bin/sh', str(script), TOKEN, '100'], capture_output=True, text=True, timeout=30,
                env={**os.environ, 'PATH':str(root/'bin')+':'+os.environ['PATH'],
                     'MOCK_ROOT':str(root), 'MOCK_CASE':case, 'MOCK_POWER':'SLEEP' if case=='frozen' else 'AWAKE'})
            commands = (root/'commands').read_text() if (root/'commands').exists() else ''
            self.last_events = [__import__('json').loads(x) for x in (root/'supervisor/supervisor-events.jsonl').read_text().splitlines()] if (root/'supervisor/supervisor-events.jsonl').exists() else []
            status = (root/'supervisor/status.txt').read_text() if (root/'supervisor/status.txt').exists() else ''
            self.assertEqual(run.returncode, 4 if case=='locked' else 0, run.stderr)
            return int((root/'tests').read_text()), commands, status, run.stdout

    def test_healthy_sleeping_and_screen_off_freeze_do_not_restart(self):
        for case in ['healthy', 'sleeping', 'frozen']:
            with self.subTest(case=case):
                count, commands, status, _ = self.run_case(case)
                self.assertEqual(count, 1, commands)
                self.assertIn('stopped', status)

    def test_stuck_rpc_with_live_heartbeat_and_process_exit_each_recover_once(self):
        for case, reason in [('rpc', 'rpc-stalled'), ('process', 'process-exited')]:
            with self.subTest(case=case):
                count, commands, status, _ = self.run_case(case)
                self.assertEqual(count, 2, commands)
                self.assertIn(reason, commands)
                self.assertIn('-s recoveryAttempt 1', commands)

    def test_diagnostics_publish_causes_commands_and_stopping(self):
        self.run_case('rpc')
        self.assertTrue(any(e['cause']=='rpc-stalled' and e['state']=='retrying' for e in self.last_events))
        self.assertTrue(any(e['command']=='force-stop' and e['exitCode']==0 for e in self.last_events))
        self.assertTrue(any(e['command']=='start-worker' for e in self.last_events))
        self.assertEqual(self.last_events[-1]['state'],'stopped')
        self.assertLessEqual(len(self.last_events),120)

    def test_four_retries_use_requested_delays_then_stop(self):
        count, commands, status, output = self.run_case('fail')
        self.assertEqual(count,5,commands)
        self.assertIn('quietstartSupervisorState exhausted',commands)
        self.assertIn('4 exhausted',status)
        for attempt,delay in [(1,5),(2,15),(3,30),(4,60)]:
            retry=next(e for e in self.last_events if e['state']=='retrying' and e['attempt']==attempt)
            launch=next(e for e in self.last_events if e['command']=='start-worker' and e['attempt']==attempt)
            self.assertEqual(launch['at']-retry['at'],(delay+2)*1000)

    def test_stop_during_final_backoff_cancels_pending_launch(self):
        count, commands, status, output = self.run_case('stop-cooldown')
        self.assertEqual(count,4,commands)
        self.assertIn('retrying attempt=4',output)
        self.assertIn('stopped',status)

    def test_initial_stop_command_failure_does_not_abandon_supervision(self):
        count, commands, status, output = self.run_case('command-fail')
        self.assertEqual(count,1,commands)
        self.assertIn('start-command-failed',output)
        self.assertIn('healthy',output)

    def test_one_healthy_minute_resets_fast_retry_delay(self):
        count, commands, status, output = self.run_case('stable-reset')
        self.assertEqual(count,3,commands)
        retry = next(e for e in self.last_events if e['state']=='retrying' and e['attempt']==2)
        launch = next(e for e in self.last_events if e['command']=='start-worker' and e['attempt']==2)
        self.assertLessEqual(launch['at']-retry['at'],10000)

    def test_user_request_during_exit_capture_cancels_worker_restart(self):
        count, commands, status, _ = self.run_case('user-request')
        self.assertEqual(count,1,commands)
        self.assertIn('quietstartRecoveryReason process-exited',commands)
        self.assertIn('stopped',status)

    def test_empty_crashed_lock_is_reclaimed(self):
        count, commands, _, _ = self.run_case('empty-lock')
        self.assertEqual(count, 1, commands)

    def test_stop_during_backoff_cancels_relaunch(self):
        count, commands, status, _ = self.run_case('stop-backoff')
        self.assertEqual(count, 1, commands)
        self.assertIn('stopped', status)

    def test_live_lock_prevents_duplicate_supervisor(self):
        count, commands, _, _ = self.run_case('locked')
        self.assertEqual(count, 0, commands)

if __name__ == '__main__':
    unittest.main()

