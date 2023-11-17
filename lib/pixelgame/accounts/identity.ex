defmodule Pixelgame.Accounts.Identity do
  use Ecto.Schema
  import Ecto.Changeset

  alias Pixelgame.Accounts.{Identity, User}

  @github "github"

  # hide sensitive info from logs
  @derive {Inspect, except: [:provider_token]}
  schema "identities" do
    field :provider, :string
    field :provider_token, :string
    field :provider_email, :string
    field :provider_username, :string
    field :provider_url, :string

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def github_signup_changeset(info, token) do
    attrs = %{
      "provider_token" => token,
      "provider_email" => info.email,
      "provider_username" => info.nickname,
      "provider_url" => info.urls.html_url
    }

    %Identity{provider: @github}
    |> cast(attrs, [
      :provider_token,
      :provider_email,
      :provider_username,
      :provider_url
    ])
    |> validate_required([
      :provider_token,
      :provider_email,
      :provider_username,
      :provider_url
    ])
  end
end
