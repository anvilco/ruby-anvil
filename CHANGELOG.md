# Changelog

All notable changes to this gem are recorded here. It follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the gem follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are cut from [package-ops](https://github.com/anvilco/package-ops),
which renames `[Unreleased]` to the version it is releasing. Note changes here
as they land.

## [Unreleased]

## [v0.1.0] - 2026-11-23

The first release: the Anvil API in Ruby, with the same coverage as the
[Node client](https://github.com/anvilco/node-anvil).

### Added

- `Anvil::Client` with `fill_pdf`, `generate_pdf`, `create_etch_packet`,
  `get_etch_packet`, `generate_etch_sign_url`, `download_documents`,
  `forge_submit` and `remove_weld_data`, plus the `request_graphql` and
  `request_rest` escape hatches for everything else the API can do.
- API key (Basic) and OAuth access token (Bearer) authentication.
- A configurable `base_url` that every endpoint is derived from, so one setting
  points the whole client at staging.
- Automatic rate limiting, sized from your organization's own
  `x-ratelimit-limit` and `x-ratelimit-interval-ms` headers on the first
  response, and a retry on a 429 after the delay the API asks for.
- Structured errors: an exception class per failure kind, carrying the status
  code, the normalized messages and any field-level details.
- Typed request payloads under `Anvil::Payloads` and typed responses under
  `Anvil::Types`, both of which pass through anything they do not know about.
- GraphQL file uploads over the multipart request spec, prepared with
  `Anvil.prepare_graphql_file`.
- `:string`, `:io`, `:stream` and `:json` response types, so a large PDF or zip
  never has to be held in memory whole.
- `get_current_user`, reading whoever the credentials belong to.
- `dig` on GraphQL responses and on response types, alongside `[]`, so a nested
  value can be read in one call without checking each level for nil.
- An `ANVIL_API_KEY` environment variable fallback, so a client built with no
  arguments works.
- Retries for the responses the API could not give: 500, 502, 503 and 504, and
  connection errors, backing off 100ms and doubling, or honoring a `Retry-After`.
  A timeout is not retried, since the request may already have been acted on.
- `examples/`, and a `CONTRIBUTING.md` covering developing, the test client, the
  types, versioning and publishing.
- Every type in the API's specs, generated from `@anvilco/types`: the GraphQL
  object, input and enum types, the arguments of every query and mutation under
  `Anvil::Operations`, and the REST request bodies. A sync workflow keeps them
  in step with production, and CI fails on a stale or hand-edited generated file.

### Notes

The client follows the SDK conventions the other Anvil clients are held to, so a
few behaviors match python-anvil and dotnet-anvil rather than node-anvil:

- An OAuth access token that is a JWT is sent verbatim, as the API wants. Only
  a non-JWT token is base64 encoded.
- The rate limiter is a sliding window shared per process, keyed by the
  environment and the credentials, counting requests in flight as well as
  finished. A 429 is retried for as long as the API keeps asking, waiting the
  `Retry-After` it named capped at a minute.
- A 2xx whose body carries only a `name` or a `message` is not an error.
  node-anvil treats it as one; that is a known divergence.

