defmodule Blop.Client do
  alias Blop.{Parser, Request, Response, Socket, Client, Mailbox}

  require Logger

  defstruct [
    :conn,
    :capability,
    selected_mailbox: nil,
    mailboxes: [],
    logged_in: false,
    tag_number: 1
  ]

  @moduledoc """
  ## Blop Client

  It's supposed to be used in a GenServer. It starts a linked Agent to hold to the client state.

  client = Client.new host: "imap.my.provider.com"
  Client.login(client, "my@provider.com", "my-unique-password")
  Client.list(client)
  Client.select(client, "INBOX")
  Client.fetch(client, "1:5")
  """

  @doc """
  Create a new IMAP client.

  Accepted options:

  - `:host` - The hostname of the IMAP server. (required)
  - `:port` - The port of the IMAP server. Default is 993.
  - `:socket_module` - The socket module to use. Default is `:ssl`.
  - `:login` - A tuple with the username and password. This will be used to log in automatically
    after the client is created. Users can also call `Client.login/3` manually.

  Connection options:

  For example when using `:ssl`

  - `:ssl` - A list of options to pass to `:ssl.connect/4`. Default is `[:binary, active: false, cacertfile: CAStore.file_path()]`.
  """
  def new(opts) do
    opts = Enum.into(opts, %{})

    host = Map.fetch!(opts, :host)
    port = Map.get(opts, :port, 993)

    socket_module = Map.get(opts, :socket_module, :ssl)

    conn_opts =
      case socket_module do
        :ssl ->
          [
            :binary
            | Keyword.merge(
                [active: false, cacertfile: CAStore.file_path()],
                Map.get(opts, :ssl, [])
              )
          ]

        other ->
          Map.get(opts, other, [])
      end

    {:ok, conn} = Socket.connect(socket_module, to_charlist(host), port, conn_opts)
    conn = {socket_module, conn}

    Agent.start_link(fn ->
      %Client{conn: conn, capability: imap_receive_raw(conn)}
    end)
    |> tap(fn
      {:ok, client} ->
        with {username, password} <- Map.get(opts, :login),
             :ok <- __MODULE__.login(client, username, password) do
          {:ok, client}
        end

      {:error, reason} ->
        Logger.error("Failed to start IMAP client agent: #{inspect(reason)}")
        {:error, reason}
    end)
  end

  @doc """
  Log the client in to the server with the given username and password.
  """
  def login(client, username, password) do
    with {:ok, _} <- Client.exec(client, Request.login(username, password)) do
      Agent.update(client, &Map.put(&1, :logged_in, true))
    else
      {:error, reason} ->
        Logger.error("Failed to log in: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Return the client state.
  """
  def info(client) do
    Agent.get(client, & &1)
  end

  def info(client, key) do
    Agent.get(client, &get_in(&1, [Access.key!(key)]))
  end

  @doc """
  Perform a LIST command on the server to get a list of mailboxes.
  """
  def list(client, reference \\ ~s|""|, mailbox \\ "*") do
    with true <- Agent.get(client, & &1.logged_in),
         {:ok, list} <- Client.exec(client, Request.list(reference, mailbox)) do
      for {:mailbox, name, delimiter, flags} <- list do
        %Blop.Mailbox{name: name, delimiter: delimiter, flags: flags}
      end
    end
    |> tap(fn mailboxes ->
      Agent.update(client, &Map.put(&1, :mailboxes, mailboxes))
    end)
  end

  @doc """
  Perform a SELECT command on a mailbox. Sets the currently selected mailbox in the client state.
  """
  def select(client, mailbox_name) do
    do_select_or_examine(client, mailbox_name, Request.select(inspect(mailbox_name)))
  end

  @doc """
  Perform a EXAMINE command on a mailbox. Sets the currently selected mailbox in the client state.
  """
  def examine(client, mailbox_name) do
    do_select_or_examine(client, mailbox_name, Request.examine(inspect(mailbox_name)))
  end

  defp do_select_or_examine(client, mailbox_name, cmd) do
    with true <- Agent.get(client, & &1.logged_in),
         {:ok, resp} <- Client.exec(client, cmd) do
      mailbox_status =
        Enum.reduce(resp, %{}, fn
          {"EXISTS", n}, acc -> Map.put(acc, :exists, n)
          {"RECENT", n}, acc -> Map.put(acc, :recent, n)
          _, acc -> acc
        end)

      Agent.update(client, fn state ->
        update_in(
          state,
          [Access.key!(:mailboxes), Mailbox.find(mailbox_name)],
          &Map.merge(&1, mailbox_status)
        )
      end)

      mailbox =
        Agent.get(
          client,
          &get_in(&1, [Access.key!(:mailboxes), Mailbox.find(mailbox_name)])
        )

      Agent.update(client, &Map.put(&1, :selected_mailbox, mailbox))

      mailbox
    end
  end

  @doc """
  Create a new mailbox.
  """
  def create(client, mailbox) do
    with true <- Agent.get(client, & &1.logged_in),
         {:ok, _resp} <- Client.exec(client, Request.create(inspect(mailbox))) do
      :ok
    end
  end

  @doc """
  Perform a FETCH command on the server to get a list of messages.
  """
  @spec fetch(pid()) :: [Mail.Message.t()]
  def fetch(client) do
    do_fetch(
      client,
      Request.fetch(Request.sequence_set(__MODULE__.info(client, :selected_mailbox).exists))
    )
  end

  @spec fetch(pid(), sequence_set :: String.t()) :: [Mail.Message.t()]
  def fetch(client, sequence_set) do
    do_fetch(client, Request.fetch(Request.sequence_set(sequence_set)))
  end

  @spec fetch(pid(), sequence_set :: String.t(), md_items_or_macro :: String.t()) ::
          [Mail.Message.t()]
  def fetch(client, sequence_set, md_items_or_macro) do
    do_fetch(client, Request.fetch(Request.sequence_set(sequence_set), md_items_or_macro))
  end

  defp do_fetch(client, cmd) do
    with true <- Agent.get(client, & &1.logged_in),
         {:ok, resp} <- Client.exec(client, cmd) do
      for %Mail.Message{} = message <- List.flatten(resp) do
        message
      end
    end
  end

  @doc """
  Append a message to a mailbox.
  """
  def append(client, mailbox, content, flags \\ [], datetime \\ nil) do
    content =
      if is_binary(content) do
        content
      else
        Mail.render(content)
      end

    size = byte_size(content)

    flags =
      if Enum.empty?(flags) do
        ""
      else
        "(" <> Enum.join(flags, " ") <> ") "
      end

    datetime =
      if datetime do
        # datetime should be formatted as "dd-Mon-yyyy hh:mm:ss +zzzz"
        ~s("#{datetime}") <> " "
      else
        ""
      end

    params = "#{inspect(mailbox)} #{flags}#{datetime}{#{size}}"

    with true <- Agent.get(client, & &1.logged_in) do
      do_append(client, Request.append(params), content)
    end
  end

  defp do_append(client_agent, %Request{} = req, content) do
    client =
      Agent.get_and_update(
        client_agent,
        &{&1, %{&1 | tag_number: &1.tag_number + 1}}
      )

    req = %{req | tag: "EX#{client.tag_number}"}

    # 1. Send command
    imap_send(client, req)

    # 2. Receive continuation or error
    case Socket.recv(client.conn) do
      {:ok, "+" <> _} ->
        # 3. Send content
        imap_send_raw(client.conn, content <> "\r\n")

        # 4. Receive final response
        imap_receive(client, req)
        |> Parser.response()
        |> Response.extract()

      {:ok, other} ->
        # Could be an error or unexpected response
        Logger.error("Unexpected response during APPEND: #{inspect(other)}")
        {:error, other}

      error ->
        error
    end
  end

  @doc """
  Execute an IMAP command with the client.
  """
  def exec(client_agent, %Request{} = req) do
    client =
      Agent.get_and_update(
        client_agent,
        &{&1, %{&1 | tag_number: &1.tag_number + 1}}
      )

    req = %{req | tag: "EX#{client.tag_number}"}

    imap_send(client, req)

    imap_receive(client, req)
    |> Parser.response()
    |> Response.extract()
  end

  defp imap_send(%{conn: conn}, req) do
    message = Request.serialize(req)
    imap_send_raw(conn, message)
  end

  defp imap_send_raw(conn, message) do
    Logger.debug(">>> #{message}")
    Socket.send(conn, message)
  end

  defp imap_receive(%{conn: conn}, req) do
    assemble_msg(conn, req.tag)
  end

  defp assemble_msg(conn, tag) do
    {:ok, message} = Socket.recv(conn)

    Logger.debug("<<<\n#{message}")

    # TODO: improve this part with Stream or something
    if Regex.match?(~r/^.*#{tag} .*\r\n$/s, message) do
      message
    else
      message <> assemble_msg(conn, tag)
    end
  end

  defp imap_receive_raw(conn) do
    {:ok, message} = Socket.recv(conn)
    message
  end
end
