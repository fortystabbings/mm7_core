# Runnable stage-1 struct example.
%MM7Core.Messages.DeliverReq{
  mm7_version: "6.8.0",
  mms_relay_server_id: "relay-1.mms.example",
  vasp_id: "TNN",
  vas_id: "Reminder",
  linked_id: "wthr8391",
  sender: %MM7Core.Messages.Address{
    kind: :rfc2822_address,
    value: "97254265781@omms.com"
  },
  recipients: %MM7Core.Messages.Recipients{
    to: [
      %MM7Core.Messages.Address{
        kind: :short_code,
        value: "7255"
      }
    ],
    cc: [],
    bcc: []
  },
  time_stamp: "2026-04-13T14:35:21+03:00",
  priority: "Normal",
  subject: "Weather Forecast",
  applic_id: "ifx.com.neon.weather",
  reply_applic_id: "ifx.com.neon.weather.reply",
  aux_applic_info: "city=moscow"
}
