# frozen_string_literal: true
RSpec.describe InfernoSessionBrowser::Query do
  it 'includes preexisting sessions, metadata, and links without treating them as certification verdicts' do
    create_session(suite_options: JSON.generate([{ id: 'us_core_version', value: '6' }]))
    row = query.sessions({})[:data].first
    expect(row).to include(id: 's1', state: 'never_run', run_count: 0, suite_title: 'Demonstration Suite', session_url: '/demo/s1')
    expect(row[:suite_options].first).to include(label: 'US Core 6.1.0')
    expect(row[:result_counts].values.sum).to eq(0)
    expect(row).not_to have_key(:certified)
  end

  %w[queued running waiting cancelling].each do |state|
    it "shows #{state} even if a newer run has completed" do
      create_session
      create_run('active', status: state)
      create_run('finished', updated_at: BrowserDatabase::NOW + 60)
      expect(query.sessions({})[:data].first).to include(state: state, run_count: 2)
    end
  end

  it 'uses the latest active run and keeps idle distinct from result outcomes' do
    create_session
    create_run('old', status: 'waiting')
    create_run('new', status: 'running', updated_at: BrowserDatabase::NOW + 1)
    expect(query.sessions({})[:data].first[:state]).to eq('running')
    @db[:test_runs].update(status: 'done')
    expect(query.sessions({})[:data].first[:state]).to eq('idle')
  end

  it 'counts the latest result per test across reruns, including optional tests and excluding parent results' do
    create_session
    create_run
    create_result('old-fail', result: 'fail')
    create_result('latest-pass', updated_at: BrowserDatabase::NOW + 1)
    create_result('optional', test_id: 'optional-test', result: 'skip')
    create_result('parent', test_id: nil, test_group_id: 'group', result: 'fail')
    create_result('suite', test_id: nil, test_suite_id: 'demo', result: 'fail')
    row = query.sessions({})[:data].first
    expect(row[:result_counts]).to include('pass' => 1, 'skip' => 1, 'fail' => 0)
    expect(row[:result_counts].values.sum).to eq(2)
    expect(row[:latest_activity]).to eq((BrowserDatabase::NOW + 1).iso8601(3))
  end

  it 'uses result timestamps for activity and deterministic IDs to break equal timestamp ties' do
    create_session('b')
    create_session('a')
    expect(query.sessions({})[:data].map { |row| row[:id] }).to eq(%w[a b])
    create_result(test_session_id: 'b', updated_at: BrowserDatabase::NOW + 120)
    expect(query.sessions({})[:data].first[:id]).to eq('b')
  end

  it 'combines ID, suite, run state, option, sanitized URL, and exclusive date range filters' do
    create_session('matching', suite_options: '[{"id":"us_core_version","value":"6"}]')
    create_session('other')
    create_run(test_session_id: 'matching', status: 'running')
    save_input('url', 'https://user:secret@EXAMPLE.org:8443/fhir?token=hidden#private', session: 'matching')
    response = query.sessions('q' => 'match', 'suite_id' => 'demo', 'state' => 'running', 'suite_options' => { 'us_core_version' => '6' },
                              'fhir_url' => 'example.org', 'from' => (BrowserDatabase::NOW - 1).iso8601, 'to' => (BrowserDatabase::NOW + 1).iso8601)
    expect(response[:pagination][:total]).to eq(1)
    expect(response[:data].first[:fhir_url]).to eq('https://example.org:8443/fhir')
    expect(JSON.generate(response)).not_to match(/secret|token|hidden|private|user:/)
    expect(query.sessions('fhir_url' => 'hidden')[:pagination][:total]).to eq(0)
    expect(query.sessions('to' => BrowserDatabase::NOW.iso8601)[:pagination][:total]).to eq(0)
  end

  it 'treats SQL metacharacters and LIKE wildcards as search text' do
    create_session('normal')
    create_session('with%value')
    expect(query.sessions('q' => '%')[:data].map { |row| row[:id] }).to eq(['with%value'])
    expect(query.sessions('suite_id' => "demo' OR 1=1 --")[:data]).to be_empty
  end

  it 'honors configured URL input priority and handles invalid URLs without exposing other inputs' do
    create_session
    save_input('custom_url', 'javascript:secret')
    save_input('url', 'https://example.org/fhir?secret=1')
    save_input('oauth_credentials', '{"access_token":"never-return"}')
    config = InfernoSessionBrowser::Configuration.new
    config.fhir_url_input_names = %w[custom_url url]
    instance = described_class.new(db: @db, registry: @registry, configuration: config.snapshot)
    expect(instance.sessions({})[:data].first[:fhir_url]).to eq('https://example.org/fhir')
    @db[:session_data].where(name: 'custom_url').update(value: 'https://priority.example/fhir')
    expect(instance.sessions({})[:data].first[:fhir_url]).to eq('https://priority.example/fhir')
    expect(JSON.generate(instance.sessions({}))).not_to include('never-return')
  end

  it 'keeps unavailable suites and malformed option metadata browsable' do
    create_session(test_suite_id: 'removed-suite', suite_options: 'not json')
    expect(query.sessions({})[:data].first).to include(suite_title: 'removed-suite', suite_available: false, session_url: nil, suite_options: [])
    expect(query.options[:suites]).to include(id: 'removed-suite', title: 'removed-suite')
  end

  it 'offers persisted suite option values and loaded labels for filters' do
    create_session(suite_options: '[{"id":"us_core_version","value":"6"}]')
    expect(query.options[:suite_options]).to include(id: 'us_core_version', title: 'US Core Version', values: [{ value: '6', label: 'US Core 6.1.0' }])
  end

  it 'paginates a large dataset and only summarizes individual results for the selected page' do
    @db[:test_sessions].multi_insert(Array.new(1200) { |index| { id: format('session%04d', index), test_suite_id: 'demo', suite_options: '[]', created_at: BrowserDatabase::NOW, updated_at: BrowserDatabase::NOW } })
    create_result(test_session_id: 'session1199', input_json: 'sensitive payload', output_json: 'large payload')
    log = StringIO.new
    @db.loggers << Logger.new(log)
    response = query.sessions('page' => '2', 'page_size' => '25', 'sort' => 'created_at', 'direction' => 'asc')
    expect(response[:data].length).to eq(25)
    expect(response[:data].first[:id]).to eq('session0025')
    expect(response[:pagination][:total]).to eq(1200)
    expect(response[:data].sum { |row| row[:result_counts].values.sum }).to eq(0)
    expect(log.string).not_to match(/SELECT .*\b(?:input_json|output_json|result_message)\b/i)
  end

  it 'paginates normalized metadata filters across batches' do
    @db[:test_sessions].multi_insert(Array.new(600) { |index| { id: format('s%04d', index), test_suite_id: 'demo', suite_options: '[{"id":"us_core_version","value":"6"}]', created_at: BrowserDatabase::NOW, updated_at: BrowserDatabase::NOW } })
    response = query.sessions('suite_options' => { 'us_core_version' => '6' }, 'page' => '24')
    expect(response[:pagination][:total]).to eq(600)
    expect(response[:data].length).to eq(25)
    expect(response[:data].first[:id]).to eq('s0575')
  end

  it 'returns run targets and outcomes with counts scoped to each run' do
    create_session
    create_run('r1')
    create_run('r2', test_group_id: nil, test_id: 'test', created_at: BrowserDatabase::NOW + 1)
    create_result('r1fail', result: 'fail')
    create_result('r1root', test_id: nil, test_group_id: 'group', result: 'fail')
    create_result('r2pass', test_run_id: 'r2', result: 'pass')
    response = query.runs('s1', {})
    expect(response[:data].map { |row| row[:id] }).to eq(%w[r2 r1])
    expect(response[:data].map { |row| row[:outcome] }).to eq(%w[pass fail])
    expect(response[:data].first[:target]).to include(type: 'test', id: 'test')
    expect(response[:data].first[:result_counts]).to include('pass' => 1, 'fail' => 0)
  end

  it 'returns empty and out-of-range pages and rejects an unknown session' do
    expect(query.sessions({})).to include(data: [], pagination: { page: 1, page_size: 25, total: 0 })
    create_session
    expect(query.sessions('page' => '999')[:data]).to be_empty
    expect(query.runs('s1', {})[:data]).to be_empty
    expect { query.runs('unknown', {}) }.to raise_error(InfernoSessionBrowser::NotFound)
  end
end
