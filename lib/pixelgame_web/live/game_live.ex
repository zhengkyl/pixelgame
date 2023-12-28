defmodule PixelgameWeb.GameLive do
  alias Phoenix.PubSub
  alias Pixelgame.Games.TicTacToe
  alias Pixelgame.Games
  use PixelgameWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(code: "****", game: nil)}
  end

  @salt Application.compile_env(:pixelgame, PixelgameWeb.Endpoint)[:live_view][:signing_salt]

  def handle_params(params, _uri, socket) do
    socket =
      case connected?(socket) do
        false ->
          socket

        true ->
          # IO.inspect(socket.assigns)

          player_info =
            case socket.assigns do
              %{current_user: nil} ->
                %{
                  name: Pixelgame.NameGenerator.generate_name(),
                  user_id: -:rand.uniform(1_000_000_000)
                }

              %{current_user: user} ->
                %{name: user.name, user_id: user.id}
            end

          code =
            case params do
              %{"new" => _} ->
                with {:ok, player} <- Games.Player.create(player_info),
                     {:ok, code} <- Games.Server.create_game(player) do
                  {:ok, code}
                else
                  {:error, reason} -> {:error, reason}
                end

              %{"code" => code} ->
                with :ok <- Games.Server.ensure_server_exists(code),
                     {:ok, player} <- Games.Player.create(player_info),
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
              socket |> setup_socket(code)
          end
      end

    {:noreply, socket}
  end

  def handle_event("restoreCode", token_data, socket) when is_binary(token_data) do
    # 3600 = 1 hour, abitrary but should match rejoin time limit
    with {:ok, code} <-
           Phoenix.Token.decrypt(PixelgameWeb.Endpoint, @salt, token_data, max_age: 3600),
         :ok <- Games.Server.ensure_server_exists(code) do
      {:noreply, socket |> setup_socket(code)}
    else
      {:error, _} ->
        handle_event("restoreCode", nil, socket |> push_event("clear", %{key: "code"}))
    end
  end

  # no code to restore
  def handle_event("restoreCode", _, socket) do
    {:noreply, socket |> put_flash(:error, "Not currently in game.") |> redirect(to: ~p"/")}
  end

  def handle_info(:timeout, socket) do
    {:noreply, socket |> put_flash(:error, "Game timed out.") |> redirect(to: ~p"/")}
  end

  def handle_info({:game_state, %TicTacToe{} = state}, socket) do
    {:noreply, socket |> assign(:game, state)}
  end

  defp setup_socket(socket, code) do
    PubSub.subscribe(Pixelgame.PubSub, "game:#{code}")

    socket
    |> assign(code: code, game: Pixelgame.Games.Server.get_state(code))
    |> push_event("store", %{
      key: "code",
      data: Phoenix.Token.encrypt(PixelgameWeb.Endpoint, @salt, code)
    })
  end

  def render(assigns) do
    ~H"""
    <div id="game_container" phx-hook="GameCodeStore">
      <%= @code %>
      <%= if @game == nil do %>
        <div>
          Game loading...
        </div>
      <% else %>
        <ul>
          <li :for={player <- Map.values(@game.players)}>
            <%= player.name %>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end
end
