defmodule Pixelgame.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      PixelgameWeb.Telemetry,
      # Start the Ecto repository
      Pixelgame.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Pixelgame.PubSub},
      # Start Finch
      {Finch, name: Pixelgame.Finch},
      # Start the Endpoint (http/https)
      PixelgameWeb.Endpoint
      # Start a worker by calling: Pixelgame.Worker.start_link(arg)
      # {Pixelgame.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pixelgame.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PixelgameWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
