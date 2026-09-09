---
name: spec-review
description: Use when an engineering request is vague or underspecified ("make it secure", "apply encryption properly", "add validation", "improve architecture") after brainstorming or debugging has concluded but before an implementation plan is written. Also use when a spec's technical choices depend on library versions, security or cryptography guidance, or other facts that go stale.
---

# Spec Review

## Overview

Vague requests must not reach the planner. Convert them into a Senior Engineering Task Brief — a precise engineering contract grounded in project evidence, not model memory.

**Core principle: factual claims need evidence (a named file or official source); proposed design decisions need project-specific rationale; unknowns need labeled assumptions. Reference each assumption wherever a decision or claim depends on it.**

Workflow position: superpowers:brainstorming or superpowers:systematic-debugging → **spec-review** → superpowers:writing-plans. This skill does not brainstorm, plan, implement, or verify — it writes the contract the planner plans from and the verifier checks against.

## Decision rule

If the request already names concrete mechanisms, versions, error formats, and acceptance criteria, preserve its structure and add or correct only what is needed. Otherwise write the full brief. Both paths require the evidence checks below and the handoff check; specificity is not evidence of correctness. Preserve user requirements when correcting technical claims. When context is missing: inspect the project first, make safe assumptions and label them, and ask the user only when a decision is high-risk, irreversible, or impossible to infer.

## Classify every major recommendation

| Class | Examples | Evidence required |
|---|---|---|
| Stable | design principles, dependency direction, test structure, error-handling patterns | project-specific rationale for design decisions; evidence for factual claims they rely on |
| Version-sensitive | framework/library APIs, package behavior, cloud, database, deploy tooling | exact installed version from lockfile/manifest, plus official docs for that version |
| Fast-changing / high-risk | security, cryptography, authn/authz, compliance, payments, production infra | authoritative source (OWASP, NIST, vendor docs) and `Needs human review: yes` |

Check sources in this order: (1) codebase and its conventions, (2) lockfiles, manifests, config files, existing tests, (3) official documentation for the installed version, (4) recognized standards, (5) changelogs/release notes when version behavior matters. Official docs over blog posts; project-local evidence over generic advice. If a source cannot be checked (no web access, undeterminable version), say so in the brief: mark the item `not freshness-verified` and avoid version-specific instructions for it.

## The brief (required output shape)

Every section below is REQUIRED. A section with nothing to say reads `None` — never silently absent.

```markdown
# Senior Engineering Task Brief: <title>
Needs human review: yes | no
  (yes if touching auth, authz, crypto, migrations, payments,
   data loss, compliance, or production infrastructure)

## Goal
The problem being solved, one paragraph.

## Technical domain
security / data / API / backend / frontend / infrastructure /
testing / performance / architecture / other

## Current context
Only what was OBSERVED: files inspected, exact installed versions
cited as name@version from the lockfile (not caret ranges),
existing helpers/patterns/conventions the approach must reuse.

## Concrete technical approach
The proposed pattern, protocol, library, algorithm, data model, or
interface — and the project-specific rationale for choosing it.
Distinguish proposed decisions from observed behavior. Reference
supporting facts and any assumption IDs each recommendation relies on.
Every major recommendation ends with:
[Confidence: High|Medium|Low — basis: <file/doc references, assumption IDs,
or engineering judgment with the rationale stated above>]
Mark unchecked version-sensitive claims `not freshness-verified`.

## Assumptions
Every unverified factual claim or assumed condition, one per line,
each starting "ASSUMPTION:" with an ID, e.g. "ASSUMPTION: A1 — ...".
Reference these IDs wherever the brief depends on them. Proposed
design decisions belong in Concrete technical approach; observed
facts belong in Current context.

## Constraints
Compatibility, performance, security, reliability, migration,
maintainability, cost, deployment, rollback.

## Architecture impact
Modules/files touched, dependencies added or deliberately avoided,
data flow, ownership boundaries, coupling introduced or removed.

## Failure modes
Invalid input, missing config, permission failure, network failure,
race conditions, data corruption, partial failure, rollback failure,
observability gaps — what happens in each.

## Acceptance criteria
Specific checkable conditions; implementation is complete only when
all are true. Identify criteria derived from explicit user requirements
so the handoff check preserves them.

## Verification plan
Runnable commands using the project's own runners (cite the actual
script, e.g. `npm test` → `node --test test/`), named failure-case
tests, lint/build commands, manual checks.
```

