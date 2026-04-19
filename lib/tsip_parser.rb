# frozen_string_literal: true

require_relative "tsip_parser/version"

module TsipParser
  # Raised on malformed URI / Address input. Subclasses ArgumentError so
  # existing `rescue ArgumentError` clauses in tsip-core code keep working
  # when tsip_parser is swapped in.
  class ParseError < ArgumentError; end
end

# Rust extension defines TsipParser::Uri and TsipParser::Address as
# TypedData classes. Must load before the Ruby facade files that reopen them.
require "tsip_parser/tsip_parser"
require_relative "tsip_parser/uri"
require_relative "tsip_parser/address"
