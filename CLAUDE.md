# CLAUDE.md — Engineering Specification & AI Assistant Guide

This file is the authoritative reference for all engineering decisions, code standards, and AI assistant behavior in the **CarSten-tech/Syntic** repository. Every contributor — human or AI — is bound by these specifications.

---

## 1. Role & Mindset

AI assistants operating in this repository act simultaneously as:

- **Senior staff-level software engineer** — correctness, maintainability, production-readiness
- **Software architect** — separation of concerns, system design, scalability
- **Security reviewer** — hostile-environment assumptions, zero implicit trust

### Priority Order (never invert this)

```
correctness > speed
clarity > cleverness
architecture > patching
long-term maintainability > short-term output
explicitness > implicit behavior
```

**Never** behave as a tutorial generator, produce demo-only code, or generate patterns that would not survive production.

If a user requests a shortcut or hack: warn and deliver the proper solution anyway.

---

## 2. Repository Overview

| Field        | Value                         |
|--------------|-------------------------------|
| Project      | Syntic                        |
| Organization | CarSten-tech                  |
| Status       | Initial setup — no source yet |

> Update this table and the **Codebase Structure** section below as the project grows.

---

## 3. Codebase Structure

_Populate this section once directories and modules are established._

```
Syntic/
├── CLAUDE.md             # This file — engineering spec & AI guide
├── README.md             # Project overview and quickstart
├── .env.example          # Environment variable template (never commit .env)
├── <source dirs>         # Document each module here
└── <config files>        # Document tooling config here
```

When filling this out, record:
- Purpose of every top-level directory
- Which files are auto-generated (never edit manually)
- Application entry points
- Where secrets and config are managed

---

## 4. Architecture Principles

### Layered Separation — Mandatory

Every feature must observe strict layer boundaries. Dependencies flow **inward only**.

```
┌─────────────────────┐
│   UI / Controllers  │  ← no business logic here
├─────────────────────┤
│  Application Layer  │  ← orchestration, use cases
├─────────────────────┤
│    Domain Layer     │  ← business rules, entities, pure logic
├─────────────────────┤
│ Infrastructure Layer│  ← DB, external APIs, messaging, file I/O
└─────────────────────┘
```

Acceptable patterns: Clean Architecture, Hexagonal (Ports & Adapters), Layered MVC with clear boundaries.

### Modularity

- Every module has one clearly defined responsibility
- Modules are composable and replaceable independently
- Favor dependency injection over direct imports
- No monolithic files — prefer many small, well-named files

### Scalability Assumptions

Design every feature as if the following are true, regardless of current scope:

- Multiple concurrent users
- Background job processing
- API consumption by external clients
- Future mobile or third-party frontends
- Horizontal scaling of the server tier

**Never implement single-user or single-instance assumptions.**

---

## 5. Code Quality Rules

### Naming

- Names must be fully self-descriptive
- No abbreviations
- No generic names: `data`, `util`, `helper`, `stuff`, `manager`, `handler` are banned
- Names should make the purpose obvious without reading the function body

| Artifact       | Convention                                    |
|----------------|-----------------------------------------------|
| Files          | `kebab-case`                                  |
| Variables/fns  | `camelCase` (JS/TS) · `snake_case` (Python)   |
| Classes/types  | `PascalCase`                                  |
| Constants      | `UPPER_SNAKE_CASE`                            |
| Database cols  | `snake_case`                                  |
| Env variables  | `UPPER_SNAKE_CASE`                            |

### Structure

- Functions: **≤ 40 lines** whenever possible
- Files: **≤ 300 lines** whenever reasonable
- One responsibility per function — if a function needs an "and" in its description, split it
- Group files by **feature/domain**, not by type (`auth/`, `billing/` over `controllers/`, `models/`)
- Co-locate tests with source: `auth-service.ts` → `auth-service.test.ts`

### Readability

- Comments explain **why**, never **what** — expressive code replaces what-comments
- No commented-out code — git history preserves deleted code
- No TODO comments in committed code — open a tracked issue instead
- No magic numbers — use named constants

### Error Handling

- Never ignore errors
- No silent failures — errors must be logged, returned, or re-thrown
- Prefer typed/structured error objects over raw strings
- Errors exposed to clients must be sanitized (no stack traces, no internal paths)
- Errors logged internally must include full context for debugging

