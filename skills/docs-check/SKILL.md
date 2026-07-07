---
name: docs-check
description: Pre-merge documentation freshness gate — docs must pass an executable checklist, not merely exist. Triggers: "docs check", "verify docs", when writing the final report before a merge. If the project ships its own variant (docs-check-<project>), use that instead.
---

# docs-check — documentation verification gate

Documentation verification works like a code gate: the bar is not "the docs exist" but
"running the checklist passes". Every item below is judged by an executable command
wherever possible; the only human-judgment item (7) states explicit judgment criteria.
A command that prints FAIL is documentation debt — it cannot be traded for a promise
to "write it later".

## Precedence

1. If the project has its own variant of this skill (e.g. `docs-check-<project>`),
   use that instead of this one.
2. If the project's agent instructions (CLAUDE.md / AGENTS.md) declare docs-check
   configuration — canonical docs, exclusions, governed paths, an adoption date —
   those declarations pin the corresponding Step-0 values.
3. Otherwise, discover everything in Step 0.

## Step 0 — Discover the project profile

Resolve these before running any item, and record the resolved profile at the top of
the verification report. Auto-detection commands are starting points — confirm against
the repo's actual layout.

| Variable | What it is | How to resolve |
|---|---|---|
| `DEFAULT_BRANCH` | merge target | `basename "$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"`; fallback `main` |
| `BASE` | review range start | `git merge-base "$DEFAULT_BRANCH" HEAD` |
| `INSTRUCTION_DOCS` | agent instructions | existing ones among `CLAUDE.md`, `AGENTS.md` |
| `CANONICAL_DOCS` | authoritative onboarding/ops docs | `README.md` + `INSTRUCTION_DOCS` + every doc those files name as authoritative (rulebooks, handoff docs, evidence/report dirs) |
| `EXCLUDE_RE` | docs exempt from link checks | historical snapshots (design-history docs, spec/plan/review archives), `templates/**`, skill folders; if nothing applies, set `^$` — an empty pattern makes `grep -Ev` drop every line |
| `ENV_EXAMPLE` | env template | first existing of `.env.example`, `.env.sample`; may be none |
| `SRC_PATHS` | production source dirs | e.g. `src/`, `lib/`, `app/` — whatever holds shipped code |
| task runner + entry points | what a user can invoke | `Makefile` targets, `package.json` scripts, `justfile` recipes, the CLI `--help` surface |
| feature-doc convention | per-feature doc set | only if the project declares one (e.g. `specs/ plans/ reviews/ reports/`, ADRs); else item 6 is N/A |
| `HANDOFF_DOC` | session handoff/status doc | e.g. `HANDOFF.md`; if none, item 7 is N/A |
| `SOT_DOC` + `GOVERNED_PATHS` | domain source-of-truth doc and the code it governs | only if declared; else item 8 is N/A |

Exclusion principle: docs that describe a past point in time or intentionally cite
non-adopted alternatives (design-history docs, archived plans/reviews) are exempt from
path-existence checks — a "missing" path there may be a deliberate record of a road
not taken.

## Scope (no retroactive enforcement)

Checked: (a) `CANONICAL_DOCS`, (b) docs added or changed on this branch, (c) the
feature-doc set when item 6 applies. Pre-existing debt in untouched legacy docs is
recorded in the report as an observation, **not** a FAIL — legacy cleanup is its own
task. If the project records an adoption date for this gate, branches started before
it are out of scope.

## Checklist

### 1. README exists + onboarding is executable
```bash
test -f README.md
```
Expected: exit 0. **If FAIL, stop here** — every other item presupposes the docs the
README links to. If it exists, simulate a new user: execute the README's install/run
command blocks in their written order, inside an **isolated worktree + temporary HOME**
(the 5-minute onboarding test):
```bash
WT=$(mktemp -d)/wt && git worktree add "$WT" HEAD
cd "$WT" && export HOME=$(mktemp -d)
# ...run the README's commands in order...
# afterwards: git worktree remove --force "$WT"
```

**Side-effect boundary — never execute these; substitute a static check.** A temporary
HOME is not a sandbox for:
- **External service calls** — send/publish/deploy/notify/release commands hit real
  services over the network; no local isolation contains that.
- **Service-manager registration** — installers and `launchctl`/`systemctl`/cron
  commands register state at the user or system level, ignoring `$HOME`. (Origin
  incident: an install script run under a temp HOME still evicted the live launchd
  job it shadowed — the production schedule vanished until re-bootstrapped.)
- **Real credentials/config** — copying the env template (`cp $ENV_EXAMPLE .env`) is
  allowed **only inside the isolated worktree**, never in the real repo (clobbers the
  real `.env`).

Static check = the script/command exists and is executable (`test -x`), and its flags
and paths match what the README narrates. Verdict wording: "execution excluded
(side-effect boundary) — static check PASS".

Side-effect-free commands (build, test, lint, `--help`, render/dry-run modes) do not
qualify for exclusion — actually run them. The boundary exists to prevent damage, not
to weaken the gate.

PASS: every runnable command succeeds, and every excluded command passes its static
check. An excluded command is never a FAIL for not having been run.

### 2. System overview freshness
Enumerate reality, then check that the README (or the overview doc it links) mentions
all of it:
```bash
ls $SRC_PATHS                        # source modules — adapt to the project layout
grep -E '^[A-Za-z0-9_-]+:' Makefile  # or: jq -r '.scripts|keys[]' package.json / just --summary
<entrypoint> --help                  # the CLI surface, if the project has one
```
PASS: zero modules/targets/commands missing from the docs.

### 3. Documentation map
The README names every doc in `CANONICAL_DOCS` with its role and path (manual
cross-check against the Step-0 list). PASS: all of them mentioned.

