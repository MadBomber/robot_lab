# Background Job Processing with Sidekiq — Engineering Guide

## Job Design Principles

Every Sidekiq job must be idempotent: running it twice with the same arguments
must produce the same outcome. This is non-negotiable because Sidekiq retries
failed jobs and at-least-once delivery is guaranteed, not exactly-once. Achieve
idempotency by checking preconditions (has this invoice already been generated?),
using database unique constraints on job output records, and passing Stripe
idempotency keys.

## Retry Configuration

The default retry count is 25, which provides backoff up to ~21 days. For
time-sensitive jobs (send_welcome_email) reduce to 3. For financial jobs
(charge_subscription) raise to 15 to survive multi-hour outages.

Configure per-job: `sidekiq_options retry: 10`

Customize backoff with sidekiq_retry_in:

    sidekiq_retry_in { |count| (count ** 4) + 15 + rand(30) * count }

This gives approximately: 15s, 1m, 5m, 17m, 34m for the first 5 retries.

## Circuit Breaker Pattern

When a downstream service (Stripe, SendGrid) is degraded, jobs fail rapidly and
fill the retry queue, creating a thundering-herd effect when the service
recovers. Use a circuit breaker backed by Redis:

- Set `stripe:circuit_open` in Redis when 3 consecutive failures occur.
- In a job middleware, check the flag; if open, re-enqueue with 5-minute delay.
- Auto-clear the flag after 10 minutes using Redis TTL.

This converts retry churn into scheduled bursts.

## Dead Queue Management

Jobs reach the dead queue after exhausting all retries. Never bulk-retry
blindly. Group dead jobs by error class, inspect a sample for root cause,
fix the underlying issue, then use a Rake task to re-enqueue in batches of 50
with a 1-second inter-batch sleep to avoid overwhelming the recovered service.
Log each re-enqueue with original args and failure reason.

## Queue Priority and Latency Budgets

Define at least three queues: critical (< 1s SLA: auth, payments), default
(< 30s: email, webhooks), and bulk (< 1h: exports, reports). Run dedicated
Sidekiq processes per queue tier. Never mix critical and bulk work in the same
process — a spike of bulk jobs will starve critical work if they share a queue.
