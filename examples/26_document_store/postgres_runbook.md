# PostgreSQL Operations Runbook — v3.1

## Slow Query Investigation

When a query exceeds 1 second, start with pg_stat_statements:

    SELECT query, mean_exec_time, calls, total_exec_time
    FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;

Use EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) on the top offenders.
Look for Sequential Scans on large tables (> 50k rows) and Hash Joins on
unindexed foreign keys. Missing index candidates appear as "rows removed by
filter" values that are an order of magnitude larger than the rows returned.

## Connection Pool Exhaustion

PgBouncer pools connections at the transaction level. When all connections are
in use, new queries queue until pool_size is reached, at which point clients
receive "too many clients" errors. Mitigate by:
1. Reducing max_connections per Rails process via database.yml pool setting.
2. Increasing server_pool_size in pgbouncer.ini incrementally.
3. Identifying and killing idle-in-transaction connections:

       SELECT pid, state, query, now() - query_start AS duration
       FROM pg_stat_activity WHERE state = 'idle in transaction'
       AND query_start < now() - interval '30 seconds';

## Table Bloat and Vacuum

High update/delete workloads generate table bloat. Check with:

    SELECT relname, n_dead_tup, n_live_tup,
           round(n_dead_tup::numeric / nullif(n_live_tup, 0) * 100, 1) AS dead_pct
    FROM pg_stat_user_tables ORDER BY dead_pct DESC;

If dead_pct exceeds 20% on a hot table, trigger VACUUM ANALYZE manually. For
severe bloat, schedule an off-hours VACUUM FULL (acquires exclusive lock).
Autovacuum scale factor defaults to 0.2; reduce to 0.05 on high-churn tables.

## Replication Lag

Monitor standby lag with:

    SELECT client_addr, write_lag, flush_lag, replay_lag
    FROM pg_stat_replication;

Lag above 30 seconds indicates the replica is falling behind writes. Common
causes: long-running VACUUM on primary holding WAL files, network saturation
between primary and replica, or index builds on the replica.
