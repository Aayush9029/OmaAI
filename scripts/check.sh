#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
  "${project_dir}/install.sh" \
  "${project_dir}/bin/omaai" \
  "${project_dir}/bin/omaai-server"
jq empty "${project_dir}/manifest.json"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "${project_dir}"
fi

python3 -B -m unittest discover -s "${project_dir}/tests"

echo "OmaAI checks passed"
