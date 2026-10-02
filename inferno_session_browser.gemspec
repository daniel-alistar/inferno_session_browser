# frozen_string_literal: true

require_relative 'lib/inferno_session_browser/version'

Gem::Specification.new do |spec|
  spec.name = 'inferno_session_browser'
  spec.version = InfernoSessionBrowser::VERSION
  spec.authors = ['Daniel Alistar']
  spec.summary = 'A read-only session browser for the Inferno Framework'
  spec.description = 'Adds a paginated session dashboard and run history to an existing Inferno host on require.'
  spec.license = 'Apache-2.0'
  repository = 'https://github.com/daniel-alistar/inferno_session_browser'
  spec.homepage = repository
  spec.metadata = {
    'source_code_uri' => repository,
    'documentation_uri' => "#{repository}/blob/main/README.md",
    'bug_tracker_uri' => "#{repository}/issues",
    'changelog_uri' => "#{repository}/blob/main/CHANGELOG.md",
    'allowed_push_host' => 'https://rubygems.org',
    'rubygems_mfa_required' => 'true'
  }
  spec.required_ruby_version = '>= 3.3.6'
  spec.files = Dir['lib/**/*', 'examples/**/*.rb', 'examples/**/*.ru', 'examples/**/*.yml', 'examples/**/Gemfile',
                   'README.md', 'RELEASING.md', 'LICENSE', 'NOTICE', 'CHANGELOG.md']
                   .select { |path| File.file?(path) }
  spec.require_paths = ['lib']
  spec.add_dependency 'inferno_core', '>= 1.4.0', '< 1.5'
  spec.add_dependency 'rack', '>= 2.2', '< 3'
  spec.add_dependency 'sequel', '~> 5.42'
end
