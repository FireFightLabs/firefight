require "test_helper"

# What a code fix's calls cost, which its budget counts. Seen live, an hour of fixes on Claude Opus 5.5 counted $7.17
# where they cost about $1.27, since cache reads were charged at the full input price, and three fixes stopped on a $2
# budget having used about a sixth of it.
class FirefightAi::CostTest < ActiveSupport::TestCase
  include FakeProviderHelper

  test "a call's ledger row keeps how long its cache writes last, and its cost prices an hour's writes higher" do
    FakeProviderHelper::Adapter.reset!
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-opus-5-5", stop_reason: "end_turn",
                  content: [ { type: "text", text: "Done." } ],
                  usage: { input_tokens: 100, output_tokens: 10, cache_creation_input_tokens: 1_000_000,
                           cache_creation: { ephemeral_1h_input_tokens: 1_000_000, ephemeral_5m_input_tokens: 0 } } })
    choice = FirefightAi::ModelChoice.new(model: "claude-opus-5-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: "sk-ant-test"))

    _, row = FirefightAi.generate(choice, purpose: AiPurpose::SUMMARY, inference: { workspace: workspaces(:slack_workspace_one), feature: "cost_test" }) do |chat|
      chat.ask("Say done")
    end

    assert_equal({ "1h" => 1_000_000 }, row.cache_write_tokens_by_ttl)
    assert_equal 1_000_000, row.cache_write_tokens
    # 100 input at $4, a million written for an hour at $8, 10 output at $20.
    assert_equal 400 + 8_000_000 + 200, row.cost_micros
  end

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

  # An hour's cache write costs twice the input price on Anthropic, where five minutes' costs the registry's write price.
  test "cache writes are priced by how long they last" do
    hour = FirefightAi.cost_micros("claude-opus-5-5", provider: "anthropic", input: 1_000_000, output: 0, cache_write: 1_000_000,
                                                     cache_write_by_ttl: { "1h" => 1_000_000 })
    assert_equal 8_000_000, hour, "a million tokens written for an hour at twice the $4 input price"

    mixed = FirefightAi.cost_micros("claude-opus-5-5", provider: "anthropic", input: 1_000_000, output: 0, cache_write: 1_000_000,
                                                      cache_write_by_ttl: { "1h" => 600_000 })
    assert_equal 4_800_000 + 2_000_000, mixed, "600k for an hour at $8 and the other 400k at the $5 write price"

    assert_equal 5_000_000, FirefightAi.cost_micros("claude-opus-5-5", provider: "anthropic", input: 1_000_000, output: 0, cache_write: 1_000_000, cache_write_by_ttl: {}),
                 "no split prices every write at the registry's write price, as before"
  end

  # The price a code fix's budget is charged and the ledger keeps, for a call on DeepSeek's own API.
  test "a DeepSeek call costs twice as much at peak hours as off-peak" do
    off_peak = FirefightAi.cost_micros("deepseek-flash", provider: "deepseek", input: 1_000_000, output: 1_000_000, cache_read: 500_000,
                                                         at: Time.utc(2026, 10, 20, 12, 0))
    peak = FirefightAi.cost_micros("deepseek-flash", provider: "deepseek", input: 1_000_000, output: 1_000_000, cache_read: 500_000,
                                                     at: Time.utc(2026, 10, 20, 7, 0))

    # 500k plain input at $0.15, 500k cache reads at $0.003, a million output at $0.60.
    assert_equal 75_000 + 1_500 + 600_000, off_peak
    assert_equal 2 * off_peak, peak

    travel_to(Time.utc(2026, 10, 20, 7, 0)) do
      assert_equal peak, FirefightAi.cost_micros("deepseek-flash", provider: "deepseek", input: 1_000_000, output: 1_000_000, cache_read: 500_000),
                   "priced at the hour it is asked, when no time is given"
    end
  end
end
