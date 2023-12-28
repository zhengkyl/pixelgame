defmodule PixelgameWeb.PageController do
  use PixelgameWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false, values: %{"code" => ""})
  end

  def create(conn, params) do
    case Pixelgame.Games.Server.server_exists?(params["code"]) do
      false -> conn |> put_flash(:error, "Lobby does not exist") |> redirect(to: ~p"/")
      true -> conn |> redirect(to: ~p"/game?code=#{params["code"]}")
    end
  end
end
