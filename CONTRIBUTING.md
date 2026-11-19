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

`lib/anvil/types/generated/` is generated from the API's own specs, which ship in
the [`@anvilco/types`](https://www.npmjs.com/package/@anvilco/types) npm package
and are regenerated from production after every deploy:

| File | From | Holds |
| --- | --- | --- |
| `graphql.rb` | `schema.graphql` | every object type as an `Anvil::Types` class, every enum as a module of string constants |
| `operations.rb` | `schema.graphql` | every input type as an `Anvil::Payloads` class, the arguments of every query and mutation as `Anvil::Operations::<Name>Args`, and `Anvil::Operations::NAMES` |
| `rest.rb` | `openapi.json` | the REST request bodies as `Anvil::Payloads` classes |

`dev/package.json` pins the exact `@anvilco/types` version; the generated files
say which one in their header. To move to a newer one:

```sh
dev/fetch-schema.sh            # or dev/fetch-schema.sh 1.2.0
bundle exec rake types:generate
```

CI runs `rake types:check`, which regenerates and fails on any difference, so a
hand edit to a generated file cannot merge, and neither can a bump without a
regenerate. `.github/workflows/sync-api-types.yml` does the bump for you: it
runs when anvil-js publishes a new `@anvilco/types` (and on a Monday cron as a
backstop), regenerates, and opens one PR. A sync that crosses a major version of
`@anvilco/types` is a breaking change here too, since the generated types are
public API: the PR says so and the changelog note it adds is marked `BREAKING`.

The generator is `dev/generate-types.mjs`, a Node script because the specs ship
as an npm package. It emits into the client's own attribute DSL
(`Anvil::Types::Base`, `Anvil::Payloads::Base`), which is why generated classes
already map camelCase and keep fields they do not declare. The hand-written
files under `lib/anvil/types/` and `lib/anvil/payloads/` reopen generated
classes to add convenience methods, or subclass them under the name the client's
API uses (`Payloads::CreateEtchPacket` is `Operations::CreateEtchPacketArgs`).
They never redeclare fields.

Two things the generator does on purpose. A type that would shadow a Ruby core
constant from inside `Anvil::Types` is renamed (`File` is `AnvilFile`; the list
is `RENAMES`). An attribute whose name Ruby or the DSL already owns gets a
`_value` suffix and keeps the API's spelling as its key (`BillingPeriod#end_value`
reads `end`). A spec fails when the schema adds a case either list misses.

The GraphQL operation strings in `lib/anvil/graphql.rb` are hand-written and
copied from node-anvil's `src/graphql/`, variable names and default response
fields included, so the same call returns the same fields in either client. Keep
them in step.

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
