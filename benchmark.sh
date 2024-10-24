#!/bin/bash

set -euo pipefail

dub -q test --compiler=dmd --build=benchmark-release
dub -q test --compiler=ldc2 --build=benchmark-release
