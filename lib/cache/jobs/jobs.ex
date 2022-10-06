defmodule Cache.Jobs do
  alias Cache.Jobs.Job

  alias Cache.Jobs.Storage

  @doc """
  Store a Job in the jobs storage.
  """
  @spec store(Job.t()) :: {:error, :already_stored} | {:ok, Job.t()}
  defdelegate store(job), to: Storage

  @doc """
  Get a Job from the jobs storage.
  """
  @spec get(binary()) :: {:error, :not_registered} | {:ok, Job.t()}
  defdelegate get(job_key), to: Storage

  @doc """
  Set the Job state to running
  in the jobs storage.
  """
  @spec set_running(Job.t()) :: Job.t()
  defdelegate set_running(job), to: Storage

  @doc """
  Set the Job state to idle
  in the jobs storage.
  """
  @spec set_idle(Job.t()) :: Job.t()
  defdelegate set_idle(job), to: Storage

  @doc """
  Update a job in the storage.
  """
  @spec update(Job.t()) :: Job.t()
  defdelegate update(job), to: Storage

  @doc """
  Runs a given job.

  A job function seeded may or may not raise errors.
  The run function makes sure even in an exception scenario
  a uniform error tuple returned with the exception dump.
  """
  @spec run(Job.t()) :: {:ok, any()} | {:error, Exception.t()}
  def run(job = %Job{}) do
    result =
      try do
        value = job.function.()

        {:ok, value}
      rescue
        e -> {:error, e}
      end

    result
  end
end
