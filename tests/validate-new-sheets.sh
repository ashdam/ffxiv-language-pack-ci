#!/usr/bin/env bash
set -euo pipefail

validator=$(cd "$(dirname "$0")/../scripts" && pwd)/validate-pr.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/corpus" "$work/source/corpus"
git -C "$work/repo" init -q
git -C "$work/repo" config user.name Test
git -C "$work/repo" config user.email test@example.invalid
git -C "$work/repo" commit -qm base --allow-empty
base=$(git -C "$work/repo" rev-parse HEAD)
cat > "$work/source/corpus/Opening.json" <<'JSON'
{"schemaVersion":2,"sourceLanguage":"en","conversation":"Opening","gameVersion":"1","entries":[{"gameKey":"Opening#1","hash":"abc","en":"Hear..."},{"gameKey":"Opening#2","hash":"def","en":"Think..."}]}
JSON
jq '{conversation, gameVersion, entries: [.entries[] | {gameKey, hash, target: "Escucha..."}]}' \
  "$work/source/corpus/Opening.json" > "$work/valid.json"

check() {
  local expected=$1 label=$2
  git -C "$work/repo" add -A
  git -C "$work/repo" commit -qm fixture --allow-empty
  local result=0
  bash "$validator" "$base" HEAD "$work/source" "$work/report.md" "$work/repo" > "$work/output" || result=$?
  if [ "$result" != "$expected" ]; then
    cat "$work/output"
    echo "FAIL: $label (exit $result, expected $expected)"
    exit 1
  fi
  echo "PASS: $label"
}

cp "$work/valid.json" "$work/repo/corpus/Opening.json"
check 0 'new sheet matches source'
mv "$work/source/corpus/Opening.json" "$work/source/hidden.json"
check 1 'missing source'
mv "$work/source/hidden.json" "$work/source/corpus/Opening.json"
for change in \
  '.entries[0].hash = "wrong"' \
  '.entries[0].gameKey = "wrong"' \
  '.entries |= reverse' \
  '.entries |= .[:1]' \
  '.gameVersion = "wrong"' \
  '.entries[0].target = "<br>"' \
  '.entries[0].target = "TODO"'; do
  jq "$change" "$work/valid.json" > "$work/repo/corpus/Opening.json"
  check 1 "$change"
done
cp "$work/valid.json" "$work/repo/corpus/Opening.json"
check 0 'valid sheet restored'
base=$(git -C "$work/repo" rev-parse HEAD)
jq '.entries[0].target = "Piensa..."' "$work/valid.json" > "$work/repo/corpus/Opening.json"
check 0 'existing translation update'
git -C "$work/repo" rm -q corpus/Opening.json
check 1 'deleted sheet'
