---
description: Manually run a task through OpenAI Codex CLI for an alternative AI perspective
---

# Codex Bridge

Run a task through OpenAI Codex CLI using the wrapper script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-wrapper.sh" "$ARGUMENTS"
```

Return the full output from Codex to the user.

If the command fails or times out, report the error clearly.
