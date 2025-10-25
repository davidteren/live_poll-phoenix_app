defmodule LivePoll.Polls.VoteService do
  @moduledoc """
  Voting calculations and business logic.
  
  This module handles:
  - Percentage calculations
  - Vote distribution analysis
  - Statistical computations
  """

  @doc """
  Calculate vote percentages for a list of options.
  
  Returns a map of language name to percentage (rounded to 1 decimal place).
  If total votes is 0, all percentages are 0.0.
  
  ## Examples
  
      iex> options = [
      ...>   %{text: "Elixir", votes: 42},
      ...>   %{text: "Python", votes: 58}
      ...> ]
      iex> VoteService.calculate_percentages(options)
      %{"Elixir" => 42.0, "Python" => 58.0}
      
      iex> VoteService.calculate_percentages([])
      %{}
  """
  def calculate_percentages(options) when is_list(options) do
    total = Enum.sum(Enum.map(options, & &1.votes))

    if total > 0 do
      options
      |> Enum.map(fn option ->
        {option.text, Float.round(option.votes * 100 / total, 1)}
      end)
      |> Map.new()
    else
      options
      |> Enum.map(fn option -> {option.text, 0.0} end)
      |> Map.new()
    end
  end

  def calculate_percentages(_), do: %{}

  @doc """
  Calculate percentage for a single option given total votes.
  
  ## Examples
  
      iex> VoteService.percentage(42, 100)
      42
      
      iex> VoteService.percentage(0, 0)
      0
  """
  def percentage(votes, total) when total > 0 do
    (votes / total * 100) |> round()
  end

  def percentage(_votes, _total), do: 0
end

