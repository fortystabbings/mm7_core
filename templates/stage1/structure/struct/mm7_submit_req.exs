# MM7Core.Messages.SubmitReq
# mandatory: mm7_version, recipients
# sender_identification optional in struct contract, but canonical XML still emits SenderIdentification container
%MM7Core.Messages.SubmitReq{
  mm7_version: "<required:string>",
  sender_identification: %MM7Core.Messages.SenderIdentification{
    vasp_id: "<optional:string>",
    vas_id: "<optional:string>",
    sender_address: %MM7Core.Messages.Address{
      kind: :rfc2822_address,
      value: "<required if address struct is present:string>",
      display_only: "<optional:boolean>",
      address_coding: "<optional:encrypted|obfuscated>",
      id: "<optional:string>"
    }
  },
  recipients: %MM7Core.Messages.Recipients{
    to: [
      %MM7Core.Messages.Address{
        kind: :number,
        value: "<required if address struct is present:string>",
        display_only: "<optional:boolean>",
        address_coding: "<optional:encrypted|obfuscated>",
        id: "<optional:string>"
      }
    ],
    cc: [
      %MM7Core.Messages.Address{
        kind: :rfc2822_address,
        value: "<required if address struct is present:string>",
        display_only: "<optional:boolean>",
        address_coding: "<optional:encrypted|obfuscated>",
        id: "<optional:string>"
      }
    ],
    bcc: []
  },
  service_code: "<optional:string>",
  linked_id: "<optional:string>",
  message_class: "<optional:string>",
  time_stamp: "<optional:xs_date_time>",
  delivery_report: "<optional:boolean>",
  read_reply: "<optional:boolean>",
  priority: "<optional:string>",
  subject: "<optional:string>",
  applic_id: "<optional:string>",
  reply_applic_id: "<optional:string>",
  aux_applic_info: "<optional:string>"
}
