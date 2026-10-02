# frozen_string_literal: true
# Uses installed development gems; CI also runs this matrix as separate jobs.
require 'rbconfig'
$stdout.sync = true
root = File.expand_path('..', __dir__)
databases = [['sqlite', nil]]
databases << ['postgres', ENV.fetch('TEST_DATABASE_URL')] unless ENV['TEST_DATABASE_URL'].to_s.empty?
success = true
%w[1.4.0 1.4.4].each do |version|
  databases.each do |name, url|
    puts "Checking Inferno Core #{version} / #{name}"
    passed = system({ 'INFERNO_CORE_VERSION' => version, 'TEST_DATABASE_URL' => url }, RbConfig.ruby,
                    '-I', File.join(root, 'lib'), '-I', File.join(root, 'spec'),
                    Gem.bin_path('rspec-core', 'rspec'), chdir: root)
    success &&= passed
  end
end
exit(success ? 0 : 1)
