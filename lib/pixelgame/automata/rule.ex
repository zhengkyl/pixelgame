defmodule Pixelgame.Automata.Rule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, []}
  @derive {Phoenix.Param, key: :id}
  schema "rules" do
    field :name, :string
    field :rating, :integer

    timestamps(inserted_at: :created_at)
  end

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:name, :number, :rating])
    |> validate_required([:name, :number, :rating])
  end
end
