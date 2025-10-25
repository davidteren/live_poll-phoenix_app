defmodule LivePoll.Poll.Option do
  use Ecto.Schema
  import Ecto.Changeset

  schema "poll_options" do
    field :text, :string
    field :votes, :integer, default: 0

    has_many :vote_events, LivePoll.Poll.VoteEvent

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating options with validation.

  Validates:
  - Required text field
  - Text length between 1 and 50 characters
  - Only allowed characters (letters, numbers, spaces, and common programming symbols)
  - Trims whitespace
  - Normalizes case for common acronyms
  - Ensures uniqueness (case-insensitive)
  """
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :votes])
    |> validate_required([:text])
    |> validate_length(:text, min: 1, max: 50, message: "must be between 1 and 50 characters")
    |> validate_format(:text, ~r/^[a-zA-Z0-9\s\#\+\-\.\(\)\/\*]+$/,
      message: "only letters, numbers, spaces and common programming symbols allowed"
    )
    |> update_change(:text, &String.trim/1)
    |> update_change(:text, &normalize_case/1)
    |> unique_constraint(:text,
      name: :poll_options_text_unique,
      message: "already exists"
    )
  end

  @doc """
  Normalizes the case of programming language names.
  Preserves case for well-known acronyms, applies title case for others.
  """
  defp normalize_case(text) when is_binary(text) do
    # Preserve case for common acronyms and special cases
    case String.upcase(text) do
      "PHP" -> "PHP"
      "SQL" -> "SQL"
      "MATLAB" -> "MATLAB"
      "COBOL" -> "COBOL"
      "R" -> "R"
      "C" -> "C"
      "C++" -> "C++"
      "C#" -> "C#"
      "F#" -> "F#"
      _ ->
        # Title case for most languages
        text
        |> String.downcase()
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp normalize_case(text), do: text
end
