# frozen_string_literal: true

module LightwardLiquidExt
  # Adds three keyword literals to Liquid expressions, in environments that have
  # had LightwardLiquidExt.install!:
  #
  #   array    an empty array
  #   hash     an empty hash
  #   newline  "\n"
  #
  # Like Liquid's own `true` or `nil`, these are literals, not variables:
  # `{% assign hash = "x" %}` doesn't change what `hash` means afterwards, and a
  # variable the host passes in under one of these names can't be read. Templates
  # rendered in any other environment are untouched.
  #
  # The values are frozen and shared. The assign tag copies them on assignment, so
  # every `{% assign x = array %}` gets an array of its own. `newline` is recognized
  # by identity: the newline filters treat the literal itself specially, and any
  # other "\n" (an assigned copy, a captured line break) as an ordinary string.
  #
  # Lookups rooted at a keyword resolve against the literal, whatever the host
  # passed in under that name: `{{ array.size }}` is 0, `{{ hash.anything }}` and
  # `{{ hash["anything"] }}` are empty, `{{ newline.size }}` is 1.
  module KeywordLiterals
    LITERALS = {
      "hash" => {}.freeze,
      "array" => [].freeze,
      # String.new, so this is an object of its own. A frozen "\n" literal would be
      # deduplicated by Ruby with every other frozen "\n" literal in the process,
      # and a host's own "\n" would then pass for the keyword.
      "newline" => String.new("\n").freeze,
    }.freeze

    NEWLINE = LITERALS.fetch("newline")

    @environments = ObjectSpace::WeakMap.new
    @mutex = Mutex.new

    class << self
      def literal?(value)
        LITERALS.each_value.any? { |literal| value.equal?(literal) }
      end

      def newline?(value)
        value.equal?(NEWLINE)
      end

      def installed?(environment)
        !environment.nil? && @environments.key?(environment)
      end

      # The literal named by this markup, or nil, for an installed environment.
      def lookup(environment, markup)
        return unless markup.is_a?(String) && installed?(environment)

        LITERALS[markup.strip]
      end

      def install!(environment)
        @mutex.synchronize do
          unless ::Liquid::ParseContext.ancestors.include?(ParseContextHooks)
            check_compatibility!
            ::Liquid::ParseContext.prepend(ParseContextHooks)
            ::Liquid::Context.prepend(ContextHooks)
          end

          @environments[environment] = true
        end
      end

      private

      def check_compatibility!
        version = Gem::Version.new(::Liquid::VERSION)
        unless version >= Gem::Version.new("5.14") && version < Gem::Version.new("6")
          incompatible!("supports Liquid >= 5.14 and < 6, and Liquid #{::Liquid::VERSION} is loaded")
        end

        expectations = {
          [::Liquid::ParseContext, :parse_expression] => [[:req, :markup], [:key, :safe]],
          [::Liquid::ParseContext, :safe_parse_expression] => [[:req, :parser]],
          [::Liquid::Context, :[]] => [[:req, :expression]],
          [::Liquid::Context, :find_variable] => [[:req, :key], [:key, :raise_on_not_found]],
        }

        expectations.each do |(klass, method_name), parameters|
          found = klass.method_defined?(method_name) ? klass.instance_method(method_name).parameters : nil
          next if found == parameters

          incompatible!("expected #{klass}##{method_name} to take #{parameters.inspect}, and found #{found.inspect}")
        end

        unless ::Liquid::ParseContext.method_defined?(:environment) && ::Liquid::Context.method_defined?(:environment)
          incompatible!("expected Liquid::ParseContext and Liquid::Context to know their environment")
        end
      end

      def incompatible!(detail)
        raise(IncompatibleLiquidError, "lightward_liquid_ext #{detail}. See #{README_URL}")
      end
    end

    # Hands Liquid's own safe_parse_expression an expression it has already read.
    ParsedExpression = Struct.new(:expression)

    # Prepended to Liquid::ParseContext, which every tag and variable parses its
    # expressions through. The literals return before Liquid's expression cache is
    # consulted, so the cache never holds them.
    module ParseContextHooks
      def parse_expression(markup, safe: false)
        return super if !safe && error_mode == :strict2 # let Liquid raise its own error

        literal = KeywordLiterals.lookup(environment, markup)
        literal.nil? ? super : literal
      end

      def safe_parse_expression(parser)
        return super unless KeywordLiterals.installed?(environment)

        expression = parser.expression
        literal = KeywordLiterals.lookup(environment, expression)
        literal.nil? ? super(ParsedExpression.new(expression)) : literal
      end
    end

    # Prepended to Liquid::Context, for lookups made at render time (the assign
    # tag's bracket lookups, and hosts calling context["..."]).
    module ContextHooks
      # Every variable lookup's root comes through here (VariableLookup, `self`,
      # every parse mode), so a lookup rooted at a keyword name resolves against
      # the literal and never reaches a host variable of that name.
      def find_variable(key, raise_on_not_found: true)
        return super unless key.is_a?(String) && KeywordLiterals.installed?(environment)

        literal = LITERALS[key]
        literal.nil? ? super : literal
      end

      def [](expression)
        return super unless KeywordLiterals.installed?(environment)

        case expression
        when true, false, Numeric, Hash, Array
          expression
        when Symbol
          self[expression.to_s]
        when String, nil
          literal = KeywordLiterals.lookup(environment, expression)
          literal.nil? ? super : literal
        else
          raise(::Liquid::Error, "Liquid expression must be a string or primitive; got #{expression.class.name}")
        end
      end
    end
  end
end
