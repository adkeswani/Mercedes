# Stage 1: Foundation Planning

This document locks the foundational constraints for implementation, as required by the MVP architecture plan. These constraints must be implemented before any feature build-out.

## Auth Model
- Google Sign-In (Android) is required for MVP.
- Apple Sign-In must be supported in the backend model from day one (even if not exposed in Android UI initially).
- On iOS launch, Apple Sign-In must be enabled in the UI.


## Roles & ACL Boundaries
- Roles:
	- Account (base)
	- Program Owner (contextual per program)
	- Athlete (contextual per program)
	- Admin (required, not optional; not tied to any specific program, intended for system-level support and oversight)
- The same person can be both a Program Owner and an Athlete in different programs.
- All access checks (read/write) must be role-based and scoped per program, except Admin which has system-level access for support and troubleshooting.
- Per-program ACLs must enforce ownership and membership boundaries.

## Enrollment Lifecycle Fields
- Program Enrollment must include `addedAt` (timestamp when access is granted) and `removedAt` (nullable timestamp for access removal).
- Enrollment is a manual access grant.

## Versioning & Audit Requirements
- All templates (Exercise, Workout, Program) must be versioned. Editing a published template creates a new version.
- All user and owner actions that change data must be auditable (who, what, when).
- Audit fields must include: `createdBy`, `createdAt`, `updatedBy`, `updatedAt` for all main entities.
- Version history must be preserved for templates and programs.

## Implementation Constraints
- These requirements are locked and must not be changed without explicit architectural review.
- All downstream features must conform to these constraints.

---

_Last updated: 2026-04-05_
