#!/bin/bash

set -euo pipefail

echo -e "\n# Testing ..."

echo -e "\n## Testing with DMD ..."
dub -q test --compiler=dmd -c unittest-without-coverage

echo -e "\n## Testing with LDC using AddressSanitizer (ASan) ..."
dub -q test --compiler=ldc2 -c unittest-without-coverage
