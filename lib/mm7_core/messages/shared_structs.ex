defmodule MM7Core.Messages.Address do
  @moduledoc false

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
  @moduledoc false

  @type t :: %__MODULE__{
          to: [MM7Core.Messages.Address.t()],
          cc: [MM7Core.Messages.Address.t()],
          bcc: [MM7Core.Messages.Address.t()]
        }

  defstruct to: [], cc: [], bcc: []
end

defmodule MM7Core.Messages.SenderIdentification do
  @moduledoc false

  @type t :: %__MODULE__{
          vasp_id: String.t() | nil,
          vas_id: String.t() | nil,
          sender_address: MM7Core.Messages.Address.t() | nil
        }

  defstruct vasp_id: nil, vas_id: nil, sender_address: nil
end

defmodule MM7Core.Messages.Status do
  @moduledoc false

  @type t :: %__MODULE__{
          status_code: pos_integer() | nil,
          status_text: String.t() | nil,
          details: String.t() | nil
        }

  defstruct status_code: nil, status_text: nil, details: nil
end
