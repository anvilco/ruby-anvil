# Contributing

## Develop

Ruby 3.1 or newer. `.ruby-version` pins what this is developed against, and CI
runs the specs on 3.1 through 4.0.

```sh
bin/setup            # bundle install
bundle exec rake     # rubocop then rspec, which is what CI runs
bundle exec rspec    # just the specs
bundle exec rubocop  # just the linter
bin/console          # IRB with the gem loaded, and an `anvil` client when ANVIL_API_KEY is set
```

The gem has no runtime dependencies: Net::HTTP and the standard library only.
Keep it that way. Anything a dependency would give us is either small enough to
write or not worth the version conflicts in someone else's app. Note that
`base64` stopped being a default gem in Ruby 3.4, which is why encoding goes
through `pack("m0")` rather than that gem.

The specs mock HTTP with [WebMock](https://github.com/bblimke/webmock) and talk
to nothing. SimpleCov fails the run below 95% line coverage.

Two things to know about the specs:

- `build_client` passes `share_rate_limiter: false`. The limiter is shared per
  process in production, so without that one spec's adopted limit would slow
  every spec after it.
- Specs that exercise a retry stub `sleep`. A 429 sleeps on the limiter
  (`allow(client.rate_limiter).to receive(:sleep)`), and a 5xx or connection
  error sleeps on the client.

## test-client

`test-client.rb` runs every method against a real Anvil environment and prints a
pass or fail for each. It defaults to staging.

```sh
ANVIL_API_KEY=<your staging API key> ruby test-client.rb
```

| Variable | Required | What it does |
| --- | --- | --- |
| `ANVIL_API_KEY` | yes | an API key for the environment being tested |
| `ANVIL_BASE_URL` | no | defaults to `https://staging.useanvil.com` |
| `ANVIL_ACCESS_TOKEN` | no | an OAuth token, to check Bearer auth |
| `ANVIL_PDF_TEMPLATE_ID` | no | the PDF template to fill. Defaults to the first with example data |
| `ANVIL_FORGE_EID` | no | the webform to submit to. Defaults to the first in your organization |

It exits non-zero if anything failed, so it can run in a pipeline. Run it
against a release before and after a change and diff the output.

Everything it creates is removed at the end. The packets are test packets with
embedded signers, so no mail reaches anyone. The PDF template and the webform it
uses are found in your organization rather than created, so they survive the
run.

## Types

The request payloads in `Anvil::Payloads` and the response types in
`Anvil::Types` are hand-written. The other clients generate theirs from
`@anvilco/types`, and this one will too once there is a Ruby generator; until
then there is no `@anvilco/types` pin, no `typesVersion` in the release config
and no `sync-api-types.yml` here.

Both sides pass through what they do not declare: an undeclared keyword argument
to a payload is camelized and sent, and a response field the type does not know
stays reachable through `[]` and `to_h`. A new API field does not have to wait
for a gem release.

The GraphQL operation strings in `lib/anvil/graphql.rb` are copied from
node-anvil's `src/graphql/`, variable names and default response fields
included, so the same call returns the same fields in either client. Keep them
in step.

## Versioning

[Semantic versioning](https://semver.org). The version lives in one place,
`lib/anvil/version.rb`, and package-ops writes it during a release.

Note what is public: the client's methods, the payload and response types, and
the exception hierarchy. Removing or renaming any of them is a major.

Record every change under `## [Unreleased]` in
[CHANGELOG.md](CHANGELOG.md) as it lands, in
[keep-a-changelog](https://keepachangelog.com) form. A bullet starting
`- BREAKING: ` forces the next release to be a major. That section becomes the
GitHub release notes, so write it for the people installing the gem.

## Publishing

Releases are cut from [package-ops](https://github.com/anvilco/package-ops), not
from here, the same way python-anvil and dotnet-anvil are. This repo holds no
publishing secret and no publish workflow, and nothing publishes on merge.

To release: make sure the changes are noted under `## [Unreleased]`, then in
package-ops run Actions > Release > Run workflow, picking `anvilco/ruby-anvil`
and the increment, with `dry_run` on first. It runs the lint and specs, bumps
the version, renames the changelog section, commits, tags `v<version>`, creates
the GitHub release and pushes the gem to RubyGems with trusted publishing.

The release config is `repos/ruby-anvil/release.js` in package-ops, and the
notes beside it cover what is specific to this repo.
