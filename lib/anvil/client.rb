# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "stringio"
require "uri"

module Anvil
  # The Anvil API client.
  #
  #   client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))
  #   pdf = client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", data: { name: "Sally" })
  #   File.binwrite("filled.pdf", pdf.data)
  #
  # Every endpoint is derived from `base_url`, so pointing the client at
  # staging points all of it at staging:
  #
  #   Anvil::Client.new(api_key: key, base_url: "https://staging.useanvil.com")
  #
  # Requests are rate limited for you. The client starts conservatively, then
  # adopts your organization's real limit from the first response's headers. A
  # 429 is retried after the delay the API asks for.
  #
  # Failures raise: see {Anvil::Error} and its subclasses.
  class Client
    # Where the API lives unless you say otherwise.
    DEFAULT_BASE_URL = "https://app.useanvil.com"

    # What the client allows itself before the API tells it the real limit.
    DEFAULT_REQUEST_LIMIT = 1
    DEFAULT_REQUEST_LIMIT_MS = 1000

    # How many times a request the API could not answer is retried. Zero turns
    # it off. A 429 does not count against this: the limiter retries it for as
    # long as the API keeps asking.
    DEFAULT_MAX_RETRIES = 5

    # The statuses worth sending again: the API was reached but could not answer.
    RETRY_STATUSES = [500, 502, 503, 504].freeze

    # The first retry waits this long, each one after it twice as long.
    RETRY_BACKOFF_MS = 100

    # Seconds to wait for a connection, and for a response.
    DEFAULT_TIMEOUT = 300

    # The shapes a response body can be asked for.
    DATA_TYPES = %i[string io stream json].freeze
    # The shapes a PDF or a zip can be asked for.
    BINARY_DATA_TYPES = %i[string io stream].freeze

    # The HTTP methods {#request_rest} will send.
    HTTP_METHODS = {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete,
      head: Net::HTTP::Head
    }.freeze

    # @return [String] the API this client talks to, without a trailing slash
    attr_reader :base_url
    # @return [String] the Authorization header every request is sent with
    attr_reader :auth_header
    # @return [String] the User-Agent every request is sent with
    attr_reader :user_agent
    # @return [RateLimiter] the limiter in force, replaced once the API's own
    #   limit is known
    attr_reader :rate_limiter
    # @return [Integer] how many times a 429 is retried
    attr_reader :max_retries

    # @param api_key [String] an API key from your Anvil organization settings.
    #   Defaults to the `ANVIL_API_KEY` environment variable
    # @param access_token [String] an OAuth access token, instead of an API key
    # @param base_url [String] the Anvil environment to talk to
    # @param user_agent [String] overrides the User-Agent header
    # @param request_limit [Integer] requests allowed per interval before the
    #   API's own limit is known
    # @param request_limit_ms [Integer] that interval, in milliseconds
    # @param max_retries [Integer] how many times to retry a request the API
    #   could not answer. Zero turns it off; a 429 is always retried
    # @param timeout [Numeric] seconds to wait for a connection, and for a response
    # @param share_rate_limiter [Boolean] share one limiter per process with
    #   every other client for the same environment and credentials
    # @param rate_limiter [RateLimiter] a limiter of your own, instead
    # @raise [ConfigurationError] when neither an API key nor an access token
    #   was given
    def initialize(
      api_key: ENV.fetch("ANVIL_API_KEY", nil),
      access_token: nil,
      base_url: DEFAULT_BASE_URL,
      user_agent: nil,
      request_limit: DEFAULT_REQUEST_LIMIT,
      request_limit_ms: DEFAULT_REQUEST_LIMIT_MS,
      max_retries: DEFAULT_MAX_RETRIES,
      timeout: DEFAULT_TIMEOUT,
      share_rate_limiter: true,
      rate_limiter: nil
    )
      @auth_header = Auth.build_header(api_key: api_key, access_token: access_token)
      @base_url = (base_url || DEFAULT_BASE_URL).to_s.sub(%r{/+\z}, "")
      raise ConfigurationError, "base_url must be an http(s) URL" unless @base_url.match?(%r{\Ahttps?://})

      @user_agent = user_agent || "ruby-anvil/#{Anvil::VERSION}"
      @max_retries = max_retries.to_i
      @timeout = timeout
      @rate_limiter = rate_limiter || build_rate_limiter(share_rate_limiter, request_limit, request_limit_ms)
    end

    # Fills a PDF template with your data and returns the filled PDF.
    #
    #   pdf = client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", {
    #     title: "My PDF",
    #     data: { someFieldId: "Hello World!" }
    #   })
    #   File.binwrite("filled.pdf", pdf.data)
    #
    # @param pdf_template_id [String] the PDF template's eid, from its page in
    #   the Anvil dashboard
    # @param payload [Payloads::FillPdf, Hash] the data to fill it with. Its
    #   keys can be passed as keyword arguments instead
    # @param data_type [Symbol] `:string`, `:io` or `:stream`
    # @param version_number [Integer] which version of the template to fill.
    #   Defaults to the latest published version; pass {Anvil::VERSION_LATEST}
    #   for the current draft
    # @param to [IO] an IO to write a `:stream` response to
    # @yieldparam chunk [String] each chunk of a `:stream` response
    # @return [RestResponse]
    def fill_pdf(pdf_template_id, payload = nil, data_type: :string, version_number: nil, to: nil,
                 **payload_kwargs, &block)
      validate_data_type!(data_type, BINARY_DATA_TYPES)
      raise ConfigurationError, "A pdf_template_id is required" if blank?(pdf_template_id)

      path = "/api/v1/fill/#{escape(pdf_template_id)}.pdf"
      path = "#{path}?versionNumber=#{escape(version_number)}" unless version_number.nil?

      request_rest(
        path,
        method: :post,
        body: payload || payload_kwargs,
        data_type: data_type,
        to: to,
        &block
      )
    end

    # Generates a PDF from HTML and CSS, or from markdown.
    #
    #   pdf = client.generate_pdf(
    #     title: "Example",
    #     type: "html",
    #     data: { html: "<h1>Hello</h1>", css: "h1 { color: red }" }
    #   )
    #
    # @param payload [Payloads::GeneratePdf, Hash] the content to render. Its
    #   keys can be passed as keyword arguments instead
    # @param data_type [Symbol] `:string`, `:io` or `:stream`
    # @param to [IO] an IO to write a `:stream` response to
    # @yieldparam chunk [String] each chunk of a `:stream` response
    # @return [RestResponse]
    def generate_pdf(payload = nil, data_type: :string, to: nil, **payload_kwargs, &block)
      validate_data_type!(data_type, BINARY_DATA_TYPES)

      request_rest(
        "/api/v1/generate-pdf",
        method: :post,
        body: payload || payload_kwargs,
        data_type: data_type,
        to: to,
        &block
      )
    end

    # Downloads a document group's documents as a zip.
    #
    # @param document_group_eid [String]
    # @param data_type [Symbol] `:string`, `:io` or `:stream`
    # @param to [IO] an IO to write a `:stream` response to
    # @yieldparam chunk [String] each chunk of a `:stream` response
    # @return [RestResponse]
    def download_documents(document_group_eid, data_type: :string, to: nil, &block)
      validate_data_type!(data_type, BINARY_DATA_TYPES)
      raise ConfigurationError, "A document_group_eid is required" if blank?(document_group_eid)

      path = "/api/document-group/#{escape(document_group_eid)}.zip"
      request_rest(path, method: :get, data_type: data_type, to: to, &block)
    end

    # Creates an Etch e-sign packet, and sends it to the first signer unless
    # it is a draft.
    #
    #   packet = client.create_etch_packet(variables: Anvil::Payloads::CreateEtchPacket.new(
    #     name: "Test Docs",
    #     is_test: true,
    #     files: [Anvil::Payloads::EtchFile.new(id: "template", cast_eid: "05xXsZko33JIO6aq5Pnr")],
    #     signers: [Anvil::Payloads::EtchSigner.new(id: "signer1", name: "Sally", email: "sally@example.com")]
    #   ))
    #   packet.details_url
    #
    # @param variables [Payloads::CreateEtchPacket, Hash]
    # @param response_query [String] the fields to select on the new packet
    # @param mutation [String] replaces the whole mutation, response query and all
    # @return [Types::EtchPacket]
    def create_etch_packet(variables:, response_query: nil, mutation: nil)
      query = mutation || GraphQL::Mutations.create_etch_packet(*[response_query].compact)
      response = request_graphql(query: query, variables: variables)
      Types::EtchPacket.from_h(response["createEtchPacket"])
    end

    # Reads an Etch packet.
    #
    # @param eid [String] the packet's eid, a shorthand for `variables: { eid: }`
    # @param variables [Hash] the query's variables, when you would rather pass them whole
    # @param response_query [String] the fields to select
    # @return [Types::EtchPacket]
    def get_etch_packet(eid: nil, variables: nil, response_query: nil)
      variables = merge_variables({ "eid" => eid }, variables)
      query = GraphQL::Queries.etch_packet(*[response_query].compact)
      response = request_graphql(query: query, variables: variables)
      Types::EtchPacket.from_h(response["etchPacket"])
    end

    # Reads whoever the API key or access token belongs to.
    #
    #   user = client.get_current_user
    #   user.email
    #   user.organizations.map(&:slug)
    #
    # @param response_query [String] the fields to select
    # @return [Types::User]
    def get_current_user(response_query: nil)
      response = request_graphql(query: GraphQL::Queries.current_user(*[response_query].compact))
      Types::User.from_h(response["currentUser"])
    end

    # Generates a signing URL for one signer of an existing packet. The signer
    # must have been created with a `signer_type` of "embedded".
    #
    # @param signer_eid [String] the signer's eid, from the created packet
    # @param client_user_id [String] your own id for the person signing
    # @param variables [Hash] the mutation's variables, when you would rather
    #   pass them whole
    # @return [String] the URL to send the signer to
    def generate_etch_sign_url(signer_eid: nil, client_user_id: nil, variables: nil)
      variables = merge_variables(
        { "signerEid" => signer_eid, "clientUserId" => client_user_id },
        variables
      )
      response = request_graphql(query: GraphQL::Mutations.generate_etch_sign_url, variables: variables)
      response["generateEtchSignURL"]
    end

    # Submits data to one webform of a Workflow.
    #
    # @param variables [Payloads::ForgeSubmit, Hash]
    # @param response_query [String] the fields to select on the submission
    # @param mutation [String] replaces the whole mutation, response query and all
    # @return [Types::Submission]
    def forge_submit(variables:, response_query: nil, mutation: nil)
      query = mutation || GraphQL::Mutations.forge_submit(*[response_query].compact)
      response = request_graphql(query: query, variables: variables)
      Types::Submission.from_h(response["forgeSubmit"])
    end

    # Removes a Workflow submission and everything in it. This cannot be undone.
    #
    # @param eid [String] the weld data's eid, a shorthand for `variables: { eid: }`
    # @param variables [Hash] the mutation's variables, when you would rather
    #   pass them whole
    # @param mutation [String] replaces the whole mutation
    # @return [Boolean] whether it was removed
    # rubocop:disable-next Naming/PredicateMethod -- it answers with a boolean, it does not ask one
    def remove_weld_data(eid: nil, variables: nil, mutation: nil)
      variables = merge_variables({ "eid" => eid }, variables)
      query = mutation || GraphQL::Mutations.remove_weld_data
      response = request_graphql(query: query, variables: variables)
      !!response["removeWeldData"]
    end

    # Runs any GraphQL query or mutation, for the ones this client has no
    # method of its own for.
    #
    #   response = client.request_graphql(
    #     query: "query WeldData($eid: String!) { weldData(eid: $eid) { eid isComplete } }",
    #     variables: { eid: "nxflNZqxDUbltLUbYWK" }
    #   )
    #   response["weldData"]["isComplete"]
    #
    # Files anywhere in `variables` are uploaded as multipart, per the GraphQL
    # multipart request spec. Prepare each one with {Anvil.prepare_graphql_file}.
    #
    # @param query [String] the query or mutation
    # @param variables [Hash, Payloads::Base]
    # @return [GraphQLResponse]
    # @raise [GraphQLError] when the response carries GraphQL errors
    # @see https://www.useanvil.com/docs/api/graphql/reference/
    def request_graphql(query:, variables: {})
      operation = { query: query, variables: normalize_payload(variables) || {} }
      raise ConfigurationError, "Invalid File schema detected" unless Uploads.valid_upload_schema?(operation)

      clone, found = Uploads.extract_files(operation)
      operations = JSON.generate(clone)

      response =
        if found.empty?
          request_rest(
            "/graphql",
            method: :post,
            body: operations,
            headers: { "Content-Type" => "application/json" },
            data_type: :json
          )
        else
          request_multipart_graphql(operations: operations, found: found)
        end

      GraphQLResponse.new(status_code: response.status_code, headers: response.headers, body: response.data)
    end

    # Runs any REST request against the API, for the endpoints this client has
    # no method of its own for.
    #
    #   response = client.request_rest("/api/v1/generate-pdf", method: :post, body: payload)
    #
    # @param path [String] a path from `base_url`, or a whole URL
    # @param method [Symbol] `:get`, `:post`, `:put`, `:patch`, `:delete` or `:head`
    # @param body [Hash, Payloads::Base, String, nil] a Hash is sent as JSON
    # @param headers [Hash] extra request headers
    # @param data_type [Symbol] `:string`, `:io`, `:json` or `:stream`
    # @param to [IO] an IO to write a `:stream` response to
    # @yieldparam chunk [String] each chunk of a `:stream` response
    # @return [RestResponse]
    def request_rest(path, method: :get, body: nil, headers: {}, data_type: :string, to: nil, &block)
      validate_data_type!(data_type, DATA_TYPES)

      uri = build_uri(path)
      request = build_request(uri, method: method, headers: headers)
      apply_body(request, body)

      perform(uri, request, data_type: data_type, to: to, &block)
    end

    private

    def request_multipart_graphql(operations:, found:)
      map = {}
      found.each_with_index { |(_upload, paths), index| map[(index + 1).to_s] = paths }

      multipart = Multipart.build(operations: operations, map: JSON.generate(map), uploads: found.map(&:first))
      begin
        uri = build_uri("/graphql")
        request = build_request(uri, method: :post, headers: { "Content-Type" => multipart.content_type })
        request.body_stream = multipart.io
        request["Content-Length"] = multipart.content_length.to_s

        perform(uri, request, data_type: :json)
      ensure
        multipart.close
      end
    end

    # Runs the request under the rate limiter, which retries a 429 for as long
    # as the API keeps asking, and retries here what the API could not answer.
    def perform(uri, request, data_type:, to: nil, &block)
      attempt = 0

      begin
        rate_limiter.run do
          rewind_body(request)
          send_request(uri, request, data_type: data_type, to: to, &block)
        end
      rescue ServerError, ConnectionError => e
        attempt += 1
        raise if attempt > max_retries || !retryable?(e)

        sleep(retry_delay(e, attempt))
        retry
      end
    end

    # A 5xx the API named as temporary, or a connection that never got there.
    # A timeout is not retried: the request may well have been acted on.
    def retryable?(error)
      return RETRY_STATUSES.include?(error.status_code) if error.is_a?(ServerError)

      !error.cause_error.is_a?(Timeout::Error)
    end

    # The delay the response asked for, or exponential backoff.
    def retry_delay(error, attempt)
      asked = error.is_a?(ServerError) ? error.headers["retry-after"] : nil
      return RateLimiter.retry_delay_seconds(asked) if asked

      (RETRY_BACKOFF_MS * (2**(attempt - 1))) / 1000.0
    end

    def send_request(uri, request, data_type:, to: nil, &block)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout
      http.read_timeout = @timeout

      # Net::HTTP#request hands back the raw response, not the block's value,
      # so the handled result comes out through this
      result = nil
      http.start do |session|
        session.request(request) do |response|
          result = handle_response(response, data_type: data_type, to: to, &block)
        end
      end
      result
    rescue Timeout::Error, SystemCallError, IOError, OpenSSL::SSL::SSLError,
           Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, SocketError => e
      raise ConnectionError.new("Could not reach #{uri}: #{e.message}", cause_error: e)
    end

    def handle_response(response, data_type:, to: nil, &block)
      status_code = response.code.to_i
      headers = normalize_headers(response)
      rate_limiter.update_from_headers(headers)

      raise_rate_limited(response, status_code, headers) if status_code == 429

      # Whatever was asked for, a JSON body is read and parsed: the GraphQL
      # endpoint reports failure in a 200, and the REST endpoints answer with
      # JSON when they fail even though they return PDFs when they succeed.
      raw = json?(headers["content-type"]) ? read_all(response) : nil
      json = raw && parse_json(raw)

      check_for_errors(response, status_code, headers, raw, json)
      data = extract_data(response, data_type: data_type, to: to, raw: raw, json: json, &block)

      RestResponse.new(status_code: status_code, headers: headers, data: data)
    end

    def check_for_errors(response, status_code, headers, raw, json)
      # GraphQL reports failure in a 200, so its errors array is checked whatever
      # the status. A 2xx carrying only `message` or `name` is NOT an error: node
      # treats it as one, and the SDK conventions call that a legacy divergence.
      raise_response_error(status_code, json, headers, response.message) if graphql_errors?(json)
      return if status_code < 300

      raise_response_error(
        status_code, json, headers, response.message,
        body: json || raw || read_all(response)
      )
    end

    def extract_data(response, data_type:, to:, raw:, json:, &block)
      case data_type
      when :json then json || parse_json(raw || read_all(response))
      when :io then StringIO.new(raw || read_all(response))
      when :stream then stream_body(response, to: to, raw: raw, &block)
      else raw || read_all(response)
      end
    end

    # Hands each chunk to the block or writes it to `to:` as it arrives, so a
    # large PDF never has to be held whole.
    def stream_body(response, to:, raw: nil, &block)
      raise ConfigurationError, "A data_type of :stream needs a block or a `to:` IO to write to" unless block || to

      written = 0
      consume = lambda do |chunk|
        written += chunk.bytesize
        to&.write(chunk)
        block&.call(chunk)
      end

      # A JSON body was already read whole to check it for errors
      if raw
        consume.call(raw)
      else
        response.read_body { |chunk| consume.call(chunk) }
      end

      written
    end

    def raise_rate_limited(response, status_code, headers)
      drain(response)
      retry_after = headers["retry-after"]&.to_f

      raise RateLimitError.new(
        "Rate limited by the Anvil API. Retry after #{retry_after || "an unspecified number of"} seconds.",
        retry_after: retry_after,
        status_code: status_code,
        headers: headers
      )
    end

    def graphql_errors?(json)
      json.is_a?(Hash) && json["errors"].is_a?(Array) && !json["errors"].empty?
    end

    def raise_response_error(status_code, json, headers, status_text, body: nil)
      errors = Errors.normalize(json, status_text: blank?(status_text) ? "Unknown Error" : status_text)

      error_class =
        if status_code >= 300
          Errors.error_class_for(status_code)
        elsif graphql_errors?(json)
          # GraphQL answers 200 even when the query failed
          GraphQLError
        else
          ResponseError
        end

      raise error_class.new(
        nil,
        status_code: status_code,
        errors: errors,
        body: body.nil? ? json : body,
        headers: headers
      )
    end

    def build_uri(path)
      url = path.to_s.start_with?("http://", "https://") ? path.to_s : "#{base_url}#{path}"
      URI.parse(url)
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid URL #{path.inspect}: #{e.message}"
    end

    def build_request(uri, method:, headers: {})
      klass = HTTP_METHODS[method.to_s.downcase.to_sym]
      raise ConfigurationError, "Unsupported HTTP method #{method.inspect}" if klass.nil?

      request = klass.new(uri)
      request["Authorization"] = auth_header
      request["User-Agent"] = user_agent
      # Streaming a response is simpler, and the chunk sizes honest, when the
      # body is not compressed in flight
      request["Accept-Encoding"] = "identity"
      headers.each { |name, value| request[name.to_s] = value unless value.nil? }
      request
    end

    def apply_body(request, body)
      return if body.nil?
      return if body.respond_to?(:empty?) && body.empty? && !body.is_a?(String)

      if body.is_a?(String)
        request.body = body
        return
      end

      request["Content-Type"] ||= "application/json"
      request.body = JSON.generate(normalize_payload(body))
    end

    def rewind_body(request)
      request.body_stream&.rewind
    rescue IOError, NoMethodError
      nil
    end

    # Turns a payload object into the Hash the API wants, and leaves a Hash alone.
    def normalize_payload(payload)
      return nil if payload.nil?
      return payload.to_h if payload.is_a?(Payloads::Base)

      payload
    end

    def merge_variables(named, variables)
      given = normalize_payload(variables) || {}
      named.compact.merge(given.to_h)
    end

    def build_rate_limiter(shared, limit, interval_ms)
      return RateLimiter.new(limit: limit, interval_ms: interval_ms) unless shared

      RateLimiter.shared(
        base_url: @base_url,
        auth_header: @auth_header,
        limit: limit,
        interval_ms: interval_ms
      )
    end

    def normalize_headers(response)
      response.each_header.to_h { |name, value| [name.to_s.downcase, value] }
    end

    def json?(content_type)
      content_type.to_s.downcase.include?("application/json")
    end

    def parse_json(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ConnectionError.new("Could not parse the API's JSON response: #{e.message}", cause_error: e)
    end

    def read_all(response)
      response.read_body || ""
    end

    def drain(response)
      response.read_body { |_chunk| nil }
    rescue IOError
      nil
    end

    def validate_data_type!(data_type, allowed)
      return if allowed.include?(data_type)

      raise ConfigurationError, "data_type must be one of #{allowed.map(&:inspect).join(", ")}"
    end

    def escape(value)
      URI.encode_www_form_component(value.to_s)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
