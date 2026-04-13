# MM7Core

Минимальный stage-1 прототип библиотеки конвертации MM7 body-level сообщений.

## Текущий scope stage-1
- Работа только с XML внутри `SOAP Envelope.Body`.
- Без SOAP Envelope/Header, без `TransactionID`.
- Без MIME/attachments/`href:cid`.
- Поддержаны только 4 вида:
  - `mm7_submit_req`
  - `mm7_submit_res`
  - `mm7_deliver_req`
  - `mm7_deliver_res`

## Каноническая XML-политика
- Структурный источник: `docs/REL-6-MM7-1-4.xsd` + Annex L.
- Канонический namespace генерации:
  - `http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4`
- Примеры/маппинги из PDF используются как семантическая сверка, но не заменяют XSD-структуру для генерации stage-1.
- Freeze текущего прохода: `docs/mm7_stage1_design_freeze.md`.

## API
- Основная функция: `MM7Core.convert(input, opts \\ [])`
- Вход:
  - XML body (`binary`) -> `{:ok, map}`
  - JSON (`binary`) с `kind` -> `{:ok, xml_body}`
  - `map` с `kind` -> `{:ok, xml_body}`
- Ошибки: `{:error, %{code: atom(), message: binary(), details: map()}}`
- Нормализованный `map`/JSON обрабатывается строго:
  - без неявного приведения типов
  - с явной ошибкой для неверных boolean/string значений

Пример XML -> map:

```elixir
xml = """
<SubmitReq xmlns="http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4">
  <MM7Version>6.8.0</MM7Version>
  <SenderIdentification><VASPID>acme</VASPID></SenderIdentification>
  <Recipients><To><Number>79001234567</Number></To></Recipients>
</SubmitReq>
"""

{:ok, map} = MM7Core.convert(xml)
```

Пример map -> XML:

```elixir
input = %{
  "kind" => "mm7_submit_res",
  "mm7_version" => "6.8.0",
  "status" => %{"status_code" => 1000, "status_text" => "Success"},
  "message_id" => "m-1"
}

{:ok, xml} = MM7Core.convert(input)
```

## Проверка и запуск тестов

```bash
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix format --check-formatted
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix compile
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix test
```

## Шаблоны и ручная проверка
- Примеры:
  - `templates/stage1/json/*`
  - `templates/stage1/xml/*`
  - это runnable входы для ручной проверки
- Структурные заготовки:
  - `templates/stage1/structure/json/*`
  - `templates/stage1/structure/xml/*`
  - это inspection-only файлы для визуальной сверки со spec, не рабочие payload
- Ручной вход/выход:
  - `samples/in`
  - `samples/out`

## Ручная проверка (ровно 1 вход -> ровно 1 выход)
1. Положите ровно один входной файл в `samples/in`:
   - либо XML body fragment (`SubmitReq` / `SubmitRsp` / `DeliverReq` / `DeliverRsp`);
   - либо JSON с явным `kind`.
2. Запустите одну команду:
   Команда ниже перед записью результата удаляет все предыдущие non-hidden файлы из `samples/out`, чтобы на выходе остался ровно один актуальный файл.

```bash
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix run -e '
in_files =
  Path.wildcard("samples/in/*")
  |> Enum.reject(&(Path.basename(&1) |> String.starts_with?(".")))

if length(in_files) != 1 do
  IO.puts("ERROR: samples/in должен содержать ровно 1 входной файл")
  System.halt(1)
end

Path.wildcard("samples/out/*")
|> Enum.reject(&(Path.basename(&1) |> String.starts_with?(".")))
|> Enum.each(&File.rm!/1)

in_file = hd(in_files)
input = File.read!(in_file)
base = Path.rootname(Path.basename(in_file))

case MM7Core.convert(input) do
  {:ok, out} when is_map(out) ->
    out_file = "samples/out/" <> base <> ".json"
    File.write!(out_file, Jason.encode_to_iodata!(out, pretty: true))
    IO.puts("OK: " <> out_file)

  {:ok, out} when is_binary(out) ->
    out_file = "samples/out/" <> base <> ".xml"
    File.write!(out_file, out)
    IO.puts("OK: " <> out_file)

  {:error, err} ->
    IO.puts("ERROR: " <> inspect(err))
    System.halt(1)
end
'
```

3. В `samples/out` будет создан ровно один файл противоположного формата.

## Ограничения stage-1
- Нет SOAP/MIME функциональности.
- Нет legacy namespace/compatibility mode.
- XML-структуры в `templates/stage1/structure/xml/*` отражают полный canonical body tree из XSD, но runtime покрывает только stage-1 practical subset.
