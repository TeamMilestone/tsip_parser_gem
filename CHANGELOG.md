# Changelog

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
