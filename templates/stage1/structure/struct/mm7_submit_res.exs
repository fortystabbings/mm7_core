# MM7Core.Messages.SubmitRsp
# mandatory: mm7_version, status.status_code
%MM7Core.Messages.SubmitRsp{
  mm7_version: "<required:string>",
  status: %MM7Core.Messages.Status{
    status_code: "<required:positive_integer>",
    status_text: "<optional:string>",
    details: "<optional:string>"
  },
  message_id: "<optional:string>"
}
