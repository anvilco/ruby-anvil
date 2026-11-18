# frozen_string_literal: true

require "json"

module Anvil
  # Builds the Authorization header, the same way node-anvil and python-anvil do.
  #
  # An API key goes as HTTP Basic, `base64(api_key + ":")`: a username with an
  # empty password. Anvil's OAuth access tokens are JWTs, which the API wants
  # verbatim; any other token is base64 encoded, which the API still accepts for
  # backwards compatibility.
  module Auth
    # Three dot-separated base64url segments. The signature can be empty.
    JWT_PATTERN = /\A[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*\z/

    module_function

    # @param api_key [String, nil]
    # @param access_token [String, nil] wins when both are given
    # @return [String]
    # @raise [ConfigurationError] when neither is given
    def build_header(api_key: nil, access_token: nil)
      unless access_token.nil? || access_token.empty?
        return "Bearer #{access_token}" if jwt?(access_token)

        return "Bearer #{encode(access_token)}"
      end
      return "Basic #{encode("#{api_key}:")}" unless api_key.nil? || api_key.empty?

      raise ConfigurationError, "An api_key or an access_token is required"
    end

    # Whether a token is a JWT: three base64url segments whose header and
    # payload decode to JSON objects, the header carrying a string `alg`.
    #
    # Stricter than the API's own check, so anything this says yes to the API
    # treats as a JWT too.
    #
    # @param token [Object]
    # @return [Boolean]
    def jwt?(token)
      return false unless token.is_a?(String) && token.match?(JWT_PATTERN)

      header, payload = token.split(".").first(2).map { |segment| decode_json_segment(segment) }
      !!(header && payload && header["alg"].is_a?(String))
    end

    # Decodes one base64url segment of a JWT. Done with pack/unpack rather than
    # the base64 gem, which stopped being a default gem in Ruby 3.4, so the gem
    # keeps no runtime dependencies.
    #
    # @api private
    def decode_json_segment(segment)
      padded = segment + ("=" * (-segment.length % 4))
      decoded = JSON.parse(padded.tr("-_", "+/").unpack1("m0"))
      decoded.is_a?(Hash) ? decoded : nil
    rescue ArgumentError, JSON::ParserError, Encoding::CompatibilityError
      nil
    end

    # Strict base64, no line breaks.
    #
    # @api private
    def encode(value)
      [value].pack("m0")
    end
  end
end
