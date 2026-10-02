# Inferno Session Browser

A read-only dashboard for sessions in an existing Inferno Framework instance. Loading the gem exposes `/sessions`; with `BASE_PATH=/inferno`, it exposes `/inferno/sessions`.

The browser reads existing sessions immediately. It shows test suites and selected versions, sanitized FHIR server URLs, dates, recorded run states, current result counts, and expandable run history. **Open session** links to Inferno's existing detail page. It does not run tests, cancel runs, delete data, or change certification logic.

## Requirements

- Ruby 3.3.6 and Inferno Core `>= 1.4.0, < 1.5`.
- The host's existing SQLite or PostgreSQL database and web application.
- Existing access controls also cover the browser: no separate login is added.

Runtime assets are shipped in the gem. Installation requires no npm, frontend build, or CDN. Node/Playwright are used only for development checks.

## Add to an ONC host

For local development, with sibling repositories, add this to the host's `Gemfile`:

```ruby
gem 'inferno_session_browser', path: '../inferno_session_browser'
```

Add this to `lib/onc_certification_g10_test_kit.rb` before the host constructs `Inferno::Web.app`:

```ruby
require 'inferno_session_browser'
```

Then run `bundle install` in the host and restart its web process. The `require` registers the adapter automatically; no change to `config.ru`, Inferno Core, or its React application is required. Merely installing a dependency does not execute the `require`.

The gem may be loaded before or after Inferno's web provider, provided it is loaded before the application is constructed. Requiring it repeatedly registers one adapter. Worker/CLI loading does not initialize a database or load the web provider.

After installing the built gem from a local file or your own gem source, replace the path dependency with:

```ruby
gem 'inferno_session_browser', '~> 0.1.0'
```

## Docker / Podman with an unpublished gem

A sibling path is outside ONC's Docker build context. Vendor the packaged source inside the host instead:

```sh
# In the gem repository:
mkdir -p pkg
gem build inferno_session_browser.gemspec --output pkg/inferno_session_browser-0.1.0.gem

# In the ONC host repository:
mkdir -p vendor
gem unpack ../inferno_session_browser/pkg/inferno_session_browser-0.1.0.gem --target vendor
```

Use the host dependency:

```ruby
gem 'inferno_session_browser', path: 'vendor/inferno_session_browser-0.1.0'
```

In ONC's `Dockerfile`, copy that directory **before** the existing `RUN bundle install`:

```dockerfile
COPY vendor/inferno_session_browser-0.1.0 /opt/inferno/vendor/inferno_session_browser-0.1.0
```

Keep the `require` line, update the host lockfile with `bundle install`, and rebuild/restart the image through your normal workflow. The browser needs no migrations. These are installation instructions; this repository does not edit or deploy the ONC host.

## Configuration

Configure before constructing the web application:

```ruby
require 'inferno_session_browser'

InfernoSessionBrowser.configure do |config|
  config.mount_path = '/sessions'
  config.fhir_url_input_names = ['url']
end
```

The mount path is relative to `BASE_PATH`. Use another path if `/sessions` conflicts with a host route. URL inputs are matched in configured priority order, case-insensitively by their stored input name. The first valid HTTP(S) URL wins. An application snapshots its configuration when constructed.

Only those URL inputs are read from `session_data`. URLs retain scheme, host, port, and path; username/password, query, and fragment are removed before display **and before filtering**. Other inputs, credential objects, resources, result messages, and request payloads are not returned by this browser.

## Table and history

- Filter by session ID substring, suite, selected suite option values, FHIR URL substring, recorded run state, and date range.
- Date ranges use an inclusive `from` and exclusive `to`; choose creation time or latest activity. API timestamps use UTC; the page displays local time.
- Default sorting is latest activity descending, with session ID as a stable tie breaker. Creation time and suite ID are also sortable.
- Default page size is 25; choose 50 or 100. Expanded run history uses 25 rows per page.
- Filters, sorting, and session pagination are saved in the URL for bookmarks.
- Auto-refresh runs every 10 seconds while the tab is visible; it can be disabled. Failed refreshes keep the last successful table visible.

Run state is derived from persisted runs: `never_run`, an active `queued`/`running`/`waiting`/`cancelling` run, or `idle`. The latest active run takes precedence over completed runs. A recorded active status does not prove a worker is alive after a crash.