### 4. Broken relative links/paths
Scope: `CANONICAL_DOCS` + docs changed on this branch, minus `EXCLUDE_RE`.
```bash
LINK_EXT='md|py|sh|ts|js|go|rs|rb|yml|yaml|toml|json|sql|txt'  # match the project's languages; avoid TLD-like extensions (io, ai, co)
BRANCH_DOCS=$(git diff "$BASE"..HEAD --name-only --diff-filter=ACMR -- '*.md' | grep -Ev "$EXCLUDE_RE")
for f in $CANONICAL_DOCS $BRANCH_DOCS; do
  [ -f "$f" ] || continue
  # capture both inline-code paths (`path.ext`) and markdown-link targets ([txt](path.ext#anchor));
  # the char class excludes ':' so http/mailto URLs never match — relative paths only
  refs=$( { grep -oE '`[A-Za-z0-9_./<>-]+\.('"$LINK_EXT"')`' "$f" | tr -d '`'
            grep -oE '\]\([A-Za-z0-9_./<>-]+\.('"$LINK_EXT"')' "$f" | sed 's/^](//' ; } | sort -u )
  for ref in $refs; do
    case "$ref" in *'<'*|*NN*|*YYYY*) continue ;; esac   # skip placeholders
    [ -e "$ref" ] && continue
    base=$(basename "$ref")
    find . -path ./.git -prune -o -name "$base" -print 2>/dev/null | grep -q . && continue
    echo "FAIL: $f -> $ref (not found anywhere)"
  done
done | sort -u
```
A reference whose exact path is missing still passes if a file with the same name
exists anywhere in the repo (directory-elision shorthand is allowed); only names found
nowhere FAIL. PASS: no output. *Optional:* if the project already ships `lychee` or
`markdown-link-check`, run that instead (e.g. `lychee --offline $CANONICAL_DOCS
$BRANCH_DOCS`) — it also resolves anchors and reference-style links. The bash above is
the zero-dependency fallback.

### 5. Secrets/config documentation parity
N/A only if the project neither reads env keys nor has an env template. Otherwise:
```bash
grep -rhoE '"[A-Z][A-Z0-9]*(_[A-Z0-9]+)+"' $SRC_PATHS | tr -d '"' | sort -u  # keys the code reads
grep -oE '^[A-Z][A-Z0-9_]*=' "$ENV_EXAMPLE" | tr -d '=' | sort -u            # keys the template documents
```
Only underscore-containing ALL-CAPS keys count — single-token uppercase strings
(tickers like `NVDA`, status literals like `OK`) are not env keys. Extend the first
grep to the project's env-access idiom where needed (`process.env.X`, `ENV['X']`,
`os.Getenv("X")`, single-quoted strings). **Never open the real `.env`** — only the
template. PASS: every key the code reads is in the template (code ⊆ template). Keys the
template documents but the code never reads are an **observation**, not a FAIL — they
may be framework- or runtime-injected.

### 6. Feature doc set
N/A (counts as PASS) when the project declares no per-feature doc convention, or when
the branch touches no source:
```bash
git diff "$BASE"..HEAD --stat -- $SRC_PATHS | grep -q . && echo APPLY || echo "N/A (no source changes)"
```
If APPLY, verify every doc the convention requires for this branch's feature `<feat>`
exists — e.g. under a spec/plan/review/report convention:
```bash
test -f specs/<feat>.md
test -f plans/<feat>.md
test -f reviews/code-<feat>.md   # and confirm the verdict in its content (e.g. APPROVE)
test -f reports/<feat>.md
```
PASS: N/A, or every required doc exists and verdict docs carry the required conclusion.

### 7. Handoff/status doc freshness (human judgment)
N/A if the project keeps no handoff doc. Otherwise:
```bash
git log --oneline -1
```
Timing semantics: the handoff doc conventionally updates **at merge time**, so during
pre-merge verification it must accurately describe the **previous merged state** — this
branch's work not appearing in it yet is not a FAIL. Judge three things:
(a) the commit hash/branch `H` it cites matches reality, with a docs-only tolerance:
```bash
git log <H>.."$DEFAULT_BRANCH" --name-only --format= | sort -u | grep -vE '\.md$' || echo "docs-only: PASS"
```
If that prints non-`.md` files, FAIL — the default branch holds code changes the
handoff doesn't know about. Docs-only follow-up commits don't change the "code state"
the handoff describes, so they don't invalidate it.
(b) its "done" claims match the gate status at that time; (c) its "next steps" section
is still valid. Any of the three off = FAIL.

### 8. Source-of-truth doc coherence
N/A if the project declares no domain source-of-truth doc. Otherwise:
```bash
git diff "$BASE"..HEAD --stat -- $GOVERNED_PATHS
```
If governed code changed but `SOT_DOC` did not, FAIL — unless an explicit, documented
rationale states why the doc is unaffected. (Example shape: a trading rulebook governs
signal-derivation code; signal code must not drift from the rulebook silently.)
PASS: governed-code change ⇒ doc change or explicit rationale.

## Execution procedure

- **Who**: if the project runs an orchestrator/verifier harness, delegate to the
  verifier agent — the orchestrator does not self-certify. In a solo session, run it
  yourself.
- **When**: immediately before the final report, as a merge condition — same standing
  as the project's code gates.
- **How**: resolve Step 0, then run items 1–8 in order. Record each item's **actual
  command output** with its PASS/FAIL verdict — plus the resolved Step-0 profile — in
  the project's verification-evidence location, or in `docs-check-report.md` alongside
  the final report if none is defined.
- FAIL items become checklist items in the rework brief, treated exactly like code-gate
  failures. Observations (out-of-scope legacy debt) are listed separately and do not
  block the merge.
