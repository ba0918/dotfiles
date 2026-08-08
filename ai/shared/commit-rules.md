# Commit Rules

Resident digest of claude-skills `skills/commit/SKILL.md`. Applies to EVERY `git commit`,
including self-initiated commits mid-workflow (not only when the user says "commit").

## Staging

- Split changes into logical units — one concern per commit. Stage files individually;
  never `git add -A` / `git add .`
- Never stage secrets (.env, keys, credentials) or non-work-products (logs, tmp files)

## Message

- Format: `<type>: <subject>` (Conventional Commits types); body only when the why needs
  it; no footer by default. Language: Japanese (user rule)
- The message is a standalone historical record — it must read without the conversation,
  the plan, or the agent session:
  - Describe the resulting change and why it was needed — never the workflow that
    produced it
  - No phase/step/stage labels ("第 N 期", "(第 1 期-2)")
  - No agent chronology ("found during review sweep", "per user feedback")
  - No references that need local/ephemeral context: gitignored paths (`.agents/...`),
    bare agreement IDs (A8/U3). Spell the content out, or use stable refs
    (issue/PR numbers, spec names, architectural concepts)
  - No generic subjects ("address feedback", "apply remaining changes")
