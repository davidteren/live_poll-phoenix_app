# Elixir Features Demonstrated in LivePoll

This document highlights the core Elixir language features and patterns used throughout the LivePoll application. This project serves as a practical example of idiomatic Elixir code and functional programming concepts.

## Table of Contents

- [Pattern Matching](#pattern-matching)
- [Multiple Function Clauses](#multiple-function-clauses)
- [Guard Clauses](#guard-clauses)
- [The Pipe Operator](#the-pipe-operator)
- [Capture Operator](#capture-operator)
- [Immutable Data with Rebinding](#immutable-data-with-rebinding)
- [Enum.map_reduce - Stateful Transformations](#enummap_reduce---stateful-transformations)
- [Tuple Pattern Matching](#tuple-pattern-matching)
- [Ecto Query DSL - Macro Magic](#ecto-query-dsl---macro-magic)

---

## Pattern Matching

Pattern matching is one of Elixir's most powerful features, allowing you to destructure data and match against specific patterns.

### Function Head Pattern Matching

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
# Pattern matching on function parameters with guards
def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
  # Check if language already exists
  existing = Repo.get_by(Option, text: name)

  if existing do
    {:noreply, socket}
  else
    # Create new language option
    %Option{}
    |> Ecto.Changeset.change(text: name, votes: 0)
    |> Repo.insert!()

    # Broadcast update to all clients
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:language_added, %{name: name}}
    )

    {:noreply, socket}
  end
end

def handle_event("add_language", _params, socket) do
  {:noreply, socket}
end
```

**What's happening:**
- The first clause only matches when `name` has content (using a guard clause)
- The second clause catches all other cases (empty names, missing params)
- This is **multiple function clauses with the same name** - a classic Elixir pattern!

### Destructuring in Function Parameters

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
def handle_info({:poll_update, update_data}, socket) do
  %{id: id, votes: votes, language: language, timestamp: timestamp} = update_data

  options =
    Enum.map(socket.assigns.options, fn
      %{id: ^id} = option -> %{option | votes: votes}
      option -> option
    end)

  total_votes = Enum.sum(Enum.map(options, & &1.votes))
  sorted_options = Enum.sort_by(options, & &1.votes, :desc)
  # ...
end
```

**What's happening:**
- The function parameter `{:poll_update, update_data}` matches a tuple with an atom and data
- The map is destructured to extract specific fields: `%{id: id, votes: votes, ...}`
- This makes the code more readable and explicit about what data we're using

### Pattern Matching in Enum Operations

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
options =
  Enum.map(socket.assigns.options, fn
    %{id: ^id} = option -> %{option | votes: votes}  # Matches specific ID using pin operator ^
    option -> option  # Matches everything else
  end)
```

**What's happening:**
- The `^id` is the **pin operator** - it matches against the existing value of `id` rather than rebinding it
- First clause: matches options where the ID equals our target ID, updates the votes
- Second clause: matches all other options, returns them unchanged
- This is pattern matching inside an anonymous function!

---

## Multiple Function Clauses

Elixir allows you to define multiple versions of the same function with different patterns. The runtime will call the first clause that matches.

### Example: Percentage Calculation

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
# First clause: when total > 0
defp percentage(votes, total) when total > 0 do
  (votes / total * 100) |> round()
end

# Second clause: fallback for zero or negative
defp percentage(_votes, _total), do: 0
```

**What's happening:**
- Same function name `percentage/2`, different implementations
- First clause only matches when `total > 0` (guard clause)
- Second clause catches all other cases (zero or negative totals)
- The underscore `_` prefix indicates we're ignoring those parameters
- This prevents division by zero errors elegantly!

### Example: Calculate Percentages for Options

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
# When there are votes
def calculate_percentages(options, total_votes) when total_votes > 0 do
  options
  |> Enum.map(fn option ->
    {option.text, (option.votes / total_votes * 100) |> Float.round(1)}
  end)
  |> Map.new()
end

# When there are no votes
def calculate_percentages(options, _total_votes) do
  options
  |> Enum.map(fn option -> {option.text, 0.0} end)
  |> Map.new()
end
```

**What's happening:**
- Two implementations of the same function
- First clause handles the normal case with votes
- Second clause returns 0% for all options when there are no votes
- This is **function overloading via pattern matching**!

---

## Guard Clauses

Guards are additional conditions you can add to function clauses to make pattern matching more specific.

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
  # Only executes if name has content
end

defp percentage(votes, total) when total > 0 do
  # Only executes if total is positive
end
```

**What's happening:**
- The `when` keyword introduces a guard clause
- Guards can use built-in functions like `byte_size/1`, comparison operators, etc.
- If the guard fails, Elixir tries the next function clause
- Guards let you add **additional conditions** beyond pattern matching

**Common guard functions:**
- `is_atom/1`, `is_binary/1`, `is_integer/1`, `is_list/1`, `is_map/1`
- `byte_size/1`, `length/1`, `map_size/1`
- Comparison operators: `>`, `<`, `>=`, `<=`, `==`, `!=`
- Boolean operators: `and`, `or`, `not`

---

## The Pipe Operator

The pipe operator `|>` is one of Elixir's most beloved features. It takes the result of the expression on the left and passes it as the **first argument** to the function on the right.

### Simple Piping

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
# Without pipe operator
options = Enum.sort_by(Repo.all(Option), fn opt -> opt.id end)

# With pipe operator (more readable!)
options = Repo.all(Option) |> Enum.sort_by(& &1.id)
```

### Complex Transformation Pipeline

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
def language_to_class(language) do
  language
  |> String.downcase()
  |> String.replace("#", "sharp")
  |> String.replace("+", "plus")
  |> String.replace(" ", "")
end
```

**What's happening:**
- Starts with `language` (e.g., "C#")
- Converts to lowercase: "c#"
- Replaces "#" with "sharp": "csharp"
- Replaces "+" with "plus": "csharp"
- Removes spaces: "csharp"
- Each step feeds into the next, creating a readable transformation chain!

### Piping with Socket Transformations

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
socket =
  socket
  |> assign(:time_range, range_minutes)
  |> assign(:trend_data, trend_data)
  |> push_event("update-trend-chart", %{
    trendData: trend_data,
    languages: languages
  })
```

**What's happening:**
- Each function returns a new socket
- The pipe operator threads the socket through multiple transformations
- Much more readable than nested function calls!

---

## Capture Operator

The capture operator `&` provides a shorthand syntax for creating anonymous functions.

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
# Using capture operator
options = Repo.all(Option) |> Enum.sort_by(& &1.id)
total_votes = Enum.sum(Enum.map(options, & &1.votes))

# Equivalent to (without capture operator):
options = Repo.all(Option) |> Enum.sort_by(fn opt -> opt.id end)
total_votes = Enum.sum(Enum.map(options, fn opt -> opt.votes end))
```

**What's happening:**
- `&` creates an anonymous function
- `&1` refers to the first argument
- `&2` would refer to the second argument, etc.
- Much more concise for simple transformations!

**More examples:**

```elixir
# Capture operator with multiple arguments
Enum.reduce(list, 0, &(&1 + &2))
# Equivalent to: Enum.reduce(list, 0, fn x, acc -> x + acc end)

# Capture operator with function calls
Enum.map(strings, &String.upcase/1)
# Equivalent to: Enum.map(strings, fn s -> String.upcase(s) end)
```

---

## Immutable Data with Rebinding

In Elixir, all data is immutable. You can't change a value once it's created. Instead, you create new values and rebind variables.

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
socket =
  socket
  |> assign(:time_range, range_minutes)
  |> assign(:trend_data, trend_data)
  |> push_event("update-trend-chart", %{...})
```

**What's happening:**
- Each operation (`assign`, `push_event`) returns a **new socket**
- The original socket is never mutated
- We rebind the `socket` variable to the transformed version
- This prevents bugs from unexpected state changes!

### Map Updates

```elixir
# Updating a map creates a new map
option = %{id: 1, votes: 5}
updated_option = %{option | votes: 6}

# option is still %{id: 1, votes: 5}
# updated_option is %{id: 1, votes: 6}
```

---

## Enum.map_reduce - Stateful Transformations

`Enum.map_reduce/3` is a powerful function that combines mapping and reducing. It transforms a collection while maintaining state.

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
{snapshots, _final_state} =
  Enum.map_reduce(all_buckets, %{}, fn bucket_time, current_state ->
    # Get events in this bucket (if any)
    bucket_events = Map.get(events_by_bucket, bucket_time, [])

    # Update state with events from this bucket
    new_state =
      if bucket_events == [] do
        current_state  # Carry forward previous state
      else
        # Update state with new vote counts from events in this bucket
        Enum.reduce(bucket_events, current_state, fn event, state ->
          Map.put(state, event.language, event.votes_after)
        end)
      end

    # Calculate percentages from current state
    total_votes = new_state |> Map.values() |> Enum.sum()

    percentages =
      if total_votes > 0 do
        new_state
        |> Enum.map(fn {lang, votes} ->
          {lang, (votes / total_votes * 100) |> Float.round(1)}
        end)
        |> Map.new()
      else
        # No votes yet, all languages at 0%
        all_languages |> Enum.map(fn lang -> {lang, 0.0} end) |> Map.new()
      end

    snapshot = %{
      timestamp: bucket_time,
      percentages: percentages,
      vote_counts: new_state
    }

    {snapshot, new_state}  # Return tuple: (result, new_accumulator)
  end)
```

**What's happening:**
- Iterates over `all_buckets` (time buckets)
- Starts with initial state: `%{}` (empty map)
- For each bucket, returns a tuple: `{result, new_state}`
- The `result` goes into the `snapshots` list
- The `new_state` becomes `current_state` for the next iteration
- This is a **powerful functional pattern** for stateful transformations!

**Signature:**
```elixir
Enum.map_reduce(enumerable, accumulator, fun)
# fun receives: (element, accumulator)
# fun returns: {result, new_accumulator}
```

---

## Tuple Pattern Matching

Tuples are a fundamental data structure in Elixir, often used for return values and pattern matching.

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
# All LiveView callbacks return tuples
{:noreply, socket}
{:ok, vote_event} = Repo.insert(%VoteEvent{...})

# Pattern matching in comprehensions
Enum.map(options_with_weights, fn {option, weight} ->
  # Destructures tuple into option and weight
  base_votes = trunc(total_target_votes * (weight / total_weight))
  {option, base_votes}
end)
```

**What's happening:**
- `{:noreply, socket}` is a tuple with an atom and a socket
- `{:ok, vote_event}` pattern matches on successful database insert
- `fn {option, weight} ->` destructures each tuple in the enumeration
- Tuples are commonly used for tagged return values (`:ok`, `:error`, etc.)

**Common tuple patterns:**

```elixir
# Success/Error tuples
{:ok, result} = some_operation()
{:error, reason} = some_operation()

# Multiple return values
{snapshots, final_state} = Enum.map_reduce(...)

# Tagged tuples for messages
{:poll_update, data}
{:language_added, data}
```

---

## Ecto Query DSL - Macro Magic

Ecto provides a SQL-like DSL (Domain Specific Language) for building database queries. This is implemented using Elixir **macros**, which allow you to extend the language syntax.

**Location:** `lib/live_poll_web/live/poll_live.ex`

```elixir
events =
  from(e in VoteEvent,
    where: e.inserted_at >= ^cutoff_time,
    order_by: [asc: e.inserted_at],
    preload: :option
  )
  |> Repo.all()
```

**What's happening:**
- `from` is a macro that creates a query struct
- The syntax looks like SQL but it's actually Elixir code
- `^cutoff_time` uses the pin operator to inject a variable value
- The query is compiled to efficient SQL at compile time
- This is the power of **macros** - extending the language!

### More Ecto Query Examples

```elixir
# Simple query
options = Repo.all(Option)

# Query with conditions
option = Repo.get_by(Option, text: name)

# Complex query with joins and aggregations
from(e in VoteEvent,
  where: e.inserted_at >= ^cutoff_time,
  order_by: [asc: e.inserted_at],
  preload: :option
)
|> Repo.all()
```

**Key concepts:**
- Queries are composable - you can build them up piece by piece
- The `^` pin operator injects runtime values safely (prevents SQL injection)
- Queries are validated at compile time when possible
- Ecto translates the DSL to optimized SQL for your database

---

## Summary

This LivePoll application demonstrates these **core Elixir features**:

1. ✅ **Pattern Matching** - In function heads, parameters, and data structures
2. ✅ **Multiple Function Clauses** - Same name, different patterns (like `percentage/2`)
3. ✅ **Guard Clauses** - `when` conditions for additional matching logic
4. ✅ **Pipe Operator** - Elegant data transformation chains (`|>`)
5. ✅ **Capture Operator** - Shorthand anonymous functions (`& &1`)
6. ✅ **Immutability** - Data never mutates, always returns new versions
7. ✅ **Enum.map_reduce** - Stateful transformations with accumulator
8. ✅ **Tuple Matching** - Destructuring return values and tagged tuples
9. ✅ **Macros** - Ecto's query DSL extends the language

These features make Elixir:
- **Expressive** - Code reads like the problem domain
- **Safe** - Immutability prevents many classes of bugs
- **Maintainable** - Pattern matching makes code intent clear
- **Powerful** - Macros allow domain-specific languages

## Learning Resources

- [Elixir Official Guides](https://elixir-lang.org/getting-started/introduction.html)
- [Elixir School](https://elixirschool.com/)
- [Exercism Elixir Track](https://exercism.org/tracks/elixir)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [Phoenix Framework Guides](https://hexdocs.pm/phoenix/overview.html)

---

**Note:** This document is meant to be a learning resource. For the actual implementation details, refer to the source code in `lib/live_poll_web/live/poll_live.ex` and related files.

