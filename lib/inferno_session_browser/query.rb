# frozen_string_literal: true
require 'json'
require 'sequel'
require 'uri'
require 'time'
require_relative 'parameters'
require_relative 'registry'

module InfernoSessionBrowser
  class Query
    ACTIVE_STATES = %w[queued running waiting cancelling].freeze
    RESULT_STATES = %w[pass fail skip error omit cancel wait running].freeze
    BATCH_SIZE = 500

    def initialize(db:, configuration:, base_path: '', registry: Registry.new)
      @db, @configuration, @registry = db, configuration, registry
      @base_path = normalize_base(base_path)
    end

    def sessions(raw)
      parameters = Parameters.new(raw)
      dataset, bindings = filtered_sessions(parameters)
      rows, total = session_page(dataset, bindings, parameters)
      ids = rows.map { |row| row[:id] }
      urls = fhir_urls(ids)
      counts = result_counts(@db[:results].where(test_session_id: ids), :test_session_id)
      data = rows.map do |row|
        suite = @registry.suite(row[:test_suite_id])
        {
          id: row[:id], suite_id: suite&.id || row[:test_suite_id],
          suite_title: suite&.title || row[:test_suite_id], suite_available: !suite.nil?,
          suite_options: display_options(row[:suite_options], suite), fhir_url: urls[row[:id]],
          created_at: timestamp(row[:created_at]), latest_activity: timestamp(row[:latest_activity]),
          state: row[:state], run_count: row[:run_count].to_i,
          result_counts: counts.fetch(row[:id], empty_counts),
          session_url: suite ? "#{@base_path}/#{encode(suite.id)}/#{encode(row[:id])}" : nil
        }
      end
      { data: data, pagination: parameters.metadata(total) }
    end

    def options
      suites = {}
      selections = Hash.new { |hash, key| hash[key] = {} }
      each_batch(@db[:test_sessions].select(:id, :test_suite_id, :suite_options).order(:id), {}) do |rows|
        rows.each do |row|
          suite = @registry.suite(row[:test_suite_id])
          suites[row[:test_suite_id]] ||= { id: row[:test_suite_id], title: suite&.title || row[:test_suite_id] }
          display_options(row[:suite_options], suite).each do |option|
            key = option[:id]
            selections[key][:title] ||= option[:title]
            selections[key][:values] ||= {}
            selections[key][:values][option[:value]] ||= option[:label]
          end
        end
      end
      {
        suites: suites.values.sort_by { |suite| [suite[:title].to_s.downcase, suite[:id]] },
        suite_options: selections.sort.map do |id, option|
          { id: id, title: option[:title], values: option[:values].sort.map { |value, label| { value: value, label: label } } }
        end,
        states: Parameters::STATES
      }
    end

    def runs(session_id, raw)
      raise NotFound, 'Session not found' unless @db[:test_sessions].where(id: :$id).call(:first, id: session_id)
      parameters = Parameters.new(raw, history: true)
      dataset = @db[:test_runs].where(test_session_id: :$session_id)
      bindings = { session_id: session_id }
      total = dataset.select(Sequel.function(:count, Sequel.lit('*')).as(:total)).call(:first, bindings)[:total]
      rows = dataset.select(:id, :status, :created_at, :updated_at, :test_suite_id, :test_group_id, :test_id)
                    .order(Sequel.desc(:created_at), Sequel.desc(:id))
                    .limit(parameters.page_size, parameters.offset).call(:select, bindings)
      ids = rows.map { |row| row[:id] }
      counts = result_counts(@db[:results].where(test_run_id: ids), :test_run_id)
      # Select only outcome metadata; messages, input/output JSON, and requests are never loaded.
      outcomes = if rows.empty?
                   {}
                 else
                   conditions = rows.map { |row| { test_run_id: row[:id], target(row).last => row[target(row).last] } }
                   @db[:results].where(Sequel.|(*conditions))
                     .select(:test_run_id, :result, row_number(:test_run_id).as(:position))
                     .from_self.where(position: 1).all.to_h { |result| [result[:test_run_id], result[:result]] }
                 end
      data = rows.map do |row|
        type, column = target(row)
        id = row[column]
        runnable = @registry.runnable(type, id)
        { id: row[:id], status: row[:status], created_at: timestamp(row[:created_at]),
          updated_at: timestamp(row[:updated_at]),
          target: { type: type, id: runnable&.id || id, title: runnable&.title || id },
          outcome: outcomes[row[:id]], result_counts: counts.fetch(row[:id], empty_counts) }
      end
      { data: data, pagination: parameters.metadata(total) }
    end

    private

    def base_sessions
      s = Sequel[:test_sessions]
      statistics = @db[:test_runs].group(:test_session_id)
                      .select(:test_session_id, Sequel.function(:count, Sequel.lit('*')).as(:run_count),
                              Sequel.function(:max, :updated_at).as(:run_activity))
      activity = @db[:results].group(:test_session_id)
                    .select(:test_session_id, Sequel.function(:max, :updated_at).as(:result_activity))
      active = @db[:test_runs].where(status: ACTIVE_STATES)
                  .select(:test_session_id, :status, row_number(:test_session_id).as(:position))
                  .from_self.where(position: 1)
      latest = [Sequel[:run_stats][:run_activity], Sequel[:result_stats][:result_activity]]
               .reduce(s[:created_at]) { |maximum, date| Sequel.case({ (date > maximum) => date }, maximum) }
      state = Sequel.case({ Sequel.~(Sequel[:active_run][:status] => nil) => Sequel[:active_run][:status],
                            { Sequel[:run_stats][:run_count] => nil } => 'never_run' }, 'idle')
      @db[:test_sessions]
        .left_join(statistics, { Sequel[:run_stats][:test_session_id] => s[:id] }, table_alias: :run_stats)
        .left_join(activity, { Sequel[:result_stats][:test_session_id] => s[:id] }, table_alias: :result_stats)
        .left_join(active, { Sequel[:active_run][:test_session_id] => s[:id] }, table_alias: :active_run)
        .select(s[:id], s[:test_suite_id], s[:suite_options], s[:created_at],
                Sequel[:run_stats][:run_count], latest.as(:latest_activity), state.as(:state))
        .from_self(alias: :session_summary)
    end

    def filtered_sessions(parameters)
      filters = parameters.filters
      dataset = base_sessions
      bindings = {}
      if filters['q']
        dataset = dataset.where(Sequel.ilike(:id, :$q))
        bindings[:q] = "%#{filters['q'].gsub(/[\\%_]/) { |char| "\\#{char}" }}%"
      end
      { 'suite_id' => :test_suite_id, 'state' => :state }.each do |key, column|
        next unless filters[key]
        dataset = dataset.where(column => :"$#{key}")
        bindings[key.to_sym] = filters[key]
      end
      { 'from' => :>=, 'to' => :< }.each do |key, comparison|
        next unless filters[key]
        dataset = dataset.where(Sequel[filters['date_field'].to_sym].public_send(comparison, :"$#{key}"))
        bindings[key.to_sym] = filters[key]
      end
      column = parameters.sort == 'suite' ? :test_suite_id : parameters.sort.to_sym
      order = parameters.direction == 'asc' ? Sequel.asc(column) : Sequel.desc(column)
      [dataset.order(order, Sequel.asc(:id)), bindings]
    end

    def session_page(dataset, bindings, parameters)
      filters = parameters.filters
      if filters['suite_options'].empty? && !filters['fhir_url']
        total = dataset.unordered.select(Sequel.function(:count, Sequel.lit('*')).as(:total)).call(:first, bindings)[:total]
        return [dataset.limit(parameters.page_size, parameters.offset).call(:select, bindings), total]
      end

      # Option JSON and URLs are normalized in Ruby for identical SQLite/Postgres behavior.
      # Scan lightweight candidate metadata in bounded batches, retaining only the requested page.
      # This also ensures URL filters cannot match hidden userinfo/query/fragment secrets.
      page = []
      total = 0
      each_batch(dataset, bindings) do |rows|
        urls = filters['fhir_url'] ? fhir_urls(rows.map { |row| row[:id] }) : {}
        rows.each do |row|
          options = parse_options(row[:suite_options]).to_h { |option| [option['id'].to_s, option['value'].to_s] }
          next unless filters['suite_options'].all? { |key, value| options[key] == value }
          next if filters['fhir_url'] && !urls[row[:id]].to_s.downcase.include?(filters['fhir_url'].downcase)
          page << row if total >= parameters.offset && page.length < parameters.page_size
          total += 1
        end
      end
      [page, total]
    end

    def each_batch(dataset, bindings)
      offset = 0
      loop do
        rows = dataset.limit(BATCH_SIZE, offset).call(:select, bindings)
        break if rows.empty?
        yield rows
        break if rows.length < BATCH_SIZE
        offset += BATCH_SIZE
      end
    end

    def fhir_urls(ids)
      return {} if ids.empty?
      candidates = @db[:session_data].where(test_session_id: ids, name: @configuration.fhir_url_input_names)
                      .select(:test_session_id, :name, :value).all.group_by { |row| row[:test_session_id] }
      candidates.transform_values do |rows|
        @configuration.fhir_url_input_names.lazy.map do |name|
          value = rows.find { |row| row[:name] == name }&.fetch(:value)
          sanitized_url(value)
        end.find { |value| !value.nil? }
      end
    end

    def sanitized_url(value)
      return nil unless value.is_a?(String)
      uri = URI.parse(value.strip)
      return nil unless %w[http https].include?(uri.scheme&.downcase) && uri.host
      # URI#userinfo = nil does not clear existing user/password in all Ruby versions.
      # Rebuild from an explicit allowlist instead of mutating the original URI.
      type = uri.scheme.downcase == 'https' ? URI::HTTPS : URI::HTTP
      type.build(host: uri.host, port: uri.port, path: uri.path).normalize.to_s
    rescue URI::InvalidURIError, URI::InvalidComponentError
      nil
    end

    def result_counts(dataset, partition)
      ranked = dataset.exclude(test_id: nil)
                      .select(partition, :result, row_number([partition, :test_id]).as(:position)).from_self
      ranked.where(position: 1).group(partition, :result)
            .select(partition, :result, Sequel.function(:count, Sequel.lit('*')).as(:total))
            .all.each_with_object({}) do |row, counts|
        counts[row[partition]] ||= empty_counts
        counts[row[partition]][row[:result]] = row[:total] if RESULT_STATES.include?(row[:result])
      end
    end

    def row_number(partition)
      Sequel.function(:row_number).over(partition: partition,
                                       order: [Sequel.desc(:updated_at), Sequel.desc(:created_at), Sequel.desc(:id)])
    end

    def empty_counts
      RESULT_STATES.to_h { |state| [state, 0] }
    end

    def parse_options(value)
      parsed = JSON.parse(value || '[]')
      parsed.is_a?(Array) ? parsed.select { |option| option.is_a?(Hash) && option['id'] && option.key?('value') } : []
    rescue JSON::ParserError, TypeError
      []
    end

    def display_options(value, suite)
      parse_options(value).map do |selected|
        definition = suite&.suite_options&.find { |option| option.id.to_s == selected['id'].to_s }
        choice = definition&.list_options&.find { |option| option[:value].to_s == selected['value'].to_s }
        { id: selected['id'].to_s, title: definition&.title || selected['id'].to_s,
          value: selected['value'].to_s, label: choice&.fetch(:label, nil) || selected['value'].to_s }
      end
    end

    def target(row)
      return ['test', :test_id] if row[:test_id]
      return ['group', :test_group_id] if row[:test_group_id]
      ['suite', :test_suite_id]
    end

    def timestamp(value)
      value = @db.to_application_timestamp(value) if value.is_a?(String)
      value&.to_time&.utc&.iso8601(3)
    end

    def encode(value)
      URI.encode_www_form_component(value.to_s).gsub('+', '%20')
    end

    def normalize_base(path)
      path.to_s.split('/').reject(&:empty?).map { |part| "/#{part}" }.join
    end
  end
end
