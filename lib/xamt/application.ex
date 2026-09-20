defmodule Xamt.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      XamtWeb.Telemetry,
      Xamt.Repo,
      {DNSCluster, query: Application.get_env(:xamt, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Xamt.PubSub},
      XamtWeb.Presence,
      {Task.Supervisor, name: Xamt.TaskSupervisor},
      {XamtWeb.TypingTracker, Application.get_env(:xamt, XamtWeb.TypingTracker, [])},
      Xamt.Channels.LastMessageCache,
      Xamt.Channels.ChannelListCache,
      Xamt.Servers.ServerCache,
      Xamt.Messages.RateLimiter,
      XamtWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Xamt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    XamtWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
