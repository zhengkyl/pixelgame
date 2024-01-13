defmodule Pixelgame.Games.Bot do
  alias Pixelgame.Games.TicTacToe

  @directions [{1, 1}, {1, 0}, {1, -1}, {0, 1}]
  def next_move(%TicTacToe{turn: 0, board_size: n}, _player_id) do
    {:rand.uniform(n), :rand.uniform(n)}
  end

  def next_move(%TicTacToe{pieces: pieces, board_size: n, win_length: k}, player_id) do
    all_coords = for x <- 1..n, y <- 1..n, do: {x, y}

    empty_set =
      MapSet.new(
        all_coords
        |> Enum.reject(fn {x, y} ->
          pieces
          |> Map.values()
          |> Enum.any?(fn pieceSet ->
            MapSet.member?(pieceSet, {x, y})
          end)
        end)
      )

    # IO.inspect(empty_set, label: "empty_set")

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
          x >= 0 && x <= n && y >= 0 && y <= n && MapSet.member?(empty_set, {x, y})
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
                  case dy == 0 do
                    true -> {-1..(1 - y)//-1, 1..(n - y)//1}
                    false -> {-1..(1 - x)//-1, 1..(n - x)//1}
                  end

                front_len =
                  Enum.reduce_while(front, 0, fn dist, acc ->
                    coord = {x + dist * dx, y + dist * dy}

                    if MapSet.member?(empty_set, coord) or
                         MapSet.member?(pieces[player_id], coord) do
                      {:cont, acc + 1}
                    else
                      {:halt, acc}
                    end
                  end)

                back_len =
                  Enum.reduce_while(back, 0, fn dist, acc ->
                    coord = {x + dist * dx, y + dist * dy}

                    if MapSet.member?(empty_set, coord) or
                         MapSet.member?(pieces[player_id], coord) do
                      {:cont, acc + 1}
                    else
                      {:halt, acc}
                    end
                  end)

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
