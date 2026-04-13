defmodule MM7Core.TestSupport do
  alias MM7Core.Messages.Address
  alias MM7Core.Messages.DeliverReq
  alias MM7Core.Messages.DeliverRsp
  alias MM7Core.Messages.Recipients
  alias MM7Core.Messages.SenderIdentification
  alias MM7Core.Messages.Status
  alias MM7Core.Messages.SubmitReq
  alias MM7Core.Messages.SubmitRsp

  @ns "http://www.3gpp.org/ftp/Specs/archive/23_series/23.140/schema/REL-6-MM7-1-4"

  def ns, do: @ns

  def submit_req_xml do
    """
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
  end

  def submit_req_struct do
    %SubmitReq{
      mm7_version: "6.8.0",
      sender_identification: %SenderIdentification{vasp_id: "acme"},
      recipients: %Recipients{
        to: [%Address{kind: :number, value: "79001234567"}],
        cc: [%Address{kind: :rfc2822_address, value: "ops@example.net"}],
        bcc: []
      },
      subject: "Promo"
    }
  end

  def submit_rsp_xml do
    """
    <SubmitRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusCode>1000</StatusCode>
        <StatusText>Success</StatusText>
      </Status>
      <MessageID>m-1</MessageID>
    </SubmitRsp>
    """
  end

  def submit_rsp_struct do
    %SubmitRsp{
      mm7_version: "6.8.0",
      status: %Status{status_code: 1000, status_text: "Success"},
      message_id: "m-1"
    }
  end

  def deliver_req_xml do
    """
    <DeliverReq xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <LinkedID>req-1</LinkedID>
      <Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>
      <Subject>Reminder</Subject>
    </DeliverReq>
    """
  end

  def deliver_req_struct do
    %DeliverReq{
      mm7_version: "6.8.0",
      sender: %Address{kind: :rfc2822_address, value: "sender@example.test"},
      recipients: %Recipients{
        to: [%Address{kind: :short_code, value: "7255"}],
        cc: [],
        bcc: []
      },
      subject: "Reminder"
    }
  end

  def deliver_rsp_xml do
    """
    <DeliverRsp xmlns="#{@ns}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusCode>2001</StatusCode>
        <StatusText>Operation restricted</StatusText>
      </Status>
      <ServiceCode>svc-01</ServiceCode>
    </DeliverRsp>
    """
  end

  def deliver_rsp_struct do
    %DeliverRsp{
      mm7_version: "6.8.0",
      status: %Status{status_code: 1000, status_text: "Success"},
      service_code: "svc-01"
    }
  end
end

defmodule MM7CoreRoutingTest do
  use ExUnit.Case, async: true

  alias MM7Core.Messages.DeliverReq
  alias MM7Core.Messages.DeliverRsp
  alias MM7Core.Messages.SubmitReq
  alias MM7Core.Messages.SubmitRsp

  import MM7Core.TestSupport

  test "routes xml roots to message modules by kind" do
    for {xml, module} <- [
          {submit_req_xml(), SubmitReq},
          {submit_rsp_xml(), SubmitRsp},
          {deliver_req_xml(), DeliverReq},
          {deliver_rsp_xml(), DeliverRsp}
        ] do
      assert {:ok, %^module{}} = MM7Core.convert(xml)
    end
  end

  test "routes struct modules to xml roots by kind" do
    for {input, root} <- [
          {submit_req_struct(), "SubmitReq"},
          {submit_rsp_struct(), "SubmitRsp"},
          {deliver_req_struct(), "DeliverReq"},
          {deliver_rsp_struct(), "DeliverRsp"}
        ] do
      assert {:ok, xml} = MM7Core.convert(input)
      assert xml =~ ~s(<#{root} xmlns="#{ns()}">)
    end
  end

  test "rejects xml with unknown root" do
    xml = ~s(<Unknown xmlns="#{ns()}"></Unknown>)
    assert {:error, %{code: :unknown_xml_root}} = MM7Core.convert(xml)
  end

  test "rejects xml with wrong namespace" do
    xml = """
    <SubmitReq xmlns="http://wrong.example/ns">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure}} = MM7Core.convert(xml)
  end

  test "rejects invalid xml" do
    assert {:error, %{code: :invalid_xml}} = MM7Core.convert("<SubmitReq")
  end

  test "rejects multiple root elements" do
    xml = submit_req_xml() <> submit_rsp_xml()
    assert {:error, %{code: :invalid_xml}} = MM7Core.convert(xml)
  end

  test "rejects soap envelope in stage 1" do
    xml = """
    <env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
      <env:Body/>
    </env:Envelope>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "soap_envelope"}}} =
             MM7Core.convert(xml)
  end

  test "rejects soap header in stage 1" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Header>nope</Header>
      <Recipients><To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :unsupported_stage_feature, details: %{feature: "soap_header"}}} =
             MM7Core.convert(xml)
  end

  test "rejects wrong xml structure" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
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

  test "rejects invalid struct input" do
    input = %SubmitReq{mm7_version: "6.8.0", recipients: %{to: []}}
    assert {:error, %{code: :invalid_struct}} = MM7Core.convert(input)
  end

  test "rejects pseudo-struct map with extra keys" do
    input = Map.put(submit_req_struct(), :unexpected, 1)

    assert {:error, %{code: :invalid_struct, details: %{extra_keys: [:unexpected]}}} =
             MM7Core.convert(input)
  end

  test "rejects unsupported struct module" do
    assert {:error, %{code: :unknown_struct_kind}} = MM7Core.convert(%URI{path: "/"})
  end

  test "rejects unsupported input formats" do
    assert {:error, %{code: :unsupported_input_format}} = MM7Core.convert(123)

    assert {:error, %{code: :unsupported_input_format, details: %{format: "non_xml_binary"}}} =
             MM7Core.convert("not xml")
  end

  test "xml templates convert successfully" do
    for file <- Path.wildcard("templates/stage1/xml/*.xml") do
      assert {:ok, %_{} = out} = file |> File.read!() |> MM7Core.convert(), "failed for #{file}"
      assert match?(%{__struct__: _}, out)
    end
  end

  test "struct templates convert successfully" do
    for file <- Path.wildcard("templates/stage1/struct/*.exs") do
      {input, _binding} = Code.eval_file(file)
      assert {:ok, xml} = MM7Core.convert(input), "failed for #{file}"
      assert is_binary(xml)
    end
  end
end

defmodule MM7CoreSubmitReqTest do
  use ExUnit.Case, async: true

  alias MM7Core.Messages.Address
  alias MM7Core.Messages.Recipients
  alias MM7Core.Messages.SubmitReq

  import MM7Core.TestSupport

  test "decodes SubmitReq xml to struct" do
    assert {:ok, %SubmitReq{} = out} = MM7Core.convert(submit_req_xml())
    assert out.mm7_version == "6.8.0"
    assert out.sender_identification.vasp_id == "acme"
    assert [%Address{kind: :number, value: "79001234567"}] = out.recipients.to
    assert out.subject == "Promo"
  end

  test "encodes SubmitReq struct to canonical xml" do
    assert {:ok, xml} = MM7Core.convert(submit_req_struct())

    assert xml ==
             "<SubmitReq xmlns=\"#{ns()}\"><MM7Version>6.8.0</MM7Version><SenderIdentification><VASPID>acme</VASPID></SenderIdentification><Recipients><To><Number>79001234567</Number></To><Cc><RFC2822Address>ops@example.net</RFC2822Address></Cc></Recipients><Subject>Promo</Subject></SubmitReq>"
  end

  test "encodes empty SenderIdentification container when omitted in struct" do
    input = %SubmitReq{
      mm7_version: "6.8.0",
      recipients: %Recipients{to: [%Address{kind: :number, value: "79001234567"}]}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<SenderIdentification/>"
  end

  test "rejects SubmitReq xml without recipients" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, message: "missing Recipients"}} =
             MM7Core.convert(xml)
  end

  test "rejects SubmitReq xml with descendant namespace mismatch" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
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

  test "rejects mixed text inside SubmitReq complex container" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients>oops<To><Number>1</Number></To></Recipients>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{element: "Recipients"}}} =
             MM7Core.convert(xml)
  end

  test "rejects empty present SubmitReq recipients container" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients/>
    </SubmitReq>
    """

    assert {:error,
            %{code: :invalid_structure, message: "Recipients must contain at least one address"}} =
             MM7Core.convert(xml)
  end

  test "rejects invalid xml boolean in SubmitReq" do
    xml = """
    <SubmitReq xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <SenderIdentification/>
      <Recipients><To><Number>1</Number></To></Recipients>
      <DeliveryReport>maybe</DeliveryReport>
    </SubmitReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{field: "delivery_report"}}} =
             MM7Core.convert(xml)
  end

  test "rejects SubmitReq struct without recipients" do
    assert {:error, %{code: :missing_mandatory_fields}} =
             MM7Core.convert(%SubmitReq{mm7_version: "6.8.0"})
  end

  test "roundtrips SubmitReq between xml and struct" do
    assert {:ok, %SubmitReq{} = struct} = MM7Core.convert(submit_req_xml())
    assert {:ok, xml} = MM7Core.convert(struct)
    assert xml =~ "<SubmitReq"
    assert xml =~ "<Recipients><To><Number>79001234567</Number></To></Recipients>"
  end
end

defmodule MM7CoreSubmitRspTest do
  use ExUnit.Case, async: true

  alias MM7Core.Messages.Status
  alias MM7Core.Messages.SubmitRsp

  import MM7Core.TestSupport

  test "decodes SubmitRsp xml to struct" do
    xml = """
    <SubmitRsp xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusText>Success</StatusText>
        <StatusCode>1000</StatusCode>
      </Status>
      <MessageID>m-1</MessageID>
    </SubmitRsp>
    """

    assert {:ok, %SubmitRsp{} = out} = MM7Core.convert(xml)
    assert out.mm7_version == "6.8.0"
    assert out.status.status_code == 1000
    assert out.status.status_text == "Success"
    assert out.message_id == "m-1"
  end

  test "encodes SubmitRsp struct to canonical xml" do
    assert {:ok, xml} = MM7Core.convert(submit_rsp_struct())

    assert xml ==
             "<SubmitRsp xmlns=\"#{ns()}\"><MM7Version>6.8.0</MM7Version><Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status><MessageID>m-1</MessageID></SubmitRsp>"
  end

  test "encodes SubmitRsp without message_id" do
    input = %SubmitRsp{
      mm7_version: "6.8.0",
      status: %Status{status_code: 1000, status_text: "Success"}
    }

    assert {:ok, xml} = MM7Core.convert(input)
    refute xml =~ "<MessageID>"
  end

  test "rejects SubmitRsp struct without mandatory status code" do
    input = %SubmitRsp{mm7_version: "6.8.0", status: %Status{status_text: "Success"}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "synthesizes StatusText for SubmitRsp when omitted in struct" do
    input = %SubmitRsp{mm7_version: "6.8.0", status: %Status{status_code: 1000}}

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<StatusText>Success</StatusText>"
  end

  test "roundtrips SubmitRsp between struct and xml" do
    assert {:ok, xml} = MM7Core.convert(submit_rsp_struct())
    assert {:ok, %SubmitRsp{} = out} = MM7Core.convert(xml)
    assert out.status.status_code == 1000
    assert out.message_id == "m-1"
  end
end

defmodule MM7CoreDeliverReqTest do
  use ExUnit.Case, async: true

  alias MM7Core.Messages.Address
  alias MM7Core.Messages.DeliverReq

  import MM7Core.TestSupport

  test "decodes DeliverReq xml to struct" do
    assert {:ok, %DeliverReq{} = out} = MM7Core.convert(deliver_req_xml())
    assert out.mm7_version == "6.8.0"
    assert out.linked_id == "req-1"
    assert %Address{kind: :rfc2822_address, value: "sender@example.test"} = out.sender
    assert out.subject == "Reminder"
  end

  test "encodes DeliverReq struct to canonical xml" do
    assert {:ok, xml} = MM7Core.convert(deliver_req_struct())

    assert xml ==
             "<DeliverReq xmlns=\"#{ns()}\"><MM7Version>6.8.0</MM7Version><Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender><Recipients><To><ShortCode>7255</ShortCode></To></Recipients><Subject>Reminder</Subject></DeliverReq>"
  end

  test "rejects DeliverReq xml without sender" do
    xml = """
    <DeliverReq xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
    </DeliverReq>
    """

    assert {:error, %{code: :invalid_structure, message: "missing Sender"}} = MM7Core.convert(xml)
  end

  test "rejects namespaced address attribute in DeliverReq" do
    xml = """
    <DeliverReq xmlns="#{ns()}" xmlns:bad="http://bad.example/ns">
      <MM7Version>6.8.0</MM7Version>
      <Sender><RFC2822Address bad:id="x">sender@example.test</RFC2822Address></Sender>
    </DeliverReq>
    """

    assert {:error, %{code: :invalid_structure, details: %{attribute: "id"}}} =
             MM7Core.convert(xml)
  end

  test "rejects DeliverReq struct without sender" do
    assert {:error, %{code: :missing_mandatory_fields}} =
             MM7Core.convert(%DeliverReq{mm7_version: "6.8.0"})
  end

  test "roundtrips DeliverReq between xml and struct" do
    assert {:ok, %DeliverReq{} = struct} = MM7Core.convert(deliver_req_xml())
    assert {:ok, xml} = MM7Core.convert(struct)
    assert xml =~ "<DeliverReq"
    assert xml =~ "<Sender><RFC2822Address>sender@example.test</RFC2822Address></Sender>"
  end
end

defmodule MM7CoreDeliverRspTest do
  use ExUnit.Case, async: true

  alias MM7Core.Messages.DeliverRsp
  alias MM7Core.Messages.Status

  import MM7Core.TestSupport

  test "decodes DeliverRsp xml to struct" do
    xml = """
    <DeliverRsp xmlns="#{ns()}">
      <MM7Version>6.8.0</MM7Version>
      <Status>
        <StatusText>Operation restricted</StatusText>
        <StatusCode>2001</StatusCode>
      </Status>
      <ServiceCode>svc-01</ServiceCode>
    </DeliverRsp>
    """

    assert {:ok, %DeliverRsp{} = out} = MM7Core.convert(xml)
    assert out.mm7_version == "6.8.0"
    assert out.status.status_code == 2001
    assert out.status.status_text == "Operation restricted"
    assert out.service_code == "svc-01"
  end

  test "encodes DeliverRsp struct to canonical xml" do
    assert {:ok, xml} = MM7Core.convert(deliver_rsp_struct())

    assert xml ==
             "<DeliverRsp xmlns=\"#{ns()}\"><MM7Version>6.8.0</MM7Version><Status><StatusCode>1000</StatusCode><StatusText>Success</StatusText></Status><ServiceCode>svc-01</ServiceCode></DeliverRsp>"
  end

  test "rejects DeliverRsp struct without mandatory status code" do
    input = %DeliverRsp{mm7_version: "6.8.0", status: %Status{status_text: "Success"}}
    assert {:error, %{code: :missing_mandatory_fields}} = MM7Core.convert(input)
  end

  test "synthesizes StatusText for DeliverRsp when omitted in struct" do
    input = %DeliverRsp{mm7_version: "6.8.0", status: %Status{status_code: 1000}}

    assert {:ok, xml} = MM7Core.convert(input)
    assert xml =~ "<StatusText>Success</StatusText>"
  end

  test "roundtrips DeliverRsp between struct and xml" do
    assert {:ok, xml} = MM7Core.convert(deliver_rsp_struct())
    assert {:ok, %DeliverRsp{} = out} = MM7Core.convert(xml)
    assert out.status.status_code == 1000
    assert out.service_code == "svc-01"
  end
end
