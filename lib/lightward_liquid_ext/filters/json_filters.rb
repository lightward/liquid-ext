# frozen_string_literal: true

module LightwardLiquidExt
  module Filters
    # json renders any value as JSON. parse_json reads a JSON string into hashes,
    # arrays and plain values; with `silent: true`, invalid JSON gives nil instead
    # of an error.
    #
    # An object can choose its own JSON form by responding to `as_liquid_json`.
    module JsonFilters
      def json(object)
        JSON.dump(JsonFilters.object_as_liquid_json(object))
      rescue JSON::NestingError
        Support.too_deep!
      end

      def parse_json(object, options = {})
        unless object.is_a?(String)
          raise(ArgumentError, "parse_json can only be used on strings; received #{Support.type_name(object)} instead")
        end

        JSON.parse(object)
      rescue JSON::ParserError => error
        return if options.is_a?(Hash) && Support.present?(options["silent"])

        # The parser's own message quotes the input wherever parsing failed, which
        # can be anywhere in it, so only its position is kept.
        line = error.respond_to?(:line) ? error.line : nil
        column = error.respond_to?(:column) ? error.column : nil
        position = line && column ? " at line #{line}, column #{column}" : ""

        raise(ArgumentError, "parse_json failed: invalid JSON#{position}\n\ninput:\n#{Support.excerpt(object)}")
      end

      # Walks hashes and collections at most MAX_DEPTH deep (which also stops a
      # cycle), raising a Liquid::Error past that.
      def self.object_as_liquid_json(object, levels: MAX_DEPTH)
        if object.respond_to?(:as_liquid_json)
          object.as_liquid_json
        elsif object.is_a?(Hash)
          Support.too_deep! if levels < 1
          object.transform_values { |value| object_as_liquid_json(value, levels: levels - 1) }
        elsif object.respond_to?(:each)
          Support.too_deep! if levels < 1
          object.map { |value| object_as_liquid_json(value, levels: levels - 1) }
        else
          object
        end
      end
    end
  end
end
