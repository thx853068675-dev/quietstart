#!/bin/sh
set -u
D=$1
MB=$2
SECONDS=$3
case "$D" in /data/local/tmp/quietstart-pressure/*) ;; *) exit 2;; esac
case "$MB" in 64|128|256|512) ;; *) exit 2;; esac
case "$SECONDS" in 20|90|180|300) ;; *) exit 2;; esac
mkdir -p "$D"
reader=0; writer=0
cleanup() {
  trap - EXIT INT TERM
  [ "$reader" -le 1 ] || kill "$reader" 2>/dev/null || true
  [ "$writer" -le 1 ] || kill "$writer" 2>/dev/null || true
  wait 2>/dev/null || true
  echo done > "$D/done"
}
trap cleanup EXIT INT TERM
/bin/sh -c 'echo $$ > "$1/writer"; exec /bin/dd if=/dev/urandom ibs=1048576 obs=$(($2*1048576)) count="$2" status=none' pressure "$D" "$MB" 2>"$D/dd.log" | /bin/sleep "$SECONDS" &
reader=$!
i=0
while [ ! -s "$D/writer" ] && [ "$i" -lt 10 ]; do /bin/sleep 1; i=$((i+1)); done
read writer < "$D/writer" || exit 3
printf '%s %s %s\n' "$$" "$reader" "$writer" > "$D/pids"
left=$SECONDS
while [ "$left" -gt 0 ] && [ ! -f "$D/stop" ]; do
  kill -0 "$writer" 2>/dev/null || break
  /bin/sleep 1
  left=$((left-1))
done
