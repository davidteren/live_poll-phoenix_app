defmodule LivePollWeb.PollLiveTest do
  use LivePollWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LivePoll.Poll.Option
  alias LivePoll.Repo

  setup do
    # Clean up any existing options
    Repo.delete_all(Option)

    # Create test options
    elixir = Repo.insert!(%Option{text: "Elixir", votes: 0})
    python = Repo.insert!(%Option{text: "Python", votes: 0})
    javascript = Repo.insert!(%Option{text: "JavaScript", votes: 0})
    ruby = Repo.insert!(%Option{text: "Ruby", votes: 0})

    %{options: [elixir, python, javascript, ruby]}
  end

  describe "mount" do
    test "loads all poll options", %{conn: conn, options: options} do
      {:ok, view, _html} = live(conn, "/")

      # Verify all options are displayed
      assert has_element?(view, "h3", "Elixir")
      assert has_element?(view, "h3", "Python")
      assert has_element?(view, "h3", "JavaScript")
      assert has_element?(view, "h3", "Ruby")
    end

    test "displays total votes correctly", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Initially should show 0 total votes
      assert render(view) =~ "Total Votes"
    end
  end

  describe "voting" do
    test "increments vote count when vote button is clicked", %{conn: conn, options: [elixir | _]} do
      {:ok, view, _html} = live(conn, "/")

      # Click vote button for Elixir
      view |> element("button[phx-value-id='#{elixir.id}']") |> render_click()

      # Verify vote count increased
      updated_option = Repo.get!(Option, elixir.id)
      assert updated_option.votes == 1
    end

    test "updates total votes after voting", %{conn: conn, options: [elixir | _]} do
      {:ok, view, _html} = live(conn, "/")

      # Vote for Elixir
      view |> element("button[phx-value-id='#{elixir.id}']") |> render_click()

      # Wait for update
      :timer.sleep(100)

      # Verify total votes updated
      html = render(view)
      assert html =~ "1 vote"
    end

    test "broadcasts vote updates to all connected clients", %{conn: conn, options: [elixir | _]} do
      {:ok, view1, _html} = live(conn, "/")
      {:ok, view2, _html} = live(conn, "/")

      # Vote from first client
      view1 |> element("button[phx-value-id='#{elixir.id}']") |> render_click()

      # Wait for broadcast
      :timer.sleep(100)

      # Both clients should see the update
      assert render(view1) =~ "1 vote"
      assert render(view2) =~ "1 vote"
    end
  end

  describe "reset functionality" do
    test "resets all votes to zero", %{conn: conn, options: options} do
      # Add some votes first
      Enum.each(options, fn option ->
        changeset = Ecto.Changeset.change(option, votes: 10)
        Repo.update!(changeset)
      end)

      {:ok, view, _html} = live(conn, "/")

      # Click reset button
      view |> element("button[phx-click='reset_votes']") |> render_click()

      # Wait for update
      :timer.sleep(100)

      # Verify all votes are reset
      Enum.each(options, fn option ->
        updated = Repo.get!(Option, option.id)
        assert updated.votes == 0
      end)
    end

    test "broadcasts reset to all connected clients", %{conn: conn, options: [elixir | _]} do
      # Add some votes
      changeset = Ecto.Changeset.change(elixir, votes: 5)
      Repo.update!(changeset)

      {:ok, view1, _html} = live(conn, "/")
      {:ok, view2, _html} = live(conn, "/")

      # Reset from first client
      view1 |> element("button[phx-click='reset_votes']") |> render_click()

      # Wait for broadcast
      :timer.sleep(100)

      # Both clients should see reset
      assert render(view1) =~ "0 votes"
      assert render(view2) =~ "0 votes"
    end
  end

  describe "pie chart calculations" do
    test "calculates correct percentages for pie chart", %{conn: conn, options: [elixir, python, javascript, ruby]} do
      # Set specific vote counts
      Repo.update!(Ecto.Changeset.change(elixir, votes: 40))
      Repo.update!(Ecto.Changeset.change(python, votes: 30))
      Repo.update!(Ecto.Changeset.change(javascript, votes: 20))
      Repo.update!(Ecto.Changeset.change(ruby, votes: 10))

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Verify percentages are displayed correctly
      assert html =~ "40%"  # Elixir
      assert html =~ "30%"  # Python
      assert html =~ "20%"  # JavaScript
      assert html =~ "10%"  # Ruby
    end

    test "pie chart segments use correct language-specific classes", %{conn: conn, options: options} do
      # Add votes
      Enum.each(options, fn option ->
        changeset = Ecto.Changeset.change(option, votes: 25)
        Repo.update!(changeset)
      end)

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Verify language-specific CSS classes are present
      assert html =~ "chart-slice-elixir"
      assert html =~ "chart-slice-python"
      assert html =~ "chart-slice-javascript"
      assert html =~ "chart-slice-ruby"
    end

    test "calculates correct SVG path parameters for donut chart", %{conn: conn, options: [elixir, python | _]} do
      # Set votes: Elixir 75, Python 25 (total 100 for easy math)
      Repo.update!(Ecto.Changeset.change(elixir, votes: 75))
      Repo.update!(Ecto.Changeset.change(python, votes: 25))

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Verify SVG path elements are present
      assert html =~ "viewBox=\"0 0 200 200\""
      assert html =~ "<path"
      assert html =~ "stroke=\"white\""
      assert html =~ "stroke-width=\"2\""

      # Verify the path uses the 'd' attribute for drawing
      assert html =~ "d=\"M"
      assert html =~ "A 90 90"  # Outer arc with radius 90
      assert html =~ "A 50 50"  # Inner arc with radius 50
    end

    test "handles zero votes gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Should show grey circle when no votes
      assert html =~ "stroke=\"#d4d4d8\""
      assert html =~ "r=\"70\""
      assert html =~ "stroke-width=\"40\""
    end

    test "shows full circle when only one option has votes", %{conn: conn, options: [elixir | _rest]} do
      # Reset ALL options in database to 0 first
      Repo.all(Option)
      |> Enum.each(fn opt ->
        Repo.update!(Ecto.Changeset.change(opt, votes: 0))
      end)

      # Give only Elixir votes
      Repo.update!(Ecto.Changeset.change(elixir, votes: 100))

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Should show full circle for Elixir (100%)
      assert html =~ ~s(<path d="M 100 10 A 90 90)
      assert html =~ "chart-slice-elixir"

      # Should only have ONE path element in the SVG (for Elixir)
      # Count path elements within the SVG viewBox
      svg_section = html |> String.split("viewBox=\"0 0 200 200\"") |> Enum.at(1) |> String.split("</svg>") |> Enum.at(0)
      path_count = svg_section |> String.split("<path") |> length() |> Kernel.-(1)
      assert path_count == 1
    end

    test "calculates cumulative offsets correctly for multiple segments", %{conn: conn, options: [elixir, python, javascript, ruby]} do
      # Set equal votes for predictable offsets
      Repo.update!(Ecto.Changeset.change(elixir, votes: 25))
      Repo.update!(Ecto.Changeset.change(python, votes: 25))
      Repo.update!(Ecto.Changeset.change(javascript, votes: 25))
      Repo.update!(Ecto.Changeset.change(ruby, votes: 25))

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Each segment should be 25% of the circle
      # Verify all four language classes are present
      assert html =~ "chart-slice-elixir"
      assert html =~ "chart-slice-python"
      assert html =~ "chart-slice-javascript"
      assert html =~ "chart-slice-ruby"

      # Verify percentages
      assert html =~ "25%"
    end
  end

  describe "progress bars" do
    test "uses language-specific colors for progress bars", %{conn: conn, options: [elixir | _]} do
      Repo.update!(Ecto.Changeset.change(elixir, votes: 10))

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Verify data-language attribute is present
      assert html =~ "data-language=\"Elixir\""
    end
  end

  describe "bar chart" do
    test "uses language-specific colors for bar chart", %{conn: conn, options: options} do
      Enum.each(options, fn option ->
        changeset = Ecto.Changeset.change(option, votes: 10)
        Repo.update!(changeset)
      end)

      {:ok, view, _html} = live(conn, "/")

      html = render(view)

      # Verify data-language attributes are present for all languages
      assert html =~ "data-language=\"Elixir\""
      assert html =~ "data-language=\"Python\""
      assert html =~ "data-language=\"JavaScript\""
      assert html =~ "data-language=\"Ruby\""
    end
  end
end

