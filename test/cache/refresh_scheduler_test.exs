defmodule Cache.RefreshRefreshSchedulerTest do
  use ExUnit.Case, async: false

  alias Cache.{
    Jobs,
    Jobs.Job,
    RefreshScheduler
  }

  setup_all do
    on_exit(fn ->
      CacheTest.Helper.truncate_jobs()
    end)

    :ok
  end

  describe "start/1" do
    test "sets in the job the scheduler PID" do
      job = %Job{
        function: fn -> :rand.uniform(100) end,
        ttl: 10_000,
        key: "rand_number",
        refresh_interval: 30_000,
        scheduler_pid: nil,
        executed_at: nil
      }

      {:ok, job} = Jobs.store(job)

      job = RefreshScheduler.start(job)

      assert is_pid(job.scheduler_pid)
    end
  end

  describe "handle_cast/2 :start" do
    test "runs the job for the first time" do
      job = %Job{
        function: fn -> :rand.uniform(100) end,
        ttl: 10_000,
        key: "rand_number_1",
        refresh_interval: 30_000,
        scheduler_pid: nil,
        executed_at: nil
      }

      {:ok, job} = Jobs.store(job)

      assert {:noreply, {%Job{executed_at: %DateTime{}}, []}} =
               RefreshScheduler.handle_cast(
                 {:start, fn -> RefreshScheduler.schedule_next_run(job) end},
                 {job, []}
               )
    end

    test "schedule the next run" do
      job = %Job{
        function: fn -> :rand.uniform(100) end,
        ttl: 10_000,
        key: "rand_number_2",
        refresh_interval: 30_000,
        scheduler_pid: nil,
        executed_at: nil
      }

      {:ok, job} = Jobs.store(job)

      next_run_fn = fn ->
        Process.send(self(), :next_run_called, [])

        RefreshScheduler.schedule_next_run(job)
      end

      RefreshScheduler.handle_cast({:start, next_run_fn}, {job, []})

      assert_receive :next_run_called
    end
  end

  describe "handle_cast/2 :subscribe" do
    test "includes a subscriber into the entry subscribers list" do
      job = %Job{
        function: fn -> :rand.uniform(100) end,
        ttl: 10_000,
        key: "rand_number",
        refresh_interval: 30_000,
        scheduler_pid: nil
      }

      test_pid = self()

      assert {:noreply, {^job, [^test_pid]}} =
               RefreshScheduler.handle_cast({:subscribe, test_pid}, {job, []})
    end
  end

  describe "handle_cast/2 {:broadcast, :job_run}" do
    test "clean the subscribers list after broadcasting" do
      job = %Job{
        function: fn -> :rand.uniform(100) end,
        ttl: 10_000,
        key: "rand_number",
        refresh_interval: 30_000,
        scheduler_pid: nil,
        executed_at: nil
      }

      entry_subscribers = [self()]

      assert {:noreply, {_job, []}} =
               RefreshScheduler.handle_cast(
                 {:broadcast, :job_run, fn _ -> :ok end},
                 {job, entry_subscribers}
               )
    end

    test "notify subscribers" do
      job = %Job{
        function: fn -> :rand.uniform(100) end,
        ttl: 10_000,
        key: "rand_number",
        refresh_interval: 30_000,
        scheduler_pid: nil,
        executed_at: nil
      }

      entry_subscribers = [self()]

      notification_fn = fn _subscriber ->
        Process.send(self(), :job_run_broadcast_received, [])
      end

      RefreshScheduler.handle_cast(
        {:broadcast, :job_run, notification_fn},
        {job, entry_subscribers}
      )

      assert_receive :job_run_broadcast_received
    end
  end

  describe "should_run?/2" do
    test "returns true for a job ttl expired" do
      now = DateTime.utc_now()
      ttl = 30_000
      executed_at = DateTime.add(now, -ttl, :millisecond)

      job = %Job{
        function: fn -> nil end,
        key: :job,
        ttl: ttl,
        refresh_interval: 10_000,
        executed_at: executed_at
      }

      assert RefreshScheduler.should_run?(job, now) == true
    end

    test "returns false for a job with ttl not expired" do
      now = DateTime.utc_now()
      ttl = 30_000
      executed_at = DateTime.add(now, -15_000, :millisecond)

      job = %Job{
        function: fn -> nil end,
        key: :job,
        ttl: ttl,
        refresh_interval: 10_000,
        executed_at: executed_at
      }

      assert RefreshScheduler.should_run?(job, now) == false
    end
  end

  describe "run/1" do
    test "store in cache the value of the :ok tuple" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: "nice",
        refresh_interval: 30_000
      }

      {:ok, _} = Jobs.store(job)

      RefreshScheduler.run(job)

      assert :nice = Cache.get_entry(job.key)
    end

    test "store in cache the raw result of an execution" do
      job = %Job{
        function: fn -> :nice end,
        ttl: 10_000,
        key: "nice_2",
        refresh_interval: 30_000
      }

      {:ok, _} = Jobs.store(job)

      RefreshScheduler.run(job)

      assert :nice = Cache.get_entry(job.key)
    end

    test "skip storing in cache the failure returning value of the job function execution" do
      job = %Job{
        function: fn -> {:error, :not_so_nice} end,
        ttl: 10_000,
        key: "not_so_nice",
        refresh_interval: 30_000
      }

      {:ok, _} = Jobs.store(job)

      RefreshScheduler.run(job)

      assert Cache.get_entry(job.key) == nil
    end

    test "skip storing in cache errors from exceptions" do
      job = %Job{
        function: fn -> raise "Bad error" end,
        ttl: 10_000,
        key: "bad_error",
        refresh_interval: 30_000
      }

      {:ok, _} = Jobs.store(job)

      RefreshScheduler.run(job)

      assert Cache.get_entry(job.key) == nil
    end

    test "set the executed_at attribute after execution" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: "nice_3",
        refresh_interval: 30_000,
        executed_at: nil
      }

      {:ok, _} = Jobs.store(job)

      assert %Job{executed_at: %DateTime{}} = RefreshScheduler.run(job)
    end

    test "move the job to the running state while running" do
      job = %Job{
        function: fn -> Jobs.get("nice_4") end,
        ttl: 10_000,
        key: "nice_4",
        refresh_interval: 30_000,
        executed_at: nil,
        state: :idle
      }

      {:ok, _} = Jobs.store(job)

      %Job{executed_at: %DateTime{}} = RefreshScheduler.run(job)

      cached_job = Cache.get_entry("nice_4")

      assert cached_job.state == :running
    end

    test "move the job to the idle state after stop running" do
      job = %Job{
        function: fn -> Jobs.get("nice_5") end,
        ttl: 10_000,
        key: "nice_5",
        refresh_interval: 30_000,
        executed_at: nil,
        state: :idle
      }

      {:ok, _} = Jobs.store(job)

      %Job{executed_at: %DateTime{}} = RefreshScheduler.run(job)

      cached_job = Cache.get_entry("nice_5")

      assert cached_job.state == :running

      {:ok, job_in_current_state} = Jobs.get("nice_5")

      assert job_in_current_state.state == :idle
    end
  end
end
