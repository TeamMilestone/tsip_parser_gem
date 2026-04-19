use magnus::{
    function, method, prelude::*, Error, RArray, RHash, RModule, RString, Ruby, TryConvert,
};

/// Ruby-facing `TsipParser::Uri`. Wraps `tsip_parser::Uri` directly via
/// TypedData so parsing doesn't eagerly allocate a Hash/Object/ivar set.
/// Scalar accessors read from the embedded struct; `params`/`headers` build
/// a Hash on first access and the Ruby facade memoizes it so subsequent
/// reads — and any mutations — hit plain ivars.
#[magnus::wrap(class = "TsipParser::Uri", free_immediately, size)]
pub struct Uri {
    pub(crate) inner: tsip_parser::Uri,
}

impl Uri {
    pub(crate) fn from_inner(inner: tsip_parser::Uri) -> Self {
        Uri { inner }
    }

    fn parse(input: RString) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes = unsafe { input.as_slice() };
        let s = std::str::from_utf8(bytes)
            .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
        let u = tsip_parser::Uri::parse(s).map_err(|e| crate::error::to_ruby(&ruby, e))?;
        Ok(Uri { inner: u })
    }

    /// Parse an Array of strings in a single FFI call. Saves the per-call
    /// Ruby→Rust dispatch cost for bulk workloads (Via/Route header lists,
    /// registrar traffic).
    fn parse_many(input: RArray) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let out = ruby.ary_new_capa(input.len());
        for item in input.into_iter() {
            let rs: RString = TryConvert::try_convert(item)?;
            let bytes = unsafe { rs.as_slice() };
            let s = std::str::from_utf8(bytes)
                .map_err(|_| Error::new(crate::error::parse_error_class(&ruby), "invalid UTF-8"))?;
            let u = tsip_parser::Uri::parse(s).map_err(|e| crate::error::to_ruby(&ruby, e))?;
            let _ = out.push(Uri { inner: u });
        }
        Ok(out)
    }

    /// Direct single-value param lookup — searches the embedded Vec without
    /// materializing a Hash. `uri.param("transport")` is ~4-6× cheaper than
    /// `uri.params["transport"]` for parse-then-read-one-value flows.
    fn param(&self, name: RString) -> Option<String> {
        let bytes = unsafe { name.as_slice() };
        let needle = std::str::from_utf8(bytes).ok()?;
        self.inner
            .params
            .iter()
            .find(|(k, _)| k == needle)
            .map(|(_, v)| v.clone())
    }

    fn header(&self, name: RString) -> Option<String> {
        let bytes = unsafe { name.as_slice() };
        let needle = std::str::from_utf8(bytes).ok()?;
        self.inner
            .headers
            .iter()
            .find(|(k, _)| k == needle)
            .map(|(_, v)| v.clone())
    }

    fn scheme(&self) -> &'static str {
        self.inner.scheme
    }
    fn user(&self) -> Option<String> {
        self.inner.user.clone()
    }
    fn password(&self) -> Option<String> {
        self.inner.password.clone()
    }
    fn host(&self) -> String {
        self.inner.host.clone()
    }
    fn port(&self) -> Option<u16> {
        self.inner.port
    }
    fn transport(&self) -> String {
        self.inner.transport()
    }
    fn aor(&self) -> String {
        self.inner.aor()
    }
    fn host_port(&self) -> String {
        self.inner.host_port()
    }
    fn bracket_host(&self) -> String {
        self.inner.bracket_host()
    }
    fn rust_to_s(&self) -> String {
        self.inner.to_string()
    }
    fn rust_params(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        hash_from_pairs(&ruby, &self.inner.params)
    }
    fn rust_headers(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        hash_from_pairs(&ruby, &self.inner.headers)
    }
}

pub(crate) fn hash_from_pairs(ruby: &Ruby, pairs: &[(String, String)]) -> Result<RHash, Error> {
    let h = ruby.hash_new();
    for (k, v) in pairs {
        h.aset(k.as_str(), v.as_str())?;
    }
    Ok(h)
}

pub fn init(ruby: &Ruby, parent: &RModule) -> Result<(), Error> {
    let class = parent.define_class("Uri", ruby.class_object())?;
    class.define_singleton_method("parse", function!(Uri::parse, 1))?;
    class.define_singleton_method("parse_many", function!(Uri::parse_many, 1))?;
    class.define_method("param", method!(Uri::param, 1))?;
    class.define_method("header", method!(Uri::header, 1))?;
    class.define_method("scheme", method!(Uri::scheme, 0))?;
    class.define_method("user", method!(Uri::user, 0))?;
    class.define_method("password", method!(Uri::password, 0))?;
    class.define_method("host", method!(Uri::host, 0))?;
    class.define_method("port", method!(Uri::port, 0))?;
    class.define_method("transport", method!(Uri::transport, 0))?;
    class.define_method("aor", method!(Uri::aor, 0))?;
    class.define_method("host_port", method!(Uri::host_port, 0))?;
    class.define_method("bracket_host", method!(Uri::bracket_host, 0))?;
    class.define_method("_rust_to_s", method!(Uri::rust_to_s, 0))?;
    class.define_method("_rust_params", method!(Uri::rust_params, 0))?;
    class.define_method("_rust_headers", method!(Uri::rust_headers, 0))?;
    Ok(())
}
