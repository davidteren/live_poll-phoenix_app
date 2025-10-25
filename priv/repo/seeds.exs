# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     LivePoll.Repo.insert!(%LivePoll.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias LivePoll.Polls

# Use the Polls context to add languages with proper validation
# This will prevent duplicates and normalize the language names
{:ok, _} = Polls.add_language("Elixir")
{:ok, _} = Polls.add_language("Ruby")
{:ok, _} = Polls.add_language("Python")
{:ok, _} = Polls.add_language("JavaScript")

IO.puts("Seeded 4 programming languages successfully!")
