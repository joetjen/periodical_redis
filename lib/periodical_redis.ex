defmodule PeriodicalRedis do
  @moduledoc """
  A `Periodical.Coordinator` that keeps claims in Redis or KeyDB.

  Every instance that shares a named Periodical schedule claims each run with
  one atomic command,

      SET <prefix><key> <token> NX PX <ttl_ms>

  and the instance whose `SET` succeeds runs the callback. The lease expires
  on the Redis server's clock, so the instances' own clock skew does not
  affect it. Nothing needs cleaning up: expired claims disappear by
  themselves.

  ## Configuration

  Start a `Redix` connection in your supervision tree and name it:

      children = [
        {Redix, {System.fetch_env!("REDIS_URL"), [name: MyApp.Redix]}},
        # ...
      ]

      config :periodical, Periodical.Config,
        coordinator: {PeriodicalRedis, connection: MyApp.Redix}

  Options:

  - `:connection` (required) — the `Redix` connection: a registered name or pid.
  - `:prefix` — prepended to every key; `"periodical:"` by default. Give each
    application sharing a Redis its own prefix if their schedule names could
    collide.
  - `:timeout` — milliseconds to wait for Redis; 5 000 by default.

  The connection must be started before Periodical's scheduler fires its first
  coordinated occurrence. A connection that is down makes claims fail with an
  error, which Periodical's `:coordinator_error` policy handles.

  ## KeyDB

  KeyDB speaks the same protocol and supports the same commands, including
  the `EVAL` used to renew a lease, so the configuration is identical. With
  active replication between KeyDB masters, a claim is only as atomic as the
  replication: point all instances at the same master.

  ## Renewal

  `renew/2` extends a lease only while it still holds this claim's token,
  checked and extended in one Lua script, so it never extends a lease that
  expired and was won by another instance in between.
  """

  alias Periodical.Coordinator.Claim

  @behaviour Periodical.Coordinator

  @default_prefix "periodical:"
  @default_timeout_ms 5_000

  @renew_script """
  if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('PEXPIRE', KEYS[1], ARGV[2])
  else
    return 0
  end
  """

  ##
  ## Callback Implementations
  ##

  @doc """
  Claims the lease with `SET NX PX`.

  Returns `:won` when the key was set, `:lost` when it already exists, and
  `{:error, reason}` when Redis could not be reached or answered with an error.
  """
  @impl Periodical.Coordinator
  @spec claim(Claim.t(), keyword()) :: :won | :lost | {:error, term()}
  def claim(%Claim{} = claim, options) do
    command = ["SET", redis_key(claim, options), claim.token, "NX", "PX", Integer.to_string(claim.ttl_ms)]

    case Redix.command(connection(options), command, timeout: timeout(options)) do
      {:ok, "OK"} -> :won
      {:ok, nil} -> :lost
      {:ok, other} -> {:error, {:unexpected_reply, other}}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Extends the lease to `claim.ttl_ms` from now while the key still holds this claim's token.

  Returns `:lost` when the key expired or now belongs to another claim.
  """
  @impl Periodical.Coordinator
  @spec renew(Claim.t(), keyword()) :: :ok | :lost | {:error, term()}
  def renew(%Claim{} = claim, options) do
    command = ["EVAL", @renew_script, "1", redis_key(claim, options), claim.token, Integer.to_string(claim.ttl_ms)]

    case Redix.command(connection(options), command, timeout: timeout(options)) do
      {:ok, 1} -> :ok
      {:ok, 0} -> :lost
      {:ok, other} -> {:error, {:unexpected_reply, other}}
      {:error, error} -> {:error, error}
    end
  end

  ##
  ## Public API
  ##

  @doc """
  Returns the Redis key a claim is stored under.

      iex> claim = %Periodical.Coordinator.Claim{key: "abc", name: :x, scheduled_at: ~U[2026-01-01 00:00:00Z], token: "t", ttl_ms: 1}
      iex> PeriodicalRedis.redis_key(claim, [])
      "periodical:abc"
      iex> PeriodicalRedis.redis_key(claim, prefix: "billing:")
      "billing:abc"
  """
  @spec redis_key(Claim.t(), keyword()) :: String.t()
  def redis_key(%Claim{key: key}, options), do: Keyword.get(options, :prefix, @default_prefix) <> key

  ##
  ## Private Functions
  ##

  # Reads the required connection option, failing the claim clearly when it is missing.
  @spec connection(keyword()) :: Redix.connection()
  defp connection(options), do: Keyword.fetch!(options, :connection)

  @spec timeout(keyword()) :: timeout()
  defp timeout(options), do: Keyword.get(options, :timeout, @default_timeout_ms)
end
