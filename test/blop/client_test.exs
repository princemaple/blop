defmodule Blop.ClientTest do
  use ExUnit.Case
  alias Blop.Client

  defmodule MockServer do
    def start_link do
      Task.start_link(fn -> loop([]) end)
    end

    defp loop(state) do
      receive do
        {:socket_recv, caller} ->
          # If we have a queued response, send it
          case state do
            [head | tail] ->
              send(caller, {:socket_reply, head})
              loop(tail)

            [] ->
              # Wait for more instructions or hang?
              # For now, let's reply with empty if nothing, to avoid timeout?
              # Or better, the test should have queued it.
              send(caller, {:socket_reply, ""})
              loop(state)
          end

        {:socket_send, _data} ->
          # Record sent data?
          # Send back to test process if we want to assert?
          # We can forward to a "controller" pid if stored in state.
          loop(state)

        {:queue_response, response} ->
          loop(state ++ [response])

        {:set_controller, _pid} ->
          # This allows verifying sent messages
          # TODO: store pid to forward messages
          loop(state)
      end
    end
  end

  # Better Mock Server driven by the Test Process
  def start_server do
    test_pid = self()
    Task.start_link(fn -> server_loop(test_pid) end)
  end

  defp server_loop(test_pid) do
    receive do
      {:socket_recv, caller} ->
        # Ask test what to reply
        send(test_pid, {:server_get_reply, caller})
        # Test will reply to caller directly or tell us what to reply
        server_loop(test_pid)

      {:socket_send, data} ->
        # Tell test what was received
        send(test_pid, {:server_received, data})
        server_loop(test_pid)
    end
  end

  test "append sends correct commands" do
    {:ok, server_pid} = start_server()

    # Start Client
    # Client init will loop receiving capability.
    # We must be ready to provide it.

    # Need to handle the init sequence asynchronously or ensure Client doesn't block forever.
    # Client.new -> Agent.start_link -> init -> imap_receive_raw -> Socket.recv.

    # We start start_server which forwards requests to us.

    # Start Client in a Task so we can handle the interaction?
    task =
      Task.async(fn ->
        Client.new(
          host: "test",
          socket_module: Blop.MockSocket,
          "Elixir.Blop.MockSocket": [server_pid: server_pid]
        )
      end)

    # 1. Expect capability request (init)
    assert_receive {:server_get_reply, caller}
    send(caller, {:socket_reply, "* OK [CAPABILITY IMAP4rev1] MockServer ready\r\n"})

    {:ok, client} = Task.await(task)

    # Hack: set logged_in to true since we didn't do login
    Agent.update(client, fn state -> Map.put(state, :logged_in, true) end)

    # 2. Call Append
    # Client.append(client, "INBOX", "Body Content", [:Seen], "25-Dec-2025 10:00:00 +0000")
    # This runs in test process.
    # It calls do_append -> send -> recv -> send -> recv.

    append_task =
      Task.async(fn ->
        Client.append(client, "INBOX", "Body Content", ["\\Seen"], "25-Dec-2025 10:00:00 +0000")
      end)

    # 3. Expect Command
    assert_receive {:server_received, cmd}
    # "EX2 APPEND \"INBOX\" (\\Seen) \"25-Dec-2025 10:00:00 +0000\" {12}\r\n"
    # Note: Tag is EX2 because EX1 was capability? No, capability was untagged receive.
    # Client tag starts at 1. `exec` increments.
    # `do_append` increments.
    # Wait, `client.tag_number` starts at 1. `do_append` uses `tag_number + 1` -> 2.
    assert cmd =~ ~r/EX\d+ APPEND "INBOX" \(\\Seen\) "25-Dec-2025 10:00:00 \+0000" \{12\}\r\n/
    [tag, _] = String.split(cmd, " ", parts: 2)

    # 4. Client waits for continuation.
    assert_receive {:server_get_reply, caller}
    send(caller, {:socket_reply, "+ go ahead\r\n"})

    # 5. Expect Content
    assert_receive {:server_received, content}
    assert content == "Body Content\r\n"

    # 6. Client waits for final response
    assert_receive {:server_get_reply, caller}
    send(caller, {:socket_reply, "#{tag} OK APPEND completed\r\n"})

    # 7. Await result
    result = Task.await(append_task)
    assert {:ok, _} = result

    # Verify parsing if possible, Client.append returns Response.extract() which might be :ok or list.
    # Response.extract usually returns {:ok, ...} or error.
  end
end
