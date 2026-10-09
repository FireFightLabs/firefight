require "test_helper"

# What a code fix's calls cost, which its budget counts. Seen live, an hour of fixes on Claude Opus 5.5 counted $7.17
# where they cost about $1.27, since cache reads were charged at the full input price, and three fixes stopped on a $2
# budget having used about a sixth of it.
class FirefightAi::CostTest < ActiveSupport::TestCase
  test "cache reads and writes are charged at their own prices, for the model as the provider that served it prices it" do
    cost = FirefightAi.cost_micros("claude-opus-5-5", provider: "anthropic", input: 1_720_000, output: 20_000, cache_read: 1_550_000, cache_write: 50_000)

    # 120k plain input at $4, 1.55M cache reads at $0.20, 50k cache writes at $5, 20k output at $20.
    assert_equal 480_000 + 310_000 + 250_000 + 400_000, cost
    assert_operator cost, :<, 1_720_000 * 4, "far below charging every input token at the full price"

    vertex = FirefightAi.cost_micros("claude-opus-5-5", provider: "vertexai", input: 1_000_000, output: 0, cache_read: 1_000_000)
    assert_equal 400_000, vertex, "the provider's own cache read price"
  end

  test "a kind of token the registry has no price for is charged as plain input, and an unknown model costs nothing" do
    written = FirefightAi.cost_micros("claude-opus-5-5", provider: "vertexai", input: 1_000_000, output: 0, cache_write: 1_000_000)
    assert_equal 8_000_000, written, "a million input tokens all written to the cache, with no cache write price, cost what a million inputs do"

    assert_equal 0, FirefightAi.cost_micros("no-such-model", provider: "anthropic", input: 1_000, output: 1_000)
    assert FirefightAi.priced_for?("claude-opus-5-5", "anthropic")
    assert_not FirefightAi.priced_for?("claude-opus-5-5", "openai")
  end
end
