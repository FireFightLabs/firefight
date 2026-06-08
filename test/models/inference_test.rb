require "test_helper"

class InferenceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @context = {
      workspace: @workspace,
      feature: "catchup",
      provider: "anthropic",
      model: "claude-haiku-4-5",
      inferable: @incident,
      member: @member
    }
  end

  test "track records a row with all dimensions on success" do
    response = stub_response(
      input_tokens: 1200, output_tokens: 300,
      cache_read_tokens: 800, cache_write_tokens: 0,
      cost: 0.0045, stop_reason: "end_turn", id: "msg_01ABC"
    )

    inference = nil
    returned_response = nil
    assert_difference "Inference.count", 1 do
      returned_response, inference = Inference.track(@context) { response }
    end
    assert_equal response, returned_response

    assert_equal @workspace, inference.workspace
    assert_equal @incident, inference.inferable
    assert_equal @member, inference.member
    assert_equal "catchup", inference.feature
    assert_equal "anthropic", inference.provider
    assert_equal "claude-haiku-4-5", inference.model
    assert_equal 1200, inference.input_tokens
    assert_equal 300, inference.output_tokens
    assert_equal 800, inference.cache_read_tokens
    assert_equal 0, inference.cache_write_tokens
    assert_equal 4500, inference.cost_micros  # 0.0045 dollars -> 4500 micros
    assert_equal "end_turn", inference.stop_reason
    assert_equal "msg_01ABC", inference.provider_request_id
    assert_equal Inference::STATUS_SUCCESS, inference.status
    assert_nil inference.error_class
    assert inference.latency_ms >= 0
  end

  test "track stores cost as integer micros (millionths of a dollar)" do
    response = stub_response(cost: 1.235)
    Inference.track(@context) { response }
    assert_equal 1_235_000, Inference.order(:created_at).last.cost_micros
  end

  test "track records error and re-raises when block raises" do
    error_class = Class.new(StandardError) do
      def self.name = "BoomError"
    end

    assert_difference "Inference.count", 1 do
      assert_raises(error_class) do
        Inference.track(@context) { raise error_class, "kaboom" }
      end
    end

    inference = Inference.order(:created_at).last
    assert_equal Inference::STATUS_ERROR, inference.status
    assert_equal "BoomError", inference.error_class
    assert_equal 0, inference.input_tokens
    assert_equal 0, inference.cost_micros
  end

  test "track works without inferable, member, or api_key" do
    minimal = @context.except(:inferable, :member)
    Inference.track(minimal) { stub_response }

    inference = Inference.order(:created_at).last
    assert_nil inference.inferable
    assert_nil inference.member
    assert_nil inference.api_key
  end

  test "track ignores unknown context keys" do
    bad = @context.merge(garbage: "ignored", another: 42)
    assert_nothing_raised { Inference.track(bad) { stub_response } }
  end

  private

  def stub_response(input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0,
                    cost: 0.0, stop_reason: nil, id: nil)
    OpenStruct.new(
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_read_tokens: cache_read_tokens,
      cache_write_tokens: cache_write_tokens,
      cost: cost,
      stop_reason: stop_reason,
      id: id
    )
  end
end
