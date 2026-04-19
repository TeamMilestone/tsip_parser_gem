# tsip_parser

[![Gem Version](https://badge.fury.io/rb/tsip_parser.svg)](https://rubygems.org/gems/tsip_parser)
[![CI](https://github.com/TeamMilestone/tsip_parser_gem/actions/workflows/ci.yml/badge.svg)](https://github.com/TeamMilestone/tsip_parser_gem/actions/workflows/ci.yml)

Ruby binding for the [`tsip-parser`](https://crates.io/crates/tsip-parser)
Rust crate. Parses and serializes RFC 3261 §19.1 **SIP URIs** and §25.1
**Addresses** (`Name <uri>;tag=...`) in pure Rust, exposed to Ruby via a
`magnus` native extension.

```ruby
u = TsipParser::Uri.parse("sip:alice@atlanta.com:5060;transport=tcp")
u.scheme     # => "sip"
u.user       # => "alice"
u.host       # => "atlanta.com"
u.port       # => 5060
u.transport  # => "tcp"
u.to_s       # => "sip:alice@atlanta.com:5060;transport=tcp"

a = TsipParser::Address.parse('"Alice" <sip:alice@atlanta.com>;tag=abc')
a.display_name  # => "Alice"
a.uri.user      # => "alice"
a.tag           # => "abc"
```

## Install

```ruby
# Gemfile
gem "tsip_parser"
```

or

```sh
gem install tsip_parser
```

Precompiled binaries are published for the common Ruby-supported platforms
(linux-x64-gnu, linux-arm64, darwin-x64, darwin-arm64). Installing on any
other platform will compile the Rust extension from source — requires
Rust ≥ 1.75 and Ruby ≥ 3.0.

## Why

`tsip-core` (our pure-Ruby SIP stack) ships a byte-scan Uri / Address parser
that allocates ~10 intermediate strings per parse. On a hot SIP server those
allocations are the single largest GC pressure source. This gem is the same
parser, reimplemented in Rust and surfaced with the exact same Ruby API, so
existing tsip-core call sites can be swapped module-for-module.

Measured on Ruby 4.0.1, M1 macOS, release build:

| endpoint          | tsip_parser  | tsip-core     | speedup |
|-------------------|--------------|---------------|---------|
| `Uri.parse`       | 595k ips     | 40k ips       | **14.8×** |
| `Address.parse`   | 672k ips     | 41k ips       | **16.6×** |
| `uri.param("t")`  | 2.07M ips *  | 125k ips *    | **16.5×** |
| `address.tag`     | 1.99M ips *  | 139k ips *    | **14.4×** |

\* parse + single-field lookup, combined.

Reproduce with `bundle exec ruby bench/compare.rb` and `bench/new_apis.rb`.

## API

### `TsipParser::Uri`

```ruby
u = TsipParser::Uri.parse(str)        # => TsipParser::Uri, or raises ParseError

u.scheme          # "sip" | "sips" | "tel"
u.user            # String | nil     (pct-decoded)
u.password        # String | nil     (pct-decoded)
u.host            # String           (IPv6 without brackets, e.g. "::1")
u.port            # Integer | nil
u.params          # Hash<String, String>  (insertion order, tsip-core compatible)
u.headers         # Hash<String, String>
u.transport       # "tcp" | "tls" | "udp" | ""   (convenience — same as params["transport"].downcase)
u.aor             # "sip:user@host"                (no port/params/headers)
u.host_port       # "host:port" or "[ipv6]:port"
u.bracket_host    # IPv6 wrapped in [] when needed
u.to_s            # full canonical serialization

# Hot-path helpers (avoid the Hash materialization)
u.param("transport")   # => String | nil  — single Vec lookup in Rust
u.header("subject")    # => String | nil

# Batch parse
TsipParser::Uri.parse_many([str1, str2, ...])  # => Array<Uri>
```

### `TsipParser::Address`

```ruby
a = TsipParser::Address.parse(str)

a.display_name    # "Alice Liddell" | nil
a.uri             # TsipParser::Uri | nil
a.params          # Hash<String, String>  (only address-level params: tag / q / expires)
a.tag             # String | nil          (params["tag"])
a.tag = "xyz"     # writes through params
a.to_s

a.param("expires")
TsipParser::Address.parse_many([...])
```

### `TsipParser::ParseError`

Subclass of `ArgumentError`. Raised on:

* empty input with no scheme
* unterminated `[` / `"` / `<`
* invalid UTF-8 after pct-decoding
* hosts containing forbidden characters (crate 0.1.1 validation)

Because it's an `ArgumentError`, existing `rescue ArgumentError` clauses
from tsip-core continue to catch it.

## Mutation semantics

Params and headers are **memoized on first access** and returned as mutable
`Hash` objects, same as tsip-core:

```ruby
u = TsipParser::Uri.parse("sip:a@b")
u.params["transport"] = "tls"   # persists
u.to_s                          # => "sip:a@b;transport=tls"
```

The fast path (`u.to_s` without any field access) skips Hash construction
and serializes directly from the Rust struct. As soon as `params` or
`headers` is read or mutated, the Ruby facade switches to the cached Hash
for serialization so mutations round-trip correctly.

## Rust crate version

Pinned in `ext/tsip_parser/Cargo.toml` to `tsip-parser = "0.1"`, currently
resolved to 0.1.1 (fuzz-hardened validation). Gem patch versions track
patch/minor bumps of the crate; a gem major bump is only needed if the
crate breaks its public API.

## Development

```sh
bundle install
bundle exec rake compile     # build the native extension
bundle exec rake test        # 25 tests, tsip-core parity + crate roundtrip subset
bundle exec ruby bench/compare.rb
```

## License

MIT. See `LICENSE`.

## Author

Wonsup Lee (이원섭) — alfonso@team-milestone.io
