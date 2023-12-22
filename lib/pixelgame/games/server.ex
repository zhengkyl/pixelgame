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

  def start_or_join(code, %Player{} = player) do
    case DynamicSupervisor.start_child(
           Pixelgame.GameSupervisor,
           {Server, [name: code, player: player]}
         ) do
      {:ok, _pid} ->
        Logger.info("STARTING game server #{inspect(code)}")
        {:ok, :started}

      :ignore ->
        Logger.info("JOINING existing game server #{inspect(code)}")
        nil

        case GenServer.call(via_tuple(code), {:join_game, player}) do
          :ok -> {:ok, :joined}
          {:error, _reason} = error -> error
        end
    end
  end

  ###
  ### Server (callbacks)
  ###

  def init(%{code: code, player: player}) do
    {:ok, TicTacToe.new(code, player)}
  end

  def handle_call({:join_game, %Player{} = player}, _from, %TicTacToe{} = state) do
    with {:ok, state} <- TicTacToe.join(state, player) do
      broadcast_game_state(state)
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to join game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  def handle_call({:ready, player_id}, _from, %TicTacToe{} = state) do
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

  def handle_call({:move, player_id, square}, _from, %TicTacToe{} = state) do
    with {:ok, player} <- TicTacToe.find_player(state, player_id),
         {:ok, state} <- TicTacToe.move(state, player, square) do
      broadcast_game_state(state)
      {:reply, :ok, state}
    else
      {:error, reason} = error ->
        Logger.error("Failed to move in game_#{state.code}: #{inspect(reason)}")
        {:reply, error, state}
    end
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
      {:ok, code}
    else
      generate_code(tries + 1)
    end
  end

  defp get_random_code() do
    range = ?A..?Z
    1..4 |> Enum.map(fn _ -> Enum.random(range) end) |> List.to_string()
  end

  def server_exists?(code) do
    case Registry.lookup(GameRegistry, code) do
      [] -> false
      [{pid, _} | _] when is_pid(pid) -> true
    end
  end

  defp via_tuple(code) do
    {:via, Registry, {Pixelgame.GameRegistry, code}}
  end
end
