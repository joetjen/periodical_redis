# PeriodicalRedis

A [Periodical](https://hex.pm/packages/periodical) coordinator that keeps
claims in Redis or KeyDB, so a schedule registered on several instances runs
each occurrence on only one of them.

Every instance claims the run with one atomic `SET key token NX PX ttl`; the
instance whose `SET` succeeds runs the callback, and the others skip the
occurrence. Leases expire on the Redis server's clock and clean up after
themselves.

## Installation

```elixir
def deps do
  [
    {:periodical, "~> 0.2"},
    {:periodical_redis, "~> 0.1"}
  ]
end
```

## Usage

Start a named `Redix` connection before Periodical fires, and configure it as
the coordinator:

```elixir
# application.ex
children = [
  {Redix, {System.fetch_env!("REDIS_URL"), [name: MyApp.Redix]}}
  # ...
]

# config/runtime.exs
config :periodical, Periodical.Config,
  coordinator: {PeriodicalRedis, connection: MyApp.Redix, prefix: "my_app:periodical:"}
```

Then name the schedules that should run once across the cluster:

```elixir
Periodical.every("FREQ=MINUTELY;INTERVAL=5", MyApp.Cleanup, :run, [], name: :cleanup)
```

| Option | Default | Purpose |
| --- | --- | --- |
| `:connection` | required | `Redix` connection name or pid |
| `:prefix` | `"periodical:"` | Prepended to every key |
| `:timeout` | `5000` | Milliseconds to wait for Redis |

Lease length, strategies, failure handling and which schedules are coordinated
are Periodical's: see `Periodical.Coordinator`.

## KeyDB

KeyDB works unchanged. With active-active replication, point all instances at
the same master: a claim is only as atomic as the server that decides it.

## Development

The suite runs against a real Redis and KeyDB:

```sh
docker compose up -d
mix test
```

`PERIODICAL_REDIS_URLS=redis=redis://host:6379,keydb=redis://host:6380`
points it elsewhere. Until the Periodical release with
`Periodical.Coordinator` is on Hex, add `PERIODICAL_PATH=../periodical` to
build against a checkout.

## License

Apache License 2.0; see [LICENSE](LICENSE).
