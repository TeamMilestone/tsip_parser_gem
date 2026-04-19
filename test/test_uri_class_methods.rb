# frozen_string_literal: true

require_relative "test_helper"

# Class-method surface exposed for tsip-core's planned
# `TsipCore::Sip::Uri = TsipParser::Uri` alias (V0_2_2_HANDOFF).
class TestUriClassMethods < Minitest::Test
  # ----- parse_range ---------------------------------------------------

  def test_parse_range_slices_inner_uri
    full = "<sip:alice@host:5060>"
    u = TsipParser::Uri.parse_range(full, 1, full.bytesize - 1)
    assert_equal "alice", u.user
    assert_equal "host", u.host
    assert_equal 5060, u.port
  end

  def test_parse_range_empty_returns_default
    u = TsipParser::Uri.parse_range("sip:", 0, 4)
    assert_equal "sip", u.scheme
    assert_equal "", u.host
  end

  def test_parse_range_out_of_bounds_raises
    assert_raises(TsipParser::ParseError) do
      TsipParser::Uri.parse_range("sip:a@h", 0, 100)
    end
  end

  def test_parse_range_reversed_offsets_raises
    assert_raises(TsipParser::ParseError) do
      TsipParser::Uri.parse_range("sip:a@h", 5, 2)
    end
  end

  # ----- parse_param ---------------------------------------------------

  def test_parse_param_inserts_key_value
    target = {}
    TsipParser::Uri.parse_param("transport=tls", target)
    assert_equal({ "transport" => "tls" }, target)
  end

  def test_parse_param_key_only
    target = {}
    TsipParser::Uri.parse_param("lr", target)
    assert_equal({ "lr" => "" }, target)
  end

  def test_parse_param_empty_noop
    target = {}
    TsipParser::Uri.parse_param("", target)
    assert_equal({}, target)
  end

  def test_parse_param_appends_to_existing_hash
    target = { "transport" => "tcp" }
    TsipParser::Uri.parse_param("lr", target)
    assert_equal({ "transport" => "tcp", "lr" => "" }, target)
  end

  def test_parse_param_overwrites_duplicate_key
    target = { "transport" => "tcp" }
    TsipParser::Uri.parse_param("transport=tls", target)
    assert_equal({ "transport" => "tls" }, target)
  end

  # ----- parse_host_port -----------------------------------------------

  def test_parse_host_port_simple
    assert_equal ["example.com", 5060], TsipParser::Uri.parse_host_port("example.com:5060")
  end

  def test_parse_host_port_no_port
    assert_equal ["example.com", nil], TsipParser::Uri.parse_host_port("example.com")
  end

  def test_parse_host_port_ipv6
    assert_equal ["::1", 5060], TsipParser::Uri.parse_host_port("[::1]:5060")
  end

  def test_parse_host_port_ipv6_no_port
    assert_equal ["::1", nil], TsipParser::Uri.parse_host_port("[::1]")
  end

  def test_parse_host_port_empty
    assert_equal ["", nil], TsipParser::Uri.parse_host_port("")
  end
end
