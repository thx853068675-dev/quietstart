#!/bin/bash
# Standard APP container containing only the main module; worker remains a rawfile.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh -p buildMode=release "$@"
IDE_ROOT="${DEVECO_APP:-/Applications/DevEco-Studio.app}/Contents"
export JAVA_HOME="$IDE_ROOT/jbr/Contents/Home"
export NODE_HOME="$IDE_ROOT/tools/node"
export DEVECO_SDK_HOME="$IDE_ROOT/sdk"
"$IDE_ROOT/tools/hvigor/bin/hvigorw" --mode project -p product=default -p buildMode=release assembleApp --no-daemon "$@"
python3 tools/verify-single-package.py
