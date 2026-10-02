# frozen_string_literal: true
gem 'inferno_core', ENV.fetch('INFERNO_CORE_VERSION', '1.4.4')
require 'inferno_session_browser'
require 'puma'
require 'sequel'
require_relative '../../spec/support/database'
include BrowserDatabase
@db = Sequel.sqlite
@db.timezone = :utc
create_browser_schema(@db)
@registry = BrowserDatabase::FakeRegistry.new
30.times do |index|
  create_session(format('session%02d', index), suite_options: '[{"id":"us_core_version","value":"6"}]', created_at: BrowserDatabase::NOW + index)
  save_input('url', "https://username:password@example.org/fhir?token=never_show#secret", session: format('session%02d', index))
end
create_run('active-run', test_session_id: 'session29', status: 'running')
create_result('passed-test', test_session_id: 'session29', test_run_id: 'active-run')
30.times { |index| create_run(format('history%02d', index), test_session_id: 'session29', created_at: BrowserDatabase::NOW + index) }
app = InfernoSessionBrowser::Middleware.new(->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['Original Inferno session']] },
                                           configuration: InfernoSessionBrowser::Configuration.new.snapshot,
                                           db: @db, registry: @registry)
server = Puma::Server.new(app)
server.add_tcp_listener('127.0.0.1', Integer(ENV.fetch('BROWSER_TEST_PORT', '4568')))
trap('TERM') { server.stop(true) }
trap('INT') { server.stop(true) }
server.run.join
