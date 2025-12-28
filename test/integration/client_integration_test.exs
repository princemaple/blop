defmodule Blop.ClientIntegrationTest do
  use ExUnit.Case
  alias Blop.Client

  @moduletag :integration

  # Default GreenMail IMAP port from docker-compose
  @port 3143
  @host "localhost"

  # GreenMail default credentials (or configured ones if different)
  # GreenMail defaults: user: login, pass: login ??
  # Actually greenmail/standalone often has login:login, or allows any.
  # Let's try creating a user first or assuming default.
  # docker-compose env: -Dgreenmail.auth.disabled -> so any user/pass works?
  # Yes "-Dgreenmail.auth.disabled" means no auth check.

  setup do
    # Ensure we use the real :ssl or :gen_tcp module
    # The default in Client.new is :ssl.
    # GreenMail unencrypted IMAP is on 3143.
    # We should use :gen_tcp usually for non-SSL, but Client keys off :socket_module.
    # Client defaults to :ssl.
    # We can pass `socket_module: :gen_tcp`?
    # Checking Client.new code:
    # `socket_module = Map.get(opts, :socket_module, :ssl)`
    # And then it uses that module to connect.

    {:ok, client} =
      Client.new(
        host: @host,
        port: @port,
        socket_module: :gen_tcp,
        gen_tcp: [:binary, active: false]
      )

    {:ok, client: client}
  end

  test "full lifecycle", %{client: client} do
    # 1. Login
    assert :ok = Client.login(client, "test@example.com", "password")
    assert Client.info(client).logged_in

    # Create mailbox since we are using a custom one (if CREATE is needed?)
    # Request.create exists. Do we have Client.create?
    # We might need to implement Client.create or use INBOX and hope we can clear it?
    # Or just ignore previous messages?
    # If we fetch 1:*, we get all.
    # If we Append, we get a UID or sequence number.
    # GreenMail auto-creates folder on APPEND? Usually invalid.
    # We need Client.create.

    # Let's check Client.create presence.
    # It is NOT in client.ex (based on my memory of reading it).
    # request.ex has it.

    # Alternative: Restart docker container.
    # 2. List (should include INBOX)
    mailboxes = Client.list(client)
    assert Enum.any?(mailboxes, fn m -> m.name == "INBOX" end)

    # 3. Append a message
    # {12}
    # Body Content
    assert {:ok, _} =
             Client.append(client, "INBOX", "Subject: Test\r\n\r\nHello World!", ["\\Seen"])

    # 4. Select INBOX and verify exists
    assert %Blop.Mailbox{name: "INBOX"} = Client.select(client, "INBOX")
    # We expect at least 1 message now
    assert Client.info(client, :selected_mailbox).exists >= 1

    # 5. Fetch the message
    # Sequence request 1:*
    messages = Client.fetch(client, "1:*")
    assert length(messages) >= 1
    # Check content if possible, but fetch returns Mail.Message structs.
    # We might need to inspect the struct.
    # 6. Create a new mailbox
    mailbox_name = "integration_test_create_#{:os.system_time(:micro_seconds)}"
    assert :ok = Client.create(client, mailbox_name)
    # Refresh mailboxes so select can find it
    Client.list(client)
    assert %Blop.Mailbox{name: ^mailbox_name} = Client.select(client, mailbox_name)
  end

  test "idle with concurrent append" do
    mailbox_name = "idle_test_#{:os.system_time(:micro_seconds)}"

    # Client A: The one that will IDLE
    {:ok, client_a} =
      Client.new(
        host: @host,
        port: @port,
        socket_module: :gen_tcp,
        gen_tcp: [:binary, active: false]
      )

    assert :ok = Client.login(client_a, "user_a", "pass")
    assert :ok = Client.create(client_a, mailbox_name)
    assert %Blop.Mailbox{} = Client.select(client_a, mailbox_name)

    # Start a task to append a message after a short delay
    Task.start(fn ->
      Process.sleep(50)

      {:ok, client_b} =
        Client.new(
          host: @host,
          port: @port,
          socket_module: :gen_tcp,
          gen_tcp: [:binary, active: false]
        )

      Client.login(client_b, "user_a", "pass")
      Client.append(client_b, mailbox_name, "Subject: Trigger IDLE\r\n\r\nWake up!", [])
    end)

    # Client A enters IDLE state. It should return when Client B appends.
    # Note: socket recv timeout might be an issue if it's too short, but default is usually infinity or long.
    # IDLE returns {:ok, [{:exists, n}, ...]} or similar list of responses.
    # Based on our implementation: Response.extract returns {:ok, list}
    # and list items are like {:exists, n} or {:recent, n} or "IDLE terminated" tag response?
    # Actually wait, Response.extract flattens things.
    # Let's see what Client.idle returns.
    # It returns Response.extract(...)

    # We expect something like: {:ok, [{"EXISTS", 1}, ...]}
    # Because do_idle receives the update_data and then the tag_resp.

    assert {:ok, responses} = Client.idle(client_a)

    # We expect at least one unsolicited response (EXISTS) and the command completion.
    # The exact format depends on Response.ex
    # Use generic assertion for now to see what we get if it fails, or iterate.
    assert Enum.any?(responses, fn
             {"EXISTS", _} -> true
             _ -> false
           end)
  end
end
