# frozen_string_literal: true

require "bundler/gem_tasks"
require "rb_sys/extensiontask"
require "rake/testtask"

task build: :compile

GEMSPEC = Gem::Specification.load("tsip_parser.gemspec")

RbSys::ExtensionTask.new("tsip_parser", GEMSPEC) do |ext|
  ext.lib_dir = "lib/tsip_parser"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task default: %i[compile test]
