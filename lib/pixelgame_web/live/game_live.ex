defmodule PixelgameWeb.GameLive do
  alias Pixelgame.Games
  use PixelgameWeb, :live_view

  def mount(params, session, socket) do
    case connected?(socket) do
      true -> connected_mount(params, session, socket)
      false -> {:ok, socket |> assign(:code, "****")}
    end
  end

  def connected_mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:code, "restoring")
     |> push_event("restore", %{key: "code", event: "restoreCode"})}
  end

  @salt Application.compile_env(:pixelgame, PixelgameWeb.Endpoint)[:live_view][:signing_salt]

  def handle_event("restoreCode", token_data, socket) when is_binary(token_data) do
    IO.inspect("restore A")
    # 3600 = 1 hour, abitrary but should match rejoin time limit
    socket =
      case Phoenix.Token.decrypt(PixelgameWeb.Endpoint, @salt, token_data, max_age: 3600) do
        {:ok, data} ->
          socket |> assign(:code, data)

        {:error, reason} ->
          socket |> put_flash(:error, reason) |> push_event("clear", %{key: "code"})
      end

    {:noreply, socket}
  end

  def handle_event("restoreCode", td, socket) do
    IO.inspect("restore B #{inspect(td)}")

    with {:ok, player} <- Games.Player.create(%{name: "test name", user_id: "123451"}),
         {:ok, code} <- Games.Server.create_game(player) do
      {:noreply,
       socket
       |> assign(:code, code)
       |> push_event("store", %{
         key: "code",
         data: Phoenix.Token.encrypt(PixelgameWeb.Endpoint, @salt, code)
       })}
    else
      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, reason)}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="game_container" phx-hook="LocalStateStore">
      <%= @code != nil && @code %>
    </div>
    """
  end
end
