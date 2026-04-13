defmodule MM7Core.Messages.DeliverRsp do
  alias MM7Core.Messages.Status
  alias MM7Core.Messages.Support

  @moduledoc false

  @children ["MM7Version", "Status", "ServiceCode"]

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          status: Status.t() | nil,
          service_code: String.t() | nil
        }

  defstruct mm7_version: nil, status: nil, service_code: nil

  def from_xml(root) do
    with :ok <- Support.ensure_children(root, @children),
         {:ok, mm7_version} <- Support.required_text(root, "MM7Version"),
         {:ok, status} <- Support.decode_status(root),
         {:ok, service_code} <- Support.optional_text(root, "ServiceCode") do
      {:ok, %__MODULE__{mm7_version: mm7_version, status: status, service_code: service_code}}
    end
  end

  def to_xml(%__MODULE__{} = struct) do
    with :ok <- validate(struct),
         {:ok, status_xml} <- Support.encode_status(struct.status) do
      {:ok,
       IO.iodata_to_binary([
         Support.open_root("DeliverRsp"),
         Support.tag("MM7Version", struct.mm7_version),
         status_xml,
         Support.maybe_tag("ServiceCode", struct.service_code),
         Support.close_root("DeliverRsp")
       ])}
    end
  end

  def validate(%__MODULE__{} = struct) do
    missing =
      []
      |> Support.maybe_missing_string(struct.mm7_version, "mm7_version")
      |> Support.maybe_missing_status_code(struct.status)

    with :ok <- Support.validate_exact_struct_keys(struct),
         :ok <- Support.validate_string_fields(struct, [:service_code]),
         :ok <- Support.validate_status(struct.status),
         :ok <- Support.missing_or_ok(__MODULE__, missing) do
      :ok
    end
  end
end
