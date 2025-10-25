defmodule LivePollWeb.PollLiveConcurrencyTest do
  use LivePollWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LivePoll.Poll.{Option, VoteEvent}
  alias LivePoll.Repo

  setup do
    # Clean up any existing data
    Repo.delete_all(VoteEvent)
    Repo.delete_all(Option)

    # Create a test option
    option = Repo.insert!(%Option{text: "Elixir", votes: 0})

    %{option: option}
  end

  describe "concurrent voting" do
    test "handles 100 concurrent votes without losing updates", %{conn: conn, option: option} do
      # Create 100 concurrent LiveView connections that will vote simultaneously
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            {:ok, view, _html} = live(conn, "/")
            view |> element("button[phx-value-id='#{option.id}']") |> render_click()
          end)
        end

      # Wait for all tasks to complete (with generous timeout)
      Task.await_many(tasks, 10_000)

      # Give broadcasts time to propagate
      :timer.sleep(200)

      # Verify exactly 100 votes were recorded (no lost updates)
      updated_option = Repo.get!(Option, option.id)
      assert updated_option.votes == 100, "Expected 100 votes, got #{updated_option.votes}"
    end

    test "handles 50 concurrent votes without losing updates", %{conn: conn, option: option} do
      # Smaller test for faster execution
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            {:ok, view, _html} = live(conn, "/")
            view |> element("button[phx-value-id='#{option.id}']") |> render_click()
          end)
        end

      Task.await_many(tasks, 5_000)
      :timer.sleep(100)

      updated_option = Repo.get!(Option, option.id)
      assert updated_option.votes == 50, "Expected 50 votes, got #{updated_option.votes}"
    end

    test "vote events have accurate vote counts under concurrency", %{conn: conn, option: option} do
      # Cast 20 concurrent votes
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, view, _html} = live(conn, "/")
            view |> element("button[phx-value-id='#{option.id}']") |> render_click()
          end)
        end

      Task.await_many(tasks, 5_000)
      :timer.sleep(100)

      # Verify all vote events were created
      vote_events =
        from(e in VoteEvent,
          where: e.option_id == ^option.id and e.event_type == "vote",
          order_by: [asc: e.votes_after]
        )
        |> Repo.all()

      assert length(vote_events) == 20

      # Verify votes_after values are sequential (1, 2, 3, ..., 20)
      # This proves each vote event captured the correct cumulative count
      votes_after_values = Enum.map(vote_events, & &1.votes_after)
      expected_values = Enum.to_list(1..20)

      assert Enum.sort(votes_after_values) == expected_values,
             "Vote events should have sequential votes_after values"
    end

    test "multiple options can receive concurrent votes independently", %{conn: conn} do
      # Create multiple options
      elixir = Repo.insert!(%Option{text: "Elixir", votes: 0})
      python = Repo.insert!(%Option{text: "Python", votes: 0})
      ruby = Repo.insert!(%Option{text: "Ruby", votes: 0})

      # Cast 30 votes to each option concurrently (90 total concurrent operations)
      tasks =
        for option <- [elixir, python, ruby],
            _ <- 1..30 do
          Task.async(fn ->
            {:ok, view, _html} = live(conn, "/")
            view |> element("button[phx-value-id='#{option.id}']") |> render_click()
          end)
        end

      Task.await_many(tasks, 10_000)
      :timer.sleep(200)

      # Verify each option has exactly 30 votes
      updated_elixir = Repo.get!(Option, elixir.id)
      updated_python = Repo.get!(Option, python.id)
      updated_ruby = Repo.get!(Option, ruby.id)

      assert updated_elixir.votes == 30, "Elixir should have 30 votes"
      assert updated_python.votes == 30, "Python should have 30 votes"
      assert updated_ruby.votes == 30, "Ruby should have 30 votes"
    end

    test "atomic increments work correctly with existing votes", %{conn: conn, option: option} do
      # Start with some existing votes
      Repo.update!(Ecto.Changeset.change(option, votes: 50))

      # Add 25 more concurrent votes
      tasks =
        for _ <- 1..25 do
          Task.async(fn ->
            {:ok, view, _html} = live(conn, "/")
            view |> element("button[phx-value-id='#{option.id}']") |> render_click()
          end)
        end

      Task.await_many(tasks, 5_000)
      :timer.sleep(100)

      # Should have 75 total votes (50 + 25)
      updated_option = Repo.get!(Option, option.id)
      assert updated_option.votes == 75, "Expected 75 votes, got #{updated_option.votes}"
    end
  end

  describe "error handling" do
    test "handles invalid option ID gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Try to vote with invalid ID
      view |> element("button[phx-value-id='99999']") |> render_click()

      # Should not crash, and no votes should be recorded
      all_options = Repo.all(Option)
      total_votes = Enum.sum(Enum.map(all_options, & &1.votes))
      assert total_votes == 0
    end

    test "handles non-numeric ID gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # This would require manually triggering the event with invalid data
      # In practice, the UI prevents this, but we test the handler directly
      result = send(view.pid, %Phoenix.Socket.Message{
        topic: "lv:#{view.id}",
        event: "event",
        payload: %{
          "type" => "click",
          "event" => "vote",
          "value" => %{"id" => "invalid"}
        },
        ref: "test"
      })

      # Give it time to process
      :timer.sleep(50)

      # Should not crash
      assert Process.alive?(view.pid)

      # No votes should be recorded
      all_options = Repo.all(Option)
      total_votes = Enum.sum(Enum.map(all_options, & &1.votes))
      assert total_votes == 0
    end

    test "handles malformed ID (number with trailing chars) gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Send event with malformed ID
      send(view.pid, %Phoenix.Socket.Message{
        topic: "lv:#{view.id}",
        event: "event",
        payload: %{
          "type" => "click",
          "event" => "vote",
          "value" => %{"id" => "123abc"}
        },
        ref: "test"
      })

      :timer.sleep(50)

      # Should not crash
      assert Process.alive?(view.pid)

      # No votes should be recorded
      all_options = Repo.all(Option)
      total_votes = Enum.sum(Enum.map(all_options, & &1.votes))
      assert total_votes == 0
    end
  end

  describe "broadcast consistency" do
    test "broadcasts contain accurate vote counts after concurrent updates", %{
      conn: conn,
      option: option
    } do
      # Subscribe to the broadcast topic
      Phoenix.PubSub.subscribe(LivePoll.PubSub, "poll:updates")

      # Cast 10 concurrent votes
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            {:ok, view, _html} = live(conn, "/")
            view |> element("button[phx-value-id='#{option.id}']") |> render_click()
          end)
        end

      Task.await_many(tasks, 5_000)

      # Collect all broadcast messages
      :timer.sleep(200)
      broadcasts = collect_broadcasts([])

      # Should have received 10 broadcasts
      assert length(broadcasts) == 10

      # All broadcasts should be for our option
      assert Enum.all?(broadcasts, fn {:poll_update, data} ->
               data.id == option.id && data.language == "Elixir"
             end)

      # Vote counts in broadcasts should be sequential (1 through 10)
      vote_counts =
        broadcasts
        |> Enum.map(fn {:poll_update, data} -> data.votes end)
        |> Enum.sort()

      assert vote_counts == Enum.to_list(1..10)
    end
  end

  # Helper function to collect broadcast messages
  defp collect_broadcasts(acc) do
    receive do
      {:poll_update, _data} = msg -> collect_broadcasts([msg | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end

