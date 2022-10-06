defmodule Cache do
  use GenServer
  require Logger

  alias Cache.{
    Entry,
    Jobs.Job,
    Jobs
  }

  @doc """
  Register a periodic function execution.

  Once a function gets registered a job is stored in the
  jobs storage and the first cache computation
  get started.

  Each function has its refresh scheduler process which
  refresh the cache value withing the refresh interval.
  """
  # This is a user face function. It only accepts keys in strings
  # to avoid reaching the Atom limitation.
  @spec register_function((() -> any()), binary(), pos_integer(), non_neg_integer()) ::
          :ok | {:error, :already_registered}
  def register_function(fun, key, ttl, refresh_interval)
      when is_function(fun, 0) and is_binary(key) and is_integer(ttl) and ttl > 0 and
             is_integer(refresh_interval) and
             refresh_interval < ttl do
    job = %Job{function: fun, key: key, ttl: ttl, refresh_interval: refresh_interval}

    with {:ok, job} <- Jobs.store(job),
         %Job{} <- Cache.RefreshScheduler.start(job) do
      :ok
    else
      {:error, :already_stored} -> {:error, :already_registered}
    end
  end

  @doc """
  Maybe fetch an entry from the Cache.

  It queries for an entry on Cache storage, returning immediately
  if found.

  If the entry is not stored. It looks for a cache computation in progress
  and wait until the timeout expires.

  Spawn a new process on every `get` request to avoid blocking the Cache process
  mailbox with requests waiting for timeout expiration.
  """
  @spec get(atom(), pos_integer()) :: {:ok, any()} | {:error, :not_registered | :timeout}
  def get(key, timeout \\ 30_000) when is_integer(timeout) and timeout > 0 do
    {:ok, pid} = DynamicSupervisor.start_child(Cache.Entries.DynamicSupervisor, {Entry, timeout})

    value = Entry.get(pid, key)

    :ok = DynamicSupervisor.terminate_child(Cache.Entries.DynamicSupervisor, pid)

    case value do
      {:error, _} = error -> error
      any -> {:ok, any}
    end
  end

  # Internal usage only

  @doc false
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc false
  def get_entry(key) do
    GenServer.call(__MODULE__, {:get_entry, key})
  end

  @doc false
  def store(key, value) do
    GenServer.cast(__MODULE__, {:store, {key, value}})
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
      :ets.new(:cache, [
        :set,
        :private,
        :named_table
      ])

    Logger.info("#{__MODULE__} started.")

    {:ok, %{storage_id: storage_id}}
  end

  @doc false
  @impl true
  def handle_call({:get_entry, key}, _from, %{storage_id: storage_id} = state) do
    result =
      case :ets.lookup(storage_id, key) do
        [] -> nil
        [{_, value}] -> value
      end

    {:reply, result, state}
  end

  @doc false
  @impl true
  def handle_cast({:store, {key, value}}, %{storage_id: storage_id} = state) do
    :ets.insert(storage_id, {key, value})

    {:noreply, state}
  end

  @doc false
  @impl true
  def handle_cast(:truncate, %{storage_id: storage_id} = state) do
    :ets.delete_all_objects(storage_id)

    {:noreply, state}
  end
end
