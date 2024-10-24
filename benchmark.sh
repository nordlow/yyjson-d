#!/bin/bash

set -euo pipefail

echo -e "echo
# Benchmarking ..."

echo -e "\n## Benchmarking with DMD ..."
dub -q test --compiler=dmd --build=benchmark-release

echo e "\n## Benchmarking with LDC ..."
dub -q test --compiler=ldc2 --build=benchmark-release
