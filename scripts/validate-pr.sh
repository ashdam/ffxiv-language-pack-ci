#!/usr/bin/env bash
# Checks the rows that a pull request changed. Writes the rejected rows to a report.
#
#   validate-pr.sh <base> <head> <source-dir> <report> [repo]
#
# The checks:
#   - Only .json files under corpus/ and glossary/ can change. New corpus files must match the source.
#   - A font under fonts/ may be added or replaced. It is a binary and has no further checks.
#   - A file is UTF-8 without BOM. Line ends are LF. The JSON is valid. No \u00XX escapes.
#   - A glossary file has no more checks. The checks below apply to corpus rows.
#   - Metadata stays as in main or matches the current English source exactly.
#   - A target is not a placeholder.
#   - The macros <...> in a target are a subset of the macros in the English row, plus the
#     `<if(gnum4,...)>` a gendered language has to add. `\<...>` is text, not a macro.
#   - A comma inside an <if(...)> branch is escaped.
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

  if [[ $path == .github/workflows/release.yml && $kind == M ]]; then
    # Allow only the layout path in the existing release trigger.
    mode=$(git -C "$repo" ls-tree "$head" -- "$path")
    before=$(git -C "$repo" show "$base:$path"; printf '.')
    after=$(git -C "$repo" show "$head:$path"; printf '.')
    old_trigger=$'\n    paths: ["corpus/**", "glossary/**", "fonts/**", "pack.json"]\n'
    new_trigger=$'\n    paths: ["corpus/**", "glossary/**", "fonts/**", "layouts/**", "pack.json"]\n'
    if [[ ${mode%% *} == 100644 && $before == *"$old_trigger"* && $after == "${before/"$old_trigger"/"$new_trigger"}" ]]; then
      changed_files=$((changed_files + 1))
      continue
    fi
  fi

  if [[ $path =~ ^layouts/[^/]+\.json$ ]]; then
    if [[ $kind != A && $kind != M && $kind != D ]]; then
      problems+=("\`$path\`: layout definitions may only be added, modified or removed.")
    elif [[ $kind != D ]]; then
      mode=$(git -C "$repo" ls-tree "$head" -- "$path")
      if [[ ${mode%% *} != 100644 ]]; then
        problems+=("\`$path\`: layout definitions must be regular non-executable files.")
      fi
    fi
    changed_files=$((changed_files + 1))
    continue
  fi

  # A font is a binary the pack serves as it is: it may be added or replaced, and nothing here can
  # read inside it. Everything else is a corpus or glossary .json.
  if [[ $path =~ ^fonts/[^/]+\.(fdt|tex)$ ]]; then
    if [ "$kind" = D ]; then
      problems+=("\`$path\`: a font is not removed by hand; the pack serves whatever \`fonts/\` holds.")
      continue
    fi
    changed_files=$((changed_files + 1))
    continue
  fi

  if ! [[ $path =~ ^(corpus/.+|glossary/[^/]+)\.json$ ]]; then
    problems+=("\`$path\`: only .json files under \`corpus/\` and \`glossary/\`, or a font under \`fonts/\`, change in a pull request.")
    continue
  fi

  if [ "$kind" != M ] && ! { [ "$kind" = A ] && [[ $path == corpus/* ]]; }; then
    problems+=("\`$path\`: only source-backed corpus files can be added; files cannot be removed or renamed.")
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

  # A glossary file carries `//` comment lines and is JSONC. A corpus file never does.
  parsed=$after
  if [[ $path == glossary/* ]]; then
    parsed=$work/parsed.json
    sed 's|^[[:space:]]*//.*$||' "$after" > "$parsed"
  fi

  if ! error=$(jq empty "$parsed" 2>&1); then
    problems+=("\`$path\`: is not valid JSON: ${error#jq: }")
    continue
  fi

  # A glossary file has no rows. Valid JSON is sufficient.
  if [[ $path == glossary/* ]]; then
    changed_files=$((changed_files + 1))
    continue
  fi

  before=$work/before.json
  english=$source/$path
  if [ "$kind" = A ]; then
    printf '{"entries":[]}\n' > "$before"
  else
    git -C "$repo" show "$base:$path" > "$before"
  fi

  if ! jq -e '
    type == "object" and (.entries | type == "array")
    and all(.entries[]; type == "object" and (.gameKey | type == "string")
      and (.hash | type == "string") and (.target | type == "string"))
    and (([.entries[].gameKey] | unique | length) == (.entries | length))
  ' "$after" > /dev/null; then
    problems+=("\`$path\`: invalid corpus rows or duplicate gameKey.")
    continue
  fi

  # Ignore the unused root questName field when comparing metadata.
  if ! jq -e -n --slurpfile b "$before" --slurpfile a "$after" '
    def metadata: del(.questName) | .entries |= map(del(.target));
    ($b[0] | metadata) == ($a[0] | metadata)
  ' > /dev/null; then
    if [ ! -f "$english" ]; then
      problems+=("\`$path\`: a corpus sync needs the English source. Merge the source sync first.")
      continue
    fi
    synced=$work/synced.json
    if ! jq -e --arg path "$path" --slurpfile b "$before" --slurpfile a "$after" '
      ($b[0].entries | map({key: .gameKey, value: .}) | from_entries) as $old
      | (.entries | map({key: .gameKey, value: .}) | from_entries) as $source
      | ($b[0].entries | map(.gameKey)) as $order
      | if $order == ($a[0].entries | map(.gameKey))
           and ($order | sort) == (.entries | map(.gameKey) | sort)
        then .entries = [$order[] | $source[.]] else . end
      | ($b[0] | del(.entries, .gameVersion, .conversation, .sheet, .questName))
        + (if $path | startswith("corpus/flat/") then {sheet: .conversation}
         else {conversation} end) + {gameVersion, entries: [.entries[] |
           . as $row | {gameKey, hash, target:
             (if $old[$row.gameKey].hash == $row.hash
              then ($old[$row.gameKey].target // "") else "" end)}]}
    ' "$english" > "$synced"; then
      problems+=("\`$path\`: cannot read the English source rows.")
      continue
    fi
    if ! jq -e -n --slurpfile s "$synced" --slurpfile a "$after" '
      def metadata: del(.questName) | .entries |= map(del(.target));
      ($s[0] | metadata) == ($a[0] | metadata)
    ' > /dev/null; then
      problems+=("\`$path\`: a sync must match the English version, keys and hashes, keep other existing header fields, and use the existing or source row order.")
      continue
    fi
    cp "$synced" "$before"
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
    # A `\<...>` is escaped text, not a macro: the emotes are translated and must not be counted.
    def macros: [scan("(?<![\\\\])<([A-Za-z]+)") | .[0]];
    def counts: group_by(.) | map({name: .[0], n: length});
    # A gendered language has to add `<if(gnum4,...)>` where the English needs no macro at all.
    def gendered: [scan("(?<![\\\\])<if\\(gnum4,")] | length;
    # Only the comma between the two branches may be bare: the game reads a second one as another
    # argument and drops the rest of the line.
    def loose_commas: [ scan("(?<![\\\\])<if\\((?:\\[[^\\]]*\\]|[A-Za-z0-9]+),([^<>()]*)\\)>") | .[0] ]
      | map(select((gsub("\\\\,"; "") | [scan(",")] | length) != 1)) | length;
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
                  + ( if ($target | test($placeholder)) and $target != $en[$new.gameKey] then
                        [["P", "`\($path)` `\($new.gameKey)`: `\($target)` is a placeholder, not a translation. Leave `target` empty until it is translated."]]
                      elif ($target | length) == 0 or $en[$new.gameKey] == null then []
                      else ($en[$new.gameKey] | macros | counts) as $wanted
                        | ($target | gendered) as $added
                        | [ ($target | macros | counts)[] as $macro
                            | ([$wanted[] | select(.name == $macro.name) | .n] | add // 0) as $allowed
                            # An added gender macro repeats whatever the sentence already carried,
                            # once per branch, so each English macro may appear once more per branch.
                            | ($allowed * (1 + $added)) as $repeated
                            | (if $macro.name == "if" then $repeated + $added else $repeated end) as $budget
                            | select($macro.n > $budget)
                            | ["P", "`\($path)` `\($new.gameKey)`: uses the macro `<\($macro.name)...>` \($macro.n) time(s); the English row has it \($allowed) time(s)."] ]
                        + ( ($target | loose_commas) as $loose
                            | if $loose > 0 then
                                [["P", "`\($path)` `\($new.gameKey)`: \($loose) `<if(...)>` branch(es) hold a bare comma; write it `\\,` or the game reads another argument and drops the rest of the line."]]
                              else [] end )
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
