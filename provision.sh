#!/bin/bash

set -euo pipefail

SOURCE_ROOT="yyjson"
TARGET_ROOT="yyjson-build"

mkdir -p "${TARGET_ROOT}"
pushd "${TARGET_ROOT}" > /dev/null

# ok to use "-march=native" because of no distribution
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-march=native" ../"${SOURCE_ROOT}"
make --quiet

popd > /dev/null
