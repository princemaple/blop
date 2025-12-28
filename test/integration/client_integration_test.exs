defmodule Blop.ClientIntegrationTest do
  use ExUnit.Case
  alias Blop.Client

  @moduletag :integration

  # Default GreenMail IMAP port from docker-compose
  # Greenmail "-Dgreenmail.auth.disabled" means no auth check.
  @port 3143
  @host "localhost"
  @greenmail_api_port 8080

  setup_all do
    # Reset GreenMail to ensure clean state before running tests
    require Logger
    url = "http://#{@host}:#{@greenmail_api_port}/api/mail/purge"

    case Req.post(url) do
      {:ok, %{status: status}} ->
        Logger.info("GreenMail purge successful: #{status}")

      {:error, reason} ->
        Logger.warning("GreenMail purge failed: #{inspect(reason)}")
    end

    :ok
  end

  setup do
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

    # 2. List (should include INBOX)
    mailboxes = Client.list(client)
    assert Enum.any?(mailboxes, fn m -> m.name == "INBOX" end)

    # 3. Create a test mailbox for isolation
    test_mailbox = "LifecycleTest"
    assert :ok = Client.create(client, test_mailbox)
    Client.list(client)

    # 4. Append a message to the test mailbox
    assert {:ok, _} =
             Client.append(client, test_mailbox, "Subject: Test\r\n\r\nHello World!", ["\\Seen"])

    # 5. Select the test mailbox and verify exists
    assert %Blop.Mailbox{name: ^test_mailbox} = Client.select(client, test_mailbox)
    # We expect exactly 1 message now
    assert Client.info(client, :selected_mailbox).exists == 1

    # 6. Fetch the message
    # Sequence request 1:*
    messages = Client.fetch(client, "1:*")
    assert length(messages) == 1
  end

  test "idle with concurrent append" do
    mailbox_name = "IdleTest"

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
    Client.list(client_a)
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

    assert {:ok, responses} = Client.idle(client_a)
    assert Enum.any?(responses, fn
             {"EXISTS", _} -> true
             _ -> false
           end)
  end

  test "mail message", %{client: client} do
    # Login
    assert :ok = Client.login(client, "test@example.com", "password")

    # Create a test mailbox
    mailbox_name = "MailTest"
    assert :ok = Client.create(client, mailbox_name)
    Client.list(client)
    assert %Blop.Mailbox{} = Client.select(client, mailbox_name)

    # Build a message using the Mail library
    message =
      Mail.build_multipart()
      |> Mail.put_from("sender@example.com")
      |> Mail.put_to("recipient@example.com")
      |> Mail.put_subject("Test Email with Headers")
      |> Mail.put_text("""
      This is a test email body.
      It has multiple lines.
      And should be parsed correctly.
      """)

    assert {:ok, _} = Client.append(client, mailbox_name, message, ["\\Seen"])

    # Fetch the message
    messages = Client.fetch(client, "1:*")
    assert length(messages) == 1

    # Verify the message is a Mail.Message struct
    [message] = messages
    assert %Mail.Message{} = message

    # Verify message headers are parsed correctly
    assert message.headers["subject"] == "Test Email with Headers"
    assert message.headers["from"] == "sender@example.com"
    assert message.headers["to"] == ["recipient@example.com"]

    # Verify message body content
    assert String.contains?(message.body, "This is a test email body")
    assert String.contains?(message.body, "multiple lines.\n")
    assert String.contains?(message.body, "parsed correctly")
  end
end
