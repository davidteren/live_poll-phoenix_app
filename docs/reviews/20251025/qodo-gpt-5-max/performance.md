# LivePoll – Performance & Optimization

This document identifies potential performance bottlenecks and suggests optimizations for database operations, seeding, trend data calculation, and LiveView memory usage.


## Database operations

1. Voting (read-modify-write)
   - Current: Repo.get!(Option, id) → change votes → Repo.update!.
   - Problem: Race conditions and potential lost updates under concurrency. Also, two queries for one logical operation.
   - Optimize: Use atomic increment in a single UPDATE with RETURNING:
     - from(o in Option, where: o.id == ^id, update: [inc: [votes: 1]], select: %{id: o.id, text: o.text, votes: o.votes})
       |> Repo.update_all([])
     - Or use Repo.query with SQL UPDATE ... RETURNING votes.

2. Trend query
   - Current: Preloads :option though only language, votes_after, inserted_at are used.
   - Optimize: Remove preload to avoid unnecessary joins/decoding.

3. Indexes
   - vote_events has indexes on option_id, inserted_at, language – good.
   - poll_options should have unique index on text for fast lookup and to avoid duplicates; add create unique_index(:poll_options, [:text]).


## Seeding process (10,000 votes)

- Current approach:
  - Deletes all rows.
  - Inserts options individually.
  - Builds a list of ~10k events with random timestamps over the last hour.
  - For each event:
    - Repo.insert(%VoteEvent{...}) → {:ok, vote_event}
    - Ecto.Adapters.SQL.query! to update inserted_at.
  - Updates options individually with final vote counts.

- Issues:
  - 10k inserts + 10k update statements is expensive; round-trips and overhead are high.
  - No explicit transaction around the whole seeding; partial failure can leave inconsistent state.

- Optimizations:
  - Use Repo.transaction and Repo.insert_all/3 for vote_events with precomputed inserted_at values to avoid post-insert UPDATE.
  - Compute votes_after per event in memory while building events, then bulk insert using a list of maps: [%{option_id:, language:, votes_after:, event_type:, inserted_at: ...}, ...].
  - Insert options with Repo.insert_all.
  - Update Option votes with bulk UPDATE or compute votes during insert_all and then set in a single UPDATE FROM derived table.
  - Chunk bulk inserts into e.g. 1,000-record batches if needed to avoid large packet sizes.

- Estimated impact: Seeding time drops from seconds/tens of seconds to sub-second/seconds depending on hardware, and DB load is significantly reduced.


## Trend data calculation and bucketing

- Algorithm:
  - Determine bucket size based on range (5s/30s/5m/10m).
  - Group events by bucket (round down inserted_at to bucket start).
  - Generate all buckets from cutoff to now.
  - Carry forward counts to create continuous series.

- Good: Efficient and linear in number of buckets + events.
- Optimizations:
  - Reuse precomputed languages list from options rather than events (to ensure consistent series across time windows, including newly-added languages). Current code already collects them from events for empty-state; both approaches are fine.
  - If trend updates are frequent, consider caching snapshots per time range and incrementally updating rather than full recomputation every 5s. This is a bigger change; current performance is likely adequate for demo scale.


## N+1 considerations

- There is no N+1 on rendering options – options are loaded once. Event query previously had preload which could be expensive; removing it avoids hidden N+1.


## LiveView memory usage & streams

- The UI assigns regular lists (options, recent_activity). For recent_activity, list is capped to 10 entries – good.
- Streams are not used; current scale is small. If options or activity grew large, use LiveView streams for options to reduce diff payloads and memory.


## Asset performance

- ECharts 6 is bundled; charts re-render on push_event. The data size for 120–144 snapshots × N languages is modest. Consider throttling updates if data volume grows (currently 5s cadence is fine).


## Checklist of changes

1. Replace vote update with atomic DB increment and a single broadcast.
2. Remove preload: :option from trend query.
3. Add unique index on poll_options(text).
4. Rework seeding to use Repo.transaction + Repo.insert_all + batched operations.
5. Consider LiveView streams for options if the number of options grows significantly.
