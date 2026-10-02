# frozen_string_literal: true

require 'inferno/version'
require_relative 'inferno_session_browser/version'
require_relative 'inferno_session_browser/configuration'
require_relative 'inferno_session_browser/middleware'

module InfernoSessionBrowser
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end

  module WebAppExtension
    def app
      original = super
      Middleware.new(original, configuration: InfernoSessionBrowser.configuration.snapshot,
                     base_path: Inferno::Application['base_path'].to_s)
    end
  end
end

# Defining this namespace does not load Inferno's web provider or database.
# The provider can define .app before or after this file is required.
module Inferno
  module Web
  end
end
Inferno::Web.singleton_class.prepend(InfernoSessionBrowser::WebAppExtension) unless
  Inferno::Web.singleton_class.ancestors.include?(InfernoSessionBrowser::WebAppExtension)
