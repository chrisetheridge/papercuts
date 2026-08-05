# Agent skill adoption: papercut logging

## Conclusion

The papercut skill can make agents more likely to log issues, but it cannot prove they did. Codex first exposes only each skill's `name` and `description`; it loads the full `SKILL.md` only after deciding the task matches. Implicit activation therefore depends on model classification, and the logging decision inside the skill remains model behavior. [OpenAI skill documentation](https://learn.chatgpt.com/docs/build-skills#how-chatgpt-and-codex-use-skills), [Agent Skills overview](https://agentskills.io/home)

The current skill is discoverable for coding work, but the frontmatter is noisy and malformed (`.Record`), and the body gives a judgment-heavy instruction (“when you hit a small friction”) without a mandatory checkpoint or observable success condition. It should improve trigger wording and decision rules, but certainty requires instrumentation outside the skill.

## How skills are used

1. **Discovery:** Codex loads skill metadata at startup. The initial list is capped at 2% of context or 8,000 characters; descriptions may be shortened and some skills may be omitted when many are installed. [OpenAI build-skills docs](https://learn.chatgpt.com/docs/build-skills#how-chatgpt-and-codex-use-skills)
2. **Activation:** Codex can activate a skill explicitly (`$skill`) or implicitly when the task matches its `description`. OpenAI specifically recommends concise descriptions with clear scope and boundaries, with trigger words front-loaded. [OpenAI build-skills docs](https://learn.chatgpt.com/docs/build-skills#how-chatgpt-and-codex-use-skills)
3. **Execution:** After activation, Codex reads the complete `SKILL.md` and may run bundled scripts or load references. A skill is an instruction package, not a runtime guarantee. [Agent Skills overview](https://agentskills.io/home)

Implication: a body instruction cannot compensate for a weak description, and a strong description cannot force the model to perform every advisory step.

## Guidance for writing this skill

### Improve the metadata

The description is the classifier-facing part. Make it concise, grammatical, and explicit about both the broad task scope and the event that matters:

```yaml
description: During coding, debugging, testing, or repository setup, record non-transient friction that is outside the current task as a papercut. Do not log issues already fixed, expected failures, or user-requested work.
```

This keeps the skill eligible throughout engineering work while supplying the classifier with concrete trigger terms (`coding`, `debugging`, `testing`, `friction`, `papercut`) and boundaries. Do not put the whole workflow in the description; it is always present in the initial context budget.

### Make the body operational

Use a short decision rule and a single immediate action:

```text
When an unexpected, non-transient friction appears:

1. Decide: is it outside the current task and worth fixing later?
2. If yes, immediately run `papercut add` before continuing.
3. If no, continue without logging.

Log: retries caused by a repository/tool problem, confusing setup, missing docs,
misleading errors, stale state, or flaky behavior.

Do not log: one-off transient failures, issues fixed in this task, expected test
failures, or work the user explicitly requested.
```

The important design choices are adjacency (log before moving on), explicit exclusions, and a bounded command. OpenAI's general skill guidance also calls for the job-to-be-done, required inputs, numbered steps, output format, and final checks. [OpenAI Academy: Using skills](https://openai.com/academy/skills/)

### Keep the skill small

Skills use progressive disclosure, and OpenAI recommends small building blocks rather than one large workflow. Keep papercut-specific details in `SKILL.md`; only add a script if it provides deterministic behavior that would otherwise be repeatedly rewritten. [OpenAI Academy: Using skills](https://openai.com/academy/skills/), [OpenAI skill-creator guidance](https://github.com/openai/skills/blob/main/skills/.system/skill-creator/SKILL.md)

## How to know whether agents actually use it

There are three levels of confidence:

| Level | Mechanism | What it proves |
| --- | --- | --- |
| Low | Skill instructions | The agent was told to log papercuts. No execution evidence. |
| Medium | Skill + end-of-task review | The agent had a second chance to catch omissions; still model-dependent. |
| High | Hook or wrapper writes an event/audit record | The runtime observed the relevant event, independent of the model remembering the instruction. |

Codex hooks are the practical enforcement layer. They can run deterministic scripts during `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, and `Stop`; hooks can also block a supported tool call or return model-visible context. [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks)

For papercuts, the minimal useful design is:

1. A `PostToolUse` hook records objective candidates such as a failed shell command, a retry, or a tool error to a session-local JSONL file.
2. A `Stop` hook checks whether candidates remain unclassified and injects a short continuation message requiring the agent to either run `papercut add` or mark the candidate as expected/transient.
3. A small audit command reports: candidate count, papercuts created, and unresolved candidates.

This does not infer every kind of friction automatically. It does make observable tool failures hard to silently forget. Do not auto-create a papercut for every non-zero exit: expected test failures and deliberate probes would create noise.

If the requirement is “every qualifying papercut is logged,” no skill-only solution can provide that guarantee. Use a managed hook or wrapper for the objective signals, and treat the skill as the classifier and writer of the final record. Codex supports managed hooks that users cannot disable from the hook browser. [Codex hooks: managed hooks](https://learn.chatgpt.com/docs/hooks#managed-hooks-from-requirementstoml)

## Recommendation for this repository

1. Fix and sharpen `skills/papercuts/SKILL.md` metadata and replace the duplicated examples with one immediate decision rule.
2. Add a lightweight candidate log only if missed papercuts are a measured problem; start with failed/retried shell commands.
3. Add a `Stop` review hook only when candidate capture shows enough signal to avoid nagging agents on normal test failures.

The skill should remain the human-readable workflow. Hooks should provide evidence and escalation, not duplicate the full papercut policy.
