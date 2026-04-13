defmodule MM7Core.Messages.Support do
  @moduledoc false

  @canonical_ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

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

  @sender_identification_optional_fields [
    {:text, :vasp_id, "VASPID"},
    {:text, :vas_id, "VASID"}
  ]

  @type error_result :: {:error, MM7Core.error_t()}
  @type result(value) :: {:ok, value} | error_result()
  @type xml_attr :: %{
          required(:ns) => String.t(),
          required(:value) => String.t(),
          optional(:duplicate?) => true
        }
  @type xml_node :: %{
          required(:name) => String.t(),
          required(:ns) => String.t(),
          required(:attrs) => %{optional(String.t()) => xml_attr()},
          required(:children) => [xml_node()],
          required(:text) => String.t()
        }
  @type optional_field_spec :: {:text | :bool, atom(), String.t()}

  @spec ensure_children(xml_node(), [String.t()], keyword()) :: :ok | error_result()
  def ensure_children(node, allowed, opts \\ []) do
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

  @spec required_text(xml_node(), String.t()) :: result(String.t())
  def required_text(node, name) do
    case optional_text(node, name) do
      {:ok, nil} -> error(:invalid_structure, "missing #{name}")
      {:ok, value} -> {:ok, value}
      {:error, _} = err -> err
    end
  end

  @spec optional_text(xml_node(), String.t()) :: result(String.t() | nil)
  def optional_text(node, name) do
    with {:ok, child} <- single_child(node, name) do
      case child do
        nil -> {:ok, nil}
        child -> simple_text(child)
      end
    end
  end

  @spec collect_optional_fields(xml_node(), [optional_field_spec()]) :: result(map())
  def collect_optional_fields(node, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case collect_optional_field(node, field) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @spec required_sender_identification(xml_node()) ::
          result(MM7Core.Messages.SenderIdentification.t() | nil)
  def required_sender_identification(root) do
    with {:ok, node} <- single_child(root, "SenderIdentification") do
      case node do
        nil -> error(:invalid_structure, "missing SenderIdentification")
        node -> decode_sender_identification_node(node)
      end
    end
  end

  @spec required_recipients(xml_node()) :: result(MM7Core.Messages.Recipients.t())
  def required_recipients(root) do
    with {:ok, node} <- single_child(root, "Recipients") do
      case node do
        nil -> error(:invalid_structure, "missing Recipients")
        node -> decode_recipients_node(node)
      end
    end
  end

  @spec optional_recipients(xml_node()) :: result(MM7Core.Messages.Recipients.t() | nil)
  def optional_recipients(root) do
    with {:ok, node} <- single_child(root, "Recipients") do
      case node do
        nil -> {:ok, nil}
        node -> decode_recipients_node(node)
      end
    end
  end

  @spec required_address(xml_node(), String.t()) :: result(MM7Core.Messages.Address.t())
  def required_address(root, name) do
    with {:ok, node} <- single_child(root, name) do
      case node do
        nil -> error(:invalid_structure, "missing #{name}")
        node -> decode_single_address(node, name)
      end
    end
  end

  @spec optional_address(xml_node(), String.t()) :: result(MM7Core.Messages.Address.t() | nil)
  defp optional_address(root, name) do
    with {:ok, node} <- single_child(root, name) do
      case node do
        nil -> {:ok, nil}
        node -> decode_single_address(node, name)
      end
    end
  end

  @spec decode_status(xml_node()) :: result(MM7Core.Messages.Status.t())
  def decode_status(root) do
    with {:ok, node} <- single_child(root, "Status") do
      case node do
        nil ->
          error(:invalid_structure, "missing Status")

        node ->
          decode_status_node(node)
      end
    end
  end

  @spec validate_exact_struct_keys(struct()) :: :ok | error_result()
  def validate_exact_struct_keys(%module{} = struct) do
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

  @spec validate_string_fields(struct(), [atom()]) :: :ok | error_result()
  def validate_string_fields(struct, fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_string_value(Map.get(struct, field), Atom.to_string(field), :invalid_struct) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @spec validate_required_string(term(), String.t(), atom()) :: :ok | error_result()
  def validate_required_string(value, _field, _code) when is_binary(value) and value != "",
    do: :ok

  def validate_required_string(_value, field, code) do
    error(code, "field must be non-empty string", %{field: field})
  end

  @spec validate_boolean_fields(struct(), [atom()]) :: :ok | error_result()
  def validate_boolean_fields(struct, fields) do
    Enum.reduce_while(fields, :ok, fn field, :ok ->
      case validate_optional_boolean(Map.get(struct, field), Atom.to_string(field)) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @spec validate_optional_boolean(term(), String.t()) :: :ok | error_result()
  def validate_optional_boolean(nil, _field), do: :ok
  def validate_optional_boolean(true, _field), do: :ok
  def validate_optional_boolean(false, _field), do: :ok

  def validate_optional_boolean(_value, field) do
    error(:invalid_struct, "field must be boolean", %{field: field})
  end

  @spec validate_optional_positive_integer(term(), String.t()) :: :ok | error_result()
  def validate_optional_positive_integer(nil, _field), do: :ok

  def validate_optional_positive_integer(value, _field) when is_integer(value) and value > 0,
    do: :ok

  def validate_optional_positive_integer(_value, field) do
    error(:invalid_struct, "field must be positive integer", %{field: field})
  end

  @spec maybe_missing_string([String.t()], term(), String.t()) :: [String.t()]
  def maybe_missing_string(list, value, _field) when is_binary(value) and value != "", do: list
  def maybe_missing_string(list, _value, field), do: list ++ [field]

  @spec maybe_missing_address([String.t()], term(), String.t()) :: [String.t()]
  def maybe_missing_address(list, %MM7Core.Messages.Address{kind: kind, value: value}, _field)
      when kind in @address_kinds and is_binary(value) and value != "" do
    list
  end

  def maybe_missing_address(list, _value, field), do: list ++ [field]

  @spec maybe_missing_status_code([String.t()], term()) :: [String.t()]
  def maybe_missing_status_code(list, %MM7Core.Messages.Status{status_code: value})
      when is_integer(value) and value > 0,
      do: list

  def maybe_missing_status_code(list, _value), do: list ++ ["status.status_code"]

  @spec maybe_missing_recipients([String.t()], term()) :: [String.t()]
  def maybe_missing_recipients(list, %MM7Core.Messages.Recipients{} = recipients) do
    if recipients_empty?(recipients), do: list ++ ["recipients"], else: list
  end

  def maybe_missing_recipients(list, _value), do: list ++ ["recipients"]

  @spec missing_or_ok(module(), [String.t()]) :: :ok | error_result()
  def missing_or_ok(_module, []), do: :ok

  def missing_or_ok(module, missing) do
    error(:missing_mandatory_fields, "missing mandatory fields", %{
      struct: inspect(module),
      fields: missing
    })
  end

  @spec validate_sender_identification(term()) :: :ok | error_result()
  def validate_sender_identification(nil), do: :ok

  def validate_sender_identification(
        %MM7Core.Messages.SenderIdentification{} = sender_identification
      ) do
    with :ok <- validate_string_fields(sender_identification, [:vasp_id, :vas_id]),
         :ok <- validate_address(sender_identification.sender_address) do
      :ok
    end
  end

  def validate_sender_identification(_value) do
    error(:invalid_struct, "sender_identification must be struct")
  end

  @spec validate_status(term()) :: :ok | error_result()
  def validate_status(nil), do: :ok

  def validate_status(%MM7Core.Messages.Status{} = status) do
    with :ok <- validate_optional_positive_integer(status.status_code, "status.status_code"),
         :ok <- validate_string_fields(status, [:status_text, :details]) do
      :ok
    end
  end

  def validate_status(_value) do
    error(:invalid_struct, "status must be struct")
  end

  @spec validate_recipients(term()) :: :ok | error_result()
  def validate_recipients(nil), do: :ok

  def validate_recipients(%MM7Core.Messages.Recipients{} = recipients) do
    with :ok <- validate_address_list(recipients.to, "recipients.to"),
         :ok <- validate_address_list(recipients.cc, "recipients.cc"),
         :ok <- validate_address_list(recipients.bcc, "recipients.bcc"),
         :ok <- validate_recipients_presence(recipients) do
      :ok
    end
  end

  def validate_recipients(_value) do
    error(:invalid_struct, "recipients must be struct")
  end

  @spec validate_address(term()) :: :ok | error_result()
  def validate_address(nil), do: :ok

  def validate_address(%MM7Core.Messages.Address{} = address) do
    with :ok <- validate_address_kind(address.kind),
         :ok <- validate_required_string(address.value, "address.value", :invalid_struct),
         :ok <- validate_optional_boolean(address.display_only, "address.display_only"),
         :ok <- validate_string_value(address.id, "address.id", :invalid_struct),
         :ok <- validate_address_coding(address.address_coding, :invalid_struct) do
      :ok
    end
  end

  def validate_address(_value) do
    error(:invalid_struct, "address must be struct")
  end

  @spec recipients_empty?(MM7Core.Messages.Recipients.t()) :: boolean()
  def recipients_empty?(%MM7Core.Messages.Recipients{} = recipients) do
    recipients.to == [] and recipients.cc == [] and recipients.bcc == []
  end

  def encode_sender_identification(nil), do: "<SenderIdentification/>"

  def encode_sender_identification(
        %MM7Core.Messages.SenderIdentification{} = sender_identification
      ) do
    [
      "<SenderIdentification>",
      maybe_tag("VASPID", sender_identification.vasp_id),
      maybe_tag("VASID", sender_identification.vas_id),
      encode_optional_sender_address(sender_identification.sender_address),
      "</SenderIdentification>"
    ]
  end

  def encode_recipients(%MM7Core.Messages.Recipients{} = recipients) do
    [
      "<Recipients>",
      encode_recipient_group("To", recipients.to),
      encode_recipient_group("Cc", recipients.cc),
      encode_recipient_group("Bcc", recipients.bcc),
      "</Recipients>"
    ]
  end

  def encode_optional_recipients(nil), do: ""

  def encode_optional_recipients(%MM7Core.Messages.Recipients{} = recipients) do
    if recipients_empty?(recipients), do: "", else: encode_recipients(recipients)
  end

  def encode_address(%MM7Core.Messages.Address{kind: kind, value: value} = address) do
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

  @spec encode_status(MM7Core.Messages.Status.t()) :: result(iodata())
  def encode_status(%MM7Core.Messages.Status{} = status) do
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

  def open_root(name), do: ["<", name, " xmlns=\"", @canonical_ns, "\">"]
  def close_root(name), do: ["</", name, ">"]
  def wrap(name, inner), do: ["<", name, ">", inner, "</", name, ">"]
  def tag(name, value), do: ["<", name, ">", escape(value), "</", name, ">"]
  def maybe_tag(_name, nil), do: ""
  def maybe_tag(_name, ""), do: ""
  def maybe_tag(name, value), do: tag(name, value)
  def maybe_attr(_name, nil), do: ""
  def maybe_attr(_name, ""), do: ""
  def maybe_attr(name, value), do: [" ", name, "=\"", escape(value), "\""]

  def escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  def escape(value), do: value |> to_string() |> escape()

  @spec parse_positive_integer(String.t() | pos_integer(), String.t()) :: result(pos_integer())
  def parse_positive_integer(value, _field) when is_integer(value) and value > 0, do: {:ok, value}

  def parse_positive_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> error(:invalid_structure, "expected positive integer", %{field: field})
    end
  end

  def parse_positive_integer(_value, field) do
    error(:invalid_structure, "expected positive integer", %{field: field})
  end

  @spec parse_optional_xml_bool(String.t() | nil, String.t()) :: result(boolean() | nil)
  def parse_optional_xml_bool(nil, _field), do: {:ok, nil}
  def parse_optional_xml_bool("true", _field), do: {:ok, true}
  def parse_optional_xml_bool("1", _field), do: {:ok, true}
  def parse_optional_xml_bool("false", _field), do: {:ok, false}
  def parse_optional_xml_bool("0", _field), do: {:ok, false}

  def parse_optional_xml_bool(_value, field) do
    error(:invalid_structure, "expected boolean", %{field: field})
  end

  def bool_to_text(true), do: "true"
  def bool_to_text(false), do: "false"
  def bool_to_text(_value), do: nil

  @spec optional_attr(xml_node(), String.t()) :: result(String.t() | nil)
  def optional_attr(node, name) do
    case Map.get(node.attrs, name) do
      nil ->
        {:ok, nil}

      %{duplicate?: true} ->
        error(:invalid_structure, "duplicate attribute name", %{attribute: name})

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

  @spec error(atom(), String.t(), map()) :: error_result()
  def error(code, message, details \\ %{}) do
    {:error, %{code: code, message: message, details: details}}
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

  @spec single_child(xml_node(), String.t()) :: result(xml_node() | nil)
  defp single_child(node, name) do
    matches = Enum.filter(element_children(node), &(&1.name == name))

    case matches do
      [] -> {:ok, nil}
      [child] -> {:ok, child}
      _ -> error(:invalid_structure, "duplicate child element", %{element: name})
    end
  end

  defp element_children(node), do: node.children

  @spec simple_text(xml_node()) :: result(String.t())
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

  @spec collect_optional_field(xml_node(), optional_field_spec()) ::
          result({atom(), String.t() | boolean()} | nil)
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

  @spec decode_status_node(xml_node()) :: result(MM7Core.Messages.Status.t())
  defp decode_status_node(node) do
    with :ok <- ensure_children(node, ["StatusCode", "StatusText", "Details"], ordered: false),
         {:ok, status_code_text} <- required_text(node, "StatusCode"),
         {:ok, status_code} <- parse_positive_integer(status_code_text, "status.status_code"),
         {:ok, status_text} <- optional_text(node, "StatusText"),
         {:ok, details} <- optional_text(node, "Details") do
      {:ok,
       %MM7Core.Messages.Status{
         status_code: status_code,
         status_text: status_text,
         details: details
       }}
    end
  end

  @spec decode_sender_identification_node(xml_node()) ::
          result(MM7Core.Messages.SenderIdentification.t() | nil)
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
        {:ok, struct(MM7Core.Messages.SenderIdentification, attrs)}
      end
    end
  end

  @spec decode_recipients_node(xml_node()) :: result(MM7Core.Messages.Recipients.t())
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
          recipients = %MM7Core.Messages.Recipients{to: groups.to, cc: groups.cc, bcc: groups.bcc}

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

  @spec decode_address_list(xml_node()) :: result([MM7Core.Messages.Address.t()])
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

  @spec decode_single_address(xml_node(), String.t()) :: result(MM7Core.Messages.Address.t())
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

  @spec decode_address_node(xml_node()) :: result(MM7Core.Messages.Address.t())
  defp decode_address_node(node) do
    kind = @address_tag_to_kind[node.name]
    unknown_attrs = Map.keys(node.attrs) -- ["displayOnly", "addressCoding", "id"]

    cond do
      is_nil(kind) ->
        error(:invalid_structure, "invalid address structure", %{element: node.name})

      unknown_attrs != [] ->
        error(:invalid_structure, "unexpected attributes", %{
          element: node.name,
          attributes: Enum.sort(unknown_attrs)
        })

      true ->
        with {:ok, display_only} <- optional_attr(node, "displayOnly"),
             {:ok, display_only} <- parse_optional_xml_bool(display_only, "displayOnly"),
             {:ok, address_coding} <- optional_attr(node, "addressCoding"),
             :ok <- validate_address_coding(address_coding, :invalid_structure),
             {:ok, id} <- optional_attr(node, "id"),
             {:ok, value} <- simple_text(node) do
          {:ok,
           %MM7Core.Messages.Address{
             kind: kind,
             value: value,
             display_only: display_only,
             address_coding: address_coding,
             id: id
           }}
        end
    end
  end

  @spec validate_address_list(term(), String.t()) :: :ok | error_result()
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

  @spec validate_recipients_presence(MM7Core.Messages.Recipients.t()) :: :ok | error_result()
  defp validate_recipients_presence(recipients) do
    if recipients_empty?(recipients) do
      error(:invalid_struct, "Recipients must contain at least one address")
    else
      :ok
    end
  end

  @spec validate_address_kind(term()) :: :ok | error_result()
  defp validate_address_kind(kind) when kind in @address_kinds, do: :ok

  defp validate_address_kind(_kind) do
    error(:invalid_struct, "unknown address kind")
  end

  @spec validate_address_coding(String.t() | nil, atom()) :: :ok | error_result()
  defp validate_address_coding(nil, _code), do: :ok
  defp validate_address_coding("encrypted", _code), do: :ok
  defp validate_address_coding("obfuscated", _code), do: :ok

  defp validate_address_coding(_value, code) do
    error(code, "field must be encrypted or obfuscated", %{field: "address_coding"})
  end

  @spec validate_string_value(term(), String.t(), atom()) :: :ok | error_result()
  defp validate_string_value(nil, _field, _code), do: :ok
  defp validate_string_value(value, _field, _code) when is_binary(value) and value != "", do: :ok

  defp validate_string_value(_value, field, code) do
    error(code, "field must be non-empty string", %{field: field})
  end

  @spec encode_optional_sender_address(MM7Core.Messages.Address.t() | nil) :: iodata()
  defp encode_optional_sender_address(nil), do: ""

  defp encode_optional_sender_address(address) do
    wrap("SenderAddress", encode_address(address))
  end

  defp encode_recipient_group(_tag, []), do: ""

  defp encode_recipient_group(tag, list) do
    ["<", tag, ">", Enum.map(list, &encode_address/1), "</", tag, ">"]
  end

  defp encode_address_attrs(address) do
    [
      maybe_attr("displayOnly", bool_to_text(address.display_only)),
      maybe_attr("addressCoding", address.address_coding),
      maybe_attr("id", address.id)
    ]
  end

  defp default_status_text(status_code), do: Map.get(@default_status_text, status_code, "Status")
end
