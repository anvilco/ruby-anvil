# frozen_string_literal: true

require "pathname"

module Anvil
  # A file to upload through the GraphQL API, together with the filename and
  # mimetype to send it under.
  #
  # Build one with {Anvil.prepare_graphql_file} rather than calling `new`
  # directly: that is where the checks live. This is the Ruby equivalent of
  # node-anvil's `UploadWithOptions`.
  class UploadWithOptions
    # Extensions worth naming. Anything else is sent as application/octet-stream,
    # which Anvil sniffs.
    MIMETYPES = {
      ".pdf" => "application/pdf",
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".tif" => "image/tiff",
      ".tiff" => "image/tiff",
      ".bmp" => "image/bmp",
      ".webp" => "image/webp",
      ".svg" => "image/svg+xml",
      ".txt" => "text/plain",
      ".html" => "text/html",
      ".htm" => "text/html",
      ".csv" => "text/csv",
      ".json" => "application/json",
      ".xml" => "application/xml",
      ".doc" => "application/msword",
      ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".xls" => "application/vnd.ms-excel",
      ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ".zip" => "application/zip"
    }.freeze

    DEFAULT_MIMETYPE = "application/octet-stream"

    # @return [String, Pathname, IO] the path or IO this wraps
    attr_reader :file
    # @return [Hash] the options it was prepared with
    attr_reader :options

    # @param file [String, Pathname, IO]
    # @param options [Hash]
    # @option options [String] :filename
    # @option options [String] :mimetype
    # @option options [Boolean] :ignore_filename_validation
    def initialize(file, options = {})
      @file = file
      @options = options.transform_keys(&:to_sym)
    end

    # @return [String, nil] the name the file is uploaded under
    def filename
      @options[:filename] || derived_filename
    end

    # @return [String] the content type the file is uploaded under
    def mimetype
      @options[:mimetype] || MIMETYPES.fetch(extension, DEFAULT_MIMETYPE)
    end

    # @return [Boolean] whether this wraps a path rather than an open IO
    def path?
      file.is_a?(String) || file.is_a?(Pathname)
    end

    # Yields an IO positioned at the start of the file's bytes. Opens and
    # closes the file when this wraps a path; rewinds when it can otherwise.
    #
    # @yieldparam io [IO]
    # @return [Object] whatever the block returned
    def with_io
      if path?
        File.open(file.to_s, "rb") { |io| return yield(io) }
      else
        file.rewind if file.respond_to?(:rewind)
        yield(file)
      end
    end

    # @return [Integer, nil] the file's size in bytes when it is knowable
    #   without reading the whole thing
    def size
      return File.size(file.to_s) if path?
      return file.size if file.respond_to?(:size)

      nil
    end

    private

    def derived_filename
      source = if path?
                 file.to_s
               elsif file.respond_to?(:path) && file.path.is_a?(String)
                 file.path
               elsif file.respond_to?(:original_filename)
                 file.original_filename
               end

      source && File.basename(source)
    end

    def extension
      name = filename
      name ? File.extname(name).downcase : ""
    end
  end
end
