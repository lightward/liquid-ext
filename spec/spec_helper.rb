# frozen_string_literal: true

require "lightward_liquid_ext"

LightwardLiquidExt.install!

# Marks a spec helper call that only renders (to see it raise), so that nil and
# false stay real expected values.
NO_EXPECTATION = Object.new.freeze

module LiquidHelpers
  # Renders with Liquid's default environment, raising on any error.
  def render_liquid(template, assigns = {})
    Liquid::Template.parse(template).render!(stringify_keys(assigns))
  end

  def stringify_keys(value)
    case value
    when Hash then value.to_h { |key, entry| [key.to_s, stringify_keys(entry)] }
    when Array then value.map { |entry| stringify_keys(entry) }
    else value
    end
  end
end

RSpec.configure do |config|
  config.include(LiquidHelpers)
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)
end
