#!/bin/bash

set -euo pipefail

echo -e "\n# Testing ..."

echo -e "\n## Testing with DMD ..."
dub -q test --compiler=dmd

echo -e "\n## Testing with LDC ..."
dub -q test --compiler=ldc2
