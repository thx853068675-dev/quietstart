#!/bin/bash
# Uses installed Debug HAPs; syncs installed-app names, preserving selection and rules.
set -u
set -o pipefail

readonly QUIETSTART_BUNDLE='com.tonghongxiang.quietstart'
readonly MAX_SESSION_SECONDS=43200
readonly EXPECTED_WAIT_TIMEOUT='Timeout: user test is not completed within the specified time.'
action="${1:-activate}"
if [[ $# -gt 1 || ( "$action" != activate && "$action" != --stop ) ]]; then
  printf '用法：%s [--stop]\n' "$0" >&2
  exit 2
fi

deveco_app="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
hdc_bin="${HDC_BIN:-$deveco_app/Contents/sdk/default/openharmony/toolchains/hdc}"
if [[ ! -x "$hdc_bin" ]]; then
  printf '找不到官方 hdc：%s\n请设置 DEVECO_APP 为 DevEco Studio 的安装路径。\n' "$hdc_bin" >&2
  exit 2
fi

session_seconds="${SESSION_SECONDS:-0}"
if [[ "$action" == activate ]]; then
  if [[ ! "$session_seconds" =~ ^[0-9]{1,5}$ ]]; then
    printf 'SESSION_SECONDS 必须是 0 或 1 至 %s 的整数；0 表示不设时限。\n' "$MAX_SESSION_SECONDS" >&2
    exit 2
  fi
  session_seconds=$((10#$session_seconds))
  if (( session_seconds < 0 || session_seconds > MAX_SESSION_SECONDS )); then
    printf 'SESSION_SECONDS 必须是 0 或 1 至 %s 的整数；0 表示不设时限。\n' "$MAX_SESSION_SECONDS" >&2
    exit 2
  fi
fi

if ! target_output="$("$hdc_bin" list targets 2>&1)"; then
  printf '读取手机连接失败：\n%s\n' "$target_output" >&2
  exit 1
fi

devices=()
while IFS= read -r line; do
  line="${line//$'\r'/}"
  # Target IDs occupy their own line; ignore the empty-list and daemon messages.
  if [[ -n "$line" && "$line" != '[Empty]' && "$line" != *[[:space:]]* &&
        "$line" != \[* && "$line" != \** ]]; then
    devices+=("$line")
  fi
done <<< "$target_output"

device="${HDC_DEVICE:-}"
if [[ -n "$device" ]]; then
  found=false
  for candidate in "${devices[@]}"; do
    if [[ "$candidate" == "$device" ]]; then found=true; fi
  done
  if [[ "$found" != true ]]; then
    printf 'HDC_DEVICE 指定的设备未连接。请解锁手机、允许 USB 调试，再重试。\n' >&2
    exit 1
  fi
elif (( ${#devices[@]} == 1 )); then
  device="${devices[0]}"
elif (( ${#devices[@]} == 0 )); then
  printf '未找到已连接手机。请解锁手机并允许 USB 调试后重试。\n可通过 HDC_DEVICE 指定已连接设备。\n' >&2
  exit 1
else
  printf '连接了多台设备，请设置 HDC_DEVICE 为目标手机的设备 ID。\n可运行官方 hdc list targets 查看。\n' >&2
  exit 1
fi

# Repeated activation replaces only QuietStart's own previous test process.
if ! stop_output="$("$hdc_bin" -t "$device" shell aa force-stop "$QUIETSTART_BUNDLE" 2>&1)"; then
  printf '结束轻启旧会话失败：\n%s\n' "$stop_output" >&2
  exit 1
fi
if [[ "$stop_output" != *'force stop process successfully.'* ]]; then
  printf '未能确认轻启旧会话已结束：\n%s\n' "$stop_output" >&2
  exit 1
fi
if [[ "$action" == --stop ]]; then
  printf '已结束轻启本次调试会话。重新使用时，请再次运行“激活轻启”。\n'
  exit 0
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
node_bin="$deveco_app/Contents/tools/node/bin/node"
if [[ ! -x "$node_bin" ]]; then
  printf '找不到 DevEco Studio 内置 Node，无法同步应用列表。\n' >&2
  exit 1
fi
printf '正在同步手机安装列表……\n'
if ! "$node_bin" "$script_dir/sync-apps.cjs" "$hdc_bin" "$device"; then
  printf '应用列表未更新，保留上次列表。继续尝试激活跳过会话。\n' >&2
fi

if (( session_seconds == 0 )); then
  printf '正在启动轻启：持续会话，直到用户结束、进程退出或手机重启。\n'
else
  printf '正在启动轻启，限时 %s 秒……\n' "$session_seconds"
fi
activation_exit=0
activation_output="$("$hdc_bin" -t "$device" shell aa test \
  -b "$QUIETSTART_BUNDLE" -m entry_test \
  -s unittest OpenHarmonyTestRunner -s mode skip \
  -s seconds "$session_seconds" -w 3 2>&1)" || activation_exit=$?

# aa's 3-second observer timeout says nothing about whether the worker is online.
# Accept that specific timeout only; retain all other failures as failures.
has_wait_timeout=false
if [[ "$activation_output" == *"$EXPECTED_WAIT_TIMEOUT"* ]]; then
  has_wait_timeout=true
fi
remaining_output="${activation_output//$EXPECTED_WAIT_TIMEOUT/}"
if [[ "$remaining_output" =~ [Ee][Rr][Rr][Oo][Rr]|[Ff][Aa][Ii][Ll]|[Dd][Ee][Nn][Ii][Ee][Dd]|[Tt][Ii][Mm][Ee][Oo][Uu][Tt] ]] ||
   { (( activation_exit != 0 )) && [[ "$has_wait_timeout" != true ]]; }; then
  printf '轻启激活命令失败：\n%s\n' "$activation_output" >&2
  exit 1
fi
if [[ "$has_wait_timeout" != true && "$activation_output" != *'user test started.'* &&
      "$activation_output" != *'user test finished.'* ]]; then
  printf '未收到可识别的调试启动结果：\n%s\n' "$activation_output" >&2
  exit 1
fi

printf '调试启动命令已发送；这不代表服务已成功运行。\n'
printf '请打开手机上的“轻启”，确认显示在线，再使用跳广告开关。\n'
if (( session_seconds == 0 )); then
  printf '本次不设时限；系统仍可能结束进程，请以手机上的实时心跳状态为准。\n'
  printf '若显示离线，请查看轻启中的错误信息。\n'
else
  printf '若显示离线，请查看轻启中的错误信息；本次会话最长 %s 秒。\n' "$session_seconds"
fi
