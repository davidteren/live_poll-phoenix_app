defmodule LivePoll.Repo.Migrations.CreateVoteEvents do
  use Ecto.Migration

  def change do
    create table(:vote_events) do
      add :option_id, references(:poll_options, on_delete: :delete_all), null: false
      add :language, :string, null: false
      add :votes_after, :integer, null: false
      add :event_type, :string, null: false, default: "vote"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:vote_events, [:option_id])
    create index(:vote_events, [:inserted_at])
    create index(:vote_events, [:language])
  end
end
