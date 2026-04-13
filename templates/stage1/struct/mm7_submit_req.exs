# Runnable stage-1 struct example.
%MM7Core.Messages.SubmitReq{
  mm7_version: "6.8.0",
  sender_identification: %MM7Core.Messages.SenderIdentification{
    vasp_id: "acme_vasp",
    vas_id: "promo_service"
  },
  recipients: %MM7Core.Messages.Recipients{
    to: [
      %MM7Core.Messages.Address{
        kind: :number,
        value: "79001234567"
      }
    ],
    cc: [
      %MM7Core.Messages.Address{
        kind: :rfc2822_address,
        value: "ops@example.net"
      }
    ],
    bcc: []
  },
  service_code: "gold-sp33-im42",
  linked_id: "mms00016666",
  message_class: "Informational",
  time_stamp: "2026-04-13T09:30:47+03:00",
  delivery_report: true,
  read_reply: false,
  priority: "Normal",
  subject: "Daily promo",
  applic_id: "ifx.com.neon.MyPackage.MAFIA",
  reply_applic_id: "ifx.com.neon.downloadedPackage.MAFIA",
  aux_applic_info: "session.ABC.DEF"
}
