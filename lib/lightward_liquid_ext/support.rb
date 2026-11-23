# frozen_string_literal: true

module LightwardLiquidExt
  # Small helpers, kept here so the gem needs nothing beyond liquid and json.
  module Support
    module_function

    # A plain-words name for an object's type, for error messages:
    # 5 => "integer", nil => "nil class", SomeModule::WidgetDrop.new => "widget drop".
    def type_name(object)
      name = object.class.name
      return "object" if name.nil?

      name
        .split("::").last
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .tr("_", " ")
        .downcase
    end

    # Copies hashes, arrays and strings all the way down, so that nothing reachable
    # from the copy is shared with the original. Other objects (numbers, drops,
    # anything a host put in the context) are kept as they are: Liquid has no way
    # to change them in place.
    #
    # Hashes and arrays come out as plain Hash and Array, built from their stored
    # entries only. A hash's default value or default proc isn't carried over: it
    # would be shared with the original, and a missing key should read as missing.
    #
    # Refuses anything nested deeper than `levels` hashes and arrays (which also
    # stops a cycle), with a Liquid::Error rather than a stack overflow.
    #
    # The core classes' own methods do the walking, never a subclass's overrides, so a
    # subclass whose `map`, `each_pair` or `dup` returns itself (or anything else) is
    # still copied into a new plain Hash, Array or String.
    HASH_EACH_PAIR = ::Hash.instance_method(:each_pair)
    ARRAY_MAP = ::Array.instance_method(:map)
    private_constant :HASH_EACH_PAIR, :ARRAY_MAP

    def deep_copy(value, levels: MAX_DEPTH)
      case value
      when Hash
        too_deep! if levels < 1
        copy = {}
        HASH_EACH_PAIR.bind_call(value) { |key, entry| copy[key] = deep_copy(entry, levels: levels - 1) }
        copy
      when Array
        too_deep! if levels < 1
        ARRAY_MAP.bind_call(value) { |entry| deep_copy(entry, levels: levels - 1) }
      when String
        String.new(value)
      else
        value
      end
    end

    def too_deep!
      raise(
        ::Liquid::Error,
        "Hashes and arrays can be nested at most #{MAX_DEPTH} levels deep, and this one would go deeper",
      )
    end

    # The start of a long string, for quoting in an error message.
    def excerpt(string, length = 80)
      string = string.to_s
      string.length > length ? "#{string[0, length]}…" : string
    end

    # JSON for the types JSON has; a description for anything else. Used to show
    # a hash key or array index in an error message.
    def describe_key(value)
      case value
      when String, Integer, Float, true, false, nil
        value.to_json
      else
        "an instance of #{value.class.name.to_s.split("::").last}"
      end
    end

    def present?(value)
      return false if value.nil? || value == false
      return !value.strip.empty? if value.is_a?(String)
      return !value.empty? if value.respond_to?(:empty?)

      true
    end
  end
end
