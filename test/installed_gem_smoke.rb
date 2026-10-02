# frozen_string_literal: true
# Install the built package into a temporary gem home, then boot real hosts from it.
require 'rubygems/installer'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require 'json'

package = File.expand_path(ARGV.fetch(0, 'pkg/inferno_session_browser-0.1.0.gem'))
dependency_paths = (Gem.path + Gem.loaded_specs.values.map(&:base_dir)).uniq
Dir.mktmpdir('inferno-browser-installed') do |home|
  Gem::Installer.at(package, install_dir: home, ignore_dependencies: true, wrappers: false).install
  %w[before after].each do |mode|
    environment = ENV.to_h.select { |name, _| name.start_with?('BUNDLE_') }.transform_values { nil }
    environment.merge!('GEM_HOME' => home, 'GEM_PATH' => ([home] + dependency_paths).uniq.join(File::PATH_SEPARATOR),
                       'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLER_SETUP' => nil,
                       'RUBYGEMS_GEMDEPS' => nil, 'BROWSER_PACKAGED' => '1')
    output, error, status = Open3.capture3(environment, RbConfig.ruby, File.join(__dir__, 'host_smoke.rb'), mode)
    raise "Installed gem verification failed:\n#{output}\n#{error}" unless status.success?
    result = JSON.parse(output.lines.last)
    installed_root = File.realpath(home) + File::SEPARATOR
    unless File.realpath(result.fetch('library')).start_with?(installed_root)
      raise "Loaded source instead of installed package: #{result.fetch('library')}"
    end
    puts JSON.generate(result)
  end
end
