# frozen_string_literal: true
module InfernoSessionBrowser
  class Configuration
    attr_accessor :mount_path, :fhir_url_input_names

    def initialize
      @mount_path = '/sessions'
      @fhir_url_input_names = ['url']
    end

    def snapshot
      path = mount_path.to_s.sub(%r{/+\z}, '')
      unless path.match?(%r{\A/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\z})
        raise ArgumentError, 'mount_path must be a non-root path containing letters, numbers, underscores, or hyphens'
      end
      names = Array(fhir_url_input_names).map { |name| name.to_s.downcase }.uniq
      raise ArgumentError, 'fhir_url_input_names must contain at least one nonempty input name' if names.empty? || names.any?(&:empty?)

      copy = dup
      copy.mount_path = path.freeze
      copy.fhir_url_input_names = names.map(&:freeze).freeze
      copy.freeze
    end
  end
end
