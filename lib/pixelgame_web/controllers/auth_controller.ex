defmodule PixelgameWeb.AuthController do
  use PixelgameWeb, :controller
  plug Ueberauth

  alias PixelgameWeb.UserAuth
  alias Pixelgame.Accounts

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn |> put_flash(:error, "Authentication failed.") |> redirect(to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # This is signin and signup
    case Accounts.signin_via_github(auth.info.email, auth.info, auth.credentials.token) do
      {:ok, user} ->
        IO.inspect(user, label: "user path")

        conn
        |> put_flash(:info, "Success")
        |> put_session(:user_id, user.id)
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        IO.inspect(changeset, label: "error path")
        conn |> put_flash(:error, "Error") |> redirect(to: "/")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
