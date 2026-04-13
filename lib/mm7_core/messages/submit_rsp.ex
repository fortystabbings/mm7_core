defmodule MM7Core.Messages.SubmitRsp do
  @moduledoc false

  alias MM7Core.Messages.Status
  alias MM7Core.Messages.Support

  @children ["MM7Version", "Status", "MessageID"]

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          status: Status.t() | nil,
          message_id: String.t() | nil
        }

  defstruct mm7_version: nil, status: nil, message_id: nil

  def from_xml(root) do
    with :ok <- Support.ensure_children(root, @children),
         {:ok, mm7_version} <- Support.required_text(root, "MM7Version"),
         {:ok, status} <- Support.decode_status(root),
         {:ok, message_id} <- Support.optional_text(root, "MessageID") do
      {:ok, %__MODULE__{mm7_version: mm7_version, status: status, message_id: message_id}}
    end
  end

  def to_xml(%__MODULE__{} = struct) do
    with :ok <- validate(struct),
         {:ok, status_xml} <- Support.encode_status(struct.status) do
      {:ok,
       IO.iodata_to_binary([
         Support.open_root("SubmitRsp"),
         Support.tag("MM7Version", struct.mm7_version),
         status_xml,
         Support.maybe_tag("MessageID", struct.message_id),
         Support.close_root("SubmitRsp")
       ])}
    end
  end

  def validate(%__MODULE__{} = struct) do
    missing =
      []
      |> Support.maybe_missing_string(struct.mm7_version, "mm7_version")
      |> Support.maybe_missing_status_code(struct.status)

    with :ok <- Support.validate_exact_struct_keys(struct),
         :ok <- Support.validate_string_fields(struct, [:message_id]),
         :ok <- Support.validate_status(struct.status),
         :ok <- Support.missing_or_ok(__MODULE__, missing) do
      :ok
    end
  end

  def validate(_value), do: Support.error(:invalid_struct, "invalid struct")
end
