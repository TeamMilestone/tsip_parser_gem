use magnus::{prelude::*, Error, ExceptionClass, RModule, Ruby};

/// Resolve `TsipParser::ParseError` at runtime. Falls back to `ArgumentError`
/// if the constant hasn't been defined yet (should not happen after
/// `lib/tsip_parser.rb` has loaded).
pub fn parse_error_class(ruby: &Ruby) -> ExceptionClass {
    let module: RModule = ruby.define_module("TsipParser").unwrap();
    module
        .const_get::<_, ExceptionClass>("ParseError")
        .unwrap_or_else(|_| ruby.exception_arg_error())
}

pub fn to_ruby(ruby: &Ruby, err: tsip_parser::ParseError) -> Error {
    Error::new(parse_error_class(ruby), err.to_string())
}
