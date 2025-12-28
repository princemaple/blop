defmodule Blop.Response do
  @moduledoc ~S"""
  Extract response info returned by the IMAP server and convert them to a structured format
  """

  def extract({:ok, [response: response], "", _, _, _}) do
    extract(response)
  catch
    {:error, {rejection, error}} ->
      {:error, {rejection, error}}
  end

  def extract(parts) do
    {:ok, Enum.map(parts, &extract_message_data/1)}
  end

  defp extract_message_data({:response_data, ["*", {:capability_data, ["CAPABILITY" | caps]}]}) do
    {:capability, Enum.map(caps, fn {:capability, capability} -> capability end)}
  end

  defp extract_message_data(
         {:response_data, ["*", {:mailbox_data, [{:number, number}, property]}]}
       ) do
    {property, number}
  end

  defp extract_message_data(
         {:response_data, ["*", {:mailbox_data, ["FLAGS", {:flag_list, flags}]}]}
       ) do
    {:flags, Enum.reject(flags, &is_binary/1)}
  end

  # For LIST response with empty flags
  defp extract_message_data(
         {:response_data,
          [
            "*",
            {:mailbox_data,
             [
               "LIST",
               {:mailbox_list, ["(", ")", delimiter, {:mailbox, name}]}
             ]}
          ]}
       ) do
    {:mailbox, name, delimiter, []}
  end

  # For LIST response
  defp extract_message_data(
         {:response_data,
          [
            "*",
            {:mailbox_data,
             [
               "LIST",
               {:mailbox_list, ["(", {:mbx_list_flags, flags}, ")", delimiter, {:mailbox, name}]}
             ]}
          ]}
       ) do
    {:mailbox, name, delimiter, extract_mbx_flags(flags)}
  end

  defp extract_message_data(
         {:response_data, ["*", {:resp_cond_state, ["OK", {:resp_text, message}]}]}
       ) do
    message
  end

  # For FETCH response
  defp extract_message_data(
         {:response_data,
          [
            "*",
            {:message_data, [_index, "FETCH", {:msg_att, msg_atts}]}
          ]}
       ) do
    msg_atts
    |> Enum.reject(&(&1 in ~w|( )|))
    |> Enum.map(fn
      {:msg_att_static, msg_att_static} ->
        msg_att_static

      {:msg_att_dynamic, msg_att_dynamic} ->
        msg_att_dynamic
    end)
    |> Enum.map(&extract_msg_att/1)
  end

  defp extract_message_data(
         {:response_done,
          [response_tagged: [tag, resp_cond_state: ["OK", {:resp_text, message}]]]}
       ) do
    {tag, message}
  end

  defp extract_message_data(
         {:response_done,
          [response_tagged: [_tag, resp_cond_state: [rejection, {:resp_text, error}]]]}
       )
       when rejection in ["NO", "BAD"] do
    throw({:error, {rejection, error}})
  end

  defp extract_message_data(other) do
    IO.inspect(other, label: "UNMATCHED RESPONSE DATA")
    other
  end

  defp extract_msg_att(["RFC822", ".HEADER", {:literal, [_number, body]}]) do
    Mail.Parsers.RFC2822.parse(body)
  end

  defp extract_msg_att(["RFC822", {:literal, [_number, body]}]) do
    Mail.Parsers.RFC2822.parse(body)
  end

  defp extract_msg_att(["BODY", _section, {:literal, [_number, body]}]) do
    Mail.Parsers.RFC2822.parse(body)
  end

  defp extract_msg_att(["FLAGS" | flags]) do
    {:flags, Enum.reject(flags, &(&1 in ~w|( )|))}
  end

  defp extract_msg_att(["RFC822.SIZE", {:number, number}]) do
    {:size, number}
  end

  defp extract_msg_att([
         "INTERNALDATE",
         date_time: [
           date_text: [
             {:date_day, date},
             "-",
             {:date_month, month},
             "-",
             {:date_year, year}
           ],
           time: time,
           zone: zone
         ]
       ]) do
    {:internal_date, {date, month, year, time, zone}}
  end

  defp extract_msg_att(["ENVELOPE", {:envelope, envelope}]) do
    {:envelope, envelope}
  end

  defp extract_mbx_flags(flags) do
    Enum.map(flags, &extract_mbx_flag/1)
  end

  defp extract_mbx_flag({:mbx_list_sflag, ["\\" <> flag]}) do
    flag
  end

  defp extract_mbx_flag({:mbx_list_oflag, [flag_extension: ["\\", {:atom, flag}]]}) do
    flag
  end
end
