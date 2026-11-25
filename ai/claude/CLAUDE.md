# Agent Instructions

## Workflow Routing

Read `ba0918-using-workflow` when the request is multi-stage development work and you need to choose how to proceed — brainstorm / plan / implement / review and the like.

Simple questions, investigation, explanations, minor fixes, and explicitly named single tasks do not need the workflow.

When the user names a specific workflow or skill, follow it.

## Brainstorm and shoryo

brainstorm (ba0918-brainstorm / kotowari-brainstorm) uses shoryo by default. When starting one, if the `shoryo` skill and the `shoryo` command are available, read the shoryo skill and run the rounds on the shoryo screen. Do not use it when the person wants the rounds in the conversation.

While shoryo is in use, the shoryo skill's instructions take precedence over the brainstorm skill for how rounds are presented and where records live (do not keep the progress file on the brainstorm skill's side or write the decision record round by round). Once the topic converges, read the records from `shoryo result` and from there write the specification and decision record as usual.

When shoryo is not available, present the rounds in the conversation as before.

## Rule Routing

The norms are provided as `ba0918-*` skills.
Read only the skills that apply to the current work.

| When                                     | Read                        |
| ---------------------------------------- | --------------------------- |
| architecture / design decision           | ba0918-design, ba0918-reuse |
| implementation                           | ba0918-tdd                  |
| writing prose for a person               | ba0918-readability          |
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

## Optional review seats (kotowari-review / ba0918-review)

A seat for a different model, added alongside the quality reviewer in a full review by kotowari-review or ba0918-review. When only a count is given, use them from the top.

- gpt: run it with `ba0918-opencode-exec`. Pass these values.
  - model: `openai/gpt-6.1-sol`
  - command name: `opencode`
  - prefix command: `kakoi` `--profile` `external-review` `--policy-file` `{{ vars.dotfiles_root }}/ai/kakoi/policy/readonly-workspace.toml` `--`
  - no-change: set it
  - prompt: write the review request to a file and pass it
  - reading the result: read the last message in the stdout file as the findings JSON. The stderr file holds the opencode logs and the kakoi warnings.
