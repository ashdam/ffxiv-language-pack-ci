#!/usr/bin/env bash
set -euo pipefail
validator=$(cd "$(dirname "$0")/../scripts" && pwd)/validate-pr.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/corpus/flat" "$work/source/corpus/flat"
git -C "$work/repo" init -q
git -C "$work/repo" config user.name Test
git -C "$work/repo" config user.email test@example.invalid
cat > "$work/repo/corpus/flat/Action.json" <<'JSON'
{"sheet":"Action","questName":"Existing label","gameVersion":"1","entries":[{"gameKey":"Action#1","hash":"old","target":"<br>"},{"gameKey":"Action#2","hash":"retired","target":"Retired"}]}
JSON
git -C "$work/repo" add -A
git -C "$work/repo" commit -qm base
base=$(git -C "$work/repo" rev-parse HEAD)
cat > "$work/source/corpus/flat/Action.json" <<'JSON'
{"schemaVersion":2,"sourceLanguage":"en","conversation":"Action","gameVersion":"2","entries":[{"gameKey":"Action#1","hash":"new","en":"Hello"},{"gameKey":"Action#3","hash":"added","en":"Bye"}]}
JSON
jq '{sheet: .conversation, questName: "Existing label", gameVersion, entries: [.entries[] | {gameKey, hash, target: "Hola"}]}' \
  "$work/source/corpus/flat/Action.json" > "$work/valid.json"
check() {
  local expected=$1 label=$2 result=0
  git -C "$work/repo" add -A
  git -C "$work/repo" commit -qm fixture --allow-empty
  bash "$validator" "$base" HEAD "$work/source" "$work/report.md" "$work/repo" > "$work/output" || result=$?
  if [ "$result" != "$expected" ]; then
    cat "$work/output"
    echo "FAIL: $label (exit $result, expected $expected)"
    exit 1
  fi
  echo "PASS: $label"
}
cp "$work/valid.json" "$work/repo/corpus/flat/Action.json"
check 0 'flat sheet sync with added, retired and rewritten rows'
for change in \
  '.entries[0].hash = "invented"' \
  '.entries[0].gameKey = "Action#999"' \
  '.entries |= reverse' \
  '.entries |= .[:1]' \
  '.entries += [.entries[0]]' \
  '.gameVersion = "1"' \
  '.sheet = "Wrong"' \
  '.extra = "unexpected"' \
  '.questName = "Changed label"' \
  '.entries[0].target = 12' \
  '.entries[0].target = "<br>"' \
  '.entries[0].target = "TODO"'; do
  jq "$change" "$work/valid.json" > "$work/repo/corpus/flat/Action.json"
  check 1 "$change"
done
cp "$work/valid.json" "$work/repo/corpus/flat/Action.json"
check 0 'valid sync restored'
base=$(git -C "$work/repo" rev-parse HEAD)
jq '.entries[0].target = "Saludos"' "$work/valid.json" > "$work/repo/corpus/flat/Action.json"
check 0 'translation edit after sync'
jq '.gameVersion = "3" | .entries[0].hash = "future"' \
  "$work/source/corpus/flat/Action.json" > "$work/new-source.json"
cp "$work/new-source.json" "$work/source/corpus/flat/Action.json"
check 0 'ordinary translation edit does not require an unrelated patch sync'
mkdir -p "$work/repo/corpus/quest" "$work/source/corpus/quest"
cat > "$work/source/corpus/quest/New.json" <<'JSON'
{"conversation":"quest/New","gameVersion":"3","entries":[{"gameKey":"quest/New#1","hash":"quest","en":"Hello"}]}
JSON
jq '{conversation, gameVersion, entries: [.entries[] | {gameKey, hash, target: "Hola"}]}' \
  "$work/source/corpus/quest/New.json" > "$work/repo/corpus/quest/New.json"
check 0 'new quest keeps the conversation header'

cat > "$work/source/corpus/quest/Legacy.json" <<'JSON'
{"conversation":"quest/Legacy","gameVersion":"3","entries":[{"gameKey":"Legacy#1","hash":"one","en":"One"},{"gameKey":"Legacy#2","hash":"two","en":"Two"},{"gameKey":"Legacy#3","hash":"three","en":"Three"}]}
JSON
jq '{conversation, questName: "Existing quest", gameVersion: "2", entries: [.entries[] | {gameKey, hash, target: "Hola"}] | reverse}' \
  "$work/source/corpus/quest/Legacy.json" > "$work/repo/corpus/quest/Legacy.json"
git -C "$work/repo" add -A
git -C "$work/repo" commit -qm baseline
base=$(git -C "$work/repo" rev-parse HEAD)
jq '.gameVersion = "3"' "$work/repo/corpus/quest/Legacy.json" > "$work/legacy.json"
cp "$work/legacy.json" "$work/repo/corpus/quest/Legacy.json"
check 0 'version sync preserves an existing quest name and row order'
for change in \
  '.questName = "Wrong quest"' \
  '.entries = [.entries[1], .entries[2], .entries[0]]' \
  '.entries[0].hash = "invented"' \
  '.entries |= .[:2]'; do
  jq "$change" "$work/legacy.json" > "$work/repo/corpus/quest/Legacy.json"
  check 1 "legacy: $change"
done
jq '.entries |= reverse' "$work/legacy.json" > "$work/repo/corpus/quest/Legacy.json"
check 0 'sync may adopt the exact source order'
