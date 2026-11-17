#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs every client method against a real Anvil environment (staging by
# default) and prints a pass or fail for each.
#
# Everything it checks is the client's public behavior: what each method sends,
# and the shape of what it returns. Run it against a release before and after a
# change to see which behaviors changed.
#
# Usage:
#   ANVIL_API_KEY=<your staging API key> ruby test-client.rb
#
# Environment variables:
#   ANVIL_API_KEY          Required. An API key for the environment being tested.
#   ANVIL_BASE_URL         Optional. Defaults to https://staging.useanvil.com
#   ANVIL_ACCESS_TOKEN     Optional. An OAuth access token for the same environment,
#                          to check Bearer auth. Skipped when not set.
#   ANVIL_PDF_TEMPLATE_ID  Optional. The PDF template to fill. Defaults to the first
#                          one in your organization that has example data.
#   ANVIL_FORGE_EID        Optional. The webform (Forge) in a Workflow to submit to.
#                          Defaults to the first one in your organization.
#
# Everything it creates is test data: the Etch packets are test packets, and the
# Workflow submission is a test submission that is removed at the end.

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))

require "anvil"
require "json"
require "stringio"

# Runs each check, prints its result, and counts them up.
class Runner
  # Raised by a check that cannot run because something it needed is missing.
  class Skipped < StandardError; end

  def initialize
    @passed = 0
    @failed = 0
    @skipped = 0
  end

  def check(name)
    detail = yield
    @passed += 1
    puts "  PASS  #{name}#{" (#{detail})" if detail}"
  rescue Skipped => e
    @skipped += 1
    puts "  SKIP  #{name}: #{e.message}"
  rescue Anvil::ResponseError => e
    @failed += 1
    puts "  FAIL  #{name}: #{e.message} [HTTP #{e.status_code}]"
  rescue StandardError => e
    @failed += 1
    puts "  FAIL  #{name}: #{e.class}: #{e.message}"
  end

  # @return [Boolean] whether everything that ran passed
  # rubocop:disable-next Naming/PredicateMethod -- it reports, and says whether to exit clean
  def report
    puts
    puts "#{@passed} passed, #{@failed} failed, #{@skipped} skipped"
    @failed.zero?
  end
end

def skip_unless(value, reason)
  raise Runner::Skipped, reason if value.nil? || (value.respond_to?(:empty?) && value.empty?)

  value
end

# A signature box to place on an uploaded PDF, so the packet has something to sign
def signature_field
  {
    id: "signature",
    type: "signature",
    pageNum: 1,
    rect: { x: 100, y: 100, width: 200, height: 40 }
  }
end

# A signer who signs through a URL this client generates, rather than by email,
# so running this sends no mail to anyone
def embedded_signer
  {
    id: "signer1",
    name: "Testy Signer",
    email: "testy@example.com",
    signerType: "embedded",
    fields: [{ fileId: "testFile", fieldId: "signature" }]
  }
end

api_key = ENV.fetch("ANVIL_API_KEY", nil)
base_url = ENV.fetch("ANVIL_BASE_URL", "https://staging.useanvil.com")
access_token = ENV.fetch("ANVIL_ACCESS_TOKEN", nil)

if api_key.nil? || api_key.empty?
  warn "ANVIL_API_KEY is required. Usage: ANVIL_API_KEY=<your staging API key> ruby test-client.rb"
  exit 1
end

client = Anvil::Client.new(api_key: api_key, base_url: base_url)
runner = Runner.new

puts "Testing ruby-anvil #{Anvil::VERSION} against #{base_url}"
puts

# What the later checks need, found as we go
cast_eid = ENV.fetch("ANVIL_PDF_TEMPLATE_ID", nil)
cast_data = nil
forge_eid = ENV.fetch("ANVIL_FORGE_EID", nil)
etch_packet_eid = nil
document_group_eid = nil
signer_eid = nil
weld_data_eid = nil
generated_pdf = nil

runner.check "request_graphql" do
  response = client.request_graphql(query: <<~GRAPHQL)
    query TestClient {
      currentUser { eid }
      organization {
        eid
        casts(limit: 50) { items { eid exampleData } }
        forges(isArchived: false) { eid }
      }
    }
  GRAPHQL

  organization = response["organization"] or raise "Expected an organization"
  with_example = (organization.dig("casts", "items") || []).find do |cast|
    cast["exampleData"] && !cast["exampleData"].empty?
  end

  cast_eid ||= with_example && with_example["eid"]
  cast_data = with_example && with_example["exampleData"]
  forge_eid ||= (organization["forges"] || []).map { |forge| forge["eid"] }.first

  "organization #{organization["eid"]}"
end

runner.check "rate limiting (adopted from the response headers)" do
  limiter = client.rate_limiter
  "#{limiter.tokens} requests per #{limiter.interval_ms}ms"
end

runner.check "OAuth access token (Bearer auth)" do
  skip_unless access_token, "Set ANVIL_ACCESS_TOKEN to check Bearer auth"

  oauth = Anvil::Client.new(access_token: access_token, base_url: base_url)
  response = oauth.request_graphql(query: "query CurrentUser { currentUser { eid } }")

  "current user #{response.dig("currentUser", "eid")}"
end

runner.check "request_rest" do
  response = client.request_rest(
    "/api/v1/generate-pdf",
    method: :post,
    body: { title: "request_rest", data: [{ label: "Check", content: "request_rest" }] }
  )

  "#{response.data.bytesize} bytes"
end

runner.check "generate_pdf (markdown)" do
  response = client.generate_pdf(
    title: "Test Markdown",
    data: [
      { label: "Name", content: "Sally Jones" },
      { content: "Lorem **ipsum** dolor sit _amet_" },
      { table: { firstRowHeaders: true, rows: [%w[Description Quantity], %w[Widgets 4]] } }
    ]
  )
  raise "Expected a PDF" unless response.data.start_with?("%PDF")

  generated_pdf = response.data
  "#{response.data.bytesize} bytes"
end

runner.check "generate_pdf (HTML)" do
  response = client.generate_pdf(
    Anvil::Payloads::GeneratePdf.new(
      title: "Test HTML",
      type: "html",
      data: {
        html: "<h1 class='title'>Hello</h1><p>Generated by the ruby-anvil test client.</p>",
        css: "body { font-size: 14px } .title { color: #171717 }"
      }
    )
  )
  raise "Expected a PDF" unless response.data.start_with?("%PDF")

  "#{response.data.bytesize} bytes"
end

runner.check "fill_pdf" do
  skip_unless cast_eid, "No PDF template with example data in this organization"

  response = client.fill_pdf(cast_eid, title: "Test Fill", data: cast_data || {})
  raise "Expected a PDF" unless response.data.start_with?("%PDF")

  "#{cast_eid}, #{response.data.bytesize} bytes"
end

runner.check "fill_pdf (VERSION_LATEST)" do
  skip_unless cast_eid, "No PDF template with example data in this organization"

  response = client.fill_pdf(
    cast_eid,
    { title: "Test Fill", data: cast_data || {} },
    version_number: Anvil::VERSION_LATEST
  )

  "#{response.data.bytesize} bytes"
end

runner.check "fill_pdf (streamed)" do
  skip_unless cast_eid, "No PDF template with example data in this organization"

  written = StringIO.new
  response = client.fill_pdf(
    cast_eid,
    { title: "Test Fill", data: cast_data || {} },
    data_type: :stream,
    to: written
  )
  raise "Expected a PDF" unless written.string.start_with?("%PDF")

  "#{response.data} bytes streamed"
end

runner.check "create_etch_packet (base64 upload)" do
  skip_unless generated_pdf, "generate_pdf did not produce a PDF to sign"

  packet = client.create_etch_packet(
    variables: Anvil::Payloads::CreateEtchPacket.new(
      name: "ruby-anvil test client",
      is_draft: false,
      is_test: true,
      signature_email_subject: "ruby-anvil test client",
      files: [
        Anvil::Payloads::EtchFile.new(
          id: "testFile",
          title: "Test File",
          file: { data: [generated_pdf].pack("m0"), filename: "test-client.pdf", mimetype: "application/pdf" },
          fields: [signature_field]
        )
      ],
      signers: [embedded_signer]
    )
  )

  etch_packet_eid = packet.eid
  document_group_eid = packet.document_group&.eid
  signer_eid = packet.signers.first&.eid

  packet.eid
end

runner.check "create_etch_packet (multipart file upload)" do
  skip_unless generated_pdf, "generate_pdf did not produce a PDF to upload"

  upload = Anvil.prepare_graphql_file(StringIO.new(generated_pdf), filename: "upload.pdf")
  packet = client.create_etch_packet(
    variables: {
      name: "ruby-anvil test client (multipart)",
      isDraft: true,
      isTest: true,
      files: [{ id: "testFile", title: "Uploaded File", file: upload, fields: [signature_field] }],
      signers: [embedded_signer]
    }
  )

  "draft #{packet.eid}"
end

runner.check "create_etch_packet (from a PDF template)" do
  skip_unless cast_eid, "No PDF template in this organization"

  packet = client.create_etch_packet(
    variables: {
      name: "ruby-anvil test client (template)",
      isDraft: true,
      isTest: true,
      files: [{ id: "template", castEid: cast_eid }],
      data: { payloads: { template: { data: cast_data || {} } } },
      signers: [embedded_signer.merge(fields: [{ fileId: "template", fieldId: "signature" }])]
    }
  )

  "draft #{packet.eid}"
end

runner.check "get_etch_packet" do
  skip_unless etch_packet_eid, "create_etch_packet did not produce a packet"

  packet = client.get_etch_packet(eid: etch_packet_eid)
  raise "Expected the packet we created" unless packet.eid == etch_packet_eid

  "#{packet.status}, #{packet.signers.length} signer(s)"
end

runner.check "get_etch_packet (custom response query)" do
  skip_unless etch_packet_eid, "create_etch_packet did not produce a packet"

  packet = client.get_etch_packet(eid: etch_packet_eid, response_query: "{ eid status }")
  raise "Expected only the fields we asked for" unless packet.name.nil?

  packet.eid
end

runner.check "generate_etch_sign_url" do
  skip_unless signer_eid, "create_etch_packet did not produce a signer"

  url = client.generate_etch_sign_url(signer_eid: signer_eid, client_user_id: "ruby-anvil-test-client")
  raise "Expected a URL, got #{url.inspect}" unless url.to_s.start_with?("http")

  "got a URL"
end

runner.check "download_documents" do
  skip_unless document_group_eid, "create_etch_packet did not produce a document group"

  response = client.download_documents(document_group_eid)
  raise "Expected a zip" unless response.data.start_with?("PK")

  "#{response.data.bytesize} bytes"
end

runner.check "download_documents (streamed to an IO)" do
  skip_unless document_group_eid, "create_etch_packet did not produce a document group"

  written = StringIO.new
  response = client.download_documents(document_group_eid, data_type: :stream, to: written)
  raise "Expected a zip" unless written.string.start_with?("PK")

  "#{response.data} bytes streamed"
end

runner.check "forge_submit" do
  skip_unless forge_eid, "No webform (Forge) in this organization"

  submission = client.forge_submit(
    variables: Anvil::Payloads::ForgeSubmit.new(
      forge_eid: forge_eid,
      payload: { name: "Sally Jones", email: "sally@example.com" },
      is_test: true,
      enforce_payload_valid_on_create: false
    )
  )

  weld_data_eid = submission.weld_data&.eid
  "#{forge_eid}, created #{submission.eid}"
end

runner.check "remove_weld_data" do
  skip_unless weld_data_eid, "forge_submit did not produce a submission to remove"
  raise "The API said it was not removed" unless client.remove_weld_data(eid: weld_data_eid)

  "removed #{weld_data_eid}"
end

runner.check "error handling (a rejected request raises a typed error)" do
  begin
    client.fill_pdf("notARealTemplateEid", data: {})
  rescue Anvil::ResponseError => e
    next "#{e.class.name.split("::").last} on HTTP #{e.status_code}"
  end

  raise "Expected the API to reject an unknown PDF template"
end

exit(runner.report ? 0 : 1)
