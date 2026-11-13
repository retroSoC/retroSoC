# Git Development Workflow

This document defines Git practices for retroSoC contributors and maintainers.
See [Contributing](../CONTRIBUTING.md) for discussion, review, and validation
responsibilities. Run the examples deliberately, one step at a time; stop and
inspect any failure before continuing. They assume Git is installed and the
working directory is the repository root unless stated otherwise. Replace
example account, branch, path, and commit values with your own.

## Branches and integration

| Branch | Purpose and ownership |
| --- | --- |
| `main` | Maintainer-controlled release integration. Ordinary contributions do not target this branch. |
| `dev` | Shared integration branch and default base for contribution PRs. |
| `<type>/<short-topic>` | Short-lived branch for one contribution or reviewable feature phase. |

Use lowercase, hyphen-separated topics, such as `feat/apu-stream`,
`fix/quality-format`, or `docs/contributing`. Start new work from the current
remote `dev`; do not use a local `dev` containing unrelated commits as the
base. Document dependencies if a stacked PR needs another topic branch.

Contributions enter `dev` through PRs, normally using **Create a merge commit**
to retain meaningful individual commits. Keep separate phase commits when
they aid review and diagnosis. Do not rewrite `dev` or `main`, force-push to
them, or use a direct push to bypass review. Maintainers manage release PRs
from `dev` into `main`; a release integration is not proof of hardware signoff.
These are collaboration rules, not a claim about enabled GitHub protection
settings.

## Start a contribution

### External contributors: fork workflow

Fork the repository on GitHub first. In this example, `YOUR-USER` is your
account, `origin` is your fork, and `upstream` is the canonical repository.

```sh
git clone https://github.com/YOUR-USER/retroSoC.git
cd retroSoC
git remote add upstream https://github.com/retroSoC/retroSoC.git
git remote -v
git fetch upstream
git switch --no-track -c fix/quality-format upstream/dev
```

Make and validate the change, commit it as described below, then publish the
topic branch to your fork:

```sh
git push -u origin fix/quality-format
```

Open a PR from your fork's topic branch to **retroSoC/retroSoC:dev**, using the
repository's [PR template](../.github/pull_request_template.md).

### Maintainers: canonical clone

For a canonical clone, `origin` is the project repository; an `upstream`
remote is not required. Check the URL before pushing.

```sh
git clone https://github.com/retroSoC/retroSoC.git
cd retroSoC
git remote -v
git fetch origin
git switch --no-track -c fix/quality-format origin/dev
```

After committing and validating, push with
`git push -u origin fix/quality-format` and open a PR to `dev`. Write access
does not replace review.

## Commit conventions

Use `type(scope): summary`; the scope is optional. Use `feat`, `fix`, `docs`,
`test`, `refactor`, `build`, `ci`, `perf`, `chore`, or `revert` as appropriate.
Examples:

```text
fix(apu): reject a misaligned output buffer
docs: explain contribution validation
ci: prepare locked simulation fixtures
```

`contribution.yml` checks the PR base, head branch, title, and new commit
subjects in the selected range. Git-generated merge and revert subjects retain
their standard exception. Run `make validation-plan` before requesting review
when the change can affect CI selection.

Write a concise English summary of what changes. Use the body to explain why,
compatibility implications, and relevant evidence. Reference related issues
or specifications; use a closing reference only when the change actually
resolves the issue. Explain breaking changes explicitly in both the commit
body and PR rather than relying on the title alone. Git-generated merge and
revert subjects may retain their standard form.

Each commit should represent one coherent, reviewable change. Keep unrelated
formatting, generated baseline updates, and functional work separate. Do not
commit credentials, ignored build outputs, caches, or managed checkouts.
Review the index rather than assuming that every working-tree edit belongs
in the commit:

```sh
git status --short --branch
git diff
git add -- path/to/changed-file
git diff --cached
git diff --cached --check
git commit -m "fix(scope): describe the change"
```

The path and message above are placeholders. Add each intended new or modified
file explicitly, and follow the repository's applicable validation requirements.

## Synchronize and resolve conflicts

### Save unfinished work first

Before switching branches or integrating updates, inspect `git status`,
`git diff`, and `git diff --cached`. Prefer a meaningful local commit when
the change is ready. Otherwise, save unfinished work:

```sh
git stash push -u -m "before syncing contribution"
git stash list
git status --short --branch
```

`-u` includes untracked files but excludes ignored files and changes inside
nested repositories. Save any such work separately if it matters. Continue
only after checking that Git saved the intended changes and the working tree
is ready for integration. Record which stash you created; later examples use
`stash@{0}` only if it is still that entry.

### Update a shared topic branch

Remain on your topic branch. If it is already published, first incorporate
changes pushed by collaborators to that topic. In both clone examples,
`origin` is the remote where you publish it:

```sh
git fetch origin
git log --oneline --left-right HEAD...origin/fix/quality-format
git merge origin/fix/quality-format
```

Skip this block if the topic has not been published yet. Resolve any conflicts
using the steps below before proceeding. Then integrate canonical `dev`.
For a fork:

```sh
git fetch upstream
git merge upstream/dev
```

In a canonical clone, use `git fetch origin` and `git merge origin/dev`.
Merge preserves published commits and other contributors' work. When updating
a local `dev` with no local-only commits, use `git merge --ff-only origin/dev`
(or `upstream/dev` for a fork). If that fails, inspect the divergence rather
than resetting away local commits.

