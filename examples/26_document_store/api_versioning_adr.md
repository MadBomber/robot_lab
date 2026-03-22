# Architecture Decision Record #047 — API Versioning Strategy

**Status:** Accepted (2024-11-12)
**Deciders:** Platform team, Mobile team, Partner integrations team

## Context

The v1 API has accumulated 23 breaking changes held back by an informal freeze
while three external partners built integrations. The mobile apps ship on a
4-week release cycle and cannot deploy hotfixes to force users to upgrade. We
need a versioning strategy that allows the backend to evolve without coordinated
lockstep releases across all consumers.

## Decision

We adopt URI-based versioning (/api/v2/, /api/v3/) rather than header-based
(Accept: application/vnd.company.v2+json) for the following reasons:

- URI versioning is visible in logs, dashboards, and browser dev tools.
- Proxy and CDN rules can target specific version prefixes.
- Internal clients are all first-party and can be updated in lockstep.

Header-based versioning is reserved for minor non-breaking variants (e.g.,
adding optional fields) using the Prefer header.

## Support Lifecycle

Each major version is supported for 18 months from GA. Deprecation notices are
added to response headers (Sunset: date) 6 months before EOL. The deprecation
dashboard tracks call volume per version per consumer; we do not retire a
version with > 100 calls/day without direct partner outreach.

## Backwards Compatibility Rules

Within a version, we **may**:
- Add new fields to responses.
- Add new optional request parameters.
- Add new endpoints.
- Add new enum values (consumers must ignore unknown values).

We **must not**:
- Remove or rename fields.
- Change field types.
- Change HTTP status codes for existing success cases.
- Remove endpoints.

## Migration Tooling

A version compatibility shim layer translates v1 requests to v2 internal
representations and back-translates responses. This allows v1 to remain
operational without duplicating business logic. The shim is tested with a
contract test suite against recorded v1 response fixtures.
