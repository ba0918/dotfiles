# Agent Instructions

## Core

* Respond in Japanese.
* Prioritize the user's goal and requested scope; do not expand the work unnecessarily.
* Keep facts, inferences, and unverified items apart.
* When project-specific instructions exist, apply them with priority.

## Workflow Routing

Read `ba0918-using-workflow` when the request is multi-stage development work and you need to choose how to proceed — brainstorm / plan / implement / review and the like.

Simple questions, investigation, explanations, minor fixes, and explicitly named single tasks do not need the workflow.

When the user names a specific workflow or skill, follow it.

## Human Interaction

For dialogue with the user, follow these shared contracts.

- `{{ vars.dotfiles_root }}/ai/shared/persona/gal.md`
  - surface persona, tone, and distance
- `{{ vars.dotfiles_root }}/ai/shared/human-readable.md`
  - granularity, abstraction, information density, and technical terms of responses
- `{{ vars.dotfiles_root }}/ai/shared/interaction.md`
  - questions, judgments, cause analysis, progress reports, and how work proceeds

## Rule Routing

The norms are provided as `ba0918-*` skills.
Read only the skills that apply to the current work.

| When                                     | Read                        |
| ---------------------------------------- | --------------------------- |
| architecture / design decision           | ba0918-design, ba0918-reuse |
| implementation                           | ba0918-tdd                  |
| code readability concern                 | ba0918-readability          |
| information placement decision           | ba0918-placement            |
| document creation / organization / pruning | ba0918-documents           |
| secrets / credentials / sensitive config | ba0918-secrets              |
| commit                                   | ba0918-commit               |
| delegate to subagent                     | ba0918-delegation           |
| diff review                              | ba0918-diff-review          |
| release                                  | ba0918-release              |
| CI / CD pipeline (workflow files)        | ba0918-ci                   |
| mutation testing (run / configure / CI)  | ba0918-mutation-testing     |
| verification / review                    | ba0918-verification         |
| worktree                                 | ba0918-worktree             |

Combine what you need when several apply.
Do not read unrelated skills preventively.

When deciding whether to create a document file, deciding where to place, move, or delete one, or taking inventory of old documents, read `ba0918-documents`.

Use the `kemi` skill to present diff reviews.

## Tool Guide

When unsure which development tool to use, see
`{{ vars.dotfiles_root }}/ai/shared/tools-guide.md`.

When the right tool is already clear, you do not need to read it beforehand.

## Local Instructions

When a more specific `AGENTS.md` or a project-specific contract exists, treat it as a realization of this common contract for that project.

## Verification

Run reasonable verification for what changed.

When the impact is limited, prefer verification covering that range, and do not run unnecessarily broad, unrelated verification.

Safe local verification needs no step-by-step approval midway; when a failure comes from this change, fix it and run again.

## Subagent operation rules

- Subagents in Codex consume many tokens. Invoke one only when the task needs a fresh context, such as a review from a different perspective.
- Whenever you call `wait_agent`, set `timeout_ms` to double the estimated time left until completion, in milliseconds. Make sure this fits within the tool’s min and max limits. If you cannot estimate the remaining time, simply use the default value. There is no need to shorten the wait time for quick checks, since notifications will cancel it early anyway. If a timeout happens, recalculate the expected completion time and wait again based on the same rules.

## Permission handling

The active permission profile is authoritative.

- Never request escalated permissions.
- Never set `sandbox_permissions = "require_escalated"`.
- Never request command-prefix approval.
- Run commands normally within the active permission profile.
- If an operation is denied by the sandbox, report the denied resource and continue with a materially safe alternative.

## GitHub inside the jail

`gh` and `git push` work through a scoped token (`GH_TOKEN`). Its permissions cannot
be widened from inside; do not try `gh auth login`. `gh pr checks` fails with
"Resource not accessible by personal access token" (the token type has no Checks
permission) — read CI results with `gh run list --branch <branch>` and
`gh run view <id> --log-failed` instead.
