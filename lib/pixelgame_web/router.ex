defmodule PixelgameWeb.Router do
  use PixelgameWeb, :router

  import PixelgameWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {PixelgameWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PixelgameWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/auth", PixelgameWeb do
    pipe_through :browser

    delete "/signout", AuthController, :delete
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Authed Routes
  # HTTP and Liveview ARE SEPARATE PIPELINES
  # https://hexdocs.pm/phoenix_live_view/security-model.html
  # If your application handle both regular HTTP requests and LiveViews, then you must perform authentication and authorization on both.

  scope "/", PixelgameWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_autenticated_user,
      on_mount: [{PixelgameWeb.UserAuth, :ensure_authenticated}] do
      # :whatever action available in url and as @live_action
      live "/game", GameLive, :new
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:pixelgame, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PixelgameWeb.Telemetry
    end
  end
end
