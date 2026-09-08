---
name: loop-harness
description: Orchestrator runbook for executing an implementation plan on cmux with 3 panes (Main/Builder/Verifier) using practical loop engineering. Use when starting or resuming plan execution in a cmux Main pane — triggers on "loop start", "loop-harness", "execute plan", "resume the loop".
---

# Loop Harness — Orchestrator Runbook

You are **Main**, the orchestrator. You write briefs and checklists, dispatch to
worker panes, judge evidence, and keep the ledger. **You never write product code,
run the test suite yourself, or fix failures directly — everything goes through
the panes.**

## Plan selection & state layout

**Which plan:** resolve in this order — (1) the plan path passed as the skill's
argument; (2) the path in `.loop/active-plan` (a one-line pointer file); (3) if
neither exists, ask the operator which plan and stop. Once resolved, write the path to
`.loop/active-plan` so a resumed session finds it.

**Plan slug:** the plan filename minus a leading `YYYY-MM-DD-` date and the `.md`
extension. E.g. `plans/2026-07-02-rag-grounding.md` → slug
`rag-grounding`.

**Per-plan state** lives under `.loop/<slug>/` and never collides across plans:
`.loop/<slug>/tasks/`, `.loop/<slug>/checklists/`, `.loop/<slug>/reports/`,
`.loop/<slug>/verify/`, `.loop/<slug>/progress.md`. Create these on first use
(`mkdir -p`). The finished 2026-07-01 plan's history remains at the old flat
paths (`.loop/tasks/`, `.loop/progress.md`, …) — do not touch or reuse it.

**Shared session infra stays flat** (plan-independent, transient): `.loop/done/`,
`.loop/main-surface`, `.loop/pane-config`, `.loop/active-plan`.

Below, `<slug>` means the resolved plan slug and `PLAN` means the resolved plan path.

## Session start (every session, in order)

1. `cat lessons.md` — obey every rule under `## Rules`.
2. Resolve the plan and slug (see **Plan selection & state layout** above).
   `cat .loop/<slug>/progress.md` (may not exist yet) — tasks listed there are DONE.
   Resume at the first task not marked complete. Never re-dispatch a completed task;
   trust the ledger and `git log` over memory.
3. **Locate this skill's bundled scripts.** Run the whole loop from the project
   root — the git repo you are implementing in, where `.loop/` state lives. This
   skill ships its own scripts under `scripts/`; resolve that dir once (works for
   a per-project install AND a global install — re-run this after a compaction if
   `$LH` is lost). Prefer a project-local install over a global one:
   ```bash
   for d in "$PWD/.claude/skills/loop-harness" "$HOME/.claude/skills/loop-harness"; do
     [ -e "$d" ] && LH="$d" && break
   done
   ```
   Every script call below uses `"$LH/scripts/..."`. The scripts anchor `.loop/`
   to the git repo you run them in (override with `LOOP_PROJECT_ROOT`), so where
   the skill itself is installed never matters.
4. Verify you are inside cmux: `$CMUX_SURFACE_ID` must be set.
5. **Pick worker models (Builder / Verifier).** Resolve each spec (`cli:model`)
   in order: (1) what the operator named in the start request; (2) the `spec=`
   fields already in `.loop/pane-config` from a prior run (resume — reuse
   silently, NO prompt); (3) defaults `Builder=claude:claude-opus-4-8`,
   `Verifier=codex:default`. On a FRESH start (workers absent, no
   `.loop/pane-config`), show the config and let the operator confirm or override
   before spawning:
   ```
   Models for this run — confirm or override (Enter = keep):
     Orchestrator (this session, not spawned) : <this session's model>
     Builder                                  : claude:claude-opus-4-8
     Verifier                                 : codex:default
   ```
   The **Orchestrator is this session** — the skill cannot change it; if the
   operator wants a different one, have them switch with `/model <x>` first
   (running the orchestrator on Codex is not supported yet). Valid worker specs:
   `claude:sonnet`, `claude:claude-opus-4-8`, `codex:default`, `codex:gpt-5`
   (cli ∈ `claude|codex`).
