defmodule Pixelgame.Accounts do
  import Ecto.Query
  import Ecto.Changeset

  alias Pixelgame.Accounts.{User, Identity}
  alias Pixelgame.Repo

  def signup_via_github(email, info, token) do
    if user = get_user_by_provider(:github, email) do
      update_provider_token(user, :github, token)
    else
      User.github_signup_changeset(email, info, token) |> Repo.insert()
    end
  end

  defp get_user_by_provider(provider, email) when provider in [:github] do
    Repo.one(
      from(u in User,
        join: i in assoc(u, :identities),
        # https://stackoverflow.com/questions/73588330/why-do-ecto-queries-need-the-pin-operator
        # tldr "pin" is used by Ecto to escape fields
        where: i.provider == ^to_string(provider) and u.email == ^String.downcase(email)
      )
    )
  end

  defp update_provider_token(%User{} = user, provider, token) do
    identity =
      Repo.one(
        from(i in Identity,
          where: i.user_id == ^user.id and i.provider == ^to_string(provider)
        )
      )

    {:ok, _} = identity |> change() |> put_change(:provider_token, token) |> Repo.update()
  end
end
