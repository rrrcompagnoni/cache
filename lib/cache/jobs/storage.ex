defmodule Cache.Jobs.Storage do
  use GenServer
  require Logger

  alias Cache.Jobs.Job

  # Internal usage
  @doc false
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc false
  def store(%Job{} = job) do
    GenServer.call(__MODULE__, {:store, job})
  end

  @doc false
  def get(job_key) do
    GenServer.call(__MODULE__, {:get, job_key})
  end

  @doc false
  def set_idle(%Job{} = job) do
    GenServer.call(__MODULE__, {:set_idle, job})
  end

  @doc false
  def set_running(%Job{} = job) do
    GenServer.call(__MODULE__, {:set_running, job})
  end

  @doc false
  def update(%Job{} = job) do
    GenServer.call(__MODULE__, {:update, job})
  end

  @doc false
  def truncate() do
    GenServer.cast(__MODULE__, :truncate)
  end

  # Callbacks

  @doc false
  @impl true
  def init(_options) do
    storage_id =
      :ets.new(:jobs, [
        :set,
        :private,
        :named_table
      ])

    Logger.info("#{__MODULE__} started.")

    {:ok, %{storage_id: storage_id}}
  end

  @impl true
  def handle_call({:get, job_key}, _from, %{storage_id: storage_id} = state) do
    result =
      case :ets.lookup(storage_id, job_key) do
        [] -> {:error, :not_registered}
        [{_, job}] -> {:ok, job}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:set_idle, job}, _from, %{storage_id: storage_id} = state) do
    job = update(storage_id, Job.set_idle(job))

    {:reply, job, state}
  end

  @impl true
  def handle_call({:set_running, job}, _from, %{storage_id: storage_id} = state) do
    job = update(storage_id, Job.set_running(job))

    {:reply, job, state}
  end

  @impl true
  def handle_call({:store, job}, _from, %{storage_id: storage_id} = state) do
    {:reply, store(storage_id, job), state}
  end

  @impl true
  def handle_call({:update, job}, _from, %{storage_id: storage_id} = state) do
    {:reply, update(storage_id, job), state}
  end

  @impl true
  def handle_cast(:truncate, %{storage_id: storage_id} = state) do
    :ets.delete_all_objects(storage_id)

    {:noreply, state}
  end

  # Private functions

  defp update(storage_id, job) do
    true = :ets.update_element(storage_id, job.key, {2, job})

    job
  end

  defp store(storage_id, %Job{} = job) do
    if :ets.insert_new(storage_id, {job.key, job}) do
      {:ok, job}
    else
      {:error, :already_stored}
    end
  end
end
