defmodule Cache.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Cache, []},
      {Cache.Jobs.Storage, []},
      {DynamicSupervisor, name: Cache.RefreshScheduler.DynamicSupervisor, strategy: :one_for_one},
      {DynamicSupervisor,
       name: Cache.Entries.DynamicSupervisor, strategy: :one_for_one, restart: :transient},
      {Task.Supervisor, name: Cache.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
