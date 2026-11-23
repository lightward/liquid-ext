# frozen_string_literal: true

module AssignTagSpecDrops
  class WidgetDrop < Liquid::Drop
    def name
      "a widget"
    end
  end

  class StoreDrop < Liquid::Drop
    def name
      "example-store"
    end
  end
end

RSpec.describe(LightwardLiquidExt::AssignTag) do
  context "with json parsing" do
    def test(template, expected = nil)
      if expected.nil?
        render_liquid(template)
      else
        result = JSON.parse(render_liquid(template).strip)
        expect(result).to(eq(expected))
      end
    end

    describe "array assignment" do
      it "works" do
        test('{% assign foo = "1, 2, 3" | split: ", " %}{% assign foo[3] = 4 %}{{ foo | json }}', ["1", "2", "3", 4])
      end

      it "rejects non-integer keys" do
        expect {
          test('{% assign foo = "1, 2, 3" | split: ", " %}{% assign foo["three"] = 4 %}')
        }.to(raise_error(Liquid::Error, 'Liquid error: Tried to use "three" as an index for array assignment during {% assign foo["three"] = 4 %}, but only integers can be used for array assignment'))
      end

      it "handles lookups within the lookup" do
        test("{% assign foo = array %}{% assign foo[foo.size] = 1 %}{% assign foo[foo.size] = 2 %}{{ foo | json }}", [1, 2])
        test("{% assign foo = array %}{% assign foo[foo.size] = 1 %}{% assign bar = array %}{% assign bar[foo.first] = 1 %}{{ bar | json }}", [nil, 1])

        expect {
          test("{% assign foo = array %}{% assign foo[foo.size] = 1 %}{% assign bar = array %}{% assign bar[foo[0]] = 1 %}{{ bar | json }}", [nil, 1])
        }.to(raise_error(Liquid::Error, "Liquid syntax error: Encountered nested bracket lookups during {% assign bar[foo[0]] = 1 %}, but this is not permitted"))
      end

      it "assigns by value, not by reference" do
        test(
          '
            {% assign foo = "[]" | parse_json %}
            {% assign bar = "[]" | parse_json %}
            {% assign foo[0] = bar %}
            {% assign bar[0] = "hello!" %}
            [{{ foo | json }}, {{ bar | json }}]
          ',
          [
            [[]],
            ["hello!"],
          ],
        )
      end

      it "takes negative indexes within the array, and refuses them beyond it" do
        test('{% assign foo = "1, 2" | split: ", " %}{% assign foo[-1] = 3 %}{{ foo | json }}', ["1", 3])

        expect {
          test('{% assign foo = "1, 2" | split: ", " %}{% assign foo[-3] = 3 %}')
        }.to(raise_error(Liquid::Error, 'Liquid error: Tried to use -3 as an index for array assignment during {% assign foo[-3] = 3 %}, but the array only has 2 items'))
      end

      describe "the gap cap" do
        after { LightwardLiquidExt.max_array_gap = 100_000 }

        it "allows up to 100,000 empty slots by default, with no Liquid limits set" do
          expect(LightwardLiquidExt.max_array_gap).to(eq(100_000))
          expect(render_liquid("{% assign a = array %}{% assign a[100000] = 1 %}{{ a | size }}")).to(eq("100001"))
        end

        it "refuses more before allocating, with no Liquid limits set" do
          expect {
            render_liquid("{% assign a = array %}{% assign a[0] = 0 %}{% assign a[100002] = 1 %}")
          }.to(raise_error(Liquid::Error, "Liquid error: Tried to use 100002 as an index for array assignment during {% assign a[100002] = 1 %}, but that would add 100001 empty slots to an array of 1, and at most 100000 are allowed"))

          expect {
            render_liquid("{% assign a = array %}{% assign a[1000000000000] = 1 %}")
          }.to(raise_error(Liquid::Error, /at most 100000 are allowed/))
        end

        it "can be raised or turned off" do
          LightwardLiquidExt.max_array_gap = 10
          expect { render_liquid("{% assign a = array %}{% assign a[11] = 1 %}") }.to(raise_error(Liquid::Error, /at most 10 are allowed/))

          LightwardLiquidExt.max_array_gap = nil
          expect(render_liquid("{% assign a = array %}{% assign a[200000] = 1 %}{{ a | size }}")).to(eq("200001"))
        end
      end

      it "yells when an intermediate lookup can't be performed" do
        expect {
          test("{% assign foo = array %}{% assign foo[bar][baz] = 5 %}")
        }.to(raise_error(Liquid::Error, "Liquid error: Tried to resolve `foo[bar]` during `{% assign foo[bar][baz] = 5 %}`, but `bar` is not an integer and cannot be used for array lookups (found null)"))
      end

      context "when using assignment score resource limits" do
        let(:context) {
          context = Liquid::Context.new
          context.resource_limits.assign_score_limit = 100
          context
        }

        it "prevents overly distant assignments" do
          template = Liquid::Template.parse("{% assign foo = array %}{% assign foo[101] = 5 %}")

          expect {
            template.render!(context)
          }.to(raise_error(Liquid::MemoryError, "Liquid error: Memory limits exceeded"))
        end

        it "doesn't credit the score back when overwriting inside the array" do
          # Building a 60-item array costs about 60. Overwriting index 0 repeatedly
          # must keep adding, not subtract the array's length each time.
          template = Liquid::Template.parse(
            "{% assign foo = array %}{% assign foo[59] = 1 %}" \
              "{% for i in (1..50) %}{% assign foo[0] = 1 %}{% endfor %}",
          )

          expect {
            template.render!(context)
          }.to(raise_error(Liquid::MemoryError, "Liquid error: Memory limits exceeded"))
        end
      end
    end

    describe "hash assignment" do
      it "takes quoted keys with brackets in them" do
        test('{% assign foo = hash %}{% assign foo["a]b"] = 1 %}{% assign foo[\'[c\'] = 2 %}{{ foo | json }}', { "a]b" => 1, "[c" => 2 })
      end

      it "works" do
        test('{% assign foo = "{}" | parse_json %}{% assign foo["bar"] = "baz" %}{{ foo | json }}', { "bar" => "baz" })
      end

      it "works in a nested fashion too" do
        test('{% assign foo = \'{"bar": {}}\' | parse_json %}{% assign foo["bar"]["baz"] = "qux" %}{{ foo | json }}', { "bar" => { "baz" => "qux" } })
      end

      it "descriptively prevents assignments on dot lookups" do
        expect {
          test('{% assign foo = \'{"bar": {}}\' | parse_json %}{% assign foo.bar["baz"] = "qux" %}{{ foo | json }}')
        }.to(raise_error(Liquid::Error, 'Liquid error: Assignment with dot lookups is not permitted; try replacing {% assign foo.bar["baz"] = "qux" %} with {% assign foo["bar"]["baz"] = "qux" %}'))

        expect {
          test('{% assign foo.bar = "baz" %}')
        }.to(raise_error(Liquid::Error, 'Liquid error: Assignment with dot lookups is not permitted; try replacing {% assign foo.bar = "baz" %} with {% assign foo["bar"] = "baz" %}'))
      end

      it "rejects non-string keys" do
        expect {
          test('{% assign foo = "{}" | parse_json %}{% assign foo[5] = "bar" %}')
        }.to(raise_error(Liquid::Error, 'Liquid error: Tried to use 5 as a key for hash assignment during {% assign foo[5] = "bar" %}, but only strings can be used for hash assignment'))
      end

      it "assigns by value, not by reference" do
        test(
          '
            {% assign foo = "{}" | parse_json %}
            {% assign bar = "{}" | parse_json %}
            {% assign foo["bar"] = bar %}
            {% assign bar["baz"] = "hello!" %}
            [{{ foo | json }}, {{ bar | json }}]
          ',
          [
            { "bar" => {} },
            { "baz" => "hello!" },
          ],
        )
      end

      it "yells when an intermediate lookup can't be performed" do
        expect {
          test("{% assign foo = hash %}{% assign foo[bar][baz] = 5 %}")
        }.to(raise_error(Liquid::Error, "Liquid error: Tried to resolve `foo[bar]` during `{% assign foo[bar][baz] = 5 %}`, but `bar` is not a string and cannot be used for hash lookups (found null)"))
      end
    end

    describe "plain assignment of a hash or array" do
      it "copies all the way down, so later assignments can't reach the original" do
        test(
          '
            {% assign original = \'{"inner": {"list": []}}\' | parse_json %}
            {% assign copy = original %}
            {% assign copy["top"] = 1 %}
            {% assign copy["inner"]["added"] = 2 %}
            {% assign copy["inner"]["list"][0] = 3 %}
            [{{ original | json }}, {{ copy | json }}]
          ',
          [
            { "inner" => { "list" => [] } },
            { "top" => 1, "inner" => { "list" => [3], "added" => 2 } },
          ],
        )
      end

      it "copies values that came from outside the template, leaving them unchanged" do
        outside = { "list" => [{ "name" => "a" }] }

        output = render_liquid(
          '{% assign copy = outside %}{% assign copy["list"][0]["name"] = "b" %}{{ copy | json }}',
          { "outside" => outside },
        )

        expect(JSON.parse(output)).to(eq({ "list" => [{ "name" => "b" }] }))
        expect(outside).to(eq({ "list" => [{ "name" => "a" }] }))
      end
    end

    it "predictably does not work on other things" do
      expect {
        test('{% assign foo = "1, 2, 3" %}{% assign foo[3] = 4 %}')
      }.to(raise_error(Liquid::Error, "Liquid error: Encountered a string at `foo` that is not assignable, in `{% assign foo[3] = 4 %}`. Only locally-initialized hashes and arrays support assignments."))

      expect {
        test('{% assign foo = \'{"bar": "1, 2, 3"}\' | parse_json %}{% assign foo["bar"][3] = 4 %}')
      }.to(raise_error(Liquid::Error, 'Liquid error: Encountered a string at `foo["bar"]` that is not assignable, in `{% assign foo["bar"][3] = 4 %}`. Only locally-initialized hashes and arrays support assignments.'))
    end

    it "does not reveal module scopes" do
      context = Liquid::Context.new
      context["widget"] = AssignTagSpecDrops::WidgetDrop.new

      expect {
        Liquid::Template.parse('{% assign foo = widget %}{% assign foo["bar"] = 4 %}').render!(context)
      }.to(raise_error(Liquid::Error, 'Liquid error: Encountered a widget drop at `foo` that is not assignable, in `{% assign foo["bar"] = 4 %}`. Only locally-initialized hashes and arrays support assignments.'))
    end

    it "works together" do
      test(
        '{% assign zero = 0 %}{% assign b = "b" %}{% assign a = hash %}{% assign a["b"] = array %}{% assign a[b][zero] = "hello" %}{{ a | json }}',
        { "b" => ["hello"] },
      )

      test(
        '{% assign a = array %}{% assign a[a.size] = hash %}{% assign a[0]["b"] = "hello" %}{{ a | json }}',
        [{ "b" => "hello" }],
      )
    end
  end

  describe "core functionality" do
    def test(template, result)
      expect(Liquid::Template.parse(template).render.strip).to(eq(result))
    end

    it "works" do
      test('{% assign abc = "abcdef" | split: "" %}{% assign foo = 5 %}{% assign bar = foo %}{% assign baz = abc[bar] %}{{ baz }}', "f")
    end

    it "assigns with filters" do
      test('{% assign foo = "foo" | append: "bar" | append: "baz" %}{{ foo }}', "foobarbaz")
    end

    it "assigns with filters on multiple lines" do
      test(
        '
          {% assign foo = "foo"
              | append: "bar"
              | append: "baz"
            %}
          {{ foo }}
        ',
        "foobarbaz",
      )
    end

    it "works inside a liquid tag" do
      test(%({% liquid\n  assign foo = hash\n  assign foo["bar"] = "baz"\n  echo foo["bar"]\n%}), "baz")
    end

    it "charges plain assignments to the assign score, as Liquid does" do
      context = Liquid::Context.new
      context.resource_limits.assign_score_limit = 5

      expect {
        Liquid::Template.parse('{% assign foo = "123456" %}').render!(context)
      }.to(raise_error(Liquid::MemoryError))
    end
  end

  context "with an environment variable" do
    let(:context) { Liquid::Context.new([{ "store" => AssignTagSpecDrops::StoreDrop.new }]) }

    def render(template)
      Liquid::Template.parse(template, line_numbers: true).render!(context)
    end

    it "does not update within environment variables" do
      expect(render("{{ store.name }}")).to(eq("example-store"))

      expect {
        render('{% assign store["name"] = "little" %}')
      }.to(raise_error(Liquid::Error, 'Liquid error (line 1): Tried to assign within an environment variable during {% assign store["name"] = "little" %}. To perform this assignment, start by overriding the environment variable with a new locally-defined hash or array.'))
    end

    it "does create local overrides to environment variables" do
      expect {
        expect(render('{% assign store = "foo" %}{{ store }}')).to(eq("foo"))
      }.to(not_change { context.environments.first["store"] }.from(an_instance_of(AssignTagSpecDrops::StoreDrop))
        .and(change { context.scopes.last["store"] }.from(nil).to("foo")))
    end
  end

  describe "the assign hook" do
    after { LightwardLiquidExt.assign_hook = nil }

    it "is off by default" do
      expect(LightwardLiquidExt.assign_hook).to(be_nil)
    end

    it "is called with the context on every assign" do
      seen = []
      LightwardLiquidExt.assign_hook = ->(context) { seen << context }

      context = Liquid::Context.new
      Liquid::Template.parse('{% assign a = hash %}{% assign a["b"] = 1 %}').render!(context)

      expect(seen).to(eq([context, context]))
    end

    it "can stop a render by raising" do
      LightwardLiquidExt.assign_hook = ->(_context) { raise(Liquid::Error, "stopped") }

      expect { render_liquid("{% assign a = 1 %}") }.to(raise_error(Liquid::Error, /stopped/))
    end
  end
end

RSpec::Matchers.define_negated_matcher(:not_change, :change)
