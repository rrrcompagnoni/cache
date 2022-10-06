defmodule CacheTest.Helper do
  def terminate_job(job_key) do
    {:ok, job} = Cache.Jobs.get(job_key)

    :ok =
      DynamicSupervisor.terminate_child(
        Cache.RefreshScheduler.DynamicSupervisor,
        job.scheduler_pid
      )
  end

  def truncate_jobs(), do: Cache.Jobs.Storage.truncate()

  def truncate_cache(), do: Cache.truncate()
end

ExUnit.start()
