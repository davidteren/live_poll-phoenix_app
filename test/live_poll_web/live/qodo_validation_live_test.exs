defmodule LivePollWeb.QodoValidationLiveTest do
  @moduledoc """
  Test file with TESTING ANTI-PATTERNS for Qodo to detect.
  
  Expected Qodo Findings:
  - timer.sleep usage (should use assert_receive)
  - No concurrent operation tests
  - No error path tests
  - Weak assertions
  """
  
  use LivePollWeb.ConnCase
  import Phoenix.LiveViewTest

  alias LivePoll.Poll.Option

  # TESTING ANTI-PATTERN: Using timer.sleep instead of proper async handling
  test "voting updates count with timing issue", %{conn: conn} do
    option = Repo.insert!(%Option{text: "Elixir", votes: 0})
    
    {:ok, view, _html} = live(conn, "/qodo-validation")
    
    # Click vote button
    view
    |> element("button[phx-value-id='#{option.id}']")
    |> render_click()
    
    # BAD: Using sleep to wait for async operation - flaky test!
    :timer.sleep(100)
    
    # BAD: Weak assertion
    html = render(view)
    assert html =~ "1"
  end

  # TESTING ANTI-PATTERN: No concurrent operation test for race condition
  test "does not test concurrent voting", %{conn: conn} do
    option = Repo.insert!(%Option{text: "Python", votes: 0})
    
    {:ok, view, _html} = live(conn, "/qodo-validation")
    
    # BAD: Only testing single vote, not concurrent race condition
    view
    |> element("button[phx-value-id='#{option.id}']")
    |> render_click()
    
    # Should test: 100 concurrent votes result in exactly 100 votes
    # Currently missing this critical test
  end

  # TESTING ANTI-PATTERN: No error path testing
  test "does not test error handling", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/qodo-validation")
    
    # BAD: Not testing invalid option ID
    # BAD: Not testing what happens when Repo.get! fails
    # Should test error paths but doesn't
    
    assert render(view) =~ "Qodo Validation"
  end

  # TESTING ANTI-PATTERN: No validation testing
  test "does not test input validation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/qodo-validation")
    
    # BAD: Should test XSS, injection, length limits
    # BAD: Should test duplicate language names
    # Currently missing all validation tests
    
    view
    |> form("#language-form", %{name: "Rust"})
    |> render_submit()
  end

  # TESTING ANTI-PATTERN: Another timer.sleep example
  test "seeding with timing dependency", %{conn: conn} do
    Repo.insert!(%Option{text: "JavaScript", votes: 0})
    
    {:ok, view, _html} = live(conn, "/qodo-validation")
    
    view
    |> element("button[phx-value-count='100']")
    |> render_click()
    
    # BAD: Waiting for seeding to complete with sleep
    :timer.sleep(500)
    
    html = render(view)
    assert html =~ "Seeded"
  end
end
