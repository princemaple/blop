defmodule Blop.Request do
  @moduledoc """
  IMAP commands being sent to the IMAP server
  """
  defstruct tag: "TAG", command: nil, params: []

  alias __MODULE__

  def serialize(%Request{tag: tag, command: command, params: params}) do
    params =
      params
      |> List.flatten()
      |> case do
        [] -> nil
        _ -> Enum.join(params, " ")
      end

    [tag, command, params]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
    |> Kernel.<>("\r\n")
  end

  @ops [
    noop: [],
    capability: [],
    authenticate: [:mechanism],
    login: [:username, :password],
    logout: [],
    list: [reference: ~s|""|, mailbox: "*"],
    lsub: [reference: ~s|""|, mailbox: ~s|""|],
    select: [:name],
    subscribe: [:name],
    unsubscribe: [:name],
    examine: [:name],
    create: [:name],
    delete: [:name],
    status: [:name],
    append: [:params],
    rename: [:name, :new_name],
    check: [],
    starttls: [],
    close: [],
    expunge: [],
    search: [:flags],
    fetch: [:sequence, macro: "BODY.PEEK[]"],
    store: [:sequence, :item, :value],
    copy: [:sequence, :mailbox],
    uid: [:params]
  ]

  for {op, params} <- @ops do
    command = op |> to_string |> String.upcase()

    parameters =
      Enum.map(params, fn
        arg when is_atom(arg) -> Macro.var(arg, Elixir)
        {arg, default} -> quote(do: unquote(Macro.var(arg, Elixir)) \\ unquote(default))
      end)

    arguments =
      Enum.map(params, fn
        arg when is_atom(arg) -> Macro.var(arg, Elixir)
        {arg, _default} -> Macro.var(arg, Elixir)
      end)

    def unquote(op)(unquote_splicing(parameters)) do
      %Request{command: unquote(command), params: [unquote_splicing(arguments)]}
    end
  end

  def sequence_set(s) when is_integer(s) do
    to_string(s)
  end

  def sequence_set(s) when is_list(s) do
    s |> Enum.map(&sequence_set/1) |> Enum.join(",")
  end

  def sequence_set(%Range{first: first, last: last}) do
    "#{first}:#{last}"
  end

  def sequence_set(%Range{} = r) do
    r |> Enum.to_list() |> sequence_set()
  end

  def sequence_set(s) when is_binary(s), do: s
end
