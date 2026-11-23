# frozen_string_literal: true

require "time"

module Anvil
  module Types
    # The attribute DSL shared by the response types in {Anvil::Types} and the
    # request payloads in {Anvil::Payloads}.
    #
    # It exists to map between Ruby's snake_case and the API's camelCase (and
    # its handful of names like `webhookURL` that no rule produces), and to
    # build nested objects out of nested JSON.
    #
    # @api private
    module Attributes
      def self.included(base)
        base.extend(ClassMethods)
      end

      # @api private
      module ClassMethods
        # @return [Hash{Symbol => Hash}] every attribute, including inherited ones
        def attributes
          @attributes ||= (superclass.respond_to?(:attributes) ? superclass.attributes.dup : {})
        end

        # Declares an attribute.
        #
        # @param name [Symbol] the Ruby name, in snake_case
        # @param key [String] the API's name for it. Defaults to `name` camelized
        # @param type [Class, Symbol, nil] `:time` to parse a timestamp, or a
        #   {Types::Base} subclass to build from a nested object
        # @param array_of [Class, nil] a {Types::Base} subclass to build each
        #   element of an array from
        # @return [void]
        def attribute(name, key: nil, type: nil, array_of: nil)
          attributes[name.to_sym] = {
            name: name.to_sym,
            key: key || camelize(name),
            type: type,
            array_of: array_of
          }
          attr_accessor name
        end

        # "signer_type" => "signerType"
        #
        # @api private
        def camelize(name)
          head, *rest = name.to_s.split("_")
          ([head] + rest.map(&:capitalize)).join
        end

        # @api private
        def cast(value, definition)
          return nil if value.nil?

          if definition[:array_of]
            return value unless value.is_a?(Array)

            return value.map { |element| definition[:array_of].from_h(element) }
          end

          case definition[:type]
          when nil then value
          when :time then parse_time(value)
          else definition[:type].from_h(value)
          end
        end

        # @api private
        def parse_time(value)
          return value if value.is_a?(Time)

          Time.iso8601(value.to_s)
        rescue ArgumentError
          value
        end
      end
    end

    # An object the API returned.
    #
    # Every declared field has a reader. Anything the API sent that this client
    # does not know about is still there in {#raw}, so a new API field is
    # reachable without a client release, and a custom `response_query` that
    # selects fields this class does not declare still returns all of them.
    class Base
      include Attributes

      # @return [Hash] the object exactly as the API returned it
      attr_reader :raw

      # @param raw [Hash]
      def initialize(raw = {})
        @raw = raw.is_a?(Hash) ? raw : {}
      end

      # @param hash [Hash, nil]
      # @return [Base, nil] nil when there was nothing to build from
      def self.from_h(hash)
        return nil if hash.nil?
        return hash if hash.is_a?(self)

        instance = new(hash)
        return instance unless hash.is_a?(Hash)

        attributes.each_value do |definition|
          value = hash.key?(definition[:key]) ? hash[definition[:key]] : hash[definition[:name]]
          instance.public_send(:"#{definition[:name]}=", cast(value, definition))
        end
        instance
      end

      # Reads a field by its API name, including fields this class does not
      # declare.
      #
      # @param key [String, Symbol]
      # @return [Object, nil]
      def [](key)
        raw[key.to_s].nil? ? raw[key.to_sym] : raw[key.to_s]
      end

      # Reaches into a field the way {#[]} does, and on down the path.
      #
      #   packet.dig("documentGroup", "signers", 0, "eid")
      #
      # @param key [String, Symbol]
      # @param rest [Array<String, Symbol, Integer>]
      # @return [Object, nil]
      def dig(key, *rest)
        value = self[key]
        rest.empty? ? value : value&.dig(*rest)
      end

      # @return [Hash] the object as the API returned it
      def to_h
        raw
      end

      def ==(other)
        other.is_a?(self.class) && other.raw == raw
      end
      alias eql? ==

      def hash
        [self.class, raw].hash
      end

      def inspect
        shown = self.class.attributes.each_key.filter_map do |name|
          value = public_send(name)
          "#{name}=#{value.inspect}" unless value.nil?
        end
        "#<#{self.class.name} #{shown.join(" ")}>"
      end
    end
  end
end
