# Task: Add Input Validation and Sanitization

## Category
Security, Data Integrity

## Priority
**HIGH** - XSS vulnerabilities and potential crashes from invalid input

## Description
The application lacks proper input validation and sanitization, allowing malicious input that could cause XSS attacks in chart tooltips, crashes from invalid IDs, and poor data quality from unvalidated language names. Comprehensive validation must be added at all input points.

## Current State
```elixir
# No validation on language names
def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
  # Accepts ANY characters including <script> tags
  %Option{} |> Ecto.Changeset.change(text: name, votes: 0) |> Repo.insert!()
end

# No ID validation  
def handle_event("vote", %{"id" => id}, socket) do
  option = Repo.get!(Option, id)  # Crashes on invalid ID
end

# Chart tooltips display unsanitized content
tooltip: {
  formatter: function(params) {
    return params.name + ': ' + params.value;  // XSS risk!
  }
}
```

## Proposed Solution

### Step 1: Create Comprehensive Changesets
```elixir
# lib/live_poll/polls/option.ex
defmodule LivePoll.Polls.Option do
  use Ecto.Schema
  import Ecto.Changeset
  
  @valid_name_regex ~r/^[a-zA-Z0-9\s\#\+\-\.\(\)\/\*]+$/
  @max_name_length 50
  @min_name_length 1
  
  schema "poll_options" do
    field :text, :string
    field :votes, :integer, default: 0
    has_many :vote_events, LivePoll.Polls.VoteEvent
    timestamps()
  end
  
  @doc """
  Changeset for creating new options with full validation
  """
  def create_changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :votes])
    |> validate_required([:text])
    |> validate_length(:text, min: @min_name_length, max: @max_name_length)
    |> validate_format(:text, @valid_name_regex,
        message: "can only contain letters, numbers, spaces, and programming symbols (#, +, -, ., (), /, *)")
    |> sanitize_text()
    |> normalize_text()
    |> unique_constraint(:text,
        name: :poll_options_text_unique,
        message: "already exists in the poll")
  end
  
  @doc """
  Changeset for updating votes (no text changes allowed)
  """
  def vote_changeset(option, attrs) do
    option
    |> cast(attrs, [:votes])
    |> validate_number(:votes, greater_than_or_equal_to: 0)
  end
  
  defp sanitize_text(changeset) do
    update_change(changeset, :text, fn text ->
      text
      |> strip_html_tags()
      |> remove_dangerous_characters()
      |> String.trim()
    end)
  end
  
  defp strip_html_tags(text) do
    # Remove any HTML/XML tags
    Regex.replace(~r/<[^>]*>/, text, "")
  end
  
  defp remove_dangerous_characters(text) do
    # Remove null bytes and other dangerous characters
    text
    |> String.replace("\0", "")
    |> String.replace("\r", "")
    |> String.replace("\n", " ")
  end
  
  defp normalize_text(changeset) do
    update_change(changeset, :text, fn text ->
      # Normalize whitespace
      text
      |> String.split()
      |> Enum.join(" ")
      |> handle_special_cases()
    end)
  end
  
  defp handle_special_cases(text) do
    # Preserve case for known acronyms
    case String.downcase(text) do
      "c++" -> "C++"
      "c#" -> "C#"
      "f#" -> "F#"
      "php" -> "PHP"
      "sql" -> "SQL"
      "html" -> "HTML"
      "css" -> "CSS"
      "xml" -> "XML"
      "json" -> "JSON"
      "yaml" -> "YAML"
      "matlab" -> "MATLAB"
      "cobol" -> "COBOL"
      "fortran" -> "FORTRAN"
      _ -> proper_case(text)
    end
  end
  
  defp proper_case(text) do
    text
    |> String.downcase()
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
```

