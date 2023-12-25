defmodule PixelgameWeb.GameLive do
  alias Pixelgame.Games
  use PixelgameWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:code, "****")}
  end

  @salt Application.compile_env(:pixelgame, PixelgameWeb.Endpoint)[:live_view][:signing_salt]

  def handle_params(params, _uri, socket) do
    IO.inspect(params, label: "handle_params")

    case connected?(socket) do
      true ->
        case params do
          %{"new" => _} ->
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

          %{"code" => code} ->
            {:noreply,
             socket
             |> assign(:code, code)
             |> push_event("store", %{
               key: "code",
               data: Phoenix.Token.encrypt(PixelgameWeb.Endpoint, @salt, code)
             })}

          _ ->
            {:noreply, socket |> push_event("restore", %{key: "code", event: "restoreCode"})}
        end

      false ->
        {:noreply, socket}
    end
  end

  def handle_event("restoreCode", token_data, socket) when is_binary(token_data) do
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

  # no code to restore
  def handle_event("restoreCode", _, socket) do
    {:noreply, socket |> redirect(to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <div id="game_container" phx-hook="GameCodeStore">
      <%= @code != nil && @code %>
    </div>
    """
  end
end
