# frozen_string_literal: true

# Compare TsipParser (Rust-backed) against TsipCore (pure Ruby) on a
# representative set of Uri / Address inputs. Target: 10× ips advantage for
# tsip_parser (HANDOVER §0 performance goals).
#
# Run: `bundle exec ruby bench/compare.rb`
#
# Requires tsip-core to be reachable — add it to the Gemfile under the
# :bench group, or `bundle config local.tsip_core ../tsip-core`.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "benchmark/ips"
require "tsip_parser"

# tsip-core's top-level load chain pulls in the whole stack (logger, yajl,
# etc.). We only need the two pure-Ruby parser files for the comparison, so
# require them directly to dodge irrelevant load-order issues.
$LOAD_PATH.unshift File.expand_path("../../tsip-core/lib", __dir__)
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

puts "\n== Uri.parse =="
Benchmark.ips do |x|
  x.report("tsip_parser") do
    URIS.each { |s| TsipParser::Uri.parse(s) }
  end
  x.report("tsip_core") do
    URIS.each { |s| TsipCore::Sip::Uri.parse(s) }
  end
  x.compare!
end

puts "\n== Address.parse =="
Benchmark.ips do |x|
  x.report("tsip_parser") do
    ADDRS.each { |s| TsipParser::Address.parse(s) }
  end
  x.report("tsip_core") do
    ADDRS.each { |s| TsipCore::Sip::Address.parse(s) }
  end
  x.compare!
end
