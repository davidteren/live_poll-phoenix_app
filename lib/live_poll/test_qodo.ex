defmodule LivePoll.TestQodo do
  @moduledoc """
  Test module to verify Qodo Merge Wiki configuration.
  This file contains patterns that should trigger our Phoenix-specific checks.
  """

  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Poll
  alias LivePoll.Poll.VoteEvent

  # This should trigger: "Replace read-modify-write with atomic operations"
  def increment_vote_count(poll_id) do
    poll = Repo.get!(Poll, poll_id)
    updated_poll = %{poll | vote_count: poll.vote_count + 1}
    Repo.update(updated_poll)
  end

  # This should trigger: "Use batch operations instead of individual inserts"  
  def create_multiple_votes(votes) do
    Enum.each(votes, fn vote ->
      Repo.insert(vote)
    end)
  end

  # This should trigger: "Loading all records into memory"
  def get_all_events do
    Repo.all(VoteEvent)
  end

  # Good pattern - should be recognized as correct
  def atomic_increment(poll_id) do
    from(p in Poll, where: p.id == ^poll_id)
    |> Repo.update_all(inc: [vote_count: 1])
  end
end
