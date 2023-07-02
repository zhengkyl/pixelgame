defmodule Pixelgame.Repo.Migrations.CreateRules do
  use Ecto.Migration

  def change do
    create table(:rules) do
      add :name, :string
      add :number, :decimal, precision: 43, scale: 0, null: false
      add :rating, :integer

      timestamps(inserted_at: :created_at)
    end
  end
end
