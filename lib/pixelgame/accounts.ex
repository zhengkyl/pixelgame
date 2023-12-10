defmodule Pixelgame.Accounts do
  import Ecto.Query
  import Ecto.Changeset

  alias Pixelgame.Accounts.{User, Identity, UserToken}
  alias Pixelgame.Repo

  def signin_via_github(email, info, token) do
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

  ## Database getters

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end
end
