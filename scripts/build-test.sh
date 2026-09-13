#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IDE_ROOT="${DEVECO_APP:-/Applications/DevEco-Studio.app}/Contents"
export JAVA_HOME="$IDE_ROOT/jbr/Contents/Home"
export NODE_HOME="$IDE_ROOT/tools/node"
export DEVECO_SDK_HOME="$IDE_ROOT/sdk"
exec "$IDE_ROOT/tools/hvigor/bin/hvigorw" --mode module -p product=default -p module=entry@ohosTest -p isOhosTest=true assembleHap --no-daemon "$@"
