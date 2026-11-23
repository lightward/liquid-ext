# frozen_string_literal: true

require "json"
require "liquid"

require_relative "lightward_liquid_ext/version"
require_relative "lightward_liquid_ext/support"
require_relative "lightward_liquid_ext/keyword_literals"
require_relative "lightward_liquid_ext/assign_tag"
require_relative "lightward_liquid_ext/filters/newline_filters"
require_relative "lightward_liquid_ext/filters/regexp_filters"
require_relative "lightward_liquid_ext/filters/array_filters"
require_relative "lightward_liquid_ext/filters/json_filters"

# Liquid extensions extracted from Mechanic. Requiring this file changes nothing;
# call LightwardLiquidExt.install! to turn the extensions on.
module LightwardLiquidExt
  README_URL = "https://github.com/lightward/liquid-ext#readme"

  # How deep hashes and arrays may nest, when assigned or rendered as JSON. The
  # same as the JSON library's default.
  MAX_DEPTH = 100

  # Raised on install when the loaded Liquid isn't one this gem knows how to extend.
  class IncompatibleLiquidError < StandardError; end

  FILTERS = [
    Filters::NewlineFilters,
    Filters::RegexpFilters,
    Filters::ArrayFilters,
    Filters::JsonFilters,
  ].freeze

  class << self
    # Optional callable, given the Liquid::Context, run at the start of every
    # {% assign %} render. nil by default. A host can use it to yield the thread,
    # check for cancellation, or count work. Whatever it raises propagates.
    attr_accessor :assign_hook

    # Seconds a single regular expression match in `match` or `scan` may take
    # before it gives up (Ruby's Regexp timeout). nil means inherit Ruby's
    # process-wide Regexp.timeout, which is no limit unless the host sets one.
    # This bounds one match, not a render: see the README on untrusted templates.
    attr_accessor :regexp_timeout

    # The most empty slots one array assignment may create past the end of an
    # array (`{% assign a[1000000] = 1 %}` on an empty array creates 1,000,000).
    # Checked before anything is allocated, whatever Liquid limits are set. nil
    # for no cap.
    attr_accessor :max_array_gap

    # Registers the assign tag and the filters on the given environment, and turns
    # on the keyword literals (array, hash, newline) for templates parsed and
    # rendered in it. Other environments are untouched. Safe to call more than once.
    def install!(environment = ::Liquid::Environment.default)
      # Tag and filters first: if the environment refuses them (a built, frozen
      # one, say), it's left as it was, keywords included.
      environment.register_tag("assign", AssignTag)
      FILTERS.each { |filter| environment.register_filter(filter) }

      KeywordLiterals.install!(environment)

      environment
    end
  end

  self.regexp_timeout = 1.0
  self.max_array_gap = 100_000
end
