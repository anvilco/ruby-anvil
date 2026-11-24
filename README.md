# Anvil API Client for Ruby

[![Gem Version](https://img.shields.io/gem/v/ruby-anvil.svg)](https://rubygems.org/gems/ruby-anvil)
[![CI](https://github.com/anvilco/ruby-anvil/actions/workflows/ci.yml/badge.svg)](https://github.com/anvilco/ruby-anvil/actions/workflows/ci.yml)

> [!IMPORTANT]
> **Anvil's official Ruby client.** The existing open source `anvil-ruby` gem is
> unofficial and not supported by Anvil.

[Anvil](https://www.useanvil.com/developers) is a suite of APIs for paperwork:

- [PDF filling](https://www.useanvil.com/docs/api/fill-pdf): fill a PDF template with JSON data
- [PDF generation](https://www.useanvil.com/docs/api/generate-pdf): turn HTML and CSS, or markdown, into a PDF
- [Etch e-sign](https://www.useanvil.com/docs/api/e-signatures): send documents out for signature
- [Workflows](https://www.useanvil.com/docs/api/workflows): collect data through a webform and pour it into documents

This gem wraps all of it. It is built on the standard library alone, so it adds
no runtime dependencies to your app.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Authentication](#authentication)
- [Configuration](#configuration)
- [Methods](#methods)
  - [fill_pdf](#fill_pdfpdf_template_id-payload-options)
  - [generate_pdf](#generate_pdfpayload-options)
  - [create_etch_packet](#create_etch_packetvariables-response_query-mutation)
  - [get_etch_packet](#get_etch_packeteid-response_query)
  - [get_current_user](#get_current_userresponse_query)
  - [generate_etch_sign_url](#generate_etch_sign_urlsigner_eid-client_user_id)
  - [download_documents](#download_documentsdocument_group_eid-options)
  - [forge_submit](#forge_submitvariables-response_query-mutation)
  - [remove_weld_data](#remove_weld_dataeid)
  - [request_graphql](#request_graphqlquery-variables)
  - [request_rest](#request_restpath-options)
- [Version constants](#version-constants)
- [File uploads](#file-uploads)
- [Response types](#response-types)
- [Errors](#errors)
- [Rate limits and retries](#rate-limits-and-retries)
- [Typed payloads and responses](#typed-payloads-and-responses)
- [Development](#development)
- [Integration test](#integration-test)
- [Publishing](#publishing)

## Installation

```ruby
# Gemfile
gem "ruby-anvil"
```

Or without Bundler:

```sh
gem install ruby-anvil
```

Then:

```ruby
require "anvil"
```

The gem is named `ruby-anvil` and the library is named `Anvil`. `require
"ruby-anvil"` works too, and does the same thing.

Ruby 3.1 or newer.

## Quick start

```ruby
require "anvil"

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

response = client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", {
  title: "My PDF Title",
  data: { someFieldId: "Hello World!" }
})

File.binwrite("filled.pdf", response.data)
```

Method names are Ruby's, so node-anvil's `fillPDF` is `fill_pdf` here and
`createEtchPacket` is `create_etch_packet`. Payload keys can be Ruby's too: the
typed payloads under `Anvil::Payloads` take `is_test` and send `isTest`. A plain
Hash is passed through exactly as you write it, so use the API's own camelCase
there.

## Authentication

Anvil takes either an API key or an OAuth access token. Pass one to the
constructor:

```ruby
# An API key from your organization's settings, sent as Basic auth
client = Anvil::Client.new(api_key: "7j2JuUWmN4fGjBxsCltWaybHOEy3UEtt")

# An OAuth access token, sent as Bearer auth
client = Anvil::Client.new(access_token: "an-oauth-access-token")
```

Each goes in the `Authorization` header the way the other Anvil clients send
it, so a credential that works in one client works in the other:

| Credential | Header |
| --- | --- |
| `api_key` | `Basic ` + base64 of `"#{api_key}:"` |
| `access_token`, a JWT | `Bearer ` + the token, unencoded |
| `access_token`, anything else | `Bearer ` + base64 of the token |

Note the trailing colon on the API key: it is a username with an empty
password, in the HTTP Basic style. The client handles this; you pass the raw
key.

Anvil's OAuth access tokens are JWTs, which the API wants verbatim. Any other
token is base64 encoded, which the API still accepts. The client works out
which it has, so you pass the token you were given either way.

`api_key` defaults to the **`ANVIL_API_KEY`** environment variable, so a client
with no arguments works when that is set:

```ruby
client = Anvil::Client.new
```

Find your API key in your organization's settings in the
[Anvil dashboard](https://app.useanvil.com). See the
[API key docs](https://www.useanvil.com/docs/api/getting-started#api-key) for
more.

## Configuration

```ruby
client = Anvil::Client.new(
  api_key: ENV.fetch("ANVIL_API_KEY"),

  # The Anvil environment to talk to. Defaults to production
  base_url: "https://staging.useanvil.com",

  # Overrides the User-Agent header
  user_agent: "My App/1.0",

  # What the client allows itself until the API tells it the real limit
  request_limit: 1,
  request_limit_ms: 1000,

  # How many times to retry a request the API could not answer. Zero turns it
  # off. A 429 is always retried, for as long as the API keeps asking
  max_retries: 5,

  # Seconds to wait for a connection, and for a response
  timeout: 300,

  # Share one limiter per process with every other client for the same
  # environment and credentials
  share_rate_limiter: true
)
```

### base_url

`base_url` defaults to `https://app.useanvil.com`. Every endpoint is derived
from it, so setting it once points the whole client at another environment:

| Endpoint           | URL                                           |
| ------------------ | --------------------------------------------- |
| REST               | `{base_url}/api/v1/...`                       |
| GraphQL            | `{base_url}/graphql`                          |
| Document downloads | `{base_url}/api/document-group/{eid}.zip`     |

```ruby
client = Anvil::Client.new(api_key: key, base_url: "https://staging.useanvil.com")
# GraphQL now goes to https://staging.useanvil.com/graphql
```

## Methods

Every method raises on failure rather than returning an error, so the happy
path reads straight through. See [Errors](#errors).

### `fill_pdf(pdf_template_id, payload, **options)`

Fills a PDF template with your JSON data, and returns the filled PDF.

You will need to have
[uploaded a PDF to Anvil](https://useanvil.com/docs/api/fill-pdf#creating-a-pdf-template)
first. Its id is on the template's page in the dashboard, and in that page's
URL: `https://app.useanvil.com/org/<your-org-slug>/pdf/<pdf-template-id>`.

```ruby
response = client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", {
  title: "My PDF Title",
  fontSize: 10,
  textColor: "#CC0000",
  data: { someFieldId: "Hello World!" }
})

File.binwrite("filled.pdf", response.data)
```

The payload's keys can be passed as keyword arguments, or as a typed
`Anvil::Payloads::FillPdf`:

```ruby
client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", data: { someFieldId: "Hello World!" })

client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", Anvil::Payloads::FillPdf.new(
  title: "My PDF Title",
  font_size: 10,
  text_color: "#CC0000",
  data: { someFieldId: "Hello World!" }
))
```

Options:

- `data_type` (Symbol) `:string` (the default), `:io` or `:stream`. See
  [Response types](#response-types)
- `version_number` (Integer) which version of the template to fill. Defaults to
  the latest published version. See [Version constants](#version-constants)
- `to` (IO) where to write a `:stream` response

Returns an `Anvil::RestResponse`: `data` is the PDF, and `status_code` and
`headers` are there if you want them.

### `generate_pdf(payload, **options)`

Generates a new PDF from HTML and CSS, or from markdown. Nothing has to be set
up in the dashboard first: send data, get a PDF.

```ruby
# HTML and CSS
response = client.generate_pdf(
  title: "Example",
  type: "html",
  data: {
    html: "<h1 class='header-one'>What is Lorem Ipsum?</h1><p>Lorem Ipsum is...</p>",
    css: "body { font-size: 14px; color: #171717; } .header-one { text-decoration: underline; }"
  }
)

# Markdown
response = client.generate_pdf(
  title: "Example Invoice",
  data: [
    { label: "Name", content: "Sally Jones" },
    { content: "Lorem **ipsum** dolor sit _amet_" },
    {
      table: {
        firstRowHeaders: true,
        rows: [
          ["Description", "Quantity", "Price"],
          ["4x Large Widgets", "4", "$40.00"]
        ]
      }
    }
  ]
)

File.binwrite("generated.pdf", response.data)
```

Takes the same options as `fill_pdf`, except `version_number`. See the
[HTML to PDF](https://www.useanvil.com/docs/api/generate-pdf#html--css-to-pdf)
and [markdown to PDF](https://www.useanvil.com/docs/api/generate-pdf#markdown-to-pdf)
docs for everything `data` accepts.

### `create_etch_packet(variables:, response_query: nil, mutation: nil)`

Creates an Etch e-sign packet, and sends it to the first signer unless it is a
draft.

```ruby
packet = client.create_etch_packet(variables: Anvil::Payloads::CreateEtchPacket.new(
  name: "Test Docs - Testy Signer",
  # The packet is ready to send: an email goes to the first signer.
  # Use is_draft: true to review it in the dashboard first
  is_draft: false,
  # Test packets use development signatures and are not billed
  is_test: true,
  signature_email_subject: "Please sign these documents",

  files: [
    Anvil::Payloads::EtchFile.new(id: "sampleTemplate", cast_eid: "05xXsZko33JIO6aq5Pnr")
  ],

  # Fills the PDFs before they go out for signature
  data: { payloads: { sampleTemplate: { data: { name: "Testy Signer" } } } },

  signers: [
    Anvil::Payloads::EtchSigner.new(
      id: "signer1",
      name: "Testy Signer",
      email: "testy@example.com",
      signer_type: "email",
      fields: [Anvil::Payloads::SignerField.new(file_id: "sampleTemplate", field_id: "signature")]
    )
  ]
))

puts packet.details_url
puts packet.signers.map(&:eid)
```

- `variables` (`Anvil::Payloads::CreateEtchPacket` or Hash) the mutation's
  variables. See the [API reference](https://www.useanvil.com/docs/api/graphql/reference/)
- `response_query` (String) the fields to select on the new packet, instead of
  the [default set](#typed-payloads-and-responses)
- `mutation` (String) replaces the whole mutation, response query and all, for
  when you want complete control

Returns an `Anvil::Types::EtchPacket`.

To upload a new PDF with the packet rather than using a template, see
[File uploads](#file-uploads).

### `get_etch_packet(eid:, response_query: nil)`

Reads an Etch packet.

```ruby
packet = client.get_etch_packet(eid: "AwpXqV3mnjeMgQb0VHKk")

packet.status
packet.number_remaining_signers
packet.document_group.eid
packet.signers.map { |signer| [signer.email, signer.status] }
```

Pass `variables:` instead of `eid:` if you would rather give the query's
variables whole.

### `get_current_user(response_query:)`

Reads whoever the API key or access token belongs to.

```ruby
user = client.get_current_user

user.eid
user.email
user.organizations.map(&:slug)
```

Returns an `Anvil::Types::User`.

### `generate_etch_sign_url(signer_eid:, client_user_id:)`

Generates a signing URL for one signer, for signing in your own app rather than
through Anvil's email. The signer must have been created with a `signer_type`
of `"embedded"`.

```ruby
url = client.generate_etch_sign_url(
  signer_eid: "XcVgTZ2hBjmYFhtR5nIj",
  client_user_id: "your-user-id"
)
```

Returns the URL as a String.

### `download_documents(document_group_eid, **options)`

Downloads a document group's documents, as a zip.

```ruby
response = client.download_documents("6Dnu5jXb0Z1MGJTdhEJX")
File.binwrite("documents.zip", response.data)

# Or stream it straight to disk
File.open("documents.zip", "wb") do |file|
  client.download_documents("6Dnu5jXb0Z1MGJTdhEJX", data_type: :stream, to: file)
end
```

Takes `data_type` and `to`, the same as `fill_pdf`.

### `forge_submit(variables:, response_query: nil, mutation: nil)`

Submits data to one webform (a Forge) of a Workflow.

```ruby
submission = client.forge_submit(variables: Anvil::Payloads::ForgeSubmit.new(
  forge_eid: "FsqmyvJjDRNvqmyvJsqm",
  payload: { name: "Sally Jones", email: "sally@example.com" },
  is_test: true
))

submission.eid
submission.weld_data.eid       # the Workflow submission this went into
submission.continue_url
```

Leave `weld_data_eid` out to start a new Workflow submission, and pass the one
you got back to add to an existing one.

Returns an `Anvil::Types::Submission`.

### `remove_weld_data(eid:)`

Removes a Workflow submission and everything in it. This cannot be undone.

```ruby
client.remove_weld_data(eid: "weldDataEid") # => true
```

### `request_graphql(query:, variables: {})`

Runs any GraphQL query or mutation, for everything without a method of its own.
See the [GraphQL reference](https://www.useanvil.com/docs/api/graphql/reference/)
for what the API can do.

```ruby
response = client.request_graphql(
  query: <<~GRAPHQL,
    query WeldDataQuery($eid: String!) {
      weldData(eid: $eid) {
        eid
        isComplete
        isTest
      }
    }
  GRAPHQL
  variables: { eid: "nxflNZqxDUbltLUbYWK" }
)

response["weldData"]["isComplete"]   # the result of one operation
response.dig("weldData", "isComplete") # the same, without checking each level
response.data                        # the whole GraphQL data map
response.status_code
```

Files anywhere in `variables` are uploaded as multipart. See
[File uploads](#file-uploads).

Returns an `Anvil::GraphQLResponse`, and raises `Anvil::GraphQLError` when the
response carries GraphQL errors.

### `request_rest(path, **options)`

Runs any REST request, for the endpoints without a method of their own.

```ruby
response = client.request_rest(
  "/api/v1/fill/#{pdf_template_id}.pdf",
  method: :post,
  body: payload,
  data_type: :stream,
  to: file
)
```

- `path` (String) a path from `base_url`, or a whole URL
- `method` (Symbol) `:get`, `:post`, `:put`, `:patch`, `:delete` or `:head`
- `body` (Hash, `Anvil::Payloads::Base`, String or nil) a Hash or payload is
  sent as JSON, a String is sent as it is
- `headers` (Hash) extra request headers
- `data_type` (Symbol) `:string`, `:io`, `:json` or `:stream`
- `to` (IO) where to write a `:stream` response

Returns an `Anvil::RestResponse`.

## Version constants

PDF templates are versioned. `fill_pdf` uses the latest published version
unless you ask for another:

```ruby
Anvil::VERSION_LATEST            # => -1, the latest version, usually the current draft
Anvil::VERSION_LATEST_PUBLISHED  # => -2, the latest published version, the API's default

# Fill with the current draft, to check a change before publishing it
client.fill_pdf(template_id, payload, version_number: Anvil::VERSION_LATEST)

# Or pin to a specific version
client.fill_pdf(template_id, payload, version_number: 3)
```

## File uploads

Anvil takes a new PDF in three ways: a URL it fetches itself, base64 data
inline, or a multipart file upload. The multipart route is the one to use for
anything large, and `Anvil.prepare_graphql_file` is how you say so:

```ruby
# From a path
file = Anvil.prepare_graphql_file("./contract.pdf")

# From an open IO
file = Anvil.prepare_graphql_file(File.open("./contract.pdf", "rb"))

# From bytes you already have, which need a filename of their own
file = Anvil.prepare_graphql_file(StringIO.new(bytes), filename: "contract.pdf")

# Override what it is uploaded as
file = Anvil.prepare_graphql_file("./contract", filename: "contract.pdf", mimetype: "application/pdf")
```

Put the result wherever the API takes an `Upload`, which is always the `file`
key of an object:

```ruby
packet = client.create_etch_packet(variables: {
  name: "Mutual NDA",
  isTest: true,
  files: [{
    id: "nda",
    title: "Mutual NDA",
    file: Anvil.prepare_graphql_file("./nda.pdf"),
    fields: [{
      id: "signature",
      type: "signature",
      pageNum: 0,
      rect: { x: 100, y: 100, width: 200, height: 40 }
    }]
  }],
  signers: [{ id: "signer1", name: "Sally", email: "sally@example.com", signerType: "email",
              fields: [{ fileId: "nda", fieldId: "signature" }] }]
})
```

The client sends it over the
[GraphQL multipart request spec](https://github.com/jaydenseric/graphql-multipart-request-spec),
assembling the body in a tempfile so a large PDF is never held in memory whole.
This is the Ruby equivalent of node-anvil's `Anvil.prepareGraphQLFile()`.

The other two shapes go in the same place, as plain data:

```ruby
# base64
file: { data: Base64.strict_encode64(bytes), filename: "nda.pdf", mimetype: "application/pdf" }

# a URL Anvil fetches itself, which has to be publicly reachable
file: { url: "https://example.com/nda.pdf" }
```

An upload anywhere other than under a `file` key is rejected before the request
is made, with `Anvil::ConfigurationError`, since the API would reject it too.

## Response types

The methods that return a file take a `data_type`:

| `data_type`         | `response.data` is                                           |
| ------------------- | ------------------------------------------------------------ |
| `:string` (default) | a binary String of the whole body                             |
| `:io`               | a `StringIO` over the whole body                              |
| `:stream`           | the number of bytes handed to your block or written to `to:`  |
| `:json`             | the parsed JSON (`request_rest` only)                         |

`:stream` never holds the body in memory, so it is the one to use for a large
PDF or zip. It needs somewhere to put the bytes: a block, or an IO as `to:`.

```ruby
# To a block
client.fill_pdf(template_id, payload, data_type: :stream) do |chunk|
  digest << chunk
end

# To an IO
File.open("filled.pdf", "wb") do |file|
  client.fill_pdf(template_id, payload, data_type: :stream, to: file)
end
```

## Errors

Anything that goes wrong raises. Every exception descends from `Anvil::Error`,
so one rescue catches the lot:

```ruby
begin
  client.fill_pdf(template_id, payload)
rescue Anvil::ValidationError => e
  e.status_code                  # => 422
  e.message                      # => "ValidationError (data: Required)"
  e.fields.map(&:property)       # => ["data"]
  e.fields.map(&:message)        # => ["Required"]
rescue Anvil::Error => e
  warn "Anvil call failed: #{e.message}"
end
```

| Exception                   | Raised when                                                     |
| --------------------------- | ---------------------------------------------------------------- |
| `Anvil::ConfigurationError` | the client was called with unusable arguments, before any request |
| `Anvil::ConnectionError`    | the API could not be reached, or answered with unparseable JSON   |
| `Anvil::ValidationError`    | 400 or 422                                                        |
| `Anvil::AuthenticationError`| 401                                                               |
| `Anvil::ForbiddenError`     | 403                                                               |
| `Anvil::NotFoundError`      | 404                                                               |
| `Anvil::RateLimitError`     | 429, after the retries were used up                               |
| `Anvil::ClientError`        | any other 4xx                                                     |
| `Anvil::ServerError`        | 5xx                                                               |
| `Anvil::GraphQLError`       | a GraphQL response carrying errors, which the API sends as a 200  |

Everything from `Anvil::ValidationError` down is an `Anvil::ResponseError`,
which carries:

- `status_code` (Integer)
- `errors` (Array of `Anvil::ErrorDetail`) every error the API reported, each
  with a `name`, a `message`, any `fields`, and the `raw` error as sent
- `fields` (Array of `Anvil::ErrorField`) the field-level details across all of
  them, each with a `message` and the `property` at fault
- `body` the parsed response body
- `headers` (Hash)

GraphQL and REST errors are normalized into the same shape.

Two rules about what counts as an error:

- A GraphQL response carrying an `errors` array raises, even though the API
  answers those with a 200.
- A 2xx whose body happens to carry only a `name` or a `message` does **not**
  raise. node-anvil treats that as an error; python-anvil and dotnet-anvil do
  not, and this client follows them.

## Rate limits and retries

The API rate limits by organization. The client throttles itself to stay under
the limit rather than letting you hit it:

1. It starts at one request a second, which is below any real limit.
2. The first response carries your organization's actual limit in its
   `x-ratelimit-limit` and `x-ratelimit-interval-ms` headers, and the limiter
   resizes itself from those. Requests made before that answer wait for it.
3. A request takes a slot before it is sent and gives it back when its response
   arrives, and a finished request keeps counting for one interval. So the
   requests in flight count against the limit alongside the ones that just
   finished, which is what stops a burst of concurrent calls overshooting.

**The limiter is shared per process**, keyed by the environment and a hash of
the credentials, so every client built for the same organization throttles as
one. Pass `share_rate_limiter: false` for a client with its own, or
`rate_limiter:` to supply one.

Retries, when the API does not answer:

| Response | What happens |
| --- | --- |
| 429 | waits the `Retry-After` it asked for, capped at 60s, plus 50ms, then tries again, for as long as the API keeps asking |
| 429 with no `Retry-After` | waits a second, plus the buffer |
| 500, 502, 503, 504 | retried `max_retries` times, 100ms doubling each time, or the `Retry-After` if it sent one |
| A connection that never arrived | retried the same way |
| A timeout | **not** retried, since the request may already have been acted on |
| Anything else | raised |

`Anvil::RateLimitError` is only raised if a 429 somehow reaches you, which the
throttling is there to prevent.

## Typed payloads and responses

Request payloads live under `Anvil::Payloads` and take snake_case names, which
they convert to the API's own spelling:

```ruby
Anvil::Payloads::CreateEtchPacket.new(is_test: true, webhook_url: "https://example.com/hook").to_h
# => { "isTest" => true, "webhookURL" => "https://example.com/hook" }
```

They are a convenience, not a requirement: every method also takes a plain Hash
with the API's camelCase keys. Anything a payload class does not declare is
camelized and passed through, so a new API field does not have to wait for a
gem release:

```ruby
Anvil::Payloads::FillPdf.new(data: {}, some_new_option: true).to_h
# => { "data" => {}, "someNewOption" => true }
```

The payloads the client's methods take: `FillPdf`, `GeneratePdf`,
`CreateEtchPacket`, `EtchFile`, `EtchSigner`, `SignerField`, `ForgeSubmit`.
Behind them, every REST request body and GraphQL input type in the API's specs
is generated too.

Responses come back under `Anvil::Types` with snake_case readers, and keep
everything the API sent:

```ruby
packet = client.get_etch_packet(eid: "AwpXqV3mnjeMgQb0VHKk")

packet.details_url                 # a declared field
packet.created_at                  # timestamps are parsed into Time
packet.document_group.signers      # nested objects are typed too
packet["someFieldAddedYesterday"]  # anything else, by its API name
packet.dig("documentGroup", "signers", 0, "eid")  # down a path, nils and all
packet.to_h                        # the response exactly as it arrived
```

Every type the API has is here, generated from its schema: `EtchPacket`,
`DocumentGroup`, `Signer`, `Submission`, `WeldData`, `User`, `Organization`
and some fifty more, plus `Anvil::Operations::<Name>Args` for the arguments of
every query and mutation. See [CONTRIBUTING.md](CONTRIBUTING.md) for how they
are generated and kept in step with production.

A custom `response_query` works with this: fields you did not select read as
`nil`, and fields the type does not declare are still in `to_h` and reachable
with `[]` or `dig`.

## Development

```sh
bin/setup            # install the dependencies
bundle exec rake     # rubocop and rspec, what CI runs
bundle exec rspec    # just the tests
bundle exec rubocop  # just the linter
bin/console          # an IRB session with the gem loaded
```

The tests mock HTTP with [WebMock](https://github.com/bblimke/webmock) and talk
to nothing. The suite is held above 95% line coverage by SimpleCov, which fails
the run if it drops below.

Runnable examples are in [`examples/`](examples). [CONTRIBUTING.md](CONTRIBUTING.md)
covers developing, the test client, the types, versioning and publishing.

## Integration test

`test-client.rb` runs every method against a real Anvil environment and prints
a pass or fail for each. It defaults to staging:

```sh
ANVIL_API_KEY=<your staging API key> ruby test-client.rb
```

```
Testing ruby-anvil 0.1.0 against https://staging.useanvil.com

  PASS  request_graphql (organization UESmQW9ZP6AKL9RJ7wlS)
  PASS  rate limiting (a burst past the limit surfaces no 429) (5 requests at 4 per 1000ms in 1.5s)
  SKIP  OAuth access token (Bearer auth): Set ANVIL_ACCESS_TOKEN to check Bearer auth
  PASS  get_current_user (lE0vobbpGM20qRNnkvd7, 1 organization(s))
  PASS  generate_pdf (markdown) (18023 bytes)
  ...
  PASS  cleanup (removes the packets this run created) (removed 4 packet(s))
  PASS  error handling (a rejected request raises a typed error) (ValidationError on HTTP 400)

22 passed, 0 failed, 1 skipped
```

It exits non-zero if anything failed, so it can be run in a pipeline. Run it
against a release before and after a change to see which behaviors changed.

Environment variables:

| Variable                | Required | What it does                                                               |
| ----------------------- | -------- | -------------------------------------------------------------------------- |
| `ANVIL_API_KEY`         | yes      | an API key for the environment being tested                                 |
| `ANVIL_BASE_URL`        | no       | the environment. Defaults to `https://staging.useanvil.com`                 |
| `ANVIL_ACCESS_TOKEN`    | no       | an OAuth token for the same environment, to check Bearer auth               |
| `ANVIL_PDF_TEMPLATE_ID` | no       | the PDF template to fill. Defaults to the first one with example data       |
| `ANVIL_FORGE_EID`       | no       | the webform to submit to. Defaults to the first one in your organization    |

Everything it creates is test data, and it removes all of it at the end: the
Etch packets are test packets whose signers are embedded, so no email is sent
to anyone, and the Workflow submission is a test submission. The PDF template
and the webform it uses are found in your organization rather than created, so
they survive the run.

`bundle exec rake integration` runs the same script.

## Publishing

Releases are cut from [package-ops](https://github.com/anvilco/package-ops),
not from this repo, the same way python-anvil and dotnet-anvil are: one
workflow there runs the lint and tests, bumps `Anvil::VERSION`, renames
`[Unreleased]` in the changelog to the new version, commits, tags `v<version>`,
creates the GitHub release with that section as its notes, and pushes the gem
to RubyGems with trusted publishing. This repo holds no publishing secret and
no publish workflow, and nothing publishes on merge.

To release:

1. Make sure the changes are noted under `## [Unreleased]` in
   [CHANGELOG.md](CHANGELOG.md). A `- BREAKING:` bullet there forces the next
   release to be a major.
2. In package-ops, Actions > Release > Run workflow: pick `anvilco/ruby-anvil`
   and the increment, leaving `dry_run` on. Read what it plans to do.
3. Run it again with `dry_run` off.

The release config is
[`repos/ruby-anvil/release.js`](https://github.com/anvilco/package-ops/blob/main/repos/ruby-anvil/release.js),
and the notes next to it say what is specific to this repo.

### What the release needs, outside this repo

| Where             | What                                                                                                                 |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------- |
| anvilco org       | The `anvil-package-release` GitHub App installed on this repository, and on the default branch ruleset's bypass list      |
| RubyGems          | A trusted publisher on the `ruby-anvil` gem naming `anvilco/package-ops`, workflow `release.yml`, environment `release`   |
| package-ops       | `RELEASE_APPROVERS` includes whoever runs it                                                                             |

RubyGems takes a trusted publisher for a gem that does not exist yet, as a
pending publisher under the account's profile, so 0.1.0 goes out through
package-ops like every release after it. A pending publisher expires 12 hours
after it is created, and the account that creates it becomes the gem's owner, so
create it from the account registered to services@useanvil.com shortly before
the first release. That account is recorded in 1Password, as the npm, PyPI and
NuGet accounts are. The gemspec sets `rubygems_mfa_required`, so it needs MFA
enabled.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
