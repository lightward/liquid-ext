# frozen_string_literal: true

module LightwardLiquidExt
  module Filters
    # match and scan, with Ruby-compatible regular expression patterns given as strings.
    #
    # Each match runs under LightwardLiquidExt.regexp_timeout (1 second unless the
    # host changes it). Every match `scan` finds counts once against Liquid's
    # render score, so render_score_limit bounds it.
    module RegexpFilters
      CACHE_SIZE = 100

      @cache = {}
      @cache_mutex = Mutex.new

      # One match. It renders as the matched text, and behaves like it for `size`,
      # `first` and `last` (the text's length, first character and last character)
      # and for string filters. `captures` gives an array of the groups, and
      # `named_captures` a hash.
      #
      # match[0] and match["name"] are deliberately not supported: Liquid treats
      # match.foo and match["foo"] as the same lookup, so [] can't serve both
      # captures and the text's own properties. Asking for the arrays by name
      # keeps what's going on visible.
      class MatchDrop < ::Liquid::Drop
        def initialize(matchdata)
          super()
          @matchdata = matchdata
          @matchdata_string = matchdata.to_s
        end

        def to_s
          @matchdata_string
        end

        def captures
          @matchdata.captures
        end

        def named_captures
          @matchdata.named_captures
        end

        def size
          @matchdata_string.size
        end

        def first
          @matchdata_string[0]
        end

        def last
          @matchdata_string[-1]
        end
      end

      def match(input, pattern, _options = {})
        regexp = RegexpFilters.build_regexp("match", input, pattern)

        matchdata = RegexpFilters.timing_out("match", pattern) { regexp.match(input) }
        MatchDrop.new(matchdata) if matchdata
      end

      def scan(input, pattern, _options = {})
        regexp = RegexpFilters.build_regexp("scan", input, pattern)
        resource_limits = @context&.resource_limits

        RegexpFilters.timing_out("scan", pattern) do
          input.to_enum(:scan, regexp).map do
            resource_limits&.increment_render_score(1)
            MatchDrop.new(Regexp.last_match)
          end
        end
      end

      class << self
        def build_regexp(filter_name, input, pattern)
          unless input.is_a?(String)
            raise(
              ArgumentError,
              "#{filter_name} can only be used on a string; received #{Support.type_name(input)} instead",
            )
          end

          unless pattern.is_a?(String)
            raise(
              ArgumentError,
              "#{filter_name}'s first argument must be a Ruby-compatible regexp pattern string; " \
                "received #{Support.type_name(pattern)} instead",
            )
          end

          compile(pattern, LightwardLiquidExt.regexp_timeout)
        rescue RegexpError => error
          raise(
            ArgumentError,
            "Regular expression error in \"#{filter_name}\" filter for pattern " \
              "#{Support.excerpt(pattern).to_json}: #{Support.excerpt(error.message, 200)}",
          )
        end

        def timing_out(filter_name, pattern)
          yield
        rescue Regexp::TimeoutError
          raise(
            ::Liquid::Error,
            "#{filter_name} gave up on pattern #{Support.excerpt(pattern).to_json} after " \
              "#{LightwardLiquidExt.regexp_timeout} seconds; try a simpler pattern",
          )
        end

        private

        # Compiled patterns are kept, a few at a time, so a loop doesn't recompile.
        def compile(pattern, timeout)
          key = [pattern, timeout]

          @cache_mutex.synchronize do
            regexp = @cache.delete(key)
            return @cache[key] = regexp if regexp
          end

          regexp = Regexp.new(pattern, timeout: timeout)

          @cache_mutex.synchronize do
            @cache.shift while @cache.size >= CACHE_SIZE
            @cache[key] = regexp
          end
        end
      end
    end
  end
end
