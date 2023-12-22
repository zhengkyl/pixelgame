defmodule Pixelgame.Games.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  embedded_schema do
    field :name, :string
    field :user_id, :integer
    field :order, :integer
    field :color, :string
    field :ready, :boolean
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:name, :user_id, :color])
    |> validate_required([:name, :user_id])
    |> validate_format(:color, ~r/#[A-F\d]{6}/)
  end

  def create(attrs) do
    # apply_action checks validity via pretend insert
    %Player{} |> changeset(attrs) |> apply_action(:insert)
  end
end
