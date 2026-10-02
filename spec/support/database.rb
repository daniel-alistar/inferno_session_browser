# frozen_string_literal: true
require 'ostruct'

module BrowserDatabase
  NOW = Time.utc(2026, 10, 2, 10, 0, 0)
  class FakeRegistry
    def suite(id)
      return nil unless id == 'demo'
      OpenStruct.new(id: 'demo', title: 'Demonstration Suite', suite_options: [
        OpenStruct.new(id: :us_core_version, title: 'US Core Version', list_options: [{ value: '6', label: 'US Core 6.1.0' }])
      ])
    end

    def runnable(_type, id)
      id ? OpenStruct.new(id: id, title: "Target #{id}") : nil
    end
  end

  def create_browser_schema(db)
    %i[results session_data test_runs test_sessions].each { |table| db.drop_table?(table) }
    db.create_table(:test_sessions) do
      String :id, primary_key: true
      String :test_suite_id
      String :suite_options, text: true
      DateTime :created_at
      DateTime :updated_at
    end
    db.create_table(:test_runs) do
      String :id, primary_key: true
      String :test_session_id
      String :status
      String :test_suite_id
      String :test_group_id
      String :test_id
      DateTime :created_at
      DateTime :updated_at
      index [:test_session_id, :status]
    end
    db.create_table(:results) do
      String :id, primary_key: true
      String :test_session_id
      String :test_run_id
      String :test_suite_id
      String :test_group_id
      String :test_id
      String :result
      String :result_message
      String :input_json, text: true
      String :output_json, text: true
      DateTime :created_at
      DateTime :updated_at
      index [:test_session_id, :test_id]
      index :test_run_id
    end
    db.create_table(:session_data) do
      String :id, primary_key: true
      String :test_session_id
      String :name
      String :value, text: true
      index [:test_session_id, :name], unique: true
    end
  end

  def create_session(id = 's1', **extra)
    @db[:test_sessions].insert({ id: id, test_suite_id: 'demo', suite_options: '[]', created_at: NOW, updated_at: NOW }.merge(extra))
    id
  end

  def create_run(id = 'r1', **extra)
    @db[:test_runs].insert({ id: id, test_session_id: 's1', status: 'done', test_group_id: 'group', created_at: NOW, updated_at: NOW }.merge(extra))
    id
  end

  def create_result(id = 'result1', **extra)
    @db[:results].insert({ id: id, test_session_id: 's1', test_run_id: 'r1', test_id: 'test', result: 'pass', created_at: NOW, updated_at: NOW }.merge(extra))
    id
  end

  def save_input(name, value, session: 's1')
    @db[:session_data].insert(id: "#{session}_#{name}", test_session_id: session, name: name, value: value)
  end

  def query
    InfernoSessionBrowser::Query.new(db: @db, configuration: @configuration, registry: @registry)
  end
end
