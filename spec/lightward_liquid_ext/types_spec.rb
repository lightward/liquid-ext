# frozen_string_literal: true

RSpec.describe("hash and array types") do
  def test(template, expected = nil, context: {})
    result = JSON.parse(render_liquid(template, context).strip)

    expect(result).to(eq(expected)) if expected
  end

  describe "equality" do
    it "compares arrays by contents" do
      test("{% assign foo = array %}{% assign bar = array %}{% if foo == bar %}true{% else %}false{% endif %}", true)
      test('{% assign foo = array %}{% assign bar = "" | split: "" %}{% if foo == bar %}true{% else %}false{% endif %}', true)
      test('{% assign foo = array %}{% assign bar = "[]" | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', true)
      test('{% assign foo = array %}{% assign foo[0] = "bar" %}{% assign bar = \'["bar"]\' | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', true)

      test(
        %(
          {% assign foo = array %}{% assign foo[0] = array %}{% assign foo[0][0] = "bar" %}
          {% assign bar = array %}{% assign bar[0] = array %}{% assign bar[0][0] = "bar" %}
          {% if foo == bar %}true{% else %}false{% endif %}
        ),
        true,
      )

      test(
        %(
          {% assign foo = array %}{% assign foo[0] = array %}{% assign foo[0][0] = "bar" %}
          {% if foo == bar %}true{% else %}false{% endif %}
        ),
        true,
        context: { "bar" => [["bar"]] },
      )
    end

    it "compares hashes by contents" do
      test("{% assign foo = hash %}{% assign bar = hash %}{% if foo == bar %}true{% else %}false{% endif %}", true)
      test('{% assign foo = hash %}{% assign bar = "{}" | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', true)
      test('{% assign foo = hash %}{% assign foo["bar"] = "baz" %}{% assign bar = \'{"bar": "baz"}\' | parse_json %}{% if foo == bar %}true{% else %}false{% endif %}', true)

      test(
        %(
          {% assign foo = hash %}{% assign foo["bar"] = "baz" %}
          {% assign bar = hash %}{% assign bar["bar"] = "baz" %}
          {% if foo == bar %}true{% else %}false{% endif %}
        ),
        true,
      )

      test(
        %(
          {% assign foo = hash %}{% assign foo["bar"] = hash %}{% assign foo["bar"]["baz"] = "qux" %}
          {% assign bar = hash %}{% assign bar["bar"] = hash %}{% assign bar["bar"]["baz"] = "qux" %}
          {% if foo == bar %}true{% else %}false{% endif %}
        ),
        true,
      )

      test(
        %(
          {% assign foo = hash %}{% assign foo["bar"] = hash %}{% assign foo["bar"]["baz"] = "qux" %}
          {% if foo == bar %}true{% else %}false{% endif %}
        ),
        true,
        context: { "bar" => { "bar" => { "baz" => "qux" } } },
      )
    end
  end
end
