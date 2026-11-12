# Cyclift documentation (authoritative, version-controlled)

Branch: `docs/cyclift-governance` — documentation only. No application code, firmware, workflow or release file lives
here, and nothing on this branch is built or shipped.

Version 0.1 · 12 Nov 2026 · Status of this set: **Current Draft** (awaiting owner review).

## Order of authority

1. **Project Instructions** (Master Project Instructions v2.0 — held in the Cyclift project settings)
2. **Brand Book** — `brand/CYCLIFT_BRAND_BOOK.md`
3. **Product Specifications** — `product/`
4. **Technical Architecture** — `architecture/` (entry page; the documents themselves stay on their code branches)
5. **Feature Trackers** — `trackers/`

A lower level never overrides a higher one. A conflict is recorded in `governance/CONFLICT_REGISTER.md` and decided by
the owner; it is never fixed silently. Inside one level, the latest dated owner decision wins.

## Start here

| Need | File |
|---|---|
| Which file governs a subject | `governance/DOCUMENTATION_INDEX.md` |
| Open and decided contradictions | `governance/CONFLICT_REGISTER.md` |
| Brand, design system, product principles | `brand/CYCLIFT_BRAND_BOOK.md` |
| Current specification per page | `product/PRODUCT_SPECIFICATION_INDEX.md` |
| Technical documents by subject and hardware line | `architecture/ARCHITECTURE_INDEX.md` |
| Tracker freshness and proposed corrections | `trackers/TRACKER_STATUS_AUDIT.md` |
| Proposed consolidation (nothing moved yet) | `governance/PROPOSED_CONSOLIDATION.md` |
| Proposed edits to the Project Instructions | `governance/PROPOSED_PROJECT_INSTRUCTION_CHANGES.md` |

## Rules

- **One authoritative copy.** This branch is the source. Copies in the Claude project are reference copies and carry
  a header with source path, version and last synchronisation date. They are never edited independently.
- **Every document has a status:** Current Approved · Current Draft · Historical · Superseded · Pending Review.
  Only the owner makes something "Current Approved" or "Superseded".
- **Implemented and proposed are kept apart.** A statement about behaviour says which evidence level it has:
  designed, implemented, compiled, unit-tested, simulator-tested, physical-device-tested, released, user-accepted.
- **Existing documents are not moved, renamed, deleted or rewritten** by this set. They are indexed where they are.
