# frozen_string_literal: true

require_relative "lib/lightward_liquid_ext/version"

Gem::Specification.new do |spec|
  spec.name = "lightward_liquid_ext"
  spec.version = LightwardLiquidExt::VERSION
  spec.authors = ["Lightward"]
  spec.summary = "Array and hash literals, assignment into hashes and arrays, and a few filters, for Shopify's Liquid."
  spec.description = <<~DESC.tr("\n", " ").strip
    Liquid extensions that have run in Mechanic (mechanic.dev) for years: the keyword
    literals array, hash and newline; assign into hashes and arrays by key or index;
    split and replace that understand newline; match and scan with regular expressions;
    push and unshift; json and parse_json.
  DESC
  spec.homepage = "https://github.com/lightward/liquid-ext"
  spec.license = "Unlicense"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "UNLICENSE"]
  spec.require_paths = ["lib"]

  # Liquid 5.14 requires base64 without declaring it, and base64 left Ruby's
  # default gems in 3.4.
  spec.add_dependency("base64")
  spec.add_dependency("json", ">= 2.0")
  spec.add_dependency("liquid", ">= 5.14", "< 6")
end
