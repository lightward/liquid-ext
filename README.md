# lightward_liquid_ext

A few additions to [Shopify's Liquid](https://github.com/Shopify/liquid), so a template can build its own data: hashes and arrays you can fill in key by key, a `newline` you can split and join by, and regular expressions for pulling strings apart.

These come from [Mechanic](https://mechanic.dev), Lightward's automation platform for Shopify, where every task is written in Liquid. They run there in the tasks of real Shopify stores, parts of them since 2018. This gem is taken from that code, with some changes, so anyone using Liquid can have it. It stands on plain Liquid, with no Rails, and differs from Mechanic's Liquid in these ways:

- Assignment copies by value all the way down, including a plain `{% assign copy = original %}` and a hash or array handed to a `render` partial.
- An array assignment may add at most 100,000 empty slots past the end (`max_array_gap`, below).
- Hashes and arrays nest at most 100 levels deep, for assignment and for `json`.
- `first` and `last` on a match give its first and last characters, without needing ActiveSupport.
- The keywords `array`, `hash` and `newline` apply only in environments you install the gem into.
- Regular expressions run under a per-match timeout, `scan` counts against `render_score_limit`, and `parse_json` errors quote only the start of the input.

## Before you install: two things to know

**The three keywords take over three names.** In an environment where the gem is installed, `hash`, `array` and `newline` always mean the keyword literals. If your existing templates read a variable you pass in under one of those names (`{{ hash }}`, `{{ hash.secret }}`, `{% for x in array %}`), they'll see the literal instead once you install: every lookup rooted at one of these names resolves against the literal. Rename those variables first, or install into a separate environment for the templates that want the keywords. Environments you don't install into are untouched.

**If people you don't trust write your templates, set limits.** Liquid's own defaults set none, and this gem adds tags and filters that can allocate a lot in one step. One guard is always on: an array assignment may add at most `LightwardLiquidExt.max_array_gap` empty slots past the end (100,000 by default; raise it, or set `nil` to turn it off), so `{% assign a[1000000000] = 1 %}` is refused before anything is allocated. Liquid's three limits bound most of the rest. A regular expression timeout bounds each match. Neither bounds wall-clock time across a whole render, so add a deadline too:

```ruby
require "lightward_liquid_ext"

environment = Liquid::Environment.build do |env|
  LightwardLiquidExt.install!(env)
  env.default_resource_limits = {
    render_score_limit: 100_000,    # nodes rendered (a loop body on every pass), plus each match scan finds
    assign_score_limit: 100_000,    # bytes and items assigned, including empty array slots
    render_length_limit: 1_000_000, # bytes of output
  }
end

LightwardLiquidExt.regexp_timeout = 0.5 # seconds per match; the default is 1.0

# Checked at every assign. Raising a Liquid::MemoryError stops the render.
LightwardLiquidExt.assign_hook = ->(context) do
  deadline = context.registers[:deadline]
  raise(Liquid::MemoryError, "Render took too long") if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
end

template = Liquid::Template.parse(source, environment: environment)
template.render(assigns, registers: { deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2 })
```

What these don't cover, and what's left to you as the host:

- The regexp timeout bounds one match, not a render. A loop of slow matches costs the timeout once per match, and a non-raising `render` records each timeout and carries on. Ruby 3.2+ memoizes most backtracking away (`(a+)+b` is fast), but not patterns with lookarounds or backreferences, so those are the ones that reach the timeout. Bounding the render as a whole is the host's job.
- `assign_hook` is one setting for the whole process, not per environment or per render, so a host serving several kinds of template decides inside the hook what applies (registers are a good place to carry that). It runs only at `assign`. A template that loops over `match` without assigning never reaches it. For a hard bound, also run renders under your own wall-clock and memory limits (a worker process you can stop, for instance).
- Single filter calls on large input, in this gem and in Liquid itself (`(1..1000000000) | join`, `json` on a huge value, `scan` on a multi-megabyte string you passed in) do their work before any limit is checked. `scan` counts each match against `render_score_limit` as it goes, so it stops at the limit, but it still holds the matches it has found until then.

## What it adds

### `array`, `hash` and `newline`

Three keyword literals, usable anywhere Liquid takes a value:

```liquid
{% assign tags = array %}
{% assign tags = tags | push: "vip" | push: "wholesale" %}

{% assign customer = hash %}
{% assign customer["name"] = "Alice" %}

{% assign lines = some_text | split: newline %}
{{ lines | join: newline }}
```

They're literals, like Liquid's own `true` and `nil`: `{% assign hash = "x" %}` succeeds, but doesn't change what `hash` means afterwards, and a variable passed in under one of these names can't be read (see above). Each assignment gets an empty hash or array of its own. They take filters (`{{ array | size }}`), and lookups on them resolve against the literal: `{{ array.size }}` is 0, and `{{ hash.anything }}` or `{{ hash["anything"] }}` is empty.

### Assigning into hashes and arrays

`assign` can set a key in a hash or an index in an array, inside hashes and arrays that already exist:

```liquid
{% assign sizes = hash %}
{% assign sizes["S"] = "Small" %}
{% assign key = "M" %}
{% assign sizes[key] = "Medium" %}

{% assign weekdays = array %}
{% assign weekdays[0] = "Monday" %}
{% assign weekdays[weekdays.size] = "Tuesday" %}

{% assign report = hash %}
{% assign report["by_day"] = array %}
{% assign report["by_day"][0] = sizes %}

{{ report | json }}
```

The rules:

- Assignment is always by value. What you assign is copied, all the way down, so changing it later never changes anything else, and changing anything else never changes it. That includes a plain `{% assign copy = original %}`: assigning into `copy` afterwards leaves `original` alone. It holds across `render` too: a partial that assigns into a hash it was given changes its own copy, not the caller's.
- Copying has a cost: every plain `assign` of a hash or array copies the whole of it, so re-assigning a large collection in a loop costs its size each time (stock Liquid's assign is constant-time). `assign_score_limit` counts it.
- Intermediate keys must already exist; nothing is created along the way. `{% assign h["a"]["b"] = 1 %}` needs `h["a"]` to be a hash first (`{% assign h["a"] = hash %}`).
- Hashes and arrays nest at most 100 levels deep (the JSON library's own default). Going deeper, by assignment or with `json`, is refused with a plain error.
- Only hashes and arrays made with `assign` accept assignments: from `hash`, `array`, or a filter like `split` or `parse_json`. Variables the host passed in as the template's data can't be assigned into (assign a new hash or array over them first), and neither can strings or other objects. A hash or array that reaches a template another way, as an argument to a `render` partial or in a context's outer scope, is copied on its first change instead, so the original is never touched; a Hash or Array subclass there (a `HashWithIndifferentAccess`, say) becomes a plain Hash or Array in the copy. A `for` loop variable or an `include` parameter can't be assigned into either: copy it into a variable of your own first (`{% assign my_item = item %}`).
- Hashes take string keys. Arrays take integer indexes; a negative index counts from the end, within the array's length.
- Use brackets, not dots, on the left side: `{% assign foo.bar = 1 %}` is refused with a suggestion to write `{% assign foo["bar"] = 1 %}`. Lookups inside the brackets can be quoted strings or variables (`foo[key]`, `foo[foo.size]`), but not further bracket lookups (`foo[bar[0]]`), and there's no space inside the brackets.
- Assignments count against Liquid's `assign_score_limit`, the same way Liquid's own assign does. Assigning far past the end of an array counts every empty slot it creates.

Mechanic's documentation covers this in more depth: [assign](https://learn.mechanic.dev/platform/liquid/tags/assign) and [keyword literals](https://learn.mechanic.dev/platform/liquid/keyword-literals).

### `split` and `replace` with `newline`

Given the `newline` literal itself, `split` and `replace` match `"\r\n"` as well as `"\n"`, so text from Windows, email and spreadsheets splits cleanly:

```liquid
{% assign lines = pasted_text | split: newline %}
{% assign one_line = pasted_text | replace: newline, ", " %}
```

Given anything else, both filters behave exactly as Liquid's own. (Liquid's `newline_to_br` already handles `"\r\n"`.) See [newline](https://learn.mechanic.dev/platform/liquid/keyword-literals/newline).

### `match` and `scan`

Regular expressions, written as Ruby-compatible pattern strings:

```liquid
{{ "It's a lovely day!" | match: "(?<=a ).*(?= day)" }}
=> lovely

{% assign m = "It's a lovely day!" | match: "a (?<adjective>bucolic|lovely) day" %}
{{ m.captures | json }}        => ["lovely"]
{{ m.named_captures | json }}  => {"adjective":"lovely"}

{{ "It's a lovely day!" | scan: "[\w']+" | json }}
=> ["It's","a","lovely","day"]

{{ "It's a lovely day!" | scan: "(bucolic|lovely|day)" | map: "captures" | json }}
=> [["lovely"],["day"]]
```

`match` returns the first match, or nil. `scan` returns every match. A match renders as the matched text and behaves like it for string filters and for `size`, `first` and `last` (its length, first character and last character), with `captures` and `named_captures` for the groups. Matches don't sort; `map` them to strings first. There's no `m[0]` or `m["name"]`: Liquid reads `m.foo` and `m["foo"]` as the same lookup, so asking for the captures by name keeps it clear what you're getting. See [match](https://learn.mechanic.dev/platform/liquid/filters#match) and [scan](https://learn.mechanic.dev/platform/liquid/filters#scan).

Each match gives up after `LightwardLiquidExt.regexp_timeout` seconds (1.0 by default; `nil` inherits Ruby's process-wide `Regexp.timeout`, which is no limit unless you set one) with an error saying so. Compiled patterns are reused, up to a hundred at a time.

### `push`, `unshift`, `json` and `parse_json`

```liquid
{% assign list = array | push: "b", "c" | unshift: "a" %}
{{ list | json }}  => ["a","b","c"]

{% assign data = '{"items": [1, 2]}' | parse_json %}
{% assign maybe = untrusted_text | parse_json: silent: true %}
```

`push` and `unshift` return a new array and leave the original alone. `parse_json` with `silent: true` gives nil for invalid JSON instead of an error; without it, the error gives the line and column where parsing failed (when the JSON parser reports them) and the first 80 characters of the input, and nothing else from the input. An object can choose its own JSON form for `json` by responding to `as_liquid_json`. See [json, parse_json](https://learn.mechanic.dev/platform/liquid/filters#json-parse_json).

## Installing

```ruby
# Gemfile
gem "lightward_liquid_ext"
```

Or straight from the source:

```ruby
gem "lightward_liquid_ext", git: "https://github.com/lightward/liquid-ext"
# or, with a local checkout:
gem "lightward_liquid_ext", path: "../liquid-ext"
```

```ruby
require "lightward_liquid_ext"

LightwardLiquidExt.install!  # Liquid::Environment.default
```

Or for an environment of your own (`Liquid::Environment.build` freezes what it builds, so install inside the block):

```ruby
environment = Liquid::Environment.build do |env|
  LightwardLiquidExt.install!(env)
end

Liquid::Template.parse(source, environment: environment).render!(assigns)
```

`install!` registers the `assign` tag and the filters on the environment you give it, turns on the keyword literals for templates parsed and rendered in it, and is safe to call more than once. Other environments are untouched, and requiring the gem changes nothing until you call it.

### A hook on every assign

```ruby
LightwardLiquidExt.assign_hook = ->(context) { Thread.pass }
```

If set, it's called with the `Liquid::Context` at the start of every `assign`. If it raises, that assign doesn't happen. What happens next depends on what it raises:

- A `Liquid::MemoryError` stops the render, under `render` and `render!` alike. Use it to stop a render.
- Under `render!`, anything it raises stops the render and reaches you.
- Under a non-raising `render`, any other `Liquid::Error` is recorded in `template.errors` with its own message, and the render carries on. Any error that isn't a `Liquid::Error` is recorded there as `Liquid::InternalError` ("Liquid error: internal"), with the original kept only as that error's `cause`, and the render carries on. So raise a `Liquid::Error` subclass if you want the reason to show. (In lax and strict mode the message isn't written into the output, since `assign` writes nothing; in strict2 it is.)

A host can use it to give other threads a turn, check a deadline, or count work. It's `nil` by default, and it's one setting for the whole process.

## Which Liquid

Versions follow semver, counted from 1.0.0 on the first release: the number describes the change that comes after, not a verdict on the start, so a breaking change is 2.0.

This gem targets Liquid 5.14 (the current release as of November 2026) and follows current Liquid: the gemspec allows `>= 5.14, < 6`, and new Liquid releases are what it moves toward. Most of the specs run in Liquid's default parse mode, `lax`; one renders the keyword literals and bracket assignment in each of `lax`, `warn`, `strict` and `strict2`, and another checks the literals in `strict2` in an environment without the gem. On install, it checks the Liquid version and the shape of the few Liquid methods it extends (`Liquid::ParseContext#parse_expression` and `#safe_parse_expression`, and `Liquid::Context#[]`), and raises `LightwardLiquidExt::IncompatibleLiquidError` with a pointer back here if either isn't what it expects.

The specs pass on Ruby 3.4 and 4.0, and the gemspec asks for Ruby 3.4 or later.

It depends on `base64` because Liquid 5.14 requires it without declaring it, and Ruby 3.4 stopped shipping it by default.

## Prior art

Shopify has explored array literals in Liquid itself: [Shopify/liquid#2134](https://github.com/Shopify/liquid/pull/2134) (closed), a research draft adding a bracketed syntax (`['top', 'bottom']`) to the expression grammar. This gem takes a different, smaller route (keyword literals plus assignment by key and index), the one Mechanic has used.

## Development

```sh
bundle install
bundle exec rspec
```

## License

Public domain, under the [Unlicense](UNLICENSE).
