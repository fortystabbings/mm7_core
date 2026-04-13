defmodule MM7CoreTest do
  use ExUnit.Case, async: true

  alias MM7Core.Messages.Address
  alias MM7Core.Messages.DeliverReq
  alias MM7Core.Messages.DeliverRsp
  alias MM7Core.Messages.Recipients
  alias MM7Core.Messages.SenderIdentification
  alias MM7Core.Messages.Status
  alias MM7Core.Messages.SubmitReq
  alias MM7Core.Messages.SubmitRsp

  @ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  test "decodes SubmitReq xml to typed struct" do
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
    assert is_struct(out, SubmitReq)
    assert out.__struct__ == SubmitReq
    assert out.mm7_version == "6.8.0"
    assert is_struct(out.sender_identification, SenderIdentification)
    assert out.sender_identification.vasp_id == "acme"
    assert is_struct(out.recipients, Recipients)
    assert [%Address{kind: :number, value: "79001234567"}] = out.recipients.to
    assert out.subject == "Promo"
  end

  test "decodes SubmitRsp xml to typed struct" do
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
    assert is_struct(out, SubmitRsp)
    assert out.__struct__ == SubmitRsp
    assert out.mm7_version == "6.8.0"
    assert is_struct(out.status, Status)
    assert out.status.status_code == 1000
    assert out.status.status_text == "Success"
    assert out.message_id == "m-1"
  end

  test "decodes DeliverReq xml to typed struct" do
    xml = """
    <DeliverReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <LinkedID>req-1</LinkedID>
      <Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>
      <Subject>Reminder</Subject>
    </DeliverReq>
    """

    assert {:ok, out} = MM7Core.convert(xml)
    assert is_struct(out, DeliverReq)
    assert out.__struct__ == DeliverReq
    assert out.mm7_version == "6.8.0"
    assert out.linked_id == "req-1"
    assert %Address{kind: :rfc2822_address, value: "sender@example.test"} = out.sender
    assert out.subject == "Reminder"
  end

  test "decodes DeliverRsp xml to typed struct" do
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
    assert is_struct(out, DeliverRsp)
    assert out.__struct__ == DeliverRsp
    assert out.mm7_version == "6.8.0"
    assert is_struct(out.status, Status)
    assert out.status.status_code == 2001
    assert out.status.status_text == "Operation restricted"
  end

  test "encodes SubmitReq struct to canonical xml" do
    input =
      struct(SubmitReq,
        mm7_version: "6.8.0",
        sender_identification: struct(SenderIdentification, vasp_id: "acme"),
        recipients:
          struct(Recipients,
            to: [struct(Address, kind: :number, value: "79001234567")],
            cc: [struct(Address, kind: :rfc2822_address, value: "ops@example.net")],
            bcc: []
          ),
        subject: "Promo"
      )

    assert {:ok, xml} = MM7Core.convert(input)

    assert xml ==
             "<SubmitReq xmlns=\"#{@ns}\"><MM7Version>6.8.0</MM7Version><SenderIdentification><VASPID>acme</VASPID></SenderIdentification><Recipients><To><Number>79001234567</Number></To><Cc><RFC2822Address>ops@example.net</RFC2822Address></Cc></Recipients><Subject>Promo</Subject></SubmitReq>"
  end

  test "encodes empty SenderIdentification container when submit req omits it" do
    input =
      struct(SubmitReq,
        mm7_version: "6.8.0",
        recipients: struct(Recipients, to: [struct(Address, kind: :number, value: "79001234567")])
      )

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SenderIdentification/>"
  end

  test "encodes SubmitRsp struct to canonical xml" do
    input =
      struct(SubmitRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_code: 1000, status_text: "Success"),
        message_id: "m-1"
      )

    assert {:ok, xml} = MM7Core.convert(input)

    assert xml ==
             "<SubmitRsp xmlns=\"#{@ns}\"><MM7Version>6.8.0</MM7Version><Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status><MessageID>m-1</MessageID></SubmitRsp>"
  end

  test "encodes SubmitRsp without message_id" do
    input =
      struct(SubmitRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_code: 1000, status_text: "Success")
      )

    assert {:ok, xml} = MM7Core.convert(input)
    refute xml =~ "<MessageID>"
  end

  test "encodes DeliverReq struct to canonical xml" do
    input =
      struct(DeliverReq,
        mm7_version: "6.8.0",
        sender: struct(Address, kind: :rfc2822_address, value: "sender@example.test"),
        recipients:
          struct(Recipients,
            to: [struct(Address, kind: :short_code, value: "7255")],
            cc: [],
            bcc: []
          ),
        subject: "Reminder"
      )

    assert {:ok, xml} = MM7Core.convert(input)

    assert xml ==
             "<DeliverReq xmlns=\"#{@ns}\"><MM7Version>6.8.0</MM7Version><Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender><Recipients><To><ShortCode>7255</ShortCode></To></Recipients><Subject>Reminder</Subject></DeliverReq>"
  end

  test "encodes DeliverRsp struct to canonical xml" do
    input =
      struct(DeliverRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_code: 1000, status_text: "Success"),
        service_code: "svc-01"
      )

    assert {:ok, xml} = MM7Core.convert(input)

    assert xml ==
             "<DeliverRsp xmlns=\"#{@ns}\"><MM7Version>6.8.0</MM7Version><Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status><ServiceCode>svc-01</ServiceCode></DeliverRsp>"
  end

  test "synthesizes StatusText when response struct omits it" do
    input =
      struct(DeliverRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_code: 1000)
      )

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<StatusText>Success</StatusText>"
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

  test "rejects descendant element with wrong namespace" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients xmlns="">
        <To><Number>1</Number></To>
      </Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Recipients"}}} =
             MM7Core.convert(xml)
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

  test "rejects soap header in stage 1" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Header>nope</Header>
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "soap_header"}}} =
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
      <SenderIdentification/>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <Subject>One</Subject>
      <Subject>Two</Subject>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Subject"}}} =
             MM7Core.convert(xml)
  end

  test "rejects submit req without SenderIdentification container" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, message: "missing SenderIdentification"}} =
             MM7Core.convert(xml)
  end

  test "rejects AuxApplicID because only AuxApplicInfo is supported" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <AuxApplicID>legacy</AuxApplicID>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{unknown: ["AuxApplicID"]}}} =
             MM7Core.convert(xml)
  end

  test "decodes empty SenderIdentification container as nil" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:ok, %SubmitReq{} = out} = MM7Core.convert(xml)
    assert out.sender_identification == nil
  end

  test "rejects mixed text in complex container" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>junk
      <Recipients><To><Number>79001234567</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "SubmitReq"}}} =
             MM7Core.convert(xml)
  end

  test "accepts reordered status fields in xml because Status is xs:all in XSD" do
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

    assert {:ok, %SubmitRsp{} = out} = MM7Core.convert(xml)
    assert out.status.status_code == 1000
    assert out.status.status_text == "Success"
  end

  test "rejects nested content in simple xml leaf element" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients>
        <To><Number><Extra>79001234567</Extra></Number></To>
      </Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Number"}}} =
             MM7Core.convert(xml)
  end

  test "rejects nested xml inside Status.Details" do
    xml = """
    <DeliverRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusCode>1000</StatusCode>
        <StatusText>Success</StatusText>
        <Details><Extra>nope</Extra></Details>
      </Status>
    </DeliverRsp>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Details"}}} =
             MM7Core.convert(xml)
  end

  test "rejects empty recipient address in xml" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients><To><Number></Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Number"}}} =
             MM7Core.convert(xml)
  end

  test "rejects namespaced address attribute" do
    xml = """
    <DeliverReq xmlns="#{@ns}" xmlns:x="urn:x-test">
      <MM7Version>6.8.0</MM7Version>
      <Sender><Number x:displayOnly="true">79001234567</Number></Sender>
    </DeliverReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{attribute: "displayOnly"}}} =
             MM7Core.convert(xml)
  end

  test "rejects empty recipients container when present" do
    xml = """
    <DeliverReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>
      <Recipients/>
    </DeliverReq>
    """

    assert {:error,
            %{code: :invalid_structure, message: "Recipients must contain at least one address"}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid struct kind" do
    assert {:error, %{code: :unknown_struct_kind}} = MM7Core.convert(%URI{path: "/"})
  end

  test "rejects pseudo-struct with extra keys" do
    input =
      %SubmitReq{
        mm7_version: "6.8.0",
        recipients: %Recipients{to: [%Address{kind: :number, value: "79001234567"}]}
      }
      |> Map.put(:extra, :oops)

    assert {:error, %{code: :invalid_struct, details: %{extra_keys: [:extra]}}} =
             MM7Core.convert(input)
  end

  test "rejects malformed struct input" do
    input =
      struct(SubmitReq,
        mm7_version: "6.8.0",
        recipients: %{to: []}
      )

    assert {:error, %{code: :invalid_struct}} = MM7Core.convert(input)
  end

  test "rejects unsupported input format" do
    assert {:error, %{code: :unsupported_input_format}} = MM7Core.convert(123)
  end

  test "rejects non-xml binary input" do
    assert {:error, %{code: :unsupported_input_format, details: %{format: "non_xml_binary"}}} =
             MM7Core.convert("not xml")
  end

  test "rejects MIME payloads explicitly" do
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

  test "does not treat plain cid text as MIME" do
    xml = """
    <DeliverReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>
      <AuxApplicInfo>cid:reference-only-text</AuxApplicInfo>
    </DeliverReq>
    """

    assert {:ok, %DeliverReq{} = out} = MM7Core.convert(xml)
    assert out.aux_applic_info == "cid:reference-only-text"
  end

  test "rejects invalid boolean value in xml" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <DeliveryReport>maybe</DeliveryReport>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{field: "delivery_report"}}} =
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

  test "roundtrips submit request between xml and struct" do
    xml = """
    <SubmitReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification><VASPID>acme</VASPID></SenderIdentification>
      <Recipients><To><Number>79001234567</Number></To></Recipients>
      <Subject>Promo</Subject>
    </SubmitReq>
    """

    assert {:ok, struct} = MM7Core.convert(xml)
    assert is_struct(struct, SubmitReq)
    assert {:ok, xml_again} = MM7Core.convert(struct)
    assert xml_again =~ "<SubmitReq"
    assert xml_again =~ "<Recipients><To><Number>79001234567</Number></To></Recipients>"
  end

  test "roundtrips deliver response between struct and xml" do
    struct =
      struct(DeliverRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_code: 2001, status_text: "Operation restricted")
      )

    assert {:ok, xml} = MM7Core.convert(struct)
    assert {:ok, out} = MM7Core.convert(xml)
    assert is_struct(out, DeliverRsp)
    assert out.status.status_code == 2001
    assert out.status.status_text == "Operation restricted"
  end

  test "xml templates convert successfully" do
    for file <- Path.wildcard("templates/stage1/xml/*.xml") do
      assert {:ok, out} = file |> File.read!() |> MM7Core.convert(), "failed for #{file}"
      assert is_struct(out)
    end
  end

  test "struct templates convert successfully" do
    for file <- Path.wildcard("templates/stage1/struct/*.exs") do
      {input, _binding} = Code.eval_file(file)
      assert {:ok, out} = MM7Core.convert(input), "failed for #{file}"
      assert is_binary(out)
    end
  end

  test "validates mandatory submit req recipients" do
    input =
      struct(SubmitReq,
        mm7_version: "6.8.0"
      )

    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "validates mandatory submit res status code" do
    input =
      struct(SubmitRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_text: "Success")
      )

    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "validates mandatory deliver req sender" do
    input =
      struct(DeliverReq,
        mm7_version: "6.8.0"
      )

    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "validates mandatory deliver res status code" do
    input =
      struct(DeliverRsp,
        mm7_version: "6.8.0",
        status: struct(Status, status_text: "Success")
      )

    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end
end
