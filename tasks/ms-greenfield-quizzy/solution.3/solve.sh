#!/usr/bin/env bash
# Applies this step of the reference solution and installs its gems.
set -euo pipefail
cd /app
git apply --binary --whitespace=nowarn /solution/solution.patch
bundle install
