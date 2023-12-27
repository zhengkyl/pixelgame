defmodule PixelgameWeb.GameLive do
  alias Pixelgame.Games
  use PixelgameWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:code, "****")}
  end

  @salt Application.compile_env(:pixelgame, PixelgameWeb.Endpoint)[:live_view][:signing_salt]

  def handle_params(params, _uri, socket) do
    socket =
      case connected?(socket) do
        false ->
          socket

        true ->
          code =
            case params do
              %{"new" => _} ->
                with {:ok, player} <- Games.Player.create(%{name: "test name", user_id: "151"}),
                     {:ok, code} <- Games.Server.create_game(player) do
                  {:ok, code}
                else
                  {:error, reason} -> {:error, reason}
                end

              %{"code" => code} ->
                with :ok <- Games.Server.ensure_server_exists(code),
                     {:ok, player} <- Games.Player.create(%{name: "test name", user_id: "152"}),
                     :ok <- Games.Server.join_game(code, player) do
                  {:ok, code}
                else
                  {:error, reason} -> {:error, reason}
                end

              _ ->
                nil
            end

          case code do
            nil ->
              socket |> push_event("restore", %{key: "code", event: "restoreCode"})

            {:error, reason} ->
              socket |> put_flash(:error, reason) |> redirect(to: ~p"/")

            {:ok, code} ->
              socket
              |> assign(:code, code)
              |> push_event("store", %{
                key: "code",
                data: Phoenix.Token.encrypt(PixelgameWeb.Endpoint, @salt, code)
              })
          end
      end

    {:noreply, socket}
  end

  def handle_event("restoreCode", token_data, socket) when is_binary(token_data) do
    # 3600 = 1 hour, abitrary but should match rejoin time limit
    case Phoenix.Token.decrypt(PixelgameWeb.Endpoint, @salt, token_data, max_age: 3600) do
      {:ok, data} ->
        {:noreply, socket |> assign(:code, data)}

      {:error, _} ->
        handle_event("restoreCode", nil, socket |> push_event("clear", %{key: "code"}))
    end
  end

  # no code to restore
  def handle_event("restoreCode", _, socket) do
    {:noreply, socket |> put_flash(:error, "Not currently in game.") |> redirect(to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <div id="game_container" phx-hook="GameCodeStore">
      <%= @code != nil && @code %>
    </div>
    """
  end
end
