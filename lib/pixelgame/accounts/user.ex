defmodule Pixelgame.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Pixelgame.Accounts.{User, Identity}

  schema "users" do
    field :email, :string
    field :name, :string
    field :tag, :string

    has_many :identities, Identity

    timestamps()
  end

  def github_signup_changeset(email, info, token) do
    identity_changeset = Identity.github_signup_changeset(info, token)

    if identity_changeset.valid? do
      attrs = %{
        "email" => email,
        "name" => get_change(identity_changeset, :provider_username),
        "tag" => "github"
      }

      # tag is longer than rename max -> no duplicate names as long as provider username unique
      # assume email, name validated by provider
      %User{}
      |> cast(attrs, [:email, :name, :tag])
      |> validate_required([:email, :name, :tag])
      |> unsafe_validate_unique(:email, Pixelgame.Repo)
      |> unique_constraint(:email)
      |> unsafe_validate_unique([:name, :tag], Pixelgame.Repo)
      |> unique_constraint([:name, :tag])
      |> put_assoc(:identities, [identity_changeset])
    else
      # return identity errors
      %User{}
      |> change()
      |> Map.put(:valid?, false)
      |> put_assoc(:identities, [identity_changeset])
    end
  end

  def rename_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :tag])
    |> validate_required([:name, :tag])
    |> validate_rename()
  end

  defp validate_rename(changeset) do
    changeset
    |> validate_format(:name, ~r/^[a-z\d_-]{1,39}$/)
    |> validate_format(:tag, ~r/^[a-z]{1-4}$/)
    |> unsafe_validate_unique([:name, :tag], Pixelgame.Repo)
    |> unique_constraint([:name, :tag])
  end
end
