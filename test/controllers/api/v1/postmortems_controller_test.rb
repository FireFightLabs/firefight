require "test_helper"

class Api::V1::PostmortemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @key = api_keys(:full_access_key)

    stub_post_message
    stub_update_message
    stub_set_channel_topic
  end

  test "an incident still open has nothing to write up" do
    post api_v1_incident_postmortem_url(@incident), headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_match(/still open/, json_response.dig("error", "message"))
    assert_nil @incident.reload.postmortem
  end

  test "starting one records the key as its author" do
    resolve!

    post api_v1_incident_postmortem_url(@incident), headers: api_headers, as: :json

    assert_response :created
    assert_equal @key, @incident.reload.postmortem.generated_by
    assert_equal Postmortem::STATUS_DRAFT, json_response["status"]
    assert_equal @key.name, json_response.dig("written_by", "name")
  end

  test "the body is written, sanitised, and read back" do
    resolve!
    post api_v1_incident_postmortem_url(@incident), headers: api_headers, as: :json

    patch api_v1_incident_postmortem_url(@incident),
          params: { html: "<p>The pooler ran out.</p><script>alert('no')</script>" },
          headers: api_headers, as: :json

    assert_response :success
    get api_v1_incident_postmortem_url(@incident), headers: api_headers
    assert_includes json_response["html"], "The pooler ran out"
    assert_not_includes json_response["html"], "<script>"
  end

  test "moving it along records where it now sits" do
    resolve!
    post api_v1_incident_postmortem_url(@incident), headers: api_headers, as: :json

    patch api_v1_incident_postmortem_url(@incident),
          params: { status: Postmortem::STATUS_IN_REVIEW }, headers: api_headers, as: :json

    assert_response :success
    assert_equal Postmortem::STATUS_IN_REVIEW, @incident.reload.postmortem.status
  end

  test "an incident with no postmortem is a not found, not an empty one" do
    resolve!

    get api_v1_incident_postmortem_url(@incident), headers: api_headers

    assert_response :not_found
  end

  test "a read-only key cannot start one" do
    resolve!

    post api_v1_incident_postmortem_url(@incident),
         headers: api_headers(token: "ff_test_read_only_token_12345678"), as: :json

    assert_response :forbidden
    assert_nil @incident.reload.postmortem
  end

  private

  def resolve!
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )
  end
end
