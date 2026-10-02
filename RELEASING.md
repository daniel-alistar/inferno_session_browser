# Releasing Inferno Session Browser

Releases are published manually to [RubyGems.org](https://rubygems.org). Run the commands below from the repository root using Ruby 3.3.6. Build and publish from the same clean, committed source that passed CI.

## Account setup

Create a RubyGems.org account and enable [multi-factor authentication for the UI and API](https://guides.rubygems.org/setting-up-multifactor-authentication/). The gem's `rubygems_mfa_required` metadata requires its owners to enable MFA, and `allowed_push_host` restricts publishing to RubyGems.org. Authentication is entered through the RubyGems CLI; account credentials belong outside this repository.

For the first release, confirm that `inferno_session_browser` is available to your account. For later releases, confirm that your account owns the gem and the intended version has not already been published.

## Prepare the release commit

1. Set `InfernoSessionBrowser::VERSION` in `lib/inferno_session_browser/version.rb`. It is already `0.1.0` for the first release.
2. Update `CHANGELOG.md` with the version, actual release date, and user-facing changes. Update installation examples when their supported release series changes.
3. Review the gemspec's author, homepage, metadata, Ruby requirement, and runtime dependencies.
4. Commit the final source and documentation, push that commit through the normal review process, and wait for the **Checks** workflow to pass for that exact commit. It must pass Inferno Core 1.4.0 and 1.4.4 with both SQLite and PostgreSQL, installed-package checks, and browser tests.

The [README](README.md#development-and-verification) explains the local checks. PostgreSQL checks require a dedicated disposable test database because the fixtures create and drop tables.

Before tagging, `git status --short` must show no staged, unstaged, or untracked changes. Keep the release checkout on the commit that passed CI.

## Tag the checked commit

Derive the tag and archive filename from the gemspec:

```sh
release_version="$(ruby -e 'print Gem::Specification.load("inferno_session_browser.gemspec").version')"
gem_file="$(ruby -e 'print Gem::Specification.load("inferno_session_browser.gemspec").file_name')"
gem_package="pkg/$gem_file"
release_tag="v$release_version"

git status --short
git tag -a "$release_tag" -m "Release $release_version"
git push origin "$release_tag"
```

For the first release the tag is `v0.1.0`. If a tag already exists, verify that it names the intended release commit instead of moving or replacing it. Pushing the tag runs CI; wait for those checks to pass before publishing.

## Build and verify the archive

Stay on the tagged commit. Confirm that the tag resolves to the current checkout:

```sh
test "$(git rev-parse "$release_tag^{commit}")" = "$(git rev-parse HEAD)"

export INFERNO_CORE_VERSION=1.4.4
bundle install
mkdir -p pkg
gem build inferno_session_browser.gemspec --output "$gem_package"
gem specification "$gem_package"
bundle exec ruby test/installed_gem_smoke.rb "$gem_package"
```

If an existing development lockfile selects a different Inferno Core version, run `bundle update inferno_core --conservative` with `INFERNO_CORE_VERSION=1.4.4` before verification.

Inspect the archive specification for the intended name/version, author, homepage, metadata, license, dependencies, and files. It must contain the Ruby implementation, JavaScript/CSS assets, HTML template, README, release guide, changelog, license, and notice. It must exclude local databases, logs, credentials, and generated development artifacts. The installed-package check must report the intended version for both load orders and load the library from its temporary installation.

Run `git status --short` again to confirm that build and verification did not change the release source. Publish this verified archive.

## Publish and verify

```sh
gem signin
gem push --host https://rubygems.org "$gem_package"
gem specification inferno_session_browser version --remote --version "$release_version"
```

Complete any MFA prompt from the CLI. Confirm that the [RubyGems page](https://rubygems.org/gems/inferno_session_browser) shows the intended version and repository/documentation links.

In a fresh Ruby 3.3.6 environment, install the published version:

```sh
gem install inferno_session_browser --version "$release_version"
```

Follow the README's host integration instructions and verify that the dashboard and assets load. Record the matching tag and changelog in a GitHub release. If a correction is needed after publication, prepare a new version and repeat this procedure.
