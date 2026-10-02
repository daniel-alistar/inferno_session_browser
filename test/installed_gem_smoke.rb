# frozen_string_literal: true
# Install the built package into a temporary gem home, then boot real hosts from it.
require 'rubygems/installer'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require 'json'

package = File.expand_path(ARGV.fetch(0) do
  gemspec = File.expand_path('../inferno_session_browser.gemspec', __dir__)
  File.join(File.dirname(gemspec), 'pkg', Gem::Specification.load(gemspec).file_name)
end)
dependency_paths = (Gem.path + Gem.loaded_specs.values.map(&:base_dir)).uniq
Dir.mktmpdir('inferno-browser-installed') do |home|
  installed_spec = Gem::Installer.at(package, install_dir: home, ignore_dependencies: true, wrappers: false).install
  %w[before after].each do |mode|
    environment = ENV.to_h.select { |name, _| name.start_with?('BUNDLE_') }.transform_values { nil }
    environment.merge!('GEM_HOME' => home, 'GEM_PATH' => ([home] + dependency_paths).uniq.join(File::PATH_SEPARATOR),
                       'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLER_SETUP' => nil,
                       'RUBYGEMS_GEMDEPS' => nil, 'BROWSER_PACKAGED' => '1',
                       'BROWSER_GEM_VERSION' => installed_spec.version.to_s)
    output, error, status = Open3.capture3(environment, RbConfig.ruby, File.join(__dir__, 'host_smoke.rb'), mode)
    raise "Installed gem verification failed:\n#{output}\n#{error}" unless status.success?
    result = JSON.parse(output.lines.last)
    unless result.fetch('version') == installed_spec.version.to_s
      raise "Loaded unexpected gem version: #{result.fetch('version')} (expected #{installed_spec.version})"
    end
    installed_root = File.realpath(home) + File::SEPARATOR
    unless File.realpath(result.fetch('library')).start_with?(installed_root)
      raise "Loaded source instead of installed package: #{result.fetch('library')}"
    end
    puts JSON.generate(result)
  end
end
