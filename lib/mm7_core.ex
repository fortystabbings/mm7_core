defmodule MM7Core do
  @moduledoc """
  Минимальный stage-1 конвертер MM7 body-level сообщений.
  """

  alias MM7Core.Messages.DeliverReq
  alias MM7Core.Messages.DeliverRsp
  alias MM7Core.Messages.SubmitReq
  alias MM7Core.Messages.SubmitRsp

  @canonical_ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  @root_to_module %{
    "SubmitReq" => SubmitReq,
    "SubmitRsp" => SubmitRsp,
    "DeliverReq" => DeliverReq,
    "DeliverRsp" => DeliverRsp
  }
  @supported_modules Map.values(@root_to_module)

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
  def convert(_input, _opts), do: error(:unsupported_input_format, "unsupported input type")

  defp xml_to_struct(xml) do
    with :ok <- reject_dtd(xml),
         {:ok, root} <- parse_xml(xml),
         :ok <- reject_stage_features(root),
         {:ok, module} <- detect_module(root.name),
         :ok <- validate_tree_namespaces(root),
         {:ok, struct} <- module.from_xml(root),
         :ok <- module.validate(struct) do
      {:ok, struct}
    end
  end

  defp struct_to_xml(%module{} = struct) when module in @supported_modules,
    do: module.to_xml(struct)

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
  defp sax_event({:ignorableWhitespace, _chars}, _line, state), do: state

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
        %{state | stack: [%{parent | children: [normalized | parent.children]} | tail]}
    end
  end

  defp attrs_to_map(attrs) do
    Enum.reduce(attrs, %{}, fn {uri, _, name, value}, acc ->
      local_name = IO.chardata_to_string(name)
      namespace = IO.chardata_to_string(uri)

      Map.update(
        acc,
        local_name,
        %{ns: namespace, value: IO.chardata_to_string(value)},
        fn existing ->
          Map.put(existing, :duplicate?, true)
        end
      )
    end)
  end

  defp detect_module(root_name) do
    case @root_to_module[root_name] do
      nil -> error(:unknown_xml_root, "unknown xml root", %{root: root_name})
      module -> {:ok, module}
    end
  end

  defp validate_tree_namespaces(%{ns: @canonical_ns, children: children}) do
    Enum.reduce_while(children, :ok, fn child, :ok ->
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

  defp tree_contains_element?(%{children: children}, name) do
    Enum.any?(children, &tree_contains_element?(&1, name))
  end

  defp error(code, message, details \\ %{}) do
    {:error, %{code: code, message: message, details: details}}
  end
end
