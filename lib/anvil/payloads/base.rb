# frozen_string_literal: true

module Anvil
  # Typed request payloads.
  #
  # Every client method also accepts a plain Hash with the API's own camelCase
  # keys, so these are a convenience, not a requirement. They give you
  # snake_case names, a readable `inspect`, and an error at the call site
  # instead of a 400 when a name is misspelled.
  #
  # Anything the API accepts that a payload class does not declare can still be
  # passed: unknown keyword arguments are camelized and sent through.
  module Payloads
    # The shared behavior of every request payload.
    class Base
      include Types::Attributes

      # @return [Hash] keys passed to the constructor that this class does not declare
      attr_reader :extra

      # @param attributes [Hash] declared attributes by their snake_case name,
      #   plus any undeclared keys to pass through
      def initialize(**attributes)
        @extra = {}

        attributes.each do |name, value|
          definition = self.class.attributes[name.to_sym]
          if definition
            public_send(:"#{name}=", value)
          else
            @extra[self.class.camelize(name)] = value
          end
        end
      end

      # @param hash [Hash, Base, nil]
      # @return [Base]
      def self.from_h(hash)
        return hash if hash.is_a?(self)
        return new if hash.nil?

        by_key = attributes.each_value.to_h { |definition| [definition[:key].to_s, definition[:name]] }
        known = attributes.keys.map(&:to_s)

        new(**hash.to_h.each_with_object({}) do |(key, value), kwargs|
          name = by_key[key.to_s] || (known.include?(key.to_s) ? key.to_sym : key)
          kwargs[name.to_sym] = value
        end)
      end

      # The payload as the API wants it: camelCase keys, and attributes that
      # were never set left out entirely rather than sent as null.
      #
      # @return [Hash]
      def to_h
        payload = self.class.attributes.each_with_object({}) do |(_name, definition), hash|
          value = public_send(definition[:name])
          next if value.nil?

          hash[definition[:key]] = self.class.serialize(value)
        end

        payload.merge(self.class.serialize(extra))
      end
      alias to_hash to_h

      # @api private
      def self.serialize(value)
        case value
        when Base then value.to_h
        when Array then value.map { |element| serialize(element) }
        when Hash then value.each_with_object({}) { |(key, sub), hash| hash[key] = serialize(sub) }
        when Time then value.iso8601
        else value
        end
      end

      def ==(other)
        other.is_a?(self.class) && other.to_h == to_h
      end
      alias eql? ==

      def hash
        [self.class, to_h].hash
      end

      def inspect
        "#<#{self.class.name} #{to_h.inspect}>"
      end
    end
  end
end