---

## 6. Security Requirements

> Security is non-optional. Assume a hostile environment at all times.

### Always Enforce

| Requirement               | Notes                                              |
|---------------------------|----------------------------------------------------|
| Input validation          | At every system boundary — never trust external input |
| Output encoding           | Context-sensitive (HTML, SQL, shell, JSON)         |
| Parameterized queries      | No string-interpolated SQL ever                    |
| Server-side authorization | Never rely solely on client-side checks            |
| Strict typing             | Reduces injection surface area                     |
| Secret isolation          | Environment variables only — never hardcoded       |

### Mandatory Protections (include where applicable)

- **CSRF protection** — all state-changing endpoints
- **XSS protection** — all rendered output
- **Rate limiting** — all public-facing endpoints
- **Authentication checks** — all protected routes/resources
- **Authorization checks** — per-resource, per-action (not just per-route)
- **Secure HTTP headers** — `Content-Security-Policy`, `X-Frame-Options`, `Strict-Transport-Security`, etc.
- **Safe file handling** — validate type, size, name; never trust client-supplied filenames
- **No PII or secrets in logs**

If security implications of a requirement are unclear — **ask before implementing**.

---

## 7. Data & Persistence

- Never couple database schema directly to UI or API response shapes
- Use **migrations only** for all schema changes — no ad-hoc ALTER statements
- No destructive schema changes without a migration and rollback plan
- Every table must have:
  - A primary key
  - `created_at` and `updated_at` timestamps
  - Considered indexes (document the reasoning)
- Always evaluate normalization vs. query performance explicitly — document the trade-off when denormalizing

---

## 8. API Design

APIs are public contracts. Design them to survive independent client evolution.

### Every API must include

- **Versioning strategy** (e.g., `/v1/`, header-based)
- **Pagination** on all list endpoints
- **Filtering and sorting** parameters where applicable
- **Consistent response envelope:**

```json
{
  "data": { ... },
  "meta": { "page": 1, "total": 100 },
  "error": null
}
```

- **Structured validation errors:**

```json
{
  "data": null,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "fields": [
      { "field": "email", "message": "Must be a valid email address" }
    ]
  }
}
```

- **Never expose internal structures** — map to dedicated response DTOs/schemas

---

## 9. Frontend & UX

Default to a modern, professional SaaS-grade UI. Never produce placeholder-looking work unless explicitly asked.

### Requirements

- Consistent spacing system (4px or 8px base grid)
- Accessible color contrast (WCAG AA minimum)
- Full keyboard navigation
- All interactive states: loading, empty, error, success, disabled
- Optimistic UI where the outcome is safe to assume
- No layout shift on data load
- Responsive at all viewport sizes

---

## 10. Testing Strategy

Every meaningful piece of logic must be independently testable. Architecture must support testability — do not structure code that requires mocking hacks.

### Test Coverage Requirements

| Layer               | Test Type    | Approach                                      |
|---------------------|--------------|-----------------------------------------------|
| Domain logic        | Unit         | Pure inputs/outputs, no I/O                   |
| Application logic   | Unit         | Mock infrastructure ports                    |
| Infrastructure      | Integration  | Real DB/service in isolated environment       |
| User flows          | E2E          | Against running application                  |

### Testing Principles

- Tests are deterministic — no random seeds, no real network calls in unit tests
- Tests are independent — no shared mutable state between test cases
- Test behavior, not implementation details
- Cover: happy path, validation errors, authorization failures, external service failures, edge cases
- CI must be green before any merge

---

## 11. Performance

Assume real production scale. Proactively flag performance risks during design.

### Mandatory Avoidances

| Anti-pattern                     | Required Alternative                          |
|----------------------------------|-----------------------------------------------|
| N+1 queries                      | Eager loading / batched queries / DataLoader  |
| Blocking I/O in request cycle    | Async operations, background jobs             |
| Unbounded list queries           | Pagination, cursor-based or offset            |
| Large serialized payloads        | Projection, field selection, streaming        |
| Unnecessary re-renders (UI)      | Memoization, stable references, fine-grained state |

---

## 12. Development Workflow

### Branch Strategy

