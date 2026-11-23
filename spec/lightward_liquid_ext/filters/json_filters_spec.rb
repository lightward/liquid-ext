# frozen_string_literal: true

RSpec.describe(LightwardLiquidExt::Filters::JsonFilters) do
  describe "json" do
    it "renders values as JSON" do
      expect(render_liquid("{{ foo | json }}", { "foo" => { "a" => [1, "two", nil, true] } })).to(eq('{"a":[1,"two",null,true]}'))
      expect(render_liquid('{{ "x" | json }}')).to(eq('"x"'))
      expect(render_liquid("{{ (1..3) | json }}")).to(eq("[1,2,3]"))
    end

    it "uses an object's own as_liquid_json when it has one" do
      custom = Class.new { def as_liquid_json = { "custom" => true } }.new

      expect(render_liquid("{{ foo | json }}", { "foo" => [custom] })).to(eq('[{"custom":true}]'))
    end
  end

  describe "parse_json" do
    it "parses" do
      expect(render_liquid(%({% assign foo = '{"a": [1, 2]}' | parse_json %}{{ foo.a | join: "," }}))).to(eq("1,2"))
    end

    it "yells about invalid JSON" do
      expect {
        render_liquid(%({{ "{nope" | parse_json }}))
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: parse_json failed: invalid JSON at line 1, column 2\n\ninput:\n{nope"))
    end

    it "quotes only the start of long invalid input" do
      input = "{" + ("x" * 500)

      expect {
        render_liquid("{{ s | parse_json }}", { "s" => input })
      }.to(raise_error(Liquid::ArgumentError, /\ninput:\n\{x{79}…\z/))
    end

    it "never quotes input past its first 80 characters, wherever parsing failed" do
      input = "[" + ("1," * 2000) + "SECRET-MARKER"

      expect {
        render_liquid("{{ s | parse_json }}", { "s" => input })
      }.to(raise_error(Liquid::ArgumentError) { |error|
        chain = []
        link = error
        while link
          chain << link
          link = link.cause
        end

        expect(chain.map(&:class)).not_to(include(JSON::ParserError))
        chain.each { |each_error| expect(each_error.message).not_to(include("SECRET-MARKER")) }
        expect(error.full_message(highlight: false)).not_to(include("SECRET-MARKER"))
        expect(error.message).not_to(include("SECRET-MARKER"))
        expect(error.message).to(include("at line 1, column 4002"))
        expect(error.message).to(end_with("#{input[0, 80]}…"))
      })
    end

    it "returns nil for invalid JSON when silent" do
      expect(render_liquid(%({% assign foo = "{nope" | parse_json: silent: true %}{{ foo | json }}))).to(eq("null"))
    end

    it "yells about non-strings" do
      expect {
        render_liquid("{{ 5 | parse_json }}")
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: parse_json can only be used on strings; received integer instead"))
    end
  end
end
