# Developer Guide: Unique Language Constraint

## Quick Start

### Running the Migration
```bash
# Apply the migration
mix ecto.migrate

# Verify the migration
mix ecto.migrations

# If needed, rollback
mix ecto.rollback
```

### Running Tests
```bash
# All tests
mix test

# Specific test file
mix test test/live_poll/polls_test.exs

# With coverage
mix test --cover

# Watch mode (if you have mix_test_watch)
mix test.watch
```

## API Reference

### Polls Context

#### `add_language/1`
Adds a new programming language to the poll.

```elixir
# Success
{:ok, %Option{text: "Python", votes: 0}} = Polls.add_language("Python")

# Duplicate error
{:error, "Python already exists"} = Polls.add_language("python")

# Validation error
{:error, "text: must be between 1 and 50 characters"} = Polls.add_language("")
```

#### `language_exists?/1`
Checks if a language exists (case-insensitive).

```elixir
Polls.add_language("Python")

true = Polls.language_exists?("Python")
true = Polls.language_exists?("python")
true = Polls.language_exists?("  PYTHON  ")
false = Polls.language_exists?("Ruby")
```

#### `find_similar_languages/1`
Finds up to 5 similar language names.

```elixir
Polls.add_language("JavaScript")
Polls.add_language("Java")

results = Polls.find_similar_languages("java")
# => [%Option{text: "Java"}, %Option{text: "JavaScript"}]
```

#### `list_options/0`
Lists all poll options sorted by ID.

```elixir
options = Polls.list_options()
# => [%Option{id: 1, text: "Python"}, %Option{id: 2, text: "Ruby"}]
```

#### `get_option/1` and `get_option!/1`
Gets a single option by ID.

```elixir
# Returns nil if not found
option = Polls.get_option(1)

# Raises if not found
option = Polls.get_option!(1)
```

## Validation Rules

### Text Field
- **Required**: Cannot be blank
- **Length**: 1-50 characters
- **Format**: Only letters, numbers, spaces, and symbols: `# + - . ( ) / *`
- **Trimming**: Automatic whitespace removal
- **Case**: Normalized for common acronyms
- **Uniqueness**: Case-insensitive

### Examples

#### Valid Inputs
```elixir
{:ok, _} = Polls.add_language("Python")
{:ok, _} = Polls.add_language("C++")
{:ok, _} = Polls.add_language("C#")
{:ok, _} = Polls.add_language("F#")
{:ok, _} = Polls.add_language("Objective-C")
{:ok, _} = Polls.add_language("Visual Basic .NET")
```

#### Invalid Inputs
```elixir
# Empty
{:error, _} = Polls.add_language("")

# Too long
{:error, _} = Polls.add_language(String.duplicate("a", 51))

# Invalid characters
{:error, _} = Polls.add_language("Python@3")
{:error, _} = Polls.add_language("Java$cript")
{:error, _} = Polls.add_language("Ruby & Rails")

# Duplicates
{:ok, _} = Polls.add_language("Python")
{:error, _} = Polls.add_language("python")
{:error, _} = Polls.add_language("PYTHON")
{:error, _} = Polls.add_language("  Python  ")
```

## Case Normalization

### Acronyms (Preserved)
These languages keep their uppercase format:
- `php` → `PHP`
- `sql` → `SQL`
- `matlab` → `MATLAB`
- `cobol` → `COBOL`
- `r` → `R`
- `c` → `C`
- `c++` → `C++`
- `c#` → `C#`
- `f#` → `F#`

### Regular Languages (Title Case)
Other languages are converted to title case:
- `python` → `Python`
- `javascript` → `Javascript`
- `ruby on rails` → `Ruby On Rails`
- `visual basic` → `Visual Basic`

## Database Schema

### poll_options Table
```sql
CREATE TABLE poll_options (
  id BIGSERIAL PRIMARY KEY,
  text VARCHAR(255) NOT NULL,
  votes INTEGER DEFAULT 0,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Unique index (case-insensitive)
CREATE UNIQUE INDEX poll_options_text_unique 
ON poll_options (lower(trim(text)));
```

### Querying with the Index
```elixir
# These queries use the unique index
from o in Option,
  where: fragment("lower(trim(?)) = ?", o.text, ^normalized_name)

from o in Option,
  where: fragment("lower(?) LIKE ?", o.text, ^pattern)
```

## Error Handling

### In LiveView
```elixir
def handle_event("add_language", %{"name" => name}, socket) do
  case Polls.add_language(name) do
    {:ok, option} ->
      {:noreply, 
       socket
       |> assign(:options, reload_options())
       |> put_flash(:info, "Added #{option.text} to the poll!")}
    
    {:error, message} ->
      # Check for duplicate and show suggestions
      if String.contains?(message, "already exists") do
        similar = Polls.find_similar_languages(name)
        suggestion = format_suggestions(similar)
        
        {:noreply, 
         socket
         |> put_flash(:error, "#{message}.#{suggestion}")}
      else
        {:noreply, 
         socket
         |> put_flash(:error, "Invalid input: #{message}")}
      end
  end
end
```

