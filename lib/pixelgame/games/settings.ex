defmodule Pixelgame.Games.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @presets [:custom, :tictactoe, :connect4, :gomoku]

  @primary_key false
  embedded_schema do
    field :board_size, :integer
    field :win_length, :integer
    field :preset, Ecto.Enum, values: @presets
  end

  def preset(attr) do
    case attr.win_length do
      3 when attr.board_size == 3 -> :tictactoe
      4 when attr.board_size == 7 -> :connect4
      5 when attr.board_size == 15 -> :gomoku
      _ -> :custom
    end
  end

  def changeset(settings, attrs) do
    changeset =
      settings
      |> cast(attrs, [:board_size, :win_length])

    board_size = get_field(changeset, :board_size)
    win_length = get_field(changeset, :win_length)

    preset =
      preset(%{
        board_size: board_size,
        win_length: win_length
      })

    changeset
    |> validate_number(:board_size,
      greater_than_or_equal_to: win_length,
      less_than_or_equal_to: 20
    )
    |> validate_number(:win_length, greater_than_or_equal_to: 3, less_than_or_equal_to: board_size)
    |> put_change(:preset, preset)
  end
end
