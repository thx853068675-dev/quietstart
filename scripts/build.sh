#!/bin/bash
# Build the worker first, then embed it in the single main HAP delivered to users.
set -euo pipefail
cd "$(dirname "$0")/.."
IDE_ROOT="${DEVECO_APP:-/Applications/DevEco-Studio.app}/Contents"
export JAVA_HOME="$IDE_ROOT/jbr/Contents/Home"
export NODE_HOME="$IDE_ROOT/tools/node"
export DEVECO_SDK_HOME="$IDE_ROOT/sdk"
rm -f entry/src/main/resources/rawfile/quietstart-worker.hap entry/src/main/resources/rawfile/quietstart-worker.json
bash scripts/build-test.sh "$@"
python3 tools/embed-worker.py
"$IDE_ROOT/tools/hvigor/bin/hvigorw" --mode module -p product=default -p module=entry@default assembleHap --no-daemon "$@"
python3 tools/verify-single-package.py
