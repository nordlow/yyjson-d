#!/bin/bash

set -euo pipefail

exec dub -q test --compiler=ldc2
