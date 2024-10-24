#!/bin/bash

set -euo pipefail

echo -e "\n# Testing ..."

echo -e "\n## Testing with DMD ..."
dub -q test --compiler=dmd --build=unittest-without-coverage

echo -e "\n## Testing with LDC using AddressSanitizer (ASan) ..."
dub -q test --compiler=ldc2 --build=unittest-without-coverage
