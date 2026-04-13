# MM7Core.Messages.DeliverRsp
# mandatory: mm7_version, status.status_code
# status_text optional at struct floor, but canonical XML emits StatusText
%MM7Core.Messages.DeliverRsp{
  mm7_version: "<required:string>",
  status: %MM7Core.Messages.Status{
    status_code: "<required:positive_integer>",
    status_text: "<optional:string>",
    details: "<optional:string>"
  },
  service_code: "<optional:string>"
}
