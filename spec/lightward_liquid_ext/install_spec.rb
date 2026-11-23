# frozen_string_literal: true

RSpec.describe(LightwardLiquidExt) do
  describe ".install!" do
    it "registers the tag and filters on the environment it's given" do
      plain = Liquid::Environment.build
      template = '{% assign a = hash %}{% assign a["b"] = "x" | split: "," | push: "y" %}{{ a | json }}'

      expect(plain.tag_for_name("assign")).to(be(Liquid::Assign))

      returned = nil
      environment = Liquid::Environment.build { |env| returned = LightwardLiquidExt.install!(env) }

      expect(returned).to(be(environment))

      expect(environment.tag_for_name("assign")).to(be(LightwardLiquidExt::AssignTag))
      expect(Liquid::Template.parse(template, environment: environment).render!).to(eq('{"b":["x","y"]}'))
    end

    it "leaves an environment it can't change as it was, keywords included" do
      environment = Liquid::Environment.build

      expect { LightwardLiquidExt.install!(environment) }.to(raise_error(FrozenError))

      expect(environment.tag_for_name("assign")).to(be(Liquid::Assign))
      expect(LightwardLiquidExt::KeywordLiterals.installed?(environment)).to(be(false))
      expect(Liquid::Template.parse("{{ hash }}", environment: environment).render!({ "hash" => "H" })).to(eq("H"))
    end

    it "is idempotent" do
      environment = Liquid::Environment.build { |env| 3.times { LightwardLiquidExt.install!(env) } }

      expect(Liquid::ParseContext.ancestors.count(LightwardLiquidExt::KeywordLiterals::ParseContextHooks)).to(eq(1))
      expect(Liquid::Context.ancestors.count(LightwardLiquidExt::KeywordLiterals::ContextHooks)).to(eq(1))
      expect(environment.tag_for_name("assign")).to(be(LightwardLiquidExt::AssignTag))
      expect(Liquid::Template.parse("{{ x | split: newline | json }}", environment: environment).render!({ "x" => "a\r\nb" }))
        .to(eq('["a","b"]'))
    end

    it "leaves environments it wasn't given alone, keyword literals included" do
      environment = Liquid::Environment.build
      host_data = { "hash" => "H", "array" => [1], "newline" => "<br>" }

      expect(environment.tag_for_name("assign")).to(be(Liquid::Assign))
      expect(
        Liquid::Template.parse("{{ hash }}|{{ array | size }}|{{ newline }}|{{ array[0] }}", environment: environment)
          .render!(host_data),
      ).to(eq("H|1|<br>|1"))
      expect(Liquid::Template.parse("{{ hash }}|{{ array | size }}", error_mode: :strict2, environment: environment)
          .render!(host_data)).to(eq("H|1"))
      expect(Liquid::Context.build(environment: environment)["hash"]).to(be_nil)
    end

    describe "in its own environment, lookups rooted at a keyword" do
      let(:host_data) { { "hash" => { "secret" => "value" }, "array" => ["first"], "newline" => "host" } }

      [:lax, :warn, :strict, :strict2].each do |error_mode|
        it "resolve against the literal, never the host's variable, in #{error_mode} mode" do
          {
            "{{ hash.secret }}" => "",
            '{{ hash["secret"] }}' => "",
            "{{ hash.size }}" => "0",
            "{{ array.first }}" => "",
            "{{ array[0] }}" => "",
            "{{ array.size }}" => "0",
            "{{ newline.size }}" => "1",
            "{{ self.hash.secret }}" => "",
            '{{ self["array"].first }}' => "",
            "{% for x in array %}{{ x }}{% endfor %}" => "",
            "{% if hash.secret %}leaked{% endif %}" => "",
            "{% assign a = hash.secret %}{{ a }}" => "",
            "{{ hash.secret | default: 'none' }}" => "none",
          }.each do |template, expected|
            output = Liquid::Template.parse(template, error_mode: error_mode).render!(host_data)
            expect(output).to(eq(expected), "#{template} rendered #{output.inspect}")
          end
        end
      end

      it "are still read from the host in an environment without the gem" do
        environment = Liquid::Environment.build

        output = Liquid::Template.parse(
          '{{ hash.secret }}|{{ hash["secret"] }}|{{ array.first }}|{{ self.hash.secret }}', environment: environment,
        ).render!(host_data)

        expect(output).to(eq("value|value|first|value"))
      end
    end

    it "makes the keyword literals take over host variables of the same names, in its own environment" do
      host_data = { "hash" => "H", "array" => [1], "newline" => "<br>" }

      expect(render_liquid("{{ hash | json }}|{{ array | size }}|{{ newline | json }}", host_data)).to(eq('{}|0|"\\n"'))
    end
  end
end