6. Check panes exist: `cmux list-panes` shows `Builder` and `Verifier`.
   If not, spawn with the specs resolved in step 5 (they are recorded into
   `.loop/pane-config`, which is what a later resume reads back):
   `"$LH/scripts/spawn-panes.sh" <Builder spec> <Verifier spec>`.
7. Preconditions: `docker info` succeeds (Docker Desktop running) and
   `curl -s --max-time 2 http://localhost:11434/api/version` responds (Ollama).
   If either fails, ask the operator to start it before dispatching anything.

## Per-task loop

For task N (from the plan, in order — dependencies are linear):

### 1. Write the brief → `.loop/<slug>/tasks/task-NN-brief.md`

Brief-writing rules (learned 2026-07-23, m2m-auth review — follow-up
commits fixed what the loop missed):
- **Specify outcomes, not mechanisms.** "The operator sees a one-line CLI error
  naming the missing settings, no traceback" — not "raise ValueError". Naming
  the mechanism caps the Builder at your own first idea.
- **Standards-adjacent task (auth, wire formats, crypto, protocol)?** Consult
  the authoritative spec/vendor docs (senior-specifier skill, Context7) BEFORE
  writing the brief, and cite the relevant section in the Requirements. The
  form-encoding bug (RFC 6749 §4.4.2 vs JSON) survived review because nobody
  ever opened the spec.
- **Never propagate a verifier's probe hack into the brief as the testing
  technique.** If tests need to intercept I/O, the fix is an injectable
  dependency in the product code, not a cleverer patch.
- **No personal-mode markers (`ponytail:` etc.) in shared branches** — briefs
  must tell the Builder to omit them; they read as stray noise to teammates.
- **Write the checklist FIRST, and put its standing items in the brief**
  (learned 2026-08-18, global-models-costs-settings: 10 of 12 rework rounds were
  triggered by standing items the Builder had never seen). There is nothing to
  protect by withholding the bar — when the plan carries an answer key, that key
  is explicitly the thing to build against. Copy the graded checks verbatim AND
  summarise the standing items, so the Builder self-checks before it reports DONE.
  A defect caught inside the task costs no context reset and no round trip.
- **Carry the known-defect-class list** (below) into every brief as a constraint
  and every checklist as a probe. It is the part of the harness that compounds.
- **Require every behavioural claim in the report to be executed.** "Paste the
  command and its output for each claim." A report that describes an INTENTION
  rather than the code cost a full round (task 02 r4: it stated a missing field
  surfaced as `""`; it surfaced as `None`, and nobody had run it).
