defmodule MM7CoreTest do
  use ExUnit.Case, async: true

  @ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  test "decodes SubmitReq xml to normalized map" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification>
        <VASPID>acme</VASPID>
      </SenderIdentification>
      <Recipients>
        <To><Number>79001234567</Number></To>
      </Recipients>
      <Subject>Promo</Subject>
    </SubmitReq>
    """

    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_submit_req"
    assert out["mm7_version"] == "6.8.0"
    assert out["sender_identification"]["vasp_id"] == "acme"
    assert hd(out["recipients"]["to"])["value"] == "79001234567"
    assert out["subject"] == "Promo"
  end

  test "decodes SubmitRsp xml to normalized map" do
    xml = """
    <SubmitRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusCode>1000</StatusCode>
        <StatusText>Success</StatusText>
      </Status>
      <MessageID>m-1</MessageID>
    </SubmitRsp>
    """

    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_submit_res"
    assert out["status"]["status_code"] == 1000
    assert out["status"]["status_text"] == "Success"
    assert out["message_id"] == "m-1"
  end

  test "decodes DeliverReq xml to normalized map" do
    xml = """
    <DeliverReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <LinkedID>req-1</LinkedID>
      <Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>
      <Subject>Reminder</Subject>
    </DeliverReq>
    """

    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_deliver_req"
    assert out["sender"]["kind"] == "rfc2822_address"
    assert out["sender"]["value"] == "sender@example.test"
    assert out["linked_id"] == "req-1"
  end

  test "decodes DeliverRsp xml to normalized map" do
    xml = """
    <DeliverRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusCode>2001</StatusCode>
        <StatusText>Operation restricted</StatusText>
      </Status>
    </DeliverRsp>
    """

    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_deliver_res"
    assert out["status"]["status_code"] == 2001
  end

  test "encodes SubmitReq map to canonical xml" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "sender_identification" => %{"vasp_id" => "acme"},
      "recipients" => %{"to" => [%{"kind" => "number", "value" => "79001234567"}]},
      "subject" => "Promo"
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SubmitReq"
    assert xml =~ ~s(xmlns="#{@ns}")
    assert xml =~ "<SenderIdentification><VASPID>acme</VASPID></SenderIdentification>"
    assert xml =~ "<Recipients><To><Number>79001234567</Number></To></Recipients>"
  end

  test "encodes SubmitRsp json string to canonical xml" do
    input = """
    {
      "kind": "mm7_submit_res",
      "mm7_version": "6.8.0",
      "status": {"status_code": 1000, "status_text": "Success"},
      "message_id": "m-1"
    }
    """

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SubmitRsp"
    assert xml =~ "<StatusCode>1000</StatusCode>"
    assert xml =~ "<MessageID>m-1</MessageID>"
  end

  test "encodes DeliverReq map to canonical xml" do
    input = %{
      "kind" => "mm7_deliver_req",
      "mm7_version" => "6.8.0",
      "sender" => %{"kind" => "rfc2822_address", "value" => "sender@example.test"},
      "subject" => "Reminder"
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<DeliverReq"
    assert xml =~ "<Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>"
    assert xml =~ "<Subject>Reminder</Subject>"
  end

  test "encodes DeliverRsp map to canonical xml" do
    input = %{
      "kind" => "mm7_deliver_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => 1000, "status_text" => "Success"},
      "service_code" => "svc-01"
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<DeliverRsp"
    assert xml =~ "<StatusCode>1000</StatusCode>"
    assert xml =~ "<ServiceCode>svc-01</ServiceCode>"
  end

  test "rejects xml with unknown root" do
    xml = ~s(<Unknown xmlns="#{@ns}"></Unknown>)
    assert {:error, %{code: :unknown_xml_root}} = MM7Core.convert(xml)
  end

  test "rejects xml with wrong namespace" do
    xml = """
    <SubmitReq xmlns="http://wrong.example/ns">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "rejects soap envelope in stage 1" do
    xml = """
    <env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
      <env:Body></env:Body>
    </env:Envelope>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "soap_envelope"}}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid xml" do
    assert {:error, %{code: :invalid_xml}} = MM7Core.convert("<SubmitReq")
  end

  test "rejects xml with multiple root elements" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    <DeliverRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status><StatusCode>1000</StatusCode></Status>
    </DeliverRsp>
    """

    assert {:error, %{code: :invalid_xml}} = MM7Core.convert(xml)
  end

  test "rejects duplicate optional xml child elements" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <Subject>One</Subject>
      <Subject>Two</Subject>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Subject"}}} =
             MM7Core.convert(xml)
  end

  test "rejects out-of-order status fields in xml" do
    xml = """
    <SubmitRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusText>Success</StatusText>
        <StatusCode>1000</StatusCode>
      </Status>
      <MessageID>m-1</MessageID>
    </SubmitRsp>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "rejects nested content in simple xml leaf element" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients>
        <To><Number><Extra>79001234567</Extra></Number></To>
      </Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Number"}}} =
             MM7Core.convert(xml)
  end

  test "rejects empty recipient address in xml" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number></Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Number"}}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid json" do
    assert {:error, %{code: :invalid_json}} = MM7Core.convert("{bad json")
  end

  test "rejects missing kind in map" do
    assert {:error, %{code: :missing_kind}} = MM7Core.convert(%{"mm7_version" => "6.8.0"})
  end

  test "rejects unsupported binary input" do
    assert {:error, %{code: :unsupported_input_format}} = MM7Core.convert("not xml or json")
  end

  test "rejects mime xml payload explicitly" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <Content href="cid:part-1"/>
    </SubmitReq>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "mime"}}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid boolean value in xml" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <DeliveryReport>maybe</DeliveryReport>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{field: "delivery_report"}}} =
             MM7Core.convert(xml)
  end

  test "rejects duplicate optional xml field instead of dropping it" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <Subject>Promo 1</Subject>
      <Subject>Promo 2</Subject>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Subject"}}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid address attribute boolean in xml" do
    xml = """
    <DeliverReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Sender><Number displayOnly="maybe">79001234567</Number></Sender>
    </DeliverReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{field: "displayOnly"}}} =
             MM7Core.convert(xml)
  end

  test "rejects mime map payload explicitly" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "recipients" => %{"to" => [%{"kind" => "number", "value" => "79001234567"}]},
      "content" => %{"href" => "cid:part-1"}
    }

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "mime"}}} =
             MM7Core.convert(input)
  end

  test "rejects invalid boolean value in map" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "recipients" => %{"to" => [%{"kind" => "number", "value" => "79001234567"}]},
      "delivery_report" => "true"
    }

    assert {:error, %{code: :invalid_structure, details: %{field: "delivery_report"}}} =
             MM7Core.convert(input)
  end

  test "rejects non-string optional map field instead of coercing it" do
    input = %{
      "kind" => "mm7_submit_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => 1000},
      "message_id" => 12
    }

    assert {:error, %{code: :invalid_structure, details: %{field: "message_id"}}} =
             MM7Core.convert(input)
  end

  test "rejects invalid address coding in normalized map" do
    input = %{
      "kind" => "mm7_deliver_req",
      "mm7_version" => "6.8.0",
      "sender" => %{
        "kind" => "number",
        "value" => "79001234567",
        "address_coding" => "plain"
      }
    }

    assert {:error, %{code: :invalid_structure, details: %{field: "address_coding"}}} =
             MM7Core.convert(input)
  end

  test "validates mandatory submit req recipients" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "sender_identification" => %{"vasp_id" => "acme"}
    }

    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "validates mandatory submit res status code" do
    input = %{"kind" => "mm7_submit_res", "mm7_version" => "6.8.0", "status" => %{}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "validates mandatory deliver req sender" do
    input = %{"kind" => "mm7_deliver_req", "mm7_version" => "6.8.0"}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "validates mandatory deliver res status code" do
    input = %{"kind" => "mm7_deliver_res", "mm7_version" => "6.8.0", "status" => %{}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "returns structured error for invalid status code on encode" do
    input = %{
      "kind" => "mm7_submit_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => "bad"}
    }

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(input)
  end

  test "roundtrips submit request key fields" do
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

  test "roundtrips submit request without sender_identification as omitted field" do
    input = %{
      "kind" => "mm7_submit_req",
      "mm7_version" => "6.8.0",
      "recipients" => %{"to" => [%{"kind" => "number", "value" => "79001234567"}]}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SenderIdentification/>"
    assert {:ok, out} = MM7Core.convert(xml)
    refute Map.has_key?(out, "sender_identification")
  end

  test "roundtrips deliver response key fields" do
    input = %{
      "kind" => "mm7_deliver_res",
      "mm7_version" => "6.8.0",
      "status" => %{"status_code" => 2000, "status_text" => "Client error"}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert {:ok, out} = MM7Core.convert(xml)
    assert out["kind"] == "mm7_deliver_res"
    assert out["status"]["status_code"] == 2000
  end
end
