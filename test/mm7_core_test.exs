defmodule MM7CoreTest do
  use ExUnit.Case, async: true

  @ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  test "detects SubmitReq root and decodes xml to map" do
    xml = """
    <SubmitReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification><VASPID>acme</VASPID></SenderIdentification>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded["kind"] == "mm7_submit_req"
    assert decoded["mm7_version"] == "6.8.0"
    assert decoded["recipients"]["to"] != []
  end

  test "detects SubmitRsp root and decodes status" do
    xml = """
    <SubmitRsp xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status>
      <MessageID>id-1</MessageID>
    </SubmitRsp>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded["kind"] == "mm7_submit_res"
    assert decoded["status"]["status_code"] == 1000
    assert decoded["message_id"] == "id-1"
  end

  test "detects DeliverReq root and decodes sender" do
    xml = """
    <DeliverReq xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <Sender><RFC2822Address>a@b.c</RFC2822Address></Sender>
    </DeliverReq>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded["kind"] == "mm7_deliver_req"
    assert decoded["sender"]["kind"] == "rfc2822_address"
  end

  test "detects DeliverRsp root and decodes status" do
    xml = """
    <DeliverRsp xmlns=\"#{@ns}\">
      <MM7Version>6.8.0</MM7Version>
      <Status><StatusCode>2001</StatusCode><StatusText>Temporary</StatusText></Status>
    </DeliverRsp>
    """

    assert {:ok, decoded} = MM7Core.convert(xml)
    assert decoded["kind"] == "mm7_deliver_res"
    assert decoded["status"]["status_code"] == 2001
  end

  test "encodes submit req map to canonical xml" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "sender_identification" => %{"vasp_id" => "acme"},
      "recipients" => %{"to" => [%{"kind" => "number", "value" => "79001234567"}]}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SubmitReq"
    assert xml =~ ~s(xmlns=\"#{@ns}\")
    assert xml =~ "<MM7Version>6.8.0</MM7Version>"
  end

  test "encodes submit res map to canonical xml" do
    input = %{
      "kind" => "mm7_submit_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => 1000, "status_text" => "Success"},
      "message_id" => "m-1"
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SubmitRsp"
    assert xml =~ "<StatusCode>1000</StatusCode>"
    assert xml =~ "<MessageID>m-1</MessageID>"
  end

  test "encodes deliver req map to canonical xml" do
    input = %{
      "kind" => "mm7_deliver_req",
      "mm7_version" => "6.8.0",
      "sender" => %{"kind" => "rfc2822_address", "value" => "sender@acme.test"}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<DeliverReq"
    assert xml =~ "<Sender><RFC2822Address>sender@acme.test</RFC2822Address></Sender>"
  end

  test "encodes deliver rsp map to canonical xml" do
    input = %{
      "kind" => "mm7_deliver_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => 1000, "status_text" => "Success"}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<DeliverRsp"
    assert xml =~ "<StatusCode>1000</StatusCode>"
  end

  test "rejects xml with unknown root" do
    xml = ~s(<Unknown xmlns=\"#{@ns}\"></Unknown>)
    assert {:error, %{code: :unknown_xml_root}} = MM7Core.convert(xml)
  end

  test "rejects xml with wrong namespace" do
    xml = """
    <SubmitReq xmlns=\"http://wrong.example/ns\">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification></SenderIdentification>
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "rejects soap envelope in stage-1" do
    xml = """
    <env:Envelope xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\">
      <env:Body></env:Body>
    </env:Envelope>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "soap_envelope"}}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid xml" do
    assert {:error, %{code: :invalid_xml}} = MM7Core.convert("<SubmitReq")
  end

  test "rejects invalid json string" do
    assert {:error, %{code: :invalid_json}} = MM7Core.convert("{bad json")
  end

  test "rejects non xml binary input" do
    assert {:error, %{code: :unsupported_input_format}} = MM7Core.convert("binary-data")
  end

  test "rejects missing kind" do
    assert {:error, %{code: :missing_kind}} = MM7Core.convert(%{"mm7_version" => "6.8.0"})
  end

  test "rejects unknown kind" do
    assert {:error, %{code: :unknown_kind}} =
             MM7Core.convert(%{"kind" => "x", "mm7_version" => "6.8.0"})
  end

  test "mandatory validation for submit req recipients" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "sender_identification" => %{}
    }

    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "mandatory validation for submit res status code" do
    input = %{"kind" => "mm7_submit_res", "mm7_version" => "6.8.0", "status" => %{}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "mandatory validation for deliver req sender" do
    input = %{"kind" => "mm7_deliver_req", "mm7_version" => "6.8.0"}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "mandatory validation for deliver res status code" do
    input = %{"kind" => "mm7_deliver_res", "mm7_version" => "6.8.0", "status" => %{}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "roundtrip submit req keeps key fields" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "sender_identification" => %{"vasp_id" => "acme"},
      "recipients" => %{"to" => [%{"kind" => "number", "value" => "79001234567"}]}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_submit_req"
    assert out["mm7_version"] == "6.8.0"
    assert hd(out["recipients"]["to"])["value"] == "79001234567"
  end

  test "roundtrip deliver res keeps status code" do
    input = %{
      "kind" => "mm7_deliver_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => 2000, "status_text" => "OK"}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_deliver_res"
    assert out["status"]["status_code"] == 2000
  end
end
