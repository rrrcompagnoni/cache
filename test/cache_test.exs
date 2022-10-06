defmodule CacheTest do
  use ExUnit.Case, async: false

  setup %{job_key: job_key} do
    on_exit(fn ->
      if job_key do
        CacheTest.Helper.terminate_job(job_key)
      end

      CacheTest.Helper.truncate_jobs()
      CacheTest.Helper.truncate_cache()
    end)

    :ok
  end

  describe "register_function/4" do
    @tag job_key: "rand"
    test "register a function and start the first cache computation" do
      test_pid = self()

      scheduled_function = fn ->
        Process.send(test_pid, :scheduled_function_called, [])

        :rand.uniform()
      end

      assert :ok = Cache.register_function(scheduled_function, "rand", 5_000, 1_000)

      assert_receive :scheduled_function_called
    end

    @tag job_key: "rand"
    test "does not register duplicated functions" do
      assert :ok = Cache.register_function(fn -> :ok end, "rand", 5_000, 1_000)

      assert {:error, :already_registered} =
               Cache.register_function(fn -> :ok end, "rand", 5_000, 1_000)
    end
  end

  describe "get/2" do
    @tag job_key: nil
    test "returns the cache entry if stored" do
      Cache.store("stored_entry", 55)

      assert {:ok, 55} = Cache.get("stored_entry")
    end

    @tag job_key: nil
    test "returns not registered when there is no such a value for a key" do
      assert {:error, :not_registered} = Cache.get("unregistered_entry")
    end

    @tag job_key: "timeout"
    test "returns timeout when there was not a chance to compute the cache entry" do
      :ok =
        Cache.register_function(
          fn ->
            :timer.sleep(200)
            30
          end,
          "timeout",
          5_000,
          3_000
        )

      {:error, :timeout} = Cache.get("timeout", 100)
    end

    @tag job_key: "wait"
    test "return the cache entry after waiting for cache computation" do
      :ok =
        Cache.register_function(
          fn ->
            :timer.sleep(100)
            30
          end,
          "wait",
          5_000,
          3_000
        )

      assert {:ok, 30} = Cache.get("wait", 200)
    end

    @tag job_key: "concurrent_calls"
    test "does not block concurrent calls" do
      :ok =
        Cache.register_function(
          fn ->
            :timer.sleep(100)
            30
          end,
          "concurrent_calls",
          5_000,
          3_000
        )

      task_1 =
        Task.Supervisor.async(Cache.TaskSupervisor, fn ->
          Cache.get("concurrent_calls", 150)
        end)

      task_2 =
        Task.Supervisor.async(Cache.TaskSupervisor, fn ->
          Cache.get("concurrent_calls", 250)
        end)

      task_3 =
        Task.Supervisor.async(Cache.TaskSupervisor, fn ->
          Cache.get("concurrent_calls", 10)
        end)

      assert [
               {_, {:ok, {:ok, task_1_result}}},
               {_, {:ok, {:ok, task_2_result}}},
               {_, {:ok, task_3_result}}
             ] = Task.yield_many([task_1, task_2, task_3], 300)

      assert [30, 30, {:error, :timeout}] = [task_1_result, task_2_result, task_3_result]
    end
  end
end
