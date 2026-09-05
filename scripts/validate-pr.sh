#!/usr/bin/env bash
# Checks the rows that a pull request changed. Writes the rejected rows to a report.
#
#   validate-pr.sh <base> <head> <source-dir> <report> [repo]
#
# The checks:
#   - Only .json files under corpus/ and glossary/ can change. No file is added or removed.
#   - A file is UTF-8 without BOM. Line ends are LF. The JSON is valid. No \u00XX escapes.
#   - A glossary file has no more checks. The checks below apply to corpus rows.
#   - The header, each gameKey, each hash and the row order are the same as in main.
#     Only `target` can change.
#   - A target is not a placeholder.
#   - The macros <...> in a target are a subset of the macros in the English row.
#
# <source-dir>/corpus mirrors corpus/ in the repository. Exit code 1 and a report when a check
# fails. Exit code 0 and no report when all checks pass. Needs git and jq.
set -euo pipefail

base=$1
head=$2
source=$3
report=$4
repo=${5:-.}

# Text that is not a translation. An empty target is the correct placeholder.
placeholder='^\s*(TODO|WIP|TBD|FIXME|XXX|PENDIENTE|N/?A|\?+|-+|\.+|\[[^\]]*\])\s*$'

problems=()
changed_rows=0
changed_files=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

while IFS=$'\t' read -r status path_a path_b; do
  [ -n "$status" ] || continue
  kind=${status:0:1}
  path=${path_b:-$path_a}

  if ! [[ $path =~ ^(corpus/.+|glossary/[^/]+)\.json$ ]]; then
    problems+=("\`$path\`: only .json files under \`corpus/\` and \`glossary/\` change in a pull request.")
    continue
  fi

  if [ "$kind" != M ]; then
    problems+=("\`$path\`: files are not added, removed or renamed by hand; the sync against the game does that.")
    continue
  fi

  after=$work/after.json
  git -C "$repo" show "$head:$path" > "$after"

  if [ "$(head -c 3 "$after" | od -An -tx1 | tr -d ' \n')" = efbbbf ]; then
    problems+=("\`$path\`: carries a UTF-8 BOM; save it without one.")
    continue
  fi

  if grep -q $'\r' "$after"; then
    problems+=("\`$path\`: has CRLF line endings; the corpus is LF.")
    continue
  fi

  if grep -qE '\\u00[0-9a-fA-F]{2}' "$after"; then
    problems+=("\`$path\`: escapes characters as \`\\u00XX\`; write them as they are.")
    continue
  fi

  if ! error=$(jq empty "$after" 2>&1); then
    problems+=("\`$path\`: is not valid JSON: ${error#jq: }")
    continue
  fi

  # A glossary file has no rows. Valid JSON is sufficient.
  if [[ $path == glossary/* ]]; then
    changed_files=$((changed_files + 1))
    continue
  fi

  before=$work/before.json
  git -C "$repo" show "$base:$path" > "$before"

  while IFS= read -r key; do
    problems+=("\`$path\`: the header field \`$key\` changed; only \`target\` changes in a pull request.")
  done < <(jq -r -n --slurpfile b "$before" --slurpfile a "$after" '
    ($b[0] | del(.entries)) as $old | ($a[0] | del(.entries)) as $new
    | (($old | keys) + ($new | keys) | unique)[] | select($old[.] != $new[.])')

  count_before=$(jq '.entries | length' "$before")
  count_after=$(jq '.entries | length' "$after")
  if [ "$count_before" != "$count_after" ]; then
    problems+=("\`$path\`: has $count_after rows where main has $count_before; rows are neither added nor removed.")
    continue
  fi

  # The English rows of the same file, by gameKey, for the macro check. No file: no macro check.
  english=$source/$path
  [ -f "$english" ] || english=/dev/null

  # One line for each result: "C" for a changed row, "P<tab>message" for a problem.
  file_changed=0
  while IFS=$'\t' read -r tag message; do
    case $tag in
      C) changed_rows=$((changed_rows + 1)); file_changed=1 ;;
      P) problems+=("$message") ;;
    esac
  done < <(jq -r -n --slurpfile b "$before" --slurpfile a "$after" --slurpfile e "$english" \
      --arg path "$path" --arg placeholder "$placeholder" '
    def macros: [scan("<([A-Za-z]+)") | .[0]];
    def counts: group_by(.) | map({name: .[0], n: length});
    (($e[0].entries // []) | map({key: .gameKey, value: (if (.macro // "") != "" then .macro else .en end)}) | from_entries) as $en
    | [range(0; $a[0].entries | length) as $i
        | $b[0].entries[$i] as $old | $a[0].entries[$i] as $new
        | if $old.gameKey != $new.gameKey or $old.hash != $new.hash then
            [["P", "`\($path)` row \($i + 1): `gameKey` or `hash` changed (`\($old.gameKey)`); those identify the line and are never edited."]]
          else
            [ $new | keys[] | select(. != "gameKey" and . != "hash" and . != "target")
              | ["P", "`\($path)` `\($new.gameKey)`: carries a field `\(.)` the corpus does not have."] ]
            + ( if ($old.target // "") == ($new.target // "") then []
                else ($new.target // "") as $target
                  | [["C", ""]]
                  + ( if ($target | test($placeholder)) then
                        [["P", "`\($path)` `\($new.gameKey)`: `\($target)` is a placeholder, not a translation. Leave `target` empty until it is translated."]]
                      elif ($target | length) == 0 or $en[$new.gameKey] == null then []
                      else ($en[$new.gameKey] | macros | counts) as $wanted
                        | [ ($target | macros | counts)[] as $macro
                            | ([$wanted[] | select(.name == $macro.name) | .n] | add // 0) as $allowed
                            | select($macro.n > $allowed)
                            | ["P", "`\($path)` `\($new.gameKey)`: uses the macro `<\($macro.name)...>` \($macro.n) time(s); the English row has it \($allowed) time(s)."] ]
                      end )
                end )
          end ]
    | flatten(1)[] | "\(.[0])\t\(.[1])"')

  [ "$file_changed" = 1 ] && changed_files=$((changed_files + 1))
done < <(git -C "$repo" diff --name-status "$base" "$head")

if [ ${#problems[@]} -eq 0 ]; then
  echo "$changed_rows row(s) changed in $changed_files file(s); nothing rejected."
  exit 0
fi

{
  echo "**${#problems[@]} thing(s) to fix before this can merge.** $changed_rows row(s) changed in $changed_files file(s)."
  echo
  for problem in "${problems[@]}"; do echo "- $problem"; done
} > "$report"
cat "$report"
exit 1