After integration, rerun affected checks and push the topic normally. If the
push is rejected because the remote advanced again, fetch, inspect, and merge
those changes; do not force-push around the rejection.

If a merge conflicts:

1. Run `git status` and `git diff --name-only --diff-filter=U`.
2. Edit each conflicted file, reconcile both sides' intent, and remove conflict
   markers. Review dependency entries and interface changes semantically; do
   not select an entire side merely to silence the conflict.
3. Stage the resolved paths with `git add -- path/to/resolved-file`, inspect
   `git diff --cached`, and run the affected validation.
4. Complete the merge with `git merge --continue`. To abandon the in-progress
   merge, use `git merge --abort` before restoring your stash.

### Restore unfinished work

After a successful integration, restore the recorded stash without deleting
the backup:

```sh
git stash apply 'stash@{0}'
git status
```

This restores content but does not guarantee the previous staged/unstaged
split. If that split is important, use `git stash apply --index 'stash@{0}'`
instead of the plain apply; index restoration can fail when the base changed.
Inspect the resulting state before attempting another operation. Do not
blindly apply the same stash twice.

For stash conflicts, edit and stage the resolved files, then validate the
combined result. There is no `stash --continue` or `stash --abort`; do not run
`git merge --continue` for a stash conflict. Keep the backup until the content
and intended staging are correct. If recovery is unclear, preserve the current
files and stash before making further changes; avoid destructive resets.

Once the restored work is verified and no newer stash changed the numbering,
remove only the recorded backup:

```sh
git stash drop 'stash@{0}'
```

### Rebase only private work

You may rebase or amend personal, unshared commits before review. Start with
a clean working tree and create a backup branch before rewriting history:

```sh
git branch backup/quality-format-before-rebase
git fetch upstream
git rebase upstream/dev
```

Use `origin/dev` instead for a canonical clone. Resolve conflicts, stage the
resolved paths, and use `git rebase --continue`; use `git rebase --abort` to
return to the pre-rebase branch state. Revalidate the result. Do not use
`--skip` unless you have verified that the commit is intentionally redundant.

A published personal branch may be rewritten only when nobody else's work
depends on it and affected reviewers have agreed. Fetch and inspect its
current remote history first, preserve a backup, and use `--force-with-lease`
only for that topic branch. A rejected lease means the remote changed: inspect
it instead of retrying with `--force`. Neither option is permitted for `dev`,
`main`, or a shared topic branch under this workflow.

## Recovery and releases

To undo a published change, create a new branch from current `dev` and use
`git revert COMMIT_SHA`, then submit the revert through review. For a merge
commit, inspect its parents and agree on the intended mainline with a
maintainer before using the `-m` option. Reverting creates new history;
resetting a shared branch rewrites it.

To find a lost local commit, inspect `git reflog`, verify the candidate with
`git show COMMIT_SHA`, and preserve it with
`git branch recovery/topic COMMIT_SHA`. Reflogs are local and expire; they
are not a durable backup and do not generally recover uncommitted file edits.

Maintainers choose and review the release revision on `main`, add a tracked
`quality/release-candidate.json` through the approved release PR, and publish an
immutable `vMAJOR.MINOR.PATCH` tag only after its required workflows succeed.
The [release schema](../quality/release-candidate.schema.json) defines the lock
digest, approval, stages, workflow names, and accepted gaps. Optional
`local_checks` reference revision-matched local formal summaries and manifests.
Their content is validated for clean inputs and passing prove/cover results;
revision-bearing summary hashes are not embedded in the candidate. The
[release workflow](../.github/workflows/release.yml) verifies the tag against
current `origin/main` and matching successful runs. `sole_maintainer` accepts a
merged release PR with the named maintainer's approval record; peer mode
requires an APPROVED review. Existing assets are not overwritten.

Do not move or reuse published release tags. Follow
[Engineering Workflow](engineering.md) for artifacts and release validation;
ordinary contribution pushes should name their topic branch explicitly and
should not publish tags.

## CI-green auto merge and cleanup

`quality/ownership.json` enables `auto_merge`: after every required check passes,
`python3 scripts/pr_workflow.py --pr <number> --root .` enables GitHub's native
auto-merge with a merge commit into `dev` without another manual confirmation.
The helper checks all contexts required by branch protection, including gates
that have not yet been scheduled. Pending, failed, empty, or cancelled checks
prevent merging. The command never overrides branch protection or uses
squash/rebase integration.
Every branch-protected context must report success. Non-required jobs skipped
by workflow selection retain a `SKIPPED` verdict while their required aggregate
gates enforce the selected validation plan.

After GitHub reports `MERGED`, the same command deletes the local and remote
topic branches only when the worktree is clean and the PR head belongs to the
canonical repository. It switches the main worktree to `dev` or removes a clean
linked worktree, verifies that the local branch is contained in the PR merge
commit, then deletes it without forcing. The deletion uses `origin/dev` as its
merge reference even when the main worktree is on an unrelated branch. Dirty
worktrees, unmerged local commits, non-canonical branches, and protected
`dev`/`main` branches are left untouched. `deleteBranchOnMerge` remains enabled on GitHub as a second cleanup
mechanism. Already-absent remote refs are treated as successful cleanup; other
API errors fail.

After every feature integration into `dev`, also run:

```sh
git fetch --prune
```

This removes local remote-tracking references whose corresponding remote
branches no longer exist. It is required in addition to topic-branch cleanup
and does not delete local branches, stash entries, uncommitted changes, or
build artifacts.
