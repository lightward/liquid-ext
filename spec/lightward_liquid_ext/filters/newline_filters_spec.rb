# frozen_string_literal: true

RSpec.describe(LightwardLiquidExt::Filters::NewlineFilters) do
  let(:sample) { "foo\r\nbar\r\nbaz" }

  def test(template, expected_result, context: { "sample" => sample })
    expect(Liquid::Template.parse(template).render!(context)).to(eq(expected_result))
  end

  it "begins sanely" do
    test("{{ sample }}", sample)
  end

  describe "newline_to_br" do
    it "keeps existing behavior" do
      test("{% assign foo = 'abc' %}{{ foo | newline_to_br }}", "abc")
      test("{% capture foo %}a\nb\nc{% endcapture %}{{ foo | newline_to_br }}", "a<br />\nb<br />\nc")
    end

    it "handles carriage returns" do
      test("{{ sample | newline_to_br }}", "foo<br />\nbar<br />\nbaz")
    end
  end

  describe "replace" do
    it "keeps existing behavior" do
      test("{% assign foo = 'abc' %}{{ foo | replace: 'b', 'a' | replace: 'c', 'a' }}", "aaa")
      test("{% assign foo = 'abc' %}{{ foo | replace: 'z', 'a' }}", "abc")
      test("{% assign foo = 'abc' %}{{ foo | replace: nil, 'a' }}", "aaabaca")
      test("{% assign foo = 'abc' %}{{ foo | replace: hash, 'a' }}", "abc")
      test("{% assign foo = 'abc' %}{{ foo | replace: array, 'a' }}", "abc")
    end

    it "matches Liquid's own replace for anything but the newline literal" do
      environment = Liquid::Environment.build
      [
        ["abc", "b", "x"], ["abc", nil, "x"], ["abc", {}, "x"], ["abc", [], "x"], ["a\r\nb", "\n", "-"], [nil, "a", "b"], [12, 1, 3],
      ].each do |input, string, replacement|
        template = "{{ input | replace: string, replacement }}"
        assigns = { "input" => input, "string" => string, "replacement" => replacement }

        expect(Liquid::Template.parse(template).render!(assigns))
          .to(eq(Liquid::Template.parse(template, environment: environment).render!(assigns)))
      end
    end

    it "handles carriage returns given the newline literal" do
      test("{{ sample | replace: newline, '---' }}", "foo---bar---baz")
      test("{{ sample | replace: newline, newline }}", "foo\nbar\nbaz")
    end

    it "ignores other ways to achieve a newline" do
      test("{% assign imposter_newline = newline %}{{ sample | replace: imposter_newline, '---' }}", "foo\r---bar\r---baz")
      test("{% capture imposter_newline %}\n{% endcapture %}{{ sample | replace: imposter_newline, '---' }}", "foo\r---bar\r---baz")
    end
  end

  describe "split" do
    it "keeps existing behavior" do
      test("{% assign foo = 'abc' %}{{ foo | split: 'b' | join: '-' }}", "a-c")
      test("{% assign foo = 'abc' %}{{ foo | split: 'z' | join: '-' }}", "abc")
      test("{% assign foo = 'abc' %}{{ foo | split: nil | join: '-' }}", "a-b-c")
      test("{% assign foo = 'abc' %}{{ foo | split: hash | join: '-' }}", "abc")
      test("{% assign foo = 'abc' %}{{ foo | split: array | join: '-' }}", "abc")
    end

    it "matches Liquid's own split for anything but the newline literal" do
      environment = Liquid::Environment.build
      [["a,b", ","], ["abc", nil], ["abc", {}], ["abc", []], ["a\r\nb", "\n"], [nil, ","], [123, 2]].each do |input, pattern|
        template = "{{ input | split: pattern | join: '|' }}"
        assigns = { "input" => input, "pattern" => pattern }

        expect(Liquid::Template.parse(template).render!(assigns))
          .to(eq(Liquid::Template.parse(template, environment: environment).render!(assigns)))
      end
    end

    it "handles carriage returns given the newline literal" do
      test("{{ sample | split: newline | join: '---' }}", "foo---bar---baz")
      test("{{ sample | split: newline | join: newline }}", "foo\nbar\nbaz")
    end

    it "ignores other ways to achieve a newline" do
      test("{% assign imposter_newline = newline %}{{ sample | split: imposter_newline | join: '---' }}", "foo\r---bar\r---baz")
      test("{% capture imposter_newline %}\n{% endcapture %}{{ sample | split: imposter_newline | join: '---' }}", "foo\r---bar\r---baz")
    end
  end
end
