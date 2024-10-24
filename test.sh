#!/bin/bash

set -euo pipefail

dub -q test --compiler=dmd
dub -q test --compiler=ldc2
