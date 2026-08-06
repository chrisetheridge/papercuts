---
name: papercuts
description: During coding, debugging, testing, or repository setup, record non-transient friction outside the current task as a papercut.
---

# Papercuts

Use this workflow during implementation, debugging, testing, and repository setup.

## Decide immediately

When unexpected friction appears, pause before continuing and ask:

1. Is this a repository, tool, setup, documentation, or workflow problem?
2. Is it outside the current task or not worth fixing now?
3. Would another agent likely lose time to it?

If all three answers are yes, log it now. Otherwise continue without logging.

Log examples: a retry caused by repository or tool behavior, confusing setup, missing documentation, a misleading error, stale state, flaky behavior, or a non-obvious gotcha.

Do not log: transient command failures, expected test failures, deliberate experiments, issues fixed in the current task, or work the user explicitly requested.

## Add a papercut

Review existing entries for duplicates with the installed `papercuts` CLI:

```sh
cli="$HOME/.local/bin/papercuts"
response="$($cli list --repository-path "$PWD")"
```

Then add the entry with:

```sh
response="$($cli add \
  --title "Short issue title" \
  --description "What happened" \
  --why "Why this costs quality or time" \
  --prompt "A self-contained prompt describing how to fix it" \
  --model "<current model>")"
```

Use one or two sentences for the description. Make the fix prompt concrete and independently actionable. Confirm the response succeeded before continuing.

If the CLI is unavailable, ask the user to run the installer. If the socket is unavailable, ask the user to launch Papercuts before logging; do not silently skip a qualifying papercut.

The app detects the repository and current Git branch from `repositoryPath`. To correct an entry, use:

```sh
response="$($cli edit <id> --title "Updated title" --prompt "Updated fix prompt")"
```

Omit fields that should stay unchanged.
