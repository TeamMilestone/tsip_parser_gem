# Changelog

## [0.3.0] - 2026-04-19

Tracks upstream `tsip-parser` crate 0.3.0. Dependency pin moves from `~> 0.2`
to `~> 0.3`. Exposes the crate's new SIP message framing parser so tsip-core's
bridge can drop its pure-Ruby `Sip::Parser.parse` — the last 15~18% self-time
frame in stackprof for bridge-ON throughput (7,239 cps → target 7,700~8,000).

### Added
- `TsipParser::Message.parse(raw)` — RFC 3261 message framing. Returns a
  plain Hash (no wrapper class) so tsip-core can stuff the values straight
  into `Sip::Message` ivars:
  ```ruby
  h = TsipParser::Message.parse(invite_bytes)
  # => {
  #   kind: :request,
  #   method: "INVITE",
  #   request_uri: "sip:bob@biloxi.example.com",
  #   sip_version: "SIP/2.0",
  #   headers: { "Via" => [...], "Call-ID" => [...], ... },
  #   body: "".b  # ASCII-8BIT
  # }
  ```
  Responses carry `:status_code` (Integer) and `:reason_phrase` instead of
  `:method` / `:request_uri`.

### Contract details
- `headers` keys are canonical names (compact forms expanded: `v` → `"Via"`,
  `i` → `"Call-ID"`, `l` → `"Content-Length"`, ...).
- `headers` values are `Array<String>` — multiple same-named headers keep
  wire order (Via multi-routing depends on this).
- `body` is always `ASCII-8BIT` (forced on the Rust side via
  `enc_str_new(&bytes, ascii8bit_encoding())`).
- `method` is uppercase-normalised.
- Content-Length validation happens in the crate; malformed values raise
  `TsipParser::ParseError` at parse time.

### Not added
- `TsipParser::Message.new` — tsip-core constructs `Sip::Message` from the
  returned Hash; no 0-arg allocator needed.
- `Message#to_s` / re-render — network layer re-uses the original bytes;
  the crate's `Message` has no `Display` impl.
- Structured header value parsing (Via/CSeq/Contact/...) — raw String
  preserved, unchanged from pre-0.3 behavior.

### Crate 0.3.0 reference
- 48 message tests (28 normal / 20 malformed) + 30s fuzz 4.78M runs panic=0.
- `message_parse_invite_10h` bench 1.48 µs.

## [0.2.3] - 2026-04-19

No crate change (still `tsip-parser = "0.2"`). Gem-only release that exposes
a 0-arg `Address.new` allocator so tsip-core's `Address.build` bridge can
drop its placeholder parse (`parse("<sip:_@_>")`) — ~16k placeholder
parses/s eliminated at 8k cps dialog throughput.

### Added
- `TsipParser::Address.new` — 0-arg allocator returning an empty Address
  (`display_name: nil`, `uri: nil`, `params: {}`). Use with the existing
  setters / memoized `params` Hash to assemble:
  ```ruby
  a = TsipParser::Address.new
  a.display_name = "Alice"
  a.uri = TsipParser::Uri.parse("sip:alice@example.com")
  a.params["tag"] = "xyz"
  a.to_s  # => "\"Alice\" <sip:alice@example.com>;tag=xyz"
  ```
  Implementation: the `magnus::wrap` macro does not register a Ruby
  allocator, so `new` is registered as a 0-arg singleton method returning
  `tsip_parser::Address::default()`. The empty state's `to_s` is `"<>"`
  (bare angle brackets) per the crate's `Display` impl.

### Not added (per HANDOFF §7)
- `TsipParser::Uri.new` — tsip-core always constructs `Uri` via `parse`.
- kwargs constructor on `Address.new(display_name:, uri:, params:)` —
  tsip-core's bridge `Address.build(...)` does the kwargs mapping.

## [0.2.2] - 2026-04-19

No crate change (still `tsip-parser = "0.2"`, resolved to 0.2.1). Gem-only
release that exposes three crate class methods so tsip-core can switch from
its per-parse bridge shim to a direct `TsipCore::Sip::Uri = TsipParser::Uri`
class alias. Eliminates the -2.8% throughput regression measured in the
tsip-core integration bench on 2026-04-19.

### Added
- `TsipParser::Uri.parse_range(str, from, to)` — byte-range parse that
  mirrors `tsip_parser::Uri::parse_range`. Used by tsip-core's
  `Address.parse` to parse the URI inside `<...>` without substring alloc.
  Validates offsets + UTF-8 boundary; raises `ParseError` on out-of-range
  or mid-codepoint offsets.
- `TsipParser::Uri.parse_param(raw, hash)` — parse one `key[=value]`
  segment into an existing Ruby Hash. Used by tsip-core `Via.parse` on
  each semicolon-split segment. Key-only segments insert `""`; empty raw
  is a no-op; duplicate keys overwrite.
- `TsipParser::Uri.parse_host_port(str)` — parse a `host[:port]` fragment
  including the bracketed IPv6 form (`[::1]:5060`). Returns
  `[host, port_or_nil]`.

### Not added (deliberately, per HANDOFF §3.3)
- `Address.new(display_name:, uri:, params:)` kwargs constructor. tsip-core
  will add an `Address.build(...)` helper on its side instead.

## [0.2.1] - 2026-04-19

Tracks upstream `tsip-parser` crate 0.2.1. Dependency pin unchanged (`~> 0.2`).

