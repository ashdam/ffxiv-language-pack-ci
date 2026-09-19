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
  if [ "${3:-}" = executable ]; then git -C "$work/repo" update-index --chmod=+x "${4:-layouts/example.json}"; fi
  if [ "${3:-}" = regular ]; then git -C "$work/repo" update-index --chmod=-x "${4:-layouts/example.json}"; fi
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
base=$(git -C "$work/repo" rev-parse HEAD)
printf 'on:\n  push:\n    paths: ["corpus/**", "glossary/**", "fonts/**", "layouts/**", "ui/**", "pack.json"]\n' > "$work/repo/.github/workflows/release.yml"
check 0 'Texture release trigger is allowed'
printf 'jobs: {}\n' >> "$work/repo/.github/workflows/release.yml"
check 1 'Other workflow changes are rejected'

printf '# Language pack\n' > "$work/repo/README.md"
git -C "$work/repo" add -A
git -C "$work/repo" commit -qm 'README fixture'
base=$(git -C "$work/repo" rev-parse HEAD)
printf 'Pack documentation.\n' >> "$work/repo/README.md"
check 0 'README edits are allowed'
check 1 'Executable README is rejected' executable README.md
git -C "$work/repo" rm -fq README.md
check 1 'README removal is rejected'

mkdir -p "$work/repo/glossary"
printf '{"language":"es-ES"}\n' > "$work/repo/pack.json"
git -C "$work/repo" add -A
git -C "$work/repo" commit -qm 'Pack fixture'
base=$(git -C "$work/repo" rev-parse HEAD)
printf '{"entries":[]}\n' > "$work/repo/glossary/placename-override.json"
printf '{"exclusion_groups":[]}\n' > "$work/repo/glossary/excluded-rows.json"
printf '{"language":"es-es"}\n' > "$work/repo/pack.json"
check 0 'Language policy files and pack edits are allowed'
check 1 'Executable pack metadata is rejected' executable pack.json
check 0 'Regular pack metadata is allowed' regular pack.json
printf '{}\n' > "$work/repo/glossary/unknown.json"
check 1 'Other glossary additions are rejected'
git -C "$work/repo" rm -q glossary/unknown.json
check 0 'Valid glossary paths are restored'
base=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" rm -q glossary/placename-override.json
check 1 'Place glossary removal is rejected'
base=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" rm -q pack.json
check 1 'Pack metadata removal is rejected'

base=$(git -C "$work/repo" rev-parse HEAD)
mkdir -p "$work/repo/ui/icon/120000/en" "$work/repo/ui/icon/121000/en"
printf 'sd' > "$work/repo/ui/icon/120000/en/120021.tex"
printf 'hd' > "$work/repo/ui/icon/121000/en/121001_hr1.tex"
check 0 'Both banner folders and resolutions are allowed'
check 1 'Executable texture is rejected' executable ui/icon/120000/en/120021.tex
check 0 'Regular texture is allowed' regular ui/icon/120000/en/120021.tex
printf 'wrong folder' > "$work/repo/ui/icon/120000/en/121001.tex"
check 1 'Texture in the wrong icon folder is rejected'
git -C "$work/repo" rm -q ui/icon/120000/en/121001.tex
printf 'preview' > "$work/repo/ui/icon/120000/en/120021.png"
check 1 'Texture preview is rejected'
git -C "$work/repo" rm -q ui/icon/120000/en/120021.png
mkdir -p "$work/repo/ui/icon/120000/fr"
printf 'fr' > "$work/repo/ui/icon/120000/fr/120021.tex"
check 1 'Unsupported texture language is rejected'
git -C "$work/repo" rm -q ui/icon/120000/fr/120021.tex
check 0 'Only valid textures remain'
base=$(git -C "$work/repo" rev-parse HEAD)
git -C "$work/repo" rm -q ui/icon/120000/en/120021.tex
check 0 'Texture removal is allowed'
