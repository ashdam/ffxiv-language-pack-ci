# ffxiv-language-pack-ci

Shared Linux workflows for FFXIV language packs.

| Workflow | Use |
|---|---|
| `validate.yml` | Checks changed paths, corpus structure, content and optional ULD layouts on pull requests. |
| `release.yml` | Checks source sync, builds and publishes the pack, then commits coverage. |
| `sync.yml` | Syncs each pack and keeps its PR in draft until the full pack builds. |
| `check.yml` | Runs actionlint and checks the shared Dalamud setup. |

## Setup

Each pack defines its triggers and calls the reusable workflows in this repository's `.github/workflows/`.
Pack identity comes from `pack.json`. The optional `language` input checks an expected language.

Protect `.github/` with CODEOWNERS and required code owner reviews. Dismiss approvals after new commits.
Keep automatic PR merging disabled.

## Validation

CorpusValidator checks corpus structure, content and metadata. PackBuilder checks optional ULD layouts against game files.
The explicit rule list in `validate.yml` checks LP structure, source alignment, metadata, glossary files,
review files, macro syntax, speaker labels, icons and banner textures. Linguistic and heuristic rules are not selected.
Tools is pinned to a commit that supports the selected rule names and parameters.
Banner variants and dimensions use `metadata/banner-textures.json` and `ffxivgame.ver` from game-sheets.
The workflow sets `sheets` under `[common]` in its generated `tools.ini`. No installed game is required.
Changed data files must be regular and non-executable. Workflow changes require code owner approval.
The run summary and PR comment show the results table and a link to the complete JSON report as a ZIP artifact.

## Publication

Release checks source sync, builds the pack and publishes it through GitHub Actions.
It commits `coverage.json`; this file must not trigger another release. Releases for one pack run sequentially.

## Dependencies and permissions

| Setting | Use |
|---|---|
| `CI_READ_TOKEN` | Reads Tools and game sheets. Required for release; validation can fall back to the workflow token. |
| `CI_MERGE_TOKEN` | Writes coverage. |
| `reader-client-id`, `LOCALIZATION_READER_PRIVATE_KEY` | Authenticates the Reader App for Tools and exported sheets. |
| `writer-client-id`, `LOCALIZATION_WRITER_PRIVATE_KEY` | Authenticates the Writer App for language packs. |

Pass App credentials from the source repository. Install Reader only on Tools and exported game sheets, with read-only contents access.
Install Writer only on language packs, with contents and pull request write access.
Sync opens a draft PR before the build and marks it ready only after the sync and full pack checks pass. Write tokens cover one pack.
Fix layouts in `sync/corpus-en` and rerun sync. Pending corpus, exclusion and layout changes are preserved; merge conflicts stop the run.

Treat PR files as data. Run validation code from trusted CI and Tools checkouts, without stored Git credentials.
Pin external actions by commit. The shared `actions/setup-dalamud` action verifies the runtime archive checksum.
