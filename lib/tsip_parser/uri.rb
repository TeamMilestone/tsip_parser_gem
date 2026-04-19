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
        buf << u
        pw = password
        buf << ":" << pw if pw
        buf << "@"
      end
      append_bracket_host(buf)
      p = port
      buf << ":" << p.to_s if p
      params.each do |k, v|
        buf << ";" << k
        vs = v.to_s
        buf << "=" << vs unless vs.empty?
      end
      h = headers
      unless h.empty?
        buf << "?"
        first = true
        h.each do |k, v|
          buf << "&" unless first
          first = false
          buf << k << "=" << v.to_s
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
