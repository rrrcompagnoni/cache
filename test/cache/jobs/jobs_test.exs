defmodule Cache.JobsTest do
  use ExUnit.Case, async: true

  alias Cache.{
    Jobs,
    Jobs.Job
  }

  describe "run/1" do
    test "returns the :ok tuple for a successful execution" do
      job = %Job{
        function: fn -> {:ok, :nice} end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000
      }

      assert {:ok, {:ok, :nice}} = Jobs.run(job)
    end

    test "returns the :error tuple when an exception happens" do
      job = %Job{
        function: fn -> raise "Not so nice!" end,
        ttl: 10_000,
        key: :nice_function,
        refresh_interval: 30_000
      }

      assert {:error, %RuntimeError{message: "Not so nice!"}} = Jobs.run(job)
    end
  end
end
