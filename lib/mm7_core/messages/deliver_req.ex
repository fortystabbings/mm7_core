defmodule MM7Core.Messages.DeliverReq do
  @moduledoc false

  alias MM7Core.Messages.Support

  @children [
    "MM7Version",
    "MMSRelayServerID",
    "VASPID",
    "VASID",
    "LinkedID",
    "Sender",
    "Recipients",
    "TimeStamp",
    "Priority",
    "Subject",
    "ApplicID",
    "ReplyApplicID",
    "AuxApplicInfo"
  ]

  @optional_fields [
    {:text, :mms_relay_server_id, "MMSRelayServerID"},
    {:text, :vasp_id, "VASPID"},
    {:text, :vas_id, "VASID"},
    {:text, :linked_id, "LinkedID"},
    {:text, :time_stamp, "TimeStamp"},
    {:text, :priority, "Priority"},
    {:text, :subject, "Subject"},
    {:text, :applic_id, "ApplicID"},
    {:text, :reply_applic_id, "ReplyApplicID"},
    {:text, :aux_applic_info, "AuxApplicInfo"}
  ]

  @text_fields for {:text, field, _element} <- @optional_fields, do: field

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          mms_relay_server_id: String.t() | nil,
          vasp_id: String.t() | nil,
          vas_id: String.t() | nil,
          linked_id: String.t() | nil,
          sender: MM7Core.Messages.Address.t() | nil,
          recipients: MM7Core.Messages.Recipients.t() | nil,
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

  @spec from_xml(Support.xml_node()) :: Support.result(t())
  def from_xml(root) do
    with :ok <- Support.ensure_children(root, @children),
         {:ok, mm7_version} <- Support.required_text(root, "MM7Version"),
         {:ok, sender} <- Support.required_address(root, "Sender"),
         {:ok, recipients} <- Support.optional_recipients(root),
         {:ok, optional_fields} <- Support.collect_optional_fields(root, @optional_fields) do
      {:ok,
       struct(
         __MODULE__,
         optional_fields
         |> Map.put(:mm7_version, mm7_version)
         |> Map.put(:sender, sender)
         |> Map.put(:recipients, recipients)
       )}
    end
  end

  @spec to_xml(t()) :: Support.result(String.t())
  def to_xml(%__MODULE__{} = struct) do
    with :ok <- validate(struct) do
      {:ok,
       IO.iodata_to_binary([
         Support.open_root("DeliverReq"),
         Support.tag("MM7Version", struct.mm7_version),
         Support.maybe_tag("MMSRelayServerID", struct.mms_relay_server_id),
         Support.maybe_tag("VASPID", struct.vasp_id),
         Support.maybe_tag("VASID", struct.vas_id),
         Support.maybe_tag("LinkedID", struct.linked_id),
         Support.wrap("Sender", Support.encode_address(struct.sender)),
         Support.encode_optional_recipients(struct.recipients),
         Support.maybe_tag("TimeStamp", struct.time_stamp),
         Support.maybe_tag("Priority", struct.priority),
         Support.maybe_tag("Subject", struct.subject),
         Support.maybe_tag("ApplicID", struct.applic_id),
         Support.maybe_tag("ReplyApplicID", struct.reply_applic_id),
         Support.maybe_tag("AuxApplicInfo", struct.aux_applic_info),
         Support.close_root("DeliverReq")
       ])}
    end
  end

  @spec validate(t() | term()) :: :ok | Support.error_result()
  def validate(%__MODULE__{} = struct) do
    missing =
      []
      |> Support.maybe_missing_string(struct.mm7_version, "mm7_version")
      |> Support.maybe_missing_address(struct.sender, "sender")

    with :ok <- Support.validate_exact_struct_keys(struct),
         :ok <- Support.validate_string_fields(struct, @text_fields),
         :ok <- Support.validate_address(struct.sender),
         :ok <- Support.validate_recipients(struct.recipients),
         :ok <- Support.missing_or_ok(__MODULE__, missing) do
      :ok
    end
  end

  def validate(_value), do: Support.error(:invalid_struct, "invalid struct")
end
