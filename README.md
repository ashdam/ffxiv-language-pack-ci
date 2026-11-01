# ffxiv-language-pack-ci

Shared Linux workflows for FFXIV language packs.

| Workflow | Use |
|---|---|
| `validate.yml` | Checks changed paths, corpus structure, content and optional ULD layouts on pull requests. |
| `release.yml` | Checks source sync, builds and publishes the pack, then commits coverage. |
| `sync.yml` | Syncs each pack from its main branch and opens or updates one pull request. |
| `check.yml` | Runs actionlint and checks the shared Dalamud setup. |

## Setup

Each pack defines its triggers and calls the reusable workflows in this repository's `.github/workflows/`.
Pack identity comes from `pack.json`. The optional `language` input checks an expected language.

Protect `.github/` with CODEOWNERS and required code owner reviews. Dismiss approvals after new commits.
Keep automatic PR merging disabled.

## Validation

CorpusValidator checks corpus structure, content and metadata. PackBuilder checks optional ULD layouts against game files.
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
Sync builds changed packs before it opens a PR. Write tokens cover one pack.
The `sync/corpus-en` branch is managed by the sync workflow. Keep manual changes on other branches.

Treat PR files as data. Run validation code from trusted CI and Tools checkouts, without stored Git credentials.
Pin external actions by commit. The shared `actions/setup-dalamud` action verifies the runtime archive checksum.
