# AGENTS.md

Instructions for AI agents working in this repository.
Claude Code / Codex / Cursor / Aider and others load it directly.

## Project overview

- Personal dotfiles (WSL2 + fish + a number of dev tools)
- Management: declarative symlink deployment via **mise bootstrap**
  (`[bootstrap.packages]` / `[dotfiles]` / `[tools]`)
- Each top-level directory is a "package". A path inside a package reproduces its
  `$HOME`-relative path as is, and the `[dotfiles]` source declarations in
  `mise/config.toml` deploy it as a symlink into `$HOME`
- The real global config is `mise/config.toml` (referenced by `MISE_GLOBAL_CONFIG_FILE`)
- Users: single user / single machine today; possibly cross-environment in the future

## Rules to follow when changing things

### 1. Never commit secrets

- `.env*` / `*.pem` / `*.key` / `auth.json` / `.credentials.json` / `.git-credentials`
  and the like are blocked hard by `.gitignore`
- When adding a new file under `ai/claude/` or `ai/codex/`, **always check that
  credentials / history / sqlite / sessions / cache / backups are not mixed in**
- When a new secret path turns up, add it to `.gitignore` and
  `ai/shared/deny-patterns.yaml` (deny-patterns.yaml is the source of truth for the
  LLM deny settings. See [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md))
- Even when using `[bootstrap.secrets]`, do not persist plaintext secrets in the repo / config

### 2. Be aware of symlink side effects

- Files that tools rewrite through symlinks, such as `~/.gitconfig`, **change the repo
  file itself**
- Example: `gh auth setup-git` / `glab auth login` append to `~/.gitconfig` or
  `~/.ssh/config` → detected as a diff in `git/.gitconfig` or outside the repo
- Tidy up such external writes before committing

### 3. Script output is neutral English

- Write script stdout/stderr, header comments, and error messages in
  **neutral English** (no persona / emoji / friendly tone)
- User-facing conversation, README, and commit messages are **Japanese**
- Note that the language is split between documents and scripts

### 4. Respond and commit in Japanese

- Conversation responses in Japanese
- Commit messages in Japanese
- Technical terms and code identifiers keep their original form

### 5. mise: dry run first

- Confirm collisions and diffs with `mise bootstrap --dry-run` before applying for real
- `apply --force` replaces existing real files; check the contents before using it
- Monitor short-lived changes with `git status` so that files in the repo do not become symlinks

### 6. Never skip tests

Same as the global policy: fix failing tests instead of skipping them
(`skip` / `xit` / deletion).

This repo has two test tracks; `mise run test` (`scripts/run-tests.sh`) runs them all.
GitHub Actions (`.github/workflows/ci.yml`) runs the same entry point on pushes to main,
but since there is no PR workflow, CI is a detector after the fact. Run the tests locally
before pushing when you have touched something (for the commands, see the test section of
[docs/commands.md](docs/commands.md)).

- **pytest** — `ai/shared/hooks/tests/` (security hooks)
- **bash harness** — `scripts/test_*.sh` (generator scripts / wrappers)

New bash scripts automatically enter the scope of CI's `mise run lint` (shellcheck)
(every file under git with a bash shebang).

### 7. Do not let generated artifacts pass while empty

For artifacts of the kind that come out shape-valid even when generation fails, such as the
deny settings, write the check through to dropping the run on a count or an invariant. In the
past, `generate-deny.sh` returned 0 entries under mawk and still exited 0, and a
`settings.json` with empty deny settings was distributed silently.

For the same reason, keep shell script regular expressions **POSIX-compatible**. GNU
extensions such as `\s` / `\d` silently stop matching under mawk, the Debian/Ubuntu default.

## Constraints when adding a hook

When a hook setting calls a target outside the repo (a notification script, an external
tool's state management, and the like), do not write the command directly; go through
`run-if-present`'s `path` mode. On a new machine the dependency does not exist, so when the
target is absent the hook is skipped silently. A failure of the command itself propagates as
is (a broken dependency stays visible).

For the target list and how each is called, see the "hook の repo 外依存" section of
[docs/dependencies.md](docs/dependencies.md).

## References

| Document | Contents |
|---|---|
| [docs/layout.md](docs/layout.md) | Layout, package list, how to add packages |
| [docs/commands.md](docs/commands.md) | Command reference |
| [docs/dependencies.md](docs/dependencies.md) | External tool dependencies, supply-chain measures, kakoi |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Troubleshooting |
| [meta/LLM-SETTINGS.md](meta/LLM-SETTINGS.md) | The conf.d / deny-patterns pipeline for LLM settings |
| [meta/MIGRATION.md](meta/MIGRATION.md) | How to take in existing settings |