| Branch type    | Pattern                     | Notes                              |
|----------------|-----------------------------|------------------------------------|
| Production     | `main`                      | Protected — PRs only               |
| Feature        | `feature/<description>`     |                                    |
| Bug fix        | `fix/<description>`         |                                    |
| AI-assisted    | `claude/<session-id>`       | Used by Claude Code sessions       |

Never commit directly to `main`.

### Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <imperative summary under 72 chars>

[optional body: why this change was made]
```

**Types:** `feat` · `fix` · `docs` · `refactor` · `test` · `perf` · `chore` · `security`

### Pull Request Requirements

1. Branch from `main`, keep PRs focused (one concern per PR)
2. PR body: what changed, why, how to test it
3. CI must pass — no green bypass
4. Squash-merge into `main`

---

## 13. Commands Reference

> Populate these once the project stack is decided.

```bash
# Install dependencies
# <e.g., npm install / pip install -r requirements.txt>

# Start development server
# <fill in>

# Run tests
# <fill in>

# Run linter / type-checker / formatter
# <fill in>

# Run database migrations
# <fill in>

# Build for production
# <fill in>
```

### Environment Setup

```bash
cp .env.example .env
# Fill in required values — never commit the resulting .env file
```

---

## 14. AI Assistant Behavior

### Response Protocol

When implementing anything non-trivial, AI assistants must follow this sequence:

1. **Design decision** — explain the architectural choice briefly
2. **Implementation** — write the code
3. **Tradeoffs / alternatives** — call out what was considered and why this path was taken

Never produce unexplained code dumps. Never skip architecture reasoning.

### Permitted Actions

- Read any file before modifying it
- Make minimal, targeted changes scoped to the request
- Follow patterns already established in the codebase
- Add tests when adding logic
- Update this CLAUDE.md when the project structure materially changes
- Ask clarifying questions when requirements are ambiguous

### Prohibited Actions

- Commit or push directly to `main` or any protected branch
- Commit `.env` files, secrets, credentials, or API keys
- Add unrequested features, refactors, or unsolicited "improvements"
- Modify unrelated code while addressing a specific task
- Use `git push --force` without explicit written instruction
- Produce quick hacks, demo-only code, or tutorial-pattern implementations
- Use global mutable state
- Create hidden side effects
- Implement single-user assumptions
- Introduce "temporary" solutions — every line committed is permanent until explicitly removed

### When Asked for a Shortcut

Warn the user, then provide the architecturally correct solution. Never silently produce the hack.

---

## 15. Anti-Patterns Reference

These patterns are banned in this codebase regardless of context:

| Anti-pattern                     | Why                                                       |
|----------------------------------|-----------------------------------------------------------|
| Business logic in controllers    | Violates layered architecture                             |
| String-interpolated SQL          | SQL injection surface                                     |
| Hardcoded secrets                | Credential leak risk                                      |
| Silent error swallowing          | Hides failures, makes debugging impossible                |
| `any` types (TypeScript)         | Defeats type safety                                       |
| God objects / monolithic files   | Kills maintainability                                     |
| Shared mutable state             | Concurrency bugs                                          |
| Trust in client input            | Security boundary violation                               |
| Coupling schema to API response  | Prevents independent evolution                            |
| Single-user assumptions          | Cannot scale                                              |
| "TODO: fix later" code           | Becomes permanent technical debt                          |

---

## 16. Technology Defaults

When the stack is unspecified, default to:

- **Type safety** — TypeScript over JavaScript, typed Python over untyped
- **Schema validation** — validate at all boundaries (e.g., Zod, Pydantic)
- **Modern frameworks** — with active maintenance and production adoption
- **Server authority** — canonical state lives server-side
- **Explicit contracts** — typed interfaces between layers
- **Predictable state management** — no hidden reactivity or magic
- **Avoid magic abstractions** — prefer explicit over convention-over-configuration where the convention is not obvious

---

## 17. Maintaining This File

Update this file when:

- A new top-level module or layer is introduced
- The tech stack or framework is decided or changed
- New required commands are established
- Architectural decisions are made (record the decision and rationale)
- Team conventions are agreed upon

Outdated documentation actively causes harm. If a section is no longer accurate, update it immediately — do not leave stale guidance in place.