### Step 2: Add Input Validation Module
```elixir
# lib/live_poll/validation.ex
defmodule LivePoll.Validation do
  @moduledoc """
  Centralized input validation for the application
  """
  
  @doc """
  Validate and parse an ID parameter
  """
  def validate_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} when int_id > 0 ->
        {:ok, int_id}
      _ ->
        {:error, :invalid_id}
    end
  end
  
  def validate_id(id) when is_integer(id) and id > 0 do
    {:ok, id}
  end
  
  def validate_id(_), do: {:error, :invalid_id}
  
  @doc """
  Validate vote count parameter
  """
  def validate_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {int_count, ""} when int_count > 0 and int_count <= 100_000 ->
        {:ok, int_count}
      {int_count, ""} when int_count > 100_000 ->
        {:error, :count_too_large}
      _ ->
        {:error, :invalid_count}
    end
  end
  
  def validate_count(count) when is_integer(count) do
    cond do
      count <= 0 -> {:error, :count_too_small}
      count > 100_000 -> {:error, :count_too_large}
      true -> {:ok, count}
    end
  end
  
  def validate_count(_), do: {:error, :invalid_count}
  
  @doc """
  Sanitize text for safe display in HTML/JavaScript
  """
  def sanitize_for_display(text) when is_binary(text) do
    text
    |> html_escape()
    |> javascript_escape()
  end
  
  def sanitize_for_display(_), do: ""
  
  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
  
  defp javascript_escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
  
  @doc """
  Check if text contains potentially malicious content
  """
  def contains_malicious_content?(text) do
    patterns = [
      ~r/<script/i,
      ~r/javascript:/i,
      ~r/on\w+=/i,  # onclick=, onload=, etc.
      ~r/<iframe/i,
      ~r/<object/i,
      ~r/<embed/i,
      ~r/data:text\/html/i,
      ~r/vbscript:/i
    ]
    
    Enum.any?(patterns, &Regex.match?(&1, text))
  end
end
```

### Step 3: Update Polls Context with Validation
```elixir
# lib/live_poll/polls.ex
defmodule LivePoll.Polls do
  alias LivePoll.Validation
  alias LivePoll.Polls.Option
  
  @doc """
  Add a new language with full validation
  """
  def add_language(name) when is_binary(name) do
    # Check for malicious content first
    if Validation.contains_malicious_content?(name) do
      {:error, "Invalid characters detected in language name"}
    else
      %Option{}
      |> Option.create_changeset(%{text: name, votes: 0})
      |> Repo.insert()
      |> case do
        {:ok, option} ->
          broadcast_option_added(option)
          {:ok, option}
        
        {:error, changeset} ->
          {:error, format_changeset_errors(changeset)}
      end
    end
  end
  
  def add_language(_), do: {:error, "Language name must be text"}
  
  @doc """
  Cast a vote with ID validation
  """
  def cast_vote(id) do
    with {:ok, int_id} <- Validation.validate_id(id),
         %Option{} = option <- get_option(int_id) do
      # Proceed with atomic vote increment
      do_cast_vote(option)
    else
      nil -> {:error, :option_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Seed votes with count validation
  """
  def seed_votes(count) do
    with {:ok, valid_count} <- Validation.validate_count(count) do
      Seeder.seed(vote_count: valid_count)
    end
  end
  
  @doc """
  Get sanitized chart data for safe display
  """
  def get_chart_data_safe do
    options = list_options()
    
    Enum.map(options, fn option ->
      %{
        name: Validation.sanitize_for_display(option.text),
        value: option.votes,
        id: option.id
      }
    end)
  end
  
  defp format_changeset_errors(changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    
    errors
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
```

