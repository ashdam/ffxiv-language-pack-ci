# ffxiv-language-pack-ci

Shared workflows for `ffxiv-language-pack-<code>` repositories.

| Workflow | Use | Result |
|---|---|---|
| `validate.yml` | Language pack pull requests | Checks paths, corpus content and optional layouts. A new run cancels the previous validation for the same PR and validates the full corpus again. |
| `auto-merge.yml` | Called by a language repository | Enables auto-merge. Required checks and reviews must be configured in the repository rules. |
| `release.yml` | Changes to release inputs on `main`, or manual dispatch | Checks the source sync, builds and publishes the pack, then commits its coverage. Releases use a separate concurrency group and are not cancelled by validation. |
| `test.yml` | Changes to CI scripts or tests | Checks Bash syntax and runs the path restriction tests. |

A language repository calls a shared workflow from its own `.github/workflows/`:

```yaml
jobs:
  validate:
    uses: ashdam/ffxiv-language-pack-ci/.github/workflows/validate.yml@main
    with:
      language: es-es
    secrets: inherit
```

## Validation

- `scripts/validate-pr.sh` checks permitted paths, operations and file modes before the build dependencies are downloaded.
- CorpusValidator checks source and target content and baseline metadata without an installed game.
- PackBuilder checks layout definitions against the original ULD files. The source hash and node fields must match; only declared font-size bytes may change.
- The layout action uses the Tools checkout and .NET setup from the validation job.
- Release checks cover the built pack, font character support and packaged ULD files.

The job summary contains the path and corpus reports. The automatic PR comment contains the corpus report.

## Coverage

PackBuilder calls `LocalizationKit --inventory --format json`. It includes that document in the pack manifest and writes a copy beside the archive.

After publication, the release workflow copies the document to `coverage.json` and commits it to the language repository with `CI_MERGE_TOKEN`. The web reads that file. The release path filter excludes `coverage.json`, so this commit does not start another release. PR validation does not update coverage.

## Tests

`tests/validate-layout-paths.sh` checks allowed layout paths and operations, rejects executable files and raw ULD files, and restricts workflow edits.

`validate-new-sheets.sh` and `validate-patch-sync.sh` use an unsupported script interface and are not run. Their content cases belong in CorpusValidator tests.

## Secrets and repository rules

| Secret | Use |
|---|---|
| `CI_READ_TOKEN` | Reads the private Tools and game-sheet repositories. Required for release; validation can use the workflow token when it has access. |
| `CI_MERGE_TOKEN` | Writes the coverage commit. Also enables auto-merge when that workflow is called. |

Language repositories must configure the current validation status as a required check. A language with a lead must require the lead's review through `CODEOWNERS` and branch rules.

Enable repository auto-merge only when the language repository calls that workflow. Without required branch rules, `gh pr merge --auto` can merge immediately.

## Permissions

Each job requests its own permissions. PR files are read as data; validation code comes from CI and Tools. Checkouts do not retain credentials.

External actions are pinned by commit. The Dalamud archive is pinned by revision and hash.
