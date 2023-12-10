defmodule Pixelgame.Games.TicTacToe do
  alias Pixelgame.Accounts.User
  alias __MODULE__

  defstruct code: nil, status: :waiting, players: [], turn: 0, size: 3, board: []

  @type t :: %TicTacToe{
          code: nil | String.t(),
          status: :waiting | :ready | :playing | :done,
          players: [User],
          turn: integer(),
          size: integer(),
          board: [integer()]
        }

  # def new(game_code, )
end
