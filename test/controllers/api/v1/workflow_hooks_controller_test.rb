require "test_helper"

class Api::V1::WorkflowHooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Deploy hook", created_by: @alice)
    draft = @workflow.open_draft!(by: @alice)
    step = { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => FirefightTools::SEARCH_INCIDENTS, "arguments" => { "query" => "{{trigger.body.service}}" } } }
    draft.update!(trigger: { "kind" => Workflow::Trigger::KIND_INBOUND_WEBHOOK, "inputs" => [],
                             "conditions" => [ { "field" => "body.service", "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => [ "web", "api" ] } ] },
                  steps: [ step ], edges: [])
    assert WorkflowPublishService.new(@workflow).publish!(draft.reload, by: @alice).ok
    @workflow.reload
  end

  def signed(body, secret: @workflow.hook_secret, at: Time.current)
    timestamp = at.utc.iso8601
    { "X-Firefight-Timestamp" => timestamp, "X-Firefight-Signature" => "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v1:#{timestamp}:#{body}")}",
      "Content-Type" => "application/json" }
  end

  def deliver(body, headers: signed(body), token: @workflow.hook_token)
    post api_v1_workflow_hook_path(token), params: body, headers: headers
  end

  test "a signed delivery starts a run with what it was sent, once per delivery id" do
    body = { service: "web", version: "1.2.3" }.to_json

    deliver(body, headers: signed(body).merge("X-Firefight-Delivery" => "d-1"))
    assert_response :accepted
    run = @workflow.runs.sole
    assert_equal run.id, response.parsed_body["run_id"]
    assert_equal({ "service" => "web", "version" => "1.2.3" }, run.trigger_payload["body"])
    assert_equal Workflow::Run::STARTED_BY_TRIGGER, run.started_by_kind

    deliver(body, headers: signed(body).merge("X-Firefight-Delivery" => "d-1"))
    assert_response :accepted
    assert_equal 1, @workflow.runs.count
  end

  test "a delivery its conditions do not meet starts nothing and says so" do
    body = { service: "batch" }.to_json

    deliver(body)

    assert_response :ok
    assert_equal false, response.parsed_body["started"]
    assert_empty @workflow.runs
  end

  test "a delivery signed wrongly, too long ago or not as an object is refused" do
    body = { service: "web" }.to_json
    deliver(body, headers: signed(body, secret: "guess"))
    assert_response :unauthorized
    deliver(body, headers: signed(body, at: 10.minutes.ago))
    assert_response :unauthorized
    deliver("[1]", headers: signed("[1]"))
    assert_response :unprocessable_content
    deliver("not json", headers: signed("not json"))
    assert_response :bad_request
    assert_empty @workflow.runs
  end

  test "a start past its most runs an hour says why and is counted as skipped on the workflow" do
    @workflow.update!(runs_per_hour: 1)
    deliver({ service: "web" }.to_json)
    deliver({ service: "api" }.to_json)

    assert_response :conflict
    assert_match "as many as it allows", response.parsed_body["error"]
    assert_equal 1, @workflow.recent_skips.sole.count
    assert_nil @workflow.reload.trigger_refusal
  end

  test "a new address retires the old one and its secret" do
    old_token = @workflow.hook_token
    old_secret = @workflow.hook_secret
    @workflow.replace_hook!
    body = { service: "web" }.to_json

    deliver(body, token: old_token, headers: signed(body, secret: old_secret))
    assert_response :not_found
    deliver(body, headers: signed(body, secret: old_secret))
    assert_response :unauthorized
    deliver(body, token: @workflow.reload.hook_token)
    assert_response :accepted
  end

  test "an address that starts nothing answers not found" do
    body = { service: "web" }.to_json
    deliver(body, token: "nothing-here")
    assert_response :not_found

    @workflow.update!(enabled: false)
    deliver(body)
    assert_response :not_found
  end
end
