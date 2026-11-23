# frozen_string_literal: true

RSpec.describe(LightwardLiquidExt::KeywordLiterals) do
  def test(template, expected = NO_EXPECTATION, **options)
    if expected.equal?(NO_EXPECTATION)
      render_liquid(template)
    else
      result = JSON.parse(Liquid::Template.parse(template, **options).render!.strip)
      expect(result).to(eq(expected))
    end
  end

  describe "additional literals" do
    it "includes newline, hash, and array, behaving like normal literals" do
      test("{{ true | json }}", true)
      test("{% assign true = false %}{{ true | json }}", true)

      test("{{ newline | json }}", "\n")
      test('{% assign newline = "n" %}{{ newline | json }}', "\n")
      test('{% assign a = newline | prepend: "before" | append: "after" %}{{ a | json }}', "before\nafter")

      test("{{ hash | json }}", {})
      test('{% assign hash = "a" %}{{ hash | json }}', {})
      test('{% assign a = hash %}{% assign a["foo"] = "bar" %}{{ a | json }}', { "foo" => "bar" })

      test("{{ array | json }}", [])
      test('{% assign array = "a" %}{{ array | json }}', [])
      test('{% assign a = array %}{% assign a[0] = "foobar" %}{{ a | json }}', ["foobar"])
      test("{% assign a = array | concat: array %}{{ a | json }}", [])
      test('{% assign a = array %}{% assign b = "abc" | split: "" %}{% assign c = a | concat: b %}{{ c | json }}', ["a", "b", "c"])
    end

    it "handles equality predictably" do
      test('{% assign foo = hash %}{% assign bar = "{}" | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', true)
      test('{% assign foo = hash %}{% assign bar = \'{"foo": "bar"}\' | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', false)

      test('{% assign foo = array %}{% assign bar = "[]" | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', true)
      test('{% assign foo = array %}{% assign bar = \'["foo", "bar"]\' | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', false)

      test("{% assign foo = newline %}{% capture bar %}" + "\n" + "{% endcapture %}{% if foo == bar %}true{% else %}false{% endif %}", true)
      test('{% assign foo = newline %}{% assign bar = "baz" %}{% if foo == bar %}true{% else %}false{% endif %}', false)
    end

    it "does not permit assigning within hash and array" do
      expect {
        test('{% assign hash["foo"] = "bar" %}')
      }.to(raise_error(Liquid::Error, 'Liquid error: Encountered a nil class at `hash` that is not assignable, in `{% assign hash["foo"] = "bar" %}`. Only locally-initialized hashes and arrays support assignments.'))

      expect {
        test('{% assign array[0] = "bar" %}')
      }.to(raise_error(Liquid::Error, 'Liquid error: Encountered a nil class at `array` that is not assignable, in `{% assign array[0] = "bar" %}`. Only locally-initialized hashes and arrays support assignments.'))
    end

    it "gives each assignment its own copy, leaving the shared literal untouched" do
      test(
        '{% assign a = hash %}{% assign b = hash %}{% assign a["x"] = 1 %}{% assign c = array %}{% assign c[0] = 1 %}' \
          "[{{ a | json }}, {{ b | json }}, {{ hash | json }}, {{ array | json }}]",
        [{ "x" => 1 }, {}, {}, []],
      )

      expect(described_class::LITERALS["hash"]).to(eq({}).and(be_frozen))
      expect(described_class::LITERALS["array"]).to(eq([]).and(be_frozen))
    end

    it "takes filters, used more than once in a template" do
      expect(render_liquid("{{ array | size }}-{{ array | size }}-{{ hash | size }}-{{ newline | size }}")).to(eq("0-0-0-1"))
    end

    it "is told apart from any other newline string by identity" do
      expect(LightwardLiquidExt::KeywordLiterals.newline?(Liquid::Context.new["newline"])).to(be(true))
      expect(LightwardLiquidExt::KeywordLiterals.newline?("\n")).to(be(false))
      expect(LightwardLiquidExt::KeywordLiterals.newline?(-"\n")).to(be(false))
    end

    [:lax, :warn, :strict, :strict2].each do |error_mode|
      it "works in #{error_mode} parse mode" do
        test(
          '{% assign a = hash %}{% assign a["list"] = array %}{% assign a["list"][0] = newline %}' \
            "{% if a.list.size == 1 %}{{ a | json }}{% endif %}",
          { "list" => ["\n"] },
          error_mode: error_mode,
        )
      end
    end

    describe "parsing" do
      it "resolves the keywords in an installed environment, outside Liquid's expression cache" do
        cache = {}
        parse_context = Liquid::ParseContext.new(environment: Liquid::Environment.default, expression_cache: cache)

        expect(parse_context.parse_expression("hash")).to(be(described_class::LITERALS["hash"]))
        expect(parse_context.parse_expression(" newline ")).to(be(described_class::NEWLINE))
        expect(parse_context.parse_expression("foo.bar")).to(be_a(Liquid::VariableLookup))
        expect(cache.keys).to(eq(["foo.bar"]))
      end

      it "leaves Liquid::Expression itself alone" do
        expect(Liquid::Expression.parse("hash")).to(be_a(Liquid::VariableLookup))
      end
    end

    describe "context lookups" do
      it "does not crash when context[] receives primitives" do
        context = Liquid::Context.build

        expect(context[true]).to(be(true))
        expect(context[123]).to(be(123))
        expect(context[:hash]).to(eq({}))
        expect(context["array"]).to(eq([]))
        expect(context[{ "foo" => "bar" }]).to(eq({ "foo" => "bar" }))
        expect(context[[1, 2, 3]]).to(eq([1, 2, 3]))
      end

      it "rejects unexpected objects" do
        expect {
          Liquid::Context.build[Class.new.new]
        }.to(raise_error(Liquid::Error, /must be a string or primitive/))
      end
    end
  end
end
