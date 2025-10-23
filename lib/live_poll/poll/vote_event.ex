defmodule LivePoll.Poll.VoteEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vote_events" do
    field :language, :string
    field :votes_after, :integer
    field :event_type, :string, default: "vote"
    
    belongs_to :option, LivePoll.Poll.Option

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(vote_event, attrs) do
    vote_event
    |> cast(attrs, [:option_id, :language, :votes_after, :event_type])
    |> validate_required([:option_id, :language, :votes_after, :event_type])
    |> validate_inclusion(:event_type, ["vote", "seed", "reset"])
  end
end

