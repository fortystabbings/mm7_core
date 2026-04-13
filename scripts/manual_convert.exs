root = Path.expand("..", __DIR__)
samples_in = Path.join(root, "samples/in")
samples_out = Path.join(root, "samples/out")

unless Code.ensure_loaded?(MM7Core) do
  message_module_files =
    Path.wildcard(Path.join(root, "lib/mm7_core/messages/*.ex"))
    |> Enum.sort()
    |> Enum.reject(&String.ends_with?(&1, "/support.ex"))
    |> Enum.reject(&String.ends_with?(&1, "/shared_structs.ex"))

  code_files =
    [
      "lib/mm7_core/messages/shared_structs.ex",
      "lib/mm7_core/messages/support.ex"
    ] ++ message_module_files ++ ["lib/mm7_core.ex"]

  Enum.each(code_files, &Code.require_file(&1, root))
end

in_files =
  Path.wildcard(Path.join(samples_in, "*"))
  |> Enum.reject(&(Path.basename(&1) |> String.starts_with?(".")))

if length(in_files) != 1 do
  IO.puts("ERROR: samples/in должен содержать ровно 1 входной файл")
  System.halt(1)
end

in_file = hd(in_files)
base = Path.rootname(Path.basename(in_file))
input_text = File.read!(in_file)
extension = Path.extname(in_file)

input =
  cond do
    extension == ".xml" and String.starts_with?(String.trim_leading(input_text), "<") ->
      input_text

    extension == ".exs" ->
      try do
        {value, _binding} = Code.eval_file(in_file)
        value
      rescue
        error ->
          IO.puts("ERROR: не удалось вычислить struct input: #{Exception.message(error)}")
          System.halt(1)
      end

    true ->
      IO.puts("ERROR: samples/in поддерживает только .xml или .exs")
      System.halt(1)
  end

stale_out_files =
  Path.wildcard(Path.join(samples_out, "*"))
  |> Enum.reject(&(Path.basename(&1) |> String.starts_with?(".")))

case MM7Core.convert(input) do
  {:ok, out} when is_binary(out) ->
    Enum.each(stale_out_files, &File.rm!/1)
    out_file = Path.join(samples_out, base <> ".xml")
    File.write!(out_file, out)
    IO.puts("OK: " <> out_file)

  {:ok, out} when is_struct(out) ->
    Enum.each(stale_out_files, &File.rm!/1)
    out_file = Path.join(samples_out, base <> ".exs")

    rendered =
      inspect(out,
        pretty: true,
        width: 98,
        limit: :infinity,
        printable_limit: :infinity
      ) <> "\n"

    File.write!(out_file, rendered)
    IO.puts("OK: " <> out_file)

  {:error, err} ->
    IO.puts("ERROR: " <> inspect(err))
    System.halt(1)
end
