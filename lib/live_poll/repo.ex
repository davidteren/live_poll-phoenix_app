defmodule LivePoll.Repo do
  use Ecto.Repo,
    otp_app: :live_poll,
    adapter: Ecto.Adapters.Postgres
end
