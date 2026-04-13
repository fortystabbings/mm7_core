# MM7Core.Messages.SubmitRsp
# mandatory: mm7_version, status.status_code
# status_text optional at struct floor, but canonical XML emits StatusText
# message_id optional at struct floor, though canonical XML tree still shows MessageID
%MM7Core.Messages.SubmitRsp{
  mm7_version: "<required:string>",
  status: %MM7Core.Messages.Status{
    status_code: "<required:positive_integer>",
    status_text: "<optional:string>",
    details: "<optional:string>"
  },
  message_id: "<optional:string>"
}
