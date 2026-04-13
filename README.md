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
  - XML body (`binary`) -> `{:ok, struct}`
  - поддержанный Elixir struct -> `{:ok, xml_body}`
- Ошибки: `{:error, %{code: atom(), message: binary(), details: map()}}`
- Публичный in-memory contract stage-1:
  - `MM7Core.Messages.SubmitReq`
  - `MM7Core.Messages.SubmitRsp`
  - `MM7Core.Messages.DeliverReq`
  - `MM7Core.Messages.DeliverRsp`
- Внутренняя архитектура stage-1:
  - `MM7Core` — thin routing/core entry module
  - message-specific logic вынесена в отдельные `MM7Core.Messages.*` modules по виду сообщения
- Общий nested/XML support для этих модулей держится во внутреннем `MM7Core.Messages.Support`; это не public API.

Пример XML -> struct:

```elixir
xml = """
<SubmitReq xmlns="http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4">
  <MM7Version>6.8.0</MM7Version>
  <SenderIdentification><VASPID>acme</VASPID></SenderIdentification>
  <Recipients><To><Number>79001234567</Number></To></Recipients>
</SubmitReq>
"""

{:ok, %MM7Core.Messages.SubmitReq{} = struct} = MM7Core.convert(xml)
```

Пример struct -> XML:

```elixir
input = %MM7Core.Messages.SubmitRsp{
  mm7_version: "6.8.0",
  status: %MM7Core.Messages.Status{status_code: 1000, status_text: "Success"},
  message_id: "m-1"
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
  - `templates/stage1/struct/*`
  - `templates/stage1/xml/*`
  - это runnable входы для ручной проверки
- Структурные заготовки:
  - `templates/stage1/structure/struct/*`
  - `templates/stage1/structure/xml/*`
  - это inspection-only файлы для визуальной сверки со spec и struct contract, не рабочие payload
- Ручной вход/выход:
  - `samples/in`
  - `samples/out`

## Ручная проверка (ровно 1 вход -> ровно 1 выход)
1. Положите ровно один входной файл в `samples/in`:
   - либо XML body fragment (`SubmitReq` / `SubmitRsp` / `DeliverReq` / `DeliverRsp`);
   - либо `.exs` файл, который вычисляется в один поддержанный struct.
   - `.exs` вход исполняется локально Elixir-рантаймом, поэтому используйте только доверенные файлы.
2. Запустите одну команду:
   Скрипт пишет результат только после успешной конвертации и затем оставляет в `samples/out` ровно один актуальный non-hidden файл.

```bash
elixir scripts/manual_convert.exs
```

3. В `samples/out` будет создан ровно один файл противоположного формата:
   - XML -> `.exs`
   - struct `.exs` -> `.xml`

## Ограничения stage-1
- Нет SOAP/MIME функциональности.
- Нет legacy namespace/compatibility mode.
- JSON/map больше не являются основным публичным contract stage-1.
- XML-структуры в `templates/stage1/structure/xml/*` отражают полный canonical body tree из XSD, но runtime покрывает только stage-1 practical subset.
