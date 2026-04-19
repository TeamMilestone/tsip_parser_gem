use magnus::{
    function, method, prelude::*, Error, RArray, RHash, RModule, RString, Ruby, TryConvert,
};

use crate::uri;

#[magnus::wrap(class = "TsipParser::Address", free_immediately, size)]
pub struct Address {
    inner: tsip_parser::Address,
}

impl Address {
    fn parse(input: RString) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes = unsafe { input.as_slice() };
        let s = std::str::from_utf8(bytes)
            .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
        let a = tsip_parser::Address::parse(s).map_err(|e| crate::error::to_ruby(&ruby, e))?;
        Ok(Address { inner: a })
    }

    fn parse_many(input: RArray) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let out = ruby.ary_new_capa(input.len());
        for item in input.into_iter() {
            let rs: RString = TryConvert::try_convert(item)?;
            let bytes = unsafe { rs.as_slice() };
            let s = std::str::from_utf8(bytes)
                .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
            let a = tsip_parser::Address::parse(s).map_err(|e| crate::error::to_ruby(&ruby, e))?;
            let _ = out.push(Address { inner: a });
        }
        Ok(out)
    }

    /// Direct address-level param lookup — no Hash materialization. Use
    /// `address.tag` / `address.param("expires")` etc. in hot paths.
    fn param(&self, name: RString) -> Option<String> {
        let bytes = unsafe { name.as_slice() };
        let needle = std::str::from_utf8(bytes).ok()?;
        self.inner
            .params
            .iter()
            .find(|(k, _)| k == needle)
            .map(|(_, v)| v.clone())
    }

    /// Fast-path `tag` reader that skips the Ruby facade's Hash
    /// memoization. `address.rust_tag` ≈ `address.params["tag"]` but
    /// without building the Hash. Ruby facade falls through to this when
    /// `@params` hasn't been materialized.
    fn rust_tag(&self) -> Option<String> {
        self.inner.tag().map(|s| s.to_string())
    }

    fn display_name(&self) -> Option<String> {
        self.inner.display_name.clone()
    }

    /// Returns a fresh `TsipParser::Uri` wrapping a clone of the embedded
    /// URI. Ruby facade memoizes this so repeated access + any field
    /// mutations land on the same wrapper.
    fn rust_uri(&self) -> Option<uri::Uri> {
        self.inner.uri.clone().map(uri::Uri::from_inner)
    }

    fn rust_params(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        uri::hash_from_pairs(&ruby, &self.inner.params)
    }

    fn rust_to_s(&self) -> String {
        self.inner.to_string()
    }
}

pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    let class = parent.define_class("Address", ruby.class_object())?;
    class.define_singleton_method("parse", function!(Address::parse, 1))?;
    class.define_singleton_method("parse_many", function!(Address::parse_many, 1))?;
    class.define_method("param", method!(Address::param, 1))?;
    class.define_method("_rust_tag", method!(Address::rust_tag, 0))?;
    class.define_method("_rust_display_name", method!(Address::display_name, 0))?;
    class.define_method("_rust_uri", method!(Address::rust_uri, 0))?;
    class.define_method("_rust_params", method!(Address::rust_params, 0))?;
    class.define_method("_rust_to_s", method!(Address::rust_to_s, 0))?;
    Ok(())
}
