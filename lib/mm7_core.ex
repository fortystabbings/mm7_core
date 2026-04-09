defmodule MM7Core do
  @moduledoc """
  Минимальный stage-1 конвертер MM7 body-level сообщений (без SOAP/MIME).
  """

  @mm7_ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  @root_to_kind %{
    "SubmitReq" => :mm7_submit_req,
    "SubmitRsp" => :mm7_submit_res,
    "DeliverReq" => :mm7_deliver_req,
    "DeliverRsp" => :mm7_deliver_res
  }

  @kind_to_root Map.new(@root_to_kind, fn {root, kind} -> {kind, root} end)
  @supported_kinds [:mm7_submit_req, :mm7_submit_res, :mm7_deliver_req, :mm7_deliver_res]

  @type error_code ::
          :unsupported_input_format
          | :invalid_xml
          | :invalid_json
          | :missing_kind
          | :unknown_kind
          | :unknown_xml_root
          | :missing_mandatory_fields
          | :invalid_structure
          | :unsupported_stage_feature

  @type structured_error :: %{
          code: error_code,
          message: String.t(),
          details: map()
        }

  @spec convert(binary() | map(), keyword()) ::
          {:ok, map() | String.t()} | {:error, structured_error}
  def convert(input, opts \\ [])

  def convert(input, _opts) when is_binary(input) do
    trimmed = String.trim_leading(input)

    cond do
      trimmed == "" ->
        error(:unsupported_input_format, "Input payload is empty")

      String.starts_with?(trimmed, "<") ->
        xml_to_map(trimmed)

      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        json_to_xml(trimmed)

      mime_payload?(trimmed) ->
        unsupported_feature(:mime)

      true ->
        error(:unsupported_input_format, "Only XML body or JSON payload is supported")
    end
  end

  def convert(input, _opts) when is_map(input) do
    map_to_xml(input)
  end

  def convert(_input, _opts) do
    error(:unsupported_input_format, "Input must be XML string, JSON string or map")
  end

  defp xml_to_map(xml) do
    with {:ok, kind} <- detect_xml_kind(xml),
         {:ok, root} <- parse_xml(xml),
         :ok <- ensure_root(kind, root),
         {:ok, decoded} <- decode(kind, root),
         :ok <- ensure_no_invalid_values(decoded),
         :ok <- validate_stage_mandatory(decoded) do
      {:ok, decoded}
    end
  end

  defp json_to_xml(json_binary) do
    case Jason.decode(json_binary) do
      {:ok, decoded} when is_map(decoded) -> map_to_xml(decoded)
      {:ok, _decoded} -> error(:invalid_json, "JSON root must be an object")
      {:error, reason} -> error(:invalid_json, "JSON decode failed", %{reason: inspect(reason)})
    end
  end

  defp map_to_xml(map) do
    with :ok <- check_stage_flags(map),
         {:ok, kind} <- extract_kind(map),
         :ok <- validate_stage_mandatory(map, kind),
         {:ok, xml} <- encode(kind, map) do
      {:ok, xml}
    end
  end

  defp check_stage_flags(map) do
    cond do
      has_any_key?(map, :soap_envelope) -> unsupported_feature(:soap_envelope)
      has_any_key?(map, :soap_header) -> unsupported_feature(:soap_header)
      has_any_key?(map, :mime) -> unsupported_feature(:mime)
      true -> :ok
    end
  end

  defp validate_stage_mandatory(map, kind \\ nil)

  defp validate_stage_mandatory(map, nil) do
    with {:ok, extracted_kind} <- extract_kind(map) do
      validate_stage_mandatory(map, extracted_kind)
    end
  end

  defp validate_stage_mandatory(map, :mm7_submit_req) do
    require_fields(map, [[:kind], [:mm7_version], [:recipients]])
  end

  defp validate_stage_mandatory(map, :mm7_submit_res) do
    require_fields(map, [[:kind], [:mm7_version], [:status, :status_code]])
  end

  defp validate_stage_mandatory(map, :mm7_deliver_req) do
    require_fields(map, [[:kind], [:mm7_version], [:sender]])
  end

  defp validate_stage_mandatory(map, :mm7_deliver_res) do
    require_fields(map, [[:kind], [:mm7_version], [:status, :status_code]])
  end

  defp validate_stage_mandatory(_map, _kind) do
    error(:unknown_kind, "Unsupported kind")
  end

  defp require_fields(map, paths) do
    missing =
      Enum.reduce(paths, [], fn path, acc ->
        if present?(get_path(map, path)), do: acc, else: [format_path(path) | acc]
      end)
      |> Enum.reverse()

    case missing do
      [] -> :ok
      fields -> error(:missing_mandatory_fields, "Missing mandatory fields", %{fields: fields})
    end
  end

  defp extract_kind(map) do
    case fetch_any(map, :kind) do
      nil ->
        error(:missing_kind, "Field 'kind' is required")

      kind when is_atom(kind) and kind in @supported_kinds ->
        {:ok, kind}

      kind when is_binary(kind) ->
        case normalize_kind(kind) do
          nil -> error(:unknown_kind, "Unknown kind", %{kind: kind})
          parsed -> {:ok, parsed}
        end

      kind ->
        error(:unknown_kind, "Kind must be string or atom", %{kind: inspect(kind)})
    end
  end

  defp normalize_kind(kind) do
    case String.trim(kind) do
      "mm7_submit_req" -> :mm7_submit_req
      "mm7_submit_res" -> :mm7_submit_res
      "mm7_deliver_req" -> :mm7_deliver_req
      "mm7_deliver_res" -> :mm7_deliver_res
      _ -> nil
    end
  end

  defp detect_xml_kind(xml) do
    cleaned = strip_leading_xml_preamble(xml)

    case Regex.run(~r/\A<\s*(?:[A-Za-z_][\w.-]*:)?([A-Za-z_][\w.-]*)\b/s, cleaned) do
      [_, "Envelope"] ->
        unsupported_feature(:soap_envelope)

      [_, "Header"] ->
        unsupported_feature(:soap_header)

      [_, root] ->
        case Map.fetch(@root_to_kind, root) do
          {:ok, kind} -> {:ok, kind}
          :error -> error(:unknown_xml_root, "Unknown XML root", %{root: root})
        end

      _ ->
        error(:invalid_xml, "Cannot detect XML root element")
    end
  end

  defp strip_leading_xml_preamble(xml) do
    xml
    |> String.trim_leading()
    |> strip_xml_decl()
    |> strip_xml_comment()
  end

  defp strip_xml_decl(xml) do
    case Regex.run(~r/\A<\?xml.*?\?>\s*/s, xml) do
      [decl] -> String.trim_leading(String.replace_prefix(xml, decl, ""))
      _ -> xml
    end
  end

  defp strip_xml_comment(xml) do
    case Regex.run(~r/\A<!--.*?-->\s*/s, xml) do
      [comment] ->
        xml
        |> String.replace_prefix(comment, "")
        |> String.trim_leading()
        |> strip_xml_comment()

      _ ->
        xml
    end
  end

  defp parse_xml(xml) do
    down = String.downcase(xml)

    cond do
      String.contains?(down, "<!doctype") ->
        error(:invalid_xml, "DTD is not allowed")

      String.contains?(down, "<!entity") ->
        error(:invalid_xml, "ENTITY declarations are not allowed")

      true ->
        try do
          {root, _tail} = :xmerl_scan.string(String.to_charlist(xml), quiet: true)
          {:ok, root}
        catch
          :exit, reason -> error(:invalid_xml, "XML parse failed", %{reason: inspect(reason)})
          :error, reason -> error(:invalid_xml, "XML parse failed", %{reason: inspect(reason)})
        end
    end
  end

  defp ensure_root(kind, root) do
    expected_root = Map.fetch!(@kind_to_root, kind)
    root_name = local_name(root)
    root_ns = element_namespace(root)

    cond do
      root_name != expected_root ->
        error(:invalid_structure, "Root does not match detected kind", %{
          expected: expected_root,
          actual: root_name
        })

      root_ns != @mm7_ns ->
        error(:invalid_structure, "MM7 namespace mismatch", %{
          expected: @mm7_ns,
          actual: root_ns
        })

      true ->
        :ok
    end
  end

  defp decode(:mm7_submit_req, root), do: decode_submit_req(root)
  defp decode(:mm7_submit_res, root), do: decode_submit_res(root)
  defp decode(:mm7_deliver_req, root), do: decode_deliver_req(root)
  defp decode(:mm7_deliver_res, root), do: decode_deliver_res(root)

  defp decode_submit_req(root) do
    allowed = [
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

    with :ok <- ensure_only_allowed_children(root, allowed),
         {:ok, mm7_version} <- required_text(root, "MM7Version", "mm7_version"),
         {:ok, sender_identification_el} <-
           required_child(root, "SenderIdentification", "sender_identification"),
         {:ok, sender_identification} <- parse_sender_identification(sender_identification_el),
         {:ok, recipients_el} <- required_child(root, "Recipients", "recipients"),
         {:ok, recipients} <- parse_recipients(recipients_el) do
      map =
        %{
          kind: "mm7_submit_req",
          mm7_version: mm7_version,
          sender_identification: sender_identification,
          recipients: recipients
        }
        |> put_optional_text(root, "ServiceCode", :service_code)
        |> put_optional_text(root, "LinkedID", :linked_id)
        |> put_optional_text(root, "MessageClass", :message_class)
        |> put_optional_text(root, "TimeStamp", :time_stamp)
        |> put_optional_text(root, "EarliestDeliveryTime", :earliest_delivery_time)
        |> put_optional_text(root, "ExpiryDate", :expiry_date)
        |> put_optional_bool(root, "DeliveryReport", :delivery_report)
        |> put_optional_bool(root, "ReadReply", :read_reply)
        |> put_optional_text(root, "Priority", :priority)
        |> put_optional_text(root, "Subject", :subject)
        |> put_optional_text(root, "ChargedParty", :charged_party)
        |> put_optional_text(root, "ChargedPartyID", :charged_party_id)
        |> put_optional_bool(root, "DistributionIndicator", :distribution_indicator)
        |> put_optional_text(root, "ApplicID", :applic_id)
        |> put_optional_text(root, "ReplyApplicID", :reply_applic_id)
        |> put_optional_text(root, "AuxApplicInfo", :aux_applic_info)
        |> put_optional_text(root, "ContentClass", :content_class)
        |> put_optional_bool(root, "DRMContent", :drm_content)

      with {:ok, map} <- put_optional_reply_charging(map, root),
           {:ok, map} <- put_optional_delivery_condition(map, root),
           {:ok, map} <- put_optional_content(map, root) do
        {:ok, map}
      end
    end
  end

  defp decode_submit_res(root) do
    with :ok <- ensure_only_allowed_children(root, ["MM7Version", "Status", "MessageID"]),
         {:ok, mm7_version} <- required_text(root, "MM7Version", "mm7_version"),
         {:ok, status_el} <- required_child(root, "Status", "status"),
         {:ok, status} <- parse_status(status_el),
         {:ok, message_id} <- required_text(root, "MessageID", "message_id") do
      {:ok,
       %{
         kind: "mm7_submit_res",
         mm7_version: mm7_version,
         status: status,
         message_id: message_id
       }}
    end
  end

  defp decode_deliver_req(root) do
    allowed = [
      "MM7Version",
      "MMSRelayServerID",
      "VASPID",
      "VASID",
      "LinkedID",
      "Sender",
      "Recipients",
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

    with :ok <- ensure_only_allowed_children(root, allowed),
         {:ok, mm7_version} <- required_text(root, "MM7Version", "mm7_version"),
         {:ok, sender_el} <- required_child(root, "Sender", "sender"),
         {:ok, sender} <- parse_address_container(sender_el, "sender") do
      map =
        %{
          kind: "mm7_deliver_req",
          mm7_version: mm7_version,
          sender: sender
        }
        |> put_optional_text(root, "MMSRelayServerID", :mms_relay_server_id)
        |> put_optional_text(root, "VASPID", :vasp_id)
        |> put_optional_text(root, "VASID", :vas_id)
        |> put_optional_text(root, "LinkedID", :linked_id)
        |> put_optional_text(root, "SenderSPI", :sender_spi)
        |> put_optional_text(root, "RecipientSPI", :recipient_spi)
        |> put_optional_text(root, "TimeStamp", :time_stamp)
        |> put_optional_text(root, "ReplyChargingID", :reply_charging_id)
        |> put_optional_text(root, "Priority", :priority)
        |> put_optional_text(root, "Subject", :subject)
        |> put_optional_text(root, "ApplicID", :applic_id)
        |> put_optional_text(root, "ReplyApplicID", :reply_applic_id)
        |> put_optional_text(root, "AuxApplicInfo", :aux_applic_info)

      with {:ok, map} <- put_optional_recipients(map, root),
           {:ok, map} <- put_optional_uacapabilities(map, root),
           {:ok, map} <- put_optional_content(map, root) do
        {:ok, map}
      end
    end
  end

  defp decode_deliver_res(root) do
    with :ok <- ensure_only_allowed_children(root, ["MM7Version", "Status", "ServiceCode"]),
         {:ok, mm7_version} <- required_text(root, "MM7Version", "mm7_version"),
         {:ok, status_el} <- required_child(root, "Status", "status"),
         {:ok, status} <- parse_status(status_el) do
      map =
        %{
          kind: "mm7_deliver_res",
          mm7_version: mm7_version,
          status: status
        }
        |> put_optional_text(root, "ServiceCode", :service_code)

      {:ok, map}
    end
  end

  defp encode(:mm7_submit_req, map), do: encode_submit_req(map)
  defp encode(:mm7_submit_res, map), do: encode_submit_res(map)
  defp encode(:mm7_deliver_req, map), do: encode_deliver_req(map)
  defp encode(:mm7_deliver_res, map), do: encode_deliver_res(map)

  defp encode_submit_req(map) do
    with {:ok, mm7_version} <- required_string(map, :mm7_version, "mm7_version"),
         {:ok, sender_identification} <- optional_map(map, :sender_identification),
         {:ok, sender_xml} <- encode_sender_identification(sender_identification),
         {:ok, recipients_map} <- required_map(map, :recipients, "recipients"),
         {:ok, recipients_xml} <- encode_recipients(recipients_map, "recipients"),
         {:ok, optional_xml} <-
           build_submit_req_optional_xml(map) do
      xml =
        [
          "<SubmitReq xmlns=\"",
          @mm7_ns,
          "\">",
          element("MM7Version", mm7_version),
          sender_xml,
          recipients_xml,
          optional_xml,
          "</SubmitReq>"
        ]
        |> IO.iodata_to_binary()

      {:ok, xml}
    end
  end

  defp build_submit_req_optional_xml(map) do
    with {:ok, reply_charging} <- encode_optional_reply_charging(map),
         {:ok, delivery_condition} <- encode_optional_delivery_condition(map),
         {:ok, bool_delivery_report} <-
           optional_bool_element(map, :delivery_report, "DeliveryReport", "delivery_report"),
         {:ok, bool_read_reply} <-
           optional_bool_element(map, :read_reply, "ReadReply", "read_reply"),
         {:ok, bool_distribution} <-
           optional_bool_element(
             map,
             :distribution_indicator,
             "DistributionIndicator",
             "distribution_indicator"
           ),
         {:ok, bool_drm} <- optional_bool_element(map, :drm_content, "DRMContent", "drm_content"),
         {:ok, content_xml} <- encode_optional_content(map) do
      xml =
        [
          optional_text_element(map, :service_code, "ServiceCode"),
          optional_text_element(map, :linked_id, "LinkedID"),
          optional_text_element(map, :message_class, "MessageClass"),
          optional_text_element(map, :time_stamp, "TimeStamp"),
          reply_charging,
          optional_text_element(map, :earliest_delivery_time, "EarliestDeliveryTime"),
          optional_text_element(map, :expiry_date, "ExpiryDate"),
          bool_delivery_report,
          bool_read_reply,
          optional_text_element(map, :priority, "Priority"),
          optional_text_element(map, :subject, "Subject"),
          optional_text_element(map, :charged_party, "ChargedParty"),
          optional_text_element(map, :charged_party_id, "ChargedPartyID"),
          bool_distribution,
          delivery_condition,
          optional_text_element(map, :applic_id, "ApplicID"),
          optional_text_element(map, :reply_applic_id, "ReplyApplicID"),
          optional_text_element(map, :aux_applic_info, "AuxApplicInfo"),
          optional_text_element(map, :content_class, "ContentClass"),
          bool_drm,
          content_xml
        ]

      {:ok, IO.iodata_to_binary(xml)}
    end
  end

  defp encode_submit_res(map) do
    with {:ok, mm7_version} <- required_string(map, :mm7_version, "mm7_version"),
         {:ok, status_map} <- required_map(map, :status, "status"),
         {:ok, status} <- encode_status(status_map),
         {:ok, message_id} <- required_string(map, :message_id, "message_id") do
      {:ok,
       [
         "<SubmitRsp xmlns=\"",
         @mm7_ns,
         "\">",
         element("MM7Version", mm7_version),
         status,
         element("MessageID", message_id),
         "</SubmitRsp>"
       ]
       |> IO.iodata_to_binary()}
    end
  end

  defp encode_deliver_req(map) do
    with {:ok, mm7_version} <- required_string(map, :mm7_version, "mm7_version"),
         {:ok, sender_map} <- required_map(map, :sender, "sender"),
         {:ok, sender} <- encode_address_container("Sender", sender_map, "sender"),
         {:ok, recipients} <- encode_optional_recipients(map),
         {:ok, content} <- encode_optional_content(map),
         {:ok, uacapabilities} <- encode_optional_uacapabilities(map) do
      {:ok,
       [
         "<DeliverReq xmlns=\"",
         @mm7_ns,
         "\">",
         element("MM7Version", mm7_version),
         optional_text_element(map, :mms_relay_server_id, "MMSRelayServerID"),
         optional_text_element(map, :vasp_id, "VASPID"),
         optional_text_element(map, :vas_id, "VASID"),
         optional_text_element(map, :linked_id, "LinkedID"),
         sender,
         recipients,
         optional_text_element(map, :sender_spi, "SenderSPI"),
         optional_text_element(map, :recipient_spi, "RecipientSPI"),
         optional_text_element(map, :time_stamp, "TimeStamp"),
         optional_text_element(map, :reply_charging_id, "ReplyChargingID"),
         optional_text_element(map, :priority, "Priority"),
         optional_text_element(map, :subject, "Subject"),
         optional_text_element(map, :applic_id, "ApplicID"),
         optional_text_element(map, :reply_applic_id, "ReplyApplicID"),
         optional_text_element(map, :aux_applic_info, "AuxApplicInfo"),
         uacapabilities,
         content,
         "</DeliverReq>"
       ]
       |> IO.iodata_to_binary()}
    end
  end

  defp encode_deliver_res(map) do
    with {:ok, mm7_version} <- required_string(map, :mm7_version, "mm7_version"),
         {:ok, status_map} <- required_map(map, :status, "status"),
         {:ok, status} <- encode_status(status_map) do
      {:ok,
       [
         "<DeliverRsp xmlns=\"",
         @mm7_ns,
         "\">",
         element("MM7Version", mm7_version),
         status,
         optional_text_element(map, :service_code, "ServiceCode"),
         "</DeliverRsp>"
       ]
       |> IO.iodata_to_binary()}
    end
  end

  defp encode_status(status_map) do
    with {:ok, status_code} <-
           required_positive_integer(status_map, :status_code, "status.status_code"),
         {:ok, status_text} <- required_string(status_map, :status_text, "status.status_text") do
      details = optional_text_element(status_map, :details, "Details")

      {:ok,
       [
         "<Status>",
         element("StatusCode", Integer.to_string(status_code)),
         element("StatusText", status_text),
         details,
         "</Status>"
       ]
       |> IO.iodata_to_binary()}
    end
  end

  defp encode_sender_identification(nil), do: {:ok, "<SenderIdentification/>"}

  defp encode_sender_identification(sender_identification) when is_map(sender_identification) do
    with {:ok, sender_address_xml} <- encode_optional_sender_address(sender_identification) do
      xml =
        [
          "<SenderIdentification>",
          optional_text_element(sender_identification, :vasp_id, "VASPID"),
          optional_text_element(sender_identification, :vas_id, "VASID"),
          sender_address_xml,
          "</SenderIdentification>"
        ]
        |> IO.iodata_to_binary()

      {:ok, xml}
    end
  end

  defp encode_sender_identification(_),
    do: error(:invalid_structure, "sender_identification must be object")

  defp encode_optional_sender_address(sender_identification) do
    case fetch_any(sender_identification, :sender_address) do
      nil ->
        {:ok, ""}

      sender_address when is_map(sender_address) ->
        encode_address_container(
          "SenderAddress",
          sender_address,
          "sender_identification.sender_address"
        )

      _ ->
        error(:invalid_structure, "sender_identification.sender_address must be object")
    end
  end

  defp encode_recipients(recipients, path) when is_map(recipients) do
    with {:ok, to_xml, to_count} <- encode_recipient_group(recipients, :to, "To", path <> ".to"),
         {:ok, cc_xml, cc_count} <- encode_recipient_group(recipients, :cc, "Cc", path <> ".cc"),
         {:ok, bcc_xml, bcc_count} <-
           encode_recipient_group(recipients, :bcc, "Bcc", path <> ".bcc") do
      total = to_count + cc_count + bcc_count

      if total == 0 do
        error(:missing_mandatory_fields, "At least one recipient is required", %{fields: [path]})
      else
        {:ok, ["<Recipients>", to_xml, cc_xml, bcc_xml, "</Recipients>"] |> IO.iodata_to_binary()}
      end
    end
  end

  defp encode_recipients(_recipients, path),
    do: error(:invalid_structure, "#{path} must be object", %{field: path})

  defp encode_recipient_group(recipients, key, tag, path) do
    case fetch_any(recipients, key) do
      nil ->
        {:ok, "", 0}

      [] ->
        {:ok, "", 0}

      addresses when is_list(addresses) ->
        with {:ok, encoded} <-
               addresses
               |> Enum.with_index()
               |> Enum.reduce_while({:ok, []}, fn {address, idx}, {:ok, acc} ->
                 case encode_address(address, "#{path}[#{idx}]") do
                   {:ok, xml} -> {:cont, {:ok, [acc, xml]}}
                   {:error, reason} -> {:halt, {:error, reason}}
                 end
               end) do
          group_xml = ["<", tag, ">", encoded, "</", tag, ">"] |> IO.iodata_to_binary()
          {:ok, group_xml, length(addresses)}
        end

      _ ->
        error(:invalid_structure, "#{path} must be list of addresses", %{field: path})
    end
  end

  defp encode_address_container(tag, address, path) do
    with {:ok, encoded} <- encode_address(address, path) do
      {:ok, ["<", tag, ">", encoded, "</", tag, ">"] |> IO.iodata_to_binary()}
    end
  end

  defp encode_address(address, path) when is_map(address) do
    with {:ok, kind} <- required_string(address, :address_kind, path <> ".address_kind"),
         {:ok, value} <- required_string(address, :value, path <> ".value"),
         {:ok, tag} <- map_address_tag(kind),
         {:ok, attrs} <- encode_address_attrs(address, path) do
      {:ok, ["<", tag, attrs, ">", escape_xml(value), "</", tag, ">"] |> IO.iodata_to_binary()}
    end
  end

  defp encode_address(_address, path),
    do: error(:invalid_structure, "#{path} must be object", %{field: path})

  defp map_address_tag("number"), do: {:ok, "Number"}
  defp map_address_tag("rfc2822_address"), do: {:ok, "RFC2822Address"}
  defp map_address_tag("short_code"), do: {:ok, "ShortCode"}

  defp map_address_tag(other) do
    error(:invalid_structure, "Unknown address_kind", %{address_kind: other})
  end

  defp encode_address_attrs(address, path) do
    with {:ok, display_only} <-
           optional_bool_attr(address, :display_only, "displayOnly", path <> ".display_only"),
         {:ok, address_coding} <-
           optional_enum_attr(
             address,
             :address_coding,
             "addressCoding",
             ["encrypted", "obfuscated"],
             path <> ".address_coding"
           ) do
      {:ok, IO.iodata_to_binary([display_only, address_coding])}
    end
  end

  defp encode_optional_reply_charging(map) do
    case fetch_any(map, :reply_charging) do
      nil ->
        {:ok, ""}

      reply_charging when is_map(reply_charging) ->
        with {:ok, size_attr} <-
               optional_integer_attr(
                 reply_charging,
                 :reply_charging_size,
                 "replyChargingSize",
                 "reply_charging.reply_charging_size"
               ),
             {:ok, deadline_attr} <-
               optional_string_attr(
                 reply_charging,
                 :reply_deadline,
                 "replyDeadline",
                 "reply_charging.reply_deadline"
               ) do
          {:ok, ["<ReplyCharging", size_attr, deadline_attr, "/>"] |> IO.iodata_to_binary()}
        end

      _ ->
        error(:invalid_structure, "reply_charging must be object")
    end
  end

  defp encode_optional_delivery_condition(map) do
    case fetch_any(map, :delivery_condition) do
      nil ->
        {:ok, ""}

      delivery_condition when is_map(delivery_condition) ->
        case fetch_any(delivery_condition, :dc) do
          nil ->
            {:ok, "<DeliveryCondition/>"}

          dc_list when is_list(dc_list) ->
            with {:ok, parts} <-
                   dc_list
                   |> Enum.with_index()
                   |> Enum.reduce_while({:ok, []}, fn {dc, idx}, {:ok, acc} ->
                     case to_positive_integer(dc) do
                       {:ok, value} ->
                         {:cont, {:ok, [acc, element("DC", Integer.to_string(value))]}}

                       :error ->
                         {:halt,
                          error(
                            :invalid_structure,
                            "delivery_condition.dc[#{idx}] must be positive integer"
                          )}
                     end
                   end) do
              {:ok,
               ["<DeliveryCondition>", parts, "</DeliveryCondition>"] |> IO.iodata_to_binary()}
            end

          _ ->
            error(:invalid_structure, "delivery_condition.dc must be list")
        end

      _ ->
        error(:invalid_structure, "delivery_condition must be object")
    end
  end

  defp encode_optional_recipients(map) do
    case fetch_any(map, :recipients) do
      nil -> {:ok, ""}
      recipients -> encode_recipients(recipients, "recipients")
    end
  end

  defp encode_optional_content(map) do
    case fetch_any(map, :content) do
      nil -> {:ok, ""}
      content when is_map(content) -> encode_content(content)
      _ -> error(:invalid_structure, "content must be object")
    end
  end

  defp encode_content(content) do
    with {:ok, href} <- required_string(content, :href, "content.href"),
         {:ok, allow_adaptations} <-
           optional_bool_attr(
             content,
             :allow_adaptations,
             "allowAdaptations",
             "content.allow_adaptations"
           ) do
      {:ok,
       ["<Content href=\"", escape_xml(href), "\"", allow_adaptations, "/>"]
       |> IO.iodata_to_binary()}
    end
  end

  defp encode_optional_uacapabilities(map) do
    case fetch_any(map, :ua_capabilities) do
      nil ->
        {:ok, ""}

      ua_capabilities when is_map(ua_capabilities) ->
        with {:ok, ua_prof} <-
               optional_string_attr(
                 ua_capabilities,
                 :ua_prof,
                 "UAProf",
                 "ua_capabilities.ua_prof"
               ),
             {:ok, ts} <-
               optional_string_attr(
                 ua_capabilities,
                 :time_stamp,
                 "TimeStamp",
                 "ua_capabilities.time_stamp"
               ) do
          {:ok, ["<UACapabilities", ua_prof, ts, "/>"] |> IO.iodata_to_binary()}
        end

      _ ->
        error(:invalid_structure, "ua_capabilities must be object")
    end
  end

  defp optional_bool_element(map, key, xml_name, field_path) do
    case fetch_any(map, key) do
      nil ->
        {:ok, ""}

      value ->
        case to_bool(value) do
          {:ok, bool} ->
            {:ok, element(xml_name, if(bool, do: "true", else: "false"))}

          :error ->
            error(:invalid_structure, "#{field_path} must be boolean", %{field: field_path})
        end
    end
  end

  defp optional_text_element(map, key, xml_name) do
    case fetch_any(map, key) do
      nil -> ""
      "" -> ""
      value when is_binary(value) -> element(xml_name, value)
      value when is_integer(value) -> element(xml_name, Integer.to_string(value))
      value -> element(xml_name, to_string(value))
    end
  end

  defp optional_bool_attr(map, key, xml_name, field_path) do
    case fetch_any(map, key) do
      nil ->
        {:ok, ""}

      value ->
        case to_bool(value) do
          {:ok, bool} ->
            {:ok, [" ", xml_name, "=\"", if(bool, do: "true", else: "false"), "\""]}

          :error ->
            error(:invalid_structure, "#{field_path} must be boolean", %{field: field_path})
        end
    end
  end

  defp optional_integer_attr(map, key, xml_name, field_path) do
    case fetch_any(map, key) do
      nil ->
        {:ok, ""}

      value ->
        case to_positive_integer(value) do
          {:ok, integer} ->
            {:ok, [" ", xml_name, "=\"", Integer.to_string(integer), "\""]}

          :error ->
            error(:invalid_structure, "#{field_path} must be positive integer", %{
              field: field_path
            })
        end
    end
  end

  defp optional_string_attr(map, key, xml_name, field_path) do
    case fetch_any(map, key) do
      nil ->
        {:ok, ""}

      value when is_binary(value) and value != "" ->
        {:ok, [" ", xml_name, "=\"", escape_xml(value), "\""]}

      "" ->
        {:ok, ""}

      _ ->
        error(:invalid_structure, "#{field_path} must be string", %{field: field_path})
    end
  end

  defp optional_enum_attr(map, key, xml_name, allowed, field_path) do
    case fetch_any(map, key) do
      nil ->
        {:ok, ""}

      value when is_binary(value) ->
        if value in allowed do
          {:ok, [" ", xml_name, "=\"", escape_xml(value), "\""]}
        else
          error(:invalid_structure, "#{field_path} has unsupported value", %{
            field: field_path,
            value: value
          })
        end

      _ ->
        error(:invalid_structure, "#{field_path} must be string", %{field: field_path})
    end
  end

  defp required_string(map, key, path) do
    case fetch_any(map, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          error(:missing_mandatory_fields, "Missing mandatory fields", %{fields: [path]})
        else
          {:ok, value}
        end

      _ ->
        error(:missing_mandatory_fields, "Missing mandatory fields", %{fields: [path]})
    end
  end

  defp required_positive_integer(map, key, path) do
    case fetch_any(map, key) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> error(:invalid_structure, "#{path} must be positive integer", %{field: path})
        end

      _ ->
        if has_any_key?(map, key) do
          error(:invalid_structure, "#{path} must be positive integer", %{field: path})
        else
          error(:missing_mandatory_fields, "Missing mandatory fields", %{fields: [path]})
        end
    end
  end

  defp required_map(map, key, path) do
    case fetch_any(map, key) do
      value when is_map(value) -> {:ok, value}
      _ -> error(:missing_mandatory_fields, "Missing mandatory fields", %{fields: [path]})
    end
  end

  defp optional_map(map, key) do
    case fetch_any(map, key) do
      nil -> {:ok, nil}
      value when is_map(value) -> {:ok, value}
      _ -> error(:invalid_structure, "#{Atom.to_string(key)} must be object")
    end
  end

  defp required_child(root, child_name, field_path) do
    case child(root, child_name) do
      nil ->
        error(:invalid_structure, "Required XML element is missing", %{
          field: field_path,
          xml_element: child_name
        })

      child_element ->
        {:ok, child_element}
    end
  end

  defp required_text(root, child_name, field_path) do
    with {:ok, child_element} <- required_child(root, child_name, field_path),
         {:ok, text} <- element_text_required(child_element, field_path) do
      {:ok, text}
    end
  end

  defp element_text_required(element, field_path) do
    text = element_text(element)

    if text == "" do
      error(:invalid_structure, "XML element must contain text", %{field: field_path})
    else
      {:ok, text}
    end
  end

  defp ensure_only_allowed_children(root, allowed_names) do
    unknown =
      root
      |> children()
      |> Enum.map(&local_name/1)
      |> Enum.reject(&(&1 in allowed_names))
      |> Enum.uniq()

    case unknown do
      [] -> :ok
      names -> error(:invalid_structure, "Unexpected XML elements", %{unexpected_elements: names})
    end
  end

  defp put_optional_text(map, root, xml_name, field_name) do
    case child(root, xml_name) do
      nil ->
        map

      child_element ->
        case element_text_required(child_element, Atom.to_string(field_name)) do
          {:ok, value} ->
            Map.put(map, field_name, value)

          {:error, _reason} ->
            Map.put(map, field_name, {:invalid_text, Atom.to_string(field_name)})
        end
    end
  end

  defp put_optional_bool(map, root, xml_name, field_name) do
    case child(root, xml_name) do
      nil ->
        map

      child_element ->
        case element_text_required(child_element, Atom.to_string(field_name)) do
          {:ok, raw} ->
            case to_bool(raw) do
              {:ok, parsed} -> Map.put(map, field_name, parsed)
              :error -> Map.put(map, field_name, :invalid_boolean)
            end

          {:error, _reason} ->
            Map.put(map, field_name, {:invalid_text, Atom.to_string(field_name)})
        end
    end
  end

  defp put_optional_reply_charging(map, root) do
    case child(root, "ReplyCharging") do
      nil ->
        {:ok, map}

      reply_charging ->
        with {:ok, parsed} <- parse_reply_charging(reply_charging) do
          {:ok, Map.put(map, :reply_charging, parsed)}
        end
    end
  end

  defp put_optional_delivery_condition(map, root) do
    case child(root, "DeliveryCondition") do
      nil ->
        {:ok, map}

      delivery_condition ->
        with {:ok, parsed} <- parse_delivery_condition(delivery_condition) do
          {:ok, Map.put(map, :delivery_condition, parsed)}
        end
    end
  end

  defp put_optional_recipients(map, root) do
    case child(root, "Recipients") do
      nil ->
        {:ok, map}

      recipients ->
        with {:ok, parsed} <- parse_recipients(recipients) do
          {:ok, Map.put(map, :recipients, parsed)}
        end
    end
  end

  defp put_optional_uacapabilities(map, root) do
    case child(root, "UACapabilities") do
      nil ->
        {:ok, map}

      uacapabilities ->
        with {:ok, parsed} <- parse_uacapabilities(uacapabilities) do
          {:ok, Map.put(map, :ua_capabilities, parsed)}
        end
    end
  end

  defp put_optional_content(map, root) do
    case child(root, "Content") do
      nil ->
        {:ok, map}

      content ->
        with {:ok, parsed} <- parse_content(content) do
          {:ok, Map.put(map, :content, parsed)}
        end
    end
  end

  defp parse_sender_identification(sender_identification) do
    map = %{}

    map =
      map
      |> maybe_put_text_from_child(sender_identification, "VASPID", :vasp_id)
      |> maybe_put_text_from_child(sender_identification, "VASID", :vas_id)

    case child(sender_identification, "SenderAddress") do
      nil ->
        {:ok, map}

      sender_address ->
        with {:ok, parsed} <-
               parse_address_container(sender_address, "sender_identification.sender_address") do
          {:ok, Map.put(map, :sender_address, parsed)}
        end
    end
  end

  defp parse_recipients(recipients) do
    with {:ok, to} <- parse_recipient_nodes(recipients, "To", "recipients.to"),
         {:ok, cc} <- parse_recipient_nodes(recipients, "Cc", "recipients.cc"),
         {:ok, bcc} <- parse_recipient_nodes(recipients, "Bcc", "recipients.bcc") do
      if to == [] and cc == [] and bcc == [] do
        error(:invalid_structure, "Recipients must contain at least one recipient", %{
          field: "recipients"
        })
      else
        {:ok, %{to: to, cc: cc, bcc: bcc}}
      end
    end
  end

  defp parse_recipient_nodes(recipients, xml_name, path) do
    recipients
    |> children(xml_name)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {node, idx}, {:ok, acc} ->
      case parse_multi_address_container(node, "#{path}[#{idx}]") do
        {:ok, addresses} -> {:cont, {:ok, Enum.reverse(addresses) ++ acc}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end)
  end

  defp parse_multi_address_container(container, path) do
    container
    |> children()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {address, idx}, {:ok, acc} ->
      case parse_address(address, "#{path}[#{idx}]") do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end)
  end

  defp parse_address_container(container, path) do
    case children(container) do
      [single] -> parse_address(single, path)
      [] -> error(:invalid_structure, "Address container is empty", %{field: path})
      _ -> error(:invalid_structure, "Address container must contain one address", %{field: path})
    end
  end

  defp parse_address(address, path) do
    kind = local_name(address)

    with {:ok, address_kind} <- decode_address_kind(kind),
         {:ok, value} <- element_text_required(address, path <> ".value") do
      map =
        %{
          address_kind: address_kind,
          value: value
        }
        |> maybe_put_address_bool_attr(address, :displayOnly, :display_only, path)
        |> maybe_put_address_coding_attr(address, :addressCoding, :address_coding, path)

      {:ok, map}
    end
  end

  defp decode_address_kind("Number"), do: {:ok, "number"}
  defp decode_address_kind("RFC2822Address"), do: {:ok, "rfc2822_address"}
  defp decode_address_kind("ShortCode"), do: {:ok, "short_code"}

  defp decode_address_kind(other) do
    error(:invalid_structure, "Unsupported address element", %{address_element: other})
  end

  defp parse_status(status_element) do
    with :ok <-
           ensure_only_allowed_children(status_element, ["StatusCode", "StatusText", "Details"]),
         {:ok, status_code_raw} <-
           required_text(status_element, "StatusCode", "status.status_code"),
         {:ok, status_code} <- parse_positive_integer(status_code_raw, "status.status_code"),
         {:ok, status_text} <- required_text(status_element, "StatusText", "status.status_text") do
      status = %{
        status_code: status_code,
        status_text: status_text
      }

      status =
        case child(status_element, "Details") do
          nil -> status
          details -> Map.put(status, :details, details_text(details))
        end

      {:ok, status}
    end
  end

  defp parse_reply_charging(reply_charging) do
    attrs = attributes(reply_charging)

    with {:ok, size} <-
           maybe_parse_positive_integer_attr(
             attrs,
             :replyChargingSize,
             "reply_charging.reply_charging_size"
           ),
         {:ok, deadline} <- maybe_attr(attrs, :replyDeadline) do
      parsed = %{}
      parsed = if is_integer(size), do: Map.put(parsed, :reply_charging_size, size), else: parsed

      parsed =
        if is_binary(deadline) and deadline != "",
          do: Map.put(parsed, :reply_deadline, deadline),
          else: parsed

      {:ok, parsed}
    end
  end

  defp parse_delivery_condition(delivery_condition) do
    with :ok <- ensure_only_allowed_children(delivery_condition, ["DC"]),
         {:ok, dc_values} <-
           delivery_condition
           |> children("DC")
           |> Enum.with_index()
           |> Enum.reduce_while({:ok, []}, fn {dc, idx}, {:ok, acc} ->
             case element_text_required(dc, "delivery_condition.dc[#{idx}]") do
               {:ok, raw} ->
                 case parse_positive_integer(raw, "delivery_condition.dc[#{idx}]") do
                   {:ok, value} -> {:cont, {:ok, [value | acc]}}
                   {:error, reason} -> {:halt, {:error, reason}}
                 end

               {:error, reason} ->
                 {:halt, {:error, reason}}
             end
           end) do
      {:ok, %{dc: Enum.reverse(dc_values)}}
    end
  end

  defp parse_content(content) do
    attrs = attributes(content)

    with {:ok, href} <- required_attr(attrs, :href, "content.href"),
         {:ok, allow_adaptations} <-
           maybe_parse_bool_attr(attrs, :allowAdaptations, "content.allow_adaptations") do
      map = %{href: href}

      map =
        if is_boolean(allow_adaptations),
          do: Map.put(map, :allow_adaptations, allow_adaptations),
          else: map

      {:ok, map}
    end
  end

  defp parse_uacapabilities(uacapabilities) do
    attrs = attributes(uacapabilities)

    with {:ok, ua_prof} <- maybe_attr(attrs, :UAProf),
         {:ok, ts} <- maybe_attr(attrs, :TimeStamp) do
      map = %{}
      map = if present?(ua_prof), do: Map.put(map, :ua_prof, ua_prof), else: map
      map = if present?(ts), do: Map.put(map, :time_stamp, ts), else: map
      {:ok, map}
    end
  end

  defp maybe_put_text_from_child(map, root, child_name, key) do
    case child(root, child_name) do
      nil ->
        map

      child_element ->
        case element_text_required(child_element, Atom.to_string(key)) do
          {:ok, value} -> Map.put(map, key, value)
          {:error, _reason} -> Map.put(map, key, {:invalid_text, Atom.to_string(key)})
        end
    end
  end

  defp maybe_put_address_coding_attr(map, element, attr_name, key, path) do
    case attr(attributes(element), attr_name) do
      nil ->
        map

      "encrypted" = value ->
        Map.put(map, key, value)

      "obfuscated" = value ->
        Map.put(map, key, value)

      _other ->
        Map.put(map, key, {:invalid_enum, path <> "." <> Atom.to_string(key)})
    end
  end

  defp maybe_put_address_bool_attr(map, element, attr_name, key, path) do
    case attr(attributes(element), attr_name) do
      nil ->
        map

      value ->
        case to_bool(value) do
          {:ok, bool} -> Map.put(map, key, bool)
          :error -> Map.put(map, key, {:invalid_boolean, path})
        end
    end
  end

  defp maybe_attr(attrs, name), do: {:ok, attr(attrs, name)}

  defp maybe_parse_bool_attr(attrs, name, path) do
    case attr(attrs, name) do
      nil ->
        {:ok, nil}

      value ->
        case to_bool(value) do
          {:ok, parsed} -> {:ok, parsed}
          :error -> error(:invalid_structure, "#{path} must be boolean", %{field: path})
        end
    end
  end

  defp maybe_parse_positive_integer_attr(attrs, name, path) do
    case attr(attrs, name) do
      nil -> {:ok, nil}
      value -> parse_positive_integer(value, path)
    end
  end

  defp required_attr(attrs, name, path) do
    case attr(attrs, name) do
      nil -> error(:invalid_structure, "Missing required XML attribute", %{field: path})
      value -> {:ok, value}
    end
  end

  defp parse_positive_integer(value, field_path) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 ->
        {:ok, parsed}

      _ ->
        error(:invalid_structure, "#{field_path} must be positive integer", %{field: field_path})
    end
  end

  defp to_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp to_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp to_positive_integer(_), do: :error

  defp to_bool(value) when is_boolean(value), do: {:ok, value}

  defp to_bool(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      "1" -> {:ok, true}
      "0" -> {:ok, false}
      _ -> :error
    end
  end

  defp to_bool(_), do: :error

  defp children(element),
    do: Enum.filter(xml_element_content(element), &(is_tuple(&1) and elem(&1, 0) == :xmlElement))

  defp children(element, xml_name),
    do: Enum.filter(children(element), &(local_name(&1) == xml_name))

  defp child(element, xml_name), do: Enum.find(children(element), &(local_name(&1) == xml_name))

  defp attributes(element), do: xml_element_attributes(element)

  defp attr(attributes, name_atom) do
    Enum.find_value(attributes, fn attribute ->
      if attribute_name(attribute) == Atom.to_string(name_atom),
        do: xml_attribute_value(attribute) |> List.to_string(),
        else: nil
    end)
  end

  defp attribute_name(attribute), do: local_name(xml_attribute_name(attribute))

  defp local_name(element_or_name)

  defp local_name(element) when is_tuple(element) and elem(element, 0) == :xmlElement do
    xml_element_name(element) |> local_name()
  end

  defp local_name(name) when is_atom(name), do: name |> Atom.to_string() |> local_name()

  defp local_name(name) when is_binary(name) do
    case String.split(name, ":", parts: 2) do
      [single] -> single
      [_prefix, local] -> local
    end
  end

  defp element_namespace(element) do
    namespace = xml_element_namespace(element)
    nsinfo = xml_element_nsinfo(element)

    case nsinfo do
      [] ->
        namespace |> xml_namespace_default() |> uri_to_string()

      {prefix, _local} ->
        prefix
        |> to_string()
        |> then(fn normalized_prefix ->
          namespace
          |> xml_namespace_nodes()
          |> Enum.find_value("", fn {node_prefix, uri} ->
            if to_string(node_prefix) == normalized_prefix, do: uri_to_string(uri), else: nil
          end)
        end)
    end
  end

  defp uri_to_string(nil), do: ""
  defp uri_to_string([]), do: ""
  defp uri_to_string(uri) when is_atom(uri), do: Atom.to_string(uri)
  defp uri_to_string(uri) when is_list(uri), do: List.to_string(uri)
  defp uri_to_string(uri) when is_binary(uri), do: uri

  defp element_text(element) do
    element
    |> xml_element_content()
    |> Enum.reduce([], fn
      node, acc when is_tuple(node) and elem(node, 0) == :xmlText ->
        [xml_text_value(node) | acc]

      _other, acc ->
        acc
    end)
    |> Enum.reverse()
    |> List.flatten()
    |> List.to_string()
    |> String.trim()
  end

  defp details_text(element) do
    text = collect_text(element) |> String.trim()
    if text == "", do: nil, else: text
  end

  defp collect_text(element) do
    element
    |> xml_element_content()
    |> Enum.map(fn
      node when is_tuple(node) and elem(node, 0) == :xmlText ->
        xml_text_value(node) |> List.to_string()

      node when is_tuple(node) and elem(node, 0) == :xmlElement ->
        collect_text(node)

      _ ->
        ""
    end)
    |> Enum.join("")
  end

  defp xml_element_name(element), do: elem(element, 1)
  defp xml_element_nsinfo(element), do: elem(element, 3)
  defp xml_element_namespace(element), do: elem(element, 4)
  defp xml_element_attributes(element), do: elem(element, 7)
  defp xml_element_content(element), do: elem(element, 8)
  defp xml_namespace_default(namespace), do: elem(namespace, 1)
  defp xml_namespace_nodes(namespace), do: elem(namespace, 2)
  defp xml_attribute_name(attribute), do: elem(attribute, 1)
  defp xml_attribute_value(attribute), do: elem(attribute, 8)
  defp xml_text_value(text), do: elem(text, 4)

  defp element(name, value), do: ["<", name, ">", escape_xml(value), "</", name, ">"]

  # Мы экранируем все текстовые значения централизованно, чтобы исключить поломку XML и XSS-подобные эффекты при дальнейшей обработке.
  defp escape_xml(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(value) when is_integer(value), do: Integer.to_string(value)
  defp escape_xml(value), do: value |> to_string() |> escape_xml()

  defp format_path(path), do: Enum.map_join(path, ".", &Atom.to_string/1)

  defp get_path(map, [single]), do: fetch_any(map, single)

  defp get_path(map, [head | tail]) do
    case fetch_any(map, head) do
      nested when is_map(nested) -> get_path(nested, tail)
      _ -> nil
    end
  end

  defp fetch_any(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      true ->
        nil
    end
  end

  defp has_any_key?(map, key) when is_map(map) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(value), do: value != :invalid_boolean

  defp ensure_no_invalid_values(value) do
    case first_invalid_marker(value) do
      nil ->
        :ok

      :invalid_boolean ->
        error(:invalid_structure, "Boolean field has invalid value")

      {:invalid_boolean, path} ->
        error(:invalid_structure, "Boolean field has invalid value", %{field: path})

      {:invalid_text, path} ->
        error(:invalid_structure, "Field must contain text", %{field: path})

      {:invalid_enum, path} ->
        error(:invalid_structure, "Field has unsupported enum value", %{field: path})
    end
  end

  defp first_invalid_marker(value) when is_map(value) do
    Enum.find_value(value, fn {_k, v} -> first_invalid_marker(v) end)
  end

  defp first_invalid_marker(value) when is_list(value) do
    Enum.find_value(value, &first_invalid_marker/1)
  end

  defp first_invalid_marker(value) when value in [:invalid_boolean], do: :invalid_boolean
  defp first_invalid_marker({:invalid_boolean, _path} = marker), do: marker
  defp first_invalid_marker({:invalid_text, _path} = marker), do: marker
  defp first_invalid_marker({:invalid_enum, _path} = marker), do: marker
  defp first_invalid_marker(_), do: nil

  defp mime_payload?(payload) do
    down = String.downcase(payload)
    String.contains?(down, "multipart/") or String.contains?(down, "content-id:")
  end

  defp unsupported_feature(feature) do
    error(
      :unsupported_stage_feature,
      "Feature is outside stage-1 scope",
      %{feature: feature}
    )
  end

  defp error(code, message, details \\ %{}) do
    {:error, %{code: code, message: message, details: details}}
  end
end
