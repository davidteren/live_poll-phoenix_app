# Performance & Optimization

This analysis identifies hotspots and suggests optimizations with concrete steps.

## 1) Seeding 10,000 votes (handle_info :perform_seeding)

Current
- Inserts each VoteEvent individually, then issues an UPDATE per row to set inserted_at to a random timestamp.
- Complexity: O(N) inserts + O(N) updates (N ≈ 10k) in two passes; many round trips.

Risks
- Slow local/CI runs; potential timeouts in constrained DBs
- Heavy transaction log churn

Optimizations
- Build a list of maps with precomputed :inserted_at timestamps and use Repo.insert_all/3 in a single batch per language or in chunks of 1–5k.
- Track counts in memory, then insert_all once. Example approach:
  - Pre-generate random timestamps (DateTime.add(now, -rand_sec))
  - Build a list of %{option_id, language, votes_after, event_type, inserted_at}
  - Repo.insert_all(VoteEvent, list, on_conflict: :nothing)
- Update options with final vote counts via a single update_all or batched updates.
- Wrap in a transaction for consistency.

Expected gains
- >10x faster seeding; fewer DB round-trips; simpler code (no post-update queries).

## 2) Trend bucketing (build_trend_data_from_events)

Current
- Query all events since cutoff; group in Elixir; iterate all buckets and carry forward state.
- Preloads :option unnecessarily.

Optimizations
- Remove preload: it’s unused and adds overhead.
- Add WHERE and ORDER index coverage (already present on inserted_at and language; good).
- For large datasets, consider DB-side aggregation:

      SELECT date_trunc('second', inserted_at)::timestamp AS bucket,
             language,
             max(votes_after) AS votes_after
      FROM vote_events
      WHERE inserted_at >= $1
      GROUP BY 1, 2
      ORDER BY 1 ASC;

  Then build carry-forward in Elixir per language from this compact set.
- Consider caching last N snapshots in memory (e.g., via an Agent or ETS) and update incrementally every 5s using only new events.

## 3) LiveView timers and broadcast handling

- Two periodic timers run every 5s (update_stats + capture_trend). If user count grows, server CPU may rise due to repeated recomputes. Consider:
  - Increase interval for :capture_trend to 10–15s or compute only on changes.
  - Coalesce events: only recompute trend_data when new vote_events since last snapshot.

## 4) Front-end charts

- ECharts re-renders via setOption; modest data sizes are fine.
- If languages become >20 and snapshots >200, consider throttling push_event frequency or send only deltas.
- Lazy-load echarts only when chart containers are visible (IntersectionObserver) to reduce initial bundle execution.

## 5) N+1s and queries

- LiveView receives PubSub messages and reloads options via Repo.all/1. This is fine for a small table.
- Ensure indices exist for frequent lookups: poll_options(id) default PK; vote_events(inserted_at), language present – good.

## 6) Memory with LiveView streams

- No streams are used; collections are lists. For long activity feeds, consider streams to avoid diff growth, but current recent_activity is capped at 10 – fine.

## Concrete Steps

1. Seeding
   - Switch to Repo.insert_all with precomputed inserted_at; remove per-row updates.
   - Chunk inserts in 2–5k rows per call.
2. Trend
   - Remove preload from event query.
   - Optional: DB aggregation with GROUP BY bucket and max(votes_after).
3. Timers
   - Consider increasing :capture_trend interval or compute-on-change.
4. Front-end
   - Optionally lazy-load echarts; remove unused PercentageTrendChart.

## Metrics & Observability

- Telemetry handlers exist for repo.query.*; consider measuring seeding duration and trend computation time via :telemetry.span events for visibility.
