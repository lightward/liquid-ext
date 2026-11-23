# frozen_string_literal: true

module LightwardLiquidExt
  # Liquid's assign tag, extended to assign into hashes and arrays:
  #
  #   {% assign foo = 'monkey' %}
  #   {% assign bar = hash %}
  #   {% assign bar["baz"] = 'monkey' %}
  #   {% assign list = array %}
  #   {% assign list[list.size] = 'monkey' %}
  #   {% assign bar["nested"] = hash %}
  #   {% assign bar["nested"]["deeper"] = list %}
  #
  # Assignment is always by value. Whatever lands in a variable, or inside a hash
  # or array, is a copy: changing it later never changes anything else, and
  # changing anything else never changes it.
  #
  # Only hashes and arrays made in the template (with `hash`, `array`, or a filter
  # like `split` or `parse_json`) accept assignments. Hashes take string keys,
  # arrays take integer indexes, and dot lookups on the left side are refused
  # with a suggestion to use brackets.
  class AssignTag < ::Liquid::Assign
    THING = /(?:#{::Liquid::QuotedString}|[\w\-\[\]\.]+?)/o
    SYNTAX = /\A\s*(#{::Liquid::VariableSignature}+?)((?:\[#{THING}\])*)\s*=\s*(.*)\s*\z/om
    LOOKUP_SYNTAX = /\[(#{THING})\]/o

    attr_reader :to_lookups

    def initialize(tag_name, markup, parse_context)
      # Liquid::Assign#initialize parses the target as a plain variable name, and
      # in strict2 mode refuses a bracketed one, so its parser is skipped here.
      ::Liquid::Tag.instance_method(:initialize).bind_call(self, tag_name, markup, parse_context)

      match = SYNTAX.match(markup)
      self.class.raise_syntax_error(parse_context) unless match

      @to = match[1]

      unless match[2].empty?
        @to_lookups = match[2].scan(LOOKUP_SYNTAX).flatten

        if @to_lookups.any? { |lookup| !lookup.match?(/\A#{::Liquid::QuotedString}\z/o) && lookup.match?(/[\[\]]/) }
          raise(
            ::Liquid::SyntaxError,
            "Encountered nested bracket lookups during {% assign #{markup.strip} %}, but this is not permitted",
          )
        end
      end

      @from = ::Liquid::Variable.new(match[3], parse_context)
    end

    def render_to_output_buffer(context, output)
      LightwardLiquidExt.assign_hook&.call(context)

      if @to.split(".").size > 1
        replacement_to = @to.gsub(/\.(\w+)/, '["\1"]')
        replacement_markup = @markup.strip.sub(@to, replacement_to)
        raise(
          ::Liquid::Error,
          "Assignment with dot lookups is not permitted; try replacing {% assign #{@markup.strip} %} with " \
            "{% assign #{replacement_markup} %}",
        )
      end

      if @to_lookups.nil?
        val = copy_for_variable(@from.render(context))
        context.scopes.last[@to] = val
        owned_by(context)[val] = true if val.is_a?(Hash) || val.is_a?(Array)
      else
        thing = assignable_root(context)
        lookup_representation = @to

        @to_lookups[0..-2].each do |lookup|
          lookup_representation += "[#{lookup}]"
          lookup_value = context[lookup]

          assert_lookupable!(thing, lookup_representation, lookup_value, lookup)
          thing = thing[lookup_value]
          assert_assignable!(thing, lookup_representation)
        end

        # The value lands inside as many hashes and arrays as there are lookups,
        # so it gets that many fewer levels of its own.
        val = Support.deep_copy(@from.render(context), levels: MAX_DEPTH - @to_lookups.size)

        assign_in(thing, context[@to_lookups.last], val, context: context)
      end

      context.resource_limits.increment_assign_score(assign_score_of(val))

      output
    end

    private

    # The hash or array named by the target, ready to be changed in place.
    #
    # Only the outermost scope holds what {% assign %} made, and the hashes and
    # arrays this context assigned are recorded as its own. Anything else found
    # there (a `render` argument, say, which is the caller's object) is copied
    # into place before the first change, so assignment never reaches back into
    # whoever passed it.
    def assignable_root(context)
      outermost = context.scopes.last

      # Liquid reads a name from the innermost scope that has it, so a loop
      # variable or include parameter shadows an assigned variable of the same
      # name. Refuse it rather than change the shadowed one.
      if context.scopes[0..-2].any? { |scope| scope.key?(@to) }
        raise(
          ::Liquid::Error,
          "Tried to assign within `#{@to}` during {% assign #{@markup.strip} %}, but `#{@to}` is a loop " \
            "variable or an include parameter, which can't be assigned into. To perform this assignment, " \
            "start by copying it into a variable of your own, e.g. {% assign my_#{@to} = #{@to} %}.",
        )
      end

      unless outermost.key?(@to)
        if context.environments.any? { |environment| environment.key?(@to) }
          raise(
          ::Liquid::Error,
            "Tried to assign within an environment variable during {% assign #{@markup.strip} %}. " \
              "To perform this assignment, start by overriding the environment variable with a " \
              "new locally-defined hash or array.",
          )
        end
      end

      thing = outermost[@to]
      assert_assignable!(thing, @to)

      owned = owned_by(context)
      unless owned.key?(thing)
        thing = Support.deep_copy(thing)
        context.resource_limits.increment_assign_score(assign_score_of(thing))
        outermost[@to] = thing
        owned[thing] = true
      end

      thing
    end

    # The hashes and arrays this context's own assigns created. Held weakly, so a
    # collection that's been overwritten can be collected, and compared by
    # identity, since an equal hash someone else passed in isn't one of ours.
    # (ObjectSpace::WeakMap rather than WeakKeyMap: WeakKeyMap compares keys by
    # equality, and a hash's equality changes as it's assigned into.)
    def owned_by(context)
      context.instance_variable_get(:@lightward_liquid_ext_owned) ||
        context.instance_variable_set(:@lightward_liquid_ext_owned, ObjectSpace::WeakMap.new)
    end

    # A plain `{% assign x = value %}` copies the keyword literals (they're frozen
    # and shared, and an assigned `newline` must stop being the literal), and
    # copies hashes and arrays all the way down, so assigning into `x` later can't
    # reach back into `value`. Everything else is stored as is.
    def copy_for_variable(value)
      if KeywordLiterals.literal?(value) || value.is_a?(Hash) || value.is_a?(Array)
        Support.deep_copy(value)
      else
        value
      end
    end

    def assert_lookupable!(object, object_representation, lookup_value, lookup_representation)
      addendum = (lookup_representation != lookup_value ? " (found #{Support.describe_key(lookup_value)})" : "")

      case object
      when Hash
        unless lookup_value.is_a?(String)
          raise(
          ::Liquid::Error,
            "Tried to resolve `#{object_representation}` during `{% assign #{@markup.strip} %}`, but " \
              "`#{lookup_representation}` is not a string and cannot be used for hash lookups#{addendum}",
          )
        end
      when Array
        unless lookup_value.is_a?(Integer)
          raise(
          ::Liquid::Error,
            "Tried to resolve `#{object_representation}` during `{% assign #{@markup.strip} %}`, but " \
              "`#{lookup_representation}` is not an integer and cannot be used for array lookups#{addendum}",
          )
        end
      end
    end

    def assign_in(object, key, value, context:)
      case object
      when Hash
        unless key.is_a?(String)
          raise(
          ::Liquid::Error,
            "Tried to use #{Support.describe_key(key)} as a key for hash assignment during " \
              "{% assign #{@markup.strip} %}, but only strings can be used for hash assignment",
          )
        end

        # The key costs what Liquid charges for a string; the value is charged
        # with every assignment, after this.
        context.resource_limits.increment_assign_score(assign_score_of(key))

        object[key] = value
      when Array
        unless key.is_a?(Integer)
          raise(
          ::Liquid::Error,
            "Tried to use #{Support.describe_key(key)} as an index for array assignment during " \
              "{% assign #{@markup.strip} %}, but only integers can be used for array assignment",
          )
        end

        if key < -object.length
          raise(
          ::Liquid::Error,
            "Tried to use #{key} as an index for array assignment during {% assign #{@markup.strip} %}, " \
              "but the array only has #{object.length} #{object.length == 1 ? "item" : "items"}",
          )
        end

        # Ruby arrays aren't sparse: assigning far past the end fills every slot in
        # between with nil. Cap those slots, and charge them to the assign score,
        # before making them.
        gap = key - object.length
        max_gap = LightwardLiquidExt.max_array_gap
        if max_gap && gap > max_gap
          raise(
          ::Liquid::Error,
            "Tried to use #{key} as an index for array assignment during {% assign #{@markup.strip} %}, " \
              "but that would add #{gap} empty slots to an array of #{object.length}, and at most " \
              "#{max_gap} are allowed",
          )
        end
        context.resource_limits.increment_assign_score(gap) if gap > 0

        begin
          object[key] = value
        rescue IndexError, NoMemoryError
          raise(
          ::Liquid::Error,
            "Tried to use #{key} as an index for array assignment during {% assign #{@markup.strip} %}, " \
              "but that index is too large",
          )
        end
      end
    end

    def assert_assignable!(thing, lookup_representation)
      return if thing.instance_of?(Hash) || thing.instance_of?(Array)

      raise(
        ::Liquid::Error,
        "Encountered a #{Support.type_name(thing)} at `#{lookup_representation}` that is not assignable, " \
          "in `{% assign #{@markup.strip} %}`. Only locally-initialized hashes and arrays support assignments.",
      )
    end
  end
end