### Crate 0.2.1 semantics
- Accepts URI-level param keys/values containing `; ? & = < >`. Round-trip
  stability comes from render-side pct-escape with lowercase hex (so the
  key downcase on re-parse reaches a fixed point in one cycle). `%` is
  deliberately *not* escaped — params are stored literally, so escaping `%`
  would break the fixed point.
- Closes the last xoracle parity case (`sip:alice@host;<evil>=1`) vs the
  Ruby tsip-core reference.

### Gem-side
- **Ruby `Uri#append_to` now mirrors the crate's render-side escape.**
  Previously the Ruby serialization path (triggered once `params` or
  `headers` was touched) wrote fields literally, which diverged from the
  Rust `Display` output for inputs containing `@ : ; ? < > % & =` or
  whitespace. After this release, fast-path (`to_s` without field access)
  and slow-path (`to_s` after mutation) produce identical output.
  - `append_pct_escaped` — userinfo + URI header key/value, uppercase hex,
    escapes `@ : ; ? < > % & = space tab CR LF`.
  - `append_param_escaped` — URI-level param key/value, lowercase hex,
    escapes `; ? & = < >`.

### Measured (Ruby 4.0.1, M1 macOS, release build; crate 0.2.1)
- `Uri.parse` — 646k ips vs `TsipCore::Sip::Uri.parse` 41k ips → **15.8× faster**.
- `Address.parse` — 694k ips vs `TsipCore::Sip::Address.parse` 41k ips → **16.8× faster**.
- Escape work only runs on the slow path (fields mutated), so parse-only
  throughput is unchanged from 0.2.0.

## [0.2.0] - 2026-04-19

Tracks upstream `tsip-parser` crate 0.2.0. Dependency pin moves from `~> 0.1`
to `~> 0.2`. **Behavior change, not API change** — the Ruby surface is
unchanged, but inputs that 0.1.1 rejected with `ParseError::InvalidHost`
may now parse successfully.

### Crate 0.2.0 semantics (relevant to gem users)
- **Permissive parse**: accepts pct-encoded userinfo specials, `<` in param
  keys, and leading/trailing whitespace in URI-level param/header values.
  Converges with the tsip-core pure-Ruby parser's accepted-input set.
- Round-trip stability is now enforced on the **render** side: pct-decoded
  fields (userinfo, URI header key/value) are pct-escaped when serializing
  back via `to_s`. Callers who previously saw `ParseError` on raw
  user-provided SIP URIs will now get a parsed `Uri` whose `to_s` produces
  a stable canonical form.
- Narrow parse-time rejections remain for bytes literal param storage
  cannot round-trip: `>` in any param, `?` in URI-level params.

### Measured (Ruby 4.0.1, M1 macOS, release build; crate 0.2.0)
- `Uri.parse` — 654k ips vs `TsipCore::Sip::Uri.parse` 41k ips → **16.1× faster**.
- `Address.parse` — 695k ips vs `TsipCore::Sip::Address.parse` 41k ips → **16.8× faster**.
- Permissive validation recovers most of 0.1.1's validation overhead;
  numbers are back in line with 0.1.0.

## [0.1.0] - 2026-04-19

Initial release. Thin Ruby binding around the `tsip-parser` Rust crate (≥ 0.1.1;
pinned to `~> 0.1`). Picks up 0.1.1's fuzz-hardened validation — ~350 round-trip
unstable inputs are now rejected with `InvalidHost`-flavored `ParseError`.

### Added
- `TsipParser::Uri.parse(str)` — RFC 3261 §19.1 SIP URI parser.
- `TsipParser::Address.parse(str)` — RFC 3261 §25.1 name-addr / addr-spec parser.
- `TsipParser::ParseError` raised on malformed input (subclass of `ArgumentError`).

### Implementation
- Rust structs exposed via `#[magnus::wrap]` TypedData — parsing does **not**
  eagerly allocate a Ruby Hash or set ivars. Scalar fields are Rust accessor
  methods; `params` / `headers` materialize on first access and the Ruby
  facade memoizes so mutations (`uri.params["x"] = "y"`, `address.tag = "t"`)
  persist across reads and round-trip through `to_s`.

### Measured (Ruby 4.0.1, M1 macOS, release build; crate 0.1.1)
- `Uri.parse` — 595k ips vs `TsipCore::Sip::Uri.parse` 40k ips → **14.8× faster**.
- `Address.parse` — 672k ips vs `TsipCore::Sip::Address.parse` 41k ips → **16.6× faster**.
- Clears the 10× HANDOVER §0 target on both entry points. (Crate 0.1.0 was
  17× on both; 0.1.1's stricter validation trims a few µs but rejects
  round-trip-unstable input in exchange.)

### Hot-path helpers
- `TsipParser::Uri.parse_many(strs)` / `Address.parse_many(strs)` — single
  FFI call per batch. ~8-12% faster than a Ruby loop over `parse`; meant
  for bulk parsing paths (Via/Route header lists, registrar input queues).
- `uri.param(name)` / `uri.header(name)` / `address.param(name)` — searches
  the Rust `Vec` directly, skipping Hash materialization. ~1.6-1.9× faster
  than `uri.params[name]` for single-key lookups, which is the common
  parse-and-check-one-value pattern. `address.tag` takes this fast path
  automatically when `params` hasn't been touched.
