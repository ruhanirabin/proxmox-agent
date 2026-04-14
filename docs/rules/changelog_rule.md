# changelog_rule.md - Proxmox Agent

This rule file is derived from `AGENTS.md`. Use it when creating or updating changelog entries.

## Changelog location

- File: `docs/CHANGELOG.md`
- Ordering: newest version at the top
- Audience: end users and operators

## Entry prefixes (one line per entry)

- `feat:` New user-facing capability
- `fix:` Bug fix
- `perf:` Performance improvement
- `improve:` UX/refactor that changes behavior
- `removed:` Removal/deprecation/breaking change

## Rules

- Write entries as outcomes, not implementation details.
- Changelog version header must match repo `VERSION` for the release.
- Do not include:
  - CI/build/internal tooling changes
  - refactors with no user-visible behavior impact
  - internal-only documentation changes
- Note breaking changes explicitly.

## Suggested format

```md
# Changelog

## [0.7.3] - 2026-04-14
- feat: add ...
- fix: correct ...
- improve: ...
```
