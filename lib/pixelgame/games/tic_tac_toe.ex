defmodule Pixelgame.Games.TicTacToe do
  alias Pixelgame.Accounts.User
  alias __MODULE__

  defstruct code: nil, status: :waiting, players: [], turn: 0, size: 3, board: [], timer_ref: nil

  @type t :: %TicTacToe{
          code: nil | String.t(),
          status: :waiting | :ready | :playing | :done,
          players: [User],
          turn: integer(),
          size: integer(),
          board: [integer()],
          timer_ref: nil
        }

  def new(code, player, size \\ 3) do
    %TicTacToe{
      code: code,
      players: [player],
      size: size,
      board: List.duplicate(0, size)
    }
    |> set_timer()
  end

  # Neat pattern matching use
  def join_game(%TicTacToe{players: []} = _state, %User{}) do
    {:error, "Cannot join EMPTY game"}
  end

  def join_game(%TicTacToe{players: [_p1, _p2]} = _state, %User{}) do
    {:error, "Cannot join FULL game"}
  end

  def join_game(%TicTacToe{players: [p1]} = state, %User{} = p2) do
    {:ok, %TicTacToe{state | players: [p1, p2]} |> reset_timer()}
  end

  def start_game(%TicTacToe{status: :ready, players: [_p1, _p2]} = state) do
    {:ok, state}
  end

  # 5 minute timeout
  @timeout_time 1000 * 60 * 5

  defp reset_timer(%TicTacToe{} = state) do
    state |> cancel_timer() |> set_timer()
  end

  defp cancel_timer(%TicTacToe{timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %TicTacToe{state | timer_ref: nil}
  end

  defp cancel_timer(%TicTacToe{} = state), do: state

  defp set_timer(%TicTacToe{} = state) do
    %TicTacToe{
      state
      | timer_ref: Process.send_after(self(), :end_for_timeout, @timeout_time)
    }
  end
end
