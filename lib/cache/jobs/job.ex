defmodule Cache.Jobs.Job do
  @keys [:function, :key, :ttl, :refresh_interval]
  @enforce_keys @keys
  defstruct @keys ++ [executed_at: nil, state: :idle, scheduler_pid: nil]

  @type t() :: %__MODULE__{
          function: fun(),
          key: String.t(),
          ttl: non_neg_integer(),
          refresh_interval: non_neg_integer(),
          executed_at: nil | DateTime.t(),
          state: atom(),
          scheduler_pid: pid() | nil
        }

  @doc false
  def set_idle(%__MODULE__{} = job) do
    %{job | state: :idle}
  end

  @doc false
  def set_running(%__MODULE__{} = job) do
    %{job | state: :running}
  end
end
