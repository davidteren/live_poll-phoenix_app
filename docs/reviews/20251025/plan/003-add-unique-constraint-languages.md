# Task: Add Unique Constraint to Prevent Duplicate Languages

## Category
Database, Data Integrity

## Priority
**CRITICAL** - Data integrity issue allowing duplicate entries

## Description
The poll_options table lacks a unique constraint on the text field, allowing users to create duplicate programming language entries. This leads to confusing UI, split votes, and poor data quality. A unique index must be added to prevent duplicates.

## Current State
```elixir
# Current migration - NO unique constraint
create table(:poll_options) do
  add :text, :string  # Can have duplicates!
  add :votes, :integer, default: 0
  timestamps()
end

# Current code - No validation
def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
  %Option{}
  |> Ecto.Changeset.change(text: name, votes: 0)
  |> Repo.insert!()  # Will create duplicates!
end
```

### Problem Example
- User A adds "Python"
- User B adds "Python" again
- Now there are two "Python" options splitting votes

## Proposed Solution

### Step 1: Create Migration for Unique Index
```elixir
# priv/repo/migrations/20251025000001_add_unique_constraint_to_poll_options.exs
defmodule LivePoll.Repo.Migrations.AddUniqueConstraintToPollOptions do
  use Ecto.Migration
  
  def up do
    # First, clean up any existing duplicates
    execute """
    DELETE FROM poll_options o1
    WHERE EXISTS (
      SELECT 1 FROM poll_options o2
      WHERE o2.text = o1.text
      AND o2.id < o1.id
    )
    """
    
    # Merge vote counts from duplicates before deletion
    execute """
    UPDATE poll_options o1
    SET votes = (
      SELECT SUM(votes) 
      FROM poll_options o2 
      WHERE LOWER(TRIM(o2.text)) = LOWER(TRIM(o1.text))
    )
    WHERE o1.id = (
      SELECT MIN(id) 
      FROM poll_options o3 
      WHERE LOWER(TRIM(o3.text)) = LOWER(TRIM(o1.text))
    )
    """
    
    # Add case-insensitive unique index
    create unique_index(:poll_options, ["lower(trim(text))"], name: :poll_options_text_unique)
  end
  
  def down do
    drop index(:poll_options, :poll_options_text_unique)
  end
end
```

### Step 2: Create Option Schema with Changeset
```elixir
# lib/live_poll/polls/option.ex
defmodule LivePoll.Polls.Option do
  use Ecto.Schema
  import Ecto.Changeset
  
  schema "poll_options" do
    field :text, :string
    field :votes, :integer, default: 0
    
    has_many :vote_events, LivePoll.Polls.VoteEvent
    
    timestamps()
  end
  
  @doc """
  Changeset for creating/updating options with validation
  """
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :votes])
    |> validate_required([:text])
    |> validate_length(:text, min: 1, max: 50)
    |> validate_format(:text, ~r/^[a-zA-Z0-9\s\#\+\-\.\(\)\/]+$/, 
        message: "only letters, numbers, spaces and common programming symbols allowed")
    |> update_change(:text, &String.trim/1)
    |> update_change(:text, &normalize_case/1)
    |> unique_constraint(:text, 
        name: :poll_options_text_unique,
        message: "This language already exists")
  end
  
  defp normalize_case(text) do
    # Preserve case for acronyms and special cases
    case text do
      "PHP" -> "PHP"
      "SQL" -> "SQL"
      "MATLAB" -> "MATLAB"
      "COBOL" -> "COBOL"
      _ -> 
        # Title case for most languages
        text
        |> String.downcase()
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end
end
```

### Step 3: Create Polls Context with Proper Validation
```elixir
# lib/live_poll/polls.ex
defmodule LivePoll.Polls do
  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent}
  
  @doc """
  Add a new programming language with validation
  """
  def add_language(name) when is_binary(name) do
    %Option{}
    |> Option.changeset(%{text: name, votes: 0})
    |> Repo.insert()
    |> case do
      {:ok, option} -> 
        broadcast_option_added(option)
        {:ok, option}
      
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}
    end
  end
  
  def add_language(_), do: {:error, "Invalid language name"}
  
  @doc """
  Check if a language already exists (case-insensitive)
  """
  def language_exists?(name) do
    normalized = String.trim(name) |> String.downcase()
    
    Repo.exists?(
      from o in Option,
      where: fragment("lower(trim(?)) = ?", o.text, ^normalized)
    )
  end
  
  @doc """
  Get similar language names for suggestions
  """
  def find_similar_languages(name) do
    pattern = "%#{String.downcase(name)}%"
    
    Repo.all(
      from o in Option,
      where: fragment("lower(?) LIKE ?", o.text, ^pattern),
      limit: 5
    )
  end
  
  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
  
  defp broadcast_option_added(option) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:option_added, option}
    )
  end
end
```

