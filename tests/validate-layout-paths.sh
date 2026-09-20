#!/usr/bin/env bash
set -euo pipefail
validator=$(cd "$(dirname "$0")/../scripts" && pwd)/validate-pr.sh
temp_root=$(cd "${TMPDIR:-/tmp}" && pwd -P)
work=$(mktemp -d "$temp_root/path-validation.XXXXXX")
case "$work" in "$temp_root"/path-validation.*) ;; *) exit 1 ;; esac
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/repo"
git -C "$work/repo" init -q
git -C "$work/repo" config user.name Test
git -C "$work/repo" config user.email test@example.invalid
git -C "$work/repo" commit -qm base --allow-empty
base=$(git -C "$work/repo" rev-parse HEAD)

check() {
  local expected=$1 label=$2 result=0
  git -C "$work/repo" add -A
  if [ "${3:-}" = executable ]; then
    git -C "$work/repo" update-index --chmod=+x "$4"
  fi
  git -C "$work/repo" commit -qm fixture --allow-empty
  bash "$validator" "$base" HEAD "$work/report.md" "$work/repo" > "$work/output" || result=$?
  if [ "$result" != "$expected" ]; then
    cat "$work/output"
    echo "FAIL: $label"
    exit 1
  fi
  echo "PASS: $label"
}

mkdir -p "$work/repo/reviews"
printf '{}\n' > "$work/repo/reviews/validator-reviews.json"
check 0 'Normal pack files are allowed'
base=$(git -C "$work/repo" rev-parse HEAD)

printf '#!/usr/bin/env bash\n' > "$work/repo/helper.sh"
check 1 'Executable files are rejected' executable helper.sh
base=$(git -C "$work/repo" rev-parse HEAD)

git -C "$work/repo" rm -fq helper.sh
check 0 'Normal file removal is allowed'

mkdir -p "$work/repo/.github/workflows"
printf 'on:\n  push:\n    paths: ["corpus/**", "glossary/**", "fonts/**", "pack.json"]\n' > "$work/repo/.github/workflows/release.yml"
git -C "$work/repo" add -A
git -C "$work/repo" commit -qm 'Release fixture'
base=$(git -C "$work/repo" rev-parse HEAD)

printf 'on:\n  push:\n    paths: ["corpus/**", "glossary/**", "fonts/**", "layouts/**", "pack.json"]\n' > "$work/repo/.github/workflows/release.yml"
check 0 'Supported release trigger update is allowed'
base=$(git -C "$work/repo" rev-parse HEAD)

printf 'jobs: {}\n' >> "$work/repo/.github/workflows/release.yml"
check 1 'Other workflow changes are rejected'
