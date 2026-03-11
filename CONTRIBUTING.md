# Contributing — codex-bridge

> **你主写，我主测；有问题走 issue / PR，不双写同一文件。**

## Division of Work

### Claudius — Implementation
- Plugin structure (manifest, agents, skills)
- Wrapper core logic (`scripts/codex-wrapper.sh`)
- README and documentation
- Bug fixes based on Jarvis's test reports

### Jarvis — Verification
- Test all scenarios (success, failure, timeout, non-git, edge cases)
- Report issues via GitHub Issues or PR with minimal patches
- Codex auth / environment troubleshooting
- Future additions: hooks, MCP server integration

## Rules

1. **Don't double-write the same file.** Claudius writes, Jarvis tests.
2. **Issues before PRs.** If a bug is found, file an issue first unless the fix is trivial.
3. **Review before merge.** Claudius reviews Jarvis's patches. Jarvis validates Claudius's implementations.
4. **Communicate in #claws.** Tag each other by name when handing off work.
