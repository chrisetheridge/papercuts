---
name: papercuts
description: During coding, debugging, testing, or repository setup, record non-transient friction outside the current task as a papercut.
---

# Papercuts

## Log papercuts

When you hit a small friction while working—a tool call that missed and had to be retried, a confusing or undocumented setup step, a flaky command, a stale cache, a misleading error, or a non-obvious gotcha—check Papercuts and log it proactively in the moment.

Papercuts listens on this per-user Unix-domain socket:

```text
~/Library/Application Support/Papercuts/papercuts.sock
```

Send one newline-delimited JSON request and read one newline-delimited JSON response. Use the standard library socket support available in your language. Python example:

```python
import json
import os
import socket

socket_path = os.path.expanduser("~/Library/Application Support/Papercuts/papercuts.sock")

def papercuts(request):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.connect(socket_path)
        connection.sendall((json.dumps(request) + "\n").encode())
        return json.loads(connection.makefile("rb").readline())

repository_path = os.getcwd()
existing = papercuts({"action": "list", "repositoryPath": repository_path})
```

Review the returned papercuts for duplicates before sending an `add` request:

```python
result = papercuts({
    "action": "add",
    "model": "<model>",
    "title": "Short issue title",
    "description": "What happened",
    "why": "Why this costs quality or time",
    "prompt": "A self-contained prompt describing how to fix it",
    "repositoryPath": repository_path,
})
```

To correct an existing entry, send its `id` from the `list` response. Omitted fields stay unchanged:

```python
result = papercuts({
    "action": "edit",
    "id": existing_id,
    "title": "Updated issue title",
    "prompt": "Updated self-contained fix prompt",
})
```

The app detects the repository and current Git branch from `repositoryPath`. Set `branch` to override the detected branch. If the socket is unavailable, ask the user to launch Papercuts before logging.

This is distinct from `LOG.md`, which records what you accomplished, and from Linear issues, which represent real bugs or tracked work. Do not create a papercut for a transient command failure or an issue already fixed in the current task.
