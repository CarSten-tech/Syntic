# CLAUDE.md — Engineering Specification & AI Assistant Guide

This file is the authoritative reference for all engineering decisions, code standards, and AI assistant behavior in the **CarSten-tech/Syntic** repository. Every contributor — human or AI — is bound by these specifications.

> **Core premise:** Every project built here is a **production-grade SaaS application** held to the highest engineering standard. There are no prototypes, no MVPs cut with shortcuts, no "we'll clean it up later." The first line of code sets the quality floor — and that floor is high.

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

Every output must be consistent with a world-class SaaS product. The benchmark is not "does it work" but "would a senior engineer at a top-tier SaaS company be proud to ship this."

If a user requests a shortcut or hack: warn and deliver the proper solution anyway.

---

## 2. Repository Overview

| Field        | Value                         |
|--------------|-------------------------------|
| Project      | Syntic                        |
| Organization | CarSten-tech                  |
| Product type | SaaS application              |
| Standard     | Highest — production-grade from day one |
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

Default to a modern, professional SaaS-grade UI. The benchmark is Stripe, Linear, Vercel, Notion. Never produce placeholder-looking work unless explicitly asked.

### Design System

- Use a **design token system** for all visual values — never hardcode raw hex, px, or rem values directly in component styles
- Token categories: `color`, `spacing`, `typography`, `radius`, `shadow`, `z-index`, `transition`
- All components must be built from the token set — no one-off magic values
- Maintain a **component library** — never duplicate UI logic across features
- Components must be self-contained: style, state, and behavior co-located

### Spacing & Layout

- Base grid: **8px** (4px allowed for micro-adjustments only)
- Spacing scale: `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 · 96 · 128`
- No arbitrary pixel values outside the scale
- Use CSS logical properties (`padding-inline`, `margin-block`) for i18n-readiness
- Layouts must not break at any viewport width between 320px and 2560px

### Typography

- Define a **type scale** — minimum: `xs · sm · base · lg · xl · 2xl · 3xl · 4xl`
- One font family for UI, optionally a second for display/headings
- Line length: 60–80 characters for body text (max `prose` width ~65ch)
- Never use `font-size` below 12px
- `font-weight` must come from the token system — no arbitrary values

### Color System

- Semantic color tokens required:
  - `color-primary`, `color-primary-hover`, `color-primary-subtle`
  - `color-danger`, `color-warning`, `color-success`, `color-info`
  - `color-surface`, `color-surface-raised`, `color-surface-overlay`
  - `color-text`, `color-text-secondary`, `color-text-disabled`
  - `color-border`, `color-border-strong`
- Never use raw hex values in component code — always reference tokens
- WCAG AA contrast minimum for all text (4.5:1 normal, 3:1 large)
- Design for **dark mode from the start** — token system must support it

### Interactive States

Every interactive element must implement all applicable states:

| State      | Required for                         |
|------------|--------------------------------------|
| Default    | All                                  |
| Hover      | Buttons, links, rows, cards          |
| Focus      | All — visible ring, not just outline removal |
| Active     | Buttons, clickable elements          |
| Disabled   | Form fields, buttons                 |
| Loading    | Buttons, forms, data-fetching areas  |
| Error      | Form fields, async operations        |
| Success    | Form submissions, async operations   |
| Empty      | All lists, tables, dashboards        |

**Never render a state that has no visual treatment.**

### Forms

- Every field requires a visible, persistent `<label>` — no placeholder-as-label
- Validation is **inline** and **immediate on blur** (not only on submit)
- Error messages appear directly below the offending field
- Required fields must be marked explicitly
- Submit buttons show loading state during async operations and are disabled during submission
- Autofill must be supported (`autocomplete` attributes set correctly)
- Tab order must be logical and complete

### SaaS-Specific UI Patterns

The following patterns must be implemented to SaaS production standard:

**Data tables:**
- Server-side pagination, sorting, filtering
- Column selection / visibility toggle
- Row-level actions (inline and bulk)
- Empty state with contextual CTA
- Loading skeleton (not spinner) for initial load

**Dashboards:**
- Skeleton loading — never blank-then-flash
- Widgets must handle: loading / empty / error / data states independently
- Metrics cards must clearly show label, value, unit, and trend

**Settings pages:**
- Grouped by domain (account, billing, team, integrations, etc.)
- Each setting saves independently with inline feedback
- Destructive actions (delete account, remove member) require explicit confirmation — separate confirm step, not just a dialog

