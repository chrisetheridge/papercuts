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

Review existing entries for duplicates with an `{"action":"list","repositoryPath":os.getcwd()}` request, then send one newline-delimited JSON request to the Papercuts socket using standard-library Unix-domain socket support:

```python
import json, os, socket

path = os.path.expanduser("~/Library/Application Support/Papercuts/papercuts.sock")
request = {
    "action": "add",
    "model": "<current model>",
    "title": "Short issue title",
    "description": "What happened",
    "why": "Why this costs quality or time",
    "prompt": "A self-contained prompt describing how to fix it",
    "repositoryPath": os.getcwd(),
}
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(5)
    connection.connect(path)
    connection.sendall((json.dumps(request) + "\n").encode())
    response = json.loads(connection.makefile("rb").readline())
if response.get("error"):
    raise RuntimeError(response["error"])
```

Use one or two sentences for the description. Make the fix prompt concrete and independently actionable. Confirm the response succeeded before continuing.

If the socket is unavailable, ask the user to launch Papercuts before logging; do not silently skip a qualifying papercut.

The app detects the repository and current Git branch from `repositoryPath`. To correct an entry, send `{"action":"edit","id":"<id>", ...}`; omitted fields stay unchanged.

This is distinct from `LOG.md`, which records what was accomplished, and from Linear issues, which represent real bugs or tracked work.

## Whole-session review

Run a repository's session-review command only when the user asks. It may send the transcript to another model and must not run unprompted.