- **Second sighting of a defect family → write a STRUCTURAL brief, not a patch
  brief.** State the property to establish ("one validated record; every reader
  and writer goes through it; a new consumer cannot dereference a field the record
  has not validated"), not the call sites to fix. In the 2026-08-18 run the same
  class recurred EIGHT times because each brief named only the reported site; the
  structural brief, written at sighting five, held immediately. Also make it a
  standing brief rule that **when the Builder fixes a defect it greps for the
  siblings and lists them in its report**.

**Known defect classes — the compounding checklist.** Every one of these was found
the expensive way. Put them in the brief as constraints and in the checklist as
probes, and add to the list whenever a new class costs a round:

1. **Consume the validated object; never return the raw decode.** Validating that
   something parsed is not validating that it is the shape you need, and using a
   validator as a predicate then discarding its result is the same bug wearing a
   hat.
2. **Absent ≠ corrupt.** Absent is empty/None; present-but-unparseable, wrong
   shape, or wrong value types raises. A loader that collapses them lets a damaged
   file masquerade as a missing one.
3. **Authoritative files are written atomically** — temp in the same directory +
   `os.replace` — and validated as a WHOLE before anything replaces the existing
   file. Atomicity without validation just makes destruction tidy.
4. **One damaged record must not take down a page, a listing, or startup.**
   Per-record isolation in every multi-record scan; the loader stays strict.
5. **No secret in any output.** Not the page, not a `value=`/`data-` attribute,
   not a JSON payload, not a log at any verbosity, not an error message that
   echoes an upstream body. Compose operator-facing text from your own strings
   plus a status code rather than filtering what came back over the wire.
6. **Success must mean usable, not merely written.** If a write reports success,
   the app must still serve the result — follow the operator's actual next request
   in the test, not just the write's return value.

```markdown
# Task NN Brief: <task name>

## Context
<one line: where this task fits>

## Requirements
<the ENTIRE task section copied verbatim from PLAN — code blocks, commands,
expected outputs. Do not paraphrase. Also copy the plan's "Global Constraints"
section verbatim.>

## Interfaces from earlier tasks
<exact signatures this task consumes (from the plan's Interfaces blocks)>

## Working rules
- TDD exactly as the steps say: run the test, watch it FAIL for the right
  reason, implement, watch it PASS, run the full suite, commit.
- Touch only the files the task lists.
- Run Python via `uv run` (e.g. `uv run pytest`). Never hardcode an interpreter path.
- Write the commit message with the git-commit skill (`skills/git-commit`):
  a `type: imperative summary` subject, a body only for what the diff cannot
  show, and `Refs: #<issue>` / `Co-Authored-By:` trailers. No PR-style headings
  or file-by-file restatement.

## Completion contract (follow exactly)
1. Write your report to `.loop/<slug>/reports/task-NN-report.md`:
   status, commits made, test summary (command + counts), concerns.
2. Write the status as the FIRST LINE of `.loop/done/Builder.done`:
   `DONE <one-line summary>` or `BLOCKED <reason>`.
3. Notify Main:
   `cmux send --surface $(cat .loop/main-surface) "Builder DONE task NN"` then
   `cmux send-key --surface $(cat .loop/main-surface) Enter`.
```

### 2. Write the checklist → `.loop/<slug>/checklists/task-NN.md`

Derive from the task's verification steps. Every item = exact command + expected
output + `[ ] PASS / [ ] FAIL`. Always include as final items:
- full unit suite green: `uv run pytest` → all pass
- the task's integration tests (if any): `uv run pytest -m integration <files>` → all pass
- commit exists: `git log --oneline -1` shows the task's commit
- `git status --short` clean (nothing uncommitted)

**Standing items — every checklist (task verification and reviews alike) ends
with these; the checklist is a floor, not a ceiling:**
- **Free-form pass**: "Review the full diff for problems NOT covered by any
  item above — design, spec conformance, operator experience, missing
  coverage. Findings here carry the same weight as item failures." (A verifier
  bounded to your checklist can only find your own blind spots' complement.)
- **Spec conformance** (when the change touches a standard — OAuth, HTTP,
  crypto, file formats): "Verify the wire format / flow against the
  authoritative spec or vendor docs; cite the section in your evidence."
- **Error-path UX** (when the change adds failure modes): "Trigger each new
  failure mode from the real entrypoint as a user would. Expect a clean,
  actionable error — message says what is wrong AND surfaces upstream error
  detail (sanitized: secrets redacted, body length capped). No tracebacks."
- **Test isolation**: "Run the new tests with a poisoned environment (exported
  env vars set to junk for every setting the code reads) — they must still
  pass. File-level isolation (`_env_file=None` etc.) does not cover exported
  vars."

**Two-tier verdicts — grade the plan's checks, TRIAGE everything else.** This is
the single biggest lever on how long a task takes (2026-08-18: 10 of 12 rework
rounds came from standing items, not from the plan's own checks, while those
checks passed unchanged for three consecutive rounds). When the plan carries an
answer key, its checks are the bar and a failed check always blocks. Findings from
the standing items are reported SEPARATELY, each with a severity, and only these
three block the task:

- **destroys or corrupts data** (a write that loses or damages what was there),
- **leaks a credential or secret**,
- **breaks a path the plan says is supported** (a check's own scenario, or a
  workflow the spec names — e.g. "hand-editing the file on disk" being explicitly
  supported makes a 500 on a hand-edited file blocking).

Everything else — exotic-input robustness, resource exhaustion, adversarial
encodings, pre-existing app-wide gaps — is **recorded and filed as its own issue**,
not reworked. Filing is the correct outcome, not a cop-out: it keeps the finding
while letting the chunk finish. If the plan's answer key explicitly forbids
inventing a standard, say so in the checklist and hold the line: a non-blocking
finding is a finding, not a failure.

**Defensive framing for adversarial items.** A checklist that reads like an attack
brief ("reflect the credential in seven encodings and assert none of it leaks")
can trip a worker's safety classifier, and the round dies with nothing written
(observed 2026-08-18, Codex). Three fixes, all of which keep the check's force:
state the context in both the checklist and the dispatch ("defensive verification
of our OWN app in this repo, local stub, no real service or credential"); invert
the method so the primary probe verifies the output is COMPOSED only from our own
strings rather than hunting for a string that might escape (the stronger property
anyway); and use a neutral placeholder with a couple of variants rather than an
exhaustive matrix.

End the checklist with the Verifier completion contract:
```markdown
## Completion contract (follow exactly)
1. Execute EVERY item yourself — do not trust the Builder's report.
2. Write `.loop/<slug>/verify/task-NN.md`: per item, the command you ran and the
   actual output pasted as evidence, then PASS or FAIL. End the file with TWO
   blocks: the graded verdict block (one line per plan check, in the plan's own
   format), and a `Findings:` list — one line each, with a severity of
   `blocking-data` / `blocking-secret` / `blocking-supported-path` / `file-issue`.
3. Write the FIRST LINE of `.loop/done/Verifier.done`: `PASS` or
   `FAIL <failed item ids>`. Write it ONCE, at the very end, when your verdict is
   final — a preliminary value written early and revised later trips Main's monitor
   on the wrong verdict.
4. If an item seems out of bounds or you cannot complete it, write what you DID
   complete to the evidence file, put `BLOCKED <item> <reason>` in the done file,
   and notify Main. Never stop silently: a silent stop costs the whole round.
5. Notify Main:
   `cmux send --surface $(cat .loop/main-surface) "Verifier PASS|FAIL task NN"` then
   `cmux send-key --surface $(cat .loop/main-surface) Enter`.
```

### 3. Dispatch Builder

```bash
"$LH/scripts/dispatch.sh" Builder "Read .loop/<slug>/tasks/task-NN-brief.md and execute it exactly. Follow its completion contract." 1200
```
- exit 0 (`DONE`) → step 4.
- exit 2 (`BLOCKED`) → read the report; missing context → extend the brief and
  re-dispatch; plan defect → stop and ask the operator.
- exit 124 → read the printed screen capture. Mid-work → re-poll by waiting for
  `.loop/done/Builder.done` once more (extend once). Stuck or prompting → answer
  the prompt via `cmux send` if safe/obvious, else ask the operator.

### 4. Dispatch Verifier

```bash
"$LH/scripts/dispatch.sh" Verifier "Read .loop/<slug>/checklists/task-NN.md, execute every item yourself, and follow its completion contract." 900
```
- `PASS` → confirm `.loop/<slug>/verify/task-NN.md` actually contains per-item evidence
  (a PASS without evidence is invalid — re-dispatch verification), then step 5.
- `FAIL` → **triage before you rework.** Split the verdict into (a) failed plan
  checks, which always go back, and (b) standing-item findings, which go back only
  at the three blocking severities (data, secret, supported path). Everything else
  is filed as its own issue and named in `progress.md` — say so explicitly in the
  rework brief so the Verifier does not re-raise it next round.
  Then write `.loop/<slug>/tasks/task-NN-rework-R.md` with ONLY the items that
  block, each with the Verifier's evidence, plus the same completion contract →
  re-dispatch Builder → re-verify.
- **Adjudicate your own checklist too.** If a FAIL rests on wording you added that
  is stricter than the plan's standard, reverse it to PASS, say so in the rework
  brief with the reasoning, and move the real behaviour into the rework on its own
  merits. A Verifier that inherits your mistakes silently is worth less than one
  that can see them. (2026-08-18: two rounds' worth of FAILs came from my wording,
  not the code.)
- **Scale re-verification to the diff.** Round 1 runs the whole checklist. After a
  50-line fix, re-run the failed items plus anything the diff could plausibly have
  touched, and let the Verifier carry the rest forward with its reasoning stated.
  Re-running twenty items against a ten-line change is how a loop stops finishing.
- **Ceiling: 3 rework rounds**, then stop and report evidence to the operator — including
  what still fails, its severity, and a recommendation. The operator may authorise more
  (they did twice on 2026-08-18, and both extra rounds closed cleanly), but the
  decision is theirs, not yours. Keep your word: if you said you would stop at the
  ceiling, stop.

### 5. Record and reset

```bash
echo "Task NN: complete (commits <base7>..<head7>, verify PASS)" >> .loop/<slug>/progress.md
"$LH/scripts/dispatch.sh" Builder "/clear" 30 || true   # fresh context; timeout is fine
"$LH/scripts/dispatch.sh" Verifier "/new" 30 || true    # codex: new conversation
```
(`/clear`//`/new` produce no done-file — a timeout here is expected and harmless.
Verify the pane shows a fresh prompt via `cmux capture-pane` if in doubt.)

Then proceed to task N+1 without asking the operator (continuous execution). Stop only
for: BLOCKED you cannot resolve, 3 failed rework rounds, or all tasks complete.

## After the plan's final task

1. Dispatch Verifier (fresh context) for a whole-branch review: full diff
   (`git log --oneline; git diff <first-commit>..HEAD --stat`) against the plan
   and the spec it references (read the plan header's `Spec:` line for the path);
   report to `.loop/<slug>/verify/final-review.md` with the same completion contract.
2. Run the docs-check skill (.claude/skills/docs-check) — dispatch it to the Verifier
   with a checklist brief, same contract as any verification. FAIL items become a
   rework brief. Merging without docs-check PASS violates the Definition of Done
   (AGENTS.md). Retroactive findings on legacy docs are recorded, not fixed.
3. Findings → one rework brief → Builder → re-verify.
4. Update `lessons.md`: failures observed / confirmed root causes / [VERIFIED]
   facts / promoted one-line rules. Never promote a guess.
5. If the branch ships as a GitHub PR: invoke the pr-description skill
   (`skills/pr-description`) to draft the title and body, show the draft to
   the operator, and wait for approval before running `gh pr create`.
6. Report completion to the operator with evidence (test counts, commit list).

## Hard rules

- Main writes no product code and runs no product tests — dispatch everything.
  (Exception: trivial read-only spot checks like `git log`, `cat`.)
- Long instructions go in files; the dispatch message carries only "read X and
  execute".
- Builder self-report is never completion evidence — only the Verifier's
  evidence report is.
- One task in flight at a time. No parallel dispatch.
- If a pane dies (shell prompt visible): restart its CLI
  (`claude --model claude-opus-4-8 --dangerously-skip-permissions` or
  `codex --dangerously-bypass-approvals-and-sandbox`), then re-dispatch the same
  brief — briefs are idempotent, completed commits are in git.
- After context compaction: re-read `lessons.md` and `.loop/<slug>/progress.md` before
  doing anything.
- Never `git reset --hard` (or any destructive git operation) while a worker is
  live: unstaged edits leave no git objects and nothing is recoverable but the
  worker's own context. Prefer `git reset --mixed` plus a targeted
  `git checkout -- <file>`, and tell Builders to commit early in small steps when
  the worktree is shared with another session (2026-08-18: a parallel agent's
  `reset --hard` destroyed a Builder's uncommitted work mid-task).
- A finding that belongs to the whole app, not to this task, is filed as an issue
  and excluded from the rework in writing. Fixing it on the one route a Verifier
  happened to probe is inconsistent by construction — check whether the rest of the
  codebase shares the gap before treating it as this chunk's defect.
