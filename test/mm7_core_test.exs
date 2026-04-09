defmodule MM7CoreTest do
  use ExUnit.Case, async: true

  @ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  test "XML root detection and XML -> map for SubmitReq" do
    xml = """
    <SubmitReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification><VASPID>TNN</VASPID></SenderIdentification>
      <Recipients><To><Number>79261234567</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded.kind == "mm7_submit_req"
    assert decoded.mm7_version == "6.8.0"
    assert decoded.sender_identification.vasp_id == "TNN"
    assert [%{address_kind: "number", value: "79261234567"}] = decoded.recipients.to
  end

  test "XML -> map for SubmitRsp" do
    xml = """
    <SubmitRsp xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status>
      <MessageID>041502073667</MessageID>
    </SubmitRsp>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded.kind == "mm7_submit_res"
    assert decoded.status.status_code == 1000
    assert decoded.message_id == "041502073667"
  end

  test "XML -> map for DeliverReq" do
    xml = """
    <DeliverReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <Sender><RFC2822Address>sender@example.com</RFC2822Address></Sender>
      <Subject>Weather</Subject>
    </DeliverReq>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded.kind == "mm7_deliver_req"
    assert decoded.sender.address_kind == "rfc2822_address"
    assert decoded.subject == "Weather"
  end

  test "XML -> map for DeliverRsp" do
    xml = """
    <DeliverRsp xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status>
    </DeliverRsp>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded.kind == "mm7_deliver_res"
    assert decoded.status.status_code == 1000
  end

  test "JSON string -> XML for SubmitRsp" do
    json =
      ~s({"kind":"mm7_submit_res","mm7_version":"6.8.0","status":{"status_code":1000,"status_text":"Success"},"message_id":"041502073667"})

    assert {:ok, xml} = MM7Core.convert(json)
    assert xml =~ "<SubmitRsp xmlns=\"#{@ns}\">"
    assert xml =~ "<MM7Version>6.8.0</MM7Version>"
    assert xml =~ "<StatusCode>1000</StatusCode>"
    assert xml =~ "<MessageID>041502073667</MessageID>"
  end

  test "map -> XML -> map round-trip for DeliverReq" do
    payload = %{
      kind: "mm7_deliver_req",
      mm7_version: "6.8.0",
      mms_relay_server_id: "relay-1",
      sender: %{address_kind: "rfc2822_address", value: "sender@example.com"},
      subject: "Weather",
      recipients: %{to: [%{address_kind: "number", value: "79261230000"}]}
    }

    assert {:ok, xml} = MM7Core.convert(payload)
    assert xml =~ "<DeliverReq xmlns=\"#{@ns}\">"

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded.kind == "mm7_deliver_req"
    assert decoded.mm7_version == "6.8.0"
    assert decoded.sender.address_kind == "rfc2822_address"
    assert decoded.subject == "Weather"
    assert hd(decoded.recipients.to).value == "79261230000"
  end

  test "boolean false values are preserved in XML encoding" do
    payload = %{
      kind: "mm7_submit_req",
      mm7_version: "6.8.0",
      recipients: %{to: [%{address_kind: "number", value: "79000000000"}]},
      delivery_report: false
    }

    assert {:ok, xml} = MM7Core.convert(payload)
    assert xml =~ "<DeliveryReport>false</DeliveryReport>"
  end

  test "unknown XML root returns explicit error" do
    assert {:error, %{code: :unknown_xml_root}} = MM7Core.convert("<Ping/>")
  end

  test "SOAP envelope is rejected as unsupported stage feature" do
    xml = """
    <env:Envelope xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\">
      <env:Body />
    </env:Envelope>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: :soap_envelope}}} =
             MM7Core.convert(xml)
  end

  test "MIME-like input is rejected as unsupported stage feature" do
    mime = "Content-Type: multipart/related; boundary=abc\n--abc\n"

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: :mime}}} =
             MM7Core.convert(mime)
  end

  test "empty payload returns unsupported_input_format" do
    assert {:error, %{code: :unsupported_input_format}} = MM7Core.convert("  ")
  end

  test "plain text payload returns unsupported_input_format" do
    assert {:error, %{code: :unsupported_input_format}} = MM7Core.convert("not xml and not json")
  end

  test "invalid XML returns invalid_xml" do
    assert {:error, %{code: :invalid_xml}} = MM7Core.convert("<SubmitReq")
  end

  test "DTD XML returns invalid_xml" do
    xml = "<!DOCTYPE a [<!ENTITY x SYSTEM 'x'>]><SubmitReq/>"
    assert {:error, %{code: :invalid_xml}} = MM7Core.convert(xml)
  end

  test "invalid JSON returns invalid_json" do
    assert {:error, %{code: :invalid_json}} = MM7Core.convert("{not-json}")
  end

  test "missing kind in map returns missing_kind" do
    assert {:error, %{code: :missing_kind}} = MM7Core.convert(%{"mm7_version" => "6.8.0"})
  end

  test "unknown kind in map returns unknown_kind" do
    assert {:error, %{code: :unknown_kind}} = MM7Core.convert(%{"kind" => "mm7_ping"})
  end

  test "mandatory validation for submit_req requires recipients" do
    payload = %{"kind" => "mm7_submit_req", "mm7_version" => "6.8.0"}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(payload)
  end

  test "mandatory validation for submit_res requires status_code" do
    payload = %{"kind" => "mm7_submit_res", "mm7_version" => "6.8.0", "status" => %{}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(payload)
  end

  test "mandatory validation for deliver_req requires sender" do
    payload = %{"kind" => "mm7_deliver_req", "mm7_version" => "6.8.0"}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(payload)
  end

  test "mandatory validation for deliver_res requires status_code" do
    payload = %{"kind" => "mm7_deliver_res", "mm7_version" => "6.8.0", "status" => %{}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(payload)
  end

  test "status_code must be positive integer in map input" do
    payload = %{
      kind: "mm7_deliver_res",
      mm7_version: "6.8.0",
      status: %{status_code: 0, status_text: "Bad"}
    }

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(payload)
  end

  test "invalid boolean value in XML is rejected" do
    xml = """
    <SubmitReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification />
      <Recipients><To><Number>1</Number></To></Recipients>
      <DeliveryReport>yes</DeliveryReport>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "invalid address_coding value in XML is rejected" do
    xml = """
    <SubmitReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification />
      <Recipients><To><Number addressCoding=\"broken\">1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "delivery_condition.dc must be positive integer in XML" do
    xml = """
    <SubmitReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification />
      <Recipients><To><Number>1</Number></To></Recipients>
      <DeliveryCondition><DC>0</DC></DeliveryCondition>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "canonical namespace mismatch is rejected" do
    xml = """
    <SubmitReq xmlns=\"http://example.com/mm7\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification />
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "presence of unsupported stage keys in map is rejected regardless of value type" do
    payload = %{
      kind: "mm7_deliver_res",
      mm7_version: "6.8.0",
      soap_header: %{},
      status: %{status_code: 1000, status_text: "Success"}
    }

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: :soap_header}}} =
             MM7Core.convert(payload)
  end
end
