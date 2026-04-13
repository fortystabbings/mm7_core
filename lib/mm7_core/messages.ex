defmodule MM7Core.Messages.Address do
  @type kind :: :rfc2822_address | :number | :short_code

  @type t :: %__MODULE__{
          kind: kind() | nil,
          value: String.t() | nil,
          display_only: boolean() | nil,
          address_coding: String.t() | nil,
          id: String.t() | nil
        }

  defstruct kind: nil,
            value: nil,
            display_only: nil,
            address_coding: nil,
            id: nil
end

defmodule MM7Core.Messages.Recipients do
  alias MM7Core.Messages.Address

  @type t :: %__MODULE__{
          to: [Address.t()],
          cc: [Address.t()],
          bcc: [Address.t()]
        }

  defstruct to: [], cc: [], bcc: []
end

defmodule MM7Core.Messages.SenderIdentification do
  alias MM7Core.Messages.Address

  @type t :: %__MODULE__{
          vasp_id: String.t() | nil,
          vas_id: String.t() | nil,
          sender_address: Address.t() | nil
        }

  defstruct vasp_id: nil, vas_id: nil, sender_address: nil
end

defmodule MM7Core.Messages.Status do
  @type t :: %__MODULE__{
          status_code: pos_integer() | nil,
          status_text: String.t() | nil,
          details: String.t() | nil
        }

  defstruct status_code: nil, status_text: nil, details: nil
end

defmodule MM7Core.Messages.SubmitReq do
  alias MM7Core.Messages.Recipients
  alias MM7Core.Messages.SenderIdentification

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          sender_identification: SenderIdentification.t() | nil,
          recipients: Recipients.t() | nil,
          service_code: String.t() | nil,
          linked_id: String.t() | nil,
          message_class: String.t() | nil,
          time_stamp: String.t() | nil,
          delivery_report: boolean() | nil,
          read_reply: boolean() | nil,
          priority: String.t() | nil,
          subject: String.t() | nil,
          applic_id: String.t() | nil,
          reply_applic_id: String.t() | nil,
          aux_applic_info: String.t() | nil
        }

  defstruct mm7_version: nil,
            sender_identification: nil,
            recipients: nil,
            service_code: nil,
            linked_id: nil,
            message_class: nil,
            time_stamp: nil,
            delivery_report: nil,
            read_reply: nil,
            priority: nil,
            subject: nil,
            applic_id: nil,
            reply_applic_id: nil,
            aux_applic_info: nil
end

defmodule MM7Core.Messages.SubmitRsp do
  alias MM7Core.Messages.Status

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          status: Status.t() | nil,
          message_id: String.t() | nil
        }

  defstruct mm7_version: nil, status: nil, message_id: nil
end

defmodule MM7Core.Messages.DeliverReq do
  alias MM7Core.Messages.Address
  alias MM7Core.Messages.Recipients

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          mms_relay_server_id: String.t() | nil,
          vasp_id: String.t() | nil,
          vas_id: String.t() | nil,
          linked_id: String.t() | nil,
          sender: Address.t() | nil,
          recipients: Recipients.t() | nil,
          time_stamp: String.t() | nil,
          priority: String.t() | nil,
          subject: String.t() | nil,
          applic_id: String.t() | nil,
          reply_applic_id: String.t() | nil,
          aux_applic_info: String.t() | nil
        }

  defstruct mm7_version: nil,
            mms_relay_server_id: nil,
            vasp_id: nil,
            vas_id: nil,
            linked_id: nil,
            sender: nil,
            recipients: nil,
            time_stamp: nil,
            priority: nil,
            subject: nil,
            applic_id: nil,
            reply_applic_id: nil,
            aux_applic_info: nil
end

defmodule MM7Core.Messages.DeliverRsp do
  alias MM7Core.Messages.Status

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          status: Status.t() | nil,
          service_code: String.t() | nil
        }

  defstruct mm7_version: nil, status: nil, service_code: nil
end
