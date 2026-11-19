# frozen_string_literal: true

require_relative "anvil/version"
require_relative "anvil/errors"
require_relative "anvil/auth"
require_relative "anvil/rate_limiter"
require_relative "anvil/upload_with_options"
require_relative "anvil/uploads"
require_relative "anvil/multipart"
require_relative "anvil/graphql"
require_relative "anvil/response"
require_relative "anvil/types/base"
require_relative "anvil/payloads/base"
# Generated from the API specs: every type, then the hand-written files reopen them
require_relative "anvil/types/generated/graphql"
require_relative "anvil/types/generated/operations"
require_relative "anvil/types/generated/rest"
require_relative "anvil/types/etch_packet"
require_relative "anvil/payloads/fill_pdf"
require_relative "anvil/payloads/generate_pdf"
require_relative "anvil/payloads/etch_signer"
require_relative "anvil/payloads/etch_file"
require_relative "anvil/payloads/create_etch_packet"
require_relative "anvil/payloads/forge_submit"
require_relative "anvil/client"

# The Anvil API client for Ruby.
#
#   client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))
#
# @see https://www.useanvil.com/docs/api/getting-started
module Anvil
  # The version number to pass as a PDF template's `version_number` to use the
  # latest version, published or not. That is usually the current draft.
  VERSION_LATEST = -1

  # The version number to pass as a PDF template's `version_number` to use the
  # latest published version. This is what the API uses when no version is
  # given.
  VERSION_LATEST_PUBLISHED = -2

  # The response types the API's objects are returned as.
  module Types; end

  # Prepares a file for upload through the GraphQL API.
  #
  #   file = Anvil.prepare_graphql_file("./contract.pdf")
  #   file = Anvil.prepare_graphql_file(File.open("./contract.pdf", "rb"))
  #   file = Anvil.prepare_graphql_file(StringIO.new(bytes), filename: "contract.pdf")
  #
  # Put the result wherever the API takes an `Upload`, which is always the
  # `file` key of an object:
  #
  #   client.create_etch_packet(variables: {
  #     files: [{ id: "contract", title: "Contract", file: file }]
  #   })
  #
  # The client uploads it as multipart, per the GraphQL multipart request spec.
  # This is the Ruby equivalent of node-anvil's `Anvil.prepareGraphQLFile()`.
  #
  # @param file [String, Pathname, IO, StringIO, Tempfile] a path to a file, or
  #   an open IO holding its bytes
  # @param filename [String] the name to upload it under. Required for an IO
  #   that has no path of its own, since there is nothing to derive a name from
  # @param mimetype [String] the content type to upload it under. Guessed from
  #   the filename's extension otherwise
  # @param ignore_filename_validation [Boolean] send an IO with no derivable
  #   filename anyway
  # @param options [Hash] any other options, kept on the returned object
  # @return [UploadWithOptions]
  # @raise [ConfigurationError] when the path does not exist, or a filename
  #   could not be worked out
  # @see https://github.com/jaydenseric/graphql-multipart-request-spec
  def self.prepare_graphql_file(file, filename: nil, mimetype: nil, ignore_filename_validation: false, **options)
    upload = UploadWithOptions.new(
      file,
      options.merge(
        filename: filename,
        mimetype: mimetype,
        ignore_filename_validation: ignore_filename_validation
      ).compact
    )

    if upload.path?
      raise ConfigurationError, "No file at #{file.to_s.inspect} to upload" unless File.file?(file.to_s)
    elsif !file.respond_to?(:read)
      raise ConfigurationError,
            "prepare_graphql_file takes a path or an IO, not a #{file.class}. " \
            "To upload bytes you already have, wrap them in a StringIO and pass a filename."
    elsif !ignore_filename_validation && (upload.filename.nil? || upload.filename.empty?)
      raise ConfigurationError,
            "When passing a #{file.class} to prepare_graphql_file, `filename:` must be provided. " \
            "If you think you can ignore this, pass `ignore_filename_validation: true`."
    end

    upload
  end
end
