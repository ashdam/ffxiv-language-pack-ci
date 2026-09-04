<#
.SYNOPSIS
    Checks the rows a pull request changed, and writes the rejected ones to a report.

.DESCRIPTION
    What a contributor can break without the tools, checked without the tools:

      - only files under corpus/ change, and none is added or removed: the sync does that
      - a file is UTF-8 without BOM, LF, valid JSON, with no \u00XX escapes
      - the header and every gameKey, hash and row position are exactly what main has; only
        `target` differs
      - a target is not a placeholder standing in for a translation
      - the macros <...> a target carries are a subset of the English row's

    Exit 1 with the report written when anything is rejected; exit 0 and no report otherwise.

.PARAMETER Base
    The commit the pull request is against.

.PARAMETER Head
    The pull request's commit.

.PARAMETER Source
    The English corpus checkout: <Source>/corpus mirrors this repository's corpus/.

.PARAMETER Report
    Where the markdown report goes. Only written when something is rejected.

.PARAMETER Repo
    The language repository checkout. Default: the working directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Base,
    [Parameter(Mandatory)] [string] $Head,
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Report,
    [string] $Repo = '.'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# The bytes of a file at a commit. Native output through the pipeline is text in the console's
# encoding; a byte check needs the stream itself.
function Get-GitBlob([string] $Revision, [string] $Path) {
    $start = [System.Diagnostics.ProcessStartInfo]::new('git', "-C `"$Repo`" show `"${Revision}:$Path`"")
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($start)
    $memory = [System.IO.MemoryStream]::new()
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "git show ${Revision}:$Path failed." }
    return $memory.ToArray()
}

# Macro names in a string: `<if(`, `<br>`, `<nbsp>`, `<italic(`. The name is what a translation
# has to keep; the arguments carry text the translator may change.
function Get-MacroNames([string] $Text) {
    return [regex]::Matches($Text, '<([A-Za-z]+)') | ForEach-Object { $_.Groups[1].Value }
}

# Placeholders somebody typed instead of a translation. An empty target is the placeholder here,
# and text that is not a translation reaches the player.
$placeholder = '^\s*(TODO|WIP|TBD|FIXME|XXX|PENDIENTE|N/?A|\?+|-+|\.+|\[[^\]]*\])\s*$'

$problems = [System.Collections.Generic.List[string]]::new()
$changedRows = 0
$changedFiles = 0

$status = & git -C $Repo diff --name-status $Base $Head
if ($LASTEXITCODE -ne 0) { throw "git diff $Base $Head failed." }

foreach ($line in @($status)) {
    if (-not $line) { continue }
    $fields = $line -split "`t"
    $kind = $fields[0].Substring(0, 1)
    $path = $fields[-1]

    if ($path -notmatch '^corpus/.+\.json$') {
        $problems.Add("``$path``: only files under ``corpus/`` change in a pull request.")
        continue
    }

    if ($kind -ne 'M') {
        $problems.Add("``$path``: files are not added, removed or renamed by hand; the sync against the game does that.")
        continue
    }

    $bytes = Get-GitBlob $Head $path
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $problems.Add("``$path``: carries a UTF-8 BOM; save it without one.")
        continue
    }

    if ($bytes -contains 0x0D) {
        $problems.Add("``$path``: has CRLF line endings; the corpus is LF.")
        continue
    }

    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text -match '\\u00[0-9a-fA-F]{2}') {
        $problems.Add("``$path``: escapes characters as ``\u00XX``; write them as they are.")
        continue
    }

    try { $after = $text | ConvertFrom-Json -AsHashtable }
    catch { $problems.Add("``$path``: is not valid JSON: $($_.Exception.Message)"); continue }

    $before = [System.Text.Encoding]::UTF8.GetString((Get-GitBlob $Base $path)) | ConvertFrom-Json -AsHashtable

    foreach ($key in ($before.Keys + $after.Keys | Sort-Object -Unique)) {
        if ($key -eq 'entries') { continue }
        if (-not $before.ContainsKey($key) -or -not $after.ContainsKey($key) -or "$($before[$key])" -cne "$($after[$key])") {
            $problems.Add("``$path``: the header field ``$key`` changed; only ``target`` changes in a pull request.")
        }
    }

    if ($before.entries.Count -ne $after.entries.Count) {
        $problems.Add("``$path``: has $($after.entries.Count) rows where main has $($before.entries.Count); rows are neither added nor removed.")
        continue
    }

    # The English rows of the same file, by gameKey, for the macro check.
    $english = @{}
    $sourceFile = Join-Path $Source $path
    if (Test-Path $sourceFile) {
        foreach ($row in ((Get-Content $sourceFile -Raw -Encoding utf8) | ConvertFrom-Json -AsHashtable).entries) {
            $english[$row.gameKey] = if ($row.ContainsKey('macro') -and $row.macro) { $row.macro } else { $row.en }
        }
    }

    $fileChanged = $false
    for ($i = 0; $i -lt $after.entries.Count; $i++) {
        $old = $before.entries[$i]
        $new = $after.entries[$i]

        if ($old.gameKey -cne $new.gameKey -or $old.hash -cne $new.hash) {
            $problems.Add("``$path`` row $($i + 1): ``gameKey`` or ``hash`` changed (``$($old.gameKey)``); those identify the line and are never edited.")
            continue
        }

        foreach ($key in $new.Keys) {
            if ($key -notin 'gameKey', 'hash', 'target') {
                $problems.Add("``$path`` ``$($new.gameKey)``: carries a field ``$key`` the corpus does not have.")
            }
        }

        if ("$($old.target)" -ceq "$($new.target)") { continue }
        $changedRows++
        $fileChanged = $true
        $target = "$($new.target)"

        if ($target -match $placeholder) {
            $problems.Add("``$path`` ``$($new.gameKey)``: ``$target`` is a placeholder, not a translation. Leave ``target`` empty until it is translated.")
            continue
        }

        if ($target.Length -eq 0) { continue }

        if ($english.ContainsKey($new.gameKey)) {
            $wanted = @(Get-MacroNames $english[$new.gameKey] | Group-Object | ForEach-Object { @{ Name = $_.Name; Count = $_.Count } })
            $have = Get-MacroNames $target | Group-Object
            foreach ($macro in $have) {
                $allowed = ($wanted | Where-Object { $_.Name -ceq $macro.Name } | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
                if ($macro.Count -gt $allowed) {
                    $problems.Add("``$path`` ``$($new.gameKey)``: uses the macro ``<$($macro.Name)...>`` $($macro.Count) time(s); the English row has it $allowed time(s).")
                }
            }
        }
    }

    if ($fileChanged) { $changedFiles++ }
}

if ($problems.Count -eq 0) {
    Write-Host "$changedRows row(s) changed in $changedFiles file(s); nothing rejected."
    exit 0
}

$lines = @("**$($problems.Count) thing(s) to fix before this can merge.** $changedRows row(s) changed in $changedFiles file(s).", '')
$lines += $problems | ForEach-Object { "- $_" }
[System.IO.File]::WriteAllLines($Report, $lines, [System.Text.UTF8Encoding]::new($false))
$lines | ForEach-Object { Write-Host $_ }
exit 1
