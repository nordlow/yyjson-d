#!/bin/bash

set -euo pipefail

echo -e "\n# Benchmarking ..."

echo -e "\n## Benchmarking with DMD ..."
dub -q test --compiler=dmd -c benchmark-release

echo -e "\n## Benchmarking with LDC ..."
dub -q test --compiler=ldc2 -c benchmark-release
