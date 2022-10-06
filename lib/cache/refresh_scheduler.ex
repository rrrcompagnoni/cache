defmodule Cache.RefreshScheduler do
  use GenServer

  alias Cache.{
    Jobs,
    Jobs.Job
  }

  # Internal usage

  @doc false
  def start_link(%Job{} = job) do
    GenServer.start_link(__MODULE__, job)
  end

  @doc """
  Start a new scheduler for a given process.

  Spawn a new process to execute from time to time
  the function registered.

  Starting a new scheduler, set the scheduler PID
  in the job and call for the first cache computation.

  The job scheduler keeps online as much as the application stays alive.
  There is no process shutdown available.
  """
  @spec start(Job.t()) :: Job.t()
  def start(%Job{} = job) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Cache.RefreshScheduler.DynamicSupervisor,
        {__MODULE__, job}
      )

    job = Jobs.update(%{job | scheduler_pid: pid})

    :ok = GenServer.cast(pid, {:start, fn -> schedule_next_run(job) end})

    job
  end

  @doc false
  def schedule_next_run(%Job{} = job),
    do: Process.send_after(job.scheduler_pid, :maybe_run, job.refresh_interval)

  @doc """
  Subscribe an Entry process to the subscribers list

  Like a pub/sub an Entry process can subscribe to
  the the :job_run event.
  """
  @spec subscribe(Job.t(), pid()) :: :ok
  def subscribe(%Job{} = job, subscriber_pid) when is_pid(subscriber_pid) do
    GenServer.cast(job.scheduler_pid, {:subscribe, subscriber_pid})
  end

  # A very limited broadcast function
  #
  # This broadcast function notify entry processes
  # subscribed to the :job_run event.
  #
  # It is a purpose built use case, a more
  # generic pub/sub relation should
  # take action in case of extension.
  @doc false
  def broadcast(event, %Job{} = job) do
    GenServer.cast(
      job.scheduler_pid,
      {:broadcast, event, fn subscriber -> Cache.Entry.notify(subscriber) end}
    )
  end

  @doc false
  def should_run?(%Job{} = job, %DateTime{} = utc_now) do
    DateTime.diff(utc_now, job.executed_at, :millisecond) >= job.ttl
  end

  @doc false
  def run(%Job{} = job) do
    job = %Job{state: :running} = Jobs.set_running(job)

    case Jobs.run(job) do
      {:ok, {:ok, value}} ->
        Cache.store(job.key, value)

      {:ok, {:error, _}} ->
        nil

      {:ok, value} ->
        Cache.store(job.key, value)

      {:error, _} ->
        nil
    end

    job = %Job{state: :idle} = Jobs.set_idle(%{job | executed_at: DateTime.utc_now()})

    broadcast(:job_run, job)

    job
  end

  # Callbacks

  @doc false
  @impl true
  def init(%Job{} = job) do
    {:ok, {%{job | scheduler_pid: self()}, []}}
  end

  @doc false
  @impl true
  def handle_cast({:start, next_run_fn}, {job, entry_subscribers})
      when is_function(next_run_fn) do
    job = run(job)

    next_run_fn.()

    {:noreply, {job, entry_subscribers}}
  end

  @doc false
  @impl true
  def handle_cast({:subscribe, pid}, {job, entry_subscribers}) do
    {:noreply, {job, [pid | entry_subscribers]}}
  end

  # Note: Entry subscribers
  # are short living process. To not increase
  # the scheduler memory usage over the time
  # all subscribers get discarded after broadcasting.
  @doc false
  @impl true
  def handle_cast({:broadcast, :job_run, notification_fn}, {job, entry_subscribers})
      when is_function(notification_fn, 1) do
    :ok = Enum.each(entry_subscribers, fn subscriber -> notification_fn.(subscriber) end)

    {:noreply, {job, []}}
  end

  @doc false
  @impl true
  def handle_info(:maybe_run, {job, entry_subscribers}) do
    job =
      if should_run?(job, DateTime.utc_now()) do
        run(job)
      else
        job
      end

    schedule_next_run(job)

    {:noreply, {job, entry_subscribers}}
  end
end
