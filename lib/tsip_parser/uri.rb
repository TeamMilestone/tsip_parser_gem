# frozen_string_literal: true

module TsipParser
  # `TsipParser::Uri` is a TypedData wrapper around a Rust `tsip_parser::Uri`.
  # Scalar accessors (`scheme`, `user`, …) are Rust methods defined by the
  # native extension. This file adds the Ruby-side concerns: memoizing
  # `params` / `headers` so mutations stick, plus serialization / equality.
  class Uri
    # Materialize the params Hash lazily. Once touched, subsequent reads —
    # and any in-place mutations — hit the cached ivar, so tsip-core-style
    # `uri.params["transport"] = "tls"` patterns keep working.
    def params
      return @params if defined?(@params)
      @params = _rust_params
    end

    def headers
      return @headers if defined?(@headers)
      @headers = _rust_headers
    end

    def to_s
      # Hot path: nothing has been touched, so the Rust-side `Display` impl
      # reproduces the canonical string without ever materializing a Hash.
      return _rust_to_s unless defined?(@params) || defined?(@headers)
      out = +""
      append_to(out)
      out
    end

    def append_to(buf)
      buf << scheme << ":"
      u = user
      if u
        Uri.append_pct_escaped(buf, u)
        pw = password
        if pw
          buf << ":"
          Uri.append_pct_escaped(buf, pw)
        end
        buf << "@"
      end
      append_bracket_host(buf)
      p = port
      buf << ":" << p.to_s if p
      params.each do |k, v|
        buf << ";"
        Uri.append_param_escaped(buf, k)
        vs = v.to_s
        unless vs.empty?
          buf << "="
          Uri.append_param_escaped(buf, vs)
        end
      end
      h = headers
      unless h.empty?
        buf << "?"
        first = true
        h.each do |k, v|
          buf << "&" unless first
          first = false
          Uri.append_pct_escaped(buf, k)
          buf << "="
          Uri.append_pct_escaped(buf, v.to_s)
        end
      end
      buf
    end

    def append_bracket_host(buf)
      h = host
      if h.include?(":") && !h.start_with?("[")
        buf << "[" << h << "]"
      else
        buf << h
      end
    end

    # Mirror crate 0.2.1's `append_pct_escaped` — used for fields that are
    # pct-decoded on parse (userinfo, URI header key/value). Uppercase hex
    # because re-parse re-decodes, so case doesn't affect the fixed point.
    PCT_ESCAPE_CHARS = "@:;?<>%&= \t\r\n"
    def self.append_pct_escaped(buf, src)
      src.each_char do |ch|
        if PCT_ESCAPE_CHARS.include?(ch)
          buf << format("%%%02X", ch.ord)
        else
          buf << ch
        end
      end
      buf
    end

    # Mirror crate 0.2.1's `append_param_escaped`. URI-level params are
    # stored literally (no pct-decode on parse), so only bytes that would
    # re-tokenize the URI body on re-parse need escaping. `%` is NOT
    # escaped here: the stored value already contains any `%` the user put
    # in, and escaping `%` would turn `%3c` into `%253c` on re-render.
    # Lowercase hex — on re-parse, `downcase_str` lowercases keys, so
    # matching case reaches a fixed point in one cycle rather than two.
    PARAM_ESCAPE_CHARS = ";?&=<>"
    def self.append_param_escaped(buf, src)
      src.each_char do |ch|
        if PARAM_ESCAPE_CHARS.include?(ch)
          buf << format("%%%02x", ch.ord)
        else
          buf << ch
        end
      end
      buf
    end

    def ==(other)
      other.is_a?(Uri) &&
        scheme == other.scheme && user == other.user &&
        host.downcase == other.host.downcase && port == other.port
    end

    def hash
      [scheme, user, host.downcase, port].hash
    end
    alias eql? ==
  end
end
