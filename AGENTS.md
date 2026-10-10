# Fork maintenance

This repository is a fork of OpenAI Codex. Its important downstream behavior is
support for externally managed installations, especially Nix: when no official
daemon installation exists, use the current CLI executable and leave updates to
the external package manager. Preserve existing managed installations, including
broken selections that need explicit repair.

## Local build policy

Building Codex locally can take around two hours. Do not run local builds unless
the user explicitly requests them. A `Rebase` command or a general request to
fix, test, or validate changes does not by itself authorize a local build.

This applies to commands that compile Codex or its dependencies, including
`cargo build`, `cargo test`, `cargo check`, `nix build`, `nix run`, and build or
test wrappers. Use source review, static checks, and evaluation without builds
by default. Do not trigger a build merely to validate a hash or version.
If a validation step requires compilation, skip it and report that it was not
run under this policy; continue the remaining work without requesting build
permission as a routine step.

## Exact command: `Rebase`

When the entire user message, after trimming surrounding whitespace, is exactly
`Rebase` (case-sensitive), treat it as an instruction to execute the complete
maintenance workflow below. This is the prompt passed by `opencode2 run Rebase`;
do not require the user to repeat the steps or stop after proposing a plan.
Other messages do not automatically trigger this workflow.

### Branch roles

- `origin`: the fork, currently `git@github.com:hooreique/codex.git`.
- `upstream`: OpenAI Codex, currently `git@github.com:openai/codex.git`.
- Local `master`: the upstream baseline, tracking `upstream/main`.
- Local `main`: downstream commits rebased onto local `master`.

Inspect the actual configuration before acting. Do not confuse local `master`
with a remote branch named `master` or rebase the upstream baseline onto the fork.

### 0. Check and report related upstream work first

- Before changing branches or starting the rebase, inspect the fork's downstream
  delta and search the live open issues and pull requests in `openai/codex` for
  work addressing the same goals. Include externally managed installations,
  current-executable daemon fallback, managed installation repair, external
  update ownership, and Nix packaging where relevant to the actual fork changes.
- Read relevant issue and PR descriptions and discussions to assess overlap;
  matching keywords alone are insufficient. Distinguish requests or proposals
  from implemented changes, and open PRs from changes already merged upstream.
- If related open issues or PRs exist, report them to the user **before proceeding
  with the rebase**. Include links, their current status, the overlapping fork
  behavior, and any implications for retaining or adapting downstream patches.
  This preliminary report must not be deferred to the final maintenance summary.
- If no relevant results are found, say so briefly. If the search cannot be
  completed, report the limitation rather than claiming there are no matches.
- Reporting related work does not by itself require approval or stop the
  authorized maintenance workflow. Continue after reporting unless a genuine
  ambiguity requires clarification. Do not drop a fork patch merely because an
  open issue or PR proposes equivalent behavior; verify coverage in the refreshed
  upstream baseline before adapting or removing it.

### 1. Preserve and inspect the starting state

- Read applicable repository instructions and inspect status, current branch,
  worktrees, ongoing Git operations, tracking branches, and recent history.
- Preserve uncommitted and untracked user work. Do not discard it, include it in
  maintenance commits, or overwrite it when switching branches. If temporarily
  stashing is necessary, record the stash and restore it after maintenance; keep
  the stash if restoration conflicts and report what remains to be resolved.
- Record starting commit IDs and create a uniquely named local backup ref for
  `main` before rewriting it. Do not overwrite an existing backup.
- Do not abort an existing user rebase/merge or reset a divergent branch merely
  to make this workflow proceed. Ask only when a genuine ambiguity or conflict
  cannot be resolved from the repository and these instructions.

### 2. Refresh remotes and reconcile branches

- Fetch current branches from both `origin` and `upstream`, pruning stale remote
  tracking refs. Fetch upstream release tags as well. Do not force-overwrite
  conflicting local tags without investigating their provenance.
- Fast-forward local `master` to `upstream/main` using fast-forward-only
  semantics. If local `master` contains divergent commits, investigate instead
  of silently dropping them.
- Reconcile `main` with the freshly fetched `origin/main` before rebasing:
  - If merely behind, fast-forward it.
  - If merely ahead, retain its local commits.
  - If diverged, compare history and patch equivalence. An earlier local rebase
    may make ahead/behind counts misleading. Preserve genuine remote-only and
    local-only work without replaying equivalent fork patches twice.
  - Do not merge `origin/main` blindly or replace local `main` with the remote.
    Stop for clarification if competing changes cannot be reconciled reliably.

### 3. Rebase the fork

- Rebase local `main` onto the refreshed local `master`.
- Inspect the downstream delta before resolving conflicts. Preserve its intent
  while adopting upstream changes; do not use blanket “ours” or “theirs”.
