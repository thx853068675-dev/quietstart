#!/bin/bash
# 把「轻启」一个主 HAP 安装到你的鸿蒙手机（macOS / Linux）。
# 用法：把本脚本和一个 .hap 放在同一目录，运行：
#   bash install-to-user-device.sh
# hdc 不存在时会提示设置 DEVECO_APP 或 HDC_BIN。

set -u
set -o pipefail

HAP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_HAP="$HAP_DIR/entry-default-signed.hap"

# 使用接收者自行准备的官方 hdc；交付包不包含 SDK 二进制。
if [[ -n "${HDC_BIN:-}" ]]; then
  hdc_bin="$HDC_BIN"
elif [[ -x "$HAP_DIR/hdc" ]]; then
  hdc_bin="$HAP_DIR/hdc"
else
  deveco_app="${DEVECO_APP:-/Applications/DevEco-Studio.app}"
  hdc_bin="$deveco_app/Contents/sdk/default/openharmony/toolchains/hdc"
fi

if [[ ! -x "$hdc_bin" ]]; then
  printf '找不到 hdc：%s\n请设置 DEVECO_APP 为 DevEco Studio 安装路径，或用 HDC_BIN 指定 hdc 路径。\n' "$hdc_bin" >&2
  exit 2
fi

if [[ ! -f "$APP_HAP" ]]; then
  printf '缺少 HAP 文件：请确认 %s 存在，且同目录有 entry-default-signed.hap 。\n' "$HAP_DIR" >&2
  exit 2
fi

if ! target_output=$("$hdc_bin" list targets 2>&1); then
  printf '读取设备列表失败：\n%s\n' "$target_output" >&2
  exit 2
fi
devices=()
while IFS= read -r device; do
  device="${device//$'\r'/}"
  [[ -n "$device" && "$device" != \[* && "$device" != *[[:space:]]* ]] && devices+=("$device")
done <<< "$target_output"

if [[ ${#devices[@]} -ne 1 ]]; then
  printf '请连接并仅保留一台已授权的目标设备。\n' >&2
  "$hdc_bin" list targets >&2
  exit 2
fi

printf '开始安装到你的手机...\n'
printf '安装轻启单包...\n'
output=$("$hdc_bin" -t "${devices[0]}" install -r "$APP_HAP" 2>&1)
code=$?
printf '%s\n' "$output"
if [[ $code -ne 0 || "$output" != *"install bundle successfully"* || "$output" == *"[Fail]"* ]]; then
  printf '安装未成功，请检查签名授权与设备连接。\n' >&2; exit 1
fi
printf '轻启已安装。打开应用，按向导开启无线调试；首次连接会自动安装工作模块，无需安装第二个文件。\n'
