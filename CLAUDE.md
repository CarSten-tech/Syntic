# CLAUDE.md — AI Assistant Guide for Syntic

This file provides guidance for AI assistants (Claude Code and similar tools) working in the **CarSten-tech/Syntic** repository. Keep this file up to date as the project evolves.

---

## Repository Overview

| Field       | Value                          |
|-------------|-------------------------------|
| Project     | Syntic                         |
| Organization| CarSten-tech                   |
| Status      | Initial setup (no source yet)  |

> **Note:** This repository is currently empty. Update this file with project details as the codebase is established.

---

## Codebase Structure

_To be filled in once source files are added. Follow the template below:_

```
Syntic/
├── CLAUDE.md          # This file
├── README.md          # Project overview and quickstart
├── <source dirs>      # To be documented
└── <config files>     # To be documented
```

When the project structure exists, document:
- What each top-level directory contains and why it exists
- Which files are auto-generated (never edit by hand)
- Entry points (main files, index files, server start)
- Where environment/config is managed

---

## Development Workflow

### Branch Strategy

- **Default branch:** `main` (or `master`) — production-ready code only
- **Feature branches:** `feature/<short-description>`
- **Fix branches:** `fix/<short-description>`
- **Claude branches:** `claude/<task-id>` — used by AI-assisted sessions

Never commit directly to `main`. All changes go through a branch and pull request.

### Commit Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

[optional body]
```

**Types:**
- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation only
- `refactor` — code restructuring without behavior change
- `test` — adding or updating tests
- `chore` — build process, dependency updates, tooling

**Examples:**
```
feat(auth): add JWT token refresh endpoint
fix(api): handle null response from upstream service
docs: update CLAUDE.md with project structure
```

### Pull Request Workflow

1. Create a branch from `main`
2. Make focused, atomic commits
3. Push the branch and open a PR
4. PR description must include: what changed, why, and how to test
5. Squash-merge into `main` after approval

---

## Commands to Know

> Update this section with real commands once the project is set up.

### Common Tasks

```bash
# Install dependencies
# <fill in: e.g., npm install / pip install -r requirements.txt>

# Run development server
# <fill in>

# Run tests
# <fill in>

# Run linter / formatter
# <fill in>

# Build for production
# <fill in>
```

### Environment Setup

```bash
# Copy example env file (never commit .env)
cp .env.example .env
# Edit .env with your local values
```

---

## Code Conventions

> Update this section based on the language(s) and frameworks used.

### General Rules

- **No magic numbers:** use named constants
- **No commented-out code:** delete it; git history preserves it
- **No TODO comments in production code:** open an issue instead
- **Single responsibility:** functions and modules do one thing well
- **Fail loudly:** prefer explicit errors over silent fallbacks
- **Never swallow exceptions** without logging or re-raising

### Naming

| Context       | Convention            |
|---------------|-----------------------|
| Files         | `kebab-case`          |
| Variables/fns | `camelCase` (JS/TS) / `snake_case` (Python) |
| Classes       | `PascalCase`          |
| Constants     | `UPPER_SNAKE_CASE`    |
| Database cols | `snake_case`          |

### File Organization

- Group files by **feature/domain**, not by type (avoid `controllers/`, `models/` at the root level)
- Co-locate tests with source: `foo.ts` → `foo.test.ts`
- Keep files under ~300 lines; split if growing larger

---

## Testing

> Update with actual test commands and framework details.

### Principles

- Tests must be deterministic (no random seeds, no real network calls)
- Mock external services in unit tests; use real services only in integration tests
- Each test should be independent — no shared mutable state between tests
- Test behavior, not implementation details

### Test Types

| Type        | Scope                          | Speed  |
|-------------|-------------------------------|--------|
| Unit        | Single function/module        | Fast   |
| Integration | Multiple modules + real deps  | Medium |
| E2E         | Full user flows               | Slow   |

Run the full test suite before opening a PR. CI must be green.

---

## Security

- **Never commit secrets:** no API keys, passwords, tokens in code
- Use environment variables for all secrets (see `.env.example`)
- Sanitize all user inputs at system boundaries
- Validate inputs server-side regardless of client-side validation
- Keep dependencies updated; review dependency changes in PRs
- Do not log sensitive data (passwords, tokens, PII)

---

## AI Assistant Instructions

### What AI assistants SHOULD do

- Read files before modifying them
- Make minimal, focused changes — only what is asked
- Follow existing patterns in the codebase rather than introducing new ones
- Add tests for new functionality
- Update this CLAUDE.md when the project structure changes significantly
- Commit with descriptive messages following the convention above

### What AI assistants MUST NOT do

- Push directly to `main` or any protected branch
- Commit `.env` files or secrets
- Add unrequested features, refactors, or "improvements"
- Remove or modify unrelated code
- Use `git push --force` without explicit instruction
- Create new files when editing an existing one is sufficient

### Recommended Workflow for AI Sessions

1. Fetch the latest state of the branch before making changes
2. Read and understand relevant files before editing
3. Make changes in small, reviewable increments
4. Run tests (if available) before committing
5. Commit and push to the feature branch — never to `main`

---

## Updating This File

This file should be updated whenever:
- New top-level directories or modules are introduced
- The tech stack or framework changes
- New required commands are added (build, lint, test, migrate, etc.)
- Team conventions are decided or changed
- A significant architectural decision is made

Keep entries concise and accurate. Outdated documentation is worse than no documentation.
