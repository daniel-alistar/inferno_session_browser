# frozen_string_literal: true
require 'open3'
require 'rbconfig'

RSpec.describe 'Require-only activation in a real Inferno host' do
  %w[before after worker].each do |mode|
    it "supports #{mode} load order without changing the host" do
      output, error, status = Open3.capture3(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__),
                                           File.expand_path('../test/host_smoke.rb', __dir__), mode)
      expect(status.success?).to be(true), "#{output}\n#{error}"
      result = JSON.parse(output.lines.last)
      if mode == 'worker'
        expect(result['worker_safe']).to be(true)
      else
        expect(result).to include('historical_sessions' => 1, 'activation_count' => 1)
      end
    end
  end
end
