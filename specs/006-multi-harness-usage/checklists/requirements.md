# Specification Quality Checklist: Multi-Harness Usage (Codex and OpenCode)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-14
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- The brainstorm's open questions were resolved with informed defaults:
  - Auth mode comes from the session's plan marker (FR-014).
  - Cached input is split into cache read plus input, and reasoning is priced as output unless a dedicated price exists (FR-008, FR-020).
  - OpenCode `anthropic` has no built-in match (Assumptions).
  - The stored harness value is accepted but no longer restricts attribution (FR-018).
  - A busy database leaves the previous values in place, marked stale (FR-005).
- Harness names, provider ids, and default locations are user-visible product facts rather than implementation details.
- Validation passed on the first iteration.
