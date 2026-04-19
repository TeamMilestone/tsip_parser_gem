# Changelog

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
