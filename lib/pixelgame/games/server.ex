defmodule Pixelgame.Games.Server do
  use GenServer

  require Logger

  alias Pixelgame.Games.Bot
  alias Pixelgame.Games.TicTacToe
  alias __MODULE__

  alias Pixelgame.Games.Player

  # https://hexdocs.pm/elixir/1.12/Supervisor.html#module-child-specification
  def child_spec(opts) do
    code = Keyword.get(opts, :name, Server)
    # fetch doesn't work for nested
    player = Keyword.fetch!(opts, :player)

    %{
      id: "#{Server}_#{code}",
      start: {Server, :start_link, [code, player]},
      restart: :transient
    }
  end

  def start_link(code, player) do
    case GenServer.start_link(Server, %{code: code, player: player}, name: via_tuple(code)) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        :ignore
    end
  end

  def create_game(%Player{} = player) do
    with {:ok, code} <- generate_code(),
         {:ok, _pid} <-
           DynamicSupervisor.start_child(
             Pixelgame.GameSupervisor,
             {Server, [name: code, player: player]}
           ) do
      Logger.info("CREATING game #{inspect(code)}")
      {:ok, code}
    else
      {:error, reason} -> {:error, "FAILED creating game: #{reason}"}
    end
  end

  def get_state(code) do
    GenServer.call(via_tuple(code), :get_state)
  end

  def join_game(code, %Player{} = player) do
    GenServer.call(via_tuple(code), {:join_game, player})
  end

  def customize_player(code, player_id, updates) do
    GenServer.call(via_tuple(code), {:customize_player, player_id, updates})
  end

  def leave_game(code, player_id) do
    GenServer.call(via_tuple(code), {:leave_game, player_id})
  end

  def ready_player(code, player_id, ready) do
    GenServer.call(via_tuple(code), {:ready_player, player_id, ready})
  end

  def make_move(code, player_id, move) do
    GenServer.call(via_tuple(code), {:make_move, player_id, move})
  end

  def update_settings(code, settings) do
    GenServer.call(via_tuple(code), {:update_settings, settings})
  end

  ###
  ### Server (callbacks)
  ###

  def init(%{code: code, player: player}) do
    {:ok, TicTacToe.new(code, player)}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:join_game, %Player{} = player}, _from, %TicTacToe{} = state) do
    case TicTacToe.join(state, player) do
      # player already joined, no updated state
      :ok ->
        {:reply, :ok, state}

      {:ok, state} ->
        broadcast_game_state(state)
        {:reply, :ok, state}

      {:error, reason} = error ->
        Logger.error("Failed to join game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:customize_player, player_id, updates}, _from, state) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, player} <-
           Player.changeset(player, updates) |> Ecto.Changeset.apply_action(:insert) do
      state = TicTacToe.customize(state, player)
      broadcast_game_state(state)
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to customize game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:leave_game, player_id}, _from, %TicTacToe{} = state) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, state} <- TicTacToe.leave(state, player) do
      case map_size(state.players) do
        0 ->
          {:stop, :normal, :ok, state}

        _ ->
          broadcast_game_state(state)
          {:reply, :ok, state}
      end
    else
      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:ready_player, player_id, ready}, _from, %TicTacToe{} = state) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, state} <- try_ready_and_next(state, player, ready) do
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error(
          "Fail to ready player: #{player_id} in game_#{state.code}: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  def handle_call({:make_move, player_id, move}, _from, %TicTacToe{} = state) do
    with {:ok, state} <- try_move(state, player_id, move) do
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to move in game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:update_settings, settings}, _from, %TicTacToe{} = state) do
    state = TicTacToe.update(state, settings)
    broadcast_game_state(state)
    {:reply, :ok, state}
  end

  def handle_info(:start_game, %TicTacToe{} = state) do
    with {:ok, state} <- TicTacToe.start(state) do
      broadcast_game_state(state)
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.error("Fail to start game: game_#{state.code}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:bot_move, bot_id}, %TicTacToe{} = state) do
    case try_move(state, bot_id, Bot.next_move(state, bot_id)) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to move in game_#{state.code}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:end_turn, %TicTacToe{} = state) do
    state = TicTacToe.next_turn(state) |> TicTacToe.reset_timer()
    broadcast_game_state(state)
    {:noreply, state}
  end

  def handle_info(:end_for_timeout, %TicTacToe{} = state) do
    Logger.info("game_#{state.code} ended due to timeout")

    alias Phoenix.PubSub
    PubSub.broadcast(Pixelgame.PubSub, "game:#{state.code}", :timeout)

    {:stop, :normal, state}
  end

  defp try_move(%TicTacToe{} = state, player_id, move) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, state} <- TicTacToe.move(state, player, move) do
      broadcast_game_state(state)
      {:ok, state}
    end
  end

  defp try_ready_and_next(%TicTacToe{} = state, player, ready) when player.ready == ready,
    do: {:ok, state}

  defp try_ready_and_next(%TicTacToe{} = state, player, ready) do
    with {:ok, state} <- TicTacToe.ready(state, player, ready),
         {:ok, state} <- try_next(state) do
      broadcast_game_state(state)
      {:ok, state}
    end
  end

  defp try_next(%TicTacToe{status: :done} = state) do
    case Map.values(state.players) |> Enum.all?(fn player -> !player.ready end) do
      true -> {:ok, TicTacToe.reset(state)}
      false -> {:ok, state}
    end
  end

  defp try_next(%TicTacToe{status: :waiting} = state) do
    if map_size(state.players) >= state.min_players &&
         Map.values(state.players) |> Enum.all?(fn player -> player.ready end) do
      Process.send_after(self(), :start_game, 4000)
    end

    {:ok, state}
  end

  def broadcast_game_state(%TicTacToe{} = state) do
    alias Phoenix.PubSub
    PubSub.broadcast(Pixelgame.PubSub, "game:#{state.code}", {:game_state, state})
  end

  def generate_code(tries \\ 0)

  def generate_code(tries) when tries > 5 do
    {:error, "Couldn't generate unique code. Try again later."}
  end

  def generate_code(tries) do
    code = get_random_code()

    if server_exists?(code) do
      generate_code(tries + 1)
    else
      {:ok, code}
    end
  end

  defp get_random_code() do
    range = ?A..?Z
    1..4 |> Enum.map(fn _ -> Enum.random(range) end) |> List.to_string()
  end

  def ensure_server_exists(code) do
    case server_exists?(code) do
      false -> {:error, "#{code} is not a valid code."}
      true -> :ok
    end
  end

  def server_exists?(code) do
    case Registry.lookup(Pixelgame.GameRegistry, code) do
      [] -> false
      [{pid, _} | _] when is_pid(pid) -> true
    end
  end

  defp via_tuple(code) do
    {:via, Registry, {Pixelgame.GameRegistry, code}}
  end
end
