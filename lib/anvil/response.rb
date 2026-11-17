# frozen_string_literal: true

module Anvil
  # What the escape hatches {Client#request_rest} and {Client#request_graphql}
  # return. The methods with a name of their own return the useful part
  # directly instead: the PDF's bytes, the typed packet, the sign URL.
  class Response
    # @return [Integer] the HTTP status code
    attr_reader :status_code
    # @return [Hash{String => String}] the response headers, keys downcased
    attr_reader :headers

    def initialize(status_code:, headers: {})
      @status_code = status_code
      @headers = headers
    end

    # @return [Boolean]
    def success?
      status_code.between?(200, 299)
    end

    # @return [String, nil]
    def content_type
      headers["content-type"]
    end
  end

  # A response from a REST endpoint.
  class RestResponse < Response
    # The body, in the shape asked for by `data_type`:
    #
    # - `:string` (the default) a binary String
    # - `:io` a StringIO holding the whole body
    # - `:json` the parsed JSON
    # - `:stream` the number of bytes handed to your block or written to `to:`
    #
    # @return [String, StringIO, Hash, Array, Integer, nil]
    attr_reader :data

    def initialize(status_code:, headers: {}, data: nil)
      super(status_code: status_code, headers: headers)
      @data = data
    end

    # @return [Integer, nil] the body's length in bytes, when it is known
    def content_length
      length = headers["content-length"]
      length&.to_i
    end
  end

  # A response from the GraphQL endpoint.
  #
  # A GraphQL request that fails raises {GraphQLError} rather than returning a
  # response with an `errors` array, so anything you get back here succeeded.
  class GraphQLResponse < Response
    # @return [Hash] the whole response body, `{"data" => {...}}`
    attr_reader :body

    def initialize(status_code:, headers: {}, body: nil)
      super(status_code: status_code, headers: headers)
      @body = body.is_a?(Hash) ? body : {}
    end

    # The `data` map of the GraphQL response: a key per operation in the query.
    #
    # @return [Hash]
    def data
      value = body["data"]
      value.is_a?(Hash) ? value : {}
    end

    # The result of one operation in the query.
    #
    #   response["createEtchPacket"]
    #
    # @param name [String, Symbol] the operation's name in the response
    # @return [Object, nil]
    def [](name)
      data[name.to_s]
    end
  end
end
