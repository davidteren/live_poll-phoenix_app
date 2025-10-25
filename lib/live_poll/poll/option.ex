defmodule LivePoll.Poll.Option do
  use Ecto.Schema
  import Ecto.Changeset

  schema "poll_options" do
    field :text, :string
    field :votes, :integer

    has_many :vote_events, LivePoll.Poll.VoteEvent

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating options with validation.

  Validates:
  - Required text field
  - Length between 1-50 characters
  - Only allowed characters (letters, numbers, spaces, and common programming symbols)
  - Trims whitespace
  - Normalizes case for consistency
  - Ensures uniqueness (case-insensitive)
  """
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :votes])
    |> validate_required([:text])
    |> validate_length(:text, min: 1, max: 50)
    |> validate_format(:text, ~r/^[a-zA-Z0-9\s\#\+\-\.\(\)\/]+$/,
      message: "only letters, numbers, spaces and common programming symbols allowed"
    )
    |> update_change(:text, &String.trim/1)
    |> update_change(:text, &LivePoll.Polls.normalize_language_name/1)
    |> unique_constraint(:text,
      name: :poll_options_text_unique,
      message: "This language already exists"
    )
  end
end
