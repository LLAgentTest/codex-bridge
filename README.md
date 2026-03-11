# codex-bridge

> Claude Code plugin: use OpenAI Codex CLI as a sub-agent

A Claude Code plugin that lets Claude delegate tasks to [OpenAI Codex CLI](https://github.com/openai/codex) for alternative perspectives, stubborn bugs, or when GPT-series models may perform better.

## How it works

```
Claude Code → subagent "codex" → codex-wrapper.sh → codex exec --full-auto --json
```

- **Subagent** (`agents/codex.md`) — Claude auto-delegates when appropriate
- **Skill** (`skills/codex/SKILL.md`) — Manual trigger via `/codex-bridge:codex <task>`
- **Wrapper** (`scripts/codex-wrapper.sh`) — Handles cwd, timeout, exit codes, output formatting

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) v1.0.33+
- [Codex CLI](https://github.com/openai/codex) installed and authenticated (`npm install -g @openai/codex`)
- `jq` for JSON processing

## Install

```bash
# Clone the plugin
git clone https://github.com/LLAgentTest/codex-bridge.git

# Option 1: Load for current session
claude --plugin-dir ./codex-bridge

# Option 2: Install permanently
# In Claude Code, run:
#   /plugin install --path ./codex-bridge
```

## Usage

### Automatic (subagent)

Claude will automatically delegate to Codex when it determines a second opinion would help. No action needed.

### Manual (skill)

```
/codex-bridge:codex fix the race condition in src/worker.ts
```

### Wrapper directly

```bash
bash scripts/codex-wrapper.sh "fix the race condition in src/worker.ts" /path/to/project 300
```

## Configuration

The wrapper accepts three arguments:
1. **Task description** (required)
2. **Working directory** (default: current directory)
3. **Timeout in seconds** (default: 300)

## Architecture

```
codex-bridge/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── agents/
│   └── codex.md             # Subagent definition (auto-delegation)
├── skills/
│   └── codex/
│       └── SKILL.md         # Manual skill trigger
├── scripts/
│   └── codex-wrapper.sh     # Thin wrapper around codex exec
└── README.md
```

## License

MIT
