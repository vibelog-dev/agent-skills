---
name: senior-specifier
description: Use when an engineering request is vague or underspecified ("make it secure", "apply encryption properly", "add validation", "improve architecture") after brainstorming or debugging has concluded but before an implementation plan is written. Also use when a spec's technical choices depend on library versions, security or cryptography guidance, or other facts that go stale.
---

# Senior Specifier

## Overview

Vague requests must not reach the planner. Convert them into a Senior Engineering Task Brief — a precise engineering contract grounded in project evidence, not model memory.

**Core principle: every technical claim in the brief is either evidence-backed (a named file or official source) or a labeled assumption. Nothing in between.**

Workflow position: superpowers:brainstorming or superpowers:systematic-debugging → **senior-specifier** → superpowers:writing-plans. This skill does not brainstorm, plan, implement, or verify — it writes the contract the planner plans from and the verifier checks against.

## Decision rule

If the request already names concrete mechanisms, versions, error formats, and acceptance criteria, pass it through and add only what is missing. Otherwise write the full brief. When context is missing: inspect the project first, make safe assumptions and label them, and ask the user only when a decision is high-risk, irreversible, or impossible to infer.

## Classify every major recommendation

| Class | Examples | Evidence required |
|---|---|---|
| Stable | design principles, dependency direction, test structure, error-handling patterns | engineering judgment is enough |
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
The exact pattern, protocol, library, algorithm, data model, or
interface — and why it fits THIS project. Every major
recommendation ends with:
[Confidence: High|Medium|Low — evidence: <file, doc, or "not freshness-verified">]

## Assumptions
Every unverified claim, one per line, each starting "ASSUMPTION:".
Verified facts stay in Current context.

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
all are true.

## Verification plan
Runnable commands using the project's own runners (cite the actual
script, e.g. `npm test` → `node --test test/`), named failure-case
tests, lint/build commands, manual checks.
```

## Handoff check

The handoff check is a separate adversarial pass over the finished draft — not a glance while writing. Switch roles: you are now the verifier trying to prove the brief undeliverable. In agentic workflows, dispatch a fresh-context subagent with the draft and this checklist and fix what it finds; the author's context hides its own contradictions.

Walk every acceptance criterion and every failure-mode outcome through the brief's own specified changes:

- **Name the mechanism and the check.** Which numbered item of the approach makes this criterion true, in which file — and which named test in the verification plan proves it? No mechanism → add one or fix the criterion. No test → add one.
- **Trace the real execution path.** Middleware order, framework default handlers, and the declared change surface must actually produce the promised status and shape. A promised JSON 500 requires an error handler inside the change surface; a request rejected by an earlier middleware never reaches the auth check that was supposed to 401 it.
- **Propagate accepted exceptions into the criterion wording.** When the trace surfaces an exception you accept ("malformed JSON is rejected before auth"), rewrite the criterion to encode it: "every request that reaches the router returns 401" is checkable; "every request returns 401" alongside that exception is a spec bug. A criterion promises only what its mechanism was verified to produce — no promised error shapes or messages beyond what was checked.
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

- **Library behavior asserted from memory.** Example: "Zod strips unknown keys by default" written unchecked, producing an acceptance criterion (reject unknown fields) that the specified mechanism cannot satisfy (needs `.strict()`). When an acceptance criterion depends on library behavior, verify it for the installed version or name the exact API that provides it.
- **Facts and guesses interleaved.** Unlabeled assumptions read as facts; the planner inherits them as truth. Assumptions live only in the Assumptions section.
- **Human-review flag omitted exactly where it matters.** Crypto and auth briefs are the ones that skip it. The flag is the first line, so it cannot be forgotten at the end.
- **Verification plan with no runnable command.** "Add tests" is not verifiable; the project's real test command exercising named failure cases is.
- **Caret ranges cited as versions.** `^4.19.2` is a constraint; the lockfile's `4.19.2` is evidence.
- **Acceptance criteria the declared change surface cannot deliver.** A brief promised `500 {"error":"internal"}` on decrypt failure while restricting changes to two function bodies — with no error middleware in scope, the framework's default HTML error page wins. The handoff check catches exactly this.
