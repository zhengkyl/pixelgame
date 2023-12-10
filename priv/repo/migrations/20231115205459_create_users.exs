defmodule Pixelgame.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext, null: false
      add :name, :citext, null: false
      add :tag, :citext, null: false

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:name, :tag])

    create table(:identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_token, :string, null: false
      add :provider_email, :string, null: false
      add :provider_username, :string, null: false
      add :provider_url, :string

      timestamps()
    end

    create index(:identities, [:user_id])
    create index(:identities, [:provider])
    create unique_index(:identities, [:user_id, :provider])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
