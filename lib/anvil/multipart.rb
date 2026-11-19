# frozen_string_literal: true

require "securerandom"
require "tempfile"

module Anvil
  # Encodes a GraphQL operation and its files as a multipart/form-data body,
  # following the GraphQL multipart request spec that the Anvil API implements.
  #
  # The body is assembled in a tempfile rather than a String so that uploading a
  # large PDF does not pull the whole thing into memory.
  #
  # @see https://github.com/jaydenseric/graphql-multipart-request-spec
  module Multipart
    CRLF = "\r\n"
    CHUNK_SIZE = 64 * 1024

    # A built body, ready to hand to Net::HTTP.
    class Body
      # @return [String] the multipart boundary
      attr_reader :boundary
      # @return [IO] the body, positioned at the start
      attr_reader :io
      # @return [Integer] the body's length in bytes
      attr_reader :content_length

      def initialize(boundary:, io:, content_length:)
        @boundary = boundary
        @io = io
        @content_length = content_length
      end

      # @return [String] the Content-Type header this body must be sent with
      def content_type
        "multipart/form-data; boundary=#{boundary}"
      end

      # Releases the tempfile backing the body.
      def close
        io.close! if io.respond_to?(:close!)
      rescue IOError
        nil
      end
    end

    module_function

    # @param operations [String] the JSON operation, with files nulled out
    # @param map [String] the JSON map of part names to variable paths
    # @param uploads [Array<UploadWithOptions>] in the same order as the map
    # @return [Body]
    def build(operations:, map:, uploads:)
      boundary = "anvil-#{SecureRandom.hex(16)}"
      io = Tempfile.new("anvil-upload")
      io.binmode

      write_field(io, boundary, "operations", operations)
      write_field(io, boundary, "map", map)
      uploads.each_with_index { |upload, index| write_file(io, boundary, (index + 1).to_s, upload) }
      io.write("--#{boundary}--#{CRLF}")

      content_length = io.size
      io.rewind
      Body.new(boundary: boundary, io: io, content_length: content_length)
    end

    # @api private
    def write_field(io, boundary, name, value)
      io.write("--#{boundary}#{CRLF}")
      io.write(%(Content-Disposition: form-data; name="#{escape(name)}"#{CRLF}))
      io.write(CRLF)
      io.write(value)
      io.write(CRLF)
    end

    # @api private
    def write_file(io, boundary, name, upload)
      filename = upload.filename
      raise ConfigurationError, "An upload is missing a filename" if filename.nil? || filename.empty?

      io.write("--#{boundary}#{CRLF}")
      io.write(
        %(Content-Disposition: form-data; name="#{escape(name)}"; filename="#{escape(filename)}"#{CRLF})
      )
      io.write("Content-Type: #{upload.mimetype}#{CRLF}")
      io.write(CRLF)

      upload.with_io do |source|
        while (chunk = source.read(CHUNK_SIZE))
          io.write(chunk)
        end
      end

      io.write(CRLF)
    end

    # Header values cannot carry a newline, and a quote would end the field name.
    #
    # @api private
    def escape(value)
      value.to_s.gsub(/[\r\n]/, "").gsub('"', "%22")
    end
  end
end