### In Tests
```elixir
test "handles duplicate languages" do
  assert {:ok, _} = Polls.add_language("Python")
  assert {:error, message} = Polls.add_language("Python")
  assert message =~ "already exists"
end
```

## Common Patterns

### Adding Multiple Languages
```elixir
languages = ["Python", "Ruby", "JavaScript", "Elixir"]

results = Enum.map(languages, fn lang ->
  case Polls.add_language(lang) do
    {:ok, option} -> {:ok, option}
    {:error, message} -> {:error, {lang, message}}
  end
end)

# Separate successes and failures
{successes, failures} = Enum.split_with(results, fn
  {:ok, _} -> true
  {:error, _} -> false
end)
```

### Checking Before Adding
```elixir
def add_language_if_not_exists(name) do
  if Polls.language_exists?(name) do
    {:error, "#{name} already exists"}
  else
    Polls.add_language(name)
  end
end
```

### Finding and Suggesting
```elixir
def suggest_or_add(name) do
  if Polls.language_exists?(name) do
    similar = Polls.find_similar_languages(name)
    {:error, :duplicate, similar}
  else
    case Polls.add_language(name) do
      {:ok, option} -> {:ok, option}
      {:error, message} -> {:error, :invalid, message}
    end
  end
end
```

## Testing Patterns

### Setup
```elixir
setup do
  # Tests run in a transaction that's rolled back
  # No need to clean up manually
  :ok
end
```

### Testing Duplicates
```elixir
test "prevents duplicates" do
  {:ok, opt1} = Polls.add_language("Python")
  {:error, msg} = Polls.add_language("Python")
  
  assert msg =~ "already exists"
  assert Polls.list_options() |> length() == 1
end
```

### Testing Case Insensitivity
```elixir
test "case insensitive duplicates" do
  {:ok, _} = Polls.add_language("Python")
  
  assert {:error, _} = Polls.add_language("python")
  assert {:error, _} = Polls.add_language("PYTHON")
  assert {:error, _} = Polls.add_language("PyThOn")
end
```

### Testing Normalization
```elixir
test "normalizes case" do
  {:ok, opt} = Polls.add_language("python")
  assert opt.text == "Python"
  
  {:ok, opt} = Polls.add_language("php")
  assert opt.text == "PHP"
end
```

## Troubleshooting

### Migration Fails
```bash
# Check current migration status
mix ecto.migrations

# Check database connection
mix ecto.psql

# Rollback and try again
mix ecto.rollback
mix ecto.migrate
```

### Tests Fail
```bash
# Make sure test database is set up
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate

# Run tests with verbose output
mix test --trace

# Run a specific test
mix test test/live_poll/polls_test.exs:42
```

### Duplicate Index Error
If you see "index already exists":
```bash
# Drop the index manually
mix ecto.psql

# In psql:
DROP INDEX IF EXISTS poll_options_text_unique;

# Then run migration again
mix ecto.migrate
```

### Race Condition Still Occurs
The unique index prevents race conditions at the database level. If you still see issues:
1. Verify the index exists: `\d poll_options` in psql
2. Check that you're using `Polls.add_language/1` not direct `Repo.insert`
3. Ensure the changeset includes `unique_constraint(:text, name: :poll_options_text_unique)`

## Performance Tips

### Batch Operations
```elixir
# Instead of multiple individual inserts
Enum.each(languages, &Polls.add_language/1)

# Consider using Repo.insert_all for bulk operations
# (but this bypasses validation)
Repo.insert_all(Option, 
  Enum.map(languages, fn lang ->
    %{text: lang, votes: 0, inserted_at: now, updated_at: now}
  end),
  on_conflict: :nothing
)
```

### Caching
```elixir
# Cache the list of languages if it doesn't change often
defmodule LanguageCache do
  use GenServer
  
  def get_languages do
    GenServer.call(__MODULE__, :get_languages)
  end
  
  def handle_call(:get_languages, _from, state) do
    languages = state[:languages] || Polls.list_options()
    {:reply, languages, Map.put(state, :languages, languages)}
  end
end
```

## Best Practices

1. **Always use the Polls context** - Don't bypass it with direct Repo calls
2. **Handle errors gracefully** - Show user-friendly messages
3. **Test edge cases** - Empty strings, long strings, special characters
4. **Use transactions** - When performing multiple related operations
5. **Monitor performance** - Watch for slow queries on the unique index
6. **Document changes** - Update this guide when adding new features

## Next Steps

After implementing this feature, consider:
1. Adding fuzzy matching for similar names
2. Pre-populating common languages
3. Adding language aliases (e.g., "JS" → "JavaScript")
4. Implementing an admin panel for managing languages
5. Adding audit logging for language additions

