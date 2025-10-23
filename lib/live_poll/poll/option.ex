defmodule LivePoll.Poll.Option do
  use Ecto.Schema
  import Ecto.Changeset

  schema "poll_options" do
    field :text, :string
    field :votes, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:text, :votes])
    |> validate_required([:text, :votes])
  end
end
