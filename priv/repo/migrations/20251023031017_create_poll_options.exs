defmodule LivePoll.Repo.Migrations.CreatePollOptions do
  use Ecto.Migration

  def change do
    create table(:poll_options) do
      add :text, :string
      add :votes, :integer

      timestamps(type: :utc_datetime)
    end
  end
end
