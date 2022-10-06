# Cache

The Cache is an application for running periodic functions and
storing their results in an in-memory cache.

Architecture overview:

![Architecture overview](https://i.imgur.com/JfOAhNO.png)

It is an experiment, do not use it in production.

## Installation

```elixir
def deps do
  [
    {:cache, git: "https://github.com/rrrcompagnoni/cache.git", tag: "v1.0.0"}
  ]
end
```

## Usage

### Registering a periodic function execution

```elixir
    :ok = Cache.register_function(fn -> :timer.sleep(10_000); :rand.uniform(100) end, "rand_number", 5_000, 1_000)
```

### Fetching an entry from the Cache

```elixir
  Cache.get("rand_number") # Default timeout of 30 seconds.
```