### Step 4: Update LiveView with Validation
```elixir
# lib/live_poll_web/live/poll_live.ex
def handle_event("vote", %{"id" => id}, socket) do
  case LivePoll.Polls.cast_vote(id) do
    {:ok, option, _event} ->
      {:noreply, update_option_in_socket(socket, option)}
    
    {:error, :option_not_found} ->
      {:noreply, put_flash(socket, :error, "Option not found")}
    
    {:error, :invalid_id} ->
      {:noreply, put_flash(socket, :error, "Invalid vote selection")}
    
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to record vote")}
  end
end

def handle_event("add_language", %{"name" => name}, socket) do
  case LivePoll.Polls.add_language(name) do
    {:ok, option} ->
      {:noreply,
       socket
       |> load_data()
       |> assign(:form, to_form(%{"name" => ""}))
       |> put_flash(:info, "Added #{option.text} to the poll!")}
    
    {:error, message} ->
      {:noreply,
       socket
       |> assign(:form, to_form(%{"name" => name}))
       |> put_flash(:error, message)}
  end
end

def handle_event("seed_data", %{"count" => count}, socket) do
  case LivePoll.Polls.seed_votes(count) do
    {:ok, _task} ->
      {:noreply, put_flash(socket, :info, "Seeding votes...")}
    
    {:error, :count_too_large} ->
      {:noreply, put_flash(socket, :error, "Maximum 100,000 votes allowed")}
    
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Invalid vote count")}
  end
end
```

### Step 5: Sanitize JavaScript Chart Data
```javascript
// assets/js/charts.js
function sanitizeForTooltip(text) {
  const div = document.createElement('div');
  div.textContent = text;  // Uses textContent, not innerHTML
  return div.innerHTML;     // Returns escaped HTML
}

const PieChart = {
  mounted() {
    // ...
    this.chart.setOption({
      tooltip: {
        formatter: function(params) {
          const safeName = sanitizeForTooltip(params.name);
          return `${safeName}: ${params.value} votes (${params.percent}%)`;
        }
      },
      // ...
    });
  }
};
```

## Requirements
1. ✅ Validate all user inputs (language names, IDs, counts)
2. ✅ Sanitize text for safe HTML/JavaScript display
3. ✅ Prevent XSS in chart tooltips
4. ✅ Handle invalid IDs gracefully (no crashes)
5. ✅ Limit input lengths and characters
6. ✅ Provide clear validation error messages
7. ✅ Check for malicious patterns in input

## Definition of Done
1. **Validation Implementation**
   - [ ] Option changeset with comprehensive validation
   - [ ] Validation module for common patterns
   - [ ] All inputs validated before processing
   - [ ] Malicious content detection

2. **Security Fixes**
   - [ ] XSS prevention in tooltips
   - [ ] HTML escaping for display
   - [ ] JavaScript escaping for charts
   - [ ] No crashes from invalid input

3. **Tests**
   ```elixir
   test "rejects HTML tags in language names" do
     assert {:error, _} = Polls.add_language("<script>alert('xss')</script>")
   end
   
   test "rejects overly long language names" do
     long_name = String.duplicate("a", 51)
     assert {:error, _} = Polls.add_language(long_name)
   end
   
   test "handles invalid vote IDs gracefully" do
     assert {:error, :invalid_id} = Polls.cast_vote("not_a_number")
     assert {:error, :invalid_id} = Polls.cast_vote(-1)
     assert {:error, :option_not_found} = Polls.cast_vote(999999)
   end
   ```

4. **Quality Checks**
   - [ ] No XSS vulnerabilities
   - [ ] No crashes from user input
   - [ ] Clear error messages
   - [ ] `mix test` passes

## Branch Name
`fix/input-validation-security`

## Dependencies
- Task 003 (Unique Constraint) - Should be coordinated
- Task 004 (Extract Context) - Validation in context layer

## Estimated Complexity
**M (Medium)** - 3-4 hours

## Testing Instructions
1. Try adding languages with HTML tags (should be rejected)
2. Try adding languages with special characters
3. Try voting with invalid IDs (letters, negative, huge numbers)
4. Try seeding with invalid counts
5. Check chart tooltips properly escape special characters
6. Verify no console errors or crashes
7. Test validation error messages are helpful

## Security Checklist
- [ ] No <script> tags accepted
- [ ] No javascript: URLs accepted
- [ ] No event handlers (onclick=) accepted
- [ ] Tooltips escape HTML entities
- [ ] IDs validated as positive integers
- [ ] Counts have reasonable limits
- [ ] Error messages don't leak sensitive info

## Notes
- Consider using a library like HtmlSanitizeEx for more robust sanitization
- May want to add a blocklist of inappropriate language names
- Consider rate limiting along with validation
- Log validation failures for security monitoring
