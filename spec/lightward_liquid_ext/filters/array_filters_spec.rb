# frozen_string_literal: true

RSpec.describe(LightwardLiquidExt::Filters::ArrayFilters) do
  describe "push" do
    it "appends" do
      expect(render_liquid('{{ "1,2" | split: "," | push | json }}')).to(eq('["1","2"]'))
      expect(render_liquid('{{ "1,2" | split: "," | push: "3" | json }}')).to(eq('["1","2","3"]'))
      expect(render_liquid('{{ "1,2" | split: "," | push: "3", "4" | json }}')).to(eq('["1","2","3","4"]'))
    end

    it "does not modify the original" do
      sample = <<~LIQUID
        {% assign foo = array %}
        {% assign foo[0] = "1" %}
        {% assign bar = foo | push: "2" %}
        foo: {{ foo | json }}
        bar: {{ bar | json }}
      LIQUID

      expect(render_liquid(sample).strip).to(eq(%(foo: ["1"]\nbar: ["1","2"])))
    end

    it "yells for a non-array" do
      expect {
        render_liquid('{{ "1,2" | push | json }}')
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: push can only be used on array-like objects; received string instead"))
    end
  end

  describe "unshift" do
    it "prepends" do
      expect(render_liquid('{{ "1,2" | split: "," | unshift | json }}')).to(eq('["1","2"]'))
      expect(render_liquid('{{ "1,2" | split: "," | unshift: "3" | json }}')).to(eq('["3","1","2"]'))
      expect(render_liquid('{{ "1,2" | split: "," | unshift: "3", "4" | json }}')).to(eq('["3","4","1","2"]'))
    end

    it "does not modify the original" do
      sample = <<~LIQUID
        {% assign foo = array %}
        {% assign foo[0] = "1" %}
        {% assign bar = foo | unshift: "2" %}
        foo: {{ foo | json }}
        bar: {{ bar | json }}
      LIQUID

      expect(render_liquid(sample).strip).to(eq(%(foo: ["1"]\nbar: ["2","1"])))
    end

    it "yells for a non-array" do
      expect {
        render_liquid('{{ "1,2" | unshift | json }}')
      }.to(raise_error(Liquid::ArgumentError, "Liquid error: unshift can only be used on array-like objects; received string instead"))
    end
  end

  it "leaves the array literal alone" do
    expect(render_liquid('{{ array | push: "a" | json }}{{ array | json }}')).to(eq('["a"][]'))
  end
end
