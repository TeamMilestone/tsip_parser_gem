use magnus::{Error, Ruby};

mod address;
mod error;
mod uri;

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    // TsipParser::ParseError is defined in lib/tsip_parser.rb
    // (< ArgumentError, per HANDOVER §7) — resolved lazily in error::parse_error_class.
    let module = ruby.define_module("TsipParser")?;
    uri::init(ruby, &module)?;
    address::init(ruby, &module)?;
    Ok(())
}
