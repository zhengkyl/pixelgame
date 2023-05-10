defmodule Pixelgame.Repo do
  use Ecto.Repo,
    otp_app: :pixelgame,
    adapter: Ecto.Adapters.Postgres
end
