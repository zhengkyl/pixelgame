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
       settings: to_form(%{"board_size" => 3, "win_length" => 3, "preset" => "custom"})
     )
     |> setup_game_assigns(%TicTacToe{})
     |> setup_settings(%TicTacToe{})}
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
    game = Pixelgame.Games.Server.get_state(client_info.code)

    socket
    |> assign(client_info: client_info)
    |> setup_game_assigns(game)
    |> setup_settings(game)
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

  def handle_event("move", params, socket) do
    %{game: game, client_info: %{code: code, id: id}} = socket.assigns
    player = game.players[id]

    with :ok <- Games.TicTacToe.verify_status(game, [:playing]),
         :ok <- Games.TicTacToe.verify_player_turn(game, player),
         :ok <-
           Games.Server.make_move(
             code,
             id,
             {String.to_integer(params["row"]), String.to_integer(params["col"])}
           ) do
      {:noreply, socket}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(:timeout, socket) do
    {:noreply, socket |> put_flash(:error, "Game timed out.") |> redirect(to: ~p"/")}
  end

  def handle_info({:game_state, %TicTacToe{} = state}, socket) do
    {:noreply,
     socket
     |> setup_timer(state)
     |> setup_settings(state)
     |> setup_game_assigns(state)
     |> endgame_fix(state)}
  end

  def endgame_fix(socket, %TicTacToe{} = state) do
    %{game: game} = socket.assigns

    if game.status == :done && state.status == :done &&
         map_size(game.players) != map_size(state.players) do
      socket
      |> assign(game: %TicTacToe{state | pieces: game.pieces})
    else
      socket
    end
  end

  def setup_game_assigns(socket, %TicTacToe{} = state) do
    sorted_players = Map.values(state.players) |> Enum.sort(fn p1, p2 -> p1.order < p2.order end)

    current_player =
      (map_size(state.players) > 0 &&
         Enum.at(sorted_players, rem(state.turn, map_size(state.players)))) || nil

    game_result =
      case(state.status) do
        :playing ->
          case current_player do
            %Games.Player{id: id} when id == socket.assigns.client_info.id ->
              "YOUR TURN"

            player ->
              (player.name |> String.upcase()) <> "'S TURN"
          end

        :done ->
          case current_player do
            _ when not is_map_key(state.pieces, :win) -> "DRAW"
            _ -> (current_player.name |> String.upcase()) <> " WINS"
          end

        :waiting ->
          nil
      end

    socket
    |> assign(
      game: state,
      ready_count: Map.values(state.players) |> Enum.count(fn player -> player.ready end),
      sorted_players: sorted_players,
      current_player: current_player,
      game_result: game_result
    )
  end

  def setup_timer(socket, %TicTacToe{} = state) do
    %{game: game, client_info: client_info, current_player: current_player} = socket.assigns

    case state.status do
      :playing when game.status == :playing and state.turn != game.turn ->
        socket |> push_event("startTimer", %{s: 60})

      :playing when game.status == :waiting ->
        socket |> push_event("startTimer", %{s: 60})

      :done when game.status == :playing ->
        info =
          case current_player do
            _ when not is_map_key(state.pieces, :win) ->
              %{msg: "DRAW", win: false}

            %Games.Player{id: id} when id == client_info.id ->
              %{msg: "VICTORY", win: true}

            %Games.Player{} ->
              %{msg: "DEFEAT", win: false}
          end

        socket
        |> push_event("stopTimer", %{})
        |> push_event("announce", info)

      _ ->
        socket
    end
  end

  def setup_settings(socket, %TicTacToe{} = state) do
    preset =
      case state.win_length do
        3 when state.board_size == 3 -> :tictactoe
        4 when state.board_size == 7 -> :connect4
        5 when state.board_size == 15 -> :gomoku
        _ -> :custom
      end

    socket |> assign(:preset, preset)
  end

  def render(assigns) do
    ~H"""
    <div id="game_container" phx-hook="GameHooks">
      <div :if={@client_info.id && @game.status == :waiting} class="flex flex-col gap-4">
        <div
          :if={
            map_size(@game.players) >= @game.min_players &&
              @ready_count == map_size(@game.players)
          }
          class="bg-black/80 fixed inset-0 transition-opacity z-10 font-bold"
        >
          <div class="mt-[15svh] h-[min(100vw,50svh)] flex justify-center items-center">
            <div id="countdown" phx-hook="Countdown"></div>
          </div>
          <.button phx-click="toggle_ready" class="block m-auto">
            Cancel
          </.button>
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
        <ul class="flex flex-wrap gap-4">
          <li
            :for={player <- @sorted_players}
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
        <div class="bg-zinc-900 border p-4 rounded-lg">
          <.form for={@settings} class="flex flex-col gap-4" phx-change="change_settings">
            <div>
              <div class="block font-black text-xl mb-1 text-center">Presets</div>
              <div class="flex flex-wrap gap-2 justify-center">
                <.enum_button hue={if @preset == :custom, do: "amber"}>
                  <.icon name="hero-cog-6-tooth" class="m-auto" />
                  <div>Custom</div>
                </.enum_button>
                <.enum_button hue={if @preset == :tictactoe, do: "amber"}>
                  <.icon name="hero-hashtag" class="m-auto" />
                  <div>Tic-tac-toe</div>
                </.enum_button>
                <.enum_button hue={if @preset == :connect4, do: "amber"}>
                  <.icon name="hero-table-cells" class="m-auto" />
                  <div>Connect 4</div>
                </.enum_button>
                <.enum_button hue={if @preset == :gomoku, do: "amber"}>
                  <.icon name="hero-currency-yen" class="m-auto" />
                  <div>Gomoku</div>
                </.enum_button>
              </div>
            </div>
            <.input
              field={@settings["board_size"]}
              type="number"
              label="Board size"
              min="3"
              max="20"
              step="1"
            />
            <.input
              field={@settings["win_length"]}
              type="number"
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
            phx-click="toggle_ready"
          >
            <%= (@game.players[@client_info.id].ready &&
                   "Waiting (#{@ready_count}/#{map_size(@game.players)})...") ||
              "Ready up (#{@ready_count}/#{map_size(@game.players)})" %>
          </.button>
        </div>
      </div>
      <div :if={@game.status !== :waiting} class="flex flex-col gap-4">
        <div
          id="announcement"
          class="hidden bg-black/80 fixed left-0 right-0 top-1/3 p-16 transition-opacity ease-in z-10 text-5xl font-black text-center duration-[3s]"
          phx-hook="Announcement"
        >
        </div>
        <div
          id="game_header"
          class="flex justify-between"
          phx-update={(@game.status == :done && "ignore") || "replace"}
        >
          <div class="flex-1">
            <span class="text-xl">Turn </span>
            <span class="text-xl font-black">
              <%= @game.turn + 1 %>
            </span>
          </div>
          <div class="text-xl font-black [flex:2] text-center min-h-[3.5rem]">
            <%= @game_result %>
          </div>

          <div id="timer" class="text-xl flex-1 text-right" phx-hook="Timer"></div>
        </div>
        <ul class="flex flex-wrap gap-4">
          <li
            :for={player <- @sorted_players}
            class={[
              "rounded p-2 flex-1 flex flex-col justify-between",
              player.id == @client_info.id && "outline",
              (Games.TicTacToe.is_player_turn?(@game, player) && "bg-fuchsia-900") || "bg-zinc-700"
            ]}
          >
            <span class="font-bold">
              <%= player.name %>
            </span>
          </li>
        </ul>
        <div
          id="game_grid"
          class={"grid grid-cols-#{@game.board_size} gap-2"}
          phx-update={(@game.status == :done && "ignore") || "replace"}
        >
          <%= for x <- 1..@game.board_size do %>
            <%= for y <- 1..@game.board_size do %>
              <div
                class={[
                  "border rounded-lg aspect-square",
                  "cursor-pointer",
                  (Map.has_key?(@game.pieces, :win) && MapSet.member?(@game.pieces[:win], {x, y}) &&
                     "bg-amber-600 hover:bg-amber-500") || "hover:bg-white/10"
                ]}
                phx-click="move"
                phx-value-row={x}
                phx-value-col={y}
              >
                <%= for id <- Map.keys(@game.players) do %>
                  <%= if MapSet.member?(@game.pieces[id], {x, y}) do %>
                    <%= case @game.players[id].shape do %>
                      <% :cross -> %>
                        <.cross stroke={@game.players[id].color} />
                      <% :circle -> %>
                        <.circle stroke={@game.players[id].color} />
                      <% :square -> %>
                        <.square stroke={@game.players[id].color} />
                      <% :triangle -> %>
                        <.triangle stroke={@game.players[id].color} />
                    <% end %>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
        <div :if={@game.status == :done} class="flex gap-4">
          <.button phx-click="leave">
            Leave
          </.button>
          <.button
            hue={(@game.players[@client_info.id].ready && "green") || "yellow"}
            class="flex-1"
            phx-click="toggle_ready"
          >
            <%= (!@game.players[@client_info.id].ready &&
                   "Waiting (#{map_size(@game.players) - @ready_count}/#{map_size(@game.players)})...") ||
              "Replay (#{map_size(@game.players) - @ready_count}/#{map_size(@game.players)})" %>
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