### Step 4: Update LiveView to Handle Duplicates Gracefully
```elixir
# lib/live_poll_web/live/poll_live.ex
def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
  case LivePoll.Polls.add_language(name) do
    {:ok, option} ->
      options = [option | socket.assigns.options] |> Enum.sort_by(& &1.id)
      
      {:noreply, 
       socket
       |> assign(:options, options)
       |> put_flash(:info, "Added #{option.text} to the poll!")}
    
    {:error, message} when is_binary(message) ->
      # Check if it's a duplicate error and provide helpful message
      if String.contains?(message, "already exists") do
        similar = LivePoll.Polls.find_similar_languages(name)
        
        suggestion = if length(similar) > 0 do
          "Did you mean: #{Enum.map(similar, & &1.text) |> Enum.join(", ")}?"
        else
          ""
        end
        
        {:noreply, 
         socket
         |> put_flash(:error, "#{name} already exists in the poll. #{suggestion}")}
      else
        {:noreply, put_flash(socket, :error, message)}
      end
  end
end
```

## Requirements
1. ✅ Add unique constraint to poll_options table
2. ✅ Handle existing duplicates in migration (merge votes)
3. ✅ Implement case-insensitive uniqueness check
4. ✅ Create proper changeset validation in Option schema
5. ✅ Provide clear error messages for duplicate attempts
6. ✅ Suggest similar existing languages when duplicate attempted
7. ✅ Add input validation for allowed characters

## Definition of Done
1. **Database Changes**
   - [ ] Migration created and tested
   - [ ] Existing duplicates merged with combined vote counts
   - [ ] Unique index successfully created
   - [ ] Case-insensitive comparison working

2. **Code Implementation**
   - [ ] Option schema created with proper changeset
   - [ ] Polls context module created with validation
   - [ ] LiveView updated to use context functions
   - [ ] Error handling provides helpful messages

3. **Tests**
   ```elixir
   test "prevents duplicate language names" do
     {:ok, _} = Polls.add_language("Python")
     assert {:error, message} = Polls.add_language("Python")
     assert message =~ "already exists"
   end
   
   test "case-insensitive duplicate prevention" do
     {:ok, _} = Polls.add_language("JavaScript")
     assert {:error, _} = Polls.add_language("javascript")
     assert {:error, _} = Polls.add_language("JAVASCRIPT")
   end
   
   test "trims whitespace before checking uniqueness" do
     {:ok, _} = Polls.add_language("Ruby")
     assert {:error, _} = Polls.add_language("  Ruby  ")
   end
   ```

4. **Quality Checks**
   - [ ] Migration runs successfully
   - [ ] No data loss during migration
   - [ ] `mix test` passes all tests
   - [ ] Manual testing confirms duplicates prevented

## Branch Name
`fix/unique-language-constraint`

## Dependencies
None - This is a standalone fix

## Estimated Complexity
**S (Small)** - 1-2 hours

## Testing Instructions
1. Create backup of current data
2. Run migration: `mix ecto.migrate`
3. Verify existing duplicates were merged
4. Try adding duplicate languages (should fail)
5. Try case variations (python, Python, PYTHON - all should be blocked)
6. Verify helpful error messages shown
7. Test validation for special characters

## Rollback Plan
```bash
# If issues occur, rollback the migration
mix ecto.rollback

# The unique constraint can be temporarily disabled while investigating
```

## Notes
- Migration handles existing duplicates by merging vote counts
- Case-insensitive comparison prevents Python/python/PYTHON duplicates
- Consider adding fuzzy matching for similar names (e.g., "JS" vs "JavaScript")
- May want to pre-populate common languages to avoid variations