**Onboarding flows:**
- Step indicator with completion state
- Progress is preserved on reload
- Each step validates before advancing
- Skip options where appropriate

**Notifications & Feedback:**
- Toast/snackbar: transient, non-blocking, auto-dismiss (success: 3s, error: persistent until dismissed)
- Modal: only for decisions that require full user attention; never for simple confirmations of non-destructive actions
- Inline alerts: for persistent contextual warnings on a page
- Do not stack more than 3 toasts simultaneously

### Motion & Animation

- Animation must be **purposeful** — communicates state change, hierarchy, or relationship
- Duration scale: `75ms · 100ms · 150ms · 200ms · 300ms · 500ms` — nothing slower than 500ms for UI transitions
- Easing: use `ease-out` for elements entering, `ease-in` for exiting, `ease-in-out` for position changes
- Always implement `prefers-reduced-motion` — disable or reduce animations when set
- No decorative animations that add no informational value

### Accessibility (non-negotiable)

- WCAG AA minimum — WCAG AAA where feasible
- Full keyboard navigation for every interactive element
- ARIA roles, labels, and live regions used correctly (not as a substitute for semantic HTML)
- Semantic HTML first — ARIA only where native semantics are insufficient
- Focus management on route changes and modal open/close
- Screen reader tested on key user flows

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

## 12. Multi-Tenancy

Every application built here is a SaaS with multiple tenants. Tenant isolation is a hard architectural requirement, not a feature.

### Data Isolation

- Every tenant's data must be **physically or logically isolated** at the database level
- Preferred strategy: **row-level isolation** with a non-nullable `tenant_id` foreign key on every tenant-scoped table, enforced via database-level Row Level Security (RLS) where the DB supports it
- Alternative: **schema-per-tenant** (more isolation, higher ops overhead) — decide and document the strategy before writing the first table
- Never query tenant-scoped data without an explicit `tenant_id` filter

### Tenant Context

- The current `tenant_id` must be resolved **at the request boundary** (from auth token, subdomain, or path) and injected into all downstream layers via context/DI
- No component, service, or repository should accept a `tenant_id` as a caller-supplied parameter from untrusted input
- Every authenticated request must have a verified tenant context before touching data

### Cross-Tenant Protection

- Automated tests must explicitly cover cross-tenant access attempts
- Any query that could theoretically return data from another tenant is a **critical security bug**
- Audit log every access to sensitive tenant data

### Tenant-Aware Features

- Rate limiting is per-tenant (not just per-IP)
- Feature flags and plan limits are enforced per-tenant
- Billing and usage metering is always tenant-scoped

---

## 13. Authentication & Authorization

### Authentication

- Session strategy must be decided explicitly: **JWT (stateless)** vs. **server-side sessions (stateful)**
  - JWT: faster, stateless, but requires token revocation strategy (blocklist or short expiry + refresh)
  - Server-side sessions: easier revocation, requires session store (Redis)
- **Access tokens** must be short-lived (≤ 15 minutes)
- **Refresh tokens** must be: long-lived, rotated on each use, stored securely (httpOnly cookie, not localStorage)
- Passwords hashed with `bcrypt` (cost ≥ 12) or `argon2id` — never MD5, SHA-1, or unsalted hashes
- MFA support must be designed for from the start (TOTP minimum)

### Authorization

- Use **Role-Based Access Control (RBAC)** as the baseline
- Extend with **Attribute-Based Access Control (ABAC)** for resource-level permissions where RBAC is insufficient
- Authorization checks happen in the **application layer**, not in controllers or the UI
- Every API endpoint has an explicit authorization rule — no endpoint is implicitly public
- Failed authorization returns `403 Forbidden`, not `404` (unless existence itself is sensitive)

### Session Security

- CSRF tokens required for all cookie-based sessions
- `SameSite=Strict` or `SameSite=Lax` on all auth cookies
- `Secure` flag mandatory in production
- `HttpOnly` flag on all auth cookies (no JavaScript access)

---

## 14. Observability & Logging

Production systems are only debuggable if they are observable. Observability is not added after the fact.

### Structured Logging

- All logs are **structured JSON** — no freeform string concatenation
- Every log entry includes: `timestamp`, `level`, `service`, `traceId`, `tenantId` (where applicable), `userId` (where applicable), `message`, and context fields
- Log levels used consistently:
  - `ERROR` — unexpected failures requiring immediate attention
  - `WARN` — recoverable issues, degraded state, deprecated usage
  - `INFO` — significant business events (user signed up, payment processed)
  - `DEBUG` — diagnostic detail, disabled in production by default

