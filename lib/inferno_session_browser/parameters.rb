# frozen_string_literal: true
require 'time'

module InfernoSessionBrowser
  class InvalidParameters < StandardError; end
  class NotFound < StandardError; end

  class Parameters
    STATES = %w[never_run queued running waiting cancelling idle].freeze
    SORTS = %w[latest_activity created_at suite].freeze
    KEYS = %w[page page_size q suite_id suite_options fhir_url state date_field from to sort direction].freeze
    attr_reader :page, :page_size, :filters, :sort, :direction

    def initialize(raw, history: false)
      unknown = raw.keys - (history ? %w[page page_size] : KEYS)
      raise InvalidParameters, "Unknown parameter: #{unknown.first}" unless unknown.empty?

      @page = integer(raw.fetch('page', '1'), 'page')
      @page_size = integer(raw.fetch('page_size', '25'), 'page_size')
      raise InvalidParameters, 'page_size must be 25, 50, or 100' unless [25, 50, 100].include?(@page_size)
      @sort = scalar(raw.fetch('sort', 'latest_activity'), 'sort')
      @direction = scalar(raw.fetch('direction', 'desc'), 'direction')
      raise InvalidParameters, 'Invalid sort field' unless SORTS.include?(@sort)
      raise InvalidParameters, 'direction must be asc or desc' unless %w[asc desc].include?(@direction)

      @filters = raw.slice('q', 'suite_id', 'fhir_url', 'state', 'date_field').transform_values do |value|
        scalar(value, 'filter')
      end
      @filters.reject! { |_key, value| value.empty? }
      state = @filters['state']
      raise InvalidParameters, 'Invalid run state' if state && !STATES.include?(state)
      date_field = @filters.fetch('date_field', 'created_at')
      raise InvalidParameters, 'date_field must be created_at or latest_activity' unless %w[created_at latest_activity].include?(date_field)
      @filters['date_field'] = date_field
      %w[from to].each { |key| @filters[key] = timestamp(raw[key], key) if raw[key] && raw[key] != '' }
      if @filters['from'] && @filters['to'] && @filters['from'] >= @filters['to']
        raise InvalidParameters, 'from must be earlier than to'
      end
      options = raw.fetch('suite_options', {})
      raise InvalidParameters, 'suite_options must be an object of option IDs and values' unless options.is_a?(Hash)
      @filters['suite_options'] = options.each_with_object({}) do |(key, value), selected|
        raise InvalidParameters, 'Invalid suite option ID' unless key.match?(/\A[a-zA-Z0-9_-]+\z/)
        selected[key] = scalar(value, 'suite option') unless value == ''
      end
    end

    def offset
      (page - 1) * page_size
    end

    def metadata(total)
      { page: page, page_size: page_size, total: total }
    end

    private

    def scalar(value, name)
      raise InvalidParameters, "#{name} must be a string" unless value.is_a?(String)
      raise InvalidParameters, "#{name} is too long" if value.length > 2048
      value
    end

    def integer(value, name)
      text = scalar(value, name)
      raise InvalidParameters, "#{name} must be a positive integer" unless text.match?(/\A[1-9]\d{0,8}\z/)
      text.to_i
    end

    def timestamp(value, name)
      text = scalar(value, name)
      unless text.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
        raise InvalidParameters, "#{name} must be an ISO 8601 timestamp with a timezone"
      end
      Time.iso8601(text).utc
    rescue ArgumentError
      raise InvalidParameters, "#{name} must be an ISO 8601 timestamp with a timezone"
    end
  end
end
