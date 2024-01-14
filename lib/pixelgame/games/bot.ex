defmodule Pixelgame.Games.Bot do
  alias Pixelgame.Games.TicTacToe

  @directions [{1, 1}, {1, 0}, {1, -1}, {0, 1}]

  @empty_set MapSet.new()
  # We bound minimax values to [-10, 10]
  @neg_infinity -11
  @pos_infinity 11
  defp minimax(%TicTacToe{pieces: %{empty: set}}, _is_min) when set == @empty_set,
    do: 0

  defp minimax(%TicTacToe{pieces: pieces} = state, is_min) do
    order = rem(state.turn + ((is_min && 1) || 0), 2)
    player = Enum.find(state.players, fn player -> player.order == order end)

    if is_min do
      Enum.reduce(pieces.empty, @pos_infinity, fn coord, acc ->
        value =
          if winning_move?(state, player.id, coord) do
            -10
          else
            minimax(move(state, player.id, coord), false)
          end

        min(acc, value)
      end)
    else
      Enum.reduce(pieces.empty, @neg_infinity, fn coord, acc ->
        value =
          if winning_move?(state, player.id, coord) do
            10
          else
            minimax(move(state, player.id, coord), true)
          end

        max(acc, value)
      end)
    end
  end

  defp move(%TicTacToe{} = state, id, move) do
    %TicTacToe{
      state
      | pieces: %{
          state.pieces
          | id => state.pieces[id] |> MapSet.put(move),
            empty: state.pieces.empty |> MapSet.delete(move)
        }
    }
  end

  defp winning_move?(%TicTacToe{pieces: pieces, board_size: n, win_length: k}, id, {x, y}) do
    Enum.any?(@directions, fn {dx, dy} ->
      {front, back} =
        case dx == 0 do
          true -> {-1..(1 - y)//-1, 1..(n - y)//1}
          false -> {-1..(1 - x)//-1, 1..(n - x)//1}
        end

      front_len =
        Enum.count_until(
          front,
          fn dist ->
            coord = {x + dist * dx, y + dist * dy}
            not MapSet.member?(pieces[id], coord)
          end,
          1000
        )

      back_len =
        Enum.count_until(
          back,
          fn dist ->
            coord = {x + dist * dx, y + dist * dy}
            not MapSet.member?(pieces[id], coord)
          end,
          1000
        )

      front_len + 1 + back_len >= k
    end)
  end

  def next_move(%TicTacToe{pieces: pieces, players: players, board_size: n} = state, _player_id)
      when map_size(players) == 2 and n < 5 do
    Enum.reduce(pieces.empty, {{-1, -1}, @neg_infinity}, fn coord, acc ->
      v = minimax(state, false)

      if v > elem(acc, 1) do
        {coord, v}
      else
        acc
      end
    end)
    |> elem(0)
  end

  # Minimax is for 2 players and max^n is hard to implement.
  # Specifically, max^n isn't prunable and requires a good heuristic for positional value
  #
  # The simple next-best-move heuristic below only considers moves adjacent to an existing piece
  # and prioritizes
  # - winning
  # - blocking an immediate win
  # - long chains with enough space to win
  # in that order. It easily loses to 2 step setups, but for > 3 players, this isn't obvious.
  def next_move(%TicTacToe{turn: 0, board_size: n}, _player_id) do
    {:rand.uniform(n), :rand.uniform(n)}
  end

  def next_move(%TicTacToe{pieces: pieces, board_size: n, win_length: k}, player_id) do
    Enum.reduce(@directions, %{}, fn {dx, dy}, acc ->
      # IO.inspect("dir #{dx} #{dy}")

      Enum.reduce(pieces, %{}, fn {id, pieceSet}, acc ->
        pieceSet
        |> Enum.sort()
        |> Enum.reduce(%{}, fn {x, y}, acc ->
          len = Map.get(acc, {x, y}, 1)

          preCoords = {x - len * dx, y - len * dy}
          prePreCoords = {x - (len + 1) * dx, y - (len + 1) * dy}

          postCoords = {x + dx, y + dy}

          acc
          # start at one, but keep value set by postCoords
          |> Map.put_new({x, y}, 1)

          # if preCoord can combine two lines
          |> Map.put(preCoords, len + Map.get(acc, prePreCoords, 0) + 1)
          |> Map.put(postCoords, len + 1)
        end)
        # |> IO.inspect(label: "unfiltered")
        |> Enum.filter(fn {{x, y}, _value} ->
          x >= 0 && x <= n && y >= 0 && y <= n && MapSet.member?(pieces.empty, {x, y})
        end)
        # |> IO.inspect(label: "filter")
        |> Enum.map(fn {{x, y}, value} ->
          value =
            case value do
              # winning
              ^k when id == player_id ->
                1_000_000

              # blocking win
              ^k ->
                100_000

              # only value tiles with enough space to win
              v ->
                {front, back} =
                  case dx == 0 do
                    true -> {-1..(1 - y)//-1, 1..(n - y)//1}
                    false -> {-1..(1 - x)//-1, 1..(n - x)//1}
                  end

                front_len =
                  Enum.count_until(
                    front,
                    fn dist ->
                      coord = {x + dist * dx, y + dist * dy}

                      not (MapSet.member?(pieces.empty, coord) or
                             MapSet.member?(pieces[player_id], coord))
                    end,
                    1000
                  )

                back_len =
                  Enum.count_until(
                    back,
                    fn dist ->
                      coord = {x + dist * dx, y + dist * dy}

                      not (MapSet.member?(pieces.empty, coord) or
                             MapSet.member?(pieces[player_id], coord))
                    end,
                    1000
                  )

                if front_len + 1 + back_len >= k do
                  v
                else
                  0
                end
            end

          {{x, y}, value}
        end)
        # |> IO.inspect(label: "revalued")
        |> Map.new()
        |> Map.merge(acc, fn _coord, v1, v2 ->
          v1 + v2
        end)

        # |> IO.inspect(label: "merge 1")

        # map with coords, value = sum of each player value in this direction
      end)
      |> Map.merge(acc, fn _coord, v1, v2 ->
        v1 + v2
      end)

      # |> IO.inspect(label: "merge 2")

      # map with coords, value = sum of each player value in ALL directions
    end)
    |> Enum.sort(fn {_, v1}, {_, v2} -> v1 >= v2 end)
    # |> IO.inspect(label: "filter")
    |> Enum.at(0)
    |> elem(0)
  end
end
