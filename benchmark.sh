#!/bin/bash

set -euo pipefail

echo
echo "# Benchmarking ..."

echo
echo "## Benchmarking with DMD ..."
dub -q test --compiler=dmd --build=benchmark-release

echo
echo "## Benchmarking with LDC ..."
dub -q test --compiler=ldc2 --build=benchmark-release
