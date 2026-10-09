# Model Routing

Choose models based on the nature of the task and the independence it needs.
Pin a specific model only when its advantage has been confirmed to reproduce consistently.

## Roles

### Main session

Ordinary dialogue, implementation, investigation, editing, and progress management happen in the main session by default.
Do not delegate simple work, or work where shared context matters, to a subagent.

### Judge

Use it only when an independent judgment is useful.

Examples:

* contract or specification interpretations diverge
* review results conflict
* a decision is irreversible or high-risk
* assessments are evenly split on an important design branch

Do not use it for simple judgments or problems the main session can settle well enough.

### Scout

Use it when you need independent read-only investigation, or to check the main session's hypothesis in a separate context.
Do simple code exploration or searching directly in the main session.

### External reviewer / executor

Use it when you need an independent review by a different model, or a dedicated execution environment.
Choose the model to use based on current performance, cost, and availability.

## Delegation

Use subagents when:

* a separate context is useful
* verification from a different viewpoint is needed
* independent work can run in parallel

Handle simple work, sequential work, small changes, and work that must preserve shared state directly in the main session.

## Model selection

Pin a model only where a stable difference has been confirmed by measurement.
After moving to a new model generation, do not assume the existing pins; re-verify them.
Use full model IDs, not model aliases, for evaluations that need reproducibility.

## Handoff

Do not assume the delegate automatically shares the user-scope rules, skills, or session history.

State the goal, constraints, success conditions, and relevant facts the delegation needs.
Do not unconditionally expand the full text of known shared rules, either.

## Output ownership

The main session integrates the final deliverable and the explanation to the user.

Do not adopt a subagent's output as is; check facts and consistency as needed before using it.
