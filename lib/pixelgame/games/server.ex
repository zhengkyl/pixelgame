defmodule Pixelgame.Games.Server do
  use GenServer

  require Logger

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

  def join_game(code, %Player{} = player) do
    GenServer.call(via_tuple(code), {:join_game, player})
  end

  def ready_player(code, player_id) do
    GenServer.call(via_tuple(code), {:ready_player, player_id})
  end

  def start_game(code) do
    GenServer.call(via_tuple(code), :start_game)
  end

  def restart_game(code) do
    GenServer.call(via_tuple(code), :restart_game)
  end

  def make_move(code, player_id, move) do
    GenServer.call(via_tuple(code), {:make_move, player_id, move})
  end

  ###
  ### Server (callbacks)
  ###

  def init(%{code: code, player: player}) do
    {:ok, TicTacToe.new(code, player)}
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

  def handle_call({:ready_player, player_id}, _from, %TicTacToe{} = state) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, state} <- TicTacToe.ready(state, player) do
      broadcast_game_state(state)
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error(
          "Fail to ready player: #{player_id} in game_#{state.code}: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  def handle_call(:start_game, _from, %TicTacToe{} = state) do
    with {:ok, state} <- TicTacToe.start(state) do
      broadcast_game_state(state)
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Fail to start game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:make_move, player_id, move}, _from, %TicTacToe{} = state) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, state} <- TicTacToe.move(state, player, move) do
      broadcast_game_state(state)
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to move in game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call(:restart_game, _from, %TicTacToe{} = state) do
    state = TicTacToe.restart(state)
    broadcast_game_state(state)
    {:reply, :ok, state}
  end

  def handle_info(:end_turn, %TicTacToe{} = state) do
    state = TicTacToe.next_turn(state)
    broadcast_game_state(state)
    {:reply, :ok, state}
  end

  def handle_info(:end_for_timeout, %TicTacToe{} = state) do
    Logger.info("game_#{state.code} ended due to timeout")
    {:stop, :normal, state}
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