Current result counts use the latest result for each individual test across runs, including optional tests. Group/suite results are excluded from counts. History counts are scoped to the selected run; its target outcome is shown separately when stored. Neither a completed run nor these counts is a certification verdict.

Sessions whose suite is no longer installed remain listed using stored IDs/options; **Open session** is unavailable for them. Only the connected host database is listed, not other Inferno servers.

Option and sanitized URL filters scan lightweight candidate metadata in batches of 500 for consistent SQLite/PostgreSQL behavior. Only the requested page receives result summaries; complete test histories and payloads are never fetched for the table. Very large databases can still make aggregate activity/filter scans expensive.

## JSON API

All routes accept GET/HEAD. Writes return 405. Responses are not cached. Invalid parameters return 400 JSON; unknown sessions return 404.

| Route | Response |
| --- | --- |
| `/sessions/api/sessions` | `{ data: [...], pagination: { page, page_size, total } }` |
| `/sessions/api/options` | `{ suites: [...], suite_options: [...], states: [...] }` |
| `/sessions/api/sessions/:id/runs` | `{ data: [...], pagination: { page, page_size, total } }` |

Collection parameters: `page`, `page_size` (25/50/100), `q`, `suite_id`, `suite_options[option_id]`, `fhir_url`, `state`, `date_field` (`created_at`/`latest_activity`), `from`, `to`, `sort` (`created_at`/`latest_activity`/`suite`), and `direction` (`asc`/`desc`). Dates must be ISO 8601 with a timezone. History accepts only `page` and `page_size`; options accepts no parameters.

Session fields: `id`, `suite_id`, `suite_title`, `suite_available`, `suite_options`, `fhir_url`, `created_at`, `latest_activity`, `state`, `run_count`, `result_counts`, and `session_url`. Run fields: `id`, `status`, `created_at`, `updated_at`, `target` (`type`, `id`, `title`), `outcome`, and `result_counts`.

Example:

```sh
curl --get 'http://localhost/sessions/api/sessions' \
  --data-urlencode 'state=running' \
  --data-urlencode 'suite_options[us_core_version]=6' \
  --data-urlencode 'page_size=25'
```

## Development and verification

```sh
bundle install
bundle exec rspec
```

Set `INFERNO_CORE_VERSION=1.4.0` or `1.4.4` when installing/resolving the bundle to pin the compatibility target. If an existing development lockfile pins another version, run `bundle update inferno_core --conservative` with the chosen environment variable.

By default specs use in-memory SQLite. For PostgreSQL, set `TEST_DATABASE_URL` to a **dedicated disposable test database**: fixtures create/drop the four test tables. Never point it at the host database. With both core versions installed, `ruby scripts/check.rb` runs the compatibility matrix (including PostgreSQL when this variable is set).

```sh
TEST_DATABASE_URL='postgres://localhost/inferno_browser_test' bundle exec rspec
```

The activation specs boot real Inferno instances in temporary directories, run Inferno's own migrations on fresh fixture databases, and verify both load orders, historical sessions, original session pages, packaged assets, timezone handling, and worker-safe loading.

Browser checks:

```sh
npm install
npx playwright install chromium
npm run test:browser
```

They start a local fixture server on `127.0.0.1:4568` and check pagination, filters, bookmarks, history, refresh controls, and failure recovery. To use installed Chrome, set `PLAYWRIGHT_BROWSER_CHANNEL=chrome`. Set `BROWSER_TEST_RUBY` to an explicit Ruby executable if needed. No browser tests contact your ONC instance.

GitHub Actions runs the database/core matrix plus browser checks. Build and install locally:

```sh
mkdir -p pkg
gem build inferno_session_browser.gemspec --output pkg/inferno_session_browser-0.1.0.gem
gem install --local pkg/inferno_session_browser-0.1.0.gem
BROWSER_PACKAGED=1 ruby test/host_smoke.rb before
```

The last check loads the installed gem into an isolated ONC-style host. No source-path override is used in that check. For an isolated install that also works with Bundler-managed dependency locations, run `bundle exec ruby test/installed_gem_smoke.rb pkg/inferno_session_browser-0.1.0.gem`. Publication and live deployment are separate steps.

## License

Apache License 2.0. See `LICENSE` and `NOTICE`.
