# frozen_string_literal: true

require_relative 'lib/inferno_session_browser/version'

Gem::Specification.new do |spec|
  spec.name = 'inferno_session_browser'
  spec.version = InfernoSessionBrowser::VERSION
  spec.authors = ['Inferno Session Browser contributors']
  spec.summary = 'A read-only session browser for the Inferno Framework'
  spec.description = 'Adds a paginated session dashboard and run history to an existing Inferno host on require.'
  spec.license = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.3.6'
  spec.files = Dir['lib/**/*', 'examples/**/*.rb', 'examples/**/*.ru', 'examples/**/*.yml', 'examples/**/Gemfile',
                   'README.md', 'LICENSE', 'NOTICE', 'CHANGELOG.md']
                   .select { |path| File.file?(path) }
  spec.require_paths = ['lib']
  spec.add_dependency 'inferno_core', '>= 1.4.0', '< 1.5'
  spec.add_dependency 'rack', '>= 2.2', '< 3'
  spec.add_dependency 'sequel', '~> 5.42'
end
