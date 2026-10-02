# Run from examples/host; creates only this example's data/demo.db.
require 'bundler/setup'
require 'fileutils'
require 'sequel'
FileUtils.mkdir_p(%w[data log tmp])
Sequel.extension :migration
db = Sequel.sqlite('data/demo.db')
Sequel::Migrator.run(db, File.join(Gem::Specification.find_by_name('inferno_core').full_gem_path, 'lib/inferno/db/migrations'))
if db[:test_sessions].empty?
  now = Time.now
  db[:test_sessions].insert(id: 'example', test_suite_id: 'session_browser_demo', suite_options: '[]', created_at: now, updated_at: now)
end
db.disconnect
puts 'Example ready. Start with: ASYNC_JOBS=false bundle exec rackup -p 4568'
