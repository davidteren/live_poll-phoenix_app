defmodule LivePoll.PollsTest do
  use LivePoll.DataCase, async: true

  alias LivePoll.Polls
  alias LivePoll.Poll.Option

  describe "add_language/1" do
    test "creates a new language option with valid data" do
      assert {:ok, %Option{} = option} = Polls.add_language("Python")
      assert option.text == "Python"
      assert option.votes == 0
    end

    test "prevents duplicate language names (exact match)" do
      assert {:ok, _} = Polls.add_language("Python")
      assert {:error, message} = Polls.add_language("Python")
      assert message =~ "Python already exists"
    end

    test "prevents duplicate language names (case-insensitive)" do
      assert {:ok, _} = Polls.add_language("JavaScript")
      assert {:error, message} = Polls.add_language("javascript")
      assert message =~ "Javascript already exists"

      assert {:error, message} = Polls.add_language("JAVASCRIPT")
      assert message =~ "Javascript already exists"

      assert {:error, message} = Polls.add_language("JaVaScRiPt")
      assert message =~ "Javascript already exists"
    end

    test "trims whitespace before checking uniqueness" do
      assert {:ok, option} = Polls.add_language("Ruby")
      assert option.text == "Ruby"

      assert {:error, message} = Polls.add_language("  Ruby  ")
      assert message =~ "Ruby already exists"

      assert {:error, message} = Polls.add_language("\tRuby\n")
      assert message =~ "Ruby already exists"
    end

    test "normalizes case for common programming languages" do
      assert {:ok, option} = Polls.add_language("python")
      assert option.text == "Python"

      assert {:ok, option} = Polls.add_language("javascript")
      assert option.text == "Javascript"

      assert {:ok, option} = Polls.add_language("type script")
      assert option.text == "Type Script"
    end

    test "preserves case for well-known acronyms" do
      assert {:ok, option} = Polls.add_language("php")
      assert option.text == "PHP"

      assert {:ok, option} = Polls.add_language("sql")
      assert option.text == "SQL"

      assert {:ok, option} = Polls.add_language("c++")
      assert option.text == "C++"

      assert {:ok, option} = Polls.add_language("c#")
      assert option.text == "C#"
    end

    test "validates text length" do
      # Too short (empty after trim)
      assert {:error, message} = Polls.add_language("")
      assert message =~ "can't be blank"

      assert {:error, message} = Polls.add_language("   ")
      assert message =~ "can't be blank"

      # Too long (over 50 characters)
      long_name = String.duplicate("a", 51)
      assert {:error, message} = Polls.add_language(long_name)
      assert message =~ "must be between 1 and 50 characters"
    end

    test "validates allowed characters" do
      # Valid characters
      assert {:ok, _} = Polls.add_language("C++")
      assert {:ok, _} = Polls.add_language("C#")
      assert {:ok, _} = Polls.add_language("F#")
      assert {:ok, _} = Polls.add_language("Objective-C")
      assert {:ok, _} = Polls.add_language("Visual Basic .NET")

      # Invalid characters
      assert {:error, message} = Polls.add_language("Python@3")
      assert message =~ "only letters, numbers, spaces and common programming symbols allowed"

      assert {:error, message} = Polls.add_language("Java$cript")
      assert message =~ "only letters, numbers, spaces and common programming symbols allowed"

      assert {:error, message} = Polls.add_language("Ruby & Rails")
      assert message =~ "only letters, numbers, spaces and common programming symbols allowed"
    end

    test "returns error for invalid input types" do
      assert {:error, "Invalid language name"} = Polls.add_language(nil)
      assert {:error, "Invalid language name"} = Polls.add_language(123)
      assert {:error, "Invalid language name"} = Polls.add_language(%{})
    end
  end

  describe "language_exists?/1" do
    test "returns true when language exists (exact match)" do
      Polls.add_language("Python")
      assert Polls.language_exists?("Python") == true
    end

    test "returns true when language exists (case-insensitive)" do
      Polls.add_language("Python")
      assert Polls.language_exists?("python") == true
      assert Polls.language_exists?("PYTHON") == true
      assert Polls.language_exists?("PyThOn") == true
    end

    test "returns true when language exists (with whitespace)" do
      Polls.add_language("Python")
      assert Polls.language_exists?("  Python  ") == true
      assert Polls.language_exists?("\tPython\n") == true
    end

    test "returns false when language does not exist" do
      assert Polls.language_exists?("NonExistent") == false
    end

    test "returns false for invalid input types" do
      assert Polls.language_exists?(nil) == false
      assert Polls.language_exists?(123) == false
      assert Polls.language_exists?(%{}) == false
    end
  end

  describe "find_similar_languages/1" do
    setup do
      Polls.add_language("JavaScript")
      Polls.add_language("Java")
      Polls.add_language("Python")
      Polls.add_language("TypeScript")
      :ok
    end

    test "finds languages with similar names" do
      results = Polls.find_similar_languages("java")
      texts = Enum.map(results, & &1.text)

      assert "JavaScript" in texts
      assert "Java" in texts
    end

    test "finds languages with partial matches" do
      results = Polls.find_similar_languages("script")
      texts = Enum.map(results, & &1.text)

      assert "JavaScript" in texts
      assert "TypeScript" in texts
    end

    test "returns empty list when no matches found" do
      results = Polls.find_similar_languages("rust")
      assert results == []
    end

    test "limits results to 5 languages" do
      # Add more languages
      Enum.each(1..10, fn i ->
        Polls.add_language("Language#{i}")
      end)

      results = Polls.find_similar_languages("language")
      assert length(results) <= 5
    end

    test "returns empty list for invalid input types" do
      assert Polls.find_similar_languages(nil) == []
      assert Polls.find_similar_languages(123) == []
      assert Polls.find_similar_languages(%{}) == []
    end
  end

  describe "list_options/0" do
    test "returns all options sorted by ID" do
      {:ok, opt1} = Polls.add_language("Python")
      {:ok, opt2} = Polls.add_language("JavaScript")
      {:ok, opt3} = Polls.add_language("Ruby")

      options = Polls.list_options()
      assert length(options) == 3
      assert Enum.at(options, 0).id == opt1.id
      assert Enum.at(options, 1).id == opt2.id
      assert Enum.at(options, 2).id == opt3.id
    end

    test "returns empty list when no options exist" do
      assert Polls.list_options() == []
    end
  end

  describe "get_option/1 and get_option!/1" do
    test "get_option/1 returns the option when it exists" do
      {:ok, option} = Polls.add_language("Python")
      assert Polls.get_option(option.id).id == option.id
    end

    test "get_option/1 returns nil when option does not exist" do
      assert Polls.get_option(999_999) == nil
    end

    test "get_option!/1 returns the option when it exists" do
      {:ok, option} = Polls.add_language("Python")
      assert Polls.get_option!(option.id).id == option.id
    end

    test "get_option!/1 raises when option does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Polls.get_option!(999_999)
      end
    end
  end
end

