# frozen_string_literal: true
gem 'inferno_core', ENV.fetch('INFERNO_CORE_VERSION', '1.4.4')
require 'rspec'
require 'rack/test'
require 'sequel'
require 'json'
require 'stringio'
require 'logger'
require 'inferno_session_browser'
require_relative 'support/database'

RSpec.configure do |config|
  config.include BrowserDatabase
  config.order = :random
  config.before do
    @db = if !ENV['TEST_DATABASE_URL'].to_s.empty?
            Sequel.connect(ENV.fetch('TEST_DATABASE_URL'), max_connections: 1, timezone: :utc)
          else
            Sequel.sqlite(nil, timezone: :utc)
          end
    @db.timezone = :utc
    create_browser_schema(@db)
    @configuration = InfernoSessionBrowser::Configuration.new.snapshot
    @registry = BrowserDatabase::FakeRegistry.new
  end
  config.after { @db&.disconnect }
end
