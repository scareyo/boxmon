defmodule Boxmon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BoxmonWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:boxmon, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Boxmon.PubSub},
        {Task.Supervisor, name: Boxmon.TaskSup}
      ] ++
        if(Application.get_env(:boxmon, :start_monitor, true), do: [Boxmon.Monitor], else: []) ++
        [
          # Start to serve requests, typically the last entry
          BoxmonWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Boxmon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BoxmonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
