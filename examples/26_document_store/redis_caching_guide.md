# Redis Caching Patterns — Implementation Guide

## Cache Key Design

Keys must encode every dimension that affects the cached value. For a
user-scoped collection: `orders:user_USER_ID:page_PAGE:v2`. Always include a
version suffix (v2) so a code deploy can invalidate globally by bumping the
version, without a manual cache flush. Avoid encoding mutable data (e.g.,
user.plan) directly in the key; use separate keys and join at read time,
or accept stale reads.

## TTL Strategy

Set TTLs based on acceptable staleness, not on intuition:

- User session data: 24h (refreshed on activity)
- API response cache (authenticated): 5 minutes
- API response cache (public, CDN-backed): 60 seconds
- Computed aggregates (dashboards): 15 minutes with background refresh
- Feature flags: 30 seconds (fast propagation of flag changes)

Always set a TTL. Unbounded keys are a production outage waiting to happen
when a runaway process fills the Redis instance.

## Cache Invalidation

Explicit invalidation is more reliable than TTL-only for write-heavy data. Use
after_commit callbacks to delete or update cache entries when records change.
For collections, track the latest updated_at timestamp as the cache key
component (Russian doll caching). When multiple cache entries must be
invalidated atomically, use a Redis pipeline or Lua script.

## Redis Memory Pressure

When Redis hits maxmemory, it evicts keys according to the eviction policy. Use
`allkeys-lru` for pure cache workloads. Monitor `evicted_keys` in Redis INFO; a
non-zero and growing value means your cache is too small for the working set.
Separate cache and session data into different Redis instances (or databases)
so session eviction cannot be triggered by cache pressure.

## Stampede Protection

Under high read concurrency, a cache miss causes multiple processes to
simultaneously recompute the same expensive value — the cache stampede.
Mitigate with probabilistic early expiration: recompute when TTL drops below a
random fraction of the original TTL. Alternatively, use a distributed lock
(Redlock or a simple SET NX PX lock key) to allow only one process to recompute
while others wait briefly on the stale value.
