# ffxiv-language-pack-ci

The workflows every `ffxiv-language-pack-<code>` repository calls, so there is one copy of each.

| Workflow | Called on | What it does |
|---|---|---|
| `validate.yml` | every pull request | Checks translation edits and source-backed patch syncs. Metadata must match `main` or the current English source; targets must pass the JSON, placeholder and macro checks. Reports rejected rows on the pull request. |
| `auto-merge.yml` | every pull request | Enables auto-merge, so the pull request lands the moment `validate` passes. A repository with a language lead makes review required, and the workflow then waits for it. |
| `release.yml` | every push to `main` | Builds the pack from the corpus and the exported game sheets, and publishes the release. Concurrency per language: two merges in a row publish two releases in order. |

A language repository calls them like this, in its own `.github/workflows/`:

```yaml
jobs:
  validate:
    uses: ashdam/ffxiv-language-pack-ci/.github/workflows/validate.yml@main
    with:
      language: it
    secrets: inherit
```

## Secrets a language repository needs

| Secret | For |
|---|---|
| `CI_READ_TOKEN` | Reading the private repositories the release clones: the build tools and the game sheets. A fine-grained token, contents read. |
| `CI_MERGE_TOKEN` | Enabling auto-merge as a person. A fine-grained token on the language repository: contents write, pull requests write. The workflow token cannot be used: a merge it makes starts no workflow, so the release would never run. |

## Repository settings

- **Allow auto-merge** on, and a branch protection rule on `main` with `validate` as a required
  status check. Without the rule `gh pr merge --auto` merges at once; without auto-merge it refuses.
- When the language has a lead: `CODEOWNERS` with `corpus/ @lead` and *require review from code
  owners* in the same rule.

## What the release runner does not check

The full validator needs the installed game and does not run here. The build's own gates
run instead: every page is rebuilt byte-identical before anything is substituted, and a row whose
macros do not survive the round trip is skipped and counted, never guessed at.

## What the workflows may do

- The workflow token starts with no permissions; each job asks for what it needs: `validate` reads contents and writes a comment, `release` writes contents, `auto-merge` writes contents and pull requests.
- Nothing from a pull request is executed. `validate` reads its files as data and runs the script from this repository; `auto-merge` checks nothing out.
- Every action is pinned by commit, and the Dalamud archive by hash. A Dalamud update needs the new hash in `release.yml`.
- Checkouts keep no credentials. The tokens live in the language repository's secrets and reach the logs only masked.
