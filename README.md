# tsip_parser

A Ruby binding over the [`tsip-parser`](https://crates.io/crates/tsip-parser)
Rust crate. Provides RFC 3261 §19.1 SIP URI and §25.1 Address parsing.

## Install

```ruby
gem "tsip_parser"
```

## Usage

```ruby
require "tsip_parser"

u = TsipParser::Uri.parse("sip:alice@atlanta.com;transport=tcp")
u.scheme     # => "sip"
u.user       # => "alice"
u.host       # => "atlanta.com"
u.params     # => {"transport" => "tcp"}
u.transport  # => "tcp"
u.to_s       # => "sip:alice@atlanta.com;transport=tcp"

a = TsipParser::Address.parse('"Alice" <sip:alice@atlanta.com>;tag=xyz')
a.display_name  # => "Alice"
a.uri.user      # => "alice"
a.tag           # => "xyz"
```

Raises `TsipParser::ParseError` (a subclass of `ArgumentError`) on malformed
input.

## License

MIT
