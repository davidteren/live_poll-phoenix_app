defmodule LivePollWeb.PageController do
  use LivePollWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
