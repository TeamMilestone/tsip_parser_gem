# frozen_string_literal: true

# Benches the two new hot-path helpers:
#   * TsipParser::Uri.parse_many / Address.parse_many — one FFI call per
#     batch rather than one per input.
#   * uri.param(k) / uri.header(k) / address.param(k) — search the Rust Vec
#     directly, no Hash build.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../../tsip-core/lib", __dir__)

require "benchmark/ips"
require "tsip_parser"
require "tsip_core/sip/uri"
require "tsip_core/sip/address"

URIS = [
  "sip:alice@atlanta.com",
  "sip:alice@atlanta.com:5060;transport=tcp",
  "sip:alice:secret@atlanta.com:5061;transport=tls;lr",
  "sips:bob@biloxi.com?subject=hi&priority=urgent",
  "sip:carol@[2001:db8::1]:5060;transport=udp"
].freeze

ADDRS = [
  '"Alice" <sip:alice@atlanta.com>;tag=abc',
  "Bob <sip:bob@biloxi.com:5060;transport=tcp>;tag=xyz;expires=600",
  "sip:carol@chicago.com;tag=1928301774",
  '"Dave Smith" <sips:dave@secure.example.com>'
].freeze

puts "\n== Uri.parse_many vs loop of Uri.parse =="
Benchmark.ips do |x|
  x.report("parse (loop)")   { URIS.each { |s| TsipParser::Uri.parse(s) } }
  x.report("parse_many")     { TsipParser::Uri.parse_many(URIS) }
  x.report("tsip_core loop") { URIS.each { |s| TsipCore::Sip::Uri.parse(s) } }
  x.compare!
end

puts "\n== Address.parse_many vs loop =="
Benchmark.ips do |x|
  x.report("parse (loop)")   { ADDRS.each { |s| TsipParser::Address.parse(s) } }
  x.report("parse_many")     { TsipParser::Address.parse_many(ADDRS) }
  x.report("tsip_core loop") { ADDRS.each { |s| TsipCore::Sip::Address.parse(s) } }
  x.compare!
end

puts "\n== Param lookup: .param('transport') vs .params['transport'] =="
PARAM_URI = "sip:alice@atlanta.com:5060;transport=tls;lr;maddr=1.2.3.4"
Benchmark.ips do |x|
  x.report("uri.param('transport')") do
    u = TsipParser::Uri.parse(PARAM_URI)
    u.param("transport")
  end
  x.report("uri.params['transport']") do
    u = TsipParser::Uri.parse(PARAM_URI)
    u.params["transport"]
  end
  x.report("tsip_core params[]") do
    u = TsipCore::Sip::Uri.parse(PARAM_URI)
    u.params["transport"]
  end
  x.compare!
end

puts "\n== Address tag lookup =="
TAG_ADDR = '"Alice" <sip:alice@atlanta.com>;tag=abc123;expires=3600'
Benchmark.ips do |x|
  x.report("addr.tag (fast)") do
    a = TsipParser::Address.parse(TAG_ADDR)
    a.tag
  end
  x.report("addr.params['tag']") do
    a = TsipParser::Address.parse(TAG_ADDR)
    a.params["tag"]
  end
  x.report("tsip_core tag") do
    a = TsipCore::Sip::Address.parse(TAG_ADDR)
    a.tag
  end
  x.compare!
end
