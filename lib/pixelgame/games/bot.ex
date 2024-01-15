defmodule Pixelgame.Games.Bot do
  alias Pixelgame.Games.TicTacToe

  @directions [{1, 1}, {1, 0}, {1, -1}, {0, 1}]

  # We bound minimax values to [-10, 10]
  @neg_infinity -11
  @pos_infinity 11

  defp minimax(%TicTacToe{} = state, move, is_min, alpha, beta) do
    order = rem(state.turn + if(is_min, do: 0, else: 1), 2)
    previous = Map.values(state.players) |> Enum.find(fn player -> player.order == order end)

    if winning_move?(state, previous.id, move) do
      # previous players move, so opposite of is_min
      depth = 9 - MapSet.size(state.pieces.empty)
      if is_min, do: 10 - depth, else: -10 + depth
    else
      state = move(state, previous.id, move)

      if MapSet.size(state.pieces.empty) == 0 do
        0
      else
        if is_min do
          Enum.reduce_while(state.pieces.empty, {@pos_infinity, beta}, fn coord, {min, beta} ->
            value = minimax(state, coord, false, alpha, beta)

            min = min(min, value)
            beta = min(beta, value)

            if beta <= alpha do
              {:halt, {min, beta}}
            else
              {:cont, {min, beta}}
            end
          end)
        else
          Enum.reduce_while(state.pieces.empty, {@neg_infinity, alpha}, fn coord, {max, alpha} ->
            value = minimax(state, coord, true, alpha, beta)

            max = max(max, value)
            alpha = max(max, value)

            if beta <= alpha do
              {:halt, {max, alpha}}
            else
              {:cont, {max, alpha}}
            end
          end)
        end
        |> elem(0)
      end
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

  # Forward and backward offsets for chain in given direction on n x n board
  defp offsets(x, y, {dx, dy}, n) do
    case {dx, dy} do
      {0, 1} -> {-1..(1 - y)//-1, 1..(n - y)//1}
      {1, 0} -> {-1..(1 - x)//-1, 1..(n - x)//1}
      {1, 1} -> {-1..max(1 - x, 1 - y)//-1, 1..min(n - x, n - y)//1}
      {1, -1} -> {-1..max(1 - x, y - n)//-1, 1..min(n - x, y - 1)//1}
    end
  end

  defp winning_move?(%TicTacToe{pieces: pieces, board_size: n, win_length: k}, id, {x, y}) do
    Enum.any?(@directions, fn {dx, dy} ->
      {front, back} = offsets(x, y, {dx, dy}, n)

      front_len =
        count_while(
          front,
          fn dist ->
            coord = {x + dist * dx, y + dist * dy}
            MapSet.member?(pieces[id], coord)
          end
        )

      back_len =
        count_while(
          back,
          fn dist ->
            coord = {x + dist * dx, y + dist * dy}
            MapSet.member?(pieces[id], coord)
          end
        )

      front_len + 1 + back_len >= k
    end)
  end

  # With only alpha beta pruning, minimax can only do 3x3 in reasonable time
  # Using a max depth + a good heuristic is the next step but...
  # That only works for 2 players + good heuristic is non trivial + choose slow or shallow depth
  # See heuristic-based next_move() below which is ok for 3+ players on arbitrary boards size
  # for potential direction for a board state heuristic
  def next_move(%TicTacToe{pieces: pieces, players: players, board_size: n} = state, _player_id)
      when map_size(players) == 2 and n == 3 do
    Enum.map(pieces.empty, fn coord ->
      v = minimax(state, coord, true, @neg_infinity, @pos_infinity)
      {coord, v}
    end)
    |> Enum.reduce({[], -1000}, fn {coord, v}, {coords, max_v} = acc ->
      case v do
        v when v > max_v -> {[coord], v}
        v when v == max_v -> {[coord | coords], v}
        _ -> acc
      end
    end)
    |> elem(0)
    |> Enum.random()
  end

  # Minimax is for 2 players and max^n is hard to implement.
  # Specifically, max^n isn't prunable and requires a good heuristic for positional value
  #
  # The simple next-best-move heuristic below only considers moves adjacent to an existing piece
  # and prioritizes
  # - winning
  # - blocking an immediate win
  # - long chains with enough space to win
  # in that order. It can't detect 2 step setups, but for 3+ players, this is mitigated
  def next_move(%TicTacToe{turn: 0, board_size: n}, _player_id) do
    {:rand.uniform(n), :rand.uniform(n)}
  end

  def next_move(%TicTacToe{pieces: pieces, board_size: n, win_length: k}, player_id) do
    Enum.reduce(@directions, %{}, fn {dx, dy}, acc ->
      pieces
      |> Map.delete(:empty)
      |> Enum.reduce(%{}, fn {id, pieceSet}, acc ->
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
        |> Enum.filter(fn {{x, y}, _value} ->
          x >= 0 && x <= n && y >= 0 && y <= n && MapSet.member?(pieces.empty, {x, y})
        end)
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
                {front, back} = offsets(x, y, {dx, dy}, n)

                front_len =
                  count_while(
                    front,
                    fn dist ->
                      coord = {x + dist * dx, y + dist * dy}

                      MapSet.member?(pieces.empty, coord) or
                        MapSet.member?(pieces[player_id], coord)
                    end
                  )

                back_len =
                  count_while(
                    back,
                    fn dist ->
                      coord = {x + dist * dx, y + dist * dy}

                      MapSet.member?(pieces.empty, coord) or
                        MapSet.member?(pieces[player_id], coord)
                    end
                  )

                if front_len + 1 + back_len >= k do
                  v
                else
                  0
                end
            end

          {{x, y}, value}
        end)
        |> Map.new()
        |> Map.merge(acc, fn _coord, v1, v2 ->
          v1 + v2
        end)

        # map with coords, value = sum of each player value in this direction
      end)
      |> Map.merge(acc, fn _coord, v1, v2 ->
        v1 + v2
      end)

      # map with coords, value = sum of each player value in ALL directions
    end)
    |> Enum.sort(fn {_, v1}, {_, v2} -> v1 >= v2 end)
    # |> IO.inspect(label: "all")
    |> Enum.at(0)
    |> elem(0)
  end

  defp count_while(enumerable, fun) do
    Enum.reduce_while(enumerable, 0, fn value, acc ->
      if fun.(value) do
        {:cont, acc + 1}
      else
        {:halt, acc}
      end
    end)
  end
end
