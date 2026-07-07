# CLAUDE.md

Model-agnostic Agent Skills package. README covers install/layout — this file is gotchas only.

## Merge gate
- Every PR to `main` needs exactly one label: `release:patch|minor|major`, else CI (`release-gate.yml`) fails.

## Conventions
- Skills: `skills/<name>/SKILL.md`, YAML frontmatter requires `name` + `description`. One definition serves all CLIs.
- `install.sh` is sourced by tests — keep `main` behind the `MAIN_RAN` guard, no top-level side effects.
- Run `test/run.sh` before pushing.
- Git-ignore working/progress files (transient, local-only), not permanent docs — e.g. `docs/superpowers/` and `docs/docs-check/`. Don't commit them.
