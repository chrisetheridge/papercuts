---
name: papercuts
description: Use when writing code or implementing features. .Record small workflow, quality, or speed issues discovered while working in a Git repository.
---

# Papercuts

## Log papercuts

When you hit a small friction while working—a tool call that missed and had to be retried, a confusing or undocumented setup step, a flaky command, a stale cache, a misleading error, or a non-obvious gotcha—log it proactively in the moment.

Use one or two sentences covering what you were doing, what got in the way, and optionally your guess at the cause or fix:

```sh
papercut add \
  --model "<model>" \
  --title "Short issue title" \
  --description "What happened" \
  --why "Why this costs quality or time" \
  --prompt "A self-contained prompt describing how to fix it"
```

The `--model` value records which agent model encountered the papercut. `-m` is accepted as a shorthand. This is distinct from `LOG.md`, which records what you accomplished, and from Linear issues, which represent real bugs or tracked work.

For a whole-session papercut review, use a user-triggered review command when the repository provides one (for example, `yarn papercut:review`). It may feed the session transcript to a cheap model such as Gemini Flash using `GOOGLE_API_KEY` from `.env` and append what it finds. Never run a session review unprompted.

Create a papercut when you find a small issue worth fixing later but outside the current task.

Run this from the affected repository:

```sh
papercut add \
  --model "gpt-5" \
  --title "Short issue title" \
  --description "What happened" \
  --why "Why this costs quality or time" \
  --prompt "A self-contained prompt describing how to fix it"
```

The CLI records the repository and current Git branch automatically. Keep the prompt concrete and independently actionable. Do not create a papercut for a transient command failure or an issue already fixed in the current task.
