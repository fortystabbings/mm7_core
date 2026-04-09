# mm7_core

`mm7_core` — минимальный stage-1 прототип MM7 body-level конвертера (Elixir).

## Что реализовано
- Один публичный API: `MM7Core.convert/2`.
- Поддерживаемые виды сообщений:
  - `mm7_submit_req`
  - `mm7_submit_res`
  - `mm7_deliver_req`
  - `mm7_deliver_res`
- Направления конвертации:
  - XML body -> нормализованный map
  - JSON/map (`kind`) -> XML body
- Явные структурированные ошибки для invalid/unsupported сценариев.
- Усилена валидация stage-1:
  - `status.status_code`, `delivery_condition.dc`, `reply_charging.reply_charging_size` -> только `positive_integer`;
  - строгий reject unsupported stage keys (`soap_envelope`, `soap_header`, `mime`) в map/JSON;
  - reject некорректных `addressCoding` и пустых optional text-узлов.

## Каноническая XML-политика stage-1
- Канонический источник структуры: raw XSD + Annex L.
- Канонический namespace для генерации: `REL-6-MM7-1-4`.
- Legacy/sample namespace поддержка в этом проходе не добавлялась.

## Parser choice
Используется `:xmerl_scan` (OTP) без дополнительных XML-зависимостей:
- минимальный runtime footprint;
- предсказуемый контроль структуры по корневому тегу и элементам;
- безопасная отсечка `DOCTYPE`/`ENTITY` до парсинга.

## Пример использования
```elixir
# XML -> map
{:ok, data} = MM7Core.convert("""
<SubmitRsp xmlns=\"http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4\">
  <MM7Version>6.8.0</MM7Version>
  <Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status>
  <MessageID>041502073667</MessageID>
</SubmitRsp>
""")

# JSON/map -> XML
{:ok, xml} = MM7Core.convert(%{
  kind: "mm7_deliver_res",
  mm7_version: "6.8.0",
  status: %{status_code: 1000, status_text: "Success"}
})
```

## Проверка
Во всей сессии использовать переменные среды:
```bash
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix format --check-formatted
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix compile
MIX_HOME=/tmp/mix HEX_HOME=/tmp/hex mix test
```

## Ограничения stage-1
- Только XML внутри `SOAP Envelope.Body`.
- Без SOAP Envelope/Header/TransactionID.
- Без MIME/attachments/`href:cid` обработки содержимого MIME-частей.
- Без arbitrary binary payload обработки как контента MM.
- `Status/Details` обрабатывается как текстовая проекция (без полного `anyDataType` subtree round-trip).
- Для `DeliverReq` поля `Previouslysentby`/`Previouslysentdateandtime` пока не поддержаны и отклоняются как `invalid_structure`.
