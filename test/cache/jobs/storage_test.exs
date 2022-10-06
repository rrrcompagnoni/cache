defmodule Cache.Jobs.StorageTest do
  use ExUnit.Case, async: false

  alias Cache.Jobs.{
    Job,
    Storage
  }

  setup do
    on_exit(fn -> Storage.truncate() end)

    :ok
  end

  describe "store/1" do
    test "stores a job in storage" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000
      }

      assert {:ok, _job} = Storage.store(job)
    end

    test "does not store a job when there is a job within the same key" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000
      }

      assert {:ok, _job} = Storage.store(job)

      assert {:error, :already_stored} = Storage.store(job)
    end
  end

  describe "get/1" do
    test "returns the :ok tuple with the job when job is stored" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000
      }

      {:ok, _} = Storage.store(job)

      assert {:ok, %Job{key: :nice_function}} = Storage.get(job.key)
    end

    test "returns the :error tuple when job is not stored" do
      assert {:error, :not_registered} = Storage.get(:some_key)
    end
  end

  describe "set_running/1" do
    test "set the job to the running state" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000,
        state: :idle
      }

      {:ok, _} = Storage.store(job)

      assert %Job{state: :running} = Storage.set_running(job)

      assert {:ok, %Job{state: :running}} = Storage.get(job.key)
    end
  end

  describe "set_idle/1" do
    test "set the job to the idle state" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000,
        state: :running
      }

      {:ok, _} = Storage.store(job)

      assert %Job{state: :idle} = Storage.set_idle(job)

      assert {:ok, %Job{state: :idle}} = Storage.get(job.key)
    end
  end

  describe "update/1" do
    test "store the update in the job storage" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000,
        state: :running
      }

      {:ok, _} = Storage.store(job)

      Storage.update(%{job | state: :idle})

      assert {:ok, %Job{state: :idle}} = Storage.get(job.key)
    end
  end
end
