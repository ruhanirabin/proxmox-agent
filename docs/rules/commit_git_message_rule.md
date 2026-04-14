# commit_git_message_rule.md - Proxmox Agent

This rule file is derived from `AGENTS.md`. Follow these rules for commit messages.

## Allowed prefixes

- `feat:`
- `fix:`
- `perf:`
- `improve:`
- `internal:`
- `doc:`
- `removed:`
- `test:`
- `ci:`
- `build:`

## Rules

- Subject line only (no long body), target <= 72 chars.
- Prefer one logical change per commit.
- Avoid ambiguous messages: `WIP`, `temp`, `misc`, `stuff`.
- If commit is purely formatting, use `internal:`.

## Examples

- `feat: add webhook event filtering by event name`
- `fix: skip backup commit when no config files changed`
- `improve: harden doctor checks for missing env values`
- `internal: normalize shell script line endings`