### What to Log

| Event                        | Level  |
|------------------------------|--------|
| Unhandled exceptions         | ERROR  |
| External service failures    | ERROR  |
| Auth failures (repeated)     | WARN   |
| Slow queries (> threshold)   | WARN   |
| Business events              | INFO   |
| Request/response cycle       | DEBUG  |

**Never log:** passwords, tokens, full credit card numbers, PII beyond what is operationally necessary.

### Error Tracking

- Integrate an error tracking service (e.g., Sentry) from day one
- Every unhandled exception must produce a tracked error with full context
- Errors are linked to deploys — correlation between new deploy and error spike must be visible

### Metrics & Alerting

- Track at minimum: request rate, error rate, p50/p95/p99 latency, queue depth, background job failure rate
- Alerts are defined for: error rate spike, latency degradation, queue backup, low disk/memory
- Dashboards exist before the product goes live — not retrofitted after an incident

### Distributed Tracing

- Every request carries a `traceId` propagated across service boundaries
- Trace context is included in all log entries and error reports

---

## 15. Internationalisation (i18n)

Design for internationalisation from the first line of UI code, even if only one language is launched initially. Retrofitting i18n is extremely costly.

### Rules

- **No hardcoded user-facing strings** anywhere in source code
- All strings in an external translation file (e.g., `en.json`) keyed by semantic identifier
- Never construct sentences by concatenating translated fragments — word order differs across languages
- Use ICU message format for plurals, genders, and interpolations
- Dates, times, numbers, and currencies formatted via `Intl` APIs — never manually formatted
- Text containers must handle strings up to **40% longer** than English (German, Finnish, etc.)
- RTL layout support must be considered in the component model from the start (`dir="rtl"`)
- Never use emojis as the sole means of conveying information

---

## 16. Dependency Management

### Rules

- **Lockfiles are committed** and must not be bypassed (`package-lock.json`, `yarn.lock`, `poetry.lock`, etc.)
- Direct dependencies are explicitly declared — do not rely on transitive dependencies
- Dependencies have a clear justification for inclusion — no adding packages to solve trivial problems
- Audit dependencies on every PR: `npm audit` / `pip-audit` / equivalent must be part of CI
- No dependencies with known unresolved critical CVEs may be merged
- Prefer smaller, focused packages over large all-in-one frameworks where the trade-off is justified

### Update Policy

- Dependencies are updated on a **scheduled cadence** (at minimum monthly), not only when breaking
- Major version upgrades are treated as migration tasks — planned, tested, documented
- Do not pin to exact versions without a documented reason — use range specifiers appropriately

---

## 17. CI/CD Pipeline

### CI Requirements (must pass before merge)

- Lint (zero warnings policy)
- Type checking (zero errors)
- Unit tests
- Integration tests
- Dependency audit (`audit --audit-level=high` minimum)
- Build succeeds

### CD Requirements

- All deployments are automated — no manual `scp`, no manual restarts
- Environment promotion: `dev → staging → production`
- Staging must mirror production infrastructure
- **Zero-downtime deployments** — rolling update or blue/green
- Database migrations run automatically as part of the deploy pipeline, **before** the new code is activated
- Every deploy is tagged with a version and linked to a git commit
- Rollback procedure is documented and tested — not theoretical

### Environment Parity

- Production secrets never used in development or CI
- Staging uses production-equivalent data volumes (anonymized/synthesized)
- Configuration differences between environments are explicit and version-controlled

---

## 18. Development Workflow

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

## 19. Commands Reference

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

## 20. AI Assistant Behavior

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

## 21. Anti-Patterns Reference

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

## 22. Technology Defaults

When the stack is unspecified, default to:

- **Type safety** — TypeScript over JavaScript, typed Python over untyped
- **Schema validation** — validate at all boundaries (e.g., Zod, Pydantic)
- **Modern frameworks** — with active maintenance and production adoption
- **Server authority** — canonical state lives server-side
- **Explicit contracts** — typed interfaces between layers
- **Predictable state management** — no hidden reactivity or magic
- **Avoid magic abstractions** — prefer explicit over convention-over-configuration where the convention is not obvious

---

## 23. Maintaining This File

Update this file when:

- A new top-level module or layer is introduced
- The tech stack or framework is decided or changed
- New required commands are established
- Architectural decisions are made (record the decision and rationale)
- Team conventions are agreed upon

Outdated documentation actively causes harm. If a section is no longer accurate, update it immediately — do not leave stale guidance in place.
