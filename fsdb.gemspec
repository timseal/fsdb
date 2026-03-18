# frozen_string_literal: true

require_relative "lib/fsdb/version"

Gem::Specification.new do |spec|
  spec.name    = "fsdb"
  spec.version = Fsdb::VERSION
  spec.summary = "Filesystem catalogue with content-type and topic tagging"
  spec.authors = ["Tim Anderson"]
  spec.files   = Dir["lib/**/*.rb", "bin/*"]

  spec.bindir        = "bin"
  spec.executables   = ["fsdb"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "thor",            ">= 1.3"
  spec.add_dependency "sqlite3",         "~> 2.0"
  spec.add_dependency "tty-table",       ">= 0.12"
  spec.add_dependency "tty-tree",        ">= 0.4"
  spec.add_dependency "tty-progressbar", ">= 0.18"
  spec.add_dependency "pastel",          ">= 0.8"
  spec.add_dependency "faraday",         ">= 2.0"

  spec.add_development_dependency "rspec",         ">= 3.13"
  spec.add_development_dependency "rubocop",       ">= 1.60"
  spec.add_development_dependency "rubocop-rspec", ">= 2.27"
  spec.add_development_dependency "ruby-lsp",      ">= 0.17"
end
