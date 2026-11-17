# frozen_string_literal: true

require "pathname"
require "stringio"
require "tempfile"

module Anvil
  # Finds the files in a GraphQL operation and checks they are somewhere the
  # Anvil API will accept them.
  #
  # Ported from node-anvil's `src/validation.js` and its use of `extract-files`,
  # so an operation that uploads in one client uploads in the other.
  module Uploads
    module_function

    # Is this value something we should upload as a file rather than send as
    # JSON? A String is not: node-anvil treats strings as paths only when they
    # were handed to {Anvil.prepare_graphql_file}, and so do we.
    #
    # @param value [Object]
    # @return [Boolean]
    def file?(value)
      value.is_a?(UploadWithOptions) ||
        value.is_a?(IO) ||
        value.is_a?(StringIO) ||
        value.is_a?(Tempfile) ||
        value.is_a?(Pathname)
    end

    # Replaces every file in the operation with null and records where it was,
    # which is what the multipart request spec needs.
    #
    # @param operation [Hash] `{ query:, variables: }`
    # @return [Array(Hash, Array<Array(UploadWithOptions, Array<String>)>)] the
    #   operation with files nulled out, and each upload with the paths it was
    #   found at
    # @see https://github.com/jaydenseric/graphql-multipart-request-spec
    def extract_files(operation)
      found = {}.compare_by_identity
      clone = walk(operation, nil, found)
      [clone, found.values]
    end

    # Checks the places files appear. The API only accepts an upload as the
    # `file` key of an object, never at the top level or under another name.
    #
    # @param schema [Object] the operation, or any part of it
    # @param parent [Object, nil]
    # @param key [Object, nil]
    # @return [Boolean]
    def valid_upload_schema?(schema, parent = nil, key = nil)
      return true if schema.nil?
      return valid_file_value?(schema, parent) if key.to_s == "file"

      case schema
      when Array then schema.all? { |sub| valid_upload_schema?(sub, schema) }
      when Hash then schema.all? { |sub_key, sub| valid_upload_schema?(sub, schema, sub_key) }
      else
        # A file anywhere other than under a `file` key is a mistake
        !file?(schema)
      end
    end

    # The value under a `file` key, which is where every kind of upload goes.
    #
    # @api private
    def valid_file_value?(schema, parent)
      # Every flavor has to be nested in an object, never passed on its own
      return false unless parent.is_a?(Hash) && fetch_either(parent, :file).equal?(schema)
      return file?(schema) unless schema.is_a?(Hash)

      # A base64 upload: `{ file: { data:, filename:, mimetype: } }`
      if fetch_either(schema, :data)
        return fetch_either(schema, :data).is_a?(String) &&
               %i[filename mimetype].all? { |required| fetch_either(schema, required) }
      end

      # A URL upload, which Anvil fetches itself: `{ file: { url: } }`.
      # node-anvil rejects this shape; the API takes it, so we allow it.
      return fetch_either(schema, :url).is_a?(String) if fetch_either(schema, :url)

      false
    end

    # @api private
    def walk(value, path, found)
      if file?(value)
        record(value, path, found)
        return nil
      end

      case value
      when Hash
        value.each_with_object({}) do |(key, sub), clone|
          clone[key] = walk(sub, join(path, key), found)
        end
      when Array
        value.each_with_index.map { |sub, index| walk(sub, join(path, index), found) }
      else
        value
      end
    end

    # @api private
    def record(value, path, found)
      entry = found[value] ||= [value.is_a?(UploadWithOptions) ? value : Anvil.prepare_graphql_file(value), []]
      entry.last << path
      entry
    end

    # @api private
    def join(path, key)
      path ? "#{path}.#{key}" : key.to_s
    end

    # @api private
    def fetch_either(hash, key)
      hash[key.to_s] || hash[key.to_sym]
    end
  end
end
