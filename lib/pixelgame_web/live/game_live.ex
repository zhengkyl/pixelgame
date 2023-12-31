defmodule PixelgameWeb.GameLive do
  alias Phoenix.PubSub
  alias Pixelgame.Games.TicTacToe
  alias Pixelgame.Games
  use PixelgameWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       client_info: %{code: "****", id: nil},
       game: %TicTacToe{},
       settings: to_form(%{"board_size" => 3, "win_length" => 3, "preset" => "custom"})
     )}
  end

  @salt Application.compile_env(:pixelgame, PixelgameWeb.Endpoint)[:live_view][:signing_salt]
  @store_key "client_info"

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
                  id: -:rand.uniform(1_000_000_000)
                }

              %{current_user: user} ->
                %{name: user.name, id: user.id}
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
              socket |> push_event("get", %{key: @store_key, event: "restoreClientInfo"})

            {:error, reason} ->
              socket |> put_flash(:error, reason) |> redirect(to: ~p"/")

            {:ok, code} ->
              socket |> setup_socket(Map.put(player_info, :code, code))
          end
      end

    {:noreply, socket}
  end

  defp setup_socket(socket, %{} = client_info) do
    PubSub.subscribe(Pixelgame.PubSub, "game:#{client_info.code}")

    socket
    |> assign(
      game: Pixelgame.Games.Server.get_state(client_info.code),
      client_info: client_info
    )
    |> push_event("set", %{
      key: @store_key,
      data: Phoenix.Token.encrypt(PixelgameWeb.Endpoint, @salt, client_info)
    })
    # remove query params w/o redirect
    |> push_event("replaceHistory", %{url: "game"})
  end

  def handle_event("restoreClientInfo", token_data, socket) when is_binary(token_data) do
    # 3600 = 1 hour, abitrary but should match rejoin time limit
    with {:ok, client_info} <-
           Phoenix.Token.decrypt(PixelgameWeb.Endpoint, @salt, token_data, max_age: 3600),
         :ok <- Games.Server.ensure_server_exists(Map.get(client_info, :code)) do
      {:noreply, socket |> setup_socket(client_info)}
    else
      {:error, _} ->
        handle_event("restoreClientInfo", nil, socket |> push_event("clear", %{key: @store_key}))
    end
  end

  # no code to restore
  def handle_event("restoreClientInfo", _, socket) do
    {:noreply, socket |> put_flash(:error, "Not currently in game.") |> redirect(to: ~p"/")}
  end

  def handle_event("change_settings", params, socket) do
    IO.inspect(params)
    {:noreply, socket}
  end

  def handle_event("toggle_ready", _params, socket) do
    %{client_info: %{code: code, id: id}, game: %{players: players}} = socket.assigns

    case Games.Server.ready_player(code, id, !players[id].ready) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:noreply, socket |> put_flash(:error, reason)}
    end

    {:noreply, socket}
  end

  def handle_event("leave", _params, socket) do
    %{code: code, id: id} = socket.assigns.client_info

    case Games.Server.leave_game(code, id) do
      :ok ->
        {:noreply, socket |> redirect(to: ~p"/")}

      _ ->
        {:noreply, socket |> put_flash(:error, "Failed to leave game.")}
    end
  end

  def handle_info(:timeout, socket) do
    {:noreply, socket |> put_flash(:error, "Game timed out.") |> redirect(to: ~p"/")}
  end

  def handle_info({:game_state, %TicTacToe{} = state}, socket) do
    {:noreply, socket |> assign(:game, state)}
  end

  def render(assigns) do
    ~H"""
    <div id="game_container" phx-hook="GameHooks">
      <div :if={@client_info.id && @game.status == :waiting}>
        <div
          :if={
            map_size(@game.players) >= @game.min_players &&
              Map.values(@game.players) |> Enum.all?(fn player -> player.ready end)
          }
          class="bg-black/80 fixed inset-0 transition-opacity z-10 font-bold grid place-content-center"
        >
          <span id="countdown" phx-hook="Countdown" class="mb-[50%]"></span>
        </div>
        <div class="grid grid-cols-2 justify-items-center mx-16">
          <div class="text-sm">Code</div>
          <div class="text-sm">Players</div>
          <div class="text-2xl font-black">
            <%= @client_info.code %>
          </div>
          <div class="text-2xl font-black">
            <%= map_size(@game.players) %> / <%= @game.max_players %>
          </div>
        </div>
        <ul class="flex flex-wrap gap-4 my-8">
          <li
            :for={player <- Map.values(@game.players)}
            class={[
              "rounded p-4 flex-1 flex flex-col justify-between bg-fuchsia-900",
              player.id == @client_info.id && "outline"
            ]}
          >
            <span class="font-bold">
              <%= player.name %>
            </span>
            <div class={[
              "text-sm font-black",
              if(player.ready, do: "text-green-400", else: "text-yellow-400")
            ]}>
              <%= if player.ready, do: "READY", else: "NOT READY" %>
            </div>
          </li>
        </ul>
        <div class="text-3xl font-black text-center">Settings</div>
        <div class="bg-zinc-900 border p-4 rounded-lg mt-4 mb-8">
          <.form for={@settings} class="flex flex-col gap-4" phx-change="change_settings">
            <div>
              <div class="block font-black text-xl mb-1">Presets</div>
              <div class="flex flex-wrap gap-2">
                <.enum_button class="text-center">
                  <.icon name="hero-cog-6-tooth" class="m-auto" />
                  <div>Custom</div>
                </.enum_button>
                <.enum_button>
                  <.icon name="hero-hashtag" class="m-auto" />
                  <div>Tic-tac-toe</div>
                </.enum_button>
                <.enum_button>
                  <.icon name="hero-currency-yen" class="m-auto" />
                  <div>Gomoku</div>
                </.enum_button>
              </div>
            </div>
            <.input
              field={@settings["board_size"]}
              type="range"
              label="Board size"
              min="3"
              max="20"
              step="1"
            />
            <.input
              field={@settings["win_length"]}
              type="range"
              label="Win length"
              min="3"
              max="20"
              step="1"
            />
          </.form>
        </div>

        <div class="flex gap-4">
          <.button phx-click="leave">
            Leave
          </.button>
          <.button
            hue={(!@game.players[@client_info.id].ready && "green") || "yellow"}
            class="flex-1"
            phx-click={JS.push("toggle_ready", value: %{ready: @game.players[@client_info.id].ready})}
          >
            <%= (@game.players[@client_info.id].ready && "Waiting...") || "Ready up" %>
          </.button>
        </div>
      </div>
      <div :if={@game.status == :playing}>
        Playing
      </div>
      <div :if={@game.status == :done}>
        Done
      </div>
    </div>
    """
  end
end
