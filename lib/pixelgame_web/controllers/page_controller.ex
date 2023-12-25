defmodule PixelgameWeb.PageController do
  use PixelgameWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false, values: %{"code" => ""})
  end

  def create(conn, params) do
    IO.inspect(params)
    {:ok, player} = Pixelgame.Games.Player.create(%{name: "Bob", user_id: "123"})
    Pixelgame.Games.Server.join_game(params["code"], player)
    conn |> redirect(to: ~p"/game?code=#{params["code"]}")
  end
end
