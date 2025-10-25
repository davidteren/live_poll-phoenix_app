defmodule LivePoll.Polls do
  @moduledoc """
  The Polls context.

  Provides functions for managing poll options and votes with proper validation.
  """

  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Poll.Option

  @doc """
  Add a new programming language with validation.

  Returns `{:ok, option}` if successful, or `{:error, message}` if validation fails.

  ## Examples

      iex> add_language("Python")
      {:ok, %Option{text: "Python", votes: 0}}

      iex> add_language("python")
      {:ok, %Option{text: "Python", votes: 0}}

      iex> add_language("Python")
      {:error, "text: This language already exists"}

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
  Check if a language already exists (case-insensitive).

  ## Examples

      iex> language_exists?("Python")
      true

      iex> language_exists?("python")
      true

      iex> language_exists?("NonExistent")
      false

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
  Get similar language names for suggestions.

  Returns up to 5 languages that match the given pattern.

  ## Examples

      iex> find_similar_languages("py")
      [%Option{text: "Python"}]

  """
  def find_similar_languages(name) when is_binary(name) do
    pattern = "%#{String.downcase(name)}%"

    Repo.all(
      from o in Option,
        where: fragment("lower(?) LIKE ?", o.text, ^pattern),
        limit: 5
    )
  end

  def find_similar_languages(_), do: []

  @doc """
  List all poll options.
  """
  def list_options do
    Repo.all(from o in Option, order_by: [asc: o.id])
  end

  @doc """
  Get a single option by ID.
  """
  def get_option!(id), do: Repo.get!(Option, id)

  @doc """
  Get an option by text (case-insensitive).
  """
  def get_option_by_text(text) when is_binary(text) do
    normalized = String.trim(text) |> String.downcase()

    Repo.one(
      from o in Option,
        where: fragment("lower(trim(?)) = ?", o.text, ^normalized)
    )
  end

  def get_option_by_text(_), do: nil

  # Private functions

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end

  defp broadcast_option_added(option) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:language_added, %{name: option.text}}
    )
  end
end
