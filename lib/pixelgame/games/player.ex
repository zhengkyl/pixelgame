defmodule Pixelgame.Games.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  @shapes [:cross, :circle, :square, :triangle]

  def shapes(), do: @shapes

  @primary_key {:id, :id, []}
  embedded_schema do
    field :name, :string
    field :order, :integer, default: 0
    field :shape, Ecto.Enum, values: @shapes, default: :cross
    field :color, :string, default: "#ffffff"
    field :ready, :boolean, default: false
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:name, :id, :shape, :color])
    |> validate_required([:name, :id])
    |> validate_format(:color, ~r/(#[a-f\d]{6})|(none)/)
  end

  def create(attrs) do
    # apply_action checks validity via pretend insert
    case %Player{} |> changeset(attrs) |> apply_action(:insert) do
      {:error, _} ->
        {:error, "Invalid player info"}

      player ->
        player
    end
  end
end
