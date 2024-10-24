#!/bin/bash

set -euo pipefail

echo
echo "# Testing ..."

echo
echo "## Testing with DMD ..."
dub -q test --compiler=dmd

echo
echo "## Testing with LDC ..."
dub -q test --compiler=ldc2
