# frozen_string_literal: true

RSpec.describe("nesting depth") do
  let(:too_deep) { /Hashes and arrays can be nested at most 100 levels deep/ }

  def nested(levels)
    levels.times.reduce("leaf") { |inner, _| { "x" => inner } }
  end

  it "allows 100 levels of hashes and arrays, and refuses the 101st, when assigning by path" do
    template = +'{% assign a = hash %}'
    path = +""
    99.times { path << '["x"]'; template << "{% assign a#{path} = hash %}" }

    expect(JSON.parse(render_liquid(template + "{{ a | json }}")).to_s.count("{")).to(eq(100))

    path << '["x"]'
    expect { render_liquid(template + "{% assign a#{path} = hash %}") }.to(raise_error(Liquid::Error, too_deep))
    expect(render_liquid(template + "{% assign a#{path} = 1 %}ok")).to(eq("ok"))
  end

  it "refuses to copy host data nested too deep" do
    expect(render_liquid("{% assign a = deep %}ok", { "deep" => nested(100) })).to(eq("ok"))
    expect { render_liquid("{% assign a = deep %}", { "deep" => nested(101) }) }.to(raise_error(Liquid::Error, too_deep))
  end

  it "stops at a cycle instead of overflowing the stack" do
    cycle = []
    cycle << cycle

    expect { Liquid::Template.parse("{% assign a = c %}").render!({ "c" => cycle }) }.to(raise_error(Liquid::Error, too_deep))
    expect { Liquid::Template.parse("{{ c | json }}").render!({ "c" => cycle }) }.to(raise_error(Liquid::Error, too_deep))
  end

  it "renders JSON 100 levels deep, and refuses deeper in plain words" do
    expect(render_liquid("{{ deep | json | size }}", { "deep" => nested(100) }).to_i).to(be > 0)
    expect { render_liquid("{{ deep | json }}", { "deep" => nested(101) }) }.to(raise_error(Liquid::Error, too_deep))
  end

  it "shows the refusal as itself, not as an internal error, in a non-raising render" do
    template = Liquid::Template.parse("{{ deep | json }}")

    expect(template.render({ "deep" => nested(101) })).to(match(too_deep))
  end
end
