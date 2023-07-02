defmodule Pixelgame.Repo.Migrations.CreateRules do
  use Ecto.Migration

  def change do
    create table(:rules, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string
      add :rating, :integer

      timestamps(inserted_at: :created_at)
    end
  end
end
