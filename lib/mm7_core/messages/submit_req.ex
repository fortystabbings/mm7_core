defmodule MM7Core.Messages.SubmitReq do
  @moduledoc false

  alias MM7Core.Messages.Support

  @children [
    "MM7Version",
    "SenderIdentification",
    "Recipients",
    "ServiceCode",
    "LinkedID",
    "MessageClass",
    "TimeStamp",
    "DeliveryReport",
    "ReadReply",
    "Priority",
    "Subject",
    "ApplicID",
    "ReplyApplicID",
    "AuxApplicInfo"
  ]

  @optional_fields [
    {:text, :service_code, "ServiceCode"},
    {:text, :linked_id, "LinkedID"},
    {:text, :message_class, "MessageClass"},
    {:text, :time_stamp, "TimeStamp"},
    {:bool, :delivery_report, "DeliveryReport"},
    {:bool, :read_reply, "ReadReply"},
    {:text, :priority, "Priority"},
    {:text, :subject, "Subject"},
    {:text, :applic_id, "ApplicID"},
    {:text, :reply_applic_id, "ReplyApplicID"},
    {:text, :aux_applic_info, "AuxApplicInfo"}
  ]

  @text_fields for {:text, field, _element} <- @optional_fields, do: field
  @bool_fields for {:bool, field, _element} <- @optional_fields, do: field

  @type t :: %__MODULE__{
          mm7_version: String.t() | nil,
          sender_identification: MM7Core.Messages.SenderIdentification.t() | nil,
          recipients: MM7Core.Messages.Recipients.t() | nil,
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

  @spec from_xml(Support.xml_node()) :: Support.result(t())
  def from_xml(root) do
    with :ok <- Support.ensure_children(root, @children),
         {:ok, mm7_version} <- Support.required_text(root, "MM7Version"),
         {:ok, sender_identification} <- Support.required_sender_identification(root),
         {:ok, recipients} <- Support.required_recipients(root),
         {:ok, optional_fields} <- Support.collect_optional_fields(root, @optional_fields) do
      {:ok,
       struct(
         __MODULE__,
         optional_fields
         |> Map.put(:mm7_version, mm7_version)
         |> Map.put(:sender_identification, sender_identification)
         |> Map.put(:recipients, recipients)
       )}
    end
  end

  @spec to_xml(t()) :: Support.result(String.t())
  def to_xml(%__MODULE__{} = struct) do
    with :ok <- validate(struct) do
      {:ok,
       IO.iodata_to_binary([
         Support.open_root("SubmitReq"),
         Support.tag("MM7Version", struct.mm7_version),
         Support.encode_sender_identification(struct.sender_identification),
         Support.encode_recipients(struct.recipients),
         Support.maybe_tag("ServiceCode", struct.service_code),
         Support.maybe_tag("LinkedID", struct.linked_id),
         Support.maybe_tag("MessageClass", struct.message_class),
         Support.maybe_tag("TimeStamp", struct.time_stamp),
         Support.maybe_tag("DeliveryReport", Support.bool_to_text(struct.delivery_report)),
         Support.maybe_tag("ReadReply", Support.bool_to_text(struct.read_reply)),
         Support.maybe_tag("Priority", struct.priority),
         Support.maybe_tag("Subject", struct.subject),
         Support.maybe_tag("ApplicID", struct.applic_id),
         Support.maybe_tag("ReplyApplicID", struct.reply_applic_id),
         Support.maybe_tag("AuxApplicInfo", struct.aux_applic_info),
         Support.close_root("SubmitReq")
       ])}
    end
  end

  @spec validate(t() | term()) :: :ok | Support.error_result()
  def validate(%__MODULE__{} = struct) do
    missing =
      []
      |> Support.maybe_missing_string(struct.mm7_version, "mm7_version")
      |> Support.maybe_missing_recipients(struct.recipients)

    with :ok <- Support.validate_exact_struct_keys(struct),
         :ok <- Support.validate_string_fields(struct, @text_fields),
         :ok <- Support.validate_boolean_fields(struct, @bool_fields),
         :ok <- Support.validate_sender_identification(struct.sender_identification),
         :ok <- Support.validate_recipients(struct.recipients),
         :ok <- Support.missing_or_ok(__MODULE__, missing) do
      :ok
    end
  end

  def validate(_value), do: Support.error(:invalid_struct, "invalid struct")
end
