# Blop

_blop, a new email just dropped..._

IMAP Client for Elixir

## Installation

```elixir
def deps do
  [
    {:blop, "~> 0.1"}
  ]
end
```

## Usage

```elixir
alias Blop.Client

{:ok, client} = Client.new(
  host: "imap.my.host",
  port: 993,
  login: {"me@my.host", "my_strong_password"}
)
```

Create a mailbox and list them:

```elixir
Client.create(client, "New Mailbox")
Client.list(client)
```

Append a message (using string or `Mail` struct):

```elixir
Client.append(client, "INBOX", "Subject: Hello\r\n\r\nWorld!")

message =
  Mail.build_multipart()
  |> Mail.put_to("me@my.host")
  |> Mail.put_subject("Hello")
  |> Mail.put_text("World!")

Client.append(client, "INBOX", message)
```

Select a mailbox and fetch messages:

```elixir
Client.select(client, "INBOX")

Client.fetch(client, "1:5")
```
