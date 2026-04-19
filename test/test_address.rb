# frozen_string_literal: true

require_relative "test_helper"

# Ported verbatim from tsip-core/test/sip/test_address.rb (5 tests). API
# contract: if these pass, a tsip-core user can swap in TsipParser::Address
# without touching call sites.
class TestAddress < Minitest::Test
  def test_name_addr_quoted
    a = TsipParser::Address.parse('"Alice Liddell" <sip:alice@example.com>;tag=abc')
    assert_equal "Alice Liddell", a.display_name
    assert_equal "alice", a.uri.user
    assert_equal "abc", a.tag
  end

  def test_addr_spec
    a = TsipParser::Address.parse("sip:bob@example.com")
    assert_nil a.display_name
    assert_equal "bob", a.uri.user
  end

  def test_display_no_quotes
    a = TsipParser::Address.parse("Alice <sip:alice@example.com>")
    assert_equal "Alice", a.display_name
  end

  def test_bare_with_tag
    a = TsipParser::Address.parse("sip:alice@example.com;tag=xyz")
    assert_equal "xyz", a.tag
  end

  def test_roundtrip
    a = TsipParser::Address.parse('"Alice" <sip:alice@example.com>;tag=1')
    parsed = TsipParser::Address.parse(a.to_s)
    assert_equal a.display_name, parsed.display_name
    assert_equal a.tag, parsed.tag
  end

  def test_tag_setter_writes_through_params
    a = TsipParser::Address.parse("sip:alice@example.com")
    a.tag = "t1"
    assert_equal "t1", a.tag
    assert_equal "t1", a.params["tag"]
  end

  def test_bare_param_on_uri_goes_to_uri_params
    a = TsipParser::Address.parse("sip:alice@example.com;transport=tcp")
    assert_equal "tcp", a.uri.params["transport"]
    refute a.params.key?("transport")
  end

  def test_unterminated_angle_raises
    assert_raises(TsipParser::ParseError) do
      TsipParser::Address.parse('"Alice" <sip:alice@example.com')
    end
  end
end
