defmodule TemplatePhoenixWeb.Router do
  use TemplatePhoenixWeb, :router

  # auth:begin — removed by bin/remove-auth.sh
  import TemplatePhoenixWeb.UserAuth
  # auth:end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TemplatePhoenixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # auth:begin
    plug :fetch_current_scope_for_user
    # auth:end
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check for uptime monitors and load balancers (no pipeline).
  scope "/", TemplatePhoenixWeb do
    get "/health", HealthController, :show
  end

  scope "/", TemplatePhoenixWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", TemplatePhoenixWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:template_phoenix, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TemplatePhoenixWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # auth:begin
  ## Authentication routes

  scope "/", TemplatePhoenixWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TemplatePhoenixWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", TemplatePhoenixWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TemplatePhoenixWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # auth:end
end
