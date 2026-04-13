# MM7Core.Messages.DeliverReq
# mandatory: mm7_version, sender
%MM7Core.Messages.DeliverReq{
  mm7_version: "<required:string>",
  mms_relay_server_id: "<optional:string>",
  vasp_id: "<optional:string>",
  vas_id: "<optional:string>",
  linked_id: "<optional:string>",
  sender: %MM7Core.Messages.Address{
    kind: :rfc2822_address,
    value: "<required if address struct is present:string>",
    display_only: "<optional:boolean>",
    address_coding: "<optional:encrypted|obfuscated>",
    id: "<optional:string>"
  },
  recipients: %MM7Core.Messages.Recipients{
    to: [
      %MM7Core.Messages.Address{
        kind: :short_code,
        value: "<required if address struct is present:string>",
        display_only: "<optional:boolean>",
        address_coding: "<optional:encrypted|obfuscated>",
        id: "<optional:string>"
      }
    ],
    cc: [],
    bcc: []
  },
  time_stamp: "<optional:xs_date_time>",
  priority: "<optional:string>",
  subject: "<optional:string>",
  applic_id: "<optional:string>",
  reply_applic_id: "<optional:string>",
  aux_applic_info: "<optional:string>"
}
