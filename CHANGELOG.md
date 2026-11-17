# Changelog

All notable changes to this gem are recorded here. It follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the gem follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are cut from [package-ops](https://github.com/anvilco/package-ops),
which renames `[Unreleased]` to the version it is releasing. Note changes here
as they land.

## [Unreleased]

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
