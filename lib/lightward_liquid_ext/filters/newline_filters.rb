# frozen_string_literal: true

module LightwardLiquidExt
  module Filters
    # Liquid's split and replace, taught about the `newline` literal. Given
    # `newline` itself, they match "\r\n" as well as "\n". Given anything else,
    # they defer to Liquid's own filters unchanged. (Liquid's own newline_to_br
    # already handles "\r\n", so it needs nothing from here.)
    module NewlineFilters
      LINEBREAK_PATTERN = /\r?\n/

      def replace(input, string, replacement = "")
        return super unless KeywordLiterals.newline?(string)

        ::Liquid::Utils.to_s(input).gsub(LINEBREAK_PATTERN, ::Liquid::Utils.to_s(replacement))
      end

      def split(input, pattern)
        return super unless KeywordLiterals.newline?(pattern)

        ::Liquid::Utils.to_s(input).split(LINEBREAK_PATTERN)
      end
    end
  end
end
