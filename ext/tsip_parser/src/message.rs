use magnus::{function, prelude::*, Error, RArray, RHash, RModule, RString, Ruby};
use std::collections::HashMap;
use tsip_parser::{Message, StartLine};

/// Singleton `TsipParser::Message.parse(raw)` — native SIP message framing.
/// Returns a plain Hash so tsip-core's bridge can stuff the values straight
/// into its `Sip::Message` ivars without an intermediate wrapper object.
/// See `docs/V0_3_0_HANDOFF.md` §4 for the exact contract.
fn parse(input: RString) -> Result<RHash, Error> {
    let ruby = unsafe { Ruby::get_unchecked() };
    let bytes = unsafe { input.as_slice() };
    let m = Message::parse(bytes).map_err(|e| crate::error::to_ruby(&ruby, e))?;

    let hash = ruby.hash_new_capa(6);
    let sym_kind = ruby.to_symbol("kind");
    match m.start_line {
        StartLine::Request {
            method,
            request_uri,
            sip_version,
        } => {
            hash.aset(sym_kind, ruby.to_symbol("request"))?;
            hash.aset(ruby.to_symbol("method"), method)?;
            hash.aset(ruby.to_symbol("request_uri"), request_uri)?;
            hash.aset(ruby.to_symbol("sip_version"), sip_version)?;
        }
        StartLine::Response {
            sip_version,
            status_code,
            reason_phrase,
        } => {
            hash.aset(sym_kind, ruby.to_symbol("response"))?;
            hash.aset(ruby.to_symbol("sip_version"), sip_version)?;
            hash.aset(ruby.to_symbol("status_code"), status_code)?;
            hash.aset(ruby.to_symbol("reason_phrase"), reason_phrase)?;
        }
    }

    hash.aset(ruby.to_symbol("headers"), build_headers_hash(&ruby, &m.headers)?)?;

    // SIP body is arbitrary bytes — force ASCII-8BIT so downstream network
    // code doesn't choke on invalid UTF-8. Using enc_str_new with the
    // ASCII-8BIT encoding is more direct than post-hoc `.b` on Ruby side.
    let body = ruby.enc_str_new(&m.body[..], ruby.ascii8bit_encoding());
    hash.aset(ruby.to_symbol("body"), body)?;

    Ok(hash)
}

/// Convert the crate's `Vec<(name, value)>` — already canonicalised and in
/// wire order — into `{ name => [value, ...] }`. Preserves the original
/// order of duplicate-named headers (Via multi-routing depends on it) by
/// indexing the first-seen position per name.
fn build_headers_hash(ruby: &Ruby, pairs: &[(String, String)]) -> Result<RHash, Error> {
    let mut index: HashMap<&str, RArray> = HashMap::with_capacity(pairs.len());
    let hash = ruby.hash_new_capa(pairs.len().min(16));
    for (name, value) in pairs {
        if let Some(arr) = index.get(name.as_str()) {
            arr.push(value.as_str())?;
        } else {
            let arr = ruby.ary_new_capa(1);
            arr.push(value.as_str())?;
            hash.aset(name.as_str(), arr)?;
            index.insert(name.as_str(), arr);
        }
    }
    Ok(hash)
}

pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    let class = parent.define_class("Message", ruby.class_object())?;
    class.define_singleton_method("parse", function!(parse, 1))?;
    Ok(())
}
