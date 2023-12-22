defmodule Pixelgame.Games.TicTacToe do
  alias Pixelgame.Games.Player
  alias __MODULE__

  defstruct code: nil,
            status: :waiting,
            players: %{},
            min_players: 2,
            max_players: 2,
            turn: 1,
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
  @timeout_time 1000 * 60 * 5
  # 1 minute turn time while :playing
  @turn_time 1000 * 60

  def new(code, player, board_size \\ 3, win_length \\ 3) do
    %TicTacToe{
      code: code,
      players: %{player.user_id => player},
      pieces: %{player.user_id => MapSet.new()},
      board_size: board_size,
      win_length: win_length
    }
    |> set_timer(@timeout_time)
  end

  # Neat pattern matching use

  def join(%TicTacToe{players: players} = state, %Player{})
      when map_size(players) >= state.max_players,
      do: {:error, "Can't join FULL game"}

  def join(%TicTacToe{players: players} = _, %Player{})
      when map_size(players) == 0,
      do: {:error, "Can't join EMPTY game"}

  def join(%TicTacToe{players: players, pieces: pieces} = state, %Player{} = new_player) do
    index = map_size(players)

    {:ok,
     %TicTacToe{
       state
       | players: Map.put(players, new_player.user_id, %Player{new_player | order: index}),
         pieces: Map.put(pieces, new_player.user_id, MapSet.new())
     }
     |> reset_timer()}
  end

  def ready(%TicTacToe{status: :waiting} = state, %Player{} = player) do
    # Is this the best way to write this?
    {:ok,
     %TicTacToe{
       state
       | players: %{state.players | player.user_id => %Player{player | ready: !player.ready}}
     }}
  end

  def ready(%TicTacToe{status: status}, %Player{}), do: {:error, "Can't ready #{status} game"}

  def start(%TicTacToe{status: :waiting, players: players} = state)
      when map_size(players) >= state.min_players do
    {:ok, state}
  end

  def start(%TicTacToe{status: status, players: players}),
    do: {:error, "Can't start #{status} game with #{map_size(players)} players"}

  def move(%TicTacToe{status: :playing, pieces: pieces} = state, %Player{} = player, move) do
    with :ok <- verify_player_turn(state, player),
         :ok <- verify_valid_move(state, move) do
      {:ok,
       %TicTacToe{
         state
         | pieces: %{pieces | [player.user_id] => pieces[player.user_id] |> MapSet.put(move)}
       }
       |> check_win(player)
       |> next_turn()
       |> reset_timer()}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def move(%TicTacToe{status: status}, %Player{}, _),
    do: {:error, "Can't make move in #{status} game"}

  defp verify_player_turn(%TicTacToe{} = state, %Player{} = player) do
    # turn is 1-indexed but order is 0-indexed
    case rem(state.turn - 1, map_size(state.players)) do
      x when x == player.order -> :ok
      _ -> {:error, "Not player:#{player.order}'s turn"}
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

  @directions [{{-1, 0}, {1, 0}}, {{-1, -1}, {1, 1}}, {{-1, 1}, {1, -1}}, {{0, -1}, {0, 1}}]

  defp is_win?(%TicTacToe{pieces: pieces, win_length: win_length}, %Player{user_id: user_id}) do
    values = Map.values(pieces[user_id])

    Enum.any?(@directions, fn {{ax, ay}, {bx, by}} ->
      Enum.reduce_while(values, %{}, fn {x, y}, acc ->
        length = 1 + Map.get(acc, {x + ax, y + ay}, 0) + Map.get(acc, {x + bx, y + by}, 0)

        case length do
          ^win_length -> {:halt, acc}
          _ -> {:cont, Map.put(acc, {x, y}, length)}
        end
      end)
      |> case do
        {:halt, _} -> true
        _ -> false
      end
    end)
  end

  defp next_turn(%TicTacToe{status: :playing, turn: turn, board_size: board_size} = state) do
    last_turn = board_size * board_size

    case turn do
      ^last_turn -> %TicTacToe{state | status: :done}
      _ -> %TicTacToe{state | turn: turn + 1}
    end
  end

  defp next_turn(%TicTacToe{status: :done} = state), do: state

  def find_player(%TicTacToe{players: players}, player_id) do
    case Map.fetch(players, player_id) do
      :error -> {:error, "Player not found"}
      result -> result
    end
  end

  defp reset_timer(%TicTacToe{status: :playing} = state) do
    state |> cancel_timer() |> set_timer(@turn_time)
  end

  defp reset_timer(%TicTacToe{} = state) do
    state |> cancel_timer() |> set_timer(@timeout_time)
  end

  defp cancel_timer(%TicTacToe{timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %TicTacToe{state | timer_ref: nil}
  end

  defp cancel_timer(%TicTacToe{} = state), do: state

  defp set_timer(%TicTacToe{} = state, time) do
    %TicTacToe{
      state
      | timer_ref: Process.send_after(self(), :end_for_timeout, time)
    }
  end
end
