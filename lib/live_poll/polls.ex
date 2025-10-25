defmodule LivePoll.Polls do
  @moduledoc """
  The Polls context - manages all voting and poll-related business logic.
  
  This context provides functions for:
  - Managing poll options (languages)
  - Validating and preventing duplicates
  - Finding similar language names
  """

  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Poll.{Option, VoteEvent}

  @doc """
  Adds a new programming language to the poll.
  
  Returns `{:ok, option}` if successful, or `{:error, message}` if validation fails.
  
  ## Examples
  
      iex> add_language("Python")
      {:ok, %Option{text: "Python", votes: 0}}
      
      iex> add_language("python")  # Duplicate (case-insensitive)
      {:error, "Python already exists"}
      
      iex> add_language("")
      {:error, "text: can't be blank"}
  """
  def add_language(name) when is_binary(name) do
    %Option{}
    |> Option.changeset(%{text: name, votes: 0})
    |> Repo.insert()
    |> case do
      {:ok, option} ->
        broadcast_option_added(option)
        {:ok, option}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  def add_language(_), do: {:error, "Invalid language name"}

  @doc """
  Checks if a language already exists in the poll (case-insensitive).
  
  ## Examples
  
      iex> language_exists?("Python")
      true
      
      iex> language_exists?("python")
      true
      
      iex> language_exists?("  Python  ")
      true
  """
  def language_exists?(name) when is_binary(name) do
    normalized = String.trim(name) |> String.downcase()

    Repo.exists?(
      from o in Option,
        where: fragment("lower(trim(?)) = ?", o.text, ^normalized)
    )
  end

  def language_exists?(_), do: false

  @doc """
  Finds languages with similar names for suggestions.
  
  Returns up to 5 languages that match the given pattern.
  
  ## Examples
  
      iex> find_similar_languages("java")
      [%Option{text: "JavaScript"}, %Option{text: "Java"}]
  """
  def find_similar_languages(name) when is_binary(name) do
    pattern = "%#{String.downcase(name)}%"

    Repo.all(
      from o in Option,
        where: fragment("lower(?) LIKE ?", o.text, ^pattern),
        limit: 5,
        order_by: [asc: o.text]
    )
  end

  def find_similar_languages(_), do: []

  @doc """
  Lists all poll options sorted by ID.
  """
  def list_options do
    Repo.all(from o in Option, order_by: [asc: o.id])
  end

  @doc """
  Gets a single option by ID.
  """
  def get_option(id) do
    Repo.get(Option, id)
  end

  @doc """
  Gets a single option by ID, raises if not found.
  """
  def get_option!(id) do
    Repo.get!(Option, id)
  end

  # Private helper functions

  defp format_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    # Check if it's a uniqueness error and provide a better message
    case errors do
      %{text: messages} when is_list(messages) ->
        messages
        |> Enum.map(fn msg ->
          if String.contains?(msg, "already exists") do
            # Extract the normalized name from the changeset
            text = Ecto.Changeset.get_field(changeset, :text)
            "#{text} already exists"
          else
            "text: #{msg}"
          end
        end)
        |> Enum.join("; ")

      _ ->
        errors
        |> Enum.map(fn {field, field_errors} ->
          "#{field}: #{Enum.join(field_errors, ", ")}"
        end)
        |> Enum.join("; ")
    end
  end

  defp broadcast_option_added(option) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:language_added, %{name: option.text}}
    )
  end
end

