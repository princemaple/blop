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

  describe "commands" do
    setup do
      {:ok, server_pid} = start_server()

      task =
        Task.async(fn ->
          Client.new(
            host: "test",
            socket_module: Blop.MockSocket,
            "Elixir.Blop.MockSocket": [server_pid: server_pid]
          )
        end)

      assert_receive {:server_get_reply, caller}
      send(caller, {:socket_reply, "* OK [CAPABILITY IMAP4rev1] MockServer ready\r\n"})

      {:ok, client} = Task.await(task)
      {:ok, client: client, server_pid: server_pid}
    end

    test "login", %{client: client} do
      login_task = Task.async(fn -> Client.login(client, "user", "pass") end)

      assert_receive {:server_received, cmd}
      assert cmd =~ ~r/EX\d+ LOGIN user pass\r\n/
      [tag, _] = String.split(cmd, " ", parts: 2)

      assert_receive {:server_get_reply, caller}
      send(caller, {:socket_reply, "#{tag} OK LOGIN completed\r\n"})

      assert :ok = Task.await(login_task)
      assert Client.info(client).logged_in
    end

    test "list", %{client: client} do
      # Mock login state
      Agent.update(client, fn state -> Map.put(state, :logged_in, true) end)

      list_task = Task.async(fn -> Client.list(client) end)

      assert_receive {:server_received, cmd}
      assert cmd =~ ~r/EX\d+ LIST "" \*\r\n/
      [tag, _] = String.split(cmd, " ", parts: 2)

      assert_receive {:server_get_reply, caller}

      send(
        caller,
        {:socket_reply,
         "* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n#{tag} OK LIST completed\r\n"}
      )

      result = Task.await(list_task)
      assert [%Blop.Mailbox{name: "INBOX"}] = result
    end

    test "select", %{client: client} do
      Agent.update(client, fn state ->
        state
        |> Map.put(:logged_in, true)
        |> Map.put(:mailboxes, [%Blop.Mailbox{name: "INBOX"}])
      end)

      select_task = Task.async(fn -> Client.select(client, "INBOX") end)

      assert_receive {:server_received, cmd}
      assert cmd =~ ~r/EX\d+ SELECT "INBOX"\r\n/
      [tag, _] = String.split(cmd, " ", parts: 2)

      assert_receive {:server_get_reply, caller}

      send(
        caller,
        {:socket_reply,
         "* 172 EXISTS\r\n* 1 RECENT\r\n#{tag} OK [READ-WRITE] SELECT completed\r\n"}
      )

      result = Task.await(select_task)
      assert %Blop.Mailbox{name: "INBOX", exists: 172, recent: 1} = result
      assert Client.info(client, :selected_mailbox).name == "INBOX"
    end

    test "append", %{client: client} do
      Agent.update(client, fn state -> Map.put(state, :logged_in, true) end)

      append_task =
        Task.async(fn ->
          Client.append(client, "INBOX", "Body Content", ["\\Seen"], "25-Dec-2025 10:00:00 +0000")
        end)

      assert_receive {:server_received, cmd}
      assert cmd =~ ~r/EX\d+ APPEND "INBOX" \(\\Seen\) "25-Dec-2025 10:00:00 \+0000" \{12\}\r\n/
      [tag, _] = String.split(cmd, " ", parts: 2)

      assert_receive {:server_get_reply, caller}
      send(caller, {:socket_reply, "+ go ahead\r\n"})

      assert_receive {:server_received, content}
      assert content == "Body Content\r\n"

      assert_receive {:server_get_reply, caller}
      send(caller, {:socket_reply, "#{tag} OK APPEND completed\r\n"})

      assert {:ok, _} = Task.await(append_task)
    end
  end
end
