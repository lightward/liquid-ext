# frozen_string_literal: true

RSpec.describe(LightwardLiquidExt::Filters::RegexpFilters) do
  def test(template, expected)
    result = JSON.parse(render_liquid(template))

    expect(result).to(eq(expected))
  end

  # For the cases that should raise before there's anything to compare.
  def render_only(template)
    render_liquid(template)
  end

  describe "match" do
    it "returns the match, with its captures" do
      test('{{ "asdf" | match: "asdf" | json }}', "asdf")
      test('{{ "asdf" | match: "sd" | size | json }}', 2)
      test('{{ "asdf" | match: "sd" | slice: 0, 1 | json }}', "s")
      test('{{ "asdf" | match: "sd" | split: "" | reverse | join: "" | json }}', "ds")
      test('{% assign match = "asdf" | match: "sd" %}{{ match.bytesize | json }}', nil)
      test('{% assign match = "asdf" | match: "a(sd)f" %}{{ match.captures | json }}', ["sd"])
      test('{% assign match = "asdf" | match: "a(sd)f" %}{{ match.named_captures | json }}', {})
      test('{% assign match = "asdf" | match: "a(?<sd>sd)f" %}{{ match.named_captures | json }}', "sd" => "sd")

      test('{% assign match = "asdf" | match: "fdsa" %}{{ match | json }}', nil)
      test('{% assign match = "asdf" | match: "fdsa" %}{{ match.captures | json }}', nil)
      test('{% assign match = "asdf" | match: "fdsa" %}{{ match.named_captures | json }}', nil)
    end

    it "renders as the matched string" do
      expect(render_liquid(%({{ "It's a lovely day!" | match: "a (?i:LOVELY) day" }}))).to(eq("a lovely day"))
    end

    it "can't be used as a hash key during assignment" do
      expect {
        render_liquid(%q(
          {% assign match = "asdf" | match: "\w" %}
          {% assign target = hash %}
          {% assign target[match] = "A" %}
        ))
      }.to(raise_error(Liquid::Error, 'Liquid error: Tried to use an instance of MatchDrop as a key for hash assignment during {% assign target[match] = "A" %}, but only strings can be used for hash assignment'))
    end

    it "yells about invalid input" do
      expect {
        render_only('{{ 5 | match: "asdf" }}')
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: match can only be used on a string; received integer instead"))
    end

    it "yells about non-string patterns" do
      expect {
        render_only('{{ "asdf" | match: 5 }}')
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: match's first argument must be a Ruby-compatible regexp pattern string; received integer instead"))
    end

    it "yells about invalid patterns" do
      expect {
        render_only('{{ "asdf" | match: "(" }}')
      }.to(raise_error(Liquid::ArgumentError, /\ALiquid error: Regular expression error in "match" filter for pattern "\(": end pattern with unmatched parenthesis/))
    end

    it "behaves like the matched text for size, first and last" do
      expect(render_liquid('{% assign m = "say hello" | match: "hel+o" %}{{ m.size }} {{ m.first }} {{ m.last }} {{ m | first }} {{ m | last }} {{ m | size }}'))
        .to(eq("5 h o h o 5"))
    end

    it "quotes only the start of a long invalid pattern" do
      pattern = "(" + ("a" * 500)

      expect {
        render_liquid("{{ s | match: p }}", { "s" => "x", "p" => pattern })
      }.to(raise_error(Liquid::ArgumentError) { |error| expect(error.message.length).to(be < 400) })
    end
  end

  describe "the timeout" do
    after { LightwardLiquidExt.regexp_timeout = 1.0 }

    it "is one second unless the host changes it" do
      expect(LightwardLiquidExt.regexp_timeout).to(eq(1.0))
    end

    it "gives up on a slow match in plain words" do
      LightwardLiquidExt.regexp_timeout = 0.05

      [["match", "(?=(a|aa)+$)"], ["scan", "(?=(a|aa)+$)"]].each do |filter, pattern|
        expect {
          render_liquid("{{ s | #{filter}: p }}", { "s" => "#{"a" * 3000}!", "p" => pattern })
        }.to(raise_error(Liquid::Error, /\ALiquid error: #{filter} gave up on pattern .+ after 0.05 seconds/))
      end
    end

    it "inherits Ruby's global Regexp.timeout when set to nil" do
      LightwardLiquidExt.regexp_timeout = nil

      expect(render_liquid('{{ "abc" | match: "b" }}')).to(eq("b"))
      expect(LightwardLiquidExt::Filters::RegexpFilters.send(:compile, "b", nil).timeout).to(be_nil)
    end

    context "with a global Regexp.timeout and the gem's setting nil" do
      around do |example|
        original = Regexp.timeout
        Regexp.timeout = 0.07
        example.run
      ensure
        Regexp.timeout = original
      end

      it "times out under the global value, and names it" do
        LightwardLiquidExt.regexp_timeout = nil

        [["match", "(?=(a|aa)+$)"], ["scan", "(?=(a|aa)+$)"]].each do |filter, pattern|
          expect {
            render_liquid("{{ s | #{filter}: p }}", { "s" => "#{"a" * 3000}!", "p" => pattern })
          }.to(raise_error(Liquid::Error, /\ALiquid error: #{filter} gave up on pattern .+ after 0.07 seconds; try a simpler pattern\z/))
        end
      end
    end

    it "reuses compiled patterns, a bounded number of them" do
      filters = LightwardLiquidExt::Filters::RegexpFilters
      first = filters.send(:compile, "reuse-me", 1.0)

      expect(filters.send(:compile, "reuse-me", 1.0)).to(be(first))
      expect(first.timeout).to(eq(1.0))

      200.times { |i| filters.send(:compile, "pattern-#{i}", 1.0) }
      expect(filters.instance_variable_get(:@cache).size).to(be <= filters::CACHE_SIZE)
    end
  end

  describe "scan" do
    it "counts each match against the render score" do
      context = Liquid::Context.new({ "s" => "a" * 50 })
      context.resource_limits.render_score_limit = 20

      expect {
        Liquid::Template.parse('{{ s | scan: "." | size }}').render!(context)
      }.to(raise_error(Liquid::MemoryError))
    end

    it "returns every match" do
      test('{% assign match = "asdf" | scan: "\w" %}{{ match | json }}', ["a", "s", "d", "f"])
      test('{% assign match = "asdf" | scan: "\w" %}{{ match | map: "captures" | json }}', [[], [], [], []])
      test('{% assign match = "asdf" | scan: "(\w)" %}{{ match | map: "captures" | json }}', [["a"], ["s"], ["d"], ["f"]])
    end

    it "returns matchdrops" do
      test('{{ "asdf" | scan: "asdf" | first | json }}', "asdf")
      test('{{ "asdf" | scan: "sd" | first | size | json }}', 2)
      test('{{ "asdf" | scan: "sd" | first | slice: 0, 1 | json }}', "s")
      test('{{ "asdf" | scan: "sd" | first | split: "" | reverse | join: "" | json }}', "ds")
      test('{% assign match = "asdf" | scan: "sd" | first %}{{ match.bytesize | json }}', nil)
      test('{% assign match = "asdf" | scan: "a(sd)f" | first %}{{ match.captures | json }}', ["sd"])
      test('{% assign match = "asdf" | scan: "a(sd)f" | first %}{{ match.named_captures | json }}', {})
      test('{% assign match = "asdf" | scan: "a(?<sd>sd)f" | first %}{{ match.named_captures | json }}', "sd" => "sd")

      test('{% assign match = "asdf" | scan: "fdsa" | first %}{{ match | json }}', nil)
      test('{% assign match = "asdf" | scan: "fdsa" | first %}{{ match.captures | json }}', nil)
      test('{% assign match = "asdf" | scan: "fdsa" | first %}{{ match.named_captures | json }}', nil)
    end

    it "yells about invalid input" do
      expect {
        render_only('{{ 5 | scan: "asdf" }}')
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: scan can only be used on a string; received integer instead"))
    end

    it "yells about non-string patterns" do
      expect {
        render_only('{{ "asdf" | scan: 5 }}')
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: scan's first argument must be a Ruby-compatible regexp pattern string; received integer instead"))
    end

    it "yells about invalid patterns" do
      expect {
        render_only('{{ "asdf" | scan: "(" }}')
      }.to(raise_error(Liquid::ArgumentError, /\ALiquid error: Regular expression error in "scan" filter for pattern "\(": end pattern with unmatched parenthesis/))
    end
  end
end
