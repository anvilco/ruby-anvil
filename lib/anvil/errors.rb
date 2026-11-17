# frozen_string_literal: true

module Anvil
  # Base class for everything this client raises. Rescue it to catch any
  # client or API failure.
  class Error < StandardError; end

  # Raised when the client is constructed or called with unusable arguments,
  # before any request is made.
  class ConfigurationError < Error; end

  # Raised when a request could not be completed at all: a connection reset, a
  # DNS failure, a timeout, an unparseable response body.
  class ConnectionError < Error
    # @return [Exception, nil] the underlying exception, when there was one
    attr_reader :cause_error

    def initialize(message, cause_error: nil)
      super(message)
      @cause_error = cause_error
    end
  end

  # A single field-level problem inside an {ErrorDetail}, as returned by the
  # REST API's validation errors:
  #
  #   { "name": "ValidationError", "fields": [{ "message": "Required", "property": "data" }] }
  class ErrorField
    # @return [String, nil]
    attr_reader :message
    # @return [String, nil] the name of the offending field
    attr_reader :property
    # @return [Hash] the field as the API returned it
    attr_reader :raw

    def initialize(message: nil, property: nil, raw: {})
      @message = message
      @property = property
      @raw = raw
    end

    # @param hash [Hash]
    # @return [ErrorField]
    def self.from_h(hash)
      hash = { "message" => hash.to_s } unless hash.is_a?(Hash)
      new(
        message: hash["message"] || hash[:message],
        property: hash["property"] || hash[:property],
        raw: hash
      )
    end

    def to_s
      property ? "#{property}: #{message}" : message.to_s
    end

    def to_h
      raw
    end
  end

  # One normalized error from an API response. Both GraphQL errors and the
  # REST API's error bodies are normalized into these.
  class ErrorDetail
    # @return [String, nil] the error class the API reported, e.g. "ValidationError"
    attr_reader :name
    # @return [String, nil]
    attr_reader :message
    # @return [Array<ErrorField>] field-level details, empty when there are none
    attr_reader :fields
    # @return [Array<String>, nil] a GraphQL error's path into the query
    attr_reader :path
    # @return [Hash] the error as the API returned it, including any keys not
    #   broken out above
    attr_reader :raw

    def initialize(name: nil, message: nil, fields: [], path: nil, raw: {})
      @name = name
      @message = message
      @fields = fields
      @path = path
      @raw = raw
    end

    # @param hash [Hash, String]
    # @return [ErrorDetail]
    def self.from_h(hash)
      return new(message: hash.to_s, raw: { "message" => hash.to_s }) unless hash.is_a?(Hash)

      fields = hash["fields"] || hash[:fields] || []
      fields = [] unless fields.is_a?(Array)

      new(
        name: hash["name"] || hash[:name],
        message: hash["message"] || hash[:message],
        fields: fields.map { |field| ErrorField.from_h(field) },
        path: hash["path"] || hash[:path],
        raw: hash
      )
    end

    def to_s
      parts = [name, message].compact.uniq
      base = parts.empty? ? "Unknown Error" : parts.join(": ")
      return base if fields.empty?

      "#{base} (#{fields.join(", ")})"
    end

    def to_h
      raw
    end
  end

  # Raised when the API answered but the answer was an error. Carries the HTTP
  # status code and the normalized errors.
  class ResponseError < Error
    # @return [Integer, nil] the HTTP status code
    attr_reader :status_code
    # @return [Array<ErrorDetail>]
    attr_reader :errors
    # @return [Object, nil] the parsed response body, when it was JSON
    attr_reader :body
    # @return [Hash] the response headers, keys downcased
    attr_reader :headers

    def initialize(message = nil, status_code: nil, errors: [], body: nil, headers: {})
      @status_code = status_code
      @errors = errors
      @body = body
      @headers = headers
      super(message || self.class.summarize(errors, status_code))
    end

    # @return [ErrorDetail, nil] the first error, which is the only one for
    #   most REST failures
    def error
      errors.first
    end

    # @return [Array<ErrorField>] every field-level error across all errors
    def fields
      errors.flat_map(&:fields)
    end

    # @api private
    def self.summarize(errors, status_code)
      return "HTTP #{status_code || "error"}" if errors.nil? || errors.empty?

      errors.join("; ")
    end
  end

  # A GraphQL response that carried an `errors` array. GraphQL answers with
  # HTTP 200 even when the query failed, so this can be raised on a 200.
  class GraphQLError < ResponseError; end

  # A 4xx response.
  class ClientError < ResponseError; end

  # 401: the API key or access token was missing or not accepted.
  class AuthenticationError < ClientError; end

  # 403: authenticated, but not allowed to do this.
  class ForbiddenError < ClientError; end

  # 404: no such resource.
  class NotFoundError < ClientError; end

  # 400 or 422: the request was understood but rejected. Check {#fields} for
  # which parts of the payload were at fault.
  class ValidationError < ClientError; end

  # 429, still rate limited after the client's retries were used up.
  class RateLimitError < ClientError
    # @return [Float, nil] the retry-after the API asked for, in seconds
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **kwargs)
      @retry_after = retry_after
      super(message, **kwargs)
    end
  end

  # A 5xx response.
  class ServerError < ResponseError; end

  # Turns the many shapes an Anvil error response can take into {ErrorDetail}s,
  # and picks the exception class for a status code.
  #
  # Ported from node-anvil's `src/errors.js` so both clients treat the same
  # response the same way.
  module Errors
    module_function

    # Does this parsed JSON body look like an error, whatever its status code?
    #
    # @param json [Object]
    # @return [Boolean]
    def looks_like_json_error?(json)
      return false unless json.is_a?(Hash)

      !!(json["errors"] || json["message"] || json["name"])
    end

    # @param json [Object, nil] the parsed response body
    # @param status_text [String] the HTTP reason phrase, used when the body
    #   says nothing useful
    # @return [Array<ErrorDetail>] always at least one error
    def normalize(json, status_text: "Unknown Error")
      if json.is_a?(Hash)
        # The GraphQL way, and some REST errors
        errors = json["errors"]
        return errors.map { |error| ErrorDetail.from_h(error) } if errors.is_a?(Array) && !errors.empty?

        # The other REST way:
        #   { "name": "AssertionError", "message": "PDF did not generate properly from given HTML!" }
        # or
        #   { "name": "ValidationError", "fields": [{ "message": "Required", "property": "data" }] }
        return [ErrorDetail.from_h(json)] if json["message"] || json["name"]
      end

      [ErrorDetail.new(name: status_text, message: status_text,
                       raw: { "name" => status_text, "message" => status_text })]
    end

    # @param status_code [Integer, nil]
    # @return [Class] the {ResponseError} subclass for this status
    def error_class_for(status_code)
      case status_code
      when 400, 422 then ValidationError
      when 401 then AuthenticationError
      when 403 then ForbiddenError
      when 404 then NotFoundError
      when 429 then RateLimitError
      when 500..599 then ServerError
      when 300..499 then ClientError
      else ResponseError
      end
    end
  end
end
