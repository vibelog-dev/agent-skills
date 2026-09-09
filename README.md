# agent-skills

Model-agnostic [Agent Skills](https://github.com/vibelog-dev/agent-skills)
package — a collection of skills for the software development workflow,
installable into any supported coding-agent CLI with `install.sh`.

Currently supported CLIs: **Claude Code**, **Cursor**, **PI**.

## Install

```bash
git clone https://github.com/vibelog-dev/agent-skills.git
cd agent-skills
./install.sh
```

## Layout

```
skills/<name>/SKILL.md   # one skill per directory
install.sh               # the installer
```

A skill is a directory containing a `SKILL.md` with YAML frontmatter
(`name`, `description` required). The same definition serves every CLI.

## Skills

| Skill | Description |
|-------|-------------|
| `spec-review` | Turns vague engineering requests into an evidence-backed Senior Engineering Task Brief before an implementation plan is written. |
| `docs-check` | Pre-merge documentation freshness gate — docs must pass an executable checklist, not merely exist. |

## Usage

```bash
./install.sh                       # interactive: pick CLI, scope, skills
./install.sh --cli claude --scope global --all    # non-interactive
./install.sh --cli claude --project-path ~/my-repo --all   # project scope, custom path
./install.sh --dry-run             # show what would happen, change nothing
./install.sh --list                # show currently-linked skills
./install.sh --uninstall           # remove only symlinks pointing at this repo
```

Skills install as **symlinks** into each CLI's skills directory:

| CLI | global | project |
|-----|--------|---------|
| claude | `~/.claude/skills/<name>` | `<project>/.claude/skills/<name>` |
| pi | `~/.pi/agent/skills/<name>` | `<project>/.pi/skills/<name>` |
| cursor | `~/.cursor/skills/<name>` | `<project>/.cursor/skills/<name>` |

For project scope, `<project>` is the current directory by default, or the
directory you pass to `--project-path` (interactively, you're prompted for it).

The installer is non-destructive: it never overwrites a real directory or a
symlink it does not own without an explicit `--backup` or `--force`.

## Transparency

This project uses an AI-assisted agentic workflow for research, planning,
implementation, review, and verification. Tools such as Claude Code and Codex
may be used during development, but human review and verification are required
before any change is merged or published.

## License

MIT — see [LICENSE](LICENSE).
