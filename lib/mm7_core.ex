defmodule MM7Core do
  @moduledoc """
  Минимальный stage-1 конвертер MM7 body-level сообщений.
  """

  alias MM7Core.Messages.Address
  alias MM7Core.Messages.DeliverReq
  alias MM7Core.Messages.DeliverRsp
  alias MM7Core.Messages.Recipients
  alias MM7Core.Messages.SenderIdentification
  alias MM7Core.Messages.Status
  alias MM7Core.Messages.SubmitReq
  alias MM7Core.Messages.SubmitRsp

  @canonical_ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  @root_to_module %{
    "SubmitReq" => SubmitReq,
    "SubmitRsp" => SubmitRsp,
    "DeliverReq" => DeliverReq,
    "DeliverRsp" => DeliverRsp
  }

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

  @submit_rsp_children ["MM7Version", "Status", "MessageID"]

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

  @deliver_rsp_children ["MM7Version", "Status", "ServiceCode"]

  @submit_req_optional_fields [
    {:text, :service_code, "ServiceCode"},
    {:text, :linked_id, "LinkedID"},
    {:text, :message_class, "MessageClass"},
    {:text, :time_stamp, "TimeStamp"},
    {:bool, :delivery_report, "DeliveryReport"},
    {:bool, :read_reply, "ReadReply"},
    {:text, :priority, "Priority"},
    {:text, :subject, "Subject"},
    {:text, :applic_id, "ApplicID"},
    {:text, :reply_applic_id, "ReplyApplicID"},
    {:text, :aux_applic_info, "AuxApplicInfo"}
  ]

  @submit_req_text_fields for {:text, field, _element} <- @submit_req_optional_fields, do: field
  @submit_req_bool_fields for {:bool, field, _element} <- @submit_req_optional_fields, do: field

  @deliver_req_optional_fields [
    {:text, :mms_relay_server_id, "MMSRelayServerID"},
    {:text, :vasp_id, "VASPID"},
    {:text, :vas_id, "VASID"},
    {:text, :linked_id, "LinkedID"},
    {:text, :time_stamp, "TimeStamp"},
    {:text, :priority, "Priority"},
    {:text, :subject, "Subject"},
    {:text, :applic_id, "ApplicID"},
    {:text, :reply_applic_id, "ReplyApplicID"},
    {:text, :aux_applic_info, "AuxApplicInfo"}
  ]

  @deliver_req_text_fields for {:text, field, _element} <- @deliver_req_optional_fields, do: field

  @sender_identification_optional_fields [
    {:text, :vasp_id, "VASPID"},
    {:text, :vas_id, "VASID"}
  ]

  @address_tag_to_kind %{
    "RFC2822Address" => :rfc2822_address,
    "Number" => :number,
    "ShortCode" => :short_code
  }

  @address_kinds Map.values(@address_tag_to_kind)
  @address_kind_to_tag Map.new(@address_tag_to_kind, fn {tag, kind} -> {kind, tag} end)

  @default_status_text %{
    1000 => "Success",
    1100 => "Partial success",
    2000 => "Client error",
    3000 => "Server error",
    4000 => "Service error"
  }

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
        xml_to_struct(trimmed)

      true ->
        error(:unsupported_input_format, "unsupported binary input", %{format: "non_xml_binary"})
    end
  end

  def convert(%_{} = input, _opts), do: struct_to_xml(input)

  def convert(_input, _opts) do
    error(:unsupported_input_format, "unsupported input type")
  end

  defp xml_to_struct(xml) do
    with :ok <- reject_dtd(xml),
         {:ok, root} <- parse_xml(xml),
         :ok <- reject_stage_features(root),
         {:ok, module} <- detect_module(root.name),
         :ok <- validate_tree_namespaces(root),
         {:ok, struct} <- decode_module(module, root),
         :ok <- validate_mandatory_struct(struct) do
      {:ok, struct}
    end
  end

  defp struct_to_xml(%SubmitReq{} = struct) do
    with :ok <- validate_submit_req(struct) do
      {:ok,
       IO.iodata_to_binary([
         open_root("SubmitReq"),
         tag("MM7Version", struct.mm7_version),
         encode_sender_identification(struct.sender_identification),
         encode_recipients(struct.recipients),
         maybe_tag("ServiceCode", struct.service_code),
         maybe_tag("LinkedID", struct.linked_id),
         maybe_tag("MessageClass", struct.message_class),
         maybe_tag("TimeStamp", struct.time_stamp),
         maybe_tag("DeliveryReport", bool_to_text(struct.delivery_report)),
         maybe_tag("ReadReply", bool_to_text(struct.read_reply)),
         maybe_tag("Priority", struct.priority),
         maybe_tag("Subject", struct.subject),
         maybe_tag("ApplicID", struct.applic_id),
         maybe_tag("ReplyApplicID", struct.reply_applic_id),
         maybe_tag("AuxApplicInfo", struct.aux_applic_info),
         close_root("SubmitReq")
       ])}
    end
  end

  defp struct_to_xml(%SubmitRsp{} = struct) do
    with :ok <- validate_submit_rsp(struct),
         {:ok, status_xml} <- encode_status(struct.status) do
      {:ok,
       IO.iodata_to_binary([
         open_root("SubmitRsp"),
         tag("MM7Version", struct.mm7_version),
         status_xml,
         maybe_tag("MessageID", struct.message_id),
         close_root("SubmitRsp")
       ])}
    end
  end

  defp struct_to_xml(%DeliverReq{} = struct) do
    with :ok <- validate_deliver_req(struct) do
      {:ok,
       IO.iodata_to_binary([
         open_root("DeliverReq"),
         tag("MM7Version", struct.mm7_version),
         maybe_tag("MMSRelayServerID", struct.mms_relay_server_id),
         maybe_tag("VASPID", struct.vasp_id),
         maybe_tag("VASID", struct.vas_id),
         maybe_tag("LinkedID", struct.linked_id),
         wrap("Sender", encode_address(struct.sender)),
         encode_optional_recipients(struct.recipients),
         maybe_tag("TimeStamp", struct.time_stamp),
         maybe_tag("Priority", struct.priority),
         maybe_tag("Subject", struct.subject),
         maybe_tag("ApplicID", struct.applic_id),
         maybe_tag("ReplyApplicID", struct.reply_applic_id),
         maybe_tag("AuxApplicInfo", struct.aux_applic_info),
         close_root("DeliverReq")
       ])}
    end
  end

  defp struct_to_xml(%DeliverRsp{} = struct) do
    with :ok <- validate_deliver_rsp(struct),
         {:ok, status_xml} <- encode_status(struct.status) do
      {:ok,
       IO.iodata_to_binary([
         open_root("DeliverRsp"),
         tag("MM7Version", struct.mm7_version),
         status_xml,
         maybe_tag("ServiceCode", struct.service_code),
         close_root("DeliverRsp")
       ])}
    end
  end

  defp struct_to_xml(%module{} = _struct) do
    error(:unknown_struct_kind, "unknown struct kind", %{module: inspect(module)})
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
    Map.new(attrs, fn {uri, _, name, value} ->
      {IO.chardata_to_string(name),
       %{ns: IO.chardata_to_string(uri), value: IO.chardata_to_string(value)}}
    end)
  end

  defp detect_module(root_name) do
    case @root_to_module[root_name] do
      nil -> error(:unknown_xml_root, "unknown xml root", %{root: root_name})
      module -> {:ok, module}
    end
  end

  defp validate_tree_namespaces(%{ns: @canonical_ns} = node) do
    Enum.reduce_while(element_children(node), :ok, fn child, :ok ->
      case validate_tree_namespaces(child) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_tree_namespaces(%{name: name, ns: namespace}) do
    error(:invalid_structure, "namespace mismatch", %{
      element: name,
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

  defp reject_dtd(xml) do
    if Regex.match?(~r/<!\s*(DOCTYPE|ENTITY)/i, xml) do
      error(:invalid_xml, "doctype/entity is not allowed")
    else
      :ok
    end
  end

  defp decode_module(SubmitReq, root), do: decode_submit_req(root)
  defp decode_module(SubmitRsp, root), do: decode_submit_rsp(root)
  defp decode_module(DeliverReq, root), do: decode_deliver_req(root)
  defp decode_module(DeliverRsp, root), do: decode_deliver_rsp(root)

  defp reject_stage_features(%{name: "Envelope"}) do
    error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "soap_envelope"})
  end

  defp reject_stage_features(node) do
    cond do
      tree_contains_element?(node, "Header") ->
        error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "soap_header"})

      tree_contains_element?(node, "Content") ->
        error(:unsupported_stage_feature, "unsupported stage feature", %{feature: "mime"})

      true ->
        :ok
    end
  end

  defp tree_contains_element?(%{name: name}, name), do: true

  defp tree_contains_element?(node, name) do
    Enum.any?(element_children(node), &tree_contains_element?(&1, name))
  end

  defp decode_submit_req(root) do
    with :ok <- ensure_children(root, @submit_req_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, sender_identification} <- required_sender_identification(root),
         {:ok, recipients} <- required_recipients(root),
         {:ok, optional_fields} <- collect_optional_fields(root, @submit_req_optional_fields) do
      {:ok,
       struct(
         SubmitReq,
         optional_fields
         |> Map.put(:mm7_version, mm7_version)
         |> Map.put(:sender_identification, sender_identification)
         |> Map.put(:recipients, recipients)
       )}
    end
  end

  defp decode_submit_rsp(root) do
    with :ok <- ensure_children(root, @submit_rsp_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, status} <- decode_status(root),
         {:ok, message_id} <- optional_text(root, "MessageID") do
      {:ok, %SubmitRsp{mm7_version: mm7_version, status: status, message_id: message_id}}
    end
  end

  defp decode_deliver_req(root) do
    with :ok <- ensure_children(root, @deliver_req_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, sender} <- required_address(root, "Sender"),
         {:ok, recipients} <- optional_recipients(root),
         {:ok, optional_fields} <- collect_optional_fields(root, @deliver_req_optional_fields) do
      {:ok,
       struct(
         DeliverReq,
         optional_fields
         |> Map.put(:mm7_version, mm7_version)
         |> Map.put(:sender, sender)
         |> Map.put(:recipients, recipients)
       )}
    end
  end

  defp decode_deliver_rsp(root) do
    with :ok <- ensure_children(root, @deliver_rsp_children),
         {:ok, mm7_version} <- required_text(root, "MM7Version"),
         {:ok, status} <- decode_status(root),
         {:ok, service_code} <- optional_text(root, "ServiceCode") do
      {:ok, %DeliverRsp{mm7_version: mm7_version, status: status, service_code: service_code}}
    end
  end

  defp ensure_children(node, allowed, opts \\ []) do
    ordered? = Keyword.get(opts, :ordered, true)
    names = Enum.map(element_children(node), & &1.name)
    unknown = Enum.reject(names, &(&1 in allowed))

    cond do
      String.trim(node.text) != "" ->
        error(:invalid_structure, "unexpected text content", %{element: node.name})

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
        nil -> {:ok, nil}
        child -> simple_text(child)
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

  defp element_children(node), do: node.children

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
         {:ok, parsed} <- parse_optional_xml_bool(value, Atom.to_string(key)) do
      case parsed do
        nil -> {:ok, nil}
        boolean -> {:ok, {key, boolean}}
      end
    end
  end

  defp required_sender_identification(root) do
    with {:ok, node} <- single_child(root, "SenderIdentification") do
      case node do
        nil -> error(:invalid_structure, "missing SenderIdentification")
        node -> decode_sender_identification_node(node)
      end
    end
  end

  defp decode_sender_identification_node(node) do
    with :ok <- ensure_children(node, ["VASPID", "VASID", "SenderAddress"]),
         {:ok, sender_address} <- optional_address(node, "SenderAddress"),
         {:ok, sender_fields} <-
           collect_optional_fields(node, @sender_identification_optional_fields) do
      attrs =
        sender_fields
        |> Map.put(:sender_address, sender_address)
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      if map_size(attrs) == 0 do
        {:ok, nil}
      else
        {:ok, struct(SenderIdentification, attrs)}
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
      case Enum.reduce_while(element_children(node), {:ok, %{to: [], cc: [], bcc: []}}, fn child,
                                                                                           {:ok,
                                                                                            acc} ->
             key = recipient_group_key(child.name)

             case decode_address_list(child) do
               {:ok, addresses} ->
                 updated = Map.update!(acc, key, &(&1 ++ addresses))
                 {:cont, {:ok, updated}}

               {:error, _} = err ->
                 {:halt, err}
             end
           end) do
        {:ok, groups} ->
          recipients = %Recipients{to: groups.to, cc: groups.cc, bcc: groups.bcc}

          if recipients_empty?(recipients) do
            error(:invalid_structure, "Recipients must contain at least one address")
          else
            {:ok, recipients}
          end

        {:error, _} = err ->
          err
      end
    end
  end

  defp recipient_group_key("To"), do: :to
  defp recipient_group_key("Cc"), do: :cc
  defp recipient_group_key("Bcc"), do: :bcc

  defp decode_address_list(node) do
    if String.trim(node.text) != "" do
      error(:invalid_structure, "unexpected text content", %{element: node.name})
    else
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
    if String.trim(node.text) != "" do
      error(:invalid_structure, "unexpected text content", %{element: element_name})
    else
      case element_children(node) do
        [address] -> decode_address_node(address)
        _ -> error(:invalid_structure, "invalid address structure", %{element: element_name})
      end
    end
  end

  defp decode_address_node(node) do
    kind = @address_tag_to_kind[node.name]

    if is_nil(kind) do
      error(:invalid_structure, "invalid address structure", %{element: node.name})
    else
      with {:ok, display_only} <-
             optional_attr(node, "displayOnly"),
           {:ok, display_only} <-
             parse_optional_xml_bool(display_only, "displayOnly"),
           {:ok, address_coding} <- optional_attr(node, "addressCoding"),
           :ok <- validate_address_coding(address_coding, :invalid_structure),
           {:ok, id} <- optional_attr(node, "id"),
           {:ok, value} <- simple_text(node) do
        {:ok,
         %Address{
           kind: kind,
           value: value,
           display_only: display_only,
           address_coding: address_coding,
           id: id
         }}
      end
    end
  end

  defp decode_status(root) do
    with {:ok, node} <- single_child(root, "Status") do
      case node do
        nil ->
          error(:invalid_structure, "missing Status")

        node ->
          with :ok <-
                 ensure_children(node, ["StatusCode", "StatusText", "Details"], ordered: false),
               {:ok, status_code_text} <- required_text(node, "StatusCode"),
               {:ok, status_code} <-
                 parse_positive_integer(status_code_text, "status.status_code"),
               {:ok, status_text} <- optional_text(node, "StatusText"),
               {:ok, details} <- optional_text(node, "Details") do
            {:ok, %Status{status_code: status_code, status_text: status_text, details: details}}
          end
      end
    end
  end

  defp validate_submit_req(%SubmitReq{} = struct) do
    with :ok <- validate_exact_struct_keys(struct),
         :ok <- validate_string_fields(struct, @submit_req_text_fields),
         :ok <- validate_boolean_fields(struct, @submit_req_bool_fields),
         :ok <- validate_sender_identification(struct.sender_identification),
         :ok <- validate_recipients(struct.recipients),
         :ok <- validate_mandatory_struct(struct) do
      :ok
    end
  end

  defp validate_submit_rsp(%SubmitRsp{} = struct) do
    with :ok <- validate_exact_struct_keys(struct),
         :ok <- validate_string_fields(struct, [:message_id]),
         :ok <- validate_status(struct.status),
         :ok <- validate_mandatory_struct(struct) do
      :ok
    end
  end

  defp validate_deliver_req(%DeliverReq{} = struct) do
    with :ok <- validate_exact_struct_keys(struct),
         :ok <- validate_string_fields(struct, @deliver_req_text_fields),
         :ok <- validate_address(struct.sender),
         :ok <- validate_recipients(struct.recipients),
         :ok <- validate_mandatory_struct(struct) do
      :ok
    end
  end

  defp validate_deliver_rsp(%DeliverRsp{} = struct) do
    with :ok <- validate_exact_struct_keys(struct),
         :ok <- validate_string_fields(struct, [:service_code]),
         :ok <- validate_status(struct.status),
         :ok <- validate_mandatory_struct(struct) do
      :ok
    end
  end

  defp validate_mandatory_struct(%SubmitReq{} = struct) do
    missing =
      []
      |> maybe_missing_string(struct.mm7_version, "mm7_version")
      |> maybe_missing_recipients(struct.recipients)

    missing_or_ok(SubmitReq, missing)
  end

  defp validate_mandatory_struct(%SubmitRsp{} = struct) do
    missing =
      []
      |> maybe_missing_string(struct.mm7_version, "mm7_version")
      |> maybe_missing_status_code(struct.status)

    missing_or_ok(SubmitRsp, missing)
  end

  defp validate_mandatory_struct(%DeliverReq{} = struct) do
    missing =
      []
      |> maybe_missing_string(struct.mm7_version, "mm7_version")
      |> maybe_missing_address(struct.sender, "sender")

    missing_or_ok(DeliverReq, missing)
  end

  defp validate_mandatory_struct(%DeliverRsp{} = struct) do
    missing =
      []
      |> maybe_missing_string(struct.mm7_version, "mm7_version")
      |> maybe_missing_status_code(struct.status)

    missing_or_ok(DeliverRsp, missing)
  end

  defp validate_mandatory_struct(%module{} = _struct) do
    error(:unknown_struct_kind, "unknown struct kind", %{module: inspect(module)})
  end

  defp validate_mandatory_struct(_value) do
    error(:invalid_struct, "invalid struct")
  end

  defp validate_sender_identification(nil), do: :ok

  defp validate_sender_identification(%SenderIdentification{} = sender_identification) do
    with :ok <- validate_string_fields(sender_identification, [:vasp_id, :vas_id]),
         :ok <- validate_address(sender_identification.sender_address) do
      :ok
    end
  end

  defp validate_sender_identification(_value) do
    error(:invalid_struct, "sender_identification must be struct")
  end

  defp validate_status(nil), do: :ok

  defp validate_status(%Status{} = status) do
    with :ok <- validate_optional_positive_integer(status.status_code, "status.status_code"),
         :ok <- validate_string_fields(status, [:status_text, :details]) do
      :ok
    end
  end

  defp validate_status(_value) do
    error(:invalid_struct, "status must be struct")
  end

  defp validate_recipients(nil), do: :ok

  defp validate_recipients(%Recipients{} = recipients) do
    with :ok <- validate_address_list(recipients.to, "recipients.to"),
         :ok <- validate_address_list(recipients.cc, "recipients.cc"),
         :ok <- validate_address_list(recipients.bcc, "recipients.bcc"),
         :ok <- validate_recipients_presence(recipients) do
      :ok
    end
  end

  defp validate_recipients(_value) do
    error(:invalid_struct, "recipients must be struct")
  end

  defp validate_address_list(nil, field) do
    error(:invalid_struct, "address list must be list", %{field: field})
  end

  defp validate_address_list(list, _field) when is_list(list) do
    Enum.reduce_while(list, :ok, fn address, :ok ->
      case validate_address(address) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_address_list(_value, field) do
    error(:invalid_struct, "address list must be list", %{field: field})
  end

  defp validate_address(nil), do: :ok

  defp validate_address(%Address{} = address) do
    with :ok <- validate_address_kind(address.kind),
         :ok <- validate_required_string(address.value, "address.value", :invalid_struct),
         :ok <- validate_optional_boolean(address.display_only, "address.display_only"),
         :ok <- validate_string_value(address.id, "address.id", :invalid_struct),
         :ok <- validate_address_coding(address.address_coding, :invalid_struct) do
      :ok
    end
  end

  defp validate_address(_value) do
    error(:invalid_struct, "address must be struct")
  end

  defp validate_address_kind(kind) when kind in @address_kinds, do: :ok

  defp validate_address_kind(_kind) do
    error(:invalid_struct, "unknown address kind")
  end

  defp validate_address_coding(nil, _code), do: :ok
  defp validate_address_coding("encrypted", _code), do: :ok
  defp validate_address_coding("obfuscated", _code), do: :ok

  defp validate_address_coding(_value, code) do
    error(code, "field must be encrypted or obfuscated", %{field: "address_coding"})
  end

  defp missing_or_ok(_module, []), do: :ok

  defp missing_or_ok(module, missing) do
    error(:missing_mandatory_fields, "missing mandatory fields", %{
      struct: inspect(module),
      fields: missing
    })
  end

  defp maybe_missing_string(list, value, _field) when is_binary(value) and value != "", do: list
  defp maybe_missing_string(list, _value, field), do: list ++ [field]

  defp maybe_missing_address(list, %Address{kind: kind, value: value}, _field)
       when kind in @address_kinds and is_binary(value) and value != "" do
    list
  end

  defp maybe_missing_address(list, _value, field), do: list ++ [field]

  defp maybe_missing_status_code(list, %Status{status_code: value})
       when is_integer(value) and value > 0,
       do: list

  defp maybe_missing_status_code(list, _value), do: list ++ ["status.status_code"]

  defp maybe_missing_recipients(list, %Recipients{} = recipients) do
    if recipients_empty?(recipients), do: list ++ ["recipients"], else: list
  end

  defp maybe_missing_recipients(list, _value), do: list ++ ["recipients"]

  defp encode_sender_identification(nil), do: "<SenderIdentification/>"

  defp encode_sender_identification(%SenderIdentification{} = sender_identification) do
    [
      "<SenderIdentification>",
      maybe_tag("VASPID", sender_identification.vasp_id),
      maybe_tag("VASID", sender_identification.vas_id),
      encode_optional_sender_address(sender_identification.sender_address),
      "</SenderIdentification>"
    ]
  end

  defp encode_optional_sender_address(nil), do: ""

  defp encode_optional_sender_address(address) do
    wrap("SenderAddress", encode_address(address))
  end

  defp encode_recipients(%Recipients{} = recipients) do
    [
      "<Recipients>",
      encode_recipient_group("To", recipients.to),
      encode_recipient_group("Cc", recipients.cc),
      encode_recipient_group("Bcc", recipients.bcc),
      "</Recipients>"
    ]
  end

  defp encode_optional_recipients(nil), do: ""

  defp encode_optional_recipients(%Recipients{} = recipients) do
    if recipients_empty?(recipients), do: "", else: encode_recipients(recipients)
  end

  defp encode_recipient_group(_tag, []), do: ""

  defp encode_recipient_group(tag, list) do
    ["<", tag, ">", Enum.map(list, &encode_address/1), "</", tag, ">"]
  end

  defp encode_address(%Address{kind: kind, value: value} = address) do
    tag_name = @address_kind_to_tag[kind]

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

  defp encode_address_attrs(address) do
    [
      maybe_attr("displayOnly", bool_to_text(address.display_only)),
      maybe_attr("addressCoding", address.address_coding),
      maybe_attr("id", address.id)
    ]
  end

  defp encode_status(%Status{} = status) do
    with {:ok, status_code} <- parse_positive_integer(status.status_code, "status.status_code") do
      status_text = status.status_text || default_status_text(status_code)

      {:ok,
       [
         "<Status>",
         tag("StatusCode", Integer.to_string(status_code)),
         tag("StatusText", status_text),
         maybe_tag("Details", status.details),
         "</Status>"
       ]}
    end
  end

  defp default_status_text(status_code), do: Map.get(@default_status_text, status_code, "Status")

  defp open_root(name), do: ["<", name, " xmlns=\"", @canonical_ns, "\">"]
  defp close_root(name), do: ["</", name, ">"]

  defp wrap(name, inner), do: ["<", name, ">", inner, "</", name, ">"]

  defp tag(name, value), do: ["<", name, ">", escape(value), "</", name, ">"]

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

  defp parse_optional_xml_bool(nil, _field), do: {:ok, nil}
  defp parse_optional_xml_bool("true", _field), do: {:ok, true}
  defp parse_optional_xml_bool("1", _field), do: {:ok, true}
  defp parse_optional_xml_bool("false", _field), do: {:ok, false}
  defp parse_optional_xml_bool("0", _field), do: {:ok, false}

  defp parse_optional_xml_bool(_value, field) do
    error(:invalid_structure, "expected boolean", %{field: field})
  end

  defp bool_to_text(true), do: "true"
  defp bool_to_text(false), do: "false"
  defp bool_to_text(_value), do: nil

  defp optional_attr(node, name) do
    case Map.get(node.attrs, name) do
      nil ->
        {:ok, nil}

      %{ns: ns} when ns != "" ->
        error(:invalid_structure, "unexpected attribute namespace", %{
          attribute: name,
          namespace: ns
        })

      %{value: ""} ->
        error(:invalid_structure, "empty value is not allowed", %{element: name})

      %{value: value} ->
        {:ok, value}
    end
  end

  defp validate_exact_struct_keys(%module{} = struct) do
    expected =
      module
      |> struct()
      |> Map.keys()
      |> MapSet.new()

    actual = Map.keys(struct) |> MapSet.new()

    extras =
      actual
      |> MapSet.difference(expected)
      |> MapSet.delete(:__struct__)
      |> MapSet.to_list()
      |> Enum.sort()

    if extras == [] do
      :ok
    else
      error(:invalid_struct, "unexpected struct keys", %{extra_keys: extras})
    end
  end

  defp validate_recipients_presence(recipients) do
    if recipients_empty?(recipients) do
      error(:invalid_struct, "Recipients must contain at least one address")
    else
      :ok
    end
  end

  defp recipients_empty?(%Recipients{} = recipients) do
    recipients.to == [] and recipients.cc == [] and recipients.bcc == []
  end

  defp validate_string_fields(struct, fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_string_value(Map.get(struct, field), Atom.to_string(field), :invalid_struct) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_string_value(nil, _field, _code), do: :ok
  defp validate_string_value(value, _field, _code) when is_binary(value) and value != "", do: :ok

  defp validate_string_value(_value, field, code) do
    error(code, "field must be non-empty string", %{field: field})
  end

  defp validate_required_string(value, _field, _code) when is_binary(value) and value != "",
    do: :ok

  defp validate_required_string(_value, field, code),
    do: error(code, "field must be non-empty string", %{field: field})

  defp validate_boolean_fields(struct, fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_optional_boolean(Map.get(struct, field), Atom.to_string(field)) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_optional_boolean(nil, _field), do: :ok
  defp validate_optional_boolean(true, _field), do: :ok
  defp validate_optional_boolean(false, _field), do: :ok

  defp validate_optional_boolean(_value, field) do
    error(:invalid_struct, "field must be boolean", %{field: field})
  end

  defp validate_optional_positive_integer(nil, _field), do: :ok

  defp validate_optional_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: :ok

  defp validate_optional_positive_integer(_value, field) do
    error(:invalid_struct, "field must be positive integer", %{field: field})
  end

  defp error(code, message, details \\ %{}) do
    {:error, %{code: code, message: message, details: details}}
  end
end
