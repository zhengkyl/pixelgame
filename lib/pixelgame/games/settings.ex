defmodule Pixelgame.Games.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @presets [:custom, :tictactoe, :connect4, :gomoku]

  @primary_key false
  embedded_schema do
    field :board_size, :integer, default: 3
    field :win_length, :integer, default: 3
    field :preset, Ecto.Enum, values: @presets, default: :tictactoe
  end

  def changeset(settings, attrs) do
    changeset =
      settings
      |> cast(attrs, [:board_size, :win_length])

    board_size = get_field(changeset, :board_size)
    win_length = get_field(changeset, :board_size)

    preset =
      case win_length do
        3 when board_size == 3 -> :tictactoe
        4 when win_length == 7 -> :connect4
        5 when win_length == 15 -> :gomoku
        _ -> :custom
      end

    changeset
    |> validate_number(:board_size, greater_than_or_equal_to: 3, less_than_or_equal_to: 20)
    |> validate_number(:win_length, greater_than_or_equal_to: 3, less_than_or_equal_to: board_size)
    |> put_change(:preset, preset)
  end

  # def create(attrs) do
  #   # apply_action checks validity via pretend insert
  #   case %Settings{} |> changeset(attrs) |> apply_action(:insert) do
  #     {:error, _} ->
  #       {:error, "Invalid settings"}

  #     {:ok, settings} ->
  #       settings
  #   end
  # end
end
