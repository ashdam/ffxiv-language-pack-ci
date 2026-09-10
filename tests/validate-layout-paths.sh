#!/usr/bin/env bash
set -euo pipefail
validator=$(cd "$(dirname "$0")/../scripts" && pwd)/validate-pr.sh
temp_root=$(cd "${TMPDIR:-/tmp}" && pwd -P)
work=$(mktemp -d "$temp_root/uld-paths.XXXXXX")
case "$work" in "$temp_root"/uld-paths.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/repo/layouts" "$work/source"
git -C "$work/repo" init -q
git -C "$work/repo" config user.name Test
git -C "$work/repo" config user.email test@example.invalid
git -C "$work/repo" commit -qm base --allow-empty
base=$(git -C "$work/repo" rev-parse HEAD)
check() {
  local expected=$1 label=$2 result=0
  git -C "$work/repo" add -A
  if [ "${3:-}" = executable ]; then git -C "$work/repo" update-index --chmod=+x layouts/example.json; fi
  if [ "${3:-}" = regular ]; then git -C "$work/repo" update-index --chmod=-x layouts/example.json; fi
  git -C "$work/repo" commit -qm fixture --allow-empty
  bash "$validator" "$base" HEAD "$work/report.md" "$work/repo" > "$work/output" || result=$?
  if [ "$result" != "$expected" ]; then
    cat "$work/output"
    echo "FAIL: $label"
    exit 1
  fi
  echo "PASS: $label"
}
printf '{}\n' > "$work/repo/layouts/example.json"
check 0 'JSON layout definition is allowed'
check 1 'Executable layout definition is rejected' executable
check 0 'Regular layout definition is allowed' regular
printf 'uld\n' > "$work/repo/layouts/example.uld"
check 1 'Raw ULD in the language repository is rejected'
git -C "$work/repo" rm -q layouts/example.uld
mkdir -p "$work/repo/layouts/nested"
printf '{}\n' > "$work/repo/layouts/nested/example.json"
check 1 'Nested layout definition is rejected'
git -C "$work/repo" rm -q layouts/nested/example.json
check 0 'Valid layout paths are restored'
base=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" rm -q layouts/example.json
check 0 'Layout removal is allowed'

mkdir -p "$work/repo/.github/workflows"
printf 'on:\n  push:\n    paths: ["corpus/**", "glossary/**", "fonts/**", "pack.json"]\n' > "$work/repo/.github/workflows/release.yml"
git -C "$work/repo" add -A
git -C "$work/repo" commit -qm 'Release fixture'
base=$(git -C "$work/repo" rev-parse HEAD)
printf 'on:\n  push:\n    paths: ["corpus/**", "glossary/**", "fonts/**", "layouts/**", "pack.json"]\n' > "$work/repo/.github/workflows/release.yml"
check 0 'Layout release trigger is allowed'
printf 'jobs: {}\n' >> "$work/repo/.github/workflows/release.yml"
check 1 'Other workflow changes are rejected'
