# ffxiv-language-pack-ci

Shared Linux workflows for FFXIV language packs.

| Workflow | Use |
|---|---|
| `validate.yml` | Validates LP data on pull requests and manual runs. Checks changed paths and optional ULD layouts on pull requests. |
| `release.yml` | Checks source sync, builds and publishes the pack, then commits coverage. |
| `sync.yml` | Syncs each pack and keeps its PR in draft until the full pack builds. |
| `check.yml` | Runs actionlint and checks the shared Dalamud setup. |

## Setup

Each pack defines its triggers and calls the reusable workflows in this repository's `.github/workflows/`.
Pack identity comes from `pack.json`. The optional `language` input checks an expected language.

## Validation

CorpusValidator checks corpus structure, content and metadata. PackBuilder checks optional ULD layouts against game files.
The explicit rule list in `validate.yml` checks LP structure, source alignment, metadata, glossary files,
review files, macro syntax, speaker labels, icons, FATE name references, place names and banner textures.
Other linguistic and heuristic rules are not selected.
Tools is read from `main` and must support the selected rule names and parameters.

For manual validation, add `workflow_dispatch` to the pack's validation workflow and pass its optional
`rules` string input to this workflow. Select the LP branch with **Use workflow from** in GitHub Actions.
Use comma-separated rule names, such as `lp-terminology-drift-fates,lp-terminology-drift-placenames`.
An empty value uses the CI rule list. Pull requests always use the CI rule list.
Manual runs validate the full selected branch. Baseline checks compare it with the repository's default branch.
Path restrictions, ULD layout validation and PR comments run only for pull requests. Validation does not modify LP files.

Banner variants and dimensions use `metadata/banner-textures.json` and `ffxivgame.ver` from game-sheets.
The workflow sets `sheets` under `[common]` in its generated `tools.ini`. No installed game is required.
Changed data files must be regular and non-executable.
The run summary and PR comment show the results table and a link to the complete JSON report as a ZIP artifact.

## Publication

Release checks source sync, builds the pack and publishes it through GitHub Actions.
It commits `coverage.json`; this file must not trigger another release. Releases for one pack run sequentially.

## Dependencies and permissions

| Setting | Use |
|---|---|
| `CI_READ_TOKEN` | Reads Tools and game sheets. Required for release; validation can fall back to the workflow token. |
| `LOCALIZATION_WRITER_CLIENT_ID`, `LOCALIZATION_WRITER_PRIVATE_KEY` | Authenticates the Writer App to update coverage in the calling pack. |
| `reader-client-id`, `LOCALIZATION_READER_PRIVATE_KEY` | Authenticates the Reader App for Tools and exported sheets. |
| `writer-client-id`, `LOCALIZATION_WRITER_PRIVATE_KEY` | Authenticates the Writer App for language packs. |

Set the sync App credentials in the source repository and the release Writer credentials in each pack repository.
Sync opens a draft PR before the build and marks it ready only after the sync and full pack checks pass. Write tokens cover one pack.
Fix layouts in `sync/corpus-en` and rerun sync. Pending corpus, exclusion and layout changes are preserved; merge conflicts stop the run.
