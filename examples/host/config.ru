require 'bundler/setup'
require 'inferno'
require 'inferno_session_browser'
Inferno::Application.finalize!
use Rack::Static, urls: Inferno::Utils::StaticAssets.static_assets_map, root: Inferno::Utils::StaticAssets.inferno_path
run Inferno::Web.app
