# frozen_string_literal: true

require_relative "test_helper"

# Parity surface lifted from tsip-core's Uri specs plus a subset of
# sip_uri_crate/tests/uri_parity.rs — enough to catch structural regressions
# in the binding layer (ivar round-trip, Hash ordering, port, scheme casing,
# bracketed IPv6, params/headers).
class TestUri < Minitest::Test
  def test_plain_sip
    u = TsipParser::Uri.parse("sip:alice@atlanta.com")
    assert_equal "sip", u.scheme
    assert_equal "alice", u.user
    assert_equal "atlanta.com", u.host
    assert_nil u.port
    assert_empty u.params
    assert_empty u.headers
  end

  def test_sips_scheme
    u = TsipParser::Uri.parse("sips:alice@atlanta.com")
    assert_equal "sips", u.scheme
  end

  def test_tel_scheme
    u = TsipParser::Uri.parse("tel:+15551234567")
    assert_equal "tel", u.scheme
    assert_equal "+15551234567", u.host
  end

  def test_host_port
    u = TsipParser::Uri.parse("sip:alice@atlanta.com:5062")
    assert_equal 5062, u.port
    assert_equal "atlanta.com:5062", u.host_port
  end

  def test_password
    u = TsipParser::Uri.parse("sip:alice:secret@atlanta.com")
    assert_equal "alice", u.user
    assert_equal "secret", u.password
  end

  def test_params_preserved_in_order
    u = TsipParser::Uri.parse("sip:alice@atlanta.com;transport=tcp;lr;maddr=239.1.1.1")
    assert_equal %w[transport lr maddr], u.params.keys
    assert_equal "tcp", u.params["transport"]
    assert_equal "", u.params["lr"]
    assert_equal "239.1.1.1", u.params["maddr"]
    assert_equal "tcp", u.transport
  end

  def test_headers
    u = TsipParser::Uri.parse("sip:alice@atlanta.com?subject=hello&priority=urgent")
    assert_equal "hello", u.headers["subject"]
    assert_equal "urgent", u.headers["priority"]
  end

  def test_bracketed_ipv6
    u = TsipParser::Uri.parse("sip:alice@[::1]:5060")
    assert_equal "::1", u.host
    assert_equal 5060, u.port
    assert_equal "[::1]:5060", u.host_port
    assert_equal "[::1]", u.bracket_host
  end

  def test_aor
    u = TsipParser::Uri.parse("sip:alice@atlanta.com:5060;transport=tls")
    assert_equal "sip:alice@atlanta.com", u.aor
  end

  def test_roundtrip_simple
    input = "sip:alice@atlanta.com;transport=tcp"
    assert_equal input, TsipParser::Uri.parse(input).to_s
  end

  def test_roundtrip_headers
    input = "sip:alice@atlanta.com?subject=hi&foo=bar"
    assert_equal input, TsipParser::Uri.parse(input).to_s
  end

  def test_roundtrip_ipv6
    input = "sip:alice@[2001:db8::1]:5061;transport=tls"
    assert_equal input, TsipParser::Uri.parse(input).to_s
  end

  def test_scheme_case_insensitive
    u = TsipParser::Uri.parse("SIP:alice@atlanta.com")
    assert_equal "sip", u.scheme
  end

  def test_equality_on_aor_fields
    a = TsipParser::Uri.parse("sip:alice@Atlanta.COM")
    b = TsipParser::Uri.parse("sip:alice@atlanta.com")
    assert_equal a, b
    assert_equal a.hash, b.hash
  end

  def test_pct_decoded_user
    u = TsipParser::Uri.parse("sip:al%69ce@atlanta.com")
    assert_equal "alice", u.user
  end

  def test_empty_produces_blank_host
    u = TsipParser::Uri.parse("")
    assert_equal "", u.host
  end

  def test_parse_error_is_argument_error_subclass
    assert_operator TsipParser::ParseError, :<, ArgumentError
  end
end