## Handoff check

The handoff check is a separate adversarial pass over the finished draft — not a glance while writing. Switch roles: you are now the verifier trying to prove the brief undeliverable. In agentic workflows, dispatch a fresh-context subagent with the draft and this checklist and fix what it finds; the author's context hides its own contradictions.

Walk every acceptance criterion and every failure-mode outcome through the brief's own specified changes:

- **Name the mechanism and the check.** Which numbered item of the approach makes this criterion true, in which file — and which named test in the verification plan proves it? No mechanism → add one or correct an unsupported draft claim, preserving user requirements. No test → add one.
- **Trace the real execution path.** Middleware order, framework default handlers, and the declared change surface must actually produce the promised status and shape. A promised JSON 500 requires an error handler inside the change surface; a request rejected by an earlier middleware never reaches the auth check that was supposed to 401 it.
- **Preserve requirements when resolving exceptions.** Distinguish an overstatement introduced by the draft from an explicit user requirement. If the draft invented "every request returns 401" but malformed JSON is rejected before auth, narrow that draft claim to requests reaching the auth check. If the user required the broader behavior, change the mechanism to satisfy it within the authorized scope, or surface the conflict as an unresolved decision for the user. Never silently weaken a user requirement to fit the implementation; keep the affected criterion unresolved until a compliant mechanism or a user-authorized change is established.
- **Trace repeat runs of anything stateful.** Migrations, backups, seeds, and destructive verification steps (byte-flips, key rotation, file mutation): walk the second run step by step. A verification step that mutates state must restore it, or the plan is one-shot. "Idempotent" claimed without that trace is an assumption, not a criterion.
- **Every verification command must run in this repo as it exists.** No git commands in a non-repo, no scripts that are not in the manifest.

## Vague request → contract

| Vague | The brief must decide |
|---|---|
| "make it secure" | auth boundary, permission checks, input validation, secret handling, abuse cases, logging, verification for each |
| "apply encryption properly" | algorithm, key handling, nonce/IV strategy, storage format, tamper detection, error handling, migration of existing data, tests |
| "add validation" | schema, required fields, error format, client/server split, edge cases, test coverage |
| "improve architecture" | coupling points, module boundaries, dependency direction, data ownership, trade-offs, migration risk |

The generic forms — "use proper error handling", "follow best practices", "write tests", "make it scalable" — never appear in a brief; each becomes a named mechanism, in a named place, with a named check.

## Common mistakes

- **Library behavior asserted from memory.** An unchecked claim about a schema library's handling of unknown keys can produce a rejection criterion that the selected API does not satisfy. When an acceptance criterion depends on library behavior, verify the exact API and behavior for the installed version. Naming an API does not replace verification; if verification is unavailable, record the assumption and mark it `not freshness-verified` without prescribing an unchecked version-specific API.
- **Facts, decisions, and assumptions conflated.** Unlabeled assumptions read as facts; the planner inherits them as truth. Define assumptions in the Assumptions section and reference their IDs at each dependency. State design decisions as proposals with rationale, not as observed facts or unknowns.
- **Human-review flag omitted exactly where it matters.** Crypto and auth briefs are the ones that skip it. The flag is the first line, so it cannot be forgotten at the end.
- **Verification plan with no runnable command.** "Add tests" is not verifiable; the project's real test command exercising named failure cases is.
- **Caret ranges cited as versions.** `^4.19.2` is a constraint; the lockfile's `4.19.2` is evidence.
- **Acceptance criteria the declared change surface cannot deliver.** A brief promised `500 {"error":"internal"}` on decrypt failure while restricting changes to two function bodies — with no error middleware in scope, the framework's default HTML error page wins. The handoff check catches exactly this.
