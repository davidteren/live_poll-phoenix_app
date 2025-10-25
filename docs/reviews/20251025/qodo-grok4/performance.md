# Performance & Optimization Analysis

## Potential Performance Bottlenecks in Database Queries
- **Trend Data Query**: In `build_trend_data_from_events` (lib/live_poll_web/live/poll_live.ex, lines 630-710), performs `Repo.all` on all VoteEvent records within the time range, sorted by inserted_at. For large ranges (e.g., 24 hours with 10,000+ events), this loads everything into memory, potentially causing high latency and memory usage.
- **No Indexing Issues**: Assumes inserted_at is indexed (common in migrations), but confirm in priv/repo/migrations.
- **Frequent Queries**: Timer triggers trend rebuild every 5s (line 35), which could overload the database under high concurrency.

## Seeding Process Efficiency
- Seeding 10,000 votes (lines 200-320): Inserts events one-by-one with individual Repo.insert! and SQL update for timestamps. This results in 20,000+ database operations, which is inefficient and slow (potential 10-30s execution time).
- Recommendation: Use batch inserts (Ecto.Multi or insert_all) and generate timestamps in Elixir to reduce roundtrips.

## Trend Data Calculation and Bucketing Logic
- In-memory grouping and reduction over all events (lines 660-700): O(n) time where n=events, fine for 10k but scales poorly.
- Bucketing is dynamic but rebuilds full history each time; could cache snapshots or use database aggregation.

## N+1 Query Problems
- Preloads :option in trend query (line 640), avoiding N+1.
- Other queries (e.g., Repo.all(Option) in mount) are simple and don't load associations.
- No obvious N+1 issues found.

## Memory Usage Patterns with LiveView Streams
- No streams used; assigns full lists (e.g., options, trend_data) which are broadcasted.
- For many options/events, large assigns could increase memory per socket.
- PubSub broadcasts full updates, efficient for small payloads but could be optimized to diffs.

Recommendations:
- Optimize seeding with batch operations.
- For trends, use SQL aggregation (e.g., GROUP BY time bucket) to compute buckets in DB.
- Add pagination or limits if event history grows.
