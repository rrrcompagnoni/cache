defmodule Cache.Entry do
  use GenServer

  alias Cache.{
    Jobs,
    Jobs.Job,
    RefreshScheduler
  }

  # Internal usage

  @doc false
  def start_link(timeout) do
    GenServer.start_link(__MODULE__, timeout, [])
  end

  @doc false
  def get(server, key) do
    GenServer.call(server, {:get, key}, :infinity)
  end

  @doc false
  def notify(server) do
    GenServer.cast(server, :subscription_notification)
  end

  # Callbacks

  @doc false
  @impl true
  def init(timeout) do
    {:ok, timeout}
  end

  @doc false
  @impl true
  def handle_cast(:subscription_notification, timeout) do
    {:noreply, timeout}
  end

  @doc false
  @impl true
  def handle_call({:get, key}, _from, timeout) do
    result =
      case {Cache.get_entry(key), Jobs.Storage.get(key)} do
        {nil, {:ok, %Job{state: :running} = job}} ->
          try_after_waiting(job, self(), timeout)

        {nil, _} ->
          {:error, :not_registered}

        {entry, _} ->
          entry
      end

    {:reply, result, timeout}
  end

  # Private functions

  defp try_after_waiting(job, subscriber_pid, waiting_time) do
    :ok = RefreshScheduler.subscribe(job, subscriber_pid)

    receive do
      {_, :subscription_notification} ->
        Cache.get_entry(job.key)
    after
      waiting_time ->
        {:error, :timeout}
    end
  end
end
