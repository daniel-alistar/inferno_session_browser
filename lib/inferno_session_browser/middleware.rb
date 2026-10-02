# frozen_string_literal: true
require 'rack'
require 'erb'
require 'json'
require_relative 'query'

module InfernoSessionBrowser
  class Middleware
    ASSETS = { 'app.js' => 'application/javascript; charset=utf-8', 'app.css' => 'text/css; charset=utf-8' }.freeze

    def initialize(app, configuration:, base_path: '', db: nil, registry: Registry.new)
      @app, @configuration, @db, @registry = app, configuration, db, registry
      @base_path = base_path.to_s.split('/').reject(&:empty?).map { |part| "/#{part}" }.join
      @mount_path = "#{@base_path}#{configuration.mount_path}"
      @template = ERB.new(File.read(File.join(__dir__, 'templates/index.html.erb')))
      @assets = ASSETS.to_h { |name, type| [name, [type, File.binread(File.join(__dir__, 'assets', name)).freeze]] }.freeze
    end

    def call(env)
      path = env['PATH_INFO'].to_s
      return @app.call(env) unless path == @mount_path || path == "#{@mount_path}/" || path.start_with?("#{@mount_path}/api/", "#{@mount_path}/assets/")
      response = browser_response(path, env)
      env['REQUEST_METHOD'] == 'HEAD' ? [response[0], response[1], []] : response
    end

    private

    def browser_response(path, env)
      return json(405, { error: 'Only GET and HEAD are supported' }, 'Allow' => 'GET, HEAD') unless %w[GET HEAD].include?(env['REQUEST_METHOD'])
      dispatch(path, env)
    rescue InvalidParameters, Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError, Rack::QueryParser::ParamsTooDeepError => e
      json(400, { error: e.message })
    rescue NotFound => e
      json(404, { error: e.message })
    rescue StandardError => e
      # Host logging receives the class only, never SQL, session data, or URL credentials.
      log_failure(e)
      json(500, { error: 'Unable to load sessions. Please try again.' })
    end

    def log_failure(error)
      return unless defined?(Inferno::Application)
      Inferno::Application['logger']&.error("inferno_session_browser request failed: #{error.class}")
    rescue StandardError
      nil
    end

    def dispatch(path, env)
      if path == @mount_path || path == "#{@mount_path}/"
        return [200, { 'Content-Type' => 'text/html; charset=utf-8', 'Cache-Control' => 'no-store',
                       'Content-Security-Policy' => "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'",
                       'X-Content-Type-Options' => 'nosniff' }, [@template.result_with_hash(mount_path: @mount_path, version: VERSION)]]
      end
      ASSETS.each_key do |name|
        next unless path == "#{@mount_path}/assets/#{VERSION}/#{name}"
        type, content = @assets.fetch(name)
        return [200, { 'Content-Type' => type, 'Cache-Control' => 'public, max-age=31536000, immutable',
                       'X-Content-Type-Options' => 'nosniff' }, [content]]
      end
      request = Rack::Request.new(env)
      parameters = request.GET
      case path
      when "#{@mount_path}/api/sessions"
        json(200, query.sessions(parameters))
      when "#{@mount_path}/api/options"
        raise InvalidParameters, 'Options endpoint does not accept parameters' unless parameters.empty?
        json(200, query.options)
      else
        match = path.match(%r{\A#{Regexp.escape(@mount_path)}/api/sessions/([^/]+)/runs\z})
        return json(404, { error: 'Browser route not found' }) unless match
        session_id = Rack::Utils.unescape_path(match[1]).force_encoding(Encoding::UTF_8)
        raise InvalidParameters, 'Invalid session ID encoding' unless session_id.valid_encoding?
        json(200, query.runs(session_id, parameters))
      end
    end

    def query
      Query.new(db: @db || Inferno::Application['db.connection'], configuration: @configuration,
                base_path: @base_path, registry: @registry)
    end

    def json(status, body, headers = {})
      [status, { 'Content-Type' => 'application/json; charset=utf-8', 'Cache-Control' => 'no-store',
                 'X-Content-Type-Options' => 'nosniff' }.merge(headers), [JSON.generate(body)]]
    end
  end
end
