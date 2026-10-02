# frozen_string_literal: true
RSpec.describe InfernoSessionBrowser::Middleware do
  include Rack::Test::Methods
  let(:delegate) { ->(_env) { [218, { 'Content-Type' => 'text/plain' }, ['original Inferno app']] } }
  let(:app) { described_class.new(delegate, configuration: @configuration, db: @db, registry: @registry) }
  let(:version) { InfernoSessionBrowser::VERSION }

  it 'serves the page and packaged versioned assets' do
    get '/sessions'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('Session Browser', "/sessions/assets/#{version}/app.js")
    get "/sessions/assets/#{version}/app.js"
    expect(last_response.status).to eq(200)
    expect(last_response.headers['Content-Type']).to include('javascript')
    expect(last_response.headers['Cache-Control']).to include('immutable')
    get "/sessions/assets/#{version}/app.css"
    expect(last_response.status).to eq(200)
    get "/sessions/assets/#{version}/../version.rb"
    expect(last_response.status).to eq(404)
  end

  it 'delegates original routes and similarly named paths' do
    ['/demo/s1', '/api/test_sessions', '/sessions-other', '/sessions/s1', '/custom/demo/endpoint'].each do |path|
      get path
      expect(last_response.status).to eq(218)
    end
  end

  it 'rejects writes and leaves stored data unchanged' do
    create_session
    %i[post put patch delete].each do |verb|
      public_send(verb, '/sessions/api/sessions')
      expect(last_response.status).to eq(405)
      expect(last_response.headers['Allow']).to eq('GET, HEAD')
    end
    expect(@db[:test_sessions].count).to eq(1)
  end

  it 'preserves exceptions from the original application' do
    original = ->(_env) { raise 'original exception' }
    browser = described_class.new(original, configuration: @configuration, db: @db, registry: @registry)
    expect { browser.call(Rack::MockRequest.env_for('/original')) }.to raise_error(RuntimeError, 'original exception')
  end

  it 'returns bodyless HEAD errors' do
    head '/sessions/api/sessions?page=invalid'
    expect(last_response.status).to eq(400)
    expect(last_response.body).to be_empty
  end

  it 'supports HEAD without a response body' do
    head '/sessions'
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_empty
  end

  it 'serves namespaced JSON and unknown session errors' do
    create_session
    get '/sessions/api/sessions'
    expect(JSON.parse(last_response.body)['pagination']['total']).to eq(1)
    expect(last_response.headers['Cache-Control']).to eq('no-store')
    get '/sessions/api/options'
    expect(last_response.status).to eq(200)
    get '/sessions/api/sessions/missing/runs'
    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)).to eq('error' => 'Session not found')
  end

  it 'returns JSON validation errors for malformed filters' do
    [{ page: '-1' }, { page_size: '1000' }, { state: 'done' }, { sort: 'input_json' }, { from: 'yesterday' },
     { from: '2026-10-03T00:00:00Z', to: '2026-10-02T00:00:00Z' }, { suite_options: 'string' }, { unknown: 'field' }].each do |input|
      get '/sessions/api/sessions', input
      expect(last_response.status).to eq(400), last_response.body
      expect(JSON.parse(last_response.body)).to have_key('error')
    end
  end

  it 'decodes path IDs as text so SQLite does not compare them as binary values' do
    create_session('session29')
    create_run(test_session_id: 'session29')
    get '/sessions/api/sessions/session29/runs', page: '1'
    expect(last_response.status).to eq(200), last_response.body
    expect(JSON.parse(last_response.body)['data'].first['id']).to eq('r1')
  end

  it 'returns an error while leaving the application available after a query failure' do
    allow_any_instance_of(InfernoSessionBrowser::Query).to receive(:sessions).and_raise(Sequel::DatabaseError, 'secret SQL')
    get '/sessions/api/sessions'
    expect(last_response.status).to eq(500)
    expect(last_response.body).not_to include('secret SQL')
    get '/demo/s1'
    expect(last_response.status).to eq(218)
  end

  context 'with a base path and a custom mount' do
    let(:app) do
      configuration = InfernoSessionBrowser::Configuration.new
      configuration.mount_path = '/history'
      described_class.new(delegate, configuration: configuration.snapshot, db: @db, registry: @registry, base_path: '/inferno/')
    end
    it 'uses the prefix for API, assets, and existing session links' do
      create_session
      get '/inferno/history'
      expect(last_response.body).to include("/inferno/history/assets/#{version}/app.js")
      get '/inferno/history/api/sessions'
      expect(JSON.parse(last_response.body)['data'].first['session_url']).to eq('/inferno/demo/s1')
      get '/sessions'
      expect(last_response.status).to eq(218)
    end
  end
end
