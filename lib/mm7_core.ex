defmodule MM7Core do
  @moduledoc """
  Минимальный stage-1 конвертер MM7 body-level сообщений.

  Поддерживаемые kind:
  - mm7_submit_req
  - mm7_submit_res
  - mm7_deliver_req
  - mm7_deliver_res

  Scope stage-1:
  - Только XML внутри SOAP Envelope.Body
  - Без SOAP header/envelope, MIME и href:cid обработки
  """

  @canonical_ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  @root_to_kind %{
    "SubmitReq" => "mm7_submit_req",
    "SubmitRsp" => "mm7_submit_res",
    "DeliverReq" => "mm7_deliver_req",
    "DeliverRsp" => "mm7_deliver_res"
  }

  @kind_to_root Map.new(@root_to_kind, fn {root, kind} -> {kind, root} end)
  @unsupported_stage_keys ["soap_envelope", "soap_header", "mime"]

  @submit_req_order [
    "MM7Version",
    "SenderIdentification",
    "Recipients",
    "ServiceCode",
    "LinkedID",
    "MessageClass",
    "TimeStamp",
    "ReplyCharging",
    "EarliestDeliveryTime",
    "ExpiryDate",
    "DeliveryReport",
    "ReadReply",
    "Priority",
    "Subject",
    "ChargedParty",
    "ChargedPartyID",
    "DistributionIndicator",
    "DeliveryCondition",
    "ApplicID",
    "ReplyApplicID",
    "AuxApplicInfo",
    "ContentClass",
    "DRMContent",
    "Content"
  ]

  @submit_rsp_order ["MM7Version", "Status", "MessageID"]

  @deliver_req_order [
    "MM7Version",
    "MMSRelayServerID",
    "VASPID",
    "VASID",
    "LinkedID",
    "Sender",
    "Recipients",
    "Previouslysentby",
    "Previouslysentdateandtime",
    "SenderSPI",
    "RecipientSPI",
    "TimeStamp",
    "ReplyChargingID",
    "Priority",
    "Subject",
    "ApplicID",
    "ReplyApplicID",
    "AuxApplicInfo",
    "UACapabilities",
    "Content"
  ]

  @deliver_rsp_order ["MM7Version", "Status", "ServiceCode"]

  @doc """
  Унифицированный conversion API.

  - XML body string -> {:ok, map}
  - JSON string/map with kind -> {:ok, xml_body}
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
    input |> stringify_keys() |> map_to_xml()
  end

  def convert(_input, _opts) do
    error(:unsupported_input_format, "unsupported input type")
  end

  defp json_to_xml(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> map_to_xml(decoded)
      {:ok, _} -> error(:invalid_json, "json root must be an object")
      {:error, reason} -> error(:invalid_json, "invalid json", %{reason: inspect(reason)})
    end
  end

  defp map_to_xml(map) do
    with :ok <- reject_unsupported_stage_keys(map),
         {:ok, kind} <- fetch_kind(map),
         {:ok, xml} <- encode_kind(kind, map) do
      {:ok, xml}
    end
  end

  defp fetch_kind(map) do
    case Map.get(map, "kind") do
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

  defp reject_unsupported_stage_keys(map) do
    case Enum.find(@unsupported_stage_keys, &Map.has_key?(map, &1)) do
      nil -> :ok
      key -> error(:unsupported_stage_feature, "unsupported stage feature", %{feature: key})
    end
  end

  defp xml_to_map(xml) do
    with :ok <- reject_soap_envelope(xml),
         :ok <- reject_soap_header(xml),
         :ok <- reject_mime_tokens(xml),
         :ok <- reject_dtd_entities(xml),
         {:ok, root} <- parse_xml_root(xml),
         {:ok, kind} <- detect_kind(root),
         :ok <- validate_namespace(root),
         {:ok, decoded} <- decode_kind(kind, root),
         :ok <- reject_mime_marker(decoded),
         :ok <- validate_mandatory(kind, decoded) do
      {:ok, Map.put(decoded, "kind", kind)}
    end
  end

  defp parse_xml_root(xml) do
    try do
      {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
      {:ok, doc}
    catch
      :exit, reason -> error(:invalid_xml, "invalid xml", %{reason: inspect(reason)})
    end
  end

  defp detect_kind(root) do
    name = x_name(root) |> Atom.to_string()

    case Map.get(@root_to_kind, name) do
      nil -> error(:unknown_xml_root, "unknown xml root", %{root: name})
      kind -> {:ok, kind}
    end
  end

  defp validate_namespace(root) do
    attrs = x_attrs(root)

    ns =
      Enum.find_value(attrs, fn attr ->
        case a_name(attr) do
          :xmlns -> to_string(a_value(attr))
          _ -> nil
        end
      end)

    if ns == @canonical_ns do
      :ok
    else
      error(:invalid_structure, "namespace mismatch", %{namespace: ns, expected: @canonical_ns})
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

  defp reject_mime_tokens(xml) do
    down = String.downcase(xml)

    if String.contains?(down, "multipart/") or String.contains?(down, "content-type:") do
      error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})
    else
      :ok
    end
  end

  defp reject_dtd_entities(xml) do
    if Regex.match?(~r/<!\s*(DOCTYPE|ENTITY)/i, xml) do
      error(:invalid_xml, "doctype/entity is not allowed")
    else
      :ok
    end
  end

  defp reject_mime_marker(%{"_mime_rejected" => true}) do
    error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})
  end

  defp reject_mime_marker(_), do: :ok

  defp decode_kind("mm7_submit_req", root), do: decode_submit_req(root)
  defp decode_kind("mm7_submit_res", root), do: decode_submit_res(root)
  defp decode_kind("mm7_deliver_req", root), do: decode_deliver_req(root)
  defp decode_kind("mm7_deliver_res", root), do: decode_deliver_res(root)

  defp encode_kind("mm7_submit_req", map), do: encode_submit_req(map)
  defp encode_kind("mm7_submit_res", map), do: encode_submit_res(map)
  defp encode_kind("mm7_deliver_req", map), do: encode_deliver_req(map)
  defp encode_kind("mm7_deliver_res", map), do: encode_deliver_res(map)

  defp decode_submit_req(root) do
    with :ok <- ensure_only_children(root, @submit_req_order),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, sender_identification} <- decode_sender_identification(root),
         {:ok, recipients} <- decode_recipients(root, "Recipients") do
      base = %{
        "mm7_version" => mm7_version,
        "sender_identification" => sender_identification,
        "recipients" => recipients
      }

      optional =
        base
        |> maybe_put_text(root, "service_code", "ServiceCode")
        |> maybe_put_text(root, "linked_id", "LinkedID")
        |> maybe_put_text(root, "message_class", "MessageClass")
        |> maybe_put_text(root, "time_stamp", "TimeStamp")
        |> maybe_put_reply_charging(root)
        |> maybe_put_text(root, "earliest_delivery_time", "EarliestDeliveryTime")
        |> maybe_put_text(root, "expiry_date", "ExpiryDate")
        |> maybe_put_bool(root, "delivery_report", "DeliveryReport")
        |> maybe_put_bool(root, "read_reply", "ReadReply")
        |> maybe_put_text(root, "priority", "Priority")
        |> maybe_put_text(root, "subject", "Subject")
        |> maybe_put_text(root, "charged_party", "ChargedParty")
        |> maybe_put_text(root, "charged_party_id", "ChargedPartyID")
        |> maybe_put_bool(root, "distribution_indicator", "DistributionIndicator")
        |> maybe_put_delivery_condition(root)
        |> maybe_put_text(root, "applic_id", "ApplicID")
        |> maybe_put_text(root, "reply_applic_id", "ReplyApplicID")
        |> maybe_put_text(root, "aux_applic_info", "AuxApplicInfo")
        |> maybe_put_text(root, "content_class", "ContentClass")
        |> maybe_put_bool(root, "drm_content", "DRMContent")
        |> maybe_put_content(root)

      {:ok, optional}
    end
  end

  defp decode_submit_res(root) do
    with :ok <- ensure_only_children(root, @submit_rsp_order),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, status} <- decode_status(root),
         {:ok, message_id} <- optional_text(root, "MessageID") do
      map = %{"mm7_version" => mm7_version, "status" => status}
      {:ok, maybe_put(map, "message_id", message_id)}
    end
  end

  defp decode_deliver_req(root) do
    with :ok <- ensure_only_children(root, @deliver_req_order),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, sender} <- required_address(root, "Sender") do
      base = %{"mm7_version" => mm7_version, "sender" => sender}

      decoded =
        base
        |> maybe_put_text(root, "mms_relay_server_id", "MMSRelayServerID")
        |> maybe_put_text(root, "vasp_id", "VASPID")
        |> maybe_put_text(root, "vas_id", "VASID")
        |> maybe_put_text(root, "linked_id", "LinkedID")
        |> maybe_put_recipients(root)
        |> maybe_put_text(root, "sender_spi", "SenderSPI")
        |> maybe_put_text(root, "recipient_spi", "RecipientSPI")
        |> maybe_put_text(root, "time_stamp", "TimeStamp")
        |> maybe_put_text(root, "reply_charging_id", "ReplyChargingID")
        |> maybe_put_text(root, "priority", "Priority")
        |> maybe_put_text(root, "subject", "Subject")
        |> maybe_put_text(root, "applic_id", "ApplicID")
        |> maybe_put_text(root, "reply_applic_id", "ReplyApplicID")
        |> maybe_put_text(root, "aux_applic_info", "AuxApplicInfo")
        |> maybe_put_uacapabilities(root)
        |> maybe_put_content(root)

      with :ok <- reject_if_present(root, "Previouslysentby"),
           :ok <- reject_if_present(root, "Previouslysentdateandtime") do
        {:ok, decoded}
      end
    end
  end

  defp decode_deliver_res(root) do
    with :ok <- ensure_only_children(root, @deliver_rsp_order),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, status} <- decode_status(root),
         {:ok, service_code} <- optional_text(root, "ServiceCode") do
      map = %{"mm7_version" => mm7_version, "status" => status}
      {:ok, maybe_put(map, "service_code", service_code)}
    end
  end

  defp encode_submit_req(map) do
    with :ok <- validate_mandatory("mm7_submit_req", map),
         {:ok, mm7_version} <- fetch_string(map, "mm7_version"),
         {:ok, recipients} <- fetch_recipients(map) do
      sender_identification = encode_sender_identification(map)

      xml = [
        "<SubmitReq xmlns=\"",
        @canonical_ns,
        "\">",
        tag("MM7Version", mm7_version),
        sender_identification,
        encode_recipients(recipients),
        encode_optional_submit_req(map),
        "</SubmitReq>"
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp encode_submit_res(map) do
    with :ok <- validate_mandatory("mm7_submit_res", map),
         {:ok, mm7_version} <- fetch_string(map, "mm7_version"),
         {:ok, status} <- fetch_status(map),
         {:ok, message_id} <- maybe_required_submit_message_id(map, status) do
      xml = [
        "<SubmitRsp xmlns=\"",
        @canonical_ns,
        "\">",
        tag("MM7Version", mm7_version),
        encode_status(status),
        maybe_tag("MessageID", message_id),
        "</SubmitRsp>"
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp encode_deliver_req(map) do
    with :ok <- validate_mandatory("mm7_deliver_req", map),
         {:ok, mm7_version} <- fetch_string(map, "mm7_version"),
         {:ok, sender} <- fetch_address(map, "sender"),
         :ok <- reject_encode_deliver_unsupported(map),
         :ok <- reject_content_cid(map) do
      xml = [
        "<DeliverReq xmlns=\"",
        @canonical_ns,
        "\">",
        tag("MM7Version", mm7_version),
        maybe_tag("MMSRelayServerID", map["mms_relay_server_id"]),
        maybe_tag("VASPID", map["vasp_id"]),
        maybe_tag("VASID", map["vas_id"]),
        maybe_tag("LinkedID", map["linked_id"]),
        wrap("Sender", encode_address(sender)),
        encode_optional_recipients(map),
        maybe_tag("SenderSPI", map["sender_spi"]),
        maybe_tag("RecipientSPI", map["recipient_spi"]),
        maybe_tag("TimeStamp", map["time_stamp"]),
        maybe_tag("ReplyChargingID", map["reply_charging_id"]),
        maybe_tag("Priority", map["priority"]),
        maybe_tag("Subject", map["subject"]),
        maybe_tag("ApplicID", map["applic_id"]),
        maybe_tag("ReplyApplicID", map["reply_applic_id"]),
        maybe_tag("AuxApplicInfo", map["aux_applic_info"]),
        encode_uacapabilities(map),
        encode_optional_content(map),
        "</DeliverReq>"
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp encode_deliver_res(map) do
    with :ok <- validate_mandatory("mm7_deliver_res", map),
         {:ok, mm7_version} <- fetch_string(map, "mm7_version"),
         {:ok, status} <- fetch_status(map) do
      xml = [
        "<DeliverRsp xmlns=\"",
        @canonical_ns,
        "\">",
        tag("MM7Version", mm7_version),
        encode_status(status),
        maybe_tag("ServiceCode", map["service_code"]),
        "</DeliverRsp>"
      ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp validate_mandatory("mm7_submit_req", map) do
    missing =
      []
      |> maybe_missing(map, "mm7_version")
      |> maybe_missing_recipients(map)

    if missing == [] do
      :ok
    else
      error(:missing_mandatory_fields, "missing mandatory fields", %{
        kind: "mm7_submit_req",
        fields: missing
      })
    end
  end

  defp validate_mandatory("mm7_submit_res", map) do
    missing =
      []
      |> maybe_missing(map, "mm7_version")
      |> maybe_missing_status_code(map)

    if missing == [] do
      :ok
    else
      error(:missing_mandatory_fields, "missing mandatory fields", %{
        kind: "mm7_submit_res",
        fields: missing
      })
    end
  end

  defp validate_mandatory("mm7_deliver_req", map) do
    missing =
      []
      |> maybe_missing(map, "mm7_version")
      |> maybe_missing(map, "sender")

    if missing == [] do
      :ok
    else
      error(:missing_mandatory_fields, "missing mandatory fields", %{
        kind: "mm7_deliver_req",
        fields: missing
      })
    end
  end

  defp validate_mandatory("mm7_deliver_res", map) do
    missing =
      []
      |> maybe_missing(map, "mm7_version")
      |> maybe_missing_status_code(map)

    if missing == [] do
      :ok
    else
      error(:missing_mandatory_fields, "missing mandatory fields", %{
        kind: "mm7_deliver_res",
        fields: missing
      })
    end
  end

  defp validate_mandatory(_kind, _map), do: :ok

  defp maybe_missing(list, map, key) do
    if present?(map[key]), do: list, else: list ++ [key]
  end

  defp maybe_missing_status_code(list, map) do
    case map do
      %{"status" => %{"status_code" => value}} when not is_nil(value) -> list
      _ -> list ++ ["status.status_code"]
    end
  end

  defp maybe_missing_recipients(list, map) do
    case map do
      %{"recipients" => recipients} when is_map(recipients) ->
        total =
          recipients
          |> Map.values()
          |> Enum.filter(&is_list/1)
          |> Enum.map(&length/1)
          |> Enum.sum()

        if total > 0, do: list, else: list ++ ["recipients"]

      _ ->
        list ++ ["recipients"]
    end
  end

  defp ensure_only_children(root, allowed) do
    unknown =
      root
      |> child_elements()
      |> Enum.map(&(x_name(&1) |> Atom.to_string()))
      |> Enum.reject(&(&1 in allowed))

    if unknown == [] do
      :ok
    else
      error(:invalid_structure, "unexpected child elements", %{unknown: unknown})
    end
  end

  defp decode_sender_identification(root) do
    case find_child(root, "SenderIdentification") do
      nil ->
        error(:invalid_structure, "missing SenderIdentification")

      sender ->
        with :ok <- ensure_only_children(sender, ["VASPID", "VASID", "SenderAddress"]),
             {:ok, sender_address} <- optional_address(sender, "SenderAddress") do
          map =
            %{}
            |> maybe_put("vasp_id", text_value(sender, "VASPID"))
            |> maybe_put("vas_id", text_value(sender, "VASID"))
            |> maybe_put("sender_address", sender_address)

          {:ok, map}
        end
    end
  end

  defp decode_recipients(root, tag_name) do
    case find_child(root, tag_name) do
      nil -> error(:invalid_structure, "missing #{tag_name}")
      recipients -> decode_recipients_node(recipients)
    end
  end

  defp decode_recipients_node(recipients) do
    with :ok <- ensure_only_children(recipients, ["To", "Cc", "Bcc"]) do
      entries =
        recipients
        |> child_elements()
        |> Enum.reduce(%{"to" => [], "cc" => [], "bcc" => []}, fn entry, acc ->
          key =
            case x_name(entry) |> Atom.to_string() do
              "To" -> "to"
              "Cc" -> "cc"
              "Bcc" -> "bcc"
            end

          addresses = decode_address_list(entry)
          Map.update!(acc, key, &(&1 ++ addresses))
        end)

      {:ok, entries}
    end
  end

  defp decode_address_list(container) do
    container
    |> child_elements()
    |> Enum.map(&decode_address_element/1)
  end

  defp decode_address_element(address_elem) do
    name = x_name(address_elem) |> Atom.to_string()

    base =
      case name do
        "RFC2822Address" -> %{"kind" => "rfc2822_address", "value" => text_of(address_elem)}
        "Number" -> %{"kind" => "number", "value" => text_of(address_elem)}
        "ShortCode" -> %{"kind" => "short_code", "value" => text_of(address_elem)}
      end

    attrs = attributes_map(address_elem)

    base
    |> maybe_put("display_only", parse_bool(attrs["displayOnly"]))
    |> maybe_put("address_coding", attrs["addressCoding"])
    |> maybe_put("id", attrs["id"])
  end

  defp required_address(root, tag_name) do
    case find_child(root, tag_name) do
      nil ->
        error(:invalid_structure, "missing #{tag_name}")

      address_node ->
        case child_elements(address_node) do
          [single] -> {:ok, decode_address_element(single)}
          _ -> error(:invalid_structure, "invalid address structure", %{element: tag_name})
        end
    end
  end

  defp optional_address(root, tag_name) do
    case find_child(root, tag_name) do
      nil ->
        {:ok, nil}

      node ->
        case child_elements(node) do
          [single] -> {:ok, decode_address_element(single)}
          _ -> error(:invalid_structure, "invalid address structure", %{element: tag_name})
        end
    end
  end

  defp decode_status(root) do
    case find_child(root, "Status") do
      nil ->
        error(:invalid_structure, "missing Status")

      status ->
        with :ok <- ensure_only_children(status, ["StatusCode", "StatusText", "Details"]),
             {:ok, status_code_text} <- required_text(status, "StatusCode"),
             {:ok, status_code} <- parse_positive_integer(status_code_text, "status.status_code"),
             {:ok, status_text} <- optional_text(status, "StatusText") do
          details = details_text(status)

          {:ok,
           %{}
           |> Map.put("status_code", status_code)
           |> maybe_put("status_text", status_text)
           |> maybe_put("details", details)}
        end
    end
  end

  defp details_text(status) do
    case find_child(status, "Details") do
      nil ->
        nil

      details ->
        text = text_of(details)
        if text == "", do: nil, else: text
    end
  end

  defp required_text(root, child_name) do
    case optional_text(root, child_name) do
      {:ok, nil} -> error(:invalid_structure, "missing #{child_name}")
      {:ok, value} -> {:ok, value}
      {:error, _} = err -> err
    end
  end

  defp optional_text(root, child_name) do
    case find_child(root, child_name) do
      nil ->
        {:ok, nil}

      child ->
        value = text_of(child)

        if value == "" do
          error(:invalid_structure, "empty value is not allowed", %{element: child_name})
        else
          {:ok, value}
        end
    end
  end

  defp text_value(root, child_name) do
    case optional_text(root, child_name) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp maybe_put_text(map, root, json_key, xml_name) do
    case optional_text(root, xml_name) do
      {:ok, nil} -> map
      {:ok, value} -> Map.put(map, json_key, value)
      _ -> map
    end
  end

  defp maybe_put_bool(map, root, json_key, xml_name) do
    case optional_text(root, xml_name) do
      {:ok, nil} -> map
      {:ok, value} -> Map.put(map, json_key, parse_bool(value))
      _ -> map
    end
  end

  defp maybe_put_recipients(map, root) do
    case find_child(root, "Recipients") do
      nil ->
        map

      node ->
        {:ok, decoded} = decode_recipients_node(node)
        Map.put(map, "recipients", decoded)
    end
  end

  defp maybe_put_reply_charging(map, root) do
    case find_child(root, "ReplyCharging") do
      nil ->
        map

      node ->
        attrs = attributes_map(node)

        reply_charging =
          %{}
          |> maybe_put("reply_charging_size", parse_int_or_nil(attrs["replyChargingSize"]))
          |> maybe_put("reply_deadline", attrs["replyDeadline"])

        if map_size(reply_charging) == 0 do
          Map.put(map, "reply_charging", %{})
        else
          Map.put(map, "reply_charging", reply_charging)
        end
    end
  end

  defp maybe_put_delivery_condition(map, root) do
    case find_child(root, "DeliveryCondition") do
      nil ->
        map

      node ->
        if Enum.all?(child_elements(node), fn c -> x_name(c) == :DC end) do
          values =
            node
            |> child_elements()
            |> Enum.map(&text_of/1)
            |> Enum.map(&String.to_integer/1)

          Map.put(map, "delivery_condition", %{"dc" => values})
        else
          map
        end
    end
  end

  defp maybe_put_uacapabilities(map, root) do
    case find_child(root, "UACapabilities") do
      nil ->
        map

      node ->
        attrs = attributes_map(node)

        cap =
          %{}
          |> maybe_put("uaprof", attrs["UAProf"])
          |> maybe_put("time_stamp", attrs["TimeStamp"])

        Map.put(map, "ua_capabilities", cap)
    end
  end

  defp maybe_put_content(map, root) do
    case find_child(root, "Content") do
      nil ->
        map

      content ->
        attrs = attributes_map(content)
        href = attrs["href"]

        if is_binary(href) and String.starts_with?(String.downcase(href), "cid:") do
          Map.put(map, "_mime_rejected", true)
        else
          Map.put(
            map,
            "content",
            %{}
            |> maybe_put("href", href)
            |> maybe_put("allow_adaptations", parse_bool(attrs["allowAdaptations"]))
          )
        end
    end
  end

  defp reject_if_present(root, tag_name) do
    if find_child(root, tag_name) do
      error(:unsupported_stage_feature, "unsupported stage feature", %{
        feature: "mime",
        element: tag_name
      })
    else
      :ok
    end
  end

  defp reject_encode_deliver_unsupported(map) do
    if Map.has_key?(map, "previouslysentby") or Map.has_key?(map, "previouslysentdateandtime") do
      error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})
    else
      :ok
    end
  end

  defp reject_content_cid(map) do
    case map do
      %{"content" => %{"href" => href}} when is_binary(href) ->
        if String.starts_with?(String.downcase(href), "cid:") do
          error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp maybe_required_submit_message_id(map, status) do
    code = status["status_code"]
    message_id = map["message_id"]

    cond do
      code == 1000 and not present?(message_id) ->
        error(:missing_mandatory_fields, "missing mandatory fields", %{
          kind: "mm7_submit_res",
          fields: ["message_id"]
        })

      present?(message_id) ->
        {:ok, message_id}

      true ->
        {:ok, nil}
    end
  end

  defp fetch_status(map) do
    case map["status"] do
      %{} = status ->
        with {:ok, code} <- parse_positive_integer(status["status_code"], "status.status_code") do
          status_text =
            if present?(status["status_text"]) do
              status["status_text"]
            else
              default_status_text(code)
            end

          {:ok,
           %{"status_code" => code, "status_text" => status_text, "details" => status["details"]}}
        end

      _ ->
        error(:invalid_structure, "status must be object")
    end
  end

  defp default_status_text(1000), do: "Success"
  defp default_status_text(_), do: "Status"

  defp fetch_recipients(map) do
    case map["recipients"] do
      %{} = recipients -> {:ok, recipients}
      _ -> error(:invalid_structure, "recipients must be object")
    end
  end

  defp fetch_address(map, key) do
    case map[key] do
      %{} = address -> {:ok, address}
      _ -> error(:invalid_structure, "#{key} must be object")
    end
  end

  defp fetch_string(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> error(:invalid_structure, "#{key} must be non-empty string")
    end
  end

  defp encode_sender_identification(map) do
    case map["sender_identification"] do
      nil ->
        "<SenderIdentification/>"

      %{} = sender ->
        [
          "<SenderIdentification>",
          maybe_tag("VASPID", sender["vasp_id"]),
          maybe_tag("VASID", sender["vas_id"]),
          encode_sender_address(sender["sender_address"]),
          "</SenderIdentification>"
        ]

      _ ->
        "<SenderIdentification/>"
    end
  end

  defp encode_sender_address(nil), do: ""

  defp encode_sender_address(%{} = address) do
    wrap("SenderAddress", encode_address(address))
  end

  defp encode_recipients(%{} = recipients) do
    to = encode_recipient_group("To", recipients["to"])
    cc = encode_recipient_group("Cc", recipients["cc"])
    bcc = encode_recipient_group("Bcc", recipients["bcc"])
    ["<Recipients>", to, cc, bcc, "</Recipients>"]
  end

  defp encode_optional_recipients(map) do
    case map["recipients"] do
      %{} = recipients -> encode_recipients(recipients)
      _ -> ""
    end
  end

  defp encode_recipient_group(_tag, nil), do: ""

  defp encode_recipient_group(tag, list) when is_list(list) do
    if list == [] do
      ""
    else
      ["<", tag, ">", Enum.map(list, &encode_address/1), "</", tag, ">"]
    end
  end

  defp encode_recipient_group(_tag, _), do: ""

  defp encode_address(%{"kind" => kind, "value" => value} = address) when is_binary(value) do
    {tag_name, attrs} =
      case kind do
        "rfc2822_address" -> {"RFC2822Address", encode_address_attrs(address)}
        "short_code" -> {"ShortCode", encode_address_attrs(address)}
        _ -> {"Number", encode_address_attrs(address)}
      end

    ["<", tag_name, attrs, ">", escape_text(value), "</", tag_name, ">"]
  end

  defp encode_address(_), do: ""

  defp encode_address_attrs(address) do
    [
      maybe_attr("displayOnly", address["display_only"]),
      maybe_attr("addressCoding", address["address_coding"]),
      maybe_attr("id", address["id"])
    ]
  end

  defp encode_optional_submit_req(map) do
    reply_charging = encode_reply_charging(map["reply_charging"])
    delivery_condition = encode_delivery_condition(map["delivery_condition"])

    [
      maybe_tag("ServiceCode", map["service_code"]),
      maybe_tag("LinkedID", map["linked_id"]),
      maybe_tag("MessageClass", map["message_class"]),
      maybe_tag("TimeStamp", map["time_stamp"]),
      reply_charging,
      maybe_tag("EarliestDeliveryTime", map["earliest_delivery_time"]),
      maybe_tag("ExpiryDate", map["expiry_date"]),
      maybe_tag("DeliveryReport", bool_to_text(map["delivery_report"])),
      maybe_tag("ReadReply", bool_to_text(map["read_reply"])),
      maybe_tag("Priority", map["priority"]),
      maybe_tag("Subject", map["subject"]),
      maybe_tag("ChargedParty", map["charged_party"]),
      maybe_tag("ChargedPartyID", map["charged_party_id"]),
      maybe_tag("DistributionIndicator", bool_to_text(map["distribution_indicator"])),
      delivery_condition,
      maybe_tag("ApplicID", map["applic_id"]),
      maybe_tag("ReplyApplicID", map["reply_applic_id"]),
      maybe_tag("AuxApplicInfo", map["aux_applic_info"]),
      maybe_tag("ContentClass", map["content_class"]),
      maybe_tag("DRMContent", bool_to_text(map["drm_content"])),
      encode_optional_content(map)
    ]
  end

  defp encode_optional_content(map) do
    case map["content"] do
      %{} = content ->
        href = content["href"]

        cond do
          not is_binary(href) or href == "" ->
            ""

          String.starts_with?(String.downcase(href), "cid:") ->
            ""

          true ->
            [
              "<Content",
              maybe_attr("href", href),
              maybe_attr("allowAdaptations", bool_to_text(content["allow_adaptations"])),
              "/>"
            ]
        end

      _ ->
        ""
    end
  end

  defp encode_reply_charging(nil), do: ""

  defp encode_reply_charging(%{} = reply) do
    [
      "<ReplyCharging",
      maybe_attr("replyChargingSize", reply["reply_charging_size"]),
      maybe_attr("replyDeadline", reply["reply_deadline"]),
      "/>"
    ]
  end

  defp encode_reply_charging(_), do: ""

  defp encode_delivery_condition(nil), do: ""

  defp encode_delivery_condition(%{"dc" => list}) when is_list(list) do
    items = Enum.map(list, fn v -> tag("DC", to_string(v)) end)
    ["<DeliveryCondition>", items, "</DeliveryCondition>"]
  end

  defp encode_delivery_condition(_), do: ""

  defp encode_uacapabilities(map) do
    case map["ua_capabilities"] do
      %{} = cap ->
        [
          "<UACapabilities",
          maybe_attr("UAProf", cap["uaprof"]),
          maybe_attr("TimeStamp", cap["time_stamp"]),
          "/>"
        ]

      _ ->
        ""
    end
  end

  defp encode_status(%{"status_code" => status_code} = status) do
    [
      "<Status>",
      tag("StatusCode", to_string(status_code)),
      maybe_tag("StatusText", status["status_text"]),
      maybe_tag("Details", status["details"]),
      "</Status>"
    ]
  end

  defp child_elements(root) do
    root
    |> x_content()
    |> Enum.filter(&element?(&1))
  end

  defp find_child(root, child_name) do
    Enum.find(child_elements(root), fn child ->
      x_name(child) |> Atom.to_string() == child_name
    end)
  end

  defp text_of(node) do
    node
    |> x_content()
    |> Enum.filter(&text_node?(&1))
    |> Enum.map(&t_value(&1))
    |> Enum.map(&to_string/1)
    |> Enum.join("")
    |> String.trim()
  end

  defp attributes_map(node) do
    node
    |> x_attrs()
    |> Enum.reduce(%{}, fn attr, acc ->
      name = a_name(attr) |> Atom.to_string()
      Map.put(acc, name, to_string(a_value(attr)))
    end)
  end

  defp element?({:xmlElement, _, _, _, _, _, _, _, _, _, _, _}), do: true
  defp element?(_), do: false

  defp text_node?({:xmlText, _, _, _, _, _}), do: true
  defp text_node?(_), do: false

  defp x_name({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}), do: name
  defp x_attrs({:xmlElement, _, _, _, _, _, _, attrs, _, _, _, _}), do: attrs
  defp x_content({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}), do: content

  defp a_name({:xmlAttribute, name, _, _, _, _, _, _, _, _}), do: name
  defp a_value({:xmlAttribute, _, _, _, _, _, _, _, value, _}), do: value

  defp t_value({:xmlText, _, _, _, value, _}), do: value

  defp parse_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp parse_positive_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> error(:invalid_structure, "#{field} must be positive integer")
    end
  end

  defp parse_positive_integer(_value, field) do
    error(:invalid_structure, "#{field} must be positive integer")
  end

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(value) when is_integer(value), do: value

  defp parse_int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int_or_nil(_), do: nil

  defp parse_bool(nil), do: nil
  defp parse_bool(true), do: true
  defp parse_bool(false), do: false

  defp parse_bool(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "false" -> false
      "1" -> true
      "0" -> false
      _ -> nil
    end
  end

  defp parse_bool(_), do: nil

  defp bool_to_text(true), do: "true"
  defp bool_to_text(false), do: "false"
  defp bool_to_text(_), do: nil

  defp tag(name, value), do: ["<", name, ">", escape_text(value), "</", name, ">"]
  defp maybe_tag(_name, nil), do: ""

  defp maybe_tag(name, value) do
    value = to_string(value)
    if value == "", do: "", else: tag(name, value)
  end

  defp maybe_attr(_name, nil), do: ""

  defp maybe_attr(name, value) do
    value = to_string(value)
    if value == "", do: "", else: [" ", name, "=\"", escape_attr(value), "\""]
  end

  defp wrap(name, inner), do: ["<", name, ">", inner, "</", name, ">"]

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(nil), do: false
  defp present?(value), do: value != nil

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      key = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
      Map.put(acc, key, stringify_keys(v))
    end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp escape_text(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(value) do
    value
    |> escape_text()
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp error(code, message, details \\ %{}) do
    {:error, %{code: code, message: message, details: details}}
  end
end