- Important downstream behavior includes:
  - Current-executable daemon fallback for an external CLI with no usable
    package to seed and no existing daemon installation.
  - Existing managed installations retain their selection and repair behavior.
  - External fallback does not acquire the standalone installer/auto-updater.
  - Nix packaging, companion executables, and fork-specific Cachix publishing
    continue to work.
- Upstream may make a fork patch unnecessary. Drop or adapt it only after
  verifying that its intended behavior is covered, and explain the change.

### 4. Update the reported release version — required

Every `Rebase` includes version review and, when needed, a version update.
The user does **not** require the version to identify the exact source commit.
A suitable nearby official release version is sufficient, particularly for
ChatGPT mobile clients querying the underlying Codex/app-server version.

- Inspect official upstream release tags and, when useful, published release
  metadata near the new upstream baseline. Prefer a nearby stable release.
  Consider a nearby official prerelease when stable releases are substantially
  behind the source; retain its actual prerelease identifier rather than
  inventing an unreleased stable version.
- Use judgment based on release timing and source ancestry/base commits. Do not
  choose solely by the largest version number, a local tag list that has not
  been refreshed, or `git describe`.
- Release commits can live off the upstream mainline. Inspect their parents or
  merge bases where appropriate; the release tag itself need not be an ancestor
  of `main`. Never remove fork functionality just to match a release exactly.
- Inspect the previously reported version. Avoid an unexplained downgrade;
  document the reason if choosing an older nearby release is appropriate.
- Update the existing Nix version fallback in `flake.nix` rather than adding a
  version-discovery script or querying mutable “latest” metadata during builds.
  Continue honoring a real non-placeholder workspace version on release source.
  Keep comments accurate and record the chosen tag and rationale in the
  maintenance commit or final report.
- Ensure Nix's package version and the version compiled into the relevant Rust
  crates agree. Updating a derivation name alone is insufficient. The existing
  packaging patches the workspace `Cargo.toml` during the build; inspect that
  mechanism and adapt it if upstream changes version handling.
- Trace the actual CLI and remote-control version-reporting paths after the
  rebase. At the time these instructions were written, remote enrollment's
  `app_server_version` in
  `codex-rs/app-server-transport/src/transport/remote_control/server_api.rs`
  uses `CARGO_PKG_VERSION`, while some display paths use `BuildInfo`.
- Keep version reporting independent of installation ownership. In particular,
  do not add `codex-package.json` merely to supply a version: its presence can
  create a package layout, disable the current-executable fallback, and trigger
  managed-package preparation. If display-version alignment needs changes,
  prefer build-time version information without altering installation detection.
- Do not claim mobile compatibility was tested solely because a version string
  looks correct. Actual mobile acceptance is distinct from local validation.

### 5. Repair packaging and validate

- Review the rebased Cargo lockfile and Nix packaging for new or changed Git
  dependencies, missing `cargoLock.outputHashes`, toolchain requirements, native
  dependencies, and versioned assets such as V8 archives and bindings.
- Obtain real hashes from the pinned sources. Verify them through Nix when this
  can be done without a local build, or when the user explicitly requested local
  builds. Report any deferred hash verification. Never leave placeholder hashes
  or disable hash verification to pass a build.
- Run `git diff --check` and evaluate the flake for its supported systems, for
  example `nix flake check --no-build --all-systems`.
- Only when the user explicitly requests local builds, build and execute
  `nix run . -- --version` on the host platform. Confirm that the result is the
  selected version, rather than `0.0.0` or a stale fallback.
- For changed daemon fallback or version logic, run focused regression tests
  only if they require no local compilation or the user explicitly requested
  local builds. Cover absent official installations and preservation of existing
  managed selections. Avoid touching the user's live daemon, credentials, or
  official installation during validation; use isolated fixtures.
- Report skipped builds and execution tests explicitly. Source review and flake
  evaluation do not confirm a successful build or the executable's reported
  version. Evaluation is not a build test for other platforms, and `--version`
  alone is not an end-to-end remote-control or mobile compatibility test.
- When local builds are explicitly requested, follow them through completion
  when possible. If an external blocker prevents validation, report it explicitly
  rather than declaring success.

### 6. Finish locally and report

- Commit maintenance changes made by this workflow (such as release-version and
  dependency-hash updates) on `main`, using a descriptive commit message. Include
  only the workflow's changes, not unrelated user work. Do not create an empty
  commit when no maintenance edits are needed.
- Restore temporarily preserved user work and leave `main` checked out, unless
  the starting worktree arrangement makes that inappropriate; explain exceptions.
- Review the final downstream delta and status for accidental losses or extra
  changes. Keep the local backup ref available for recovery.
- `Rebase` authorizes local history rewriting and maintenance commits, **not a
  push**. Do not push or force-push unless the user separately requests it.
- Summarize the old/new upstream baseline, rebase/conflict outcome, selected
  release version and rationale, maintenance commits, validation results, and
  any unresolved issues or preserved user work. State that changes remain local.
