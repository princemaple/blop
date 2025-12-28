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
  end
end
