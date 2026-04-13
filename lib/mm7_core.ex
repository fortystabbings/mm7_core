defmodule MM7Core do
  @moduledoc """
  Минимальный stage-1 конвертер MM7 body-level сообщений.
  """

  @canonical_ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  @root_to_kind %{
    "SubmitReq" => "mm7_submit_req",
    "SubmitRsp" => "mm7_submit_res",
    "DeliverReq" => "mm7_deliver_req",
    "DeliverRsp" => "mm7_deliver_res"
  }

  @kind_to_root Map.new(@root_to_kind, fn {root, kind} -> {kind, root} end)

  @submit_req_children [
    "MM7Version",
    "SenderIdentification",
    "Recipients",
    "ServiceCode",
    "LinkedID",
    "MessageClass",
    "TimeStamp",
    "DeliveryReport",
    "ReadReply",
    "Priority",
    "Subject",
    "ApplicID",
    "ReplyApplicID",
    "AuxApplicInfo"
  ]

  @submit_res_children ["MM7Version", "Status", "MessageID"]

  @deliver_req_children [
    "MM7Version",
    "MMSRelayServerID",
    "VASPID",
    "VASID",
    "LinkedID",
    "Sender",
    "Recipients",
    "TimeStamp",
    "Priority",
    "Subject",
    "ApplicID",
    "ReplyApplicID",
    "AuxApplicInfo"
  ]

  @deliver_res_children ["MM7Version", "Status", "ServiceCode"]

  @submit_req_optional_fields [
    {:text, "service_code", "ServiceCode"},
    {:text, "linked_id", "LinkedID"},
    {:text, "message_class", "MessageClass"},
    {:text, "time_stamp", "TimeStamp"},
    {:bool, "delivery_report", "DeliveryReport"},
    {:bool, "read_reply", "ReadReply"},
    {:text, "priority", "Priority"},
    {:text, "subject", "Subject"},
    {:text, "applic_id", "ApplicID"},
    {:text, "reply_applic_id", "ReplyApplicID"},
    {:text, "aux_applic_info", "AuxApplicInfo"}
  ]

  @submit_req_text_fields for {:text, key, _element_name} <- @submit_req_optional_fields, do: key
  @submit_req_bool_fields for {:bool, key, _element_name} <- @submit_req_optional_fields, do: key

  @deliver_req_optional_fields [
    {:text, "mms_relay_server_id", "MMSRelayServerID"},
    {:text, "vasp_id", "VASPID"},
    {:text, "vas_id", "VASID"},
    {:text, "linked_id", "LinkedID"},
    {:text, "time_stamp", "TimeStamp"},
    {:text, "priority", "Priority"},
    {:text, "subject", "Subject"},
    {:text, "applic_id", "ApplicID"},
    {:text, "reply_applic_id", "ReplyApplicID"},
    {:text, "aux_applic_info", "AuxApplicInfo"}
  ]

  @deliver_req_text_fields for {:text, key, _element_name} <- @deliver_req_optional_fields,
                               do: key
  @sender_identification_optional_fields [
    {:text, "vasp_id", "VASPID"},
    {:text, "vas_id", "VASID"}
  ]

  @address_tags %{
    "RFC2822Address" => "rfc2822_address",
    "Number" => "number",
    "ShortCode" => "short_code"
  }

  @address_kinds Map.values(@address_tags)
  @address_kind_to_tag Map.new(@address_tags, fn {tag, kind} -> {kind, tag} end)
  @stage_feature_keys ~w(soap_envelope soap_header mime)

  @doc """
  Унифицированный stage-1 API.
  """
  def convert(input, opts \\ [])

  def convert(input, _opts) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      trimmed == "" ->
        error(:unsupported_input_format, "empty input")

      String.starts_with?(trimmed, "<") ->
        xml_to_map(trimmed)

      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        json_to_xml(trimmed)

      true ->
        error(:unsupported_input_format, "unsupported binary input", %{format: "non_xml_binary"})
    end
  end

  def convert(input, _opts) when is_map(input) do
    input
    |> stringify_keys()
    |> map_to_xml()
  end

  def convert(_input, _opts) do
    error(:unsupported_input_format, "unsupported input type")
  end

  defp json_to_xml(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map_to_xml(map)
      {:ok, _other} -> error(:invalid_json, "json root must be an object")
      {:error, reason} -> error(:invalid_json, "invalid json", %{reason: inspect(reason)})
    end
  end

  defp map_to_xml(map) do
    with :ok <- reject_stage_feature_keys(map),
         :ok <- reject_mime_map(map),
         {:ok, kind} <- fetch_kind(map),
         :ok <- ensure_allowed_map(kind, map),
         :ok <- validate_mandatory(kind, map),
         {:ok, xml} <- encode_kind(kind, map) do
      {:ok, xml}
    end
  end

  defp xml_to_map(xml) do
    with :ok <- reject_soap_envelope(xml),
         :ok <- reject_soap_header(xml),
         :ok <- reject_mime_payload(xml),
         :ok <- reject_dtd(xml),
         {:ok, root} <- parse_xml(xml),
         {:ok, kind} <- detect_kind(root.name),
         :ok <- validate_namespace(root.ns),
         {:ok, map} <- decode_kind(kind, root),
         :ok <- validate_mandatory(kind, map) do
      {:ok, Map.put(map, "kind", kind)}
    end
  end

  defp parse_xml(xml) do
    initial = %{stack: [], root: nil}

    try do
      result =
        :xmerl_sax_parser.stream(String.to_charlist(xml),
          event_fun: fn event, line, acc -> sax_event(event, line, acc) end,
          event_state: initial
        )

      case result do
        {:ok, %{root: nil}, _rest} ->
          error(:invalid_xml, "invalid xml")

        {:ok, %{root: root}, rest} ->
          ensure_no_trailing_input(root, rest)

        {:fatal_error, reason} ->
          error(:invalid_xml, "invalid xml", %{reason: inspect(reason)})

        {:fatal_error, reason, _line, _event, _state} ->
          error(:invalid_xml, "invalid xml", %{reason: inspect(reason)})

        other ->
          error(:invalid_xml, "invalid xml", %{reason: inspect(other)})
      end
    catch
      :throw, {:error, _} = err ->
        err

      :exit, reason ->
        error(:invalid_xml, "invalid xml", %{reason: inspect(reason)})
    end
  end

  defp sax_event(:startDocument, _line, state), do: state
  defp sax_event(:endDocument, _line, state), do: state
  defp sax_event({:startPrefixMapping, _, _}, _line, state), do: state
  defp sax_event({:endPrefixMapping, _}, _line, state), do: state

  defp sax_event({:characters, chars}, _line, %{stack: [node | rest]} = state) do
    text = IO.chardata_to_string(chars)
    %{state | stack: [%{node | text: [text | node.text]} | rest]}
  end

  defp sax_event({:characters, chars}, _line, %{stack: []} = state) do
    if chars |> IO.chardata_to_string() |> String.trim() == "" do
      state
    else
      throw(error(:invalid_xml, "unexpected text outside root"))
    end
  end

  defp sax_event({:ignorableWhitespace, _chars}, _line, state), do: state

  defp sax_event({:startElement, _uri, _local_name, _qname, _attrs}, _line, %{
         stack: [],
         root: root
       })
       when not is_nil(root) do
    throw(error(:invalid_xml, "multiple root elements are not allowed"))
  end

  defp sax_event({:startElement, uri, local_name, _qname, attrs}, _line, state) do
    node = %{
      name: IO.chardata_to_string(local_name),
      ns: IO.chardata_to_string(uri),
      attrs: attrs_to_map(attrs),
      children: [],
      text: []
    }

    %{state | stack: [node | state.stack]}
  end

  defp sax_event({:endElement, _uri, _local_name, _qname}, _line, %{stack: [node | rest]} = state) do
    normalized = %{
      node
      | children: Enum.reverse(node.children),
        text: node.text |> Enum.reverse() |> IO.iodata_to_binary()
    }

    case rest do
      [] ->
        %{state | stack: [], root: normalized}

      [parent | tail] ->
        parent = %{parent | children: [normalized | parent.children]}
        %{state | stack: [parent | tail]}
    end
  end

  defp attrs_to_map(attrs) do
    Map.new(attrs, fn {_, _, name, value} ->
      {IO.chardata_to_string(name), IO.chardata_to_string(value)}
    end)
  end

  defp detect_kind(root_name) do
    case @root_to_kind[root_name] do
      nil -> error(:unknown_xml_root, "unknown xml root", %{root: root_name})
      kind -> {:ok, kind}
    end
  end

  defp validate_namespace(@canonical_ns), do: :ok

  defp validate_namespace(namespace) do
    error(:invalid_structure, "namespace mismatch", %{
      namespace: namespace,
      expected: @canonical_ns
    })
  end

  defp ensure_no_trailing_input(root, rest) do
    if rest |> IO.chardata_to_string() |> String.trim() == "" do
      {:ok, root}
    else
      error(:invalid_xml, "multiple root elements are not allowed")
    end
  end

  defp reject_soap_envelope(xml) do
    if Regex.match?(~r/<\s*([A-Za-z0-9_]+:)?Envelope\b/, xml) do
      error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "soap_envelope"})
    else
      :ok
    end
  end

  defp reject_soap_header(xml) do
    if Regex.match?(~r/<\s*([A-Za-z0-9_]+:)?Header\b/, xml) do
      error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "soap_header"})
    else
      :ok
    end
  end

  defp reject_mime_payload(xml) do
    down = String.downcase(xml)

    if String.contains?(down, "multipart/") or String.contains?(down, "content-type:") or
         String.contains?(down, "content-id:") or String.contains?(down, "cid:") or
         Regex.match?(~r/<\s*Content\b/i, xml) do
      error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})
    else
      :ok
    end
  end

  defp reject_dtd(xml) do
    if Regex.match?(~r/<!\s*(DOCTYPE|ENTITY)/i, xml) do
      error(:invalid_xml, "doctype/entity is not allowed")
    else
      :ok
    end
  end

  defp reject_stage_feature_keys(map) do
    case Enum.find(@stage_feature_keys, &Map.has_key?(map, &1)) do
      nil ->
        :ok

      feature ->
        error(:unsupported_stage_feature, "unsupported stage feature", %{feature: feature})
    end
  end

  defp reject_mime_map(map) do
    if Map.has_key?(map, "content") do
      error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})
    else
      :ok
    end
  end

  defp fetch_kind(map) do
    case map["kind"] do
      nil ->
        error(:missing_kind, "missing kind")

      kind when is_binary(kind) ->
        if Map.has_key?(@kind_to_root, kind) do
          {:ok, kind}
        else
          error(:unknown_kind, "unknown kind", %{kind: kind})
        end

      kind ->
        error(:unknown_kind, "unknown kind", %{kind: kind})
    end
  end

  defp decode_kind("mm7_submit_req", root), do: decode_submit_req(root)
  defp decode_kind("mm7_submit_res", root), do: decode_submit_res(root)
  defp decode_kind("mm7_deliver_req", root), do: decode_deliver_req(root)
  defp decode_kind("mm7_deliver_res", root), do: decode_deliver_res(root)

  defp encode_kind("mm7_submit_req", map), do: encode_submit_req(map)
  defp encode_kind("mm7_submit_res", map), do: encode_submit_res(map)
  defp encode_kind("mm7_deliver_req", map), do: encode_deliver_req(map)
  defp encode_kind("mm7_deliver_res", map), do: encode_deliver_res(map)

  defp decode_submit_req(root) do
    with :ok <- ensure_children(root, @submit_req_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, recipients} <- required_recipients(root),
         {:ok, sender_identification} <- optional_sender_identification(root),
         {:ok, optional_fields} <- collect_optional_fields(root, @submit_req_optional_fields) do
      {:ok,
       %{}
       |> Map.put("mm7_version", mm7_version)
       |> maybe_put("sender_identification", sender_identification)
       |> Map.put("recipients", recipients)
       |> Map.merge(optional_fields)}
    end
  end

  defp decode_submit_res(root) do
    with :ok <- ensure_children(root, @submit_res_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, status} <- decode_status(root),
         {:ok, message_id} <- optional_text(root, "MessageID") do
      {:ok,
       %{}
       |> Map.put("mm7_version", mm7_version)
       |> Map.put("status", status)
       |> maybe_put("message_id", message_id)}
    end
  end

  defp decode_deliver_req(root) do
    with :ok <- ensure_children(root, @deliver_req_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, sender} <- required_address(root, "Sender"),
         {:ok, recipients} <- optional_recipients(root),
         {:ok, optional_fields} <- collect_optional_fields(root, @deliver_req_optional_fields) do
      {:ok,
       %{}
       |> Map.put("mm7_version", mm7_version)
       |> Map.put("sender", sender)
       |> maybe_put("recipients", recipients)
       |> Map.merge(optional_fields)}
    end
  end

  defp decode_deliver_res(root) do
    with :ok <- ensure_children(root, @deliver_res_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, status} <- decode_status(root),
         {:ok, service_code} <- optional_text(root, "ServiceCode") do
      {:ok,
       %{}
       |> Map.put("mm7_version", mm7_version)
       |> Map.put("status", status)
       |> maybe_put("service_code", service_code)}
    end
  end

  defp ensure_children(node, allowed, opts \\ []) do
    ordered? = Keyword.get(opts, :ordered, true)
    names = Enum.map(element_children(node), & &1.name)
    unknown = Enum.reject(names, &(&1 in allowed))

    cond do
      unknown != [] ->
        error(:invalid_structure, "unexpected child elements", %{unknown: unknown})

      ordered? and not ordered_names?(names, allowed) ->
        error(:invalid_structure, "unexpected child order", %{children: names})

      true ->
        :ok
    end
  end

  defp ordered_names?(names, allowed) do
    {ordered?, _last_index} =
      Enum.reduce_while(names, {true, -1}, fn name, {_ok?, last} ->
        index = Enum.find_index(allowed, &(&1 == name))

        if index >= last do
          {:cont, {true, index}}
        else
          {:halt, {false, last}}
        end
      end)

    ordered?
  end

  defp required_text(node, name) do
    case optional_text(node, name) do
      {:ok, nil} -> error(:invalid_structure, "missing #{name}")
      {:ok, value} -> {:ok, value}
      {:error, _} = err -> err
    end
  end

  defp optional_text(node, name) do
    with {:ok, child} <- single_child(node, name) do
      case child do
        nil ->
          {:ok, nil}

        child ->
          simple_text(child)
      end
    end
  end

  defp single_child(node, name) do
    matches = Enum.filter(element_children(node), &(&1.name == name))

    case matches do
      [] -> {:ok, nil}
      [child] -> {:ok, child}
      _ -> error(:invalid_structure, "duplicate child element", %{element: name})
    end
  end

  defp element_children(node) do
    Enum.filter(node.children, &is_map/1)
  end

  defp simple_text(node) do
    if element_children(node) == [] do
      value = String.trim(node.text)

      if value == "" do
        error(:invalid_structure, "empty value is not allowed", %{element: node.name})
      else
        {:ok, value}
      end
    else
      error(:invalid_structure, "nested elements are not allowed", %{element: node.name})
    end
  end

  defp collect_optional_fields(node, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case collect_optional_field(node, field) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp collect_optional_field(node, {:text, key, element_name}) do
    case optional_text(node, element_name) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} -> {:ok, {key, value}}
      {:error, _} = err -> err
    end
  end

  defp collect_optional_field(node, {:bool, key, element_name}) do
    with {:ok, value} <- optional_text(node, element_name),
         {:ok, parsed} <- parse_optional_xml_bool(value, key) do
      case parsed do
        nil -> {:ok, nil}
        boolean -> {:ok, {key, boolean}}
      end
    end
  end

  defp optional_sender_identification(root) do
    with {:ok, node} <- single_child(root, "SenderIdentification") do
      case node do
        nil ->
          {:ok, nil}

        node ->
          with :ok <- ensure_children(node, ["VASPID", "VASID", "SenderAddress"]),
               {:ok, sender_address} <- optional_address(node, "SenderAddress"),
               {:ok, sender_fields} <-
                 collect_optional_fields(node, @sender_identification_optional_fields) do
            sender_identification =
              sender_fields
              |> maybe_put("sender_address", sender_address)

            if map_size(sender_identification) == 0 do
              {:ok, nil}
            else
              {:ok, sender_identification}
            end
          end
      end
    end
  end

  defp required_recipients(root) do
    with {:ok, node} <- single_child(root, "Recipients") do
      case node do
        nil -> error(:invalid_structure, "missing Recipients")
        node -> decode_recipients_node(node)
      end
    end
  end

  defp optional_recipients(root) do
    with {:ok, node} <- single_child(root, "Recipients") do
      case node do
        nil -> {:ok, nil}
        node -> decode_recipients_node(node)
      end
    end
  end

  defp decode_recipients_node(node) do
    with :ok <- ensure_children(node, ["To", "Cc", "Bcc"], ordered: false) do
      Enum.reduce_while(
        element_children(node),
        {:ok, %{"to" => [], "cc" => [], "bcc" => []}},
        fn child, {:ok, acc} ->
          key =
            case child.name do
              "To" -> "to"
              "Cc" -> "cc"
              "Bcc" -> "bcc"
            end

          case decode_address_list(child) do
            {:ok, addresses} ->
              {:cont, {:ok, Map.update!(acc, key, &(&1 ++ addresses))}}

            {:error, _} = err ->
              {:halt, err}
          end
        end
      )
    end
  end

  defp decode_address_list(node) do
    case Enum.reduce_while(element_children(node), {:ok, []}, fn child, {:ok, acc} ->
           case decode_address_node(child) do
             {:ok, address} -> {:cont, {:ok, [address | acc]}}
             {:error, _} = err -> {:halt, err}
           end
         end) do
      {:ok, addresses} -> {:ok, Enum.reverse(addresses)}
      {:error, _} = err -> err
    end
  end

  defp required_address(root, name) do
    with {:ok, node} <- single_child(root, name) do
      case node do
        nil -> error(:invalid_structure, "missing #{name}")
        node -> decode_single_address(node, name)
      end
    end
  end

  defp optional_address(root, name) do
    with {:ok, node} <- single_child(root, name) do
      case node do
        nil -> {:ok, nil}
        node -> decode_single_address(node, name)
      end
    end
  end

  defp decode_single_address(node, element_name) do
    case element_children(node) do
      [address] -> decode_address_node(address)
      _ -> error(:invalid_structure, "invalid address structure", %{element: element_name})
    end
  end

  defp decode_address_node(node) do
    kind = @address_tags[node.name]

    if is_nil(kind) do
      error(:invalid_structure, "invalid address structure", %{element: node.name})
    else
      with {:ok, display_only} <-
             parse_optional_xml_bool(node.attrs["displayOnly"], "displayOnly"),
           {:ok, address_coding} <- optional_attr(node, "addressCoding"),
           {:ok, id} <- optional_attr(node, "id"),
           :ok <- validate_address_coding(address_coding),
           {:ok, value} <- simple_text(node) do
        {:ok,
         %{}
         |> Map.put("kind", kind)
         |> Map.put("value", value)
         |> maybe_put("display_only", display_only)
         |> maybe_put("address_coding", address_coding)
         |> maybe_put("id", id)}
      end
    end
  end

  defp decode_status(root) do
    with {:ok, node} <- single_child(root, "Status") do
      case node do
        nil ->
          error(:invalid_structure, "missing Status")

        node ->
          with :ok <- ensure_children(node, ["StatusCode", "StatusText", "Details"]),
               {:ok, status_code_text} <- required_text(node, "StatusCode"),
               {:ok, status_code} <-
                 parse_positive_integer(status_code_text, "status.status_code"),
               {:ok, status_text} <- optional_text(node, "StatusText"),
               {:ok, details} <- optional_text(node, "Details") do
            {:ok,
             %{}
             |> Map.put("status_code", status_code)
             |> maybe_put("status_text", status_text)
             |> maybe_put("details", details)}
          end
      end
    end
  end

  defp ensure_allowed_map("mm7_submit_req", map) do
    with :ok <-
           ensure_only_keys(map, [
             "kind",
             "mm7_version",
             "sender_identification",
             "recipients",
             "service_code",
             "linked_id",
             "message_class",
             "time_stamp",
             "delivery_report",
             "read_reply",
             "priority",
             "subject",
             "applic_id",
             "reply_applic_id",
             "aux_applic_info"
           ]),
         :ok <- validate_string_fields(map, ["mm7_version" | @submit_req_text_fields]),
         :ok <- validate_boolean_fields(map, @submit_req_bool_fields),
         :ok <- validate_sender_identification(Map.get(map, "sender_identification")),
         :ok <- validate_recipients(Map.get(map, "recipients")) do
      :ok
    end
  end

  defp ensure_allowed_map("mm7_submit_res", map) do
    with :ok <- ensure_only_keys(map, ["kind", "mm7_version", "status", "message_id"]),
         :ok <- validate_string_fields(map, ["mm7_version", "message_id"]),
         :ok <- validate_status(Map.get(map, "status")) do
      :ok
    end
  end

  defp ensure_allowed_map("mm7_deliver_req", map) do
    with :ok <-
           ensure_only_keys(map, [
             "kind",
             "mm7_version",
             "mms_relay_server_id",
             "vasp_id",
             "vas_id",
             "linked_id",
             "sender",
             "recipients",
             "time_stamp",
             "priority",
             "subject",
             "applic_id",
             "reply_applic_id",
             "aux_applic_info"
           ]),
         :ok <- validate_string_fields(map, ["mm7_version" | @deliver_req_text_fields]),
         :ok <- validate_address(Map.get(map, "sender")),
         :ok <- validate_recipients(Map.get(map, "recipients")) do
      :ok
    end
  end

  defp ensure_allowed_map("mm7_deliver_res", map) do
    with :ok <- ensure_only_keys(map, ["kind", "mm7_version", "status", "service_code"]),
         :ok <- validate_string_fields(map, ["mm7_version", "service_code"]),
         :ok <- validate_status(Map.get(map, "status")) do
      :ok
    end
  end

  defp ensure_only_keys(map, allowed) do
    unknown = map |> Map.keys() |> Enum.reject(&(&1 in allowed))

    if unknown == [] do
      :ok
    else
      error(:invalid_structure, "unknown fields", %{fields: unknown})
    end
  end

  defp validate_sender_identification(nil), do: :ok

  defp validate_sender_identification(sender_identification) when is_map(sender_identification) do
    with :ok <- ensure_only_keys(sender_identification, ["vasp_id", "vas_id", "sender_address"]),
         :ok <- validate_string_fields(sender_identification, ["vasp_id", "vas_id"]),
         :ok <- validate_address(Map.get(sender_identification, "sender_address")) do
      :ok
    end
  end

  defp validate_sender_identification(_value) do
    error(:invalid_structure, "sender_identification must be object")
  end

  defp validate_status(nil), do: :ok

  defp validate_status(status) when is_map(status) do
    with :ok <- ensure_only_keys(status, ["status_code", "status_text", "details"]),
         :ok <- validate_status_code(Map.get(status, "status_code")),
         :ok <- validate_string_fields(status, ["status_text", "details"]) do
      :ok
    end
  end

  defp validate_status(_value) do
    error(:invalid_structure, "status must be object")
  end

  defp validate_recipients(nil), do: :ok

  defp validate_recipients(recipients) when is_map(recipients) do
    with :ok <- ensure_only_keys(recipients, ["to", "cc", "bcc"]) do
      Enum.reduce_while(["to", "cc", "bcc"], :ok, fn key, :ok ->
        case validate_address_list(Map.get(recipients, key)) do
          :ok -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
      end)
    end
  end

  defp validate_recipients(_value) do
    error(:invalid_structure, "recipients must be object")
  end

  defp validate_address_list(nil), do: :ok

  defp validate_address_list(list) when is_list(list) do
    Enum.reduce_while(list, :ok, fn address, :ok ->
      case validate_address(address) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_address_list(_value) do
    error(:invalid_structure, "recipient group must be list")
  end

  defp validate_address(nil), do: :ok

  defp validate_address(address) when is_map(address) do
    with :ok <-
           ensure_only_keys(address, ["kind", "value", "display_only", "address_coding", "id"]),
         :ok <- validate_address_kind(Map.get(address, "kind")),
         :ok <- validate_address_value(Map.get(address, "value")),
         :ok <- validate_boolean_fields(address, ["display_only"]),
         :ok <- validate_string_fields(address, ["id"]),
         :ok <- validate_address_coding(Map.get(address, "address_coding")) do
      :ok
    end
  end

  defp validate_address(_value) do
    error(:invalid_structure, "address must be object")
  end

  defp validate_address_kind(nil), do: :ok

  defp validate_address_kind(kind) when is_binary(kind) and kind in @address_kinds, do: :ok

  defp validate_address_kind(_kind) do
    error(:invalid_structure, "unknown address kind")
  end

  defp validate_address_value(nil), do: :ok

  defp validate_address_value(value) when is_binary(value) and value != "", do: :ok

  defp validate_address_value(_value) do
    error(:invalid_structure, "address value must be non-empty string")
  end

  defp validate_status_code(nil), do: :ok

  defp validate_status_code(value) do
    case parse_positive_integer(value, "status.status_code") do
      {:ok, _value} -> :ok
      {:error, _} = err -> err
    end
  end

  defp validate_address_coding(nil), do: :ok
  defp validate_address_coding("encrypted"), do: :ok
  defp validate_address_coding("obfuscated"), do: :ok

  defp validate_address_coding(_value) do
    error(:invalid_structure, "field must be encrypted or obfuscated", %{field: "address_coding"})
  end

  defp validate_mandatory("mm7_submit_req", map) do
    missing =
      []
      |> maybe_missing_string(map, "mm7_version")
      |> maybe_missing_recipients(map)

    missing_or_ok("mm7_submit_req", missing)
  end

  defp validate_mandatory("mm7_submit_res", map) do
    missing =
      []
      |> maybe_missing_string(map, "mm7_version")
      |> maybe_missing_status_code(map)

    missing_or_ok("mm7_submit_res", missing)
  end

  defp validate_mandatory("mm7_deliver_req", map) do
    missing =
      []
      |> maybe_missing_string(map, "mm7_version")
      |> maybe_missing_address(map, "sender")

    missing_or_ok("mm7_deliver_req", missing)
  end

  defp validate_mandatory("mm7_deliver_res", map) do
    missing =
      []
      |> maybe_missing_string(map, "mm7_version")
      |> maybe_missing_status_code(map)

    missing_or_ok("mm7_deliver_res", missing)
  end

  defp missing_or_ok(_kind, []), do: :ok

  defp missing_or_ok(kind, missing) do
    error(:missing_mandatory_fields, "missing mandatory fields", %{kind: kind, fields: missing})
  end

  defp maybe_missing_string(list, map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> list
      _ -> list ++ [key]
    end
  end

  defp maybe_missing_address(list, map, key) do
    case map[key] do
      %{"kind" => kind, "value" => value}
      when kind in @address_kinds and is_binary(value) and value != "" ->
        list

      _ ->
        list ++ [key]
    end
  end

  defp maybe_missing_status_code(list, map) do
    case map do
      %{"status" => %{"status_code" => value}} when not is_nil(value) -> list
      _ -> list ++ ["status.status_code"]
    end
  end

  defp maybe_missing_recipients(list, map) do
    case map["recipients"] do
      %{} = recipients ->
        total =
          recipients
          |> Map.take(["to", "cc", "bcc"])
          |> Map.values()
          |> Enum.filter(&is_list/1)
          |> Enum.map(&length/1)
          |> Enum.sum()

        if total > 0, do: list, else: list ++ ["recipients"]

      _ ->
        list ++ ["recipients"]
    end
  end

  defp encode_submit_req(map) do
    xml = [
      open_root("SubmitReq"),
      tag("MM7Version", map["mm7_version"]),
      encode_sender_identification(Map.get(map, "sender_identification")),
      encode_recipients(Map.get(map, "recipients")),
      maybe_tag("ServiceCode", map["service_code"]),
      maybe_tag("LinkedID", map["linked_id"]),
      maybe_tag("MessageClass", map["message_class"]),
      maybe_tag("TimeStamp", map["time_stamp"]),
      maybe_tag("DeliveryReport", bool_to_text(map["delivery_report"])),
      maybe_tag("ReadReply", bool_to_text(map["read_reply"])),
      maybe_tag("Priority", map["priority"]),
      maybe_tag("Subject", map["subject"]),
      maybe_tag("ApplicID", map["applic_id"]),
      maybe_tag("ReplyApplicID", map["reply_applic_id"]),
      maybe_tag("AuxApplicInfo", map["aux_applic_info"]),
      close_root("SubmitReq")
    ]

    {:ok, IO.iodata_to_binary(xml)}
  end

  defp encode_submit_res(map) do
    with {:ok, status} <- encode_status(Map.get(map, "status", %{})) do
      xml = [
        open_root("SubmitRsp"),
        tag("MM7Version", map["mm7_version"]),
        status,
        maybe_tag("MessageID", map["message_id"]),
        close_root("SubmitRsp")
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp encode_deliver_req(map) do
    xml = [
      open_root("DeliverReq"),
      tag("MM7Version", map["mm7_version"]),
      maybe_tag("MMSRelayServerID", map["mms_relay_server_id"]),
      maybe_tag("VASPID", map["vasp_id"]),
      maybe_tag("VASID", map["vas_id"]),
      maybe_tag("LinkedID", map["linked_id"]),
      wrap("Sender", encode_address(map["sender"])),
      encode_optional_recipients(map["recipients"]),
      maybe_tag("TimeStamp", map["time_stamp"]),
      maybe_tag("Priority", map["priority"]),
      maybe_tag("Subject", map["subject"]),
      maybe_tag("ApplicID", map["applic_id"]),
      maybe_tag("ReplyApplicID", map["reply_applic_id"]),
      maybe_tag("AuxApplicInfo", map["aux_applic_info"]),
      close_root("DeliverReq")
    ]

    {:ok, IO.iodata_to_binary(xml)}
  end

  defp encode_deliver_res(map) do
    with {:ok, status} <- encode_status(Map.get(map, "status", %{})) do
      xml = [
        open_root("DeliverRsp"),
        tag("MM7Version", map["mm7_version"]),
        status,
        maybe_tag("ServiceCode", map["service_code"]),
        close_root("DeliverRsp")
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp encode_sender_identification(nil), do: "<SenderIdentification/>"

  defp encode_sender_identification(sender_identification) do
    [
      "<SenderIdentification>",
      maybe_tag("VASPID", sender_identification["vasp_id"]),
      maybe_tag("VASID", sender_identification["vas_id"]),
      encode_optional_sender_address(sender_identification["sender_address"]),
      "</SenderIdentification>"
    ]
  end

  defp encode_optional_sender_address(nil), do: ""

  defp encode_optional_sender_address(address) do
    wrap("SenderAddress", encode_address(address))
  end

  defp encode_recipients(recipients) do
    [
      "<Recipients>",
      encode_recipient_group("To", recipients["to"]),
      encode_recipient_group("Cc", recipients["cc"]),
      encode_recipient_group("Bcc", recipients["bcc"]),
      "</Recipients>"
    ]
  end

  defp encode_optional_recipients(nil), do: ""
  defp encode_optional_recipients(recipients), do: encode_recipients(recipients)

  defp encode_recipient_group(_tag, nil), do: ""
  defp encode_recipient_group(_tag, []), do: ""

  defp encode_recipient_group(tag, list) do
    ["<", tag, ">", Enum.map(list, &encode_address/1), "</", tag, ">"]
  end

  defp encode_address(%{"kind" => kind, "value" => value} = address) do
    tag_name = @address_kind_to_tag[kind] || "Number"

    [
      "<",
      tag_name,
      encode_address_attrs(address),
      ">",
      escape(value),
      "</",
      tag_name,
      ">"
    ]
  end

  defp encode_address(_address), do: ""

  defp encode_address_attrs(address) do
    [
      maybe_attr("displayOnly", bool_to_text(address["display_only"])),
      maybe_attr("addressCoding", address["address_coding"]),
      maybe_attr("id", address["id"])
    ]
  end

  defp encode_status(status) do
    with {:ok, status_code} <- parse_positive_integer(status["status_code"], "status.status_code") do
      status_text = status["status_text"] || default_status_text(status_code)

      {:ok,
       [
         "<Status>",
         tag("StatusCode", Integer.to_string(status_code)),
         tag("StatusText", status_text),
         maybe_tag("Details", status["details"]),
         "</Status>"
       ]}
    end
  end

  defp default_status_text(1000), do: "Success"
  defp default_status_text(1100), do: "Partial success"
  defp default_status_text(2000), do: "Client error"
  defp default_status_text(3000), do: "Server error"
  defp default_status_text(4000), do: "Service error"
  defp default_status_text(_code), do: "Status"

  defp open_root(name), do: ["<", name, " xmlns=\"", @canonical_ns, "\">"]
  defp close_root(name), do: ["</", name, ">"]

  defp wrap(_name, ""), do: ""

  defp wrap(name, inner) do
    ["<", name, ">", inner, "</", name, ">"]
  end

  defp tag(name, value) do
    ["<", name, ">", escape(value), "</", name, ">"]
  end

  defp maybe_tag(_name, nil), do: ""
  defp maybe_tag(_name, ""), do: ""
  defp maybe_tag(name, value), do: tag(name, value)

  defp maybe_attr(_name, nil), do: ""
  defp maybe_attr(_name, ""), do: ""
  defp maybe_attr(name, value), do: [" ", name, "=\"", escape(value), "\""]

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape(value), do: value |> to_string() |> escape()

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp parse_positive_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> error(:invalid_structure, "expected positive integer", %{field: field})
    end
  end

  defp parse_positive_integer(_value, field) do
    error(:invalid_structure, "expected positive integer", %{field: field})
  end

  defp bool_to_text(true), do: "true"
  defp bool_to_text(false), do: "false"
  defp bool_to_text(_value), do: nil

  defp validate_string_fields(map, fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case Map.get(map, field) do
        nil -> {:cont, :ok}
        value when is_binary(value) and value != "" -> {:cont, :ok}
        _ -> {:halt, error(:invalid_structure, "field must be non-empty string", %{field: field})}
      end
    end)
  end

  defp validate_boolean_fields(map, fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case Map.get(map, field) do
        nil -> {:cont, :ok}
        true -> {:cont, :ok}
        false -> {:cont, :ok}
        _ -> {:halt, error(:invalid_structure, "field must be boolean", %{field: field})}
      end
    end)
  end

  defp optional_attr(node, name) do
    case Map.get(node.attrs, name) do
      nil -> {:ok, nil}
      "" -> error(:invalid_structure, "empty value is not allowed", %{element: name})
      value -> {:ok, value}
    end
  end

  defp parse_optional_xml_bool(nil, _field), do: {:ok, nil}
  defp parse_optional_xml_bool("true", _field), do: {:ok, true}
  defp parse_optional_xml_bool("1", _field), do: {:ok, true}
  defp parse_optional_xml_bool("false", _field), do: {:ok, false}
  defp parse_optional_xml_bool("0", _field), do: {:ok, false}

  defp parse_optional_xml_bool(_value, field) do
    error(:invalid_structure, "expected boolean", %{field: field})
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp error(code, message, details \\ %{}) do
    {:error, %{code: code, message: message, details: details}}
  end
end
