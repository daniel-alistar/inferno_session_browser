# frozen_string_literal: true
RSpec.describe InfernoSessionBrowser::Configuration do
  it 'validates and snapshots configuration without changing a constructed app' do
    configuration = described_class.new
    first = configuration.snapshot
    configuration.mount_path = '/history/'
    configuration.fhir_url_input_names = %w[FHIR_URL url]
    expect(configuration.snapshot.mount_path).to eq('/history')
    expect(configuration.snapshot.fhir_url_input_names).to eq(%w[fhir_url url])
    expect(first.mount_path).to eq('/sessions')
    expect(first).to be_frozen
  end
  it 'rejects a root mount, unsafe paths, and empty URL input names' do
    configuration = described_class.new
    ['/', 'relative', '/api?x=1', '/foo/../bar'].each do |path|
      configuration.mount_path = path
      expect { configuration.snapshot }.to raise_error(ArgumentError)
    end
    configuration.mount_path = '/sessions'
    configuration.fhir_url_input_names = []
    expect { configuration.snapshot }.to raise_error(ArgumentError)
  end
end
