defmodule Pixelgame.Games.TicTacToe do
  alias Pixelgame.Games.Player
  alias __MODULE__

  defstruct code: nil,
            status: :waiting,
            players: %{},
            min_players: 2,
            max_players: 8,
            turn: 0,
            pieces: %{},
            board_size: 3,
            win_length: 3,
            timer_ref: nil

  @type t :: %TicTacToe{
          code: nil | String.t(),
          status: :waiting | :playing | :done,
          players: %{String.t() => Player},
          min_players: integer(),
          max_players: integer(),
          turn: integer(),
          pieces: %{String.t() => MapSet.t({integer(), integer()})},
          board_size: integer(),
          win_length: integer(),
          timer_ref: nil
        }

  # 5 minute timeout while not :playing
  @timeout_time 1000 * 60 * 50
  # 1 minute turn time while :playing
  @turn_time 1000 * 60

  def new(code, player, board_size \\ 3, win_length \\ 3) do
    %TicTacToe{
      code: code,
      players: %{player.id => player},
      pieces: %{player.id => MapSet.new()},
      board_size: board_size,
      win_length: win_length
    }
    |> reset_timer()
  end

  def reset(%TicTacToe{} = state) do
    %TicTacToe{
      state
      | status: :waiting,
        turn: 0,
        players: Map.new(state.players, fn {id, p} -> {id, %Player{p | ready: false}} end),
        pieces: Map.new(Map.keys(state.pieces), fn id -> {id, MapSet.new()} end)
    }
    |> reset_timer()
  end

  # Neat pattern matching use

  def join(%TicTacToe{players: players} = state, %Player{})
      when map_size(players) >= state.max_players,
      do: {:error, "Can't join FULL game"}

  def join(%TicTacToe{players: players} = _, %Player{})
      when map_size(players) == 0,
      do: {:error, "Can't join EMPTY game"}

  def join(%TicTacToe{players: players, pieces: pieces} = state, %Player{} = new_player) do
    case Map.has_key?(players, new_player.id) do
      true ->
        :ok

      false ->
        shape =
          Player.shapes()
          |> Enum.find(:cross, fn shape ->
            Map.values(players) |> Enum.all?(fn player -> player.shape != shape end)
          end)

        {:ok,
         %TicTacToe{
           state
           | players:
               Map.put(players, new_player.id, %Player{
                 new_player
                 | # store join order before randomized in start
                   order: map_size(players),
                   shape: shape
               }),
             pieces: Map.put(pieces, new_player.id, MapSet.new())
         }
         |> reset_timer()}
    end
  end

  def leave(%TicTacToe{players: players} = state, %Player{id: id}) do
    {:ok, %TicTacToe{state | players: Map.delete(players, id)}}
  end

  def ready(%TicTacToe{status: status} = state, %Player{} = player, ready)
      when status in [:waiting, :done] do
    {:ok,
     %TicTacToe{
       state
       | players: %{state.players | player.id => %Player{player | ready: ready}}
     }}
  end

  def ready(%TicTacToe{status: status}, %Player{}), do: {:error, "Can't ready #{status} game"}

  def start(%TicTacToe{status: :waiting, players: players} = state)
      when map_size(players) >= state.min_players do
    case Map.values(players) |> Enum.all?(fn player -> player.ready end) do
      true ->
        players =
          players
          |> Enum.zip(Enum.shuffle(0..(map_size(players) - 1)))
          |> Map.new(fn {{id, player}, order} -> {id, %Player{player | order: order}} end)

        {:ok, %TicTacToe{state | status: :playing, players: players}}

      false ->
        {:error, "Not all players ready to start game"}
    end
  end

  def start(%TicTacToe{status: status, players: players}),
    do: {:error, "Can't start #{status} game with #{map_size(players)} players"}

  def move(%TicTacToe{pieces: pieces} = state, %Player{} = player, move) do
    with :ok <- verify_status(state, [:playing]),
         :ok <- verify_player_turn(state, player),
         :ok <- verify_valid_move(state, move) do
      {:ok,
       %TicTacToe{
         state
         | pieces: %{pieces | player.id => pieces[player.id] |> MapSet.put(move)}
       }
       |> check_win(player)
       |> next_turn()
       |> reset_timer()}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_status(%TicTacToe{status: status}, allowed) do
    case Enum.member?(allowed, status) do
      true -> :ok
      false -> {:error, "Game is #{status}"}
    end
  end

  def verify_player_turn(%TicTacToe{} = state, %Player{} = player) do
    case is_player_turn?(state, player) do
      true -> :ok
      false -> {:error, "Not player:#{player.order}'s turn"}
    end
  end

  def is_player_turn?(%TicTacToe{} = state, %Player{} = player) do
    case rem(state.turn, map_size(state.players)) do
      x when x == player.order -> true
      _ -> false
    end
  end

  defp verify_valid_move(%TicTacToe{pieces: pieces}, move) do
    if Map.values(pieces) |> Enum.any?(fn v -> MapSet.member?(v, move) end) do
      {:error, "Move already taken"}
    else
      :ok
    end
  end

  defp check_win(%TicTacToe{} = state, %Player{} = player) do
    case is_win?(state, player) do
      true -> %TicTacToe{state | status: :done}
      false -> state
    end
  end

  @directions [{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}]

  defp is_win?(%TicTacToe{pieces: pieces, win_length: win_length}, %Player{id: id}) do
    Enum.any?(@directions, fn {dx, dy} ->
      pieces[id]
      |> Enum.sort()
      |> Enum.reduce_while(%{}, fn {x, y}, acc ->
        length = 1 + Map.get(acc, {x + dx, y + dy}, 0)

        case length do
          ^win_length -> {:halt, true}
          _ -> {:cont, Map.put(acc, {x, y}, length)}
        end
      end)
      |> case do
        true -> true
        _ -> false
      end
    end)
  end

  def next_turn(%TicTacToe{status: :playing, turn: turn, board_size: board_size} = state) do
    last_turn = board_size * board_size - 1

    case turn do
      ^last_turn -> %TicTacToe{state | status: :done}
      _ -> %TicTacToe{state | turn: turn + 1}
    end
  end

  def next_turn(%TicTacToe{status: :done} = state), do: state

  def find_player(%TicTacToe{players: players}, player_id) do
    case Map.fetch(players, player_id) do
      :error -> {:error, "Player not found"}
      result -> result
    end
  end

  defp reset_timer(%TicTacToe{status: :playing} = state) do
    state |> cancel_timer() |> set_timer(:end_turn, @turn_time)
  end

  defp reset_timer(%TicTacToe{} = state) do
    state |> cancel_timer() |> set_timer(:end_for_timeout, @timeout_time)
  end

  defp cancel_timer(%TicTacToe{timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %TicTacToe{state | timer_ref: nil}
  end

  defp cancel_timer(%TicTacToe{} = state), do: state

  defp set_timer(%TicTacToe{} = state, msg, time) do
    %TicTacToe{
      state
      | timer_ref: Process.send_after(self(), msg, time)
    }
  end
end
