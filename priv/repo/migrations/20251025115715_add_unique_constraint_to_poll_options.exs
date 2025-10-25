defmodule LivePoll.Repo.Migrations.AddUniqueConstraintToPollOptions do
  use Ecto.Migration

  def up do
    # First, merge vote counts from duplicates (case-insensitive)
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

    # Delete duplicate entries, keeping only the one with the lowest ID
    execute """
    DELETE FROM poll_options o1
    WHERE EXISTS (
      SELECT 1 FROM poll_options o2
      WHERE LOWER(TRIM(o2.text)) = LOWER(TRIM(o1.text))
      AND o2.id < o1.id
    )
    """

    # Add case-insensitive unique index
    create unique_index(:poll_options, ["lower(trim(text))"], name: :poll_options_text_unique)
  end

  def down do
    drop index(:poll_options, :poll_options_text_unique)
  end
end
