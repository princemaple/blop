defmodule Blop.MockSocket do
  import Kernel, except: [send: 2]

  @doc """
  Connects to a mock server.
  opts[:server_pid] can specify the PID of the mock server.
  """
  def connect(_host, _port, opts) do
    pid = Keyword.get(opts, :server_pid)
    {:ok, pid}
  end

  def send(pid, data) do
    Process.send(pid, {:socket_send, data}, [])
    :ok
  end

  def recv(pid, _length \\ 0) do
    Process.send(pid, {:socket_recv, self()}, [])

    receive do
      {:socket_reply, data} -> {:ok, data}
    after
      1000 -> {:error, :timeout}
    end
  end
end
