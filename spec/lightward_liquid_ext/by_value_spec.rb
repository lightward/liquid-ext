# frozen_string_literal: true

RSpec.describe("assignment by value, across scopes") do
  let(:file_system) do
    Class.new do
      def initialize(templates) = @templates = templates
      def read_template_file(name) = @templates.fetch(name)
    end
  end

  def environment_with(templates)
    Liquid::Environment.build(file_system: file_system.new(templates)) { |env| LightwardLiquidExt.install!(env) }
  end

  def render_in(environment, template, assigns = {})
    Liquid::Template.parse(template, environment: environment).render!(assigns)
  end

  describe "render" do
    let(:environment) do
      environment_with(
        "change" => '{% assign data["x"] = 1 %}{% assign data["inner"]["y"] = 2 %}inside: {{ data | json }}',
        "each" => '{% assign item["seen"] = true %}{{ item | json }}',
      )
    end

    it "gives a partial its own copy of a hash it changes" do
      output = render_in(
        environment,
        '{% assign h = hash %}{% assign h["inner"] = hash %}{% render "change", data: h %} outside: {{ h | json }}',
      )

      expect(output).to(eq('inside: {"inner":{"y":2},"x":1} outside: {"inner":{}}'))
    end

    it "does the same for each item of a for render" do
      output = render_in(
        environment,
        '{% assign list = array %}{% assign list[0] = hash %}{% render "each" for list as item %} {{ list | json }}',
      )

      expect(output).to(eq('{"seen":true} [{}]'))
    end
  end

  it "copies a host's outer-scope hash before changing it" do
    host = { "inner" => { "a" => 1 } }
    context = Liquid::Context.new({}, { "h" => host })

    output = Liquid::Template.parse('{% assign h["inner"]["b"] = 2 %}{{ h | json }}').render!(context)

    expect(output).to(eq('{"inner":{"a":1,"b":2}}'))
    expect(host).to(eq({ "inner" => { "a" => 1 } }))
  end

  it "says plainly that a loop variable can't be assigned into" do
    expect {
      render_liquid('{% assign items = array %}{% assign items[0] = array %}{% for s in items %}{% assign s[0] = 1 %}{% endfor %}')
    }.to(raise_error(Liquid::Error, "Liquid error: Tried to assign within `s` during {% assign s[0] = 1 %}, but `s` is a loop variable or an include parameter, which can't be assigned into. To perform this assignment, start by copying it into a variable of your own, e.g. {% assign my_s = s %}."))
  end

  it "lets a copy of a loop variable be assigned into" do
    output = render_liquid(
      '{% assign items = array %}{% assign items[0] = array %}' \
        '{% for s in items %}{% assign my_s = s %}{% assign my_s[0] = 1 %}{{ my_s | json }}{% endfor %} {{ items | json }}',
    )

    expect(output).to(eq("[1] [[]]"))
  end

  it "says plainly that an include parameter can't be assigned into" do
    environment = environment_with("inc" => '{% assign data["x"] = 1 %}')

    expect {
      render_in(environment, '{% assign h = hash %}{% include "inc", data: h %}')
    }.to(raise_error(Liquid::Error, /`data` is a loop variable or an include parameter/))
  end
end
