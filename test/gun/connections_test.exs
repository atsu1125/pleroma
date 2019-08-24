# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Gun.ConnectionsTest do
  use ExUnit.Case
  alias Pleroma.Gun.API
  alias Pleroma.Gun.Conn
  alias Pleroma.Gun.Connections

  setup_all do
    {:ok, _} = Registry.start_link(keys: :unique, name: API.Mock)
    :ok
  end

  setup do
    name = :test_gun_connections
    adapter = Application.get_env(:tesla, :adapter)
    Application.put_env(:tesla, :adapter, Tesla.Adapter.Gun)
    on_exit(fn -> Application.put_env(:tesla, :adapter, adapter) end)
    {:ok, pid} = Connections.start_link({name, [max_connections: 2, timeout: 10]})

    {:ok, name: name, pid: pid}
  end

  describe "alive?/2" do
    test "is alive", %{name: name} do
      assert Connections.alive?(name)
    end

    test "returns false if not started" do
      refute Connections.alive?(:some_random_name)
    end
  end

  test "opens connection and reuse it on next request", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)

    assert is_pid(conn)
    assert Process.alive?(conn)

    reused_conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)

    assert conn == reused_conn

    %Connections{
      conns: %{
        "http:some-domain.com:80" => %Conn{
          conn: ^conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "reuses connection based on protocol", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)
    assert is_pid(conn)
    assert Process.alive?(conn)

    https_conn = Connections.get_conn("https://some-domain.com", [genserver_pid: pid], name)

    refute conn == https_conn

    reused_https = Connections.get_conn("https://some-domain.com", [genserver_pid: pid], name)

    refute conn == reused_https

    assert reused_https == https_conn

    %Connections{
      conns: %{
        "http:some-domain.com:80" => %Conn{
          conn: ^conn,
          state: :up,
          waiting_pids: []
        },
        "https:some-domain.com:443" => %Conn{
          conn: ^https_conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "process gun_down message", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://gun_down.com", [genserver_pid: pid], name)

    refute conn

    %Connections{
      conns: %{
        "http:gun_down.com:80" => %Conn{
          conn: _,
          state: :down,
          waiting_pids: _
        }
      }
    } = Connections.get_state(name)
  end

  test "process gun_down message and then gun_up", %{name: name, pid: pid} do
    conn = Connections.get_conn("http://gun_down_and_up.com", [genserver_pid: pid], name)

    refute conn

    %Connections{
      conns: %{
        "http:gun_down_and_up.com:80" => %Conn{
          conn: _,
          state: :down,
          waiting_pids: _
        }
      }
    } = Connections.get_state(name)

    conn = Connections.get_conn("http://gun_down_and_up.com", [genserver_pid: pid], name)

    assert is_pid(conn)
    assert Process.alive?(conn)

    %Connections{
      conns: %{
        "http:gun_down_and_up.com:80" => %Conn{
          conn: _,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)
  end

  test "async processes get same conn for same domain", %{name: name, pid: pid} do
    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)
        end)
      end

    tasks_with_results = Task.yield_many(tasks)

    results =
      Enum.map(tasks_with_results, fn {task, res} ->
        res || Task.shutdown(task, :brutal_kill)
      end)

    conns = for {:ok, value} <- results, do: value

    %Connections{
      conns: %{
        "http:some-domain.com:80" => %Conn{
          conn: conn,
          state: :up,
          waiting_pids: []
        }
      }
    } = Connections.get_state(name)

    assert Enum.all?(conns, fn res -> res == conn end)
  end

  test "remove frequently used", %{name: name, pid: pid} do
    Connections.get_conn("https://some-domain.com", [genserver_pid: pid], name)

    for _ <- 1..4 do
      Connections.get_conn("http://some-domain.com", [genserver_pid: pid], name)
    end

    %Connections{
      conns: %{
        "http:some-domain.com:80" => %Conn{
          conn: _,
          state: :up,
          waiting_pids: []
        },
        "https:some-domain.com:443" => %Conn{
          conn: _,
          state: :up,
          waiting_pids: []
        }
      },
      opts: [max_connections: 2, timeout: 10]
    } = Connections.get_state(name)

    conn = Connections.get_conn("http://another-domain.com", [genserver_pid: pid], name)

    %Connections{
      conns: %{
        "http:another-domain.com:80" => %Conn{
          conn: ^conn,
          state: :up,
          waiting_pids: []
        },
        "http:some-domain.com:80" => %Conn{
          conn: _,
          state: :up,
          waiting_pids: []
        }
      },
      opts: [max_connections: 2, timeout: 10]
    } = Connections.get_state(name)
  end

  describe "integration test" do
    @describetag :integration

    test "opens connection and reuse it on next request", %{name: name} do
      api = Pleroma.Config.get([API])
      Pleroma.Config.put([API], API.Gun)
      on_exit(fn -> Pleroma.Config.put([API], api) end)
      conn = Connections.get_conn("http://httpbin.org", [], name)

      assert is_pid(conn)
      assert Process.alive?(conn)

      reused_conn = Connections.get_conn("http://httpbin.org", [], name)

      assert conn == reused_conn

      %Connections{
        conns: %{
          "http:httpbin.org:80" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        }
      } = Connections.get_state(name)
    end

    test "opens ssl connection and reuse it on next request", %{name: name} do
      api = Pleroma.Config.get([API])
      Pleroma.Config.put([API], API.Gun)
      on_exit(fn -> Pleroma.Config.put([API], api) end)
      conn = Connections.get_conn("https://httpbin.org", [], name)

      assert is_pid(conn)
      assert Process.alive?(conn)

      reused_conn = Connections.get_conn("https://httpbin.org", [], name)

      assert conn == reused_conn

      %Connections{
        conns: %{
          "https:httpbin.org:443" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        }
      } = Connections.get_state(name)
    end

    test "remove frequently used", %{name: name, pid: pid} do
      api = Pleroma.Config.get([API])
      Pleroma.Config.put([API], API.Gun)
      on_exit(fn -> Pleroma.Config.put([API], api) end)

      Connections.get_conn("https://www.google.com", [genserver_pid: pid], name)

      for _ <- 1..4 do
        Connections.get_conn("https://httpbin.org", [genserver_pid: pid], name)
      end

      %Connections{
        conns: %{
          "https:httpbin.org:443" => %Conn{
            conn: _,
            state: :up,
            waiting_pids: []
          },
          "https:www.google.com:443" => %Conn{
            conn: _,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)

      conn = Connections.get_conn("http://httpbin.org", [genserver_pid: pid], name)

      %Connections{
        conns: %{
          "http:httpbin.org:80" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          },
          "https:httpbin.org:443" => %Conn{
            conn: _,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)
    end

    test "remove earlier used", %{name: name, pid: pid} do
      api = Pleroma.Config.get([API])
      Pleroma.Config.put([API], API.Gun)
      on_exit(fn -> Pleroma.Config.put([API], api) end)

      Connections.get_conn("https://www.google.com", [genserver_pid: pid], name)
      Connections.get_conn("https://www.google.com", [genserver_pid: pid], name)

      Process.sleep(1_000)
      Connections.get_conn("https://httpbin.org", [genserver_pid: pid], name)
      Connections.get_conn("https://httpbin.org", [genserver_pid: pid], name)

      %Connections{
        conns: %{
          "https:httpbin.org:443" => %Conn{
            conn: _,
            state: :up,
            waiting_pids: []
          },
          "https:www.google.com:443" => %Conn{
            conn: _,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)

      Process.sleep(1_000)
      conn = Connections.get_conn("http://httpbin.org", [genserver_pid: pid], name)

      %Connections{
        conns: %{
          "http:httpbin.org:80" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          },
          "https:httpbin.org:443" => %Conn{
            conn: _,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)
    end
  end

  describe "with proxy usage" do
    test "proxy as ip", %{name: name, pid: pid} do
      conn =
        Connections.get_conn(
          "http://proxy_string.com",
          [genserver_pid: pid, proxy: {{127, 0, 0, 1}, 8123}],
          name
        )

      %Connections{
        conns: %{
          "http:proxy_string.com:80" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)

      reused_conn =
        Connections.get_conn(
          "http://proxy_string.com",
          [genserver_pid: pid, proxy: {{127, 0, 0, 1}, 8123}],
          name
        )

      assert reused_conn == conn
    end

    test "proxy as host", %{name: name, pid: pid} do
      conn =
        Connections.get_conn(
          "http://proxy_tuple_atom.com",
          [genserver_pid: pid, proxy: {'localhost', 9050}],
          name
        )

      %Connections{
        conns: %{
          "http:proxy_tuple_atom.com:80" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)

      reused_conn =
        Connections.get_conn(
          "http://proxy_tuple_atom.com",
          [genserver_pid: pid, proxy: {'localhost', 9050}],
          name
        )

      assert reused_conn == conn
    end

    test "proxy as ip and ssl", %{name: name, pid: pid} do
      conn =
        Connections.get_conn(
          "https://proxy_string.com",
          [genserver_pid: pid, proxy: {{127, 0, 0, 1}, 8123}],
          name
        )

      %Connections{
        conns: %{
          "https:proxy_string.com:443" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)

      reused_conn =
        Connections.get_conn(
          "https://proxy_string.com",
          [genserver_pid: pid, proxy: {{127, 0, 0, 1}, 8123}],
          name
        )

      assert reused_conn == conn
    end

    test "proxy as host and ssl", %{name: name, pid: pid} do
      conn =
        Connections.get_conn(
          "https://proxy_tuple_atom.com",
          [genserver_pid: pid, proxy: {'localhost', 9050}],
          name
        )

      %Connections{
        conns: %{
          "https:proxy_tuple_atom.com:443" => %Conn{
            conn: ^conn,
            state: :up,
            waiting_pids: []
          }
        },
        opts: [max_connections: 2, timeout: 10]
      } = Connections.get_state(name)

      reused_conn =
        Connections.get_conn(
          "https://proxy_tuple_atom.com",
          [genserver_pid: pid, proxy: {'localhost', 9050}],
          name
        )

      assert reused_conn == conn
    end
  end

  describe "crf/3" do
    setup do
      crf = Connections.crf(1, 10, 1)
      {:ok, crf: crf}
    end

    test "more used will have crf higher", %{crf: crf} do
      # used 3 times
      crf1 = Connections.crf(1, 10, crf)
      crf1 = Connections.crf(1, 10, crf1)

      # used 2 times
      crf2 = Connections.crf(1, 10, crf)

      assert crf1 > crf2
    end

    test "recently used will have crf higher on equal references", %{crf: crf} do
      # used 4 sec ago
      crf1 = Connections.crf(3, 10, crf)

      # used 3 sec ago
      crf2 = Connections.crf(4, 10, crf)

      assert crf1 > crf2
    end

    test "equal crf on equal reference and time", %{crf: crf} do
      # used 2 times
      crf1 = Connections.crf(1, 10, crf)

      # used 2 times
      crf2 = Connections.crf(1, 10, crf)

      assert crf1 == crf2
    end

    test "recently used will have higher crf", %{crf: crf} do
      crf1 = Connections.crf(2, 10, crf)
      crf1 = Connections.crf(1, 10, crf1)

      crf2 = Connections.crf(3, 10, crf)
      crf2 = Connections.crf(4, 10, crf2)
      assert crf1 > crf2
    end
  end
end
