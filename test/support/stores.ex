defmodule PeriodicalRedisTest.Stores do
  @moduledoc false

  # The stores the suite runs against: this package's docker-compose.yml
  # services unless PERIODICAL_REDIS_URLS names others.

  @defaults "redis=redis://localhost:6390,keydb=redis://localhost:6391"

  @doc false
  @spec all() :: [{String.t(), String.t()}]
  def all do
    "PERIODICAL_REDIS_URLS"
    |> System.get_env(@defaults)
    |> String.split(",", trim: true)
    |> Enum.map(fn entry ->
      case String.split(entry, "=", parts: 2) do
        [label, url] -> {label, url}
        [url] -> {url, url}
      end
    end)
  end
end

defmodule PeriodicalRedisTest.Callbacks do
  @moduledoc false

  @doc false
  @spec record(Periodical.Trigger.t(), pid(), term()) :: :ok
  def record(trigger, recipient, label) do
    send(recipient, {:ran, label, Node.self(), trigger.scheduled_at, System.os_time(:millisecond)})
    :ok
  end
end

defmodule PeriodicalRedisTest.Instance do
  @moduledoc false

  # Starts a Redix connection on a peer node, kept alive by an unlinked holder.
  @doc false
  @spec start_redix(String.t()) :: :ok
  def start_redix(url) do
    parent = self()

    spawn(fn ->
      {:ok, _pid} = Redix.start_link(url, name: PeriodicalRedisTest.Redix)
      send(parent, :redix_started)
      Process.sleep(:infinity)
    end)

    receive do
      :redix_started -> :ok
    after
      5_000 -> raise "Redix did not start"
    end
  end
end
