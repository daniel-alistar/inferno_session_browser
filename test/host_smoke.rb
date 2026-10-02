# frozen_string_literal: true
# Boots a real Inferno host and database in a temporary directory; never uses the ONC installation.
require 'tmpdir'
require 'fileutils'
require 'yaml'
require 'json'
require 'sequel'
require 'rack/mock'
gem 'inferno_core', ENV.fetch('INFERNO_CORE_VERSION', '1.4.4')
Sequel.extension :migration

mode = ARGV.fetch(0, 'before')
if mode == 'worker'
  require 'inferno_session_browser'
  raise 'Web provider was loaded by the browser gem' if $LOADED_FEATURES.any? { |file| file.include?('/inferno/apps/web/') }
  raise 'Inferno container was initialized by the browser gem' if defined?(Inferno::Application)
  puts JSON.generate(worker_safe: true)
  exit
end

Dir.mktmpdir('inferno-browser-host') do |directory|
  Dir.chdir(directory) do
    %w[config lib data tmp log].each { |name| FileUtils.mkdir_p(name) }
    database = File.join(directory, 'data/host.db')
    File.write('config/database.yml', { 'production' => { 'adapter' => 'sqlite', 'database' => database, 'max_connections' => 1 } }.to_yaml)
    File.write('lib/demo.rb', <<~RUBY)
      class BrowserDemo < Inferno::TestSuite
        id :browser_demo
        title 'Browser Demonstration'
        test do
          id :example
          title 'Example test'
          run { }
        end
      end
    RUBY
    connection = Sequel.sqlite(database)
    migrations = File.join(Gem::Specification.find_by_name('inferno_core').full_gem_path, 'lib/inferno/db/migrations')
    Sequel::Migrator.run(connection, migrations)
    now = Time.now
    connection[:test_sessions].insert(id: 'existing', test_suite_id: 'browser_demo', suite_options: '[]', created_at: now, updated_at: now)
    connection.disconnect
    project = File.expand_path('..', __dir__)
    browser_dependency = if ENV['BROWSER_PACKAGED'] == '1'
                           "gem 'inferno_session_browser', '= 0.1.0'"
                         else
                           "gem 'inferno_session_browser', path: #{project.dump}"
                         end
    File.write('Gemfile', "source 'https://rubygems.org'\ngem 'inferno_core', #{ENV.fetch('INFERNO_CORE_VERSION', '1.4.4').dump}\ngem 'rack', #{Rack.release.dump}\ngem 'sequel', #{Sequel::VERSION.dump}\n#{browser_dependency}\n")
    ENV['BUNDLE_GEMFILE'] = File.join(directory, 'Gemfile')
    require 'bundler'
    Bundler.reset!
    Bundler.definition.resolve_with_cache!
    Bundler.setup
    ENV['APP_ENV'] = 'production'
    ENV['ASYNC_JOBS'] = 'false'
    ENV['BASE_PATH'] = '/inferno'
    ENV['INFERNO_HOST'] = 'http://localhost'
    ENV.delete('LOAD_DEV_SUITES')
    require 'inferno_session_browser' if mode == 'before'
    require 'inferno'
    Inferno::Application.finalize!
    require 'inferno_session_browser' if mode == 'after'
    require 'inferno_session_browser'
    app = Inferno::Web.app
    client = Rack::MockRequest.new(app)
    response = client.get('/inferno/sessions/api/sessions')
    raise "Browser API failed: #{response.status}: #{response.body}" unless response.status == 200
    body = JSON.parse(response.body)
    raise 'Historical session missing' unless body['data'].first['id'] == 'existing'
    raise 'Creation timestamp changed timezone' if (Time.iso8601(body['data'].first['created_at']).to_f - now.to_f).abs > 1
    raise 'Base path missing from session link' unless body['data'].first['session_url'] == '/inferno/browser_demo/existing'
    raise 'Original Inferno page failed' unless client.get('/inferno/browser_demo/existing').status == 200
    raise 'Packaged asset missing' unless client.get('/inferno/sessions/assets/0.1.0/app.js').status == 200
    count = Inferno::Web.singleton_class.ancestors.count { |ancestor| ancestor == InfernoSessionBrowser::WebAppExtension }
    raise 'Repeated require registered twice' unless count == 1
    puts JSON.generate(core_version: Inferno::VERSION, version: InfernoSessionBrowser::VERSION, mode: mode,
                       historical_sessions: body['pagination']['total'], activation_count: count,
                       library: $LOADED_FEATURES.find { |file| file.end_with?('/inferno_session_browser.rb') })
    Inferno::Application['db.connection'].disconnect
  end
end
