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

alias LivePoll.Repo
alias LivePoll.Poll.Option

Repo.insert!(%Option{text: "Elixir", votes: 0})
Repo.insert!(%Option{text: "Ruby", votes: 0})
Repo.insert!(%Option{text: "Python", votes: 0})
Repo.insert!(%Option{text: "JavaScript", votes: 0})
