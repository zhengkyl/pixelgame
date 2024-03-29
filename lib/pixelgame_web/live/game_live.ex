defmodule PixelgameWeb.GameLive do
  alias Phoenix.PubSub
  alias Pixelgame.Games.TicTacToe
  alias Pixelgame.Games.Player
  alias Pixelgame.Games
  use PixelgameWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(client_info: %{code: "****", id: nil})
     |> setup_game_assigns(%TicTacToe{})}
  end

  defp salt() do
    Application.fetch_env!(:pixelgame, PixelgameWeb.Endpoint)[:live_view][:signing_salt]
  end

  @store_key "client_info"

  def handle_params(params, _uri, socket) do
    socket =
      case connected?(socket) do
        false ->
          socket

        true ->
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
    game = Pixelgame.Games.Server.get_state(client_info.code)

    case Map.has_key?(game.players, client_info.id) do
      false ->
        socket |> redirect(to: ~p"/")

      true ->
        PubSub.subscribe(Pixelgame.PubSub, "game:#{client_info.code}")

        socket
        |> assign(client_info: client_info)
        |> setup_game_assigns(game)
        |> push_event("set", %{
          key: @store_key,
          data: Phoenix.Token.encrypt(PixelgameWeb.Endpoint, salt(), client_info)
        })
        # remove query params w/o redirect
        |> push_event("replaceHistory", %{url: "game"})
    end
  end

  def handle_event("restoreClientInfo", token_data, socket) when is_binary(token_data) do
    # 3600 = 1 hour, abitrary but should match rejoin time limit
    with {:ok, client_info} <-
           Phoenix.Token.decrypt(PixelgameWeb.Endpoint, salt(), token_data, max_age: 3600),
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

  def handle_event("change_settings", %{"settings" => params}, socket) do
    form =
      socket.assigns.settings.data
      |> Games.Settings.changeset(params)
      |> Map.put(:action, :insert)
      |> to_form()

    {:noreply, assign(socket, settings: form)}
  end

  def handle_event("save_settings", %{"settings" => params}, socket) do
    %{client_info: %{code: code}, settings: settings} = socket.assigns

    case settings.data
         |> Games.Settings.changeset(params)
         |> Ecto.Changeset.apply_action(:insert) do
      {:ok, settings} ->
        Games.Server.update_settings(code, settings)

      _ ->
        nil
    end

    {:noreply, socket}
  end

  def handle_event("customize_player", %{"shape" => shape}, socket) do
    %{client_info: %{code: code, id: id}} = socket.assigns
    Games.Server.customize_player(code, id, %{shape: String.to_existing_atom(shape)})
    {:noreply, socket}
  end

  def handle_event("customize_player", %{"color" => color}, socket) do
    %{client_info: %{code: code, id: id}} = socket.assigns
    Games.Server.customize_player(code, id, %{color: color})
    {:noreply, socket}
  end

  def handle_event("add_bot", _params, socket) do
    %{client_info: %{code: code}} = socket.assigns

    with {:ok, player} <-
           Games.Player.create(%{
             name: "(bot) " <> Pixelgame.NameGenerator.generate_name(),
             id: -:rand.uniform(1_000_000_000),
             bot: true
           }),
         :ok <- Games.Server.join_game(code, player) do
      {:noreply, socket}
    else
      {:error, reason} -> {:noreply, socket |> put_flash(:error, reason)}
    end
  end

  def handle_event("remove_bot", %{"id" => id}, socket) do
    %{client_info: %{code: code}, game: game} = socket.assigns

    bot_id = String.to_integer(id)

    with {:ok, bot} <- Map.fetch(game.players, bot_id),
         true <- bot.bot,
         :ok <- Games.Server.leave_game(code, bot_id) do
      {:noreply, socket}
    else
      x ->
        IO.inspect(x)
        {:noreply, socket |> put_flash(:error, "Failed to kick bot.")}
    end
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

    form =
      to_form(
        %Games.Settings{
          board_size: state.board_size,
          win_length: state.win_length,
          preset:
            Games.Settings.preset(%{
              board_size: state.board_size,
              win_length: state.win_length
            })
        }
        |> Games.Settings.changeset(%{})
      )

    socket
    |> assign(
      game: state,
      ready_count: Map.values(state.players) |> Enum.count(fn player -> player.ready end),
      sorted_players: sorted_players,
      current_player: current_player,
      game_result: game_result,
      settings: form
    )
  end

  def setup_timer(socket, %TicTacToe{} = state) do
    %{game: game, client_info: client_info, current_player: current_player} = socket.assigns

    case state.status do
      :playing when game.status == :playing and state.turn != game.turn ->
        socket |> push_event("startTimer", %{s: 30})

      :playing when game.status == :waiting ->
        socket |> push_event("startTimer", %{s: 30})

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
        <div class="grid grid-cols-3 justify-items-center">
          <div class="text-sm">Players</div>
          <div class="text-sm">Code</div>
          <button
            id="copy_link_button"
            class="justify-self-end self-center row-span-2 inline-flex items-center gap-1 font-bold rounded-lg p-2 bg-zinc-800 hover:bg-zinc-700 active:text-white/80 border"
            phx-update="ignore"
            phx-click={
              JS.dispatch("pixelgame:clipcopy",
                detail: %{text: "#{PixelgameWeb.Endpoint.url()}/game?code=#{@client_info.code}"}
              )
            }
          >
            Copy link <.icon name="hero-link-mini" />
          </button>
          <div class="text-2xl font-black">
            <%= map_size(@game.players) %> / <%= @game.max_players %>
          </div>
          <div class="text-2xl font-black">
            <%= @client_info.code %>
          </div>
        </div>
        <div>
          <.modal id="settings_modal">
            <.form
              for={@settings}
              class="flex flex-col gap-4"
              phx-change="change_settings"
              phx-submit="save_settings"
            >
              <div>
                <div class="font-black text-xl mb-1">Presets</div>
                <div class="flex flex-wrap gap-2">
                  <.enum_button
                    hue={
                      if Map.get(@settings.source.changes, :preset, @settings.data.preset) ==
                           :tictactoe,
                         do: "amber"
                    }
                    phx-click={
                      JS.push("change_settings", value: %{settings: %{board_size: 3, win_length: 3}})
                    }
                  >
                    <.icon name="hero-hashtag" class="m-auto" />
                    <div>Tic-tac-toe</div>
                  </.enum_button>
                  <.enum_button
                    hue={
                      if Map.get(@settings.source.changes, :preset, @settings.data.preset) ==
                           :connect4,
                         do: "amber"
                    }
                    phx-click={
                      JS.push("change_settings", value: %{settings: %{board_size: 7, win_length: 4}})
                    }
                  >
                    <.icon name="hero-table-cells" class="m-auto" />
                    <div>Connect 4</div>
                  </.enum_button>
                  <.enum_button
                    hue={
                      if Map.get(@settings.source.changes, :preset, @settings.data.preset) ==
                           :gomoku,
                         do: "amber"
                    }
                    phx-click={
                      JS.push("change_settings", value: %{settings: %{board_size: 15, win_length: 5}})
                    }
                  >
                    <.icon name="hero-currency-yen" class="m-auto" />
                    <div>Gomoku</div>
                  </.enum_button>
                </div>
              </div>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <div class="text-xl font-black">Board size</div>
                  <div>Between 3 and 20 (inclusive)</div>
                </div>
                <.input field={@settings[:board_size]} type="number" min="3" max="20" step="1" />
                <div>
                  <div class="text-xl font-black">Win length</div>
                  <div>Between 3 and board size (inclusive)</div>
                </div>
                <.input field={@settings[:win_length]} type="number" min="3" max="20" step="1" />
              </div>
              <.button
                type="submit"
                hue="green"
                disabled={@settings.source.changes == %{} || !@settings.source.valid?}
              >
                Apply
              </.button>
            </.form>
          </.modal>
        </div>
        <div class="flex justify-between">
          <div class="font-semibold px-4 py-2 gap-x-4 grid grid-cols-4 justify-items-center items-center border rounded-lg bg-zinc-800">
            <div class="text-center">Board size</div>
            <div class="text-center">Win length</div>
            <div class="text-center">Min players</div>
            <div class="text-center">Max players</div>
            <div class="font-black text-xl"><%= @game.board_size %></div>
            <div class="font-black text-xl"><%= @game.win_length %></div>
            <div class="font-black text-xl"><%= @game.min_players %></div>
            <div class="font-black text-xl"><%= @game.max_players %></div>
          </div>
          <.enum_button phx-click={show_modal("settings_modal")}>
            <div>Edit</div>
            <.icon name="hero-cog-6-tooth" class="m-auto" />
          </.enum_button>
        </div>

        <div class="flex flex-wrap justify-center items-start gap-4">
          <div class="border rounded-lg flex flex-col justify-between gap-2 p-4 min-w-[240px] max-w-xs [flex:2]">
            <div>
              <div class="font-bold">
                <%= @game.players[@client_info.id].name %>
              </div>
              <div class={[
                "text-sm font-black",
                if(@game.players[@client_info.id].ready, do: "text-green-400", else: "text-yellow-400")
              ]}>
                <%= if @game.players[@client_info.id].ready, do: "READY", else: "NOT READY" %>
              </div>
            </div>
            <.player_tile player={@game.players[@client_info.id]} />
            <div class="grid grid-cols-4 gap-2">
              <%= for shapeP <- [%Player{shape: :cross}, %Player{shape: :circle}, %Player{shape: :square}, %Player{shape: :triangle}] do %>
                <.button
                  bare
                  class={
                    (@game.players[@client_info.id].shape == shapeP.shape &&
                       "outline-amber-400 outline p-2 mb-2") ||
                      "p-2 mb-2"
                  }
                  phx-click="customize_player"
                  phx-value-shape={shapeP.shape}
                >
                  <.player_tile player={shapeP} class="w-full" />
                </.button>
              <% end %>
              <%= for color <- Games.Player.colors() ++ ["none"] do %>
                <.button
                  bare
                  class={
                    (@game.players[@client_info.id].color == color && "outline-amber-400 outline p-2") ||
                      "p-2"
                  }
                  phx-click="customize_player"
                  phx-value-color={color}
                >
                  <.box
                    class="w-full"
                    fill={color}
                    stroke={if color == "none", do: "#fff", else: color}
                  />
                </.button>
              <% end %>
            </div>
          </div>
          <div class="[flex:3] min-w-[200px] flex flex-col gap-4">
            <div
              :for={player <- @sorted_players}
              :if={player.id != @client_info.id}
              class={[
                "relative rounded-lg p-4 flex justify-between border",
                player.id == @client_info.id && "outline"
              ]}
            >
              <div>
                <div class="font-bold">
                  <%= player.name %>
                </div>
                <div class={[
                  "text-sm font-black",
                  if(player.ready, do: "text-green-400", else: "text-yellow-400")
                ]}>
                  <%= if player.ready, do: "READY", else: "NOT READY" %>
                </div>
                <.button
                  :if={player.bot}
                  bare
                  class="absolute top-0 right-0 translate-x-1/3 -translate-y-1/3"
                  phx-click="remove_bot"
                  phx-value-id={player.id}
                >
                  <.icon name="hero-x-mark-mini" class="text-red-400 h-6 w-6 block" />
                </.button>
              </div>
              <.player_tile player={player} class="w-11" />
            </div>
            <.button :if={map_size(@game.players) < @game.max_players} phx-click="add_bot">
              Add bot
            </.button>
            <div
              :if={map_size(@game.players) < @game.min_players}
              class="rounded-lg p-4 border text-center text-bold"
            >
              <div class="font-black">Not enough players</div>
              Add players to start a game
            </div>
          </div>
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
          class="hidden bg-black/80 fixed left-0 right-0 top-1/3 p-16 transition-opacity ease-in z-20 text-5xl font-black text-center duration-[3s] animate-pop"
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
        <div class="relative">
          <svg
            :if={Map.has_key?(@game.pieces, :win)}
            xmlns="http://www.w3.org/2000/svg"
            viewBox={"0 0 #{@game.board_size} #{@game.board_size}"}
            class="absolute animate-draw z-10"
          >
            <path
              d={"M #{@game.pieces[:win] |>MapSet.to_list() |> List.first() |> then(fn {y, x} ->
                  "#{x - 0.5} #{y - 0.5}"
                end)} #{@game.pieces[:win] |> MapSet.to_list() |> List.last() |> then(fn {y, x} ->
                  "#{x - 0.5} #{y - 0.5}"
                end)}"}
              style="stroke-width:0.4;stroke-linecap:round"
              class="stroke-brand"
            />
          </svg>
          <div
            id="game_grid"
            class={"grid grid-cols-#{@game.board_size} gap-1"}
            phx-update={(@game.status == :done && "ignore") || "replace"}
          >
            <%= for x <- 1..@game.board_size do %>
              <%= for y <- 1..@game.board_size do %>
                <div
                  class={[
                    "border rounded aspect-square",
                    "cursor-pointer",
                    Map.has_key?(@game.pieces, :win) && MapSet.member?(@game.pieces[:win], {x, y}) &&
                      "outline outline-6 outline-amber-500"
                  ]}
                  phx-click="move"
                  phx-value-row={x}
                  phx-value-col={y}
                >
                  <%= case Enum.find(@game.players, fn {id, _} -> MapSet.member?(@game.pieces[id], {x, y}) end) do %>
                    <% {_, player} -> %>
                      <%!-- Remove class b/c this rerenders for some unknown reason --%>
                      <.player_tile
                        player={player}
                        id={"game_tile_#{x}_#{y}"}
                        phx-hook="GameTile"
                        class={[
                          @game.status == :playing && "animate-pop",
                          Map.has_key?(@game.pieces, :win) &&
                            MapSet.member?(@game.pieces[:win], {x, y}) &&
                            "[--pop-index:#{MapSet.to_list(@game.pieces[:win]) |> Enum.find_index(&(&1 == {x, y}))}] animate-delayedPop"
                        ]}
                      />
                    <% nil -> %>
                      <.player_tile
                        player={@game.players[@client_info.id]}
                        class="opacity-0 hover:opacity-10 transition-opacity"
                      />
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
          <ul class="lg:absolute lg:ml-4 lg:mt-0 mt-4 col-span-3 top-0 left-[100%] flex flex-col gap-2">
            <li
              :for={
                player <-
                  @sorted_players
                  |> Enum.split(@game.players[@client_info.id].order)
                  |> then(fn {head, tail} -> tail ++ head end)
              }
              class={[
                "border rounded p-2 flex items-center justify-between gap-2 [text-wrap:nowrap]",
                player.id == @client_info.id &&
                  "bg-amber-600 border-amber-600 mb-4",
                TicTacToe.is_player_turn?(@game, player) && "outline"
              ]}
            >
              <div class="font-bold flex-1">
                <%= player.name %>
              </div>
              <.player_tile player={player} class="w-8" />
            </li>
          </ul>
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
