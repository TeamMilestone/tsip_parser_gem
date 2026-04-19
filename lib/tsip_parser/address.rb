# frozen_string_literal: true

module TsipParser
  # `TsipParser::Address` wraps `tsip_parser::Address` via TypedData. Ruby
  # side memoizes the embedded URI, display name, and params Hash so
  # mutations (`addr.tag = "x"`, `addr.uri = Uri.parse(...)`, …) persist
  # across reads and are reflected in `to_s`.
  class Address
    def display_name
      return @display_name if defined?(@display_name)
      @display_name = _rust_display_name
    end

    def display_name=(v)
      @display_name = v
    end

    def uri
      return @uri if defined?(@uri)
      @uri = _rust_uri
    end

    def uri=(v)
      @uri = v
    end

    def params
      return @params if defined?(@params)
      @params = _rust_params
    end

    def tag
      # Fast path: if nobody has materialized @params yet, read directly
      # from the Rust Vec. Avoids building the whole Hash just to look up
      # one key — which is the common case (parsed Contact/To/From headers
      # are typically queried for tag and then dropped).
      return _rust_tag unless defined?(@params)
      @params["tag"]
    end

    def tag=(v)
      params["tag"] = v
    end

    def to_s
      return _rust_to_s unless defined?(@params) || defined?(@display_name) || defined?(@uri)
      out = +""
      append_to(out)
      out
    end

    def append_to(buf)
      dn = display_name
      buf << '"' << dn << '" ' if dn
      buf << "<"
      u = uri
      u.append_to(buf) if u
      buf << ">"
      params.each do |k, v|
        buf << ";" << k
        vs = v.to_s
        buf << "=" << vs unless vs.empty?
      end
      buf
    end
  end
end
