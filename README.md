# ffxiv-language-pack-ci

Shared Linux workflows for `ffxiv-language-pack-<code>` repositories. .NET uses SDK 10; run steps use Bash.

| Workflow | Use |
|---|---|
| `validate.yml` | Checks changed paths, corpus structure, content and optional ULD layouts on pull requests. |
| `release.yml` | Checks source sync, builds and publishes the pack, then commits coverage. |
| `auto-merge.yml` | Enables auto-merge. Branch rules enforce checks and reviews. |
| `check.yml` | Runs actionlint and checks the shared Dalamud setup. |

## Language repositories

Copy `validate.yml` and `release.yml` from `workflows/` verbatim to each language repository’s `.github/workflows/`.
Copy `auto-merge.yml` only to Italian, Polish and Brazilian Portuguese. Spanish has no auto-merge workflow.
The workflows read the language and repository from `pack.json`. The optional shared `language` input checks an expected language.

Keep the required reviews and checks in repository rules. `pull_request_target` does not check out or run PR content.

## Validation

The validation workflow checks changed paths against the PR merge base before it downloads dependencies.
Workflow edits must match a file in the shared `workflows/` directory. Data files must be regular, non-executable files.
Renames are rejected except `glossary/excluded-rows.json` to `inventory-exclusions.json`.

CorpusValidator checks source and target structure, content and baseline metadata without the game.
PackBuilder checks layout definitions against original game files. Only declared font-size bytes may change.
The summary contains path and content reports. The PR comment contains the content report.

## Publication

GitHub Actions is the only publication path. A local build does not publish.
Release verifies source sync and packaged ULD files. The build stamp must match clean source commits and the manifest inside the ZIP.
Release notes use corpus commits since the published manifest. Spanish notes use Spanish; other packs use English.

PackBuilder writes coverage beside the archive. After publication, Release commits that file as `coverage.json`.
The release path filter excludes `coverage.json` to prevent another release. Concurrent releases for one repository do not run together.

## Dependencies and permissions

| Setting | Use |
|---|---|
| `CI_READ_TOKEN` | Reads Tools and game sheets. Required for release; validation can fall back to the workflow token. |
| `CI_MERGE_TOKEN` | Writes coverage and enables auto-merge. |

PR files are data. Validation code comes from CI and Tools; checkouts do not retain credentials.
External actions are pinned by commit. `actions/setup-dalamud` verifies the pinned archive SHA-256 and caches its contents.
Tools builds, layout validation and pack releases use that action.
