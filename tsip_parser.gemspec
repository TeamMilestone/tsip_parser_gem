# frozen_string_literal: true

require_relative "lib/tsip_parser/version"

Gem::Specification.new do |spec|
  spec.name     = "tsip_parser"
  spec.version  = TsipParser::VERSION
  spec.authors  = ["Team Milestone"]
  spec.email    = ["dev@team-milestone.io"]

  spec.summary     = "RFC 3261 SIP URI and Address parser for Ruby, powered by Rust."
  spec.description = "Thin Ruby binding around the tsip-parser Rust crate. " \
                     "Provides RFC 3261 §19.1 (SIP URI) and §25.1 (Address) " \
                     "parsing and serialization at ~25-35× the speed of the " \
                     "pure-Ruby reference in tsip-core."
  spec.homepage    = "https://github.com/TeamMilestone/tsip_parser_gem"
  spec.license     = "MIT"
  spec.required_ruby_version     = ">= 3.0.0"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    ext/**/*.{rs,toml,rb}
    sig/**/*.rbs
    CHANGELOG.md
    LICENSE
    README.md
    Cargo.toml
    Cargo.lock
    Rakefile
  ])
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/tsip_parser/extconf.rb"]

  spec.add_dependency "rb_sys", "~> 0.9.91"
end
