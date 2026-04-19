# frozen_string_literal: true

require "test_helper"

class TestMessage < Minitest::Test
  INVITE = <<~SIP.gsub("\n", "\r\n")
    INVITE sip:bob@biloxi.example.com SIP/2.0
    Via: SIP/2.0/UDP pc33.atlanta.example.com;branch=z9hG4bK776asdhds
    Max-Forwards: 70
    To: Bob <sip:bob@biloxi.example.com>
    From: Alice <sip:alice@atlanta.example.com>;tag=1928301774
    Call-ID: a84b4c76e66710
    CSeq: 314159 INVITE
    Contact: <sip:alice@pc33.atlanta.example.com>
    Content-Length: 0

  SIP

  def test_parse_invite
    h = TsipParser::Message.parse(INVITE)
    assert_equal :request, h[:kind]
    assert_equal "INVITE", h[:method]
    assert_equal "sip:bob@biloxi.example.com", h[:request_uri]
    assert_equal "SIP/2.0", h[:sip_version]
    assert_equal "70", h[:headers]["Max-Forwards"].first
    assert_equal ["a84b4c76e66710"], h[:headers]["Call-ID"]
    assert_equal Encoding::ASCII_8BIT, h[:body].encoding
    assert_equal "".b, h[:body]
  end

  def test_parse_response_with_reason_phrase
    raw = "SIP/2.0 404 Not Found\r\nCall-ID: x\r\n\r\n"
    h = TsipParser::Message.parse(raw)
    assert_equal :response, h[:kind]
    assert_equal 404, h[:status_code]
    assert_equal "Not Found", h[:reason_phrase]
  end

  def test_compact_form_canonicalised
    raw = "INVITE sip:x@h SIP/2.0\r\nv: SIP/2.0/UDP h;branch=z\r\ni: abc\r\nl: 0\r\n\r\n"
    h = TsipParser::Message.parse(raw)
    assert h[:headers].key?("Via")
    assert_equal ["abc"], h[:headers]["Call-ID"]
    assert_equal ["0"], h[:headers]["Content-Length"]
  end

  def test_multiple_via_preserves_order
    raw = "INVITE sip:x@h SIP/2.0\r\n" \
          "Via: SIP/2.0/UDP a;branch=1\r\n" \
          "Via: SIP/2.0/UDP b;branch=2\r\n" \
          "Via: SIP/2.0/UDP c;branch=3\r\n" \
          "\r\n"
    vias = TsipParser::Message.parse(raw)[:headers]["Via"]
    assert_equal 3, vias.size
    assert_includes vias[0], "a"
    assert_includes vias[1], "b"
    assert_includes vias[2], "c"
  end

  def test_body_extracted
    raw = "MESSAGE sip:x@h SIP/2.0\r\nContent-Length: 5\r\n\r\nhello"
    h = TsipParser::Message.parse(raw)
    assert_equal "hello".b, h[:body]
  end

  def test_raises_parse_error_on_malformed
    assert_raises(TsipParser::ParseError) do
      TsipParser::Message.parse("not a sip message")
    end
  end

  def test_raises_on_negative_content_length
    raw = "MESSAGE sip:x@h SIP/2.0\r\nContent-Length: -1\r\n\r\n"
    assert_raises(TsipParser::ParseError) do
      TsipParser::Message.parse(raw)
    end
  end
end
