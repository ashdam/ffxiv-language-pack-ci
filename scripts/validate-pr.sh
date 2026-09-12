#!/usr/bin/env bash
# validate-pr.sh <base> <head> <report> [repo]
# CorpusValidator checks content. This script checks changed paths and file modes.
set -euo pipefail
base=$1
head=$2
report=$3
repo=${4:-.}
base=$(git -C "$repo" rev-parse --verify "$base^{commit}")
head=$(git -C "$repo" rev-parse --verify "$head^{commit}")
problems=()
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  kind=${status:0:1}
  if [[ $kind = R || $kind = C ]]; then
    IFS= read -r -d '' destination
    problems+=("Renamed or copied path: $path -> $destination")
    continue
  fi
  if [[ $path == .github/workflows/release.yml && $kind == M ]]; then
    # Allow only the layout path in the existing release trigger.
    if [[ $kind == D ]]; then continue; fi
  mode=$(git -C "$repo" ls-tree "$head" -- "$path")
    before=$(git -C "$repo" show "$base:$path"; printf '.')
    after=$(git -C "$repo" show "$head:$path"; printf '.')
    old_trigger=$'\n    paths: ["corpus/**", "glossary/**", "fonts/**", "pack.json"]\n'
    new_trigger=$'\n    paths: ["corpus/**", "glossary/**", "fonts/**", "layouts/**", "pack.json"]\n'
    if [[ ${mode%% *} == 100644 && $before == *"$old_trigger"* && $after == "${before/"$old_trigger"/"$new_trigger"}" ]]; then
      continue
    fi
  fi

  if [[ $path =~ ^corpus/.+\.json$ ]]; then
    allowed='AM'
  elif [[ $path =~ ^glossary/[^/]+\.json$ ]]; then
    allowed='M'
  elif [[ $path == review/toponimos-decisiones.csv || $path == review/toponimos.md ]]; then
    allowed='AM'
  elif [[ $path =~ ^layouts/[^/]+\.json$ ]]; then
    allowed='AMD'
  elif [[ $path =~ ^fonts/[^/]+\.(fdt|tex)$ ]]; then
    allowed='AM'
  else
    problems+=("Path is not permitted: $path")
    continue
  fi
  if [[ $allowed != *"$kind"* ]]; then
    problems+=("Operation $kind is not permitted: $path")
    continue
  fi
  if [[ $kind == D ]]; then continue; fi
  mode=$(git -C "$repo" ls-tree "$head" -- "$path")
  if [[ ${mode%% *} != 100644 ]]; then
    problems+=("Data must be a regular non-executable file: $path")
  fi
done < <(git -C "$repo" diff --name-status -z --find-renames "$base" "$head" --)
if ((${#problems[@]})); then
  printf '**Path restrictions failed.**\n\n' > "$report"
  printf '%s\n' "${problems[@]}" >> "$report"
  cat "$report"
  exit 1
fi
printf 'Changed paths satisfy the repository restrictions.\n' > "$report"
