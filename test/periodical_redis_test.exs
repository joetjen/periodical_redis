defmodule PeriodicalRedisTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Periodical.Coordinator
  alias Periodical.Coordinator.Claim
  alias PeriodicalRedisTest.{Callbacks, Stores}

  doctest PeriodicalRedis

  for {label, url} <- Stores.all() do
    describe "#{label}" do
      @describetag store: label
      @url url

      setup do
        conn = start_supervised!({Redix, @url}, id: make_ref())
        {:ok, conn: conn, options: [connection: conn, prefix: "periodical_test:#{System.unique_integer([:positive])}:"]}
      end

      test "the first claim wins and later ones lose while the lease lasts", %{options: options} do
        assert :won = PeriodicalRedis.claim(claim(:job, 10_000), options)
        assert :lost = PeriodicalRedis.claim(claim(:job, 10_000), options)
        assert :won = PeriodicalRedis.claim(claim(:other_job, 10_000), options)
      end

      test "an expired lease can be claimed again", %{options: options} do
        assert :won = PeriodicalRedis.claim(claim(:job, 100), options)
        Process.sleep(150)
        assert :won = PeriodicalRedis.claim(claim(:job, 100), options)
      end

      test "the lease lives on the server with the requested ttl", %{conn: conn, options: options} do
        first = claim(:job, 5_000)
        assert :won = PeriodicalRedis.claim(first, options)
        key = PeriodicalRedis.redis_key(first, options)
        assert {:ok, token} = Redix.command(conn, ["GET", key])
        assert token == first.token
        assert {:ok, pttl} = Redix.command(conn, ["PTTL", key])
        assert pttl in 4_000..5_000
      end

      property "of any number of concurrent claims exactly one wins", %{options: options} do
        conns = for _ <- 1..4, do: start_supervised!({Redix, @url}, id: make_ref())

        check all(claimers <- integer(2..40), max_runs: 15) do
          name = {:concurrent, System.unique_integer([:positive])}

          results =
            1..claimers
            |> Task.async_stream(fn i ->
              PeriodicalRedis.claim(claim(name, 10_000), Keyword.put(options, :connection, Enum.at(conns, rem(i, 4))))
            end)
            |> Enum.map(fn {:ok, result} -> result end)

          assert Enum.count(results, &(&1 == :won)) == 1
          assert Enum.count(results, &(&1 == :lost)) == claimers - 1
        end
      end

      test "renew extends only the holder's lease", %{options: options} do
        mine = claim(:job, 150)
        assert :won = PeriodicalRedis.claim(mine, options)
        assert :lost = PeriodicalRedis.renew(%{claim(:job, 1_000) | token: "someone-else"}, options)
        assert :ok = PeriodicalRedis.renew(%{mine | ttl_ms: 1_000}, options)
        Process.sleep(250)
        assert :lost = PeriodicalRedis.claim(claim(:job, 100), options)
      end

      test "renew reports a lease that expired and was taken as lost", %{options: options} do
        mine = claim(:job, 50)
        assert :won = PeriodicalRedis.claim(mine, options)
        Process.sleep(80)
        assert :lost = PeriodicalRedis.renew(mine, options)
        assert :won = PeriodicalRedis.claim(claim(:job, 1_000), options)
        assert :lost = PeriodicalRedis.renew(mine, options)
      end

      test "Periodical runs a named schedule only while it wins", %{options: options} do
        restart_periodical(coordinator: {PeriodicalRedis, options})
        on_exit(fn -> restart_periodical([]) end)

        at = DateTime.add(DateTime.utc_now(), 40, :millisecond)
        assert {:ok, _id} = Periodical.once(at, Callbacks, :record, [self(), :free], name: :free)
        assert_receive {:ran, :free, _, ^at, _}, 1_000

        # Another instance holds the lease on this one.
        assert :won = PeriodicalRedis.claim(claim(:held, 10_000), options)
        assert {:ok, _id} = Periodical.once(soon(), Callbacks, :record, [self(), :held], name: :held)
        refute_receive {:ran, :held, _, _, _}, 300
      end
    end
  end

  test "an unreachable server is an error, not a loss" do
    conn = start_supervised!({Redix, host: "localhost", port: 1, sync_connect: false, backoff_max: 50})
    assert {:error, _reason} = PeriodicalRedis.claim(claim(:job, 1_000), connection: conn, timeout: 500)
    assert {:error, _reason} = PeriodicalRedis.renew(claim(:job, 1_000), connection: conn, timeout: 500)
  end

  defp claim(name, ttl_ms) do
    %Claim{
      key: Coordinator.key(name),
      name: name,
      scheduled_at: DateTime.utc_now(),
      token: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower),
      ttl_ms: ttl_ms
    }
  end

  defp soon, do: DateTime.add(DateTime.utc_now(), 40, :millisecond)

  defp restart_periodical(settings) do
    _ignored = Application.stop(:periodical)
    :ok = Application.put_env(:periodical, Periodical.Config, settings)
    {:ok, _applications} = Application.ensure_all_started(:periodical)
    :ok
  end
end
