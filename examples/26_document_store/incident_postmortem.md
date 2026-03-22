# Incident Postmortem — INC-2024-089

**Date:** 2024-10-03
**Duration:** 47 minutes
**Severity:** P1
**Affected:** API gateway, order processing, checkout flows

## Timeline

| Time  | Event |
|-------|-------|
| 14:23 | Automated alert fires: p99 API latency exceeds 5 seconds |
| 14:25 | On-call engineer pages in; confirms checkout error rate at 34% |
| 14:31 | Identified spike in slow queries on orders table in Datadog APM |
| 14:38 | Root cause confirmed: migration added non-concurrent index at peak traffic |
| 14:44 | DBA kills the migration process; index creation aborted |
| 14:48 | Query latency returns to baseline; error rate drops to 0.2% |
| 15:10 | Full recovery confirmed; incident closed |

## Root Cause

An engineer ran a schema migration that created an index on orders.status
without the CONCURRENTLY keyword. Postgres acquired an AccessExclusiveLock on
the orders table for the duration of the index build (11 minutes). All queries
touching the orders table queued behind the lock, exhausting the PgBouncer
connection pool within 3 minutes.

## Contributing Factors

1. Migration review checklist did not include "concurrent index" verification.
2. The migration was run manually during business hours, not via the deploy pipeline.
3. No automated linting (strong_migrations) was enforced in CI.

## Remediation (Completed)

- `strong_migrations` gem added to Gemfile; CI fails on unsafe migration patterns.
- Runbook updated: all migrations that touch tables > 1M rows require DBA review.
- Index creation added to the concurrent-operations checklist.
- PgBouncer max_client_conn increased from 150 to 300 as a buffer.

## Lessons Learned

Lock acquisition during index creation is silent in application logs — the first
visible symptom is connection pool exhaustion, not a database error.
Instrumenting pg_locks with an alert on long-held AccessExclusiveLocks would
have cut detection time from 8 minutes to under 1 minute.
