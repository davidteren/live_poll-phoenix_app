defmodule LivePoll.PollsTest do
  use LivePoll.DataCase

  alias LivePoll.Polls
  alias LivePoll.Poll.{Option, VoteEvent}

  describe "list_options/0" do
    test "returns all options sorted by ID" do
      option1 = insert_option("Elixir", 10)
      option2 = insert_option("Python", 20)
      option3 = insert_option("Rust", 5)

      options = Polls.list_options()

      assert length(options) == 3
      assert Enum.map(options, & &1.id) == [option1.id, option2.id, option3.id]
    end

    test "returns empty list when no options exist" do
      assert Polls.list_options() == []
    end
  end

  describe "list_options_by_votes/0" do
    test "returns options sorted by votes descending" do
      insert_option("Elixir", 10)
      insert_option("Python", 20)
      insert_option("Rust", 5)

      options = Polls.list_options_by_votes()

      assert length(options) == 3
      assert Enum.map(options, & &1.votes) == [20, 10, 5]
      assert Enum.map(options, & &1.text) == ["Python", "Elixir", "Rust"]
    end
  end

  describe "get_option!/1" do
    test "returns the option with given id" do
      option = insert_option("Elixir", 42)
      assert Polls.get_option!(option.id).text == "Elixir"
    end

    test "raises when option does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Polls.get_option!(999)
      end
    end
  end

  describe "add_language/1" do
    test "creates a new language option with 0 votes" do
      assert {:ok, option} = Polls.add_language("Rust")
      assert option.text == "Rust"
      assert option.votes == 0
    end

    test "returns error when language already exists" do
      insert_option("Elixir", 10)
      assert {:error, "Language already exists"} = Polls.add_language("Elixir")
    end

    test "returns error when name is empty" do
      assert {:error, "Language name cannot be empty"} = Polls.add_language("")
    end

    test "returns error when name is not a string" do
      assert {:error, "Language name cannot be empty"} = Polls.add_language(nil)
    end
  end

  describe "cast_vote/1" do
    test "increments vote count atomically" do
      option = insert_option("Elixir", 10)

      assert {:ok, updated_option, event} = Polls.cast_vote(option.id)
      assert updated_option.votes == 11
      assert event.option_id == option.id
      assert event.votes_after == 11
      assert event.event_type == "vote"
    end

    test "creates a vote event" do
      option = insert_option("Elixir", 10)

      assert {:ok, _option, event} = Polls.cast_vote(option.id)
      assert event.language == "Elixir"
      assert event.votes_after == 11
    end

    test "returns error for non-existent option" do
      assert {:error, :option_not_found} = Polls.cast_vote(999)
    end

    test "returns error for invalid option_id" do
      assert {:error, :invalid_option_id} = Polls.cast_vote("invalid")
      assert {:error, :invalid_option_id} = Polls.cast_vote(nil)
    end

    test "handles concurrent votes correctly" do
      option = insert_option("Elixir", 0)

      # Simulate concurrent votes
      tasks =
        for _ <- 1..10 do
          Task.async(fn -> Polls.cast_vote(option.id) end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All votes should succeed
      assert Enum.all?(results, fn
               {:ok, _, _} -> true
               _ -> false
             end)

      # Final count should be exactly 10
      final_option = Polls.get_option!(option.id)
      assert final_option.votes == 10
    end
  end

  describe "reset_all_votes/0" do
    test "resets all vote counts to 0" do
      insert_option("Elixir", 10)
      insert_option("Python", 20)

      assert {:ok, :reset_complete} = Polls.reset_all_votes()

      options = Polls.list_options()
      assert Enum.all?(options, fn opt -> opt.votes == 0 end)
    end

    test "deletes all vote events" do
      option = insert_option("Elixir", 10)
      insert_vote_event(option, 5)
      insert_vote_event(option, 10)

      assert Repo.aggregate(VoteEvent, :count) == 2

      Polls.reset_all_votes()

      assert Repo.aggregate(VoteEvent, :count) == 0
    end
  end

  describe "calculate_percentages/1" do
    test "calculates correct percentages" do
      options = [
        %{text: "Elixir", votes: 25},
        %{text: "Python", votes: 75}
      ]

      percentages = Polls.calculate_percentages(options)

      assert percentages["Elixir"] == 25.0
      assert percentages["Python"] == 75.0
    end

    test "returns 0.0 for all when total is 0" do
      options = [
        %{text: "Elixir", votes: 0},
        %{text: "Python", votes: 0}
      ]

      percentages = Polls.calculate_percentages(options)

      assert percentages["Elixir"] == 0.0
      assert percentages["Python"] == 0.0
    end

    test "handles single option with all votes" do
      options = [%{text: "Elixir", votes: 100}]

      percentages = Polls.calculate_percentages(options)

      assert percentages["Elixir"] == 100.0
    end
  end

  describe "get_total_votes/0" do
    test "returns sum of all votes" do
      insert_option("Elixir", 10)
      insert_option("Python", 20)
      insert_option("Rust", 5)

      assert Polls.get_total_votes() == 35
    end

    test "returns 0 when no options exist" do
      assert Polls.get_total_votes() == 0
    end
  end

  describe "get_stats/0" do
    test "returns comprehensive statistics" do
      insert_option("Elixir", 10)
      insert_option("Python", 20)

      stats = Polls.get_stats()

      assert length(stats.options) == 2
      assert length(stats.sorted_options) == 2
      assert stats.total_votes == 30
      assert stats.percentages["Elixir"] == 33.3
      assert stats.percentages["Python"] == 66.7
      assert stats.leader.text == "Python"
    end

    test "returns nil leader when no options exist" do
      stats = Polls.get_stats()

      assert stats.leader == nil
      assert stats.total_votes == 0
    end
  end

  describe "list_vote_events/1" do
    test "returns all events ordered by most recent" do
      option = insert_option("Elixir", 10)
      event1 = insert_vote_event(option, 5)
      event2 = insert_vote_event(option, 10)

      events = Polls.list_vote_events()

      assert length(events) == 2
      # Most recent first
      assert List.first(events).id == event2.id
    end

    test "filters by option_id" do
      option1 = insert_option("Elixir", 10)
      option2 = insert_option("Python", 20)
      insert_vote_event(option1, 5)
      insert_vote_event(option2, 10)

      events = Polls.list_vote_events(option_id: option1.id)

      assert length(events) == 1
      assert List.first(events).option_id == option1.id
    end

    test "filters by event_type" do
      option = insert_option("Elixir", 10)
      insert_vote_event(option, 5, "vote")
      insert_vote_event(option, 10, "seed")

      events = Polls.list_vote_events(event_type: "vote")

      assert length(events) == 1
      assert List.first(events).event_type == "vote"
    end

    test "limits results" do
      option = insert_option("Elixir", 10)
      insert_vote_event(option, 1)
      insert_vote_event(option, 2)
      insert_vote_event(option, 3)

      events = Polls.list_vote_events(limit: 2)

      assert length(events) == 2
    end
  end

  # Helper functions
  defp insert_option(text, votes) do
    %Option{}
    |> Option.changeset(%{text: text, votes: votes})
    |> Repo.insert!()
  end

  defp insert_vote_event(option, votes_after, event_type \\ "vote") do
    %VoteEvent{}
    |> VoteEvent.changeset(%{
      option_id: option.id,
      language: option.text,
      votes_after: votes_after,
      event_type: event_type
    })
    |> Repo.insert!()
  end
end

