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

## API
- Основная функция: `MM7Core.convert(input, opts \\ [])`
- Вход:
  - XML body (`binary`) -> `{:ok, map}`
  - JSON (`binary`) с `kind` -> `{:ok, xml_body}`
  - `map` с `kind` -> `{:ok, xml_body}`
- Ошибки: `{:error, %{code: atom(), message: binary(), details: map()}}`

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
- Структурные заготовки:
  - `templates/stage1/structure/json/*`
  - `templates/stage1/structure/xml/*`
- Ручной вход/выход:
  - `samples/in`
  - `samples/out`

## Выбор XML-парсера
- Для stage-1 выбран `:xmerl_scan`.
- Причина: меньше кода и ниже риск ошибок для минимального прототипа.
- `:xmerl_sax_parser` рассмотрен, но отложен до этапа, где нужна потоковая обработка больших payload.

## Ограничения stage-1
- Нет SOAP/MIME функциональности.
- Нет legacy namespace/compatibility mode.
- `DeliverReq.Previouslysentby` и `DeliverReq.Previouslysentdateandtime` сейчас явно отклоняются как `unsupported_stage_feature`.
